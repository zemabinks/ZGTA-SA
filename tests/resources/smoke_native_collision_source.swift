// SPDX-License-Identifier: AGPL-3.0-only
// Authored SCL2 floors, deterministic transport, actual cell parser/ground
// owner/Rapier queries and literal renderer publication methods.
import Foundation
import simd

private struct Failure:Error,CustomStringConvertible {
    let description:String
    init(_ text:String){description=text}
}
private var checks=0
private func check(_ condition:@autoclosure()throws->Bool,_ text:String)throws {
    checks+=1;let passed=try condition();if !passed{throw Failure(text)}
}
private final class Request:NativeResourceTask {
    let url:URL,completion:NativeResourceTransport.Completion
    var resumes=0,cancels=0
    init(_ request:URLRequest,_ completion:@escaping NativeResourceTransport.Completion){url=request.url!;self.completion=completion}
    func resume(){resumes+=1}
    func cancel(){cancels+=1}
    func complete(_ data:Data?,status:Int=200)throws {
        let done=DispatchSemaphore(value:0)
        DispatchQueue.global(qos:.utility).async {
            self.completion(data,HTTPURLResponse(url:self.url,statusCode:status,httpVersion:"HTTP/1.1",headerFields:nil),nil)
            done.signal()
        }
        guard done.wait(timeout: .now() + 5) == .success else{throw Failure("transport delivery timeout")}
    }
}
private final class Harness {
    var server=ServerAddress("http://127.0.0.1:18003")
    var binding="authored-source-a"
    var collisions:[String:WorldCollision]=[:]
    var collisionRequests=NativeCollisionRequests()
    var desiredPhysicsCells:Set<String>=["c0"]
    var collisionLoading=Set<String>()
    var collisionRetryAfter:[String:Date]=[:]
    var collisionResourceSource:String?
    var collisionLoadTokens:[String:UUID]=[:]
    var collisionLoadTasks:[String:COLLISION_TASK_TYPE]=[:]
    // ASYNC_COLLISION_OWNER
    let groundVehicle:NativeGroundVehicle?
    init()throws {
        groundVehicle=NativeGroundVehicle()
        guard let groundVehicle else{throw Failure("actual native ground world unavailable")}
        let config:[String:Any]=["models":[String:Any](),"materialClasses":Array(repeating:2,count:256)]
        _=groundVehicle.loadDefinitions(try JSONSerialization.data(withJSONObject:config))
    }
    // Resource binding is an explicit seam. Parsing, publication/retirement,
    // cell ownership and the physical query below are production operations.
    func fixedCJSourceIdentity()->String {binding+"|"+(server?.display ?? "")}
    // ACTUAL_RENDERER_METHODS
    func physicalHeight(x:Float=0)throws->Float? {
        guard let world=groundVehicle?.world else{throw Failure("actual world retired")}
        try check(world.step(),"native world query update")
        return world.raycast(origin:SIMD3(x,20,0),direction:SIMD3(0,-1,0),distance:30).map{20-$0.distance}
    }
}
private func authoredFloorData(_ height:Float)->Data {
    var data=Data()
    func u32(_ n:UInt32){data.append(contentsOf:[UInt8(truncatingIfNeeded:n),UInt8(truncatingIfNeeded:n>>8),UInt8(truncatingIfNeeded:n>>16),UInt8(truncatingIfNeeded:n>>24)])}
    u32(0x324c4353);u32(4);u32(2);u32(1)
    let points:[SIMD3<Float>]=[SIMD3(-4,-4,height),SIMD3(4,-4,height),SIMD3(4,4,height),SIMD3(-4,4,height)]
    for p in points {
        u32(p.x.bitPattern);u32(p.y.bitPattern);u32(p.z.bitPattern)
    }
    for n in [UInt32(0),1,2,0,2,3]{u32(n)}
    data.append(contentsOf:[2,2,0,0,1,1,0,0]);return data
}
private let asynchronous=ASYNC_COLLISION_VALUE
private func until(_ message:String,_ condition:()->Bool)throws {
    let end=Date().addingTimeInterval(8)
    while !condition() && Date()<end{RunLoop.main.run(until:Date().addingTimeInterval(0.002))}
    try check(condition(),message)
}
private func drain()throws {
    var finished=false;DispatchQueue.main.async{finished=true}
    let end=Date().addingTimeInterval(5)
    while !finished && Date()<end{RunLoop.main.run(until:Date().addingTimeInterval(0.002))}
    try check(finished,"main publication queue timeout")
}
@main private enum Main {
    static func main() {
        do{try run();print("PASS \(checks) authored collision-source publication/actual Rapier floor checks; no HTTP, UI or retail acceptance")}
        catch{fputs("FAIL \(error)\n",stderr);exit(1)}
    }
    private static func run()throws {
        try check(Thread.isMainThread,"main scene owner required")
        var requests:[Request]=[]
        let factory:NativeResourceTransport.Factory={request,completion in let task=Request(request,completion);requests.append(task);return task}
        NativeResourceTransport.install(factory,bounded:{request,_,completion in factory(request,completion)})
        let h=try Harness(),zero=authoredFloorData(0),raised=authoredFloorData(3)
        h.loadCollision(name:"c0");try check(requests.count==1,"initial collision request missing")
        try check(requests[0].url.path=="/game/world/c0.col.bin" && requests[0].resumes==1,"original collision route/resume changed")
        // Old transport has already finished; its publication is queued.
        try requests[0].complete(zero)
        h.binding="authored-source-b";h.loadCollision(name:"c0")
        if asynchronous {try until("obsolete collision loading blocks the new resource source"){requests.count==2}}
        try check(requests.count==2,"obsolete collision loading blocks the new resource source")
        if !asynchronous{try check(requests[0].cancels==1,"old collision task not cancelled")}
        try drain()
        try check(h.collisions.isEmpty && h.collisionLoading.contains("c0"),"old completion published geometry or erased the new loading slot")
        try check(try h.physicalHeight()==nil,"old queued collision installed a physical floor")
        try requests[1].complete(raised);try until("current collision preparation/publication timeout"){h.collisions["c0"] != nil};try drain()
        try check(h.collisions["c0"]?.height(x:0,y:0,near:4,maxDrop:10)==3,"current native cell query did not publish raised floor")
        try check(h.groundVehicle?.isCellLoaded("c0")==true && h.collisionLoading.isEmpty,"current physical cell/loading ownership not committed")
        try check(abs(((try h.physicalHeight()) ?? -100)-3) < 0.0001,"actual current physical floor differs")
        try check(h.collisions["c0"]?.ground(x:0,y:0,near:4,maxDrop:10)?.material==1,"native cell query lost authored face material")
        try check(h.groundVehicle!.world.raycast(origin:SIMD3(0,20,0),direction:SIMD3(0,-1,0),distance:30)?.material==1,"actual physical floor lost authored face material")
        // A cell retirement must remove that cell's collider while preserving
        // an unrelated object in the same actual native world.
        let world=h.groundVehicle!.world
        guard let marker=world.addBox(halfExtents:SIMD3(1,0.5,1),position:SIMD3(50,6,0))else{throw Failure("authored independent object")}
        world.setColliderGroups(marker,collision:131071,solver:0xffffffff)
        try check(abs(((try h.physicalHeight(x:50)) ?? -100)-6.5) < 0.0001,"authored unrelated object query missing")
        guard let body=world.addBody(position:SIMD3(20,8,0),gravityScale:0)else{throw Failure("authored independent dynamic body")}
        let pose=SwiftRapierWorld.BodyState(position:SIMD3(20,8,0),rotation:simd_quatf(angle:0.3,axis:SIMD3(0,1,0)),linearVelocity:SIMD3(1,2,3),angularVelocity:SIMD3(0.1,0.2,0.3))
        try check(world.setBodyState(pose,for:body),"authored dynamic state setup")
        guard let beforeBody=world.bodyState(body)else{throw Failure("authored dynamic body state unavailable")}
        h.binding="authored-source-c";h.synchronizeCollisionResourceSource()
        try check(h.collisions.isEmpty && h.groundVehicle?.isCellLoaded("c0")==false,"accepted collision cell survived source retirement")
        guard let afterBody=world.bodyState(body)else{throw Failure("cell retirement removed unrelated dynamic body")}
        try check(beforeBody.position==afterBody.position && beforeBody.rotation.vector==afterBody.rotation.vector,"cell retirement changed unrelated body pose")
        try check(beforeBody.linearVelocity==afterBody.linearVelocity && beforeBody.angularVelocity==afterBody.angularVelocity,"cell retirement changed unrelated body momentum")
        try check(try h.physicalHeight()==nil,"retired cell retained an actual physical floor")
        try check(abs(((try h.physicalHeight(x:50)) ?? -100)-6.5) < 0.0001,"cell retirement removed an unrelated physical object")
        // A late prior-source failure cannot arm a current-source retry delay.
        h.loadCollision(name:"c0");let oldFailure=requests.count-1
        try requests[oldFailure].complete(nil,status:503)
        h.binding="authored-source-d";h.loadCollision(name:"c0")
        if asynchronous{try until("new source after old failure not admitted"){requests.count==oldFailure+2}}
        let current=requests.count-1
        try drain()
        try check(h.collisionRetryAfter["c0"]==nil && h.collisionLoading.contains("c0"),"old-source failure poisoned the current retry/loading owner")
        try requests[current].complete(zero);try until("new source after old failure publication timeout"){h.collisions["c0"] != nil};try drain()
        try check(abs((try h.physicalHeight()) ?? -100)<0.0001,"new source after obsolete failure did not install its floor")
        // Same-source refresh holds the accepted floor; this is no blanket
        // collision reset on each scene update.
        let count=requests.count;h.synchronizeCollisionResourceSource();h.loadCollision(name:"c0")
        try check(requests.count==count && h.groundVehicle!.isCellLoaded("c0"),"same source unnecessarily reloaded/retired its floor")
        // A result for a no-longer-retained cell is discarded normally.
        h.binding="authored-source-e";h.loadCollision(name:"c0")
        h.desiredPhysicsCells=[];try requests.last!.complete(raised)
        try until("offscreen collision request did not release its slot"){h.collisionLoading.isEmpty};try drain()
        try check(h.collisions.isEmpty && !h.groundVehicle!.isCellLoaded("c0") && h.collisionLoading.isEmpty,"offscreen current response published or retained loading ownership")
        try check(try h.physicalHeight()==nil,"offscreen response installed physical geometry")
        try check(requests.allSatisfy{$0.resumes==1},"collision request resumed more than once")
    }
}
