// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

private enum GateFailure:Error {case check(String)}
private var checks=0
private func require(_ condition:Bool,_ message:String)throws{checks+=1;if !condition{throw GateFailure.check(message)}}
// Registry/streaming ownership below is an explicit boundary. Actual Rapier
// contacts, traffic shapes and literal renderer query/trace code are used.
private final class Ground {
    let world:SwiftRapierWorld
    var chassisColliders=Set<UInt64>(),otherColliders=Set<UInt64>(),cameraExcludedOtherColliders=Set<UInt64>()
    init(_ world:SwiftRapierWorld){self.world=world}
    func isCellLoaded(_ name:String)->Bool{true}
    func otherVehicleColliders(id:String)->Set<UInt64>{[]}
}
private final class Trace {var trace:((SIMD3<Float>,SIMD3<Float>,Float)->Float?)?}
private struct Legacy {
    var cameraExcludedColliderIDs=Set<UInt64>()
    func metadata(collider:UInt64)->Bool?{nil}
}
private final class Carrier {
    struct Character {struct Queries {let walker:UInt64,probe:UInt64};let queries:Queries?}
    let groundVehicle:Ground?
    var driving=true,isPassenger=false,isInterior=false,currentVehicleID:String?
    var character:Character?,legacyCollisionWorld:Legacy?
    var collisionRequests=NativeCollisionRequests(),activeDetails=Set<String>(),desiredPhysicsCells=Set<String>()
    var passiveCameraTrace:NativePassiveCameraTrace?,passiveCameraRay:NativePassiveCameraTrace.Ray?
    let gameCamera=Trace()
    init(_ world:SwiftRapierWorld){groundVehicle=Ground(world)}
    func loadCollision(name:String){}
    func loadWorldSharpIfNeeded(){}
    func bindTrace(){
        // ACTUAL_TRACE_ASSIGNMENT
    }
    func raw(_ at:SIMD3<Float>,policy:Bool)->Float?{cameraRay(from:at,direction:SIMD3(0,1,0),distance:6,originalVehiclePolicy:policy)}
    // ACTUAL_QUERY_METHODS
}
@main private enum CameraRoleTests {
    static func main(){
        do{try run();print("PASS native camera roles: \(checks) checks; literal trace/query and actual compact Rapier hulls, authored shapes and coverage/registry boundary; no UI/retail acceptance")}
        catch{print("FAIL \(error)");exit(1)}
    }
    static func run()throws {
        let world=SwiftRapierWorld(gravity:.zero)!,owner=NativeAmbientTrafficBodies(world:world)
        let car=NativeAmbientTrafficBodies.Snapshot(id:17,generation:1,model:420,position:SIMD3(20,20,3),heading:0,pitch:0)
        let shape=NativeAmbientTrafficBodies.Shape(kind:"sphere",centre:SIMD3(0,1,0),halfExtents:.zero,radius:0.5,friction:0.5,restitution:0,piece:1)
        owner.synchronize([car],near:SIMD3(20,20,3),enabled:true,shapes:{_ in [shape]})
        try require(world.step() && owner.colliders.count==1,"Actual compact hull setup")
        let renderer=Carrier(world);renderer.groundVehicle!.otherColliders=owner.colliders
        renderer.passiveCameraTrace=NativePassiveCameraTrace(directory:URL(fileURLWithPath:CommandLine.arguments[1]))
        renderer.bindTrace()
        let origin=SIMD3<Float>(20,17,4),direction=SIMD3<Float>(0,1,0)
        let driver=renderer.gameCamera.trace!(origin,direction,6)
        try require(driver.map{abs($0-2.5)<0.0001}==true,"Driver must see compact kinematic hull")
        try require(renderer.passiveCameraRay?.groups==0xffff0083 && renderer.passiveCameraRay?.vehiclePolicyApplied==true,"Driver trace dispatch")
        renderer.isPassenger=true;renderer.currentVehicleID="authored-seat"
        try require(renderer.gameCamera.trace!(origin,direction,6)==nil,"Passenger used driver collision mask")
        try require(renderer.passiveCameraRay?.groups==0xffff0001 && renderer.passiveCameraRay?.vehiclePolicyApplied==false,"Passenger used driver predicate policy")
        renderer.driving=false;renderer.isPassenger=false
        try require(renderer.gameCamera.trace!(origin,direction,6)==nil && renderer.passiveCameraRay?.groups==0xffff0001,"Foot mask changed")
        // A retained trace closure must consult the current seat/driver role.
        renderer.driving=true
        try require(renderer.gameCamera.trace!(origin,direction,6) != nil,"Passenger-to-driver retained old mask")
        renderer.isPassenger=true
        try require(renderer.gameCamera.trace!(origin,direction,6)==nil,"Driver-to-passenger retained old mask")
        renderer.isPassenger=false
        try require(renderer.raw(origin,policy:false) != nil && renderer.passiveCameraRay?.groups==0xffff0083,"Explicit legacy-driver solid-body policy changed")
        let wall=world.addBox(halfExtents:SIMD3(0.5,0.5,0.5),position:SIMD3(22,4,-20))!
        try require(world.setColliderGroups(wall,collision:0x0001ffff,solver:0xffffffff) && world.step(),"Actual static wall setup")
        renderer.isPassenger=true
        let wallHit=renderer.gameCamera.trace!(SIMD3(22,17,4),direction,6)
        try require(wallHit.map{abs($0-2.5)<0.0001}==true,"Passenger mask stopped colliding with world geometry")
        try require(owner.colliders.allSatisfy{world.colliderInfo($0) != nil},"Camera roles removed physical traffic contacts")
    }
}
