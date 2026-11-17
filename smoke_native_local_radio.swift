// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit
import AVFoundation

private enum CheckError:Error {case failed(String)}
private var checks=0
private func check(_ value:Bool,_ name:String)throws{checks+=1;if !value{throw CheckError.failed(name)}}
private func wait(_ condition:()->Bool)throws {
    let timer=Timer(timeInterval:0.01,repeats:true){_ in};RunLoop.current.add(timer,forMode:.default);defer{timer.invalidate()}
    let end=Date().addingTimeInterval(30)
    while !condition(),Date()<end{_ = RunLoop.current.run(mode:.default,before:Date().addingTimeInterval(0.005))}
    try check(condition(),"bounded callback")
}
private func receipt(_ store:NativeRawResourceStore)throws->NativeRawResourceStore.ReceiptDescriptor {
    var result:Result<NativeRawResourceStore.ReceiptDescriptor,Error>?
    store.readReceiptDescriptor{result=$0};try wait{result != nil};return try result!.get()
}
private func load(_ source:NativeLocalRadioProvider)throws->NativeLocalRadioProvider.Availability {
    var result:Result<NativeLocalRadioProvider.Availability,Error>?
    source.loadCatalogue{result=$0};try wait{result != nil};return try result!.get()
}
private func read(_ source:NativeLocalRadioProvider,_ id:Int,_ offset:Int,_ count:Int)throws->NativeRadioPCMWindow {
    var result:Result<NativeRadioPCMWindow,Error>?
    source.read(id:id,offset:offset,frames:count){result=$0};try wait{result != nil};return try result!.get()
}
private func statistics(_ source:NativeLocalRadioProvider)throws->NativeLocalRadioProvider.Statistics {
    var result:NativeLocalRadioProvider.Statistics?
    source.statistics{result=$0};try wait{result != nil};return result!
}
private func extract(_ store:NativeRawResourceStore,_ file:URL)throws {
    var result:Result<NativeRawResourceStore.Snapshot,Error>?
    store.extractISO(file,progress:{_ in}){result=$0};try wait{result != nil};_ = try result!.get()
}
private func authoredExtractor(_ fixture:URL)->NativeRawResourceStore.Extractor {
    .init(identity:"authored-local-radio-integration-v1"){source,token in
        let tag=try Data(contentsOf:source).first!
        let folder=fixture.appendingPathComponent(tag==65 ? "A":"B")
        let paths=try JSONDecoder().decode([String].self,from:Data(contentsOf:fixture.appendingPathComponent("paths.json")))
        let entries=try paths.enumerated().map{offset,path in NativeISOExtraction.Entry(index:offset,path:path,group:"audio",bytes:UInt64(try Data(contentsOf:folder.appendingPathComponent(path)).count),source:.cabinet)}
        return .init(members:entries,extract:{stage,progress in
            try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:false)
            for entry in entries {
                if token.isCancelled{throw NativeISOExtraction.Failure.cancelled}
                let target=stage.appendingPathComponent(entry.path)
                try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                try Data(contentsOf:folder.appendingPathComponent(entry.path)).write(to:target)
                progress(.init(path:entry.path,completedBytes:UInt64(entry.index+1),totalBytes:UInt64(entries.count),completedFiles:UInt32(entry.index+1),totalFiles:UInt32(entries.count)))
            }
        })
    }
}
private func provider(_ fixture:URL,_ output:URL)throws {
    let store=NativeRawResourceStore(root:output.appendingPathComponent("raw"),extractor:authoredExtractor(fixture))
    let a=output.appendingPathComponent("source-A.iso"),b=output.appendingPathComponent("source-B.iso")
    try Data([65]).write(to:a);try Data([66]).write(to:b);try extract(store,a)
    let index=try receipt(store)
    let corrupt=index.resourcesByCasefoldedPath["audio/streams/co"]!
    let path=store.root.appendingPathComponent("generations/\(index.generationID)/files/\(corrupt.path)")
    try Data(repeating:0,count:Int(corrupt.bytes)).write(to:path)
    let source=NativeLocalRadioProvider(storeFactory:{store})
    guard case .available(let stations)=try load(source)else{throw CheckError.failed("local catalogue")}
    try check(stations==[0,1,2],"AA/CH/CO station identities from receipt/table, not generated HTTP index")
    let cold=try statistics(source)
    try check(cold.packs==0 && cold.decoders==0 && cold.preparations==0 && !cold.workerIsMain,"catalogue does not hash/decode packs or use main worker")
    try check(source.contains(0)&&source.contains(1)&&source.contains(2)&&source.contains(3),"original numeric IDs retained")
    let reference=try JSONSerialization.jsonObject(with:Data(contentsOf:fixture.appendingPathComponent("references.json")))as! [String:[String:[Double]]]
    let format=AVAudioFormat(standardFormatWithSampleRate:32000,channels:2)!
    for offset in [0,1,15,255,7000,7999,8000,15996,16000,17000] {
        let value=try read(source,1,offset,8000)
        try check(value.rate==32000 && value.requestedFrames==8000 && value.decodedFrames==min(8000,max(0,16000-offset)),"actual C window/EOF bound")
        for (at,expected) in reference["stereo"]! {
            let sample=Int(at)!-offset
            if sample>=0 && sample<value.decodedFrames {
                try check(abs(Double(value.samples[sample*2])-expected[0])<0.000005 && abs(Double(value.samples[sample*2+1])-expected[1])<0.000005,"independently decoded mathematical PCM")
            }
        }
        let buffer=try NativeRadioPlayback.buffer(window:value,format:format)
        try check(buffer.frameLength==8000,"program requested sample count survives shorter recording")
        for frame in value.decodedFrames..<8000 {
            try check(buffer.floatChannelData![0][frame]==0 && buffer.floatChannelData![1][frame]==0,"intentional silence padding")
        }
    }
    let warm=try statistics(source)
    try check(warm.preparations==1 && warm.packs==1 && warm.decoders==1,"late/seek windows reuse the prepared C decoder")
    _ = try read(source,0,0,8000);_ = try read(source,2,0,8000)
    let bounded=try statistics(source)
    try check(bounded.packs<=2 && bounded.decoders<=2,"pack/decoder LRU bounds")
    var rejected=false
    do{_ = try read(source,3,0,1)}catch{rejected=true}
    try check(rejected,"present corrupt raw pack is lazily rejected, not downloaded")
    // Metadata creation did not scan/hash the corrupt CO pack above.
    _ = try load(source)
    let beforeCancel=try read(source,1,0,100)
    try check(beforeCancel.samples[0] != beforeCancel.samples[1],"A source uses mathematical stereo")
    var cancelledCallbacks=0
    source.read(id:1,offset:1,frames:8000){_ in cancelledCallbacks+=1};source.cancel()
    _ = try statistics(source)
    let until=Date().addingTimeInterval(0.05)
    while Date()<until{RunLoop.current.run(until:Date().addingTimeInterval(0.005))}
    try check(cancelledCallbacks==0,"cancel suppresses already queued old window callbacks")
    let closed=try statistics(source)
    try check(closed.packs==0 && closed.decoders==0,"cancel serially destroys C and releases generation descriptors")
    _ = try load(source);_ = try read(source,1,0,100)
    try extract(store,b)
    let next=try receipt(store)
    try check(next.generationID != index.generationID && next.sourceID != index.sourceID,"actual Store source generation replacement")
    // Existing verified lease is immutable/pinned until session refresh.
    let old=try read(source,1,0,100)
    try check(old.samples[0] != old.samples[1],"old immutable descriptor stays safe until playback closes it")
    _ = try load(source)
    let refreshed=try statistics(source)
    try check(refreshed.packs==0 && refreshed.decoders==0,"session re-admits receipt and closes old generation")
    let mono=try read(source,1,0,8000)
    for i in 0..<mono.decodedFrames{try check(mono.samples[i*2]==mono.samples[i*2+1],"new generation mono duplicated by actual C")}
    var first:Result<NativeRadioPCMWindow,Error>?,second:Result<NativeRadioPCMWindow,Error>?
    source.read(id:1,offset:0,frames:100){first=$0}
    source.read(id:1,offset:0,frames:100){second=$0}
    try wait{first != nil && second != nil}
    _ = try first!.get()
    if case .failure(NativeLocalRadioProvider.Failure.busy)=second!{}else{throw CheckError.failed("single pending admission")}
    for (offset,count) in [(-1,1),(0,0),(0,8001)] {
        var rejected=false;do{_ = try read(source,1,offset,count)}catch{rejected=true}
        try check(rejected,"invalid bounded read rejected before allocation")
    }
    let changed=next.resourcesByCasefoldedPath["audio/streams/ch"]!
    try Data(repeating:0,count:Int(changed.bytes)).write(to:store.root.appendingPathComponent("generations/\(next.generationID)/files/\(changed.path)"))
    var poisoned=false;do{_ = try read(source,1,0,100)}catch{poisoned=true}
    try check(poisoned,"cached descriptor rejects post-admission mutation")
    let invalid=try statistics(source)
    try check(invalid.decoders==0,"failed descriptor cannot retain poisoned C cache")
    source.cancel();_ = try statistics(source)
    let empty=NativeLocalRadioProvider(storeFactory:{NativeRawResourceStore(root:output.appendingPathComponent("empty"),extractor:authoredExtractor(fixture))})
    if case .absent=try load(empty){}else{throw CheckError.failed("absent source may use development fallback")}
    empty.cancel()
}

private final class BufferSink {
    var buffers:[AVAudioPCMBuffer]=[]
    func scheduleBuffer(_ value:AVAudioPCMBuffer){buffers.append(value)}
}
private final class CompletionCarrier {
    private struct Pending {let ticket:UUID,generation:Int,scheduled:Int,id:Int,offset:Int,frames:Int}
    let program:NativeRadioProgram
    let node=BufferSink()
    var cursor:NativeRadioProgram.Cursor?
    var offset=100,scheduled=0,started=0.0,generation=1,fadeFrames=0,pumps=0,failures=0
    private var pending:Pending?
    private var failed=Set<Int>()
    private var onFailure:(()->Void)?
    init(_ program:NativeRadioProgram){self.program=program;onFailure={[weak self]in self?.failures+=1};seed()}
    func seed(){cursor = .init(station:1,day:0,index:0,piece:.init(id:1,kind:"song",song:0,at:0,plays:20000),into:100)}
    func pump(){pumps+=1}
    // ACTUAL_ADVANCE
    // ACTUAL_FINISH
    func test()throws {
        let format=AVAudioFormat(standardFormatWithSampleRate:32000,channels:2)!
        let data=(0..<8000).flatMap{[Float($0),-Float($0)]}
        let buffer=try NativeRadioPlayback.buffer(window:.init(rate:32000,requestedFrames:8000,decodedFrames:8000,samples:data),format:format)
        let read=Pending(ticket:UUID(),generation:1,scheduled:0,id:1,offset:100,frames:8000);pending=read
        started=ProcessInfo.processInfo.systemUptime-0.05
        finish(read,buffer:.success(buffer),fadeEligible:true)
        try check(node.buffers.count==1 && scheduled==8000 && offset==8100,"actual completion catches up without replay/starvation")
        let actual=node.buffers[0],skipped=8000-Int(actual.frameLength)
        try check(skipped>0 && skipped<8000 && actual.floatChannelData![0][0]==Float(skipped),"actual AV buffer drops only elapsed prefix")
        let other=Pending(ticket:UUID(),generation:2,scheduled:0,id:1,offset:100,frames:8000)
        generation=2;pending=other
        finish(read,buffer:.success(buffer),fadeEligible:true)
        try check(node.buffers.count==1 && pending?.ticket==other.ticket,"stale completion cannot schedule or clear new pending window")
        generation=1;pending=read;offset=100;scheduled=0;seed();started=ProcessInfo.processInfo.systemUptime-0.5
        finish(read,buffer:.failure(NativeLocalRadioProvider.Failure.codec(7)),fadeEligible:true)
        try check(failed.contains(1)&&failures==1,"obsolete failed asset cannot trigger endless prepare retries")
    }
}

private final class LocalRoutingSource:NativeRadioWindowSource {
    var completion:((Result<NativeLocalRadioProvider.Availability,Error>)->Void)?
    var loads=0,cancels=0
    func loadCatalogue(completion:@escaping(Result<NativeLocalRadioProvider.Availability,Error>)->Void){loads+=1;self.completion=completion}
    func cancel(){cancels+=1}
    func contains(_ id:Int)->Bool{false}
    func read(id:Int,offset:Int,frames:Int,completion:@escaping(Result<NativeRadioPCMWindow,Error>)->Void){completion(.failure(NativeLocalRadioProvider.Failure.unavailable))}
}
private final class RoutingCarrier {
    let local=LocalRoutingSource()
    var generation=0,stationID=1,stationName="AUTHORED",wantsPlayback=true,interrupted=false
    let program:NativeRadioProgram?
    var started:[Int]=[],fallbacks=0,status:[String]=[]
    var onStatus:((String)->Void)?
    init(_ program:NativeRadioProgram){self.program=program;onStatus={[weak self]in self?.status.append($0)}}
    func releasePlayback(){generation+=1;local.cancel()}
    func startPCM(program:NativeRadioProgram,local:NativeRadioWindowSource?){started.append(stationID)}
    func tuneFallback(token:Int){if token==generation{fallbacks+=1}}
    // ACTUAL_TUNE
    static func test(_ program:NativeRadioProgram)throws {
        let missingIndex=RoutingCarrier(program);missingIndex.tune();missingIndex.local.completion?(.success(.available(stations:[1])))
        try check(missingIndex.started==[1] && missingIndex.fallbacks==0,"actual tune selects local PCM without HTTP index")
        let emergency=RoutingCarrier(program);emergency.stationID=0;emergency.tune();emergency.local.completion?(.success(.available(stations:[0])))
        try check(emergency.started==[0],"actual emergency AA station0 reaches local provider")
        let off=RoutingCarrier(program);off.stationID=13;off.tune()
        try check(off.started.isEmpty && off.local.loads==0 && off.fallbacks==0,"actual station13 stays off")
        let absent=RoutingCarrier(program);absent.tune();absent.local.completion?(.success(.absent))
        try check(absent.fallbacks==1,"development fallback remains available when local raw audio is absent")
        let bad=RoutingCarrier(program);bad.tune();bad.local.completion?(.failure(NativeLocalRadioProvider.Failure.invalidCatalogue))
        try check(bad.started.isEmpty && bad.fallbacks==0,"present failing local resources cannot silently select HTTP fallback")
        let stale=RoutingCarrier(program);stale.tune();let old=stale.local.completion;stale.generation+=1;stale.stationID=2;old?(.success(.available(stations:[1])))
        try check(stale.started.isEmpty && stale.fallbacks==0,"retune suppresses obsolete catalogue completion")
        let paused=RoutingCarrier(program);paused.interrupted=true;paused.tune()
        try check(paused.local.loads==0 && paused.started.isEmpty,"interrupted radio does not start catalogue/playback")
        paused.interrupted=false;paused.tune();paused.local.completion?(.success(.available(stations:[1])))
        try check(paused.started==[1],"resume re-admits the station")
        let exited=RoutingCarrier(program);exited.tune();exited.wantsPlayback=false;exited.local.completion?(.success(.available(stations:[1])))
        try check(exited.started.isEmpty,"vehicle exit suppresses pending station start")
    }
}

private final class SelectionCarrier {
    private struct Station {let name:String,file:String}
    private let stations=(0..<12).map{Station(name:"AUTHORED",file:"TEST\($0)")}
    let program:NativeRadioProgram?
    var vehicleModel:Int?,following=false,vehicleType=0,specialStation:Int?,index=0,wantsPlayback=true,interrupted=false
    var remembered:(station:Int,at:Double)?
    var generation=1,tracks:[Int:URL]=[:],songs=["authored custom"],started:[Int]=[],userStarts=0,customStarts=0
    var stationID:Int{specialStation ?? (index<0 ? 13:index+1)}
    init(_ program:NativeRadioProgram){self.program=program}
    func resume(){wantsPlayback=index>=0}
    func tune(){started.append(stationID)}
    func startPCM(program:NativeRadioProgram,local:NativeRadioWindowSource?){started.append(stationID)}
    func playUserSong(token:Int){userStarts+=1}
    private func tryFormat(station:Station,formats:[String],token:Int){customStarts+=1}
    var onStatus:((String)->Void)?
    // ACTUAL_ENTER
    // ACTUAL_FALLBACK
    static func test(_ program:NativeRadioProgram)throws {
        let original=SelectionCarrier(program);original.enter(model:9001)
        try check(original.stationID==1 && original.started==[1],"custom-only HTTP index cannot bypass local station discovery")
        let emergency=SelectionCarrier(program);emergency.enter(model:9002)
        try check(emergency.stationID==0 && emergency.started==[0],"emergency local AA survives custom-only HTTP index")
        let fallback=SelectionCarrier(program);fallback.tuneFallback(token:1)
        try check(fallback.stationID==12 && fallback.userStarts==1,"genuine local absence retains custom user-track fallback")
        let remote=SelectionCarrier(program);remote.tracks[1]=URL(string:"https://invalid.invalid/authored")!;remote.tuneFallback(token:1)
        try check(remote.started==[1] && remote.userStarts==0,"remote PCM station remains valid fallback")
        let stale=SelectionCarrier(program);stale.tuneFallback(token:0)
        try check(stale.started.isEmpty && stale.userStarts==0 && stale.customStarts==0,"fallback cannot cross generation")
    }
}

private final class RequestCarrier {
    let lock=NSLock()
    var epoch:UInt64=0
    var requests:[UUID:NativeRawResourceLease.Request]=[:]
    var reservedRequests=Set<UUID>()
    // ACTUAL_RESERVE
    // ACTUAL_TRACK
    // ACTUAL_UNTRACK
    static func test()throws {
        let owner=RequestCarrier(),early=UUID(),earlyRequest=NativeRawResourceLease.Request()
        try check(owner.reserveRequest(early,token:0),"actual reservation precedes Store call")
        var delivered=false
        earlyRequest.deliverValue(Result<Int,Error>.success(1),fence:{}){_ in owner.untrack(early);delivered=true}
        try wait{delivered}
        owner.track(earlyRequest,id:early,token:0)
        try check(owner.requests.isEmpty && owner.reservedRequests.isEmpty && !earlyRequest.isCancelled,"actual completion-before-return cannot reinsert delivered Request")
        let normal=UUID(),normalRequest=NativeRawResourceLease.Request()
        try check(owner.reserveRequest(normal,token:0),"normal request reservation")
        owner.track(normalRequest,id:normal,token:0)
        try check(owner.requests[normal]===normalRequest && owner.reservedRequests.isEmpty,"returned live Request remains cancellable")
        delivered=false
        normalRequest.deliverValue(Result<Int,Error>.success(1),fence:{}){_ in owner.untrack(normal);delivered=true}
        try wait{delivered}
        try check(owner.requests.isEmpty && owner.reservedRequests.isEmpty,"normal delivered Request removed")
        let stale=UUID(),staleRequest=NativeRawResourceLease.Request()
        _ = owner.reserveRequest(stale,token:0)
        owner.epoch=1;owner.reservedRequests.removeAll()
        owner.track(staleRequest,id:stale,token:0)
        try check(owner.requests.isEmpty && staleRequest.isCancelled,"cancellation between reserve and return cancels late Request")
        try check(!owner.reserveRequest(UUID(),token:0),"stale owner cannot start new Store work")
        let forgotten=UUID(),forgottenRequest=NativeRawResourceLease.Request()
        owner.track(forgottenRequest,id:forgotten,token:1)
        try check(owner.requests.isEmpty && forgottenRequest.isCancelled,"unreserved Request fails closed")
    }
}

@main private enum LocalRadioSmoke {
    static func main()throws {
        let fixture=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        try provider(fixture,output)
        let document=try Data(contentsOf:fixture.appendingPathComponent("program.json")),program=try NativeRadioProgram(data:document)
        try CompletionCarrier(program).test()
        try RoutingCarrier.test(program)
        try SelectionCarrier.test(program)
        try RequestCarrier.test()
        for frames in [1,2,512,8000] {
            for skip in [0,1,frames-1,frames,frames+1] {
                let actual=NativeRadioWindowReconciliation.remaining(planned:100,scheduled:100+skip,readID:1,currentID:1,readOffset:20,currentOffset:20+skip,frames:frames)
                try check(actual==(skip<frames ? skip..<frames:nil),"bounded elapsed-prefix matrix")
            }
        }
        try check(NativeRadioWindowReconciliation.remaining(planned:100,scheduled:200,readID:1,currentID:2,readOffset:0,currentOffset:100,frames:8000)==nil,"piece transition discards obsolete window")
        try check(NativeRadioWindowReconciliation.remaining(planned:100,scheduled:8100,readID:1,currentID:1,readOffset:0,currentOffset:8000,frames:8000)==nil,"completely elapsed window is not replayed")
        let report:[String:Any]=["status":"PASS","checks":checks,"audioOutputStarted":false,"originalDataUsed":false]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("report.json"))
        print("LOCAL_RADIO_PASS \(checks) actual provider/PCM/lease checks; no audio device")
    }
}
