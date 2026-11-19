let root=URL(fileURLWithPath:CommandLine.arguments[1]),game=root.appendingPathComponent("local-only/site/game")
let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:game.appendingPathComponent("native/models/animations.clips.bin")))!
let actor=NativeSkeletalActor(data:try Data(contentsOf:game.appendingPathComponent("native/models/bmori.skel.bin")),vertexCount:822,device:MTLDevice())!
let definitions=try NativeFootAnimationDefinitions(data:Data(contentsOf:game.appendingPathComponent("world/peds.json")))
let weapons=try NativeFootWeaponAnimation.load(data:Data(contentsOf:game.appendingPathComponent("native/foot-animation.json")))
let doc=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [String:Any]
let animator=NativeFootAnimation(library:library,style:definitions.style(model:"bmori",library:library),random:{0.37})
func n(_ row:[String:Any],_ key:String)->Double {(row[key] as? NSNumber)?.doubleValue ?? 0}
func v(_ values:Any)->SIMD3<Float> {let a=values as! [NSNumber];return SIMD3(a[0].floatValue,a[1].floatValue,a[2].floatValue)}
func world(_ p:SIMD3<Float>,_ heading:Double)->simd_float4x4 {
 let c=Float(cos(heading)),s=Float(sin(heading));return simd_float4x4(columns:(SIMD4(c,-s,0,0),SIMD4(s,c,0,0),SIMD4(0,0,1,0),SIMD4(p,1)))
}
var checks=0,vertices=0,backFrames=0,hiddenFlying=0,deadFrames=0,maxError:Float=0,lastWeapon = -1
func check(_ condition:Bool,_ message:String){precondition(condition,message);checks += 1}
for state in [1,11,0]{var input=NativeFootAnimation.Input();input.fly=state>0 ? .init(state:state):nil;_ = animator.update(delta:0,input:input)}
for row in doc["visibility"] as! [[String:Any]] {
 check(NativeWeaponAttachment.selectedWeapon(Int(n(row,"weapon")),swimming:row["swimming"] as! Bool,jetpackFlying:row["flying"] as! Bool,armWeapon:row["arm"] as! Bool)==Int(n(row,"expected")),"Actual t8 effective selection")
}
for row in doc["rows"] as! [[String:Any]] {
 let weapon=Int(n(row,"weapon")),chosen=Int(n(row,"chosen")),state=Int(n(row,"state"))
 let effective=NativeWeaponAttachment.selectedWeapon(chosen,swimming:row["swimming"] as! Bool,jetpackFlying:state==12||state==13,armWeapon:weapons[chosen]?.flags?["arm"]==true)
 check(effective==weapon,"Frame effective selection")
 if state>=12&&state<=13&&chosen==46 {check(effective==0,"Jetpack flight suppresses non-arm equipment");hiddenFlying += 1}
 if weapon != lastWeapon {animator.arm(weapons[weapon]);lastWeapon=weapon}
 if row["method"] as? String == "die" {animator.die("koFront")}
 if row["method"] as? String == "revive" {animator.revive()}
 let source=row["input"] as! [String:Any];var input=NativeFootAnimation.Input();input.ratio=n(source,"ratio");input.look=n(source,"look")
 if let fly=source["fly"] as? [String:Any] {input.fly = .init(state:Int(n(fly,"state")),pitch:n(fly,"pitch"),roll:n(fly,"roll"))}
 let frame=animator.update(delta:n(row,"delta"),input:input)
 check(animator.dead == row["dead"] as! Bool,"Actual collapsed/revive state")
 if animator.dead {deadFrames += 1}
 let pose=actor.originalPose(blends:frame.blends,library:library,aim:frame.aim,hiddenBones:frame.hiddenBones,figurePitch:frame.figurePitch,figureRoll:frame.figureRoll,legBend:frame.legBend)
 if weapon==46 {
  backFrames += 1
  let attached=NativeWeaponAttachment.transform(weapon:weapon,rightHand:actor.transform(bone:24,in:pose),spine:actor.transform(bone:3,in:pose))!
  let model=world(v(row["feet"]!),n(row,"heading"))*attached
  for point in row["vertices"] as! [[String:Any]] {
   let p=model*SIMD4(v(point["point"]!),1),expected=v(point["world"]!),error=simd_distance(SIMD3(p.x,p.y,p.z),expected)
   maxError=max(maxError,error);check(error<0.0008,"Actual Ko bag vertex frame\(row["frame"]!) error \(error)m");vertices += 1
  }
 }
}
let identity=matrix_identity_float4x4
var hand=identity;hand.columns.3=SIMD4(2,3,4,1)
var spine=identity;spine.columns.3=SIMD4(8,9,10,1)
check(NativeWeaponAttachment.transform(weapon:46,rightHand:nil,spine:spine)==nil,"Ko requires right hand before attaching")
check(NativeWeaponAttachment.transform(weapon:46,rightHand:hand,spine:nil)! == hand,"Missing spine preserves actual unoffset hand fallback")
check(NativeWeaponAttachment.transform(weapon:22,rightHand:hand,spine:spine)! == hand,"Pistols retain hand transform")
check(NativeWeaponAttachment.transform(weapon:46,rightHand:hand,spine:spine)! == spine*NativeWeaponAttachment.foldedParachute,"Parachute spine composition")
check(backFrames>300&&hiddenFlying==30&&vertices>4000&&deadFrames==45,"Exercise gait, flight, selection, collapsed/revive and visibility transitions")
let report:[String:Any]=["authority":doc["authority"]!,"frames":(doc["rows"] as! [Any]).count,"checks":checks,"bagFrames":backFrames,"realVertexComparisons":vertices,"hiddenFlyingFrames":hiddenFlying,"deadFrames":deadFrames,"maxVertexErrorMetres":Double(maxError),"actualInventoryChecks":doc["inventoryChecks"]!,"actualHolderTransitions":doc["holderTransitions"]!]
try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[3]))
print("PASS actual equipment attachment: \(checks) checks, \(vertices) real bag vertices, maxerror \(maxError)m")
