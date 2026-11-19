// Actual raw-rig replay; the runner replaces only unused GPU storage/binding.
let root=URL(fileURLWithPath:CommandLine.arguments[1]),game=root.appendingPathComponent("local-only/site/game")
let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:game.appendingPathComponent("native/models/animations.clips.bin")))!
let actor=NativeSkeletalActor(data:try Data(contentsOf:game.appendingPathComponent("native/models/bmori.skel.bin")),vertexCount:822,device:MTLDevice())!
let catalog=try NativeWeaponMuzzle.Catalog(data:Data(contentsOf:game.appendingPathComponent("native/weapons.json")))
let definitions=try NativeFootAnimationDefinitions(data:Data(contentsOf:game.appendingPathComponent("world/peds.json")))
let document=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [String:Any]
func n(_ object:[String:Any],_ key:String)->Double {(object[key] as? NSNumber)?.doubleValue ?? 0}
func v(_ value:Any)->SIMD3<Float> {let a=value as! [NSNumber];return SIMD3(a[0].floatValue,a[1].floatValue,a[2].floatValue)}
func world(_ feet:SIMD3<Float>,_ heading:Double)->simd_float4x4 {
 let c=Float(cos(heading)),s=Float(sin(heading))
 return simd_float4x4(columns:(SIMD4(c,-s,0,0),SIMD4(s,c,0,0),SIMD4(0,0,1,0),SIMD4(feet,1)))
}
func arm(_ animator:NativeFootAnimation,_ profile:[String:Any]) throws {
 let data=try JSONSerialization.data(withJSONObject:["weapons":[profile]])
 animator.arm(try NativeFootWeaponAnimation.load(data:data)[profile["id"] as! Int])
}
var checks=0,frames=0,eventFrames=0,dualFrames=0,reloadFrames=0,maxError:Float=0
func check(_ value:Bool,_ label:String){precondition(value,label);checks += 1}
for scenario in document["cases"] as! [[String:Any]] {
 let animator=NativeFootAnimation(library:library,style:definitions.style(model:"bmori",library:library),random:{0.37})
 for row in scenario["rows"] as! [[String:Any]] {
  if let profile=(row["profile"] as? [String:Any]) ?? (row["change"] as? [String:Any]) {try arm(animator,profile)}
  if row["frame"] as! Int==67 {_ = animator.reload()}
  let inputRow=row["input"] as! [String:Any],control=row["control"] as! [String:Any]
  var input=NativeFootAnimation.Input();input.ratio=n(inputRow,"ratio");input.crouch=inputRow["crouch"] as! Bool
  let gun=inputRow["gun"] as! [String:Any];input.gun = .init(pitch:n(gun,"pitch"),yaw:n(gun,"yaw"))
  animator.control(.init(fire:control["fire"] as! Bool,aim:control["aim"] as! Bool,held:control["held"] as! Bool,ready:control["ready"] as! Bool))
  let frame=animator.update(delta:1/60,input:input),weapon=row["weapon"] as! Int,feet=v(row["feet"]!),skill=row["skill"] as! Int
  let pose=actor.originalPose(blends:frame.blends,library:library,aim:frame.aim,hiddenBones:frame.hiddenBones,figurePitch:frame.figurePitch,figureRoll:frame.figureRoll,legBend:frame.legBend)
  let snapshot=NativeWeaponMuzzle.Pose(weapon:weapon,feet:feet,actorToWorld:world(feet,n(row,"heading")),rightHand:actor.transform(bone:24,in:pose),leftHand:actor.transform(bone:34,in:pose))
  let definition=catalog.definition(weapon:weapon,skill:skill)!
  for left in [false,true] {
   let sample=NativeWeaponMuzzle.sample(weapon:weapon,left:left,feet:feet,definition:definition,pose:snapshot)!
   let expected=v(row[left ? "left":"right"]!),error=simd_distance(sample.origin,expected);maxError=max(maxError,error)
   check(sample.posed,"Real local rig unexpectedly fell back")
   check(error<0.0007,"Actual Ko muzzle mismatch weapon\(weapon) skill\(skill) frame\(row["frame"]!) left\(left): \(sample.origin) != \(expected), \(error)m")
   check(sample.usedLeft == (left && (row["guns"] as! Int)>1),"Actual holder hand selection")
  }
  check(frame.shot == row["shot"] as! Bool,"Real event timing")
  check(frame.shotLeft == row["shotLeft"] as! Bool,"Real per-hand event timing")
  check(animator.reloading == row["reloading"] as! Bool,"Real reload timing")
  if frame.shot{eventFrames += 1};if (row["guns"] as! Int)>1 {dualFrames += 1};if animator.reloading{reloadFrames += 1};frames += 1
 }
}
check(eventFrames>15 && dualFrames==100 && reloadFrames>0,"Must exercise real shots, dual attachment and reload")
let feet=SIMD3<Float>(10,20,3),definition=catalog.definition(weapon:22,skill:2)!
let identity=matrix_identity_float4x4
let pose=NativeWeaponMuzzle.Pose(weapon:22,feet:feet,actorToWorld:world(feet,0),rightHand:identity,leftHand:identity)
func sample(_ selected:NativeWeaponMuzzle.Pose?,_ def:NativeWeaponMuzzle.Definition?=definition)->NativeWeaponMuzzle.Sample? {
 NativeWeaponMuzzle.sample(weapon:22,left:true,feet:feet,definition:def,pose:selected)
}
check(sample(nil)?.fallbackReason=="pose-unavailable","No pose fallback")
check(sample(pose,nil)?.fallbackReason=="weapon-data-unavailable","No data fallback")
var hidden=pose;hidden.visible=false;check(sample(hidden)==nil,"Hidden traversal weapon must not fire")
let wrong=NativeWeaponMuzzle.Pose(weapon:23,feet:feet,actorToWorld:world(feet,0),rightHand:identity,leftHand:identity)
check(sample(wrong)?.fallbackReason=="weapon-changed","Switch between event and pose")
let stale=NativeWeaponMuzzle.Pose(weapon:22,feet:feet+SIMD3(1,0,0),actorToWorld:world(feet,0),rightHand:identity,leftHand:identity)
check(sample(stale)?.fallbackReason=="stale-pose","Stale event feet")
let noLeft=NativeWeaponMuzzle.Pose(weapon:22,feet:feet,actorToWorld:world(feet,0),rightHand:identity,leftHand:nil)
check(sample(noLeft)!.posed && !sample(noLeft)!.usedLeft,"One attached gun uses the actual right hand")
let noRight=NativeWeaponMuzzle.Pose(weapon:22,feet:feet,actorToWorld:world(feet,0),rightHand:nil,leftHand:identity)
check(sample(noRight)?.fallbackReason=="right-hand-unavailable","Left-only invalid holder")
for defect in 0..<4 {
 var hand=identity
 if defect==0{hand[0].x = .nan};if defect==1{hand[0] = .zero};if defect==2{hand[1].w = 1};if defect==3{hand[3].x=100}
 let invalid=NativeWeaponMuzzle.Pose(weapon:22,feet:feet,actorToWorld:world(feet,0),rightHand:hand,leftHand:nil)
 check(sample(invalid)?.posed==false,"Malformed rig must fall back: \(defect)")
}
check(NativeWeaponMuzzle.sample(weapon:22,left:false,feet:SIMD3(.nan,0,0),definition:definition,pose:pose)==nil,"Invalid event feet")
let chosen=catalog.definition(weapon:25)!,poor=catalog.definition(weapon:25,skill:0)!
check(chosen.skill==2 && poor.skill==0 && abs(chosen.offset.z-poor.offset.z-0.02)<0.00001,"Selected skill is data driven")
check(catalog.definition(weapon:25,skill:99)==nil,"Unknown skill cannot silently use another profile")
let report:[String:Any]=["authority":"Archived Ko/R6 actual rig, plus original weapon.dat data comparison; no retail runtime replay","frames":frames,"checks":checks,"eventFrames":eventFrames,"dualFrames":dualFrames,"reloadFrames":reloadFrames,"maxMuzzleErrorMetres":Double(maxError)]
try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[3]))
print("PASS actual weapon muzzle: \(frames) real rig frames, \(checks) checks, \(eventFrames) shot frames; maximum error \(maxError)m")
