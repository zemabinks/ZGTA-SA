// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
typealias Camera=NativeSAMPGameCamera
typealias Commands=NativeSAMPGameplayCommands
var checks=0
func check(_ value:@autoclosure()throws->Bool,_ message:String){checks+=1;do{if try !value(){fatalError("server game camera: \(message)")}}catch{fatalError("server game camera \(message): \(error)")}}
func near(_ a:SIMD3<Float>,_ b:SIMD3<Float>,_ eps:Float=0.0001)->Bool{simd_length(a-b)<=eps}
func rejects(_ reason:String,_ body:()throws->Void){do{try body();fatalError("expected camera failure: \(reason)")}catch is Camera.Failure{checks+=1}catch{fatalError("unexpected \(reason): \(error)")}}
let normal=Camera.Pose(eye:SIMD3(0,-6,3),target:SIMD3(0,0,1))
func event(_ n:UInt64,_ command:Commands.Command,_ generation:UInt64=1)->Commands.Event{Commands.Event(generation:generation,sequence:n,command:command)}
func camera()->Camera{var owner=Camera();check(try! owner.apply(event(0,.reset),at:0),"initial reset");return owner}
var owner=camera()
var sample=try owner.sample(at:0,normal:normal)
check(!sample.active && sample.pose.eye==normal.eye && sample.pose.target==normal.target,"normal follow has no invented override")
var seeded=camera();_ = try seeded.sample(at:0,normal:normal)
let fresh=Camera.Pose(eye:SIMD3(40,50,60),target:SIMD3(41,52,63))
try seeded.apply(event(1,.cameraLookAt(SIMD3(42,53,64),.cut)),at:1,seed:fresh)
check(try seeded.sample(at:1,normal:normal).pose.eye==fresh.eye,"explicit current seed outranks an older rendered normal frame")
try owner.apply(event(1,.cameraPosition(SIMD3(10,20,30))),at:0,seed:normal)
try owner.apply(event(2,.cameraLookAt(SIMD3(11,22,30),.cut)),at:0)
sample=try owner.sample(at:0,normal:normal)
check(sample.active && sample.pose.eye==SIMD3(10,20,30) && sample.pose.target==SIMD3(11,22,30),"fixed physical GTA coordinates")
check(simd_length(sample.pose.up)>0.999 && abs(simd_dot(simd_normalize(sample.pose.target-sample.pose.eye),sample.pose.up))<0.0001,"finite orthogonal up")

func interpolation(_ cut:Commands.Cut,_ hz:Int)throws->[Camera.Sample]{
 var c=camera();try c.apply(event(1,.cameraInterpolation(position:true,from:SIMD3(0,-6,3),to:SIMD3(20,-6,3),milliseconds:2000,cut:cut)),at:0,seed:normal)
 try c.apply(event(2,.cameraInterpolation(position:false,from:SIMD3(0,0,1),to:SIMD3(20,0,1),milliseconds:2000,cut:cut)),at:0)
 var values:[Camera.Sample]=[]
 for index in 0...(hz*2){values.append(try c.sample(at:Double(index)/Double(hz),normal:normal))}
 return values
}
for cut in [Commands.Cut.cut,.move]{
 for hz in [15,30,60,120]{
  let values=try interpolation(cut,hz)
  let quarter=values[hz/2],middle=values[hz],end=values[hz*2]
  let share=cut == .cut ? 0.25:Float((1-cos(Double.pi/4))/2)
  // Odd15Hz's indexed quarter is sampled at7/15s, so compare its exact elapsed fraction.
  let t=Double(hz/2)/Double(hz)/2
  let exact=cut == .cut ? Float(t):Float((1-cos(Double.pi*t))/2)
  check(near(quarter.pose.eye,SIMD3(20*exact,-6,3)),"elapsed-time quarter \(hz)Hz \(cut)")
  check(near(middle.pose.eye,SIMD3(10,-6,3)) && near(middle.pose.target,SIMD3(10,0,1)),"both independent tracks midpoint \(hz)Hz")
  check(end.pose.eye==SIMD3(20,-6,3) && end.pose.target==SIMD3(20,0,1),"exact endpoints \(hz)Hz")
  _ = share
 }
}
var linear=camera();try linear.apply(event(1,.cameraInterpolation(position:true,from:normal.eye,to:SIMD3(20,-6,3),milliseconds:2000,cut:.cut)),at:0,seed:normal)
check(near(try linear.sample(at:0.5,normal:normal).pose.eye,SIMD3(5,-6,3)),"Cut2 retains duration rather than discarding timed82")
var eased=camera();try eased.apply(event(1,.cameraInterpolation(position:true,from:normal.eye,to:SIMD3(20,-6,3),milliseconds:2000,cut:.move)),at:0,seed:normal)
check(near(try eased.sample(at:0.5,normal:normal).pose.eye,SIMD3(Float(20*(1-cos(Double.pi/4))/2),-6,3)),"source-supported half-cosine easing, not smoothstep")
var interrupted=camera();try interrupted.apply(event(1,.cameraInterpolation(position:true,from:normal.eye,to:SIMD3(20,-6,3),milliseconds:2000,cut:.cut)),at:0,seed:normal)
_ = try interrupted.sample(at:0.25,normal:normal)
try interrupted.apply(event(2,.cameraLookAt(SIMD3(30,0,1),.cut)),at:0.75)
sample=try interrupted.sample(at:1,normal:normal)
check(near(sample.pose.eye,SIMD3(10,-6,3)) && sample.pose.target==SIMD3(30,0,1),"target interruption preserves position track")
let later=try interrupted.sample(at:1.5,normal:normal),rewound=try interrupted.sample(at:0.5,normal:normal)
check(later.pose==rewound.pose,"monotonic sampling never rewinds")
var zero=camera();try zero.apply(event(1,.cameraInterpolation(position:true,from:normal.eye,to:SIMD3(99,20,30),milliseconds:0,cut:.move)),at:0,seed:normal)
check(try zero.sample(at:0,normal:normal).pose.eye==SIMD3(99,20,30),"zero-duration endpoint no division by zero")

var pending=camera();try pending.apply(event(1,.cameraLookAt(SIMD3(20,0,1),.move)),at:0,seed:normal)
sample=try pending.sample(at:1,normal:normal)
check(sample.pose.target==normal.target && sample.diagnostics.contains(.lookAtMovePolicyRequired),"untimed move does not invent a duration")
pending.lookAtMovePolicy={request in check(request.startedAt==0 && request.target==SIMD3(20,0,1),"explicit lookAt policy input");return Camera.Move(duration:2,curve:.linear)}
check(near(try pending.sample(at:1,normal:normal).pose.target,SIMD3(10,0,1)),"explicit caller policy uses absolute elapsed time")

var spectator=camera();try spectator.apply(event(1,.spectating(true)),at:0,seed:normal)
try spectator.apply(event(2,.spectatePlayer(42,.normal)),at:0)
var calls=0
let actual=Camera.Pose(eye:SIMD3(50,60,7),target:SIMD3(51,61,6))
sample=try spectator.sample(at:1,normal:normal,subjectProvider:{subject,mode in
 calls+=1;check(subject == .player(42) && mode == .normal,"provider receives actual subject and requested mode")
 return Camera.SubjectFrame(focus:actual.target,normal:actual,normalProvenance:.nativeGameCameraAdapter)
})
check(sample.pose.eye==actual.eye && sample.pose.target==actual.target && sample.spectating && calls==1,"normal spectator uses exact native provider view")
try spectator.apply(event(3,.cameraPosition(SIMD3(1,2,3))),at:1)
sample=try spectator.sample(at:1,normal:normal,subjectProvider:{_,_ in Camera.SubjectFrame(focus:actual.target,normal:actual,normalProvenance:.nativeGameCameraAdapter)})
check(sample.pose.eye==actual.eye && sample.diagnostics.contains(.cameraBlockedBySpectateMode),"normal spectator camera lock")
sample=try spectator.sample(at:2,normal:normal)
check(sample.pose.eye==actual.eye && sample.diagnostics.contains(.missingSubject),"missing subject holds last actual camera, no origin fallback")
try spectator.apply(event(4,.spectating(false)),at:2)
sample=try spectator.sample(at:2,normal:normal)
check(sample.pose.eye==actual.eye && sample.active && !sample.spectating,"exit holds actual view until confirmed spawn")
let before=sample.followRevision
check(try spectator.spawned(at:3,generation:1),"confirmed spawn")
sample=try spectator.sample(at:3,normal:normal)
check(!sample.active && !sample.spectating && sample.pose.eye==normal.eye && sample.followRevision>before,"spawn restores normal follow")

var fixed=camera();try fixed.apply(event(1,.spectating(true)),at:0,seed:normal);try fixed.apply(event(2,.spectateVehicle(7,.fixed)),at:0)
try fixed.apply(event(3,.cameraPosition(SIMD3(100,200,300))),at:0)
sample=try fixed.sample(at:1,normal:normal,subjectProvider:{_,mode in check(mode == .fixed,"fixed mode forwarded");return Camera.SubjectFrame(focus:SIMD3(11,22,33))})
check(sample.pose.eye==SIMD3(100,200,300) && sample.pose.target==SIMD3(11,22,33),"fixed eye tracks actual subject focus")
sample=try fixed.sample(at:2,normal:normal,subjectProvider:{_,_ in Camera.SubjectFrame(focus:SIMD3(12,25,35))})
check(sample.pose.eye==SIMD3(100,200,300) && sample.pose.target==SIMD3(12,25,35),"fixed subject tracking updates without guessed offsets")
try fixed.apply(event(4,.spectateVehicle(7,.side)),at:2)
sample=try fixed.sample(at:2,normal:normal,subjectProvider:{_,_ in Camera.SubjectFrame(focus:SIMD3(12,25,35))})
check(sample.diagnostics.contains(.missingSideFollow),"side offset is not fabricated")
sample=try fixed.sample(at:3,normal:normal,subjectProvider:{_,_ in Camera.SubjectFrame(focus:actual.target,side:actual)})
check(sample.pose.eye==actual.eye && sample.diagnostics.contains(.unverifiedFollow),"unverified side provider is labeled")
sample=try fixed.sample(at:4,normal:normal,subjectProvider:{_,_ in Camera.SubjectFrame(focus:SIMD3(.nan,0,0),side:actual)})
check(sample.pose.eye==actual.eye && sample.diagnostics.contains(.invalidSubject),"non-finite remote subject cannot poison view")

var authority=Commands.Authority(),restored=camera()
for item in [event(0,.reset),event(1,.controllable(false)),event(2,.spectating(true)),event(3,.cameraBehind)]{
 _ = authority.apply(item);_ = try restored.apply(item,at:0,seed:normal)
}
check(authority.inputBlocked && restored.spectating && !restored.active,"cameraBehind never unfreezes control or spectator authority")
check(!(try restored.apply(event(2,.cameraPosition(SIMD3(999,0,0))),at:.nan)),"stale event ignored before bad clock")
check(!(try restored.apply(event(0,.reset),at:0)),"duplicate reset rejected")
check(try restored.apply(event(0,.reset,2),at:0),"new generation reset")
check(!(try restored.spawned(at:1,generation:1)),"retired spawn cannot affect replacement generation")
check(!(try restored.apply(event(4,.cameraPosition(SIMD3(999,0,0)),1),at:1)),"retired camera command")

var guarded=camera();try guarded.apply(event(1,.cameraPosition(SIMD3(10,20,30))),at:0,seed:normal)
try guarded.apply(event(2,.cameraLookAt(SIMD3(10,20,30),.cut)),at:0)
sample=try guarded.sample(at:0,normal:normal)
check(simd_distance(sample.pose.eye,sample.pose.target)>0 && sample.diagnostics.contains(.coincidentLookAt),"coincident look direction repaired")
try guarded.apply(event(3,.cameraLookAt(SIMD3(10,20,31),.cut)),at:0)
sample=try guarded.sample(at:0,normal:normal)
check(abs(simd_dot(simd_normalize(sample.pose.target-sample.pose.eye),sample.pose.up))<0.0001 && sample.diagnostics.contains(.verticalUpFallback),"vertical camera has finite usable up")
var badUp=camera()
sample=try badUp.sample(at:0,normal:Camera.Pose(eye:SIMD3(1,2,3),target:SIMD3(1,3,3),up:SIMD3(.nan,0,0)))
check(sample.diagnostics.contains(.correctedUp),"invalid up repaired")
rejects("non-finite clock"){_ = try guarded.sample(at:.infinity,normal:normal)}
rejects("non-finite vector"){_ = try guarded.apply(event(4,.cameraPosition(SIMD3(.infinity,0,0))),at:0)}
rejects("oversized vector"){_ = try guarded.apply(event(4,.cameraPosition(SIMD3(20_000_000,0,0))),at:0)}
rejects("invalid duration"){_ = try guarded.apply(event(4,.cameraInterpolation(position:true,from:.zero,to:.zero,milliseconds:.max,cut:.move)),at:0)}
rejects("invalid normal"){_ = try guarded.sample(at:1,normal:Camera.Pose(eye:SIMD3(.nan,0,0),target:.zero))}
let report:[String:Any]=["status":"PASS","checks":checks,"rates":[15,30,60,120],"scope":"pure camera command/state/absolute-time interpolation/provider tests; retail timings, untimed lookAt policy and spectator offset parity unverified"]
print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self))
