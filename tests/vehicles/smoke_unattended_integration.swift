import Foundation
import simd
@main enum UnattendedIntegrationSmoke {
 static func main() throws {
  let base=URL(fileURLWithPath:CommandLine.arguments[1]),data=try Data(contentsOf:base.appendingPathComponent("local-only/site/game/native/vehicles.physics.json")),manager=NativeGroundVehicle()!
  precondition(manager.loadDefinitions(data)==212)
  var flat=Data()
  func word(_ n:UInt32){var value=n.littleEndian;withUnsafeBytes(of:&value){flat.append(contentsOf:$0)}}
  [UInt32(0x324c4353),4,2,1].forEach(word)
  for value:Float in [-1000,-1000,0,1000,-1000,0,1000,1000,0,-1000,1000,0]{word(value.bitPattern)}
  [UInt32(0),1,2,0,2,3].forEach(word);flat.append(contentsOf:[2,2,0,0,1,1,0,0]);manager.installCell("floor",data:flat)
  let source=NativeOtherVehicles.Pose(id:"parked",code:"410.6.1.0.",position:SIMD3(3,0,1.1),heading:0,pitch:0,roll:0)
  var packets=0,changes=0;manager.onOtherMove={_,_ in packets += 1};manager.onOtherCollidersChanged={changes += 1}
  func sync(){manager.synchronizeOtherVehicles([source],excluding:nil,near:.zero,delta:1/60)}
  sync();precondition(abs(manager.otherVehicle("parked")!.position.z)<0.01)
  for frame in 0..<300 {
   sync()
   if (20..<80).contains(frame),let collider=manager.otherColliders.first,let body=manager.world.colliderInfo(collider)?.body {
    let at=SwiftRapierWorld.gtaToRapier(manager.otherVehicle("parked")!.position)
    manager.shoveOtherVehicle(body:body,direction:SIMD2(1,0),point:SIMD3<Double>(at)+SIMD3(0.5,0.5,0),speed:1.4)
   }
   manager.world.step()
  }
  let shifted=manager.otherVehicle("parked")!
  precondition(shifted.position.x>3.05 && abs(shifted.position.z)<0.03 && packets>0 && changes>=2)
  let handoff=manager.takeOtherVehicle("parked")!;precondition(manager.otherColliders.isEmpty)
  let modelPosition=handoff.position+NativeGroundVehicle.modelOffset(origin:manager.modelOrigin("410")!,heading:handoff.heading,pitch:handoff.pitch,roll:handoff.roll)
  precondition(manager.enter(model:"410",modelPosition:modelPosition,heading:handoff.heading,pitch:handoff.pitch,roll:handoff.roll,bodyPose:handoff.physicalPose))
  precondition(simd_distance(manager.bodyPosition,handoff.position)<1e-6)
  manager.parkCurrentVehicle(id:"parked",code:source.code,health:1000,damage:handoff.damage,work:0)
  precondition(!manager.active && !manager.otherColliders.isEmpty)
  let parked=manager.otherVehicle("parked")!;precondition(simd_distance(parked.position,handoff.position)<1e-6)
  manager.world.step()
  print("PASS shared-world parked floor alignment, walking shove, hooks, vmove callback, predicted handoff/exit;",packets,"packets,",changes,"collider-set changes")
 }
}
