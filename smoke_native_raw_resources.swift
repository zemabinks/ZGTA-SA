import Foundation
import CryptoKit

private var checks=0
private func check(_ condition:Bool,_ message:String){checks+=1;precondition(condition,message)}
private func wait(_ condition:()->Bool){let end=Date().addingTimeInterval(180);while !condition() && Date()<end{RunLoop.main.run(until:Date().addingTimeInterval(0.002))};check(condition(),"Asynchronous raw operation timed out")}
private func sha(_ data:Data)->String{SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
private enum FixtureError:Error{case failed}
private final class Counter {
    let lock=NSLock();private var count=0
    func increment(){lock.lock();count+=1;lock.unlock()}
    var value:Int{lock.lock();defer{lock.unlock()};return count}
}
private func fixtureExtractor(_ counter:Counter,fail:Bool=false,duplicate:Bool=false,slow:Bool=false)->NativeRawResourceStore.Extractor{
    .init(identity:"authored-raw-fixture-v1"){_,token in
        counter.increment()
        let paths=duplicate ? ["audio/STREAMS/AUTHORED","AUDIO/streams/authored"]:["anim/authored.ifp","data/authored.dat","audio/CONFIG/Authored.dat","AUDIO/STREAMS/AUTHORED"]
        let members=paths.enumerated().map{NativeISOExtraction.Entry(index:$0.offset,path:$0.element,group:$0.element.components(separatedBy:"/")[0],bytes:UInt64(Data($0.element.utf8).count),source:.cabinet)}
        return .init(members:members,extract:{stage,update in
            try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:false)
            for (index,item) in members.enumerated(){
                if token.isCancelled{throw NativeISOExtraction.Failure.cancelled}
                let target=stage.appendingPathComponent(item.path)
                try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                try Data(item.path.utf8).write(to:target)
                update(.init(path:item.path,completedBytes:UInt64(index+1),totalBytes:UInt64(members.count),completedFiles:UInt32(index+1),totalFiles:UInt32(members.count)))
                if fail{throw FixtureError.failed}
                if slow{for _ in 0..<200{if token.isCancelled{throw NativeISOExtraction.Failure.cancelled};Thread.sleep(forTimeInterval:0.002)}}
            }
        })
    }
}
private func extract(_ store:NativeRawResourceStore,_ source:URL)->Result<NativeRawResourceStore.Snapshot,Error>{
    var result:Result<NativeRawResourceStore.Snapshot,Error>?
    _=store.extractISO(source,progress:{_ in}){result=$0};wait{result != nil};return result!
}
private func active(_ root:URL)throws->(String,URL,NativeRawResourceStore.Receipt){
    let json=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("catalogue.json"))) as! [String:Any]
    let source=json["activeSourceID"] as! String,generation=(json["sources"] as! [String:String])[source]!
    let stage=root.appendingPathComponent("generations/"+generation)
    return(generation,stage,try JSONDecoder().decode(NativeRawResourceStore.Receipt.self,from:Data(contentsOf:stage.appendingPathComponent("raw-resources.json"))))
}
private final class PreparedService:NativeGameFilesService{
    let snapshot=NativeResourceStore.Snapshot(mode:.development,installedContentID:nil,installedFiles:0,installedBytes:0,cachedFiles:0,cachedBytes:0,hasPlayableInstallation:false,developmentOrigin:nil,issues:[])
    var modeCalls=0
    func observe(_ update:@escaping(NativeResourceStore.Snapshot)->Void)->UUID{update(snapshot);return UUID()}
    func removeObserver(_ id:UUID){}
    func importFolder(_ folder:URL,progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->()->Void{{}}
    func verify(progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->()->Void{{}}
    func cache(origin:URL,progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->()->Void{{}}
    func setMode(_ mode:NativeResourceStore.Mode)throws{modeCalls+=1}
}
private final class RawService:NativeGameFilesRawService{
    struct Job{let progress:(NativeResourceStore.Progress)->Void,completion:(Result<NativeRawResourceStore.Snapshot,Error>)->Void;var cancels=0}
    var snapshot=NativeRawResourceStore.Snapshot.empty,jobs:[Job]=[]
    func begin(_ progress:@escaping(NativeResourceStore.Progress)->Void,_ completion:@escaping(Result<NativeRawResourceStore.Snapshot,Error>)->Void)->()->Void{
        let index=jobs.count;jobs.append(.init(progress:progress,completion:completion));return{self.jobs[index].cancels+=1}
    }
    func extractISO(_ source:URL,progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeRawResourceStore.Snapshot,Error>)->Void)->()->Void{begin(progress,completion)}
    func verifyRaw(progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeRawResourceStore.Snapshot,Error>)->Void)->()->Void{begin(progress,completion)}
}
@main struct RawResourceSmoke{
    static func main()throws{
        let folder=URL(fileURLWithPath:CommandLine.arguments[1]),source=folder.appendingPathComponent("authored.iso"),other=folder.appendingPathComponent("other.iso")
        try Data("authored source identity, not an original game ISO".utf8).write(to:source);try Data("different authored source".utf8).write(to:other)
        let root=folder.appendingPathComponent("raw-store"),count=Counter(),factory=fixtureExtractor(count)
        let store=NativeRawResourceStore(root:root,extractor:factory)
        let initial=extract(store,source)
        if case .failure(let error)=initial{throw error}
        guard case .success(let first)=initial else{preconditionFailure("Initial raw extraction failed")}
        check(first.files==4 && first.verified,"Raw receipt did not reflect checked output")
        let lockPermissions=try FileManager.default.attributesOfItem(atPath:root.appendingPathComponent("operation.lock").path)[.posixPermissions] as! NSNumber
        check(lockPermissions.intValue&0o777==0o600,"Raw lock mode must be Swift octal0600; decimal0600 prevents subsequent operations")
        check(first.sourceID==sha(try Data(contentsOf:source)),"Source identity is not the full streamed source hash")
        let original=try active(root),originalCatalogue=try Data(contentsOf:root.appendingPathComponent("catalogue.json"))
        let index=try original.2.casefoldIndex()
        check(index["audio/config/authored.dat"]?.path=="audio/CONFIG/Authored.dat","Case-insensitive complete-path index lost original spelling")
        check(original.2.resources.map(\.path).contains("AUDIO/STREAMS/AUTHORED") && original.2.resources.map(\.path).contains("audio/CONFIG/Authored.dat"),"Windows spelling or nested identities were changed")
        check(!String(data:try JSONEncoder().encode(original.2),encoding:.utf8)!.contains("buildNumber"),"Raw identity was tied to the App build")
        let reopened=NativeRawResourceStore(root:root,extractor:factory)
        check(reopened.snapshot.sourceID==first.sourceID && reopened.snapshot.files==4 && !reopened.snapshot.verified,"Restart lost raw data or claimed an unperformed fresh hash scan")
        check(count.value==1,"Opening a saved store re-extracted source data")
        _=try extract(reopened,source).get()
        let reused=try active(root)
        check(count.value==1 && reused.0==original.0,"Selecting an unchanged source re-extracted or duplicated its raw stage")
        var verified:Result<NativeRawResourceStore.Snapshot,Error>?
        _=reopened.verifyRaw(progress:{_ in}){verified=$0};wait{verified != nil}
        check(reopened.snapshot.verified,"Explicit raw verification failed")

        let failed=NativeRawResourceStore(root:root,extractor:fixtureExtractor(Counter(),fail:true))
        if case .success=extract(failed,other){preconditionFailure("Partial extraction was committed")};checks+=1
        check(try Data(contentsOf:root.appendingPathComponent("catalogue.json"))==originalCatalogue,"Failed replacement changed the active raw catalogue")
        check(try FileManager.default.contentsOfDirectory(atPath:root.appendingPathComponent("staging").path).isEmpty,"Failed stage leaked raw files")
        let duplicate=NativeRawResourceStore(root:root,extractor:fixtureExtractor(Counter(),duplicate:true))
        if case .success=extract(duplicate,other){preconditionFailure("Casefold duplicate was committed")};checks+=1
        check(try Data(contentsOf:root.appendingPathComponent("catalogue.json"))==originalCatalogue,"Ambiguous source replaced existing raw data")

        let slow=NativeRawResourceStore(root:root,extractor:fixtureExtractor(Counter(),slow:true))
        var cancelled:Result<NativeRawResourceStore.Snapshot,Error>?,operation:NativeRawResourceStore.Operation?,startedSlow=false
        operation=slow.extractISO(other,progress:{value in if value.phase=="Extracting original raw resources"{startedSlow=true}}){cancelled=$0}
        wait{startedSlow}
        var contended:Result<NativeRawResourceStore.Snapshot,Error>?
        _=reopened.verifyRaw(progress:{_ in}){contended=$0};wait{contended != nil}
        if case .success=contended!{preconditionFailure("Concurrent store instance bypassed the file lock")};checks+=1
        check(!(try FileManager.default.contentsOfDirectory(atPath:root.appendingPathComponent("staging").path)).isEmpty,"Contending store cleaned the live stage")
        operation?.cancel()
        wait{cancelled != nil}
        if case .success=cancelled!{preconditionFailure("Cancelled raw extraction committed")};checks+=1
        check(try Data(contentsOf:root.appendingPathComponent("catalogue.json"))==originalCatalogue,"Cancellation changed active raw resources")
        check(try FileManager.default.contentsOfDirectory(atPath:root.appendingPathComponent("staging").path).isEmpty,"Cancelled stage was not removed")

        let abandoned=root.appendingPathComponent("staging/"+UUID().uuidString+".partial"),orphan=root.appendingPathComponent("generations/"+UUID().uuidString)
        try FileManager.default.createDirectory(at:abandoned,withIntermediateDirectories:false);try FileManager.default.createDirectory(at:orphan,withIntermediateDirectories:false)
        verified=nil;_=reopened.verifyRaw(progress:{_ in}){verified=$0};wait{verified != nil}
        check(!FileManager.default.fileExists(atPath:abandoned.path) && !FileManager.default.fileExists(atPath:orphan.path),"Restart leftovers were not cleaned under the operation lock")
        let victim=original.1.appendingPathComponent("files/data/authored.dat")
        try Data(repeating:88,count:Data("data/authored.dat".utf8).count).write(to:victim)
        verified=nil;_=reopened.verifyRaw(progress:{_ in}){verified=$0};wait{verified != nil}
        check(!reopened.snapshot.verified && !reopened.snapshot.issues.isEmpty,"Corrupt raw data remained verified")
        _=try extract(reopened,source).get()
        let repaired=try active(root)
        check(count.value==2 && repaired.0 != original.0,"Repair did not replace the immutable damaged generation")
        check(!FileManager.default.fileExists(atPath:original.1.path),"Retired damaged generation was not cleaned after commit")
        check(try Data(contentsOf:source)==Data("authored source identity, not an original game ISO".utf8),"Extraction changed the original source")
        let protectedCatalogue=try Data(contentsOf:root.appendingPathComponent("catalogue.json"))
        let defaultC=NativeRawResourceStore(root:root)
        if case .success=extract(defaultC,other){preconditionFailure("Malformed ISO reached a committed raw stage")};checks+=1
        check(try Data(contentsOf:root.appendingPathComponent("catalogue.json"))==protectedCatalogue,"Actual C metadata refusal changed existing raw data")
        let outside=folder.appendingPathComponent("outside-raw"),dataDirectory=repaired.1.appendingPathComponent("files/data"),held=folder.appendingPathComponent("held-data")
        try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:false)
        try Data("outside stays unchanged".utf8).write(to:outside.appendingPathComponent("authored.dat"))
        try FileManager.default.moveItem(at:dataDirectory,to:held)
        try FileManager.default.createSymbolicLink(at:dataDirectory,withDestinationURL:outside)
        verified=nil;_=reopened.verifyRaw(progress:{_ in}){verified=$0};wait{verified != nil}
        check(!reopened.snapshot.verified,"A linked raw member directory was trusted")
        check(try Data(contentsOf:outside.appendingPathComponent("authored.dat"))==Data("outside stays unchanged".utf8),"Raw verification changed a linked outside file")
        try FileManager.default.removeItem(at:dataDirectory);try FileManager.default.moveItem(at:held,to:dataDirectory)
        verified=nil;_=reopened.verifyRaw(progress:{_ in}){verified=$0};wait{verified != nil};check(reopened.snapshot.verified,"Restored raw files failed explicit verification")

        let prepared=PreparedService(),raw=RawService();var begins=0,ends=0
        let coordinator=NativeGameFilesCoordinator(service:prepared,scope:.init(begin:{_ in begins+=1;return true},end:{_ in ends+=1}),rawService:raw)
        check(coordinator.extractRawISO(source),"Coordinator raw extraction refused")
        check(coordinator.state.busy && coordinator.state.activity?.kind == .extracting && begins==1 && ends==0,"Raw activity did not own scope/awake busy state")
        check(!coordinator.verifyInstalled() && !coordinator.verifyRawResources(),"A concurrent prepared/raw operation started")
        let old=raw.jobs[0];coordinator.cancel();coordinator.cancel()
        check(raw.jobs[0].cancels==1 && ends==0,"Cancel was duplicated or released scope before worker cleanup")
        old.completion(.failure(FixtureError.failed));check(!coordinator.state.busy && ends==1 && !coordinator.state.failed,"Raw cancellation did not finish safely")
        _=coordinator.extractRawISO(source);let current=coordinator.state.activity?.id
        old.completion(.success(first));check(coordinator.state.activity?.id==current && ends==1,"A stale raw completion released a replacement scope")
        raw.snapshot=first;raw.jobs[1].completion(.success(first))
        check(ends==2 && coordinator.state.raw.files==4 && !coordinator.state.resources.hasPlayableInstallation && prepared.modeCalls==0,"Raw success activated a playable/prepared installation")
        check(coordinator.state.message?.contains("Native conversion is still required")==true,"Raw UI result promised a playable install")
        let chained=RawService(),chain=NativeGameFilesCoordinator(service:prepared,rawService:chained);var handed=false
        let observer=chain.observe{state in if state.activity?.cancelling==true && !handed{handed=true;chained.jobs[0].completion(.failure(FixtureError.failed));_=chain.verifyRawResources()}}
        _=chain.verifyRawResources();chain.cancel();check(handed && chained.jobs.count==2 && chained.jobs[1].cancels==0,"Raw cancellation cancelled a reentrant replacement")
        chain.removeObserver(observer);chained.jobs[1].completion(.success(first))

        print("PASS raw-resource/coordinator: \(checks) checks; staged receipts, reuse, repair, cancel/scope, stale/reentrant callbacks; no native conversion/playability claim")
    }
}
