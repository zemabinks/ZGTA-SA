// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
private struct Failure:Error,CustomStringConvertible{let description:String;init(_ s:String){description=s}}
private var checks=0
private func check(_ value:@autoclosure()->Bool,_ text:String)throws{checks+=1;if !value(){throw Failure(text)}}
private final class Request:NativeResourceTask {
    let url:URL,completion:NativeResourceTransport.Completion
    init(_ r:URLRequest,_ c:@escaping NativeResourceTransport.Completion){url=r.url!;completion=c}
    func resume(){};func cancel(){}
    func deliver(_ data:Data?,status:Int=200)throws {
        let done=DispatchSemaphore(value:0)
        DispatchQueue.global(qos:.utility).async{self.completion(data,HTTPURLResponse(url:self.url,statusCode:status,httpVersion:"HTTP/1.1",headerFields:nil),nil);done.signal()}
        try check(done.wait(timeout:.now()+5) == .success,"physics response delivery timeout")
    }
}
// Coupling reset and support presentation are explicit boundaries. The actual
// physical metadata parser/world owner below is not replaced with a spy.
private final class Coupling {var resets=0;func reset(connection:UUID){resets+=1}}
private final class Support {var clears=0;func clear(){clears+=1}}
private final class Harness {
    // ACTUAL_CAMERA_DOCUMENTS
    struct Snapshot{let links:[Int],revision:UInt64,connection:UUID}
    var server=ServerAddress("http://127.0.0.1:18007"),binding="source-a",modelIndexToken=UUID()
    var vehicleCouplingMetadataToken=UUID(),vehicleTreadsMetadataToken=UUID()
    let groundVehicle=NativeGroundVehicle(),vehicleCoupling:Coupling?=Coupling(),supportScene:Support?=Support(),couplingConnection=UUID()
    var couplingSnapshot:Snapshot?,cameraVehicleDefinitions:[String:CameraVehicleDefinition]=[:]
    var remoteSuspensionConfigurations:[Int:NativeRemoteSuspension.Configuration]=[:]
    #if HAS_LOCAL_SHOTS
    var localShotTyreDefinitions:[Int:[NativeLocalShots.Tyre]]=[:]
    #endif
    var couplingLoads=0,treadLoads=0
    func applyVehicleCouplings(_ links:[Int],revision:UInt64,connection:UUID){fatalError("unexpected absent snapshot")}
    func loadVehicleCouplingDefinitions(){couplingLoads+=1};func loadVehicleTreads(){treadLoads+=1}
    func fixedCJSourceIdentity()->String{binding+"|"+(server?.display ?? "")}
    func loadPhysics(){
        guard let server else{return}
        // ACTUAL_MODEL_REQUEST_HEADER
        // ACTUAL_PHYSICS_REQUEST
    }
    var configuration:NativeGroundVehicle.CellConfiguration?{groundVehicle?.cellConfiguration("c0")}
}
private func drain()throws{var done=false;DispatchQueue.main.async{done=true};let end=Date().addingTimeInterval(5);while !done && Date()<end{RunLoop.main.run(until:Date().addingTimeInterval(0.002))};try check(done,"main queue timeout")}
private func metadata(_ material:Int)throws->Data{try JSONSerialization.data(withJSONObject:["models":["420":["id":420,"kind":"car","origin":0,"wheels":[["centre":[material,0,0],"radius":0.3,"front":true,"left":true]]]],"materialClasses":Array(repeating:material,count:256)])}
@main private enum Main {
    static func main(){do{try run();print("PASS \(checks) literal physics metadata/actual native ground owner checks; authored bytes, no rendered or retail acceptance")}
        catch{fputs("FAIL \(error)\n",stderr);exit(1)}}
    private static func run()throws {
        var requests:[Request]=[];NativeResourceTransport.install({r,c in let t=Request(r,c);requests.append(t);return t})
        let h=Harness(),old=try metadata(2),fresh=try metadata(7)
        guard let reference=NativeGroundVehicle()else{throw Failure("expected snapshot owner unavailable")}
        reference.loadDefinitions(fresh);let freshConfig=reference.cellConfiguration("c0")
        guard let world=h.groundVehicle?.world,let body=world.addBody(position:SIMD3(20,8,0),gravityScale:0)else{throw Failure("actual independent physical body unavailable")}
        let pose=SwiftRapierWorld.BodyState(position:SIMD3(20,8,0),rotation:simd_quatf(angle:0.3,axis:SIMD3(0,1,0)),linearVelocity:SIMD3(1,2,3),angularVelocity:SIMD3(0.1,0.2,0.3))
        try check(world.setBodyState(pose,for:body),"physical fixture setup")
        if CommandLine.arguments.contains("--source-only"){
            let prior=h.configuration;h.loadPhysics();try requests[0].deliver(old);h.binding="source-b";try drain()
            try check(h.configuration==prior && h.vehicleCoupling!.resets==0 && h.supportScene!.clears==0,"old-source physics table mutated native ground/coupling/support owners")
            #if HAS_LOCAL_SHOTS
            try check(h.localShotTyreDefinitions.isEmpty,"Retired source published shot tyre metadata")
            #endif
            return
        }
        h.loadPhysics();try requests[0].deliver(fresh);try drain();try check(h.configuration==freshConfig,"current actual ground metadata not installed")
        #if HAS_LOCAL_SHOTS
        try check(h.localShotTyreDefinitions[420]?.first?.center.x==7,"Current actual tyre catalog was not admitted with physics metadata")
        #endif
        h.loadPhysics();let retired=requests.count-1;h.loadPhysics();let latest=requests.count-1
        try requests[latest].deliver(fresh);try drain();let resets=h.vehicleCoupling!.resets,clears=h.supportScene!.clears,coupling=h.couplingLoads,treads=h.treadLoads
        try requests[retired].deliver(old);try drain()
        try check(h.configuration==freshConfig && h.vehicleCoupling!.resets==resets && h.supportScene!.clears==clears,"late physics metadata replaced current materials or reset active coupling/support owners")
        #if HAS_LOCAL_SHOTS
        try check(h.localShotTyreDefinitions[420]?.first?.center.x==7,"Retired physics response replaced the current shot tyre catalog")
        #endif
        try check(h.couplingLoads==coupling && h.treadLoads==treads,"retired physics callback restarted child metadata loads")
        guard let after=world.bodyState(body)else{throw Failure("metadata admission removed unrelated body")}
        try check(after.position==pose.position && after.rotation.vector==pose.rotation.vector && after.linearVelocity==pose.linearVelocity && after.angularVelocity==pose.angularVelocity,"metadata admission moved unrelated physical body")
    }
}
