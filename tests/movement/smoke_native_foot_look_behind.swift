let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
let reference=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [String:Any]
var checks=0,frames=0,held=0,maxError:Float=0
func check(_ condition:Bool,_ reason:String){precondition(condition,reason);checks += 1}
func number(_ object:[String:Any],_ key:String)->Float {(object[key] as! NSNumber).floatValue}
func v(_ value:Any)->SIMD3<Float> {let a=value as! [NSNumber];return SIMD3(a[0].floatValue,a[1].floatValue,a[2].floatValue)}
func close(_ actual:SIMD3<Float>,_ expected:SIMD3<Float>,_ label:String){let error=simd_distance(actual,expected);maxError=max(maxError,error);check(error<0.0007,"\(label): \(actual) != \(expected), \(error)m")}
func hit(_ origin:SIMD3<Float>,_ direction:SIMD3<Float>,_ distance:Float,_ mode:Int)->Float? {mode==1 && distance>=1.2 ? 1.2:nil}
for scenario in reference["cases"] as! [[String:Any]] {
 let camera=try NativeGameCamera(data:data),normal=try NativeGameCamera(data:data)
 for row in scenario["rows"] as! [[String:Any]] {
  let input=row["input"] as! [String:Any],expected=row["expected"] as! [String:Any]
  let foot=NativeGameCamera.Foot(position:v(input["position"]!),actorHeading:number(input,"actorHeading"),weapon:input["weapon"] as! Int,aiming:input["aiming"] as! Bool,crouching:input["crouching"] as! Bool,holdingLedge:input["holdingLedge"] as! Bool,parachuting:input["parachuting"] as! Bool,sight:input["sight"] as? String)
  let heading=number(input,"heading"),pitch=number(input,"pitch"),delta=number(input,"delta"),look=input["look"] as? String
  for c in [camera,normal]{c.setDirection(heading:heading,pitch:pitch);c.setFootZoom(input["zoom"] as! Int)}
  var calls:[(SIMD3<Float>,SIMD3<Float>,Float)]=[]
  camera.trace={o,d,m in calls.append((o,d,m));return hit(o,d,m,input["block"] as! Int)}
  normal.trace={hit($0,$1,$2,input["block"] as! Int)}
  let frame=camera.followFoot(foot,delta:delta,look:look)!,base=normal.followFoot(foot,delta:delta)!
  close(frame.source,v(expected["source"]!),"\(scenario["mode"]!) source")
  close(frame.target,v(expected["target"]!),"\(scenario["mode"]!) target")
  check(abs(NativeGameCamera.shortestAngle(frame.heading-number(expected,"heading")))<0.00003,"Wrapped reverse heading")
  check(abs(frame.pitch-number(expected,"pitch"))<0.00003,"Reverse pitch looks toward1.4m focus")
  check(abs(frame.verticalFov-number(expected,"fov"))<0.00003,"FOV is not reset")
  check(camera.heading==heading && camera.pitch==pitch,"Temporary view cannot mutate persistent yaw/pitch")
  check(camera.footTurning==normal.footTurning,"Aim/scope sensitivity history preserved")
  check(frame.source.z==base.source.z,"Retain ordinary camera height")
  check(frame.hidesPlayer==base.hidesPlayer,"Preserve scope visibility")
  check(frame.aimSource==base.aimSource,"Preserve independent aim origin")
  if look==nil || foot.aiming {
   check(frame.source==base.source && frame.target==base.target && frame.heading==base.heading && frame.pitch==base.pitch,"Release/aim returns the uninterrupted ordinary history")
  }else{held += 1}
  let queries=expected["collisions"] as! [[String:Any]]
  check(calls.count==queries.count,"Exact ordinary+reverse world-query count")
  for (call,query) in zip(calls,queries){close(call.0,v(query["origin"]!),"Query origin");close(call.1,v(query["direction"]!),"Query direction");check(abs(call.2-number(query,"distance"))<0.0001,"Query distance")}
  frames += 1
 }
}

let feet=SIMD3<Float>(1480,-1738,13),foot=NativeGameCamera.Foot(position:feet)
func boundary(_ wall:Float?,_ missing:Float?)->(NativeGameCamera,NativeGameCamera.Frame){
 let c=try! NativeGameCamera(data:data);c.setDirection(heading:0,pitch:0)
 c.trace={_,d,_ in d.y>0 ? wall:nil};c.unavailableDistance={_,d,_ in d.y>0 ? missing:nil}
 return (c,c.followFoot(foot,delta:0,look:"behind")!)
}
let (_,clear)=boundary(nil,nil),(_,wall)=boundary(0.1,nil)
check(abs(wall.source.y-feet.y-0.6)<0.0001,"Retain archived solid-wall .6m minimum")
check(clear.source.y>wall.source.y,"Normal reverse distance remains clear")
for distance:Float in [0,0.1,0.3,0.5,1] {
 let (_,limited)=boundary(nil,distance)
 check(limited.source.y-feet.y<=max(0,distance-0.3)+0.0001,"Unavailable boundary cannot be crossed by solid-wall minimum")
 check(limited.source.z==clear.source.z,"Unavailable boundary retains view height")
}
// Recorded native failure before the guard: pitch .057174 and unavailable
// reach0 produced Float eye==target==[1480,-1738,14.4]. Retain the ordinary
// view instead of relying on the renderer's generic direction fallback.
// Exercise both zero and sub-ULP front reach.
let table=try JSONSerialization.jsonObject(with:data) as! [String:Any]
let distances=table["footDistances"] as! [NSNumber],ordinaryReach=distances[1].floatValue+2
for missing:Float in [0,0.1,0.3,0.3000001] {
 let c=try NativeGameCamera(data:data),baseline=try NativeGameCamera(data:data)
 for camera in [c,baseline]{camera.setDirection(heading:0,pitch:asin(Float(0.2)/ordinaryReach));camera.unavailableDistance={_,d,_ in d.y>0 ? missing:nil}}
 let reversed=c.followFoot(foot,delta:0,look:"behind")!,normal=baseline.followFoot(foot,delta:0)!
 check(reversed.source==normal.source && reversed.target==normal.target,"Collapsed reverse view retains ordinary safe frame")
 check(simd_length_squared(reversed.target-reversed.source)>0,"Rendered view direction cannot collapse to zero")
 check(simd_normalize(reversed.target-reversed.source).x.isFinite,"Renderer normalization remains finite")
}
for invalid:Float in [.nan,.infinity,-1,100] {
 let (_,safe)=boundary(invalid,nil)
 check(safe.source==clear.source && safe.target==clear.target,"Reject malformed reverse trace result")
}
let (camera,_)=boundary(nil,nil)
check(camera.followFoot(foot,delta:-1,look:"behind")==nil,"Reject invalid tick")
check(camera.followFoot(.init(position:SIMD3(.nan,0,0)),delta:0,look:"behind")==nil,"Reject invalid feet")
let ordinary=try NativeGameCamera(data:data),reverse=try NativeGameCamera(data:data)
for i in 0..<120 {
 let f=NativeGameCamera.Foot(position:feet+SIMD3(Float(i)/20,0,0),crouching:i>20)
 ordinary.setDirection(heading:0.3,pitch:-0.2);reverse.setDirection(heading:0.3,pitch:-0.2)
 _ = ordinary.followFoot(f,delta:1/60);_ = reverse.followFoot(f,delta:1/60,look:"behind")
}
// A temporary frame must not replace the source used by later shake envelopes.
for c in [ordinary,reverse]{c.shake(at:feet+SIMD3(0,10,0),strength:0.5,nowMilliseconds:10000)}
let vehicle=NativeGameCamera.Vehicle(position:feet,forward:SIMD3(0,1,0),right:SIMD3(1,0,0),bounds:.init(maxX:1,minY:-2,maxZ:1.5))
let a=ordinary.followVehicle(vehicle,delta:1/60,nowMilliseconds:10010,random:{0.75})!,b=reverse.followVehicle(vehicle,delta:1/60,nowMilliseconds:10010,random:{0.75})!
check(a.source==b.source && a.target==b.target,"Reverse view cannot poison next vehicle shake source")
let report:[String:Any]=["authority":"Archived foot-follow + render wrapper; retail control mapping only, not retail runtime","frames":frames,"heldFrames":held,"checks":checks,"maximumPositionErrorMetres":Double(maxError)]
try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[3]))
print("PASS native foot look-behind:",frames,"actual wrapper frames,",checks,"checks, max position/query error",maxError,"m; release/history, aim/scope/crouch/ledge/parachute, wrap and boundaries")
