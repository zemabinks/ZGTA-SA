// SPDX-License-Identifier: AGPL-3.0-only
// Portable authored geometry only. No original game/archive fixture.
import Foundation
import simd
var checks=0
func check(_ value:Bool,_ label:String){checks+=1;precondition(value,label)}
func near(_ value:Double,_ expected:Double,_ label:String,_ epsilon:Double=0.00001){check(value.isFinite && abs(value-expected)<=epsilon,label)}
final class Ground {
 let world=SwiftRapierWorld(gravity:.zero)!
 var otherColliders=Set<UInt64>(),chassisColliders=Set<UInt64>(),ready=true
 func isCellLoaded(_ name:String)->Bool{ready}
}
final class Person {struct Queries{let walker:UInt64,probe:UInt64};var queries:Queries?}
final class Carrier {
 var groundVehicle:Ground?=Ground(),remoteSuspensionRayBudget=64,isInterior=false
 var character:Person?,collisionRequests=NativeCollisionRequests(),activeDetails=Set<String>(),desiredPhysicsCells=Set<String>(),loads=[String]()
 func loadCollision(name:String){loads.append(name)}
 // ACTUAL_CONTACT_METHOD
 func query(_ ray:NativeRemoteSuspension.Ray)->NativeRemoteSuspension.Contact{remoteSuspensionContact(ray)}
}
enum Transform {
 // ACTUAL_TRANSFORM_METHOD
}
let wheelRows:[[String:Any]]=[(true,true),(false,true),(true,false),(false,false)].map{front,left in
 ["centre":[left ? -0.9:0.9,0.45,front ? -1.6:1.6],"radius":0.35,"front":front,"left":left]
}
let row:[String:Any]=["id":420,"kind":"car","origin":0.8,"table":["flags":0,"upper":0.25,"lower": -0.15],"wheels":wheelRows]
let config=NativeRemoteSuspension.Configuration(row)!
for angle in [0.0,0.12,-0.18] {
 let carrier=Carrier(),world=carrier.groundVehicle!.world
 let rotation=simd_quatd(angle:angle,axis:SIMD3(0,0,1)),normal=SIMD3<Float>(rotation.act(SIMD3(0,1,0)))
 _=world.addBox(halfExtents:SIMD3(10,0.1,10),position: -normal*0.1,rotation:simd_quatf(vector:SIMD4<Float>(rotation.vector)))
 let selfBody=world.addBody(kind:.kinematicPosition,position:SIMD3(0,0.5,0))!
 _=world.addBox(halfExtents:SIMD3(2,0.05,3),body:selfBody)
 let dynamicBody=world.addBody(kind:.dynamic,position:SIMD3(0,0.3,0))!
 _=world.addBox(halfExtents:SIMD3(2,0.025,3),body:dynamicBody)
 world.step()
 let bodyBefore=world.bodyState(selfBody)!
 let matrix=Transform.transform(position:SIMD3(0,0.001,0),rotation:rotation,origin:config.origin)
 let frame=NativeRemoteSuspension.sample(config,model:matrix,query:carrier.query)!
 let n=SIMD3<Double>(SwiftRapierWorld.rapierToGTA(normal))
 for wheel in config.wheels {
  let local=wheel.centre+SIMD3(0,0,frame.offsets[wheel.index])
  let point=matrix*SIMD4<Float>(SIMD3<Float>(local),1)
  // Independent geometric contact condition, without reproducing the travel
  // formula: the posed tire sphere is tangent to the authored plane.
  near(simd_dot(n,SIMD3<Double>(Double(point.x),Double(point.y),Double(point.z)))-wheel.radius,0,"Posed tire is not tangent to plane")
 }
 let bodyAfter=world.bodyState(selfBody)!
 check(bodyBefore.position==bodyAfter.position && bodyBefore.rotation.vector==bodyAfter.rotation.vector,"Visual query changed authoritative body")
 for fps in [15,30,60,120,144] {for _ in 0..<3 {
  carrier.remoteSuspensionRayBudget=64
  let repeated=NativeRemoteSuspension.sample(config,model:matrix,query:carrier.query)!
  check(repeated.offsets==frame.offsets,"Frame schedule \(fps) altered travel")
 }}
 carrier.groundVehicle!.ready=false;carrier.remoteSuspensionRayBudget=64
 check(NativeRemoteSuspension.sample(config,model:matrix,query:carrier.query)==nil,"Unloaded collision manufactured ground")
 carrier.groundVehicle=nil
 check(NativeRemoteSuspension.sample(config,model:matrix,query:carrier.query)==nil,"No world manufactured ground")
}
let carrier=Carrier(),world=carrier.groundVehicle!.world
_=world.addBox(halfExtents:SIMD3(10,0.1,10),position:SIMD3(0,-0.1,0))
_=world.addBox(halfExtents:SIMD3(2,0.075,0.3),position:SIMD3(0,0.075,-1.6));world.step()
let matrix=Transform.transform(position:SIMD3(0,0.001,0),rotation:simd_quatd(angle:0,axis:SIMD3(0,1,0)),origin:config.origin)
let curb=NativeRemoteSuspension.sample(config,model:matrix,query:carrier.query)!
near(curb.offsets[0]-curb.offsets[1],0.15,"Independent front curb travel")
near(curb.offsets[2]-curb.offsets[3],0.15,"Independent opposite curb travel")
var airborne=matrix;airborne.columns.3.z+=3;carrier.remoteSuspensionRayBudget=64
let air=NativeRemoteSuspension.sample(config,model:airborne,query:carrier.query)!
check(air.contacts.allSatisfy{!$0},"Airborne contact invented")
for wheel in config.wheels{near(air.offsets[wheel.index],config.lower,"Airborne travel is not full droop",0)}
for kind in ["bike","boat","train","plane","heli"] {var unsupported=row;unsupported["kind"]=kind;check(NativeRemoteSuspension.Configuration(unsupported)==nil,"Unsupported rig class")}
var hydraulic=row;hydraulic["hydraulics"]=true;check(NativeRemoteSuspension.Configuration(hydraulic)==nil,"Hydraulic owner replaced")
var invalid=row;invalid["table"]=["flags":0,"upper": -1,"lower":1];check(NativeRemoteSuspension.Configuration(invalid)==nil,"Invalid travel metadata")
for contact:NativeRemoteSuspension.Contact in [.hit(distance:.nan,normal:SIMD3(0,0,1)),.hit(distance: -1,normal:SIMD3(0,0,1)),.hit(distance:100,normal:SIMD3(0,0,1)),.hit(distance:0,normal:.zero)] {
 check(NativeRemoteSuspension.sample(config,model:matrix,query:{_ in contact})==nil,"Malformed contact accepted")
}
var upsideDown=matrix;upsideDown.columns.1.y = -1;upsideDown.columns.2.z = -1
check(NativeRemoteSuspension.sample(config,model:upsideDown,query:{_ in .clear})==nil,"Upside-down car projected")
carrier.remoteSuspensionRayBudget=0
if case .unavailable=carrier.query(.init(origin:SIMD3(0,0,1),direction:SIMD3(0,0,-1),distance:2)){checks+=1}else{fatalError("Query budget bypassed")}
let obstructed=Carrier(),obstructedWorld=obstructed.groundVehicle!.world
_=obstructedWorld.addBox(halfExtents:SIMD3(2,0.05,2),position:SIMD3(0,-0.05,0))
for index in 0..<17 {
 let body=obstructedWorld.addBody(kind:.kinematicPosition,position:SIMD3(0,0.9-Float(index)*0.025,0))!
 _=obstructedWorld.addBox(halfExtents:SIMD3(1,0.005,1),body:body)
}
obstructedWorld.step()
if case .unavailable=obstructed.query(.init(origin:SIMD3(0,0,1),direction:SIMD3(0,0,-1),distance:2)){checks+=1}else{fatalError("Obstruction limit fabricated known-clear coverage")}
let flat=NativeRemoteSuspension.sample(config,model:matrix,tyres:[1,0,0,0],query:{_ in .hit(distance:0.6,normal:SIMD3(0,0,1))})!
near(flat.offsets[0],config.upper+0.35*0.75-0.6,"Flat tire effective radius")
let missing=NativeRemoteSuspension.sample(config,model:matrix,tyres:[2,0,0,0],query:{_ in .hit(distance:0.6,normal:SIMD3(0,0,1))})!
near(missing.offsets[0],config.lower,"Missing wheel cannot claim support",0)
check(!missing.contacts[0],"Missing wheel marked contact")
print("PASS portable authored remote-suspension: \(checks) checks; real native Rapier, planes/curb, moving self-colliders, unloaded world and frame schedules. No original game input.")
