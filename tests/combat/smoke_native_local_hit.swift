import Foundation
import simd
let reference=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
var checks=0,frames=0,label="",maxError=0.0
func check(_ value:Bool,_ message:String){checks+=1;if !value{FileHandle.standardError.write(Data("FAIL \(label): \(message)\n".utf8));exit(1)}}
func vec(_ raw:Any)->SIMD3<Double>{let a=raw as! [Double];return SIMD3(a[0],a[1],a[2])}
func scalar(_ a:Double,_ b:Double){let error=abs(a-b);maxError=max(maxError,error);check(error<2e-10,"numeric response differs \(a) / \(b)")}
for group in reference["groups"] as! [[String:Any]] {
 let model=NativeLocalHitReaction()
 for (index,row) in (group["frames"] as! [[String:Any]]).enumerated(){
  label="\(group["name"]!)/\(index)"
  let raw=row["input"] as! [String:Any],expected=row["expected"] as! [String:Any]
  var input=NativeLocalHitReaction.Input(weapon:raw["weapon"] as! Int,damage:raw["damage"] as! Double,healthAfter:raw["healthAfter"] as! Int,now:raw["now"] as! Double)
  input.side=raw["side"] as! Int;input.piece=raw["piece"] as! Int;input.quiet=raw["quiet"] as! Bool;input.wasAlive=raw["wasAlive"] as! Bool
  input.still=raw["still"] as! Bool;input.crouched=raw["crouched"] as! Bool;input.stun=raw["stun"] as! Bool;input.swimming=raw["swimming"] as! Bool
  input.climbing=raw["climbing"] as! Bool;input.stealth=raw["stealth"] as! Bool;input.hasActor=raw["hasActor"] as! Bool
  input.target=vec(raw["target"]!);input.source=(raw["source"] as? [Double]).map(vec)
  let result=model.receive(input)
  check(result.flinch==expected["flinch"] as? String,"flinch decision");check(result.stun==expected["stun"] as! Bool,"stun ownership")
  check(result.death==expected["death"] as? String,"death clip");check(result.loseHead==expected["loseHead"] as! Bool,"head reaction")
  if let impulse=expected["impulse"] as? [Double]{check(result.impulse != nil,"missing impulse");let target=vec(impulse);for axis in 0..<3{scalar(result.impulse![axis],target[axis])}}
  else{check(result.impulse==nil,"invented impulse")}
  if let until=expected["until"] as? Double{scalar(model.until,until)}else{check(model.until == -.infinity,"invented cooldown")}
  frames+=1
 }
 model.reset();check(model.until == -.infinity,"reset retained cooldown")
}
print("PASS local hit decisions: \(checks) checks, \(frames) actual archived frames; max error \(maxError)")
