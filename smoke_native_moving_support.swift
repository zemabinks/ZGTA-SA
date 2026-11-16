import Foundation
import simd
typealias V=SIMD3<Double>
let reference=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
var checks=0,ticks=0,maxError=0.0,label="",boundaryTies=0
func check(_ value:Bool,_ message:String){checks+=1;if !value{FileHandle.standardError.write(Data("FAIL \(label): \(message)\n".utf8));exit(1)}}
func scalar(_ a:Double,_ b:Double){let error=abs(a-b);maxError=max(maxError,error);check(error<2e-10,"scalar \(a) != \(b)")}
func vector(_ a:V,_ b:V){for axis in 0..<3{scalar(a[axis],b[axis])}}
func v(_ a:Any)->V{let row=a as! [Double];return V(row[0],row[1],row[2])}
func q(_ a:Any)->simd_quatd{let row=a as! [Double];return simd_quatd(ix:row[0],iy:row[1],iz:row[2],r:row[3])}
func id(_ a:Any?)->UInt64?{(a as? NSNumber)?.uint64Value}
final class ReplayScene:NativeMovingSupport.Scene {
 var bodies:[UInt64:NativeMovingSupport.Body]=[:],entries:[NativeMovingSupport.Entry]=[]
 var queries:[[String:Any]]=[],cursor=0
 func body(_ id:UInt64)->NativeMovingSupport.Body?{bodies[id]}
 func next(_ kind:String,_ origin:V)->[String:Any]{
  check(cursor<queries.count,"extra query \(kind)");let row=queries[cursor];cursor+=1
  check(row["kind"] as? String==kind,"query order differs at \(cursor): wanted \(kind), recorded \(row["kind"]!)");vector(origin,v(row["origin"]!));return row
 }
 func ray(origin:V,distance:Double,groups:UInt32)->NativeMovingSupport.Ray?{
  let row=next("ray",origin);scalar(distance,row["distance"] as! Double);check(UInt32(row["groups"] as! Int)==groups,"mask")
  guard let hit=row["result"] as? [String:Any] else{return nil};return .init(body:id(hit["body"])!,distance:hit["distance"] as! Double)
 }
 func nearbyTreads(at:V,radius:Double,limit:Int)->[UInt64]{let row=next("near",at);scalar(radius,row["radius"] as! Double);check(limit==row["limit"] as! Int,"query limit");return (row["result"] as! [Int]).map{UInt64($0)}}
 func treadRay(body:UInt64,origin:V,distance:Double)->Double?{let row=next("tread",origin);scalar(distance,row["distance"] as! Double);check(id(row["body"])==body,"tread body");return row["result"] as? Double}
 func belowStatic(origin:V,distance:Double)->Double?{let row=next("below",origin);scalar(distance,row["distance"] as! Double);return row["result"] as? Double}
 func fits(_ origin:V,_ body:UInt64)->Bool{let row=next("fits",origin);check(id(row["body"])==body,"excluded body");return row["result"] as! Bool}
 func update(_ frame:[String:Any]){
  queries=frame["queries"] as! [[String:Any]];cursor=0;bodies=[:]
  for row in frame["rows"] as! [[String:Any]] {
   let handle=id(row["id"])!;var body=NativeMovingSupport.Body(id:handle,position:v(row["position"]!),rotation:q(row["rotation"]!),dynamic:row["dynamic"] as? Bool ?? false)
   body.velocity=(row["velocity"] as? [Double]).map(v) ?? .zero;body.spin=(row["spin"] as? [Double]).map(v) ?? .zero;bodies[handle]=body
  }
  let old=entries
  entries=(frame["entries"] as! [[String:Any]]).map{row in
   let name=row["id"] as! String,handle=id(row["handle"])!,position=v(row["position"]!),rotation=q(row["rotation"]!)
   let entry=old.first{$0.id==name} ?? .init(handle:handle,id:name,vehicle:row["vehicle"] as? String,position:position,rotation:rotation)
   entry.handle=handle;entry.vehicle=row["vehicle"] as? String;entry.position=position;entry.rotation=rotation
   entry.driver=row["driver"] as? String;entry.origin=row["origin"] as! Double;entry.standing=row["standing"] as! Bool;entry.kind=row["kind"] as! String
   entry.velocity=(row["velocity"] as? [Double]).map(v);entry.spin=(row["spin"] as? [Double]).map(v);return entry
  }
 }
}
for scenario in reference["scenarios"] as! [[String:Any]] {
 let scene=ReplayScene(),support=NativeMovingSupport(scene:scene),rate=scenario["rate"] as! Double
 var head=V(0,1.92,0),grounded=true,rising=0.0,stands=0
 func actor()->NativeMovingSupport.Actor{.init(grounded:grounded,rising:rising,fits:{scene.fits($0,$1)},stand:{grounded=true;rising=0;stands+=1})}
 for (index,frame) in (scenario["frames"] as! [[String:Any]]).enumerated(){
  label="\(scenario["name"]!)/\(rate)/\(index)";scene.update(frame);stands=0
  let tick=frame["tick"] as! [String:Any],pre=frame["pre"] as! [String:Any],carry=frame["carry"] as! [String:Any],motor=frame["motor"] as! [String:Any],expected=frame["expected"] as! [String:Any]
  if tick["drop"] as? Bool==true{support.drop()}
  if let point=tick["head"] as? [Double]{head=v(point)}
  vector(head,v(pre["head"]!));grounded=pre["grounded"] as! Bool;rising=pre["rising"] as! Double
  let result=support.carry(delta:1/rate,actor:actor(),head:&head)
  vector(head,v(carry["head"]!));vector(result.move,v(carry["move"]!));scalar(result.yaw,carry["yaw"] as! Double)
  if let thrown=carry["thrown"] as? [Double]{check(result.thrown != nil,"missing throw");vector(result.thrown!,v(thrown))}else{check(result.thrown==nil,"unexpected throw")}
  head += (tick["motor"] as? [Double]).map(v) ?? .zero;head += result.move
  vector(head,v(motor["head"]!));grounded=motor["grounded"] as! Bool;rising=motor["rising"] as! Double
  support.settle(actor:actor(),head:&head,jumping:tick["jumping"] as? Bool ?? false,moving:tick["moving"] as? Bool ?? true)
  if let offset=tick["presentation"] as? [Double]{for entry in scene.entries{entry.position += v(offset)}}
  vector(head,v(expected["head"]!));check(grounded==expected["grounded"] as! Bool,"grounded");scalar(rising,expected["rising"] as! Double);check(stands==expected["stands"] as! Int,"stand transitions")
  check(support.through==id(expected["through"]),"support body");check(support.riding==expected["riding"] as! Bool,"riding");check(support.held==expected["held"] as! Bool,"held");check(support.afloat==expected["afloat"] as! Bool,"afloat")
  if let on=expected["on"] as? [String:Any]{check(support.attachment != nil,"attachment missing");check(support.attachment!.id==on["id"] as? String,"attachment id");let at=on["at"] as! [String:Double];vector(support.attachment!.at,V(at["x"]!,at["y"]!,at["z"]!))}else{check(support.attachment==nil,"invented attachment")}
  if let point=expected["drawn"] as? [Double]{check(support.drawnAt != nil,"presentation missing");vector(support.drawnAt!,v(point))}else{check(support.drawnAt==nil,"invented presentation")}
  check(scene.cursor==scene.queries.count,"unused queries: \(scene.queries.count-scene.cursor)");ticks+=1
 }
}
for row in reference["knockSides"] as! [[String:Any]] {
 label="support knock direction heading\(row["heading"]!) velocity\(row["velocity"]!) expected\(row["side"]!)"
 let actual=NativeFootLocomotion.supportKnockSide(velocity:v(row["velocity"]!),heading:row["heading"] as! Double),expected=row["side"] as! Int
 if actual != expected {
  // V8's and Darwin's atan2 can land on opposite sides of an exact 45/135
  // degree boundary by one ULP. Record only that adjacent-bin ambiguity;
  // every direction away from these thresholds must match exactly.
  let angle=row["angle"] as! Double,positive=angle>0
  let nearFirst=abs(abs(angle)-Double.pi/4)<2e-14,nearLast=abs(abs(angle)-3*Double.pi/4)<2e-14
  let allowed:Set<Int>=nearFirst ? [0,positive ? 1:3]:nearLast ? [2,positive ? 1:3]:[]
  check(allowed.contains(actual) && allowed.contains(expected),"knock direction differs away from a numeric boundary");boundaryTies+=1
 }else{check(true,"knock direction")}
}
for row in reference["momentumFrames"] as! [[String:Any]] {
 let motor=NativeFootLocomotion(),rate=row["rate"] as! Double;motor.setKnockMomentum(v(row["velocity"]!))
 for expected in row["frames"] as! [[Double]] {
  label="ground knock momentum \(rate)Hz"
  let actual=motor.groundMomentum(delta:1/rate),physics=v(expected)
  check(simd_distance(SIMD3<Double>(actual),V(physics.x,-physics.z,0))<1e-7,"ground momentum decay differs from original")
 }
 motor.reset(heading:0);check(motor.groundMomentum(delta:1/rate) == .zero,"reset kept knock momentum")
}
print("PASS moving support: \(checks) checks, \(ticks) archived controlled ticks plus original knock direction/ground momentum; max error \(maxError); \(boundaryTies) recorded atan2 threshold ties")
