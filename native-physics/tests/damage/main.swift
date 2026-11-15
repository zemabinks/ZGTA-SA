import Foundation
import simd

func vector(_ raw:Any)->SIMD3<Float>{let a=raw as! [Double];return SIMD3(Float(a[0]),Float(a[1]),Float(a[2]))}
let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
var count=0,maxPosition:Float=0,maxHealth=0.0,maxDoor=0.0,maxForce=0.0,maxPoint=0.0,totalEvents=0
for scenario in fixture["cases"] as! [[String:Any]]{
 let name=scenario["name"] as! String,floor=scenario["floor"] as! Bool,sphere=scenario["sphere"] as! Bool,mass=scenario["mass"] as! Double
 let world=SwiftRapierWorld(gravity:SIMD3(0,floor ? -9.81:0,0))!
 let other=world.addBox(halfExtents:floor ? SIMD3(30,0.1,30):SIMD3(30,30,0.5),position:floor ? .zero:SIMD3(0,0,-10))!
 world.setColliderSurface(other,surface:2,material:Int32(scenario["material"] as! Int))
 let body=world.addBody(position:SIMD3(0,floor ? 8:0,0),mass:.init(value:Float(mass),turnMass:3500),gravityScale:1)!
 world.setVelocities(body,linear:SIMD3(0,floor ? -5:0,floor ? 0:-30),angular:.zero)
 let shape=sphere ? world.addSphere(radius:0.8,body:body)!:world.addBox(halfExtents:SIMD3(1,0.6,2),body:body)!
 world.setColliderPiece(shape,piece:Int32(scenario["piece"] as! Int));world.setColliderSurface(shape,surface:2,material:63);world.setContactForceEvents(shape)
 let controller=NativeVehicleDamageController(world:world,mass:mass,collisionDamage:0.65,maxX:1,flags:0,model:420,origin:scenario["origin"] as! Double,flight:scenario["flight"] as! Bool)
 controller.random={0.37};controller.isOtherVehicle={_ in scenario["otherVehicle"] as! Bool};controller.isRhino={_ in scenario["rhino"] as! Bool}
 controller.hinges=Dictionary(uniqueKeysWithValues:(scenario["hinges"] as! [[Double]]).enumerated().map{($0.offset,SIMD3<Double>($0.element[0],$0.element[1],$0.element[2]))})
 controller.state.letGo(0,angle:0.6);controller.state.letGo(2,angle:-0.8)
 var events:[NativeVehicleDamage.Event]=[];controller.onEvents={e,_ in events += e}
 for (index,frame) in (scenario["frames"] as! [[String:Any]]).enumerated(){
  events=[];let before=world.bodyState(body)!;world.step();let now=world.bodyState(body)!
  controller.step(previous:before,current:now,contacts:world.drainContactForceEvents(),chassis:[shape],delta:1/60)
  maxPosition=max(maxPosition,simd_distance(now.position,vector(frame["position"]!)))
  maxHealth=max(maxHealth,abs(controller.state.health-(frame["health"] as! Double)))
  precondition(controller.state.text()==frame["text"] as! String,"\(name) frame\(index) damage text")
  for (a,e) in zip(controller.state.doors,frame["doors"] as! [Double]){maxDoor=max(maxDoor,abs(a.angle-e))}
  let expected=frame["events"] as! [[String:Any]];precondition(events.count==expected.count,"\(name) frame\(index) event count")
  for (actual,row) in zip(events,expected){
   precondition(actual.type==row["type"] as! String && actual.part==row["part"] as? Int,"\(name) event identity")
   if let force=row["force"] as? Double{maxForce=max(maxForce,abs((actual.force ?? -1)-force))}
   if let point=row["point"] as? [Double]{let p=SIMD3(point[0],point[1],point[2]);maxPoint=max(maxPoint,simd_distance(actual.point!,p))}
   totalEvents += 1
  }
  count += 1
 }
}
precondition(maxPosition<1e-6 && maxHealth<1e-6 && maxDoor<1e-8 && maxForce<1e-6 && maxPoint<1e-6,"Integrated damage mismatch: p\(maxPosition), hp\(maxHealth), door\(maxDoor), force\(maxForce), point\(maxPoint)")
precondition(totalEvents>0)
let report:[String:Any]=["frames":count,"events":totalEvents,"maxPositionError":maxPosition,"maxHealthError":maxHealth,"maxDoorAngleError":maxDoor,"maxForceError":maxForce,"maxPointError":maxPoint]
try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
print("PASS actual62540/66242 contact damage integration: \(count) frames / \(totalEvents) events; health error \(maxHealth), door \(maxDoor), contact point \(maxPoint)")
