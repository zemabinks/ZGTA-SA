import Foundation
import simd

let document=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
let cases=document["cases"] as! [[String:Any]]
var checks=0,maxError=0.0,maxContactError=0.0,maxColliderError=0.0,maxRayError=0.0,contactEvents=0,wholeWorldCompared=0
var queryTimingDifferences:[[String:Any]]=[]
func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
func values(_ actual:SwiftRapierWorld.BodyState)->[Float]{
    [actual.position.x,actual.position.y,actual.position.z,
     actual.rotation.imag.x,actual.rotation.imag.y,actual.rotation.imag.z,actual.rotation.real,
     actual.linearVelocity.x,actual.linearVelocity.y,actual.linearVelocity.z,
     actual.angularVelocity.x,actual.angularVelocity.y,actual.angularVelocity.z]
}
func compare(_ actual:SwiftRapierWorld.BodyState,_ expected:[NSNumber],_ label:String){
    let values=values(actual)
    for i in values.indices {
        let error=abs(Double(values[i])-expected[i].doubleValue);maxError=max(maxError,error)
        check(error<0.00002,"\(label)[\(i)] error\(error)")
    }
}
for (index,row) in cases.enumerated(){
    let masses=(row["masses"] as! [NSNumber]).map(\.doubleValue),contacts=row["contacts"] as! Bool
    let world=SwiftRapierWorld(gravity:.zero)!
    let a=world.addBody(position:.zero,mass:.init(value:Float(masses[0]),turnMass:Float(masses[0])))!
    let b=world.addBody(position:SIMD3(0,0,-2),mass:.init(value:Float(masses[1]),turnMass:Float(masses[1])))!
    for body in [a,b]{check(world.addBox(halfExtents:SIMD3(0.4,0.3,0.7),body:body,friction:0,restitution:0) != nil,"Collider")}
    var joint=world.createSphericalJoint(body1:a,body2:b,anchor1:SIMD3(0,0,-1),anchor2:SIMD3(0,0,1),contactsEnabled:contacts)
    check(joint != nil,"Joint");check(world.step(),"Initial mass step")
    let frames=row["frames"] as! [[String:Any]]
    for (frame,expected) in frames.enumerated(){
        if frame<100{check(world.applyImpulse(SIMD3(Float(masses[0]*0.002),0,Float(-masses[0]*0.01)),to:a),"Forward impulse")}
        if frame>=100 && frame<180{check(world.applyImpulse(SIMD3(Float(-masses[0]*0.001),0,Float(masses[0]*0.007)),to:a),"Reverse impulse")}
        if frame==30{check(world.applyTorqueImpulse(SIMD3(0,Float(masses[0]*0.1),0),to:a),"Turn")}
        if frame==60{check(world.setJointAnchor1(joint!,anchor:SIMD3(0.1,0.2,-1)),"Move anchor")}
        if frame==120{
            let before=world.bodyState(b)!,old=joint!;check(world.removeJoint(old),"Release");joint=nil
            let after=world.bodyState(b)!
            check(before.linearVelocity==after.linearVelocity && before.angularVelocity==after.angularVelocity,"Release reset momentum")
            check(!world.jointExists(old),"Removed ID remained valid")
        }
        if frame==150{joint=world.createSphericalJoint(body1:a,body2:b,anchor1:SIMD3(0.1,0.2,-1),anchor2:SIMD3(0,0,1),contactsEnabled:contacts)}
        check(world.step(),"Step")
        compare(world.bodyState(a)!,expected["a"] as! [NSNumber],"case\(index) frame\(frame) A")
        compare(world.bodyState(b)!,expected["b"] as! [NSNumber],"case\(index) frame\(frame) B")
        check((joint != nil)==expected["joint"] as! Bool,"Joint lifetime")
        if let id=joint {
            let state=world.sphericalJointState(id)!
            check(state.body1==a && state.body2==b && state.contactsEnabled==contacts,"Joint state ownership")
        }
    }
    let removed=joint!;check(world.removeBody(b),"Remove endpoint");check(!world.jointExists(removed),"Body cleanup")
    let replacement=world.addBody(position:SIMD3(0,0,-2))!
    let new=world.createSphericalJoint(body1:a,body2:replacement,anchor1:.zero,anchor2:.zero)!
    check(new != removed && !world.jointExists(removed),"Old opaque ID revived")
    check(!world.setJointAnchor1(new,anchor:SIMD3(.nan,0,0)),"Nonfinite anchor accepted")
}
let overlap=document["overlap"] as! [[String:Any]]
for (index,row) in overlap.enumerated(){
    let contacts=row["contacts"] as! Bool,world=SwiftRapierWorld(gravity:.zero)!
    let bodies=[world.addBody(position:.zero)!,world.addBody(position:SIMD3(0.5,0,0))!]
    let colliders=bodies.map{world.addBox(halfExtents:SIMD3(repeating:0.5),body:$0,friction:0,restitution:0)!}
    for collider in colliders{check(world.setContactForceEvents(collider),"Overlap force events")}
    let joint=world.createSphericalJoint(body1:bodies[0],body2:bodies[1],anchor1:SIMD3(0.25,0,0),anchor2:SIMD3(-0.25,0,0),contactsEnabled:contacts)!
    check(world.sphericalJointState(joint)?.contactsEnabled==contacts,"Overlap contact flag")
    let frames=row["frames"] as! [[String:Any]];var count=0,response:Float=0
    for (frame,expected) in frames.enumerated(){
        check(world.step(),"Overlap step")
        compare(world.bodyState(bodies[0])!,expected["a"] as! [NSNumber],"overlap\(index) frame\(frame) A")
        compare(world.bodyState(bodies[1])!,expected["b"] as! [NSNumber],"overlap\(index) frame\(frame) B")
        let events=world.drainContactForceEvents(),reference=expected["events"] as! [[String:Any]]
        check(events.count==reference.count,"Overlap force event count frame\(frame)")
        for (event,sample) in zip(events,reference){
            let first=sample["first"] as! Int,second=sample["second"] as! Int
            check(event.collider1==colliders[first] && event.collider2==colliders[second],"Overlap collider event order")
            check(event.body1==bodies[first] && event.body2==bodies[second],"Overlap body event ownership")
            let expectedForce=sample["force"] as! [Double],expectedDirection=sample["maxDirection"] as! [Double]
            let actual=[Double(event.totalForce.x),Double(event.totalForce.y),Double(event.totalForce.z),Double(event.totalForceMagnitude),
                        Double(event.maxForceDirection.x),Double(event.maxForceDirection.y),Double(event.maxForceDirection.z),Double(event.maxForceMagnitude)]
            let wanted=expectedForce+[sample["magnitude"] as! Double]+expectedDirection+[sample["maxMagnitude"] as! Double]
            for i in actual.indices{
                let error=abs(actual[i]-wanted[i]);maxContactError=max(maxContactError,error)
                check(error<0.0001+abs(wanted[i])*0.000001,"Overlap force field\(i) frame\(frame) error\(error)")
            }
            check(event.totalForceMagnitude>0 && event.maxForceMagnitude>0,"Overlap positive solver force")
            count+=1;contactEvents+=1
        }
        check(world.drainContactForceEvents().isEmpty,"Overlap events drained twice")
        let a=world.bodyState(bodies[0])!,b=world.bodyState(bodies[1])!;response=max(response,abs(a.position.x))
        if !contacts{
            check(values(a)==[0,0,0,0,0,0,1,0,0,0,0,0,0] && values(b)==[0.5,0,0,0,0,0,1,0,0,0,0,0,0],"Suppressed overlap changed rest state")
        }
    }
    check(contacts ? count>0 && response>0.01 : count==0 && response==0,"Overlap did not distinguish contact suppression")
}
func vector(_ input:Any)->SIMD3<Float>{let a=input as! [NSNumber];return SIMD3(a[0].floatValue,a[1].floatValue,a[2].floatValue)}
func compareCollider(_ actual:SwiftRapierWorld.ColliderInfo,_ row:[String:Any],_ label:String){
    let p=row["collider"] as! [Double],q=row["rotation"] as! [Double]
    let actualValues=[Double(actual.translation.x),Double(actual.translation.y),Double(actual.translation.z),
                      Double(actual.rotation.imag.x),Double(actual.rotation.imag.y),Double(actual.rotation.imag.z),Double(actual.rotation.real)]
    for (i,wanted) in (p+q).enumerated(){let error=abs(actualValues[i]-wanted);maxColliderError=max(maxColliderError,error);check(error<0.000002,"\(label) collider component\(i) error\(error)")}
}
func compareRay(_ actual:SwiftRapierWorld.QueryHit?,_ expected:Any,_ label:String){
    guard let row=expected as? [String:Any] else{check(actual==nil,"\(label) unexpected hit");return}
    check(actual != nil,"\(label) missed collider");guard let actual else{return}
    let normal=row["normal"] as! [Double],wanted=[row["distance"] as! Double]+normal
    let got=[Double(actual.distance),Double(actual.normal.x),Double(actual.normal.y),Double(actual.normal.z)]
    for i in wanted.indices{let error=abs(got[i]-wanted[i]);maxRayError=max(maxRayError,error);check(error<0.000005,"\(label) ray component\(i) error\(error)")}
}
let localWorld=SwiftRapierWorld(gravity:.zero)!,parent=localWorld.addBody(position:SIMD3(2,3,4))!
let shape=localWorld.addBox(halfExtents:SIMD3(0.4,0.3,0.6),body:parent,position:SIMD3(0,0.25,0),friction:0,restitution:0)!
let checkpoints=document["parentLocal"] as! [[String:Any]]
for row in checkpoints{
    let operation=row["operation"] as! [String:Any],label=operation["label"] as! String,type=operation["type"] as! String
    switch type{
    case "step":check(localWorld.step(),"\(label) step")
    case "local":
        let before=values(localWorld.bodyState(parent)!);check(localWorld.setColliderTranslationWrtParent(shape,position:vector(operation["position"]!)),"\(label) local setter")
        check(values(localWorld.bodyState(parent)!)==before,"\(label) changed body pose/momentum")
    case "pose":
        var state=localWorld.bodyState(parent)!;state.position=vector(operation["position"]!);check(localWorld.setBodyState(state,for:parent),"\(label) translation")
        let q=operation["rotation"] as! [Double];check(localWorld.setBrowserRotation(parent,rotation:simd_quatf(ix:Float(q[0]),iy:Float(q[1]),iz:Float(q[2]),r:Float(q[3]))),"\(label) browser rotation")
    case "velocity":check(localWorld.setVelocities(parent,linear:vector(operation["linear"]!),angular:vector(operation["angular"]!)),"\(label) velocity")
    default:preconditionFailure("Unknown operation \(type)")
    }
    compare(localWorld.bodyState(parent)!,row["body"] as! [NSNumber],label)
    let info=localWorld.colliderInfo(shape)! // Actual native propagated query boundary.
    check(info.body==parent && info.dynamic,"\(label) local collider ownership");compareCollider(info,row,label)
    let rays=row["rays"] as! [[String:Any]]
    for (index,ray) in rays.enumerated(){
        let hit=localWorld.queryRay(origin:vector(ray["origin"]!),direction:vector(ray["direction"]!),distance:10)
        compareRay(hit,ray["direct"]!,"\(label) direct geometry\(index)")
        check(hit?.collider.id==shape && hit?.collider.body==parent,"\(label) query ownership")
        if ray["wholeMatchesCurrent"] as! Bool{compareRay(hit,ray["whole"]!,"\(label) whole world\(index)");wholeWorldCompared+=1}
        else{
            // Preserve the existing immediate native query policy, while
            // explicitly recording the archived world's stale broadphase.
            check(type != "step","Archived post-step broadphase was unexpectedly stale")
            queryTimingDifferences.append(["label":label,"ray":index,"archivedWorldMiss":ray["whole"] is NSNull])
        }
    }
}
check(queryTimingDifferences.count==document["staleWorldRays"] as! Int,"Lost archived broadphase timing observations")
for id in[UInt64.max,parent]{check(!localWorld.setColliderTranslationWrtParent(id,position:.zero),"Invalid local collider ID accepted")}
for value in[SIMD3<Float>(.nan,0,0),SIMD3(0,.infinity,0),SIMD3(0,0,-.infinity)]{check(!localWorld.setColliderTranslationWrtParent(shape,position:value),"Nonfinite local offset accepted")}
check(localWorld.removeCollider(shape),"Remove local shape");check(!localWorld.setColliderTranslationWrtParent(shape,position:.zero),"Removed local collider ID accepted")
let aloneWorld=SwiftRapierWorld(gravity:.zero)!,alone=aloneWorld.addBox(halfExtents:SIMD3(0.4,0.3,0.6),position:SIMD3(-8,3,4))!
let standalone=document["standalone"] as! [[String:Any]]
for row in standalone{
    let label=row["label"] as! String
    if label=="after-local-set"{check(aloneWorld.setColliderTranslationWrtParent(alone,position:SIMD3(100,200,300)),"Standalone local setter rejected")}
    if label=="after-step"{check(aloneWorld.step(),"Standalone step")}
    let info=aloneWorld.colliderInfo(alone)!;check(info.body==nil && !info.dynamic,"Standalone acquired parent")
    compareCollider(info,row,label);compareRay(aloneWorld.queryRay(origin:SIMD3(-13,3,4),direction:SIMD3(1,0,0),distance:10),row["ray"]!,label)
}
let report:[String:Any]=["checks":checks,"disjointTrajectories":cases.count,"overlapTrajectories":overlap.count,"overlapEvents":contactEvents,
    "parentLocalCheckpoints":checkpoints.count,"parentLocalRays":checkpoints.count*3,"wholeWorldRayMatches":wholeWorldCompared,
    "archivedBroadphaseTimingDifferences":queryTimingDifferences,"standaloneCheckpoints":standalone.count,
    "maxBodyComponentError":maxError,"maxContactFieldError":maxContactError,"maxColliderComponentError":maxColliderError,"maxRayComponentError":maxRayError,
    "limits":["Whole-world archived queries have a step-maintained broadphase; six propagated pre-step rays differ from the existing immediate native shape-query policy.",
              "Direct collider geometry and matching whole-world rays are compared separately. JS does not expose the native event started flag.",
              "Controlled actual archived Rapier WASM reference; no original retail game or device driving observation."]]
if CommandLine.arguments.count>2{try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))}
print("PASS spherical joint Swift/native/archived WASM: \(checks) checks, \(cases.count) disjoint + \(overlap.count) overlapping trajectories, \(contactEvents) force events; max body error\(maxError), force error\(maxContactError)")
print("PASS parent-local v2: \(checkpoints.count) checkpoints/\(checkpoints.count*3) direct rays, \(wholeWorldCompared) matching whole-world rays, collider error\(maxColliderError), ray error\(maxRayError); \(queryTimingDifferences.count) explicitly retained archived broadphase timing differences, standalone no-op/guards/momentum")
