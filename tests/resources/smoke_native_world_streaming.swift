// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import MetalKit
import ImageIO
import UniformTypeIdentifiers
import simd
private struct Failure:Error,CustomStringConvertible {let description:String;init(_ s:String){description=s}}
private var checks=0
private func check(_ value:@autoclosure()throws->Bool,_ message:String)throws{checks+=1;if try !value(){throw Failure(message)}}
private func until(_ message:String,_ condition:()->Bool)throws {
    let end=Date().addingTimeInterval(10)
    while !condition() && Date()<end{RunLoop.main.run(until:Date().addingTimeInterval(0.002))}
    try check(condition(),message)
}
private func drain()throws{var done=false;DispatchQueue.main.async{done=true};try until("main queue drain"){done}}
private final class Request:NativeResourceTask {
    let url:URL,cap:Int,encoding:String?,completion:NativeResourceTransport.Completion
    var resumes=0,cancels=0
    private let lock=NSLock();private var completed=false
    init(_ r:URLRequest,_ cap:Int,_ c:@escaping NativeResourceTransport.Completion){url=r.url!;encoding=r.value(forHTTPHeaderField:"Accept-Encoding");self.cap=cap;completion=c}
    func resume(){resumes+=1}
    func cancel(){cancels+=1;deliver(nil,error:URLError(.cancelled))}
    func deliver(_ bytes:Data?,status:Int=200,error:Error?=nil,url:URL?=nil){
        lock.lock();guard !completed else{lock.unlock();return};completed=true;lock.unlock()
        let response=HTTPURLResponse(url:url ?? self.url,statusCode:status,httpVersion:"HTTP/1.1",headerFields:nil)
        DispatchQueue.global(qos:.utility).async{self.completion(bytes,response,error)}
    }
}
private func authoredWorld()->Data {
    var d=Data()
    func word(_ n:UInt32){var n=n.littleEndian;withUnsafeBytes(of:&n){d.append(contentsOf:$0)}}
    func half(_ n:UInt16){var n=n.littleEndian;withUnsafeBytes(of:&n){d.append(contentsOf:$0)}}
    [UInt32(0x324c5257),3,3,2].forEach(word)
    for p:[Float] in [[-4,2,1],[6,8,3],[0,4,5]]{for n in p{word(n.bitPattern)}}
    for n:Float in [0,0,1,0,0.25,0.75]{word(n.bitPattern)}
    [UInt32(0),1,2].forEach(word)
    d.append(contentsOf:[255,128,0,255,32,64,128,255,255,255,255,128])
    [UInt16(0),1,0,0].forEach(half)
    d.append(contentsOf:[1,2,3,255,4,5,6,255,7,8,9,255]);[UInt16(0),2].forEach(half)
    return d
}
private func authoredPNG(width:Int=2048,height:Int=128)throws->Data {
    var bytes=[UInt8](repeating:0,count:width*height*4)
    for y in 0..<height{for x in 0..<width{let i=(y*width+x)*4;bytes[i]=UInt8(x%256);bytes[i+1]=UInt8(y%256);bytes[i+2]=UInt8((x+y)%256);bytes[i+3]=255}}
    guard let provider=CGDataProvider(data:Data(bytes) as CFData),let image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)else{throw Failure("authored image")}
    let out=NSMutableData()
    guard let destination=CGImageDestinationCreateWithData(out,UTType.png.identifier as CFString,1,nil)else{throw Failure("PNG encoder")}
    CGImageDestinationAddImage(destination,image,nil);guard CGImageDestinationFinalize(destination)else{throw Failure("PNG completion")};return out as Data
}
private func texels(_ texture:MTLTexture,_ device:MTLDevice)throws->Data {
    let count=texture.width*texture.height*4
    guard let buffer=device.makeBuffer(length:count,options:.storageModeShared),let queue=device.makeCommandQueue(),let command=queue.makeCommandBuffer(),let blit=command.makeBlitCommandEncoder()else{throw Failure("GPU readback allocation")}
    blit.copy(from:texture,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:texture.width,height:texture.height,depth:1),to:buffer,destinationOffset:0,destinationBytesPerRow:texture.width*4,destinationBytesPerImage:count)
    blit.endEncoding();command.commit();command.waitUntilCompleted();try check(command.status == .completed,"GPU readback command failed")
    return Data(bytes:buffer.contents(),count:count)
}
private final class Harness {
    struct Mesh {let vertices:MTLBuffer,indices:MTLBuffer,indexCount:Int,atlas:MTLTexture}
    struct WorldSharpBase {let layers:Int,mapping:[UInt16],source:String,indices:Int,center:SIMD3<Float>}
    var server=ServerAddress("http://127.0.0.1:18005"),binding="a",worldSharpSource:String?
    let device:MTLDevice,worldCellLoader:NativeWorldCellLoader
    var worldCellTokens:[String:UUID]=[:],worldCellTaskIDs:[String:UUID]=[:]
    var loading=Set<String>(),retryAfter:[String:Date]=[:],meshes:[String:Mesh]=[:],worldSharpBase:[String:WorldSharpBase]=[:]
    var activeDetail="c0",activeDetails:Set<String>=["c0"],activeFar:Set<String>=[]
    var onStatus:((String)->Void)?,hdAdmissions=0
    init(_ device:MTLDevice,worker:DispatchQueue?=nil){self.device=device;worldCellLoader=NativeWorldCellLoader(worker:worker);worldSharpSource=fixedCJSourceIdentity()}
    // Binding and downstream HD scheduling are explicit seams. The actual HD
    // implementation has its own GPU/publication gates in the selected chain.
    func fixedCJSourceIdentity()->String{binding+"|"+(server?.display ?? "")}
    func loadWorldSharpIfNeeded(){hdAdmissions+=1}
    // ACTUAL_RENDERER_METHODS
}
@main private enum Main {
    static func main(){do{try run();print("PASS \(checks) authored actual Metal world preparation, bounded scheduling and literal scene-admission checks")}
        catch{fputs("FAIL \(error)\n",stderr);exit(1)}}
    private static func run()throws {
        guard let device=MTLCreateSystemDefaultDevice()else{if CommandLine.arguments.contains("--require-gpu"){throw Failure("Metal unavailable")};print("SKIP Metal unavailable; no executed world-streaming runtime acceptance");return}
        let bin=authoredWorld(),png=try authoredPNG(),world=try WorldBinary(data:bin)
        let prepared=try NativeWorldCellLoader.Prepared.make(bin:bin,png:png,cellSize:128,device:device,maximumBytes:8*1024*1024)
        let vertexData=world.vertices.withUnsafeBytes{Data($0)},indexData=world.indices.withUnsafeBytes{Data($0)}
        try check(Data(bytes:prepared.vertices.contents(),count:vertexData.count)==vertexData,"vertex bytes changed")
        try check(Data(bytes:prepared.indices.contents(),count:indexData.count)==indexData,"index bytes changed")
        try check(prepared.center==SIMD3<Float>(1,5,3) && prepared.layers==2 && prepared.sharpLayers==[0,2] && prepared.indexCount==3,"bounds/layer metadata changed")
        let baseline=try MTKTextureLoader(device:device).newTexture(data:png,options:[.SRGB:false])
        try check(prepared.atlas.pixelFormat==baseline.pixelFormat && prepared.atlas.mipmapLevelCount==baseline.mipmapLevelCount,"texture interpretation changed")
        try check(try texels(prepared.atlas,device)==texels(baseline,device),"actual decoded GPU texture changed")
        let far=try NativeWorldCellLoader.Prepared.make(bin:bin,png:png,cellSize:64,device:device,maximumBytes:8*1024*1024)
        try check(far.center==nil && far.sharpLayers==[0,2],"far cell metadata changed")
        for (bytes,image,size,budget) in [(Data([1,2]),png,128,8*1024*1024),(bin,Data([1]),128,8*1024*1024),(bin,try authoredPNG(width:1024),128,8*1024*1024),(bin,png,32,8*1024*1024),(bin,png,128,64)] {
            var failed=false;do{_=try NativeWorldCellLoader.Prepared.make(bin:bytes,png:image,cellSize:size,device:device,maximumBytes:budget)}catch{failed=true}
            try check(failed,"invalid preparation input accepted")
        }
        var cancelled=false;do{_=try NativeWorldCellLoader.Prepared.make(bin:bin,png:png,cellSize:128,device:device,maximumBytes:8*1024*1024,cancelled:{true})}catch NativeWorldCellLoader.Failure.cancelled{cancelled=true}
        try check(cancelled,"preparation cancellation ignored")
        var requests:[Request]=[]
        NativeResourceTransport.install({_,_ in fatalError("unbounded world transfer")},bounded:{r,cap,c in let t=Request(r,cap,c);requests.append(t);return t})
        let worker=DispatchQueue(label:"authored.held.world"),release=DispatchSemaphore(value:0)
        worker.async{release.wait()}
        let loader=NativeWorldCellLoader(maximumPending:4,maximumFileBytes:2*1024*1024,maximumPreparedBytes:8*1024*1024,worker:worker)
        let root=URL(string:"http://127.0.0.1:18005")!
        var results:[String:Result<NativeWorldCellLoader.Prepared,Error>]=[:],mainReplies=true
        func load(_ name:String,_ priority:Int)->UUID {
            loader.load(name:name,bin:root.appendingPathComponent(name+".bin"),png:root.appendingPathComponent(name+".png"),cellSize:128,device:device,priority:priority){r in mainReplies = mainReplies && Thread.isMainThread;results[name]=r}
        }
        func deliverPair(_ start:Int){requests[start].deliver(bin);requests[start+1].deliver(png)}
        _=load("t0",0);_=load("c1",1);let current=load("c0",2);let queued=load("c2",1);_=load("overflow",3)
        try until("coalesced prioritized pair not started"){requests.count==2 && results["overflow"] != nil}
        try check(requests[0].url.lastPathComponent=="c0.bin" && requests[1].url.lastPathComponent=="c0.png","far request started before current detail")
        if case .failure(NativeWorldCellLoader.Failure.pendingLimit)?=results["overflow"]{checks+=1}else{throw Failure("pending cap lost")}
        deliverPair(0);try drain()
        var responsive=false;DispatchQueue.main.async{responsive=true};try until("held worker blocks main input"){responsive}
        try check(loader.activeCount==1 && loader.pendingCount==3 && results["c0"]==nil,"held CPU slot released early")
        loader.updateWanted(["c0":2,"c1":4,"c2":1]);loader.cancel(queued);loader.cancel(current)
        try until("retired pending callbacks absent"){results["t0"] != nil && results["c2"] != nil}
        try check(requests.count==2 && loader.activeCount==1 && loader.pendingCount==1,"cancelled CPU overlapped another preparation")
        release.signal();try until("cancelled CPU did not release slot"){results["c0"] != nil && requests.count==4}
        if case .failure(NativeWorldCellLoader.Failure.cancelled)?=results["c0"]{checks+=1}else{throw Failure("cancelled CPU product published")}
        try check(requests[2].url.lastPathComponent=="c1.bin","updated detail priority ignored")
        deliverPair(2);try until("fresh prepared product missing"){results["c1"] != nil && loader.activeCount==0}
        try check(try results["c1"]!.get().center==SIMD3<Float>(1,5,3),"worker actual product differs")
        for kind in ["http","redirect","oversize","badbin","badpng"] {
            let start=requests.count;_=load(kind,1);try until("bad request pair missing"){requests.count==start+2}
            switch kind {
            case "http":requests[start].deliver(bin,status:503)
            case "redirect":requests[start].deliver(bin,url:root.appendingPathComponent("other"))
            case "oversize":requests[start].deliver(Data(repeating:0,count:2*1024*1024+1))
            case "badbin":requests[start].deliver(Data([1]));requests[start+1].deliver(png)
            default:requests[start].deliver(bin);requests[start+1].deliver(Data([1]))
            }
            try until("invalid pair did not finish"){results[kind] != nil && loader.activeCount==0}
            if case .failure?=results[kind]{checks+=1}else{throw Failure("invalid pair accepted: \(kind)")}
        }
        var firstDone=false,secondDone=false
        _=loader.load(name:"first",bin:root.appendingPathComponent("first.bin"),png:root.appendingPathComponent("first.png"),cellSize:128,device:device,priority:1){_ in
            firstDone=true
            _=loader.load(name:"second",bin:root.appendingPathComponent("second.bin"),png:root.appendingPathComponent("second.png"),cellSize:128,device:device,priority:1){_ in secondDone=true}
        }
        let start=requests.count;try until("reentry first pair missing"){requests.count==start+2};deliverPair(start)
        try until("reentry second pair missing"){firstDone && requests.count==start+4};deliverPair(start+2)
        try until("reentry second completion missing"){secondDone && loader.activeCount==0}
        let resetStart=requests.count;_=load("resetActive",1);try until("reset active pair absent"){requests.count==resetStart+2};_=load("resetPending",0)
        loader.reset();try until("reset callbacks absent"){results["resetActive"] != nil && results["resetPending"] != nil && loader.activeCount==0}
        try check(loader.pendingCount==0 && requests.count==resetStart+2,"reset started queued obsolete transfer")
        try check(mainReplies && requests.allSatisfy{$0.cap==2*1024*1024 && $0.encoding=="identity" && $0.resumes==1},"bounded pair owner/encoding/resume changed")

        let h=Harness(device),sceneStart=requests.count
        h.load(name:"c0");h.load(name:"c0");try until("scene pair missing"){requests.count==sceneStart+2}
        try check(h.worldCellTokens.count==1 && h.loading==["c0"],"duplicate scene request admitted")
        h.binding="b";h.retireWorldCellRequests();h.worldSharpSource=h.fixedCJSourceIdentity();h.load(name:"c0")
        try until("new source blocked behind old transfer"){requests.count==sceneStart+4}
        try check(h.loading==["c0"] && h.retryAfter.isEmpty && h.meshes.isEmpty,"obsolete result damaged current owner")
        deliverPair(sceneStart+2);try until("actual scene mesh not admitted"){h.meshes["c0"] != nil}
        try check(h.loading.isEmpty && h.worldCellTokens.isEmpty && h.worldCellTaskIDs.isEmpty && h.hdAdmissions==1,"scene commit did not release ownership/retain HD scheduling")
        try check(h.worldSharpBase["c0"]?.source==h.fixedCJSourceIdentity() && h.worldSharpBase["c0"]?.center==SIMD3<Float>(1,5,3),"scene bounds/source metadata lost")
        try check(Data(bytes:h.meshes["c0"]!.vertices.contents(),count:vertexData.count)==vertexData,"scene GPU geometry changed")
        let edgeStart=requests.count;h.activeDetails=["c1"];h.activeDetail="c1";h.synchronizeWorldCellIntents();h.load(name:"c1")
        try until("edge pair absent"){requests.count==edgeStart+2}
        h.activeDetails=["c2"];h.activeDetail="c2";h.synchronizeWorldCellIntents();h.load(name:"c2")
        try until("obsolete edge blocked current detail"){requests.count==edgeStart+4}
        try check(h.loading==["c2"] && h.retryAfter["c1"]==nil && h.meshes["c1"]==nil,"offscreen completion erased new ownership or armed retry")
        deliverPair(edgeStart+2);try until("current edge mesh absent"){h.meshes["c2"] != nil}
        try check(h.hdAdmissions==2 && h.loading.isEmpty,"current edge publication lost")
        let failStart=requests.count;h.activeDetails=["c3"];h.activeDetail="c3";h.load(name:"c3");try until("failed scene pair absent"){requests.count==failStart+2}
        requests[failStart].deliver(nil,status:503);try until("scene failure did not release slot"){h.retryAfter["c3"] != nil && h.loading.isEmpty}
        let noRetry=requests.count;h.load(name:"c3");try drain();try check(requests.count==noRetry,"retry delay ignored")
        h.retireWorldCellRequests();try check(h.retryAfter.isEmpty && h.worldCellTokens.isEmpty,"source reset retained retry/ticket")
        let heldWorker=DispatchQueue(label:"authored.scene.pending.cpu"),heldRelease=DispatchSemaphore(value:0)
        heldWorker.async{heldRelease.wait()}
        let held=Harness(device,worker:heldWorker),heldStart=requests.count
        held.load(name:"c0");try until("held scene initial pair absent"){requests.count==heldStart+2}
        deliverPair(heldStart);try drain()
        held.binding="replacement";held.retireWorldCellRequests();held.worldSharpSource=held.fixedCJSourceIdentity();held.load(name:"c0")
        try check(requests.count==heldStart+2 && held.loading==["c0"],"retired CPU owner released serial slot early")
        heldRelease.signal();try until("held source replacement pair absent"){requests.count==heldStart+4}
        try check(held.meshes.isEmpty && held.retryAfter.isEmpty && held.loading==["c0"],"old prepared completion erased or poisoned new scene slot")
        deliverPair(heldStart+2);try until("held source replacement mesh absent"){held.meshes["c0"] != nil}
        try check(held.worldSharpBase["c0"]?.source==held.fixedCJSourceIdentity() && held.loading.isEmpty,"new prepared scene source did not commit")

    }
}
