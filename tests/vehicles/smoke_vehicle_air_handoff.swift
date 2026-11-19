import Foundation
import simd

@main enum VehicleAirHandoff {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  let rows=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [[String:Any]]
  var checks=0,maxError=0.0
  func check(_ value:Bool,_ label:String){precondition(value,label);checks += 1}
  for row in rows {
   let kind=row["kind"] as! String,fps=(row["fps"] as! NSNumber).doubleValue
   var value=(row["initial"] as! NSNumber).doubleValue
   for expected in row["frames"] as! [NSNumber] {
    value=NativeFlightDynamics.stoppedTurning(kind:kind,amount:value,ticks:50/fps)
    let error=abs(value-expected.doubleValue);maxError=max(maxError,error)
    check(error<1e-12,"Actual89888.s2 rotor coast differs")
   }
  }
  let data=try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/vehicles.physics.json"))
  var floor=Data()
  func word(_ value:UInt32){var little=value.littleEndian;withUnsafeBytes(of:&little){floor.append(contentsOf:$0)}}
  [UInt32(0x324c4353),4,2,1].forEach(word)
  for value:Float in [-1000,-1000,0,1000,-1000,0,1000,1000,0,-1000,1000,0]{word(value.bitPattern)}
  [UInt32(0),1,2,0,2,3].forEach(word);floor.append(contentsOf:[2,2,0,0,1,1,0,0])
  for model in ["487","519","520"] {
   let fleet=NativeGroundVehicle()!;precondition(fleet.loadDefinitions(data)==212);fleet.installCell("floor",data:floor)
   precondition(fleet.enter(model:model,modelPosition:SIMD3(0,0,1000),heading:0.4))
   var input=NativeVehicleDynamics.Input();input.throttle=0.8
   for _ in 0..<180 {fleet.update(delta:1/60,input:input,currentCell:"floor")}
   let rotor=Double(fleet.rotorTurning)
   check(rotor>0,"Aircraft failed to start rotor/propeller")
   if model != "487" {fleet.setLandingGear(true)}
   let gear=fleet.landingGearUp,linear=fleet.nativeLinearVelocity,angular=fleet.nativeAngularVelocity,position=fleet.bodyPosition
   let oldColliders=fleet.chassisColliders
   fleet.parkCurrentVehicle(id:"air",code:model,health:1000,damage:"",work:0)
   let parked=fleet.otherVehicle("air")!,body=fleet.otherColliders.first.flatMap{fleet.world.colliderInfo($0)?.body}!,state=fleet.world.bodyState(body)!
   check(!fleet.active && parked.dynamic,"Parking failed to transfer aircraft")
   check(oldColliders.allSatisfy{fleet.world.colliderInfo($0)==nil},"Parking retained owned hull")
   check(simd_distance(parked.position,position)<1e-5,"Parking changed physical position")
   check(SwiftRapierWorld.rapierToGTA(state.linearVelocity)==linear && SwiftRapierWorld.rapierToGTA(state.angularVelocity)==angular,"Parking changed linear/angular momentum")
   // The public audio accessor is Float; the retained physical state is Double.
   check(abs(parked.rotor-rotor)<1e-7 && parked.gearUp==gear,"Parking lost rotor or raised gear")
   func checkRenderer(_ snapshot:NativeOtherVehicles.Snapshot) {
    var initial=NativeVehicleRig.Input();initial.rotor=0.67;initial.gearUp = !snapshot.gearUp
    initial.frontSpin=17;initial.rearSpin = -13;initial.offsets=[9,8,7,6]
    let actual=rendererAirInput(fleet,id:"air",player:nil,model:Int(model)!,initial:initial)
    check(actual.rotor==snapshot.rotor && actual.gearUp==snapshot.gearUp,"Actual renderer omitted parked rotor/gear")
    if snapshot.dynamic {
     check(actual.frontSpin==snapshot.frontSpin && actual.rearSpin==snapshot.rearSpin && actual.offsets==snapshot.offsets,"Actual renderer omitted dynamic parked wheels")
    } else {
     check(actual.frontSpin==initial.frontSpin && actual.rearSpin==initial.rearSpin && actual.offsets==initial.offsets,"Demoted renderer overwrote nonphysical wheel history")
    }
    for gearFlag:Float in [0,1] {
     let player=RendererAirPlayer(kit:[0,0,0,0,0,0.42,gearFlag])
     let remote=rendererAirInput(fleet,id:"air",player:player,model:Int(model)!,initial:initial)
     check(remote.gearUp==(gearFlag != 0),"Parked gear stomped live remote kit")
     check(remote.rotor==initial.rotor && remote.frontSpin==initial.frontSpin && remote.rearSpin==initial.rearSpin && remote.offsets==initial.offsets,"Parked snapshot stomped live remote rig")
     if model=="520" {check(abs(remote.nozzle-2100)<0.001,"Live remote Hydra kit was not applied")}
    }
    let absent=rendererAirInput(fleet,id:"not-present",player:nil,model:Int(model)!,initial:initial)
    check(absent.rotor==initial.rotor && absent.gearUp==initial.gearUp && absent.offsets==initial.offsets,"Absent parked snapshot overwrote rig state")
   }
   checkRenderer(parked)
   var source=NativeOtherVehicles.Pose(id:"air",code:model,position:parked.position,heading:parked.heading,pitch:parked.pitch,roll:parked.roll)
   source.kept=true
   fleet.synchronizeOtherVehicles([source],excluding:nil,near:parked.position,delta:0)
   let demoted=fleet.otherVehicle("air")!
   check(!demoted.dynamic && demoted.rotor==parked.rotor && demoted.gearUp==gear,"Authority demotion dropped aircraft state")
   checkRenderer(demoted)
   var expected=demoted.rotor
   for _ in 0..<45 {
    expected=NativeFlightDynamics.stoppedTurning(kind:model=="487" ? "heli":"plane",amount:expected,ticks:50.0/60)
    fleet.synchronizeOtherVehicles([source],excluding:nil,near:parked.position,delta:1/60)
    let frame=fleet.otherVehicle("air")!
    check(!frame.dynamic && frame.rotor==expected && frame.gearUp==gear,"Kinematic parked coast/gear drifted")
   }
   source.kept=false
   fleet.synchronizeOtherVehicles([source],excluding:nil,near:parked.position,promoteNear:parked.position,delta:0)
   let promoted=fleet.otherVehicle("air")!
   check(promoted.dynamic && promoted.rotor==expected && promoted.gearUp==gear,"Re-promotion lost aircraft state")
   checkRenderer(promoted)
   let handoff=fleet.takeOtherVehicle("air")!
   check(fleet.otherColliders.isEmpty && fleet.otherVehicle("air")==nil,"Taking aircraft retained parked hull")
   let modelPosition=SIMD3<Float>(handoff.transform[3].x,handoff.transform[3].y,handoff.transform[3].z)
   precondition(fleet.enter(model:model,modelPosition:modelPosition,heading:handoff.heading,bodyPose:handoff.physicalPose))
   check(!fleet.landingGearUp && fleet.rotorTurning==0 && fleet.nativeLinearVelocity == .zero && fleet.nativeAngularVelocity == .zero,"Fresh owned entry does not match browser place/tp reset policy")
   fleet.exit();fleet.clearOtherVehicles()
   fleet.synchronizeOtherVehicles([source],excluding:nil,near:parked.position,promoteNear:parked.position,delta:0)
   let replacement=fleet.otherVehicle("air")!
   check(replacement.rotor==0 && !replacement.gearUp,"Same-id new aircraft inherited old equipment state")
   fleet.clearOtherVehicles()
  }
  print("PASS native aircraft handoffs: \(checks) checks, actual rotor maxerror \(maxError); momentum, gear, demotion/re-promotion, actual Renderer glue and live kit dominance")
 }
}
