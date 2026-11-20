// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
private struct Failure:Error,CustomStringConvertible {let description:String;init(_ s:String){description=s}}
private var checks=0
private func check(_ value:@autoclosure()throws->Bool,_ message:String)throws{checks+=1;if try !value(){throw Failure(message)}}
private func until(_ message:String,_ condition:()->Bool)throws {
    let end=Date().addingTimeInterval(8)
    while !condition() && Date()<end{RunLoop.main.run(until:Date().addingTimeInterval(0.002))}
    try check(condition(),message)
}
private final class Request:NativeResourceTask {
    let url:URL,cap:Int,completion:NativeResourceTransport.Completion
    var resumes=0,cancels=0
    private let lock=NSLock();private var completed=false
    init(_ request:URLRequest,_ cap:Int,_ completion:@escaping NativeResourceTransport.Completion){url=request.url!;self.cap=cap;self.completion=completion}
    func resume(){resumes+=1}
    func cancel(){cancels+=1;deliver(nil,error:URLError(.cancelled))}
    func deliver(_ data:Data?,status:Int=200,error:Error?=nil,url:URL?=nil){
        lock.lock();guard !completed else{lock.unlock();return};completed=true;lock.unlock()
        let response=HTTPURLResponse(url:url ?? self.url,statusCode:status,httpVersion:"HTTP/1.1",headerFields:nil)
        DispatchQueue.global(qos:.utility).async{self.completion(data,response,error)}
    }
}
private func floorData(_ height:Float=0)->Data {
    var data=Data()
    func word(_ n:UInt32){var n=n.littleEndian;withUnsafeBytes(of:&n){data.append(contentsOf:$0)}}
    [UInt32(0x324c4353),4,2,1].forEach(word)
    for p:[Float] in [[-4,-4,height],[4,-4,height],[4,4,height],[-4,4,height]]{for n in p{word(n.bitPattern)}}
    [UInt32(0),1,2,0,2,3].forEach(word)
    data.append(contentsOf:[2,2,0,0,1,1,0,0]);return data
}
private func definitions(sound:Int=2,parts:[[String:Int]]?=nil)throws->Data {
    var classes=Array(repeating:2,count:256);classes[1]=sound
    var d:[String:Any]=["models":[String:Any](),"materialClasses":classes]
    if let parts{d["collisionFallbackParts"]=["c0":parts]}
    return try JSONSerialization.data(withJSONObject:d)
}
@main private enum Main {
    static func main(){do{try run();print("PASS \(checks) bounded serial collision-preparation/real physical ownership checks")}
        catch{fputs("FAIL \(error)\n",stderr);exit(1)}}
    private static func run()throws {
        try check(Thread.isMainThread,"main owner required")
        guard let ground=NativeGroundVehicle()else{throw Failure("native physics unavailable")}
        ground.loadDefinitions(try definitions())
        let flat=floorData(),raised=floorData(3),config=ground.cellConfiguration("c0")
        let prepared=try NativeGroundVehicle.prepareCell(flat,configuration:config)
        try check(!ground.isCellLoaded("c0"),"CPU preparation mutated the physical world")
        let world=ground.world
        guard let body=world.addBody(position:SIMD3(20,8,0),gravityScale:0)else{throw Failure("independent body")}
        let pose=SwiftRapierWorld.BodyState(position:SIMD3(20,8,0),rotation:simd_quatf(angle:0.3,axis:SIMD3(0,1,0)),linearVelocity:SIMD3(1,2,3),angularVelocity:SIMD3(0.1,0.2,0.3))
        try check(world.setBodyState(pose,for:body),"body setup")
        let before=world.bodyState(body)!
        try check(ground.installCell("c0",data:flat,prepared:prepared),"prepared cell rejected")
        let installedBody=world.bodyState(body)!
        try check(before.linearVelocity==installedBody.linearVelocity && before.angularVelocity==installedBody.angularVelocity,"cell installation altered unrelated momentum")
        try check(before.position==installedBody.position && before.rotation.vector==installedBody.rotation.vector,"cell installation altered unrelated pose")
        try check(world.step(),"query update")
        let hit=world.raycast(origin:SIMD3(0,10,0),direction:SIMD3(0,-1,0),distance:20)
        try check(abs((hit?.distance ?? -100)-10)<0.0001 && hit?.material==1,"prepared physical floor/material differs")
        ground.retainCells([])
        let after=world.bodyState(body)!
        // step() above legitimately advances the body; removal itself must not.
        let held=world.bodyState(body)!;ground.retainCells([]);let heldAfter=world.bodyState(body)!
        try check(held.position==heldAfter.position && held.linearVelocity==heldAfter.linearVelocity && held.rotation.vector==heldAfter.rotation.vector,"cell retirement changed unrelated body")
        try check(after.linearVelocity==heldAfter.linearVelocity && after.angularVelocity==heldAfter.angularVelocity,"cell retirement altered unrelated momentum")
        ground.loadDefinitions(try definitions(sound:7))
        try check(!ground.installCell("c0",data:flat,prepared:prepared) && !ground.isCellLoaded("c0"),"old material snapshot admitted")
        let latest=try NativeGroundVehicle.prepareCell(raised,configuration:ground.cellConfiguration("c0"))
        try check(ground.installCell("c0",data:raised,prepared:latest),"fresh material snapshot rejected")
        ground.retainCells([])
        ground.loadDefinitions(try definitions(parts:[["indexStart":0,"indexCount":999]]))
        do{_=try NativeGroundVehicle.prepareCell(flat,configuration:ground.cellConfiguration("c0"));throw Failure("invalid fallback accepted")}
        catch is NativeGroundVehicle.CellPreparationError{checks+=1}
        ground.loadDefinitions(try definitions(parts:[["indexStart":0,"indexCount":3]]))
        let fallback=try NativeGroundVehicle.prepareCell(flat,configuration:ground.cellConfiguration("c0"))
        try check(ground.installCell("c0",data:flat,prepared:fallback),"valid fallback rejected")
        ground.retainCells([]);ground.loadDefinitions(try definitions())
        var empty=Data();for n:UInt32 in [0x324c4353,0,0,0]{var n=n.littleEndian;withUnsafeBytes(of:&n){empty.append(contentsOf:$0)}}
        let blank=try NativeGroundVehicle.prepareCell(empty,configuration:ground.cellConfiguration("empty"))
        try check(ground.installCell("empty",data:empty,prepared:blank) && ground.isCellLoaded("empty"),"empty valid cell lost")
        ground.retainCells([])
        guard let unconfigured=NativeGroundVehicle()else{throw Failure("deferred owner")}
        unconfigured.deferCellData("deferred",data:flat);try check(!unconfigured.isCellLoaded("deferred"),"unconfigured cell falsely loaded")
        unconfigured.loadDefinitions(try definitions());try check(unconfigured.isCellLoaded("deferred"),"deferred metadata path lost")

        var requests:[Request]=[]
        NativeResourceTransport.install({_,_ in fatalError("unbounded transfer used")},bounded:{request,cap,completion in
            let task=Request(request,cap,completion);requests.append(task);return task
        })
        let worker=DispatchQueue(label:"authored.held.collision.worker"),release=DispatchSemaphore(value:0)
        worker.async{release.wait()}
        let loader=NativeCollisionCellLoader(maximumPending:2,maximumBytes:1024,worker:worker)
        let url=URL(string:"http://127.0.0.1:18004/c0")!,snapshot=ground.cellConfiguration("c0")
        var replies:[String:Result<NativeCollisionCellLoader.Prepared,Error>]=[:],mainReplies=true
        func load(_ key:String)->UUID {
            loader.load(url:url.appendingPathComponent(key),configuration:snapshot){result in mainReplies = mainReplies && Thread.isMainThread;replies[key]=result}
        }
        let a=load("a");try check(requests.count==1 && loader.activeCount==1 && loader.pendingCount==0,"first job not active")
        try check(requests[0].cap==1024 && requests[0].resumes==1,"bounded transfer/resume changed")
        requests[0].deliver(flat)
        let b=load("b");_=load("c");_=load("overflow")
        var heartbeat=false;DispatchQueue.main.async{heartbeat=true}
        try until("main input/publication queue blocked by held CPU work"){heartbeat && replies["overflow"] != nil}
        try check(replies["a"]==nil && requests.count==1 && loader.pendingCount==2,"held worker did not retain serial admission")
        if case .failure(NativeCollisionCellLoader.Failure.pendingLimit)?=replies["overflow"]{checks+=1}else{throw Failure("pending limit not explicit")}
        loader.cancel(b);try until("pending cancel callback"){replies["b"] != nil}
        try check(loader.pendingCount==1 && requests.count==1,"cancelled queued descriptor started a transfer")
        loader.cancel(a);_=load("d")
        try check(loader.activeCount==1 && loader.pendingCount==2,"cancelled active CPU work released its serial slot early")
        release.signal()
        try until("serial worker did not finish cancellation/start next"){replies["a"] != nil && requests.count==2}
        if case .failure(NativeCollisionCellLoader.Failure.cancelled)?=replies["a"]{checks+=1}else{throw Failure("cancelled CPU result published")}
        try check(requests[1].url.lastPathComponent=="c" && loader.activeCount==1,"FIFO next descriptor changed")
        requests[1].deliver(raised)
        try until("actual prepared CPU result missing"){replies["c"] != nil && requests.count==3}
        let product=try replies["c"]!.get()
        try check(product.collision.height(x:0,y:0,near:4,maxDrop:10)==3,"async spatial floor differs")
        try check(product.ground != nil && ground.installCell("c0",data:product.data,prepared:product.ground!),"async physical product rejected")
        try check(world.step(),"async physical query update")
        let actual=world.raycast(origin:SIMD3(0,10,0),direction:SIMD3(0,-1,0),distance:20)
        try check(abs((actual?.distance ?? -100)-7)<0.0001 && actual?.material==1,"async physical floor/material differs")
        try check(requests[2].url.lastPathComponent=="d","next descriptor not pumped")
        loader.reset();try until("active transport reset did not complete"){replies["d"] != nil && loader.activeCount==0}
        try check(requests[2].cancels==1 && loader.pendingCount==0,"reset retained transfer/queue")
        var reentered:UUID?,firstDone=false,secondDone=false
        _=loader.load(url:url,configuration:snapshot){result in
            firstDone=true
            reentered=loader.load(url:url.appendingPathComponent("reentrant"),configuration:snapshot){result in secondDone=true}
        }
        requests.last!.deliver(flat)
        try until("reentrant load failed"){firstDone && requests.last!.url.lastPathComponent=="reentrant"}
        try check(reentered != nil && loader.activeCount==1,"completion reentry lost its active request")
        requests.last!.deliver(flat);try until("reentrant completion failed"){secondDone && loader.activeCount==0}
        for (key,data,status,replyURL) in [("invalid",Data([1,2]),200,nil as URL?), ("http",flat,503,nil), ("oversize",Data(repeating:0,count:1025),200,nil), ("redirect",flat,200,url.appendingPathComponent("other"))] {
            _=load(key);requests.last!.deliver(data,status:status,url:replyURL)
            try until("failure did not finish: \(key)"){replies[key] != nil && loader.activeCount==0}
            if case .failure?=replies[key]{checks+=1}else{throw Failure("invalid response accepted: \(key)")}
        }
        try check(mainReplies && requests.allSatisfy{$0.resumes==1},"callback owner/request resume changed")
        try check(loader.pendingCount==0 && loader.activeCount==0,"loader leaked work")
    }
}
