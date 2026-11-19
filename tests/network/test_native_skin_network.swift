import Foundation
import simd

let server=ServerAddress(CommandLine.arguments[1])!
let configuration=URLSessionConfiguration.ephemeral
let session=URLSession(configuration:configuration)
var checks=0
func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
func pump(){RunLoop.main.run(until:Date().addingTimeInterval(0.015))}
func wait(_ message:String,_ body:()->Bool){let end=Date().addingTimeInterval(8);while !body() && Date()<end{pump()};check(body(),message)}
func request(_ path:String,body:[String:Any]?=nil)->[String:Any]{
 var request=URLRequest(url:server.path(path));if let body{request.httpMethod="POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type");request.httpBody=try! JSONSerialization.data(withJSONObject:body)}
 var result:(Data?,URLResponse?,Error?)?
 session.dataTask(with:request){result=($0,$1,$2)}.resume()
 wait("Isolated HTTP response missing"){result != nil}
 check((result!.1 as? HTTPURLResponse)?.statusCode==200,"Fixture HTTP status")
 return try! JSONSerialization.jsonObject(with:result!.0!)as![String:Any]
}
let index=request("game/native/models/index.json")["peds"]as![String:String]
let catalog=request("game/native/samp-skins.json")["skins"]as![[String:Any]]
check(index["7"]=="male01" && index["14"]=="bmori" && index["2"]=="maccer","Overlay HTTP still uses compact skin IDs")
check(catalog.first{$0["legacyID"]as?Int==2}?["model"]as?String=="maccer","Maccer catalogue source missing")
let client=NativeMultiplayerClient(server:server,session:session)
// Explicit headless placement owner; this fixture does not render a world.
var observedPlacement:SIMD3<Float>?
client.onTeleport={point,heading in
 check([point.x,point.y,point.z].allSatisfy(\.isFinite) && heading?.isFinite != false,"Invalid authoritative placement")
 observedPlacement=point
}
defer{client.disconnect();session.invalidateAndCancel()}
client.connect();wait("Actual native client not ready"){client.isReady}
check(client.localSkin==7,"Native default changed unexpectedly")
let initial=request("__fixture"),browserID=String(initial["browserNumber"]as!Int)
let vehicle=RemoteVehicle(row:["fixture-native","Synthetic vehicle","411.0.0.0.",1480,-1738,13,0])!
var entered:(String,Bool)?
client.onEnter={entered=($0,$1)}
var directions=0,unsupported=0
let expected=[7:"male01",14:"bmori",9:"bfori",24:"wbdyg1",287:"army",2:"maccer",149:"ogloc",293:"ogloc"]
for skin in [7,14,9,24,287,2,149,293]{for driving in [false,true]{
 if skin != 7 || driving {client.setLocalSkin(skin)}
 if driving{
  entered=nil
  check(client.requestEnter(vehicle),"Actual native entry request was not emitted")
  wait("Actual native driver entry ACK missing or rejected"){entered?.0==vehicle.id && entered?.1==true}
 }else if directions>0{
  client.sendExit(SIMD3(1480,-1738,13),parked:SIMD3(1480,-1738,13),heading:0,pitch:0,roll:0,vehicle:vehicle,vehicleHealth:1000)
 }
 client.sendPosition(SIMD3(1480,-1738,13),heading:0,moving:false,running:false,vehicle:driving ? vehicle:nil)
 var snapshot:[String:Any]=[:]
 wait("Actual native packet not observed over browser WebSocket"){
  snapshot=request("__fixture")
  guard let message=(snapshot["nativeMessages"]as?[[String:Any]])?.last,
        message["skin"]as?Int==skin,message["driving"]as?Bool==driving else{return false}
  return (snapshot["browserRows"]as?[[String:Any]])?.contains{row in
   row["skin"]as?Int==skin && (driving ? !(row["code"]as?String ?? "").hasPrefix("s"):row["code"]as?String=="s\(skin)")
  }==true
 }
 directions+=1
 _=request("__fixture",body:["skin":skin,"driving":driving])
 wait("Actual native updateRows did not receive browser skin"){
  client.players[browserID].map{$0.skin==skin && (driving ? !$0.code.hasPrefix("s"):$0.code=="s\(skin)")}==true
 }
 directions+=1
 if let model=index[String(skin)]{check(model==expected[skin],"Reciprocal rendered-model lookup differs")}
 else{unsupported+=1;check(skin==149 || skin==293,"Unexpected unconverted model")}
}}
check(directions==32 && unsupported==4,"Missing reciprocal foot/driver cases")
print("PASS actual skin WebSockets: \(checks) checks; \(directions) bidirectional foot/driver cases; explicit149/293 OG Loc resource gaps")
