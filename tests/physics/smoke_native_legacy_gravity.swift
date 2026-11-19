// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
import ZGTARapier

private enum Failed:Error {case check(String)}
private var checks=0
private func check(_ v:Bool,_ label:String)throws {checks+=1;if !v{throw Failed.check(label)}}
private func near(_ a:Double,_ b:Double,_ tolerance:Double,_ label:String)throws {
    try check(a.isFinite && b.isFinite && abs(a-b)<=tolerance,"\(label): \(a), expected \(b)")
}
private struct CameraFrame {var source=SIMD3<Float>.zero,target=SIMD3<Float>(0,1,0)}
private struct FollowCameraBoundary {
    var resets=0
    mutating func resetFoot(heading:Float,pitch:Float){resets+=1}
    mutating func beginVehicle(){}
}
private final class RendererOwner {
    let groundVehicle:NativeGroundVehicle?=NativeGroundVehicle()
    var legacyGravity:Float?,legacyCameraSample:NativeSAMPGameCamera.Sample?,gameCameraFrame:CameraFrame?
    var legacyGameCamera=NativeSAMPGameCamera(),gameCamera=FollowCameraBoundary()
    var actorHeading:Float=0,cameraPitch:Float=0,legacyCameraSubject:NativeSAMPGameCamera.Subject?
    var legacySpectatorAccumulator=0.0,status=[String]()
    var onStatus:((String)->Void)?
    init(){onStatus={[weak self] in self?.status.append($0)}}
    // ACTUAL_RECEIVE_LEGACY_GAMEPLAY
}
private final class FloorQueryBoundary {
    func height(x:Float,y:Float,near:Float,maxDrop:Float)->Float?{0}
}
private final class FallbackOwner {
    var driving=false,verticalSpeed:Float=0,legacyGravity:Float?,camera=SIMD3<Float>.zero
    var collision:FloorQueryBoundary?,landings=0
    var onLand:(()->Void)?
    init(){onLand={[weak self] in self?.landings+=1}}
    func step(delta:Float) {
        if driving{return}
        // ACTUAL_FALLBACK_BRANCH
    }
}
private func fallback()throws {
    let lift=FallbackOwner();lift.legacyGravity = -0.004;lift.step(delta:1/60)
    try near(Double(lift.verticalSpeed),Double(Float(0.004))*2500/60,0.000001,"Fallback signed gravity units")
    try check(lift.camera.z>0 && lift.landings==0,"Fallback inverted force stayed snapped to ground")
    for gravity:Float? in [nil,0,0.004] {
        let owner=FallbackOwner();owner.legacyGravity=gravity;owner.camera.z=10;owner.verticalSpeed=2;owner.step(delta:1/60)
        let acceleration=gravity.map{Double($0)*2500} ?? 9.8
        try near(Double(owner.verticalSpeed),2-acceleration/60,0.000001,"Fallback airborne profile")
        owner.driving=true;let before=(owner.camera,owner.verticalSpeed);owner.step(delta:1/60)
        try check(owner.camera==before.0 && owner.verticalSpeed==before.1,"Fallback took vehicle motion ownership")
    }
    let land=FallbackOwner();land.collision=FloorQueryBoundary();land.camera.z=0.001;land.verticalSpeed = -1;land.legacyGravity=0.008
    land.step(delta:1/60);try check(land.camera.z==0 && land.verticalSpeed==0 && land.landings==1,"Fallback landing contract")
}
private func definition(_ kind:String)->[String:Any] {
    var wheels:[[String:Any]]=[]
    for front in [true,false]{for left in [true,false]{wheels.append(["centre":[left ? -0.65:0.65,0.0,front ? 1.0:-1.0],"radius":0.36,"front":front,"left":left])}}
    var row:[String:Any]=["id":900,"solverSupported":true,"kind":kind,"origin":0.55,
        "table":["mass":1100.0,"turnMass":2600.0,"drag":0.0,"damping":0.0],"wheels":wheels,
        "chassis":[["kind":"box","centre":[0.0,0.0,0.0],"halfExtents":[0.7,0.32,1.3],"friction":0.0]],
        "bounds":["box":["min":[-0.7,-1.3,-0.32],"max":[0.7,1.3,0.32]]]]
    if kind=="bike" {
        row["hubs"]=["front":["at":[0.0,1.0,0.0],"radius":0.36],"rear":["at":[0.0,-1.0,0.0],"radius":0.36]]
        row["bike"]=[String:Double]()
    }
    return row
}
private func rawWorld()throws {
    try check(zgtaphys_world_set_gravity(nil,0,-20,0)==0,"Null C world accepted")
    let raw=zgtaphys_world_new(0,-18,0)!
    defer{zgtaphys_world_free(raw)}
    for bad:Float in [.nan,.infinity,-.infinity] {
        try check(zgtaphys_world_set_gravity(raw,bad,0,0)==0,"Raw C setter accepted nonfinite acceleration")
    }
    try check(zgtaphys_world_set_gravity(raw,0,-20,0)==1,"Raw C setter refused finite acceleration")
    let w=SwiftRapierWorld(gravity:SIMD3(0,-18,0))!
    try check(w.setLegacyGravity(0),"Zero gravity rejected")
    let b=w.addBody(position:SIMD3(0,100,0),gravityScale:1)!
    try check(w.recomputeMassProperties(b),"Body mass")
    w.setVelocities(b,linear:SIMD3(1,2,3),angular:SIMD3(0.1,0.2,0.3))
    let before=w.bodyState(b)!
    for value:Float in [.nan,.infinity,-.infinity,51,-51] {
        try check(!w.setLegacyGravity(value) && w.legacyGravity==0,"Bad gravity altered context")
    }
    try check(w.setLegacyGravity(0.016),"Gravity setter")
    let after=w.bodyState(b)!
    try check(before.position==after.position && before.rotation.vector==after.rotation.vector && before.linearVelocity==after.linearVelocity && before.angularVelocity==after.angularVelocity,"Setter changed pose/momentum")
    try check(w.step(),"Actual step")
    try near(Double(w.bodyState(b)!.linearVelocity.y),2-Double(Float(0.016))*2500/60,0.00001,"C/Rapier acceleration exactly once")
    try check(w.setLegacyGravity(nil) && w.legacyGravity==nil,"Context reset")
    let speed=w.bodyState(b)!.linearVelocity.y;w.step()
    try near(Double(w.bodyState(b)!.linearVelocity.y),Double(speed)-18/60,0.00001,"Initial world vector restored")
    let remote=w.addBody(kind:.kinematicPosition,position:SIMD3(3,30,4))!
    w.setNextKinematicPose(remote,position:SIMD3(4,31,5));w.setLegacyGravity(-0.008);w.step()
    try check(w.bodyState(remote)!.position==SIMD3(4,31,5),"Gravity integrated remote authoritative pose")
}
private func motorClocks()throws {
    for value:Float in [0,0.004,0.008,0.016,-0.008] {
        var baseline:NativeCharacterController.Output?
        for fps in [15,30,60,120,144] {
            let world=SwiftRapierWorld(gravity:SIMD3(0,-18,0))!,owner=NativeCharacterController(world:world)!
            world.setLegacyGravity(value);owner.reset(feet:SIMD3(0,0,100))
            for _ in 0..<fps {owner.update(delta:1/Double(fps),displacement:SIMD3(2/Float(fps),0,0),geometryReady:true)}
            let end=owner.state
            try near(Double(end.feet.x),2,0.0001,"Input travel preserved")
            if let baseline {
                try check(simd_distance(end.feet,baseline.feet)<0.0004,"Display rate changed fixed-step position")
                try near(end.rising,baseline.rising,1e-8,"Display rate changed fall velocity")
            }else{baseline=end}
            let old=(owner.state.feet,owner.state.rising,owner.stepVelocity)
            world.setLegacyGravity(0.016)
            try check(owner.state.feet==old.0 && owner.state.rising==old.1 && owner.stepVelocity==old.2,"Midair change reset physical clock/momentum")
            owner.update(delta:1/60,displacement:.zero,verticalOverride:3,geometryReady:true)
            try near(owner.state.rising,3,0.000001,"Gravity took vertical task ownership")
            owner.update(delta:1/60,displacement:.zero,geometryReady:true)
            try check(owner.state.rising<3 && owner.state.rising>2.3,"Task exit ignored current force context")
        }
        let world=SwiftRapierWorld(gravity:.zero)!,owner=NativeCharacterController(world:world)!
        world.setLegacyGravity(value);owner.reset(feet:SIMD3(0,0,100))
        owner.update(delta:1/60,displacement:.zero,geometryReady:true)
        // At rest the first drag correction is below 1e-4 world units/s.
        // This analytic force bound detects unit, sign and double-force errors.
        try near(owner.state.rising,-Double(value)*2500/60,0.0001,"Normalized gravity units")
    }
    let world=SwiftRapierWorld(gravity:.zero)!,owner=NativeCharacterController(world:world)!
    owner.reset(feet:SIMD3(0,0,100),grounded:true);world.setLegacyGravity(-0.008)
    owner.update(delta:1/60,displacement:.zero,geometryReady:true)
    try check(owner.state.rising>0 && owner.state.feet.z>100,"Inverted force stuck in prior standing state")
}
private func vehicles()throws {
    for kind in ["car","bike"] {for value:Float in [0,0.004,0.008,0.016,-0.008] {
        let row=definition(kind),d=NativeGroundVehicle.Definition(row)!,world=SwiftRapierWorld(gravity:SIMD3(0,-18,0))!
        world.setLegacyGravity(value)
        let pose=NativeUnattendedVehicle.Pose(position:SIMD3(0,100,0),rotation:.init(angle:0,axis:SIMD3(0,1,0)))
        let parked=NativeUnattendedVehicle(world:world,definition:d,pose:pose,health:1000,damage:"")!
        parked.beforeStep(delta:1/60);world.step();parked.afterStep(delta:1/60,reference:pose)
        try near(Double(parked.state!.linearVelocity.y),-Double(value)*2500/60,0.00001,"Promoted \(kind) base gravity exactly once")
        try near(parked.damage.health,1000,0.00001,"Gravity manufactured parked impact damage")
        parked.dispose()
        let driven=NativeGroundVehicle()!
        let catalog=try JSONSerialization.data(withJSONObject:["models":["900":row],"materialClasses":[Int](repeating:0,count:256)])
        try check(driven.loadDefinitions(catalog)==1,"Authored driver catalog")
        driven.installCell("authored",data:Data([0x53,0x43,0x4c,0x32]+[UInt8](repeating:0,count:12)))
        try check(driven.isCellLoaded("authored") && driven.enter(model:"900",modelPosition:SIMD3(0,0,100),heading:0),"Actual driver admission")
        driven.world.setLegacyGravity(value);driven.update(delta:1/60,input:.init(),currentCell:"authored")
        try near(Double(driven.nativeLinearVelocity.z),-Double(value)*2500/60,0.00001,"Driven \(kind) base gravity exactly once")
        driven.exit()
    }}
}
private func vehicleClocks()throws {
    for kind in ["car","bike"] {for value:Float in [0.004,0.016] {
        var baseline:(SIMD3<Float>,SIMD3<Float>)?
        for fps in [15,30,60,120,144] {
            let driver=NativeGroundVehicle()!,row=definition(kind)
            let catalog=try JSONSerialization.data(withJSONObject:["models":["900":row],"materialClasses":[Int](repeating:0,count:256)])
            try check(driver.loadDefinitions(catalog)==1,"Clock vehicle catalog")
            driver.installCell("authored",data:Data([0x53,0x43,0x4c,0x32]+[UInt8](repeating:0,count:12)))
            try check(driver.enter(model:"900",modelPosition:SIMD3(0,0,100),heading:0),"Clock driver admission")
            driver.world.setLegacyGravity(value)
            var ticks=0;driver.onKinematicStep={_ in ticks+=1}
            for _ in 0..<fps {driver.update(delta:1/Double(fps),input:.init(),currentCell:"authored")}
            let position=driver.modelPosition,velocity=driver.nativeLinearVelocity
            try check(ticks==60,"Display rate changed vehicle step count")
            try near(Double(velocity.z),-Double(value)*2500,0.0001,"One-second driven gravity units")
            if let baseline {
                try check(simd_distance(position,baseline.0)<0.0004 && simd_distance(velocity,baseline.1)<0.0001,"Display rate changed driven trajectory")
            }else{baseline=(position,velocity)}
            driver.exit()
        }
    }}
}
private func renderer()throws {
    let owner=RendererOwner(),world=owner.groundVehicle!.world
    func event(_ g:UInt64,_ s:UInt64,_ c:NativeSAMPGameplayCommands.Command){owner.receiveLegacyGameplay(.init(generation:g,sequence:s,command:c))}
    event(1,0,.reset);let resets=owner.gameCamera.resets
    event(1,1,.gravity(0.004));try check(world.legacyGravity==0.004 && owner.legacyGravity==0.004,"Actual renderer dropped gravity")
    event(1,1,.gravity(0.016));event(0,200,.gravity(0.016))
    try check(world.legacyGravity==0.004 && owner.gameCamera.resets==resets,"Duplicate/stale gravity changed force or camera")
    event(1,2,.gravity(.nan));try check(world.legacyGravity==0.004,"Malformed force changed world")
    event(1,3,.gravity(0));try check(world.legacyGravity==0,"Zero force lost")
    event(2,0,.reset);try check(world.legacyGravity==nil && owner.legacyGravity==nil,"Retired connection leaked force")
    event(1,999,.gravity(-0.008));try check(world.legacyGravity==nil,"Old callback restored retired force")
}
@main private struct GravityGate {
    static func main(){do{try rawWorld();try motorClocks();try vehicles();try vehicleClocks();try renderer();try fallback();print("PASS \(checks) actual native gravity/world/motor/driver/parked/renderer checks; authored geometry, no retail claim")}catch{print("FAIL \(checks) \(error)");exit(2)}}
}
