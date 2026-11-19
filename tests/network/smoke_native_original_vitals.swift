import Foundation
let input=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))as![String:Any]
var checks=0
func check(_ ok:Bool,_ label:String){checks+=1;guard ok else{fatalError("Original vitals: \(label)")}}
func close(_ a:Double,_ b:Double)->Bool{abs(a-b)<0.000000001}
let cases=input["cases"]as![[String:Any]]
for (index,c)in cases.enumerated(){
 let owner=NativeOriginalWorldVitals();_=owner.begin(health:c["hp"]as!Double,armour:c["ap"]as!Double,wasted:c["dead"]as!Bool);owner.setGodly(c["godly"]as!Bool)
 let result=owner.hurt(.init(damage:c["damage"]as!Double,weapon:c["weapon"]as!Int,quiet:c["quiet"]as!Bool),context:.init(frontMeleeParry:c["parry"]as!Bool,swimming:c["swimming"]as!Bool))
 let expected=c["expected"]as![String:Any],effects=expected["events"]as![String]
 check(close(owner.health,expected["health"]as!Double),"fractional health \(index)")
 check(close(owner.armour,expected["armour"]as!Double),"fractional armour \(index)")
 check(owner.dead==expected["dead"]as!Bool,"death threshold \(index)")
 check(owner.wireHealth==expected["wireHealth"]as!Int && owner.wireArmour==expected["wireArmour"]as!Int,"ceil reporting \(index)")
 check(result.startBurning==effects.contains("fire") && result.startGas==effects.contains("gas") && result.douse==effects.contains("douse") && result.parried==effects.contains("parry"),"effect ownership \(index)")
 check(result.killed==effects.contains("death"),"single death event \(index)")
}
for sequence in input["sequences"]as![[String:Any]]{
 let owner=NativeOriginalWorldVitals();_=owner.begin(health:100,armour:sequence["armour"]as!Double)
 let states=Dictionary(uniqueKeysWithValues:(sequence["states"]as![[String:Any]]).map{($0["index"]as!Int,$0)})
 for index in 0..<1200{
  _=owner.hurt(.init(damage:0.1,weapon:22,quiet:true))
  if let expected=states[index]{check(close(owner.health,expected["health"]as!Double) && close(owner.armour,expected["armour"]as!Double) && owner.dead==expected["dead"]as!Bool,"fractional sequence \(index)")}
 }
}
for (index,c)in (input["fatalCases"]as![[String:Any]]).enumerated(){
 let current=NativeOriginalWorldVitals();_=current.begin(health:c["hp"]as!Double,armour:c["ap"]as!Double)
 let pending=current.deferMovingCarFatal(.init(damage:c["damage"]as!Double,weapon:22),nowMilliseconds:1000,drivingCar:c["kind"]as!String=="car",speed:c["speed"]as!Double)
 check((pending != nil)==c["deferred"]as!Bool,"actual deferred car admission \(index)")
 if let pending{check(pending.untilMilliseconds==c["until"]as!Double,"actual deferred deadline \(index)")}
}
let owner=NativeOriginalWorldVitals();_=owner.begin(health:10.1,armour:2.2)
for fixture in input["effects"]as![[String:Any]]{
 let effect=NativeOriginalWorldEffects()
 for (index,row)in (fixture["steps"]as![[String:Any]]).enumerated(){
  for command in row["actions"]as![[String:Any]]{
   let by=command["by"]as?String
   switch command["type"]as!String{
   case "light":_=effect.light(by:by)
   case "douse":effect.douse(command["value"]as!Double)
   case "extinguish":effect.extinguish()
   case "whiff":effect.whiff(by:by,volume:command["value"]as!Bool,random:{0.5})
   case "clearGas":effect.clearGas()
   default:fatalError("unknown effect fixture")
   }
  }
  let hits=effect.step(delta:row["delta"]as!Double),burn=hits.filter{$0.weapon==37}.reduce(0){$0+$1.amount},gas=hits.filter{$0.weapon==17}.reduce(0){$0+$1.amount}
  check(close(burn,row["burnDamage"]as!Double)&&close(gas,row["gasDamage"]as!Double),"actual effect rates \(fixture["hz"]!)/\(fixture["mode"]!)/\(index)")
  check(effect.burning==row["burning"]as!Bool&&effect.coughing==row["coughing"]as!Bool,"actual effect lifetime")
  check(effect.fireSource==row["fireSource"]as?String&&effect.gasSource==row["gasSource"]as?String,"actual effect attribution")
 }
}
owner.respawn();check(owner.health==10.1 && owner.armour==2.2,"living respawn does not heal")
_=owner.setHealth(0.1);check(owner.health==1 && !owner.dead,"alive setter clamps to1")
_=owner.staffHealth(0.1);check(owner.dead && owner.health==0,"staff below1 is kill")
check(!owner.setHealth(100) && owner.dead,"setter cannot revive")
owner.respawn();check(owner.health==100 && owner.armour==0 && !owner.dead,"dead respawn resets")
_=owner.begin(health:10,armour:5)
let hit=NativeOriginalWorldVitals.Hit(damage:20,weapon:22,source:"peer",point:SIMD3(1,2,3),piece:3)
check(owner.deferMovingCarFatal(hit,nowMilliseconds:1000,drivingCar:true,speed:0.5)==nil,"strict moving-car threshold")
let pending=owner.deferMovingCarFatal(hit,nowMilliseconds:1000,drivingCar:true,speed:0.5001)!
check(owner.health==10 && owner.armour==5 && owner.wireHealth==0 && owner.displayHealth==10,"pending fatal does not prematurely damage HUD")
check(owner.pendingFatal?.untilMilliseconds==3000 && owner.readyFatal(nowMilliseconds:2999,driving:true,wrecked:false)==nil,"two-second delay")
check(owner.readyFatal(nowMilliseconds:3000,driving:true,wrecked:true)==nil,"wreck cause wins")
check(owner.readyFatal(nowMilliseconds:3000,driving:false,wrecked:false)==nil,"old vehicle ownership cannot commit")
check(owner.readyFatal(nowMilliseconds:3000,driving:true,wrecked:false)==pending,"geometry can delay exit without losing identity")
check(owner.consumeFatal(token:pending.token+1)==nil && owner.pendingFatal != nil,"stale completion rejected")
check(owner.consumeFatal(token:pending.token) == .hit(hit) && owner.consumeFatal(token:pending.token)==nil,"pending event consumed once")
_=owner.hurt(hit);check(owner.dead && owner.armour==0,"damage after accepted actual exit")
owner.respawn();_=owner.begin(health:10,armour:0)
let delayed=owner.deferMovingCarFatal(.init(damage:20,weapon:22),nowMilliseconds:0,drivingCar:true,speed:1)!
_=owner.setHealth(100)
guard case .hit(let healedHit)?=owner.consumeFatal(token:delayed.token)else{fatalError("pending heal")}
_=owner.hurt(healedHit);check(owner.health==80 && !owner.dead,"staff heal while pending is retained")
let selfKill=owner.deferMovingCarSelfKill(nowMilliseconds:0,drivingCar:true,speed:1)!
check(owner.consumeFatal(token:selfKill.token) == .selfKill,"staff self-kill cause retained")
owner.kill();owner.respawn();check(owner.pendingFatal==nil,"new life drops old deferred cause")
check(!owner.begin(health:Double.nan,armour:0) && !owner.setArmour(Double.infinity),"nonfinite input rejected")
_=owner.begin(health:10,armour:0)
let immediate=owner.deferNativeExitFatal(.init(damage:20,weapon:22),nowMilliseconds:1000)!
check(immediate.untilMilliseconds==1000 && owner.health==10 && owner.wireHealth==0,"streamed native immediate exit does not invent2second delay or early damage")
check(owner.readyFatal(nowMilliseconds:1000,driving:true,wrecked:false)==immediate,"immediate cause waits for actual exit")
owner.respawn();check(owner.consumeFatal(token:immediate.token)==nil,"respawn invalidates blocked immediate exit")
print("PASS original fractional vitals: \(cases.count) actual archived hit cases,4 repeated-hit sequences,\((input["fatalCases"]as![[String:Any]]).count) actual moving-car fatal admission cases,\(checks) checks")
