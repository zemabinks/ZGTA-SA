let address=ServerAddress(CommandLine.arguments[1])!,session=URLSession(configuration:.ephemeral)
let client=NativeMultiplayerClient(server:address,session:session)
var started=false,finished=false,hits=0,checks=0
var attackerID:String?
func check(_ ok:Bool,_ message:String){checks+=1;precondition(ok,message)}
func publish(){
 let heading:Float=hits==2 ? -.pi:0,act=hits==3 ? 36:28
 client.sendPosition(SIMD3<Float>(1570,-2462,13.6),heading:heading,moving:false,running:false,action:act)
}
client.onConnectionState={state in if state == .ready && !started{started=true;publish()}}
client.onIncomingHit={hit in
 attackerID=hit.sourceID
 hits+=1;check(hits<=8,"Duplicate or invalid event identity replayed reaction")
 check(hit.parried==[1,2,6,7,8].contains(hits),"Native lost server parry decision")
 check(hit.authoritativeHealth==100 && client.health==100 && hit.wasAlive,"Accepted parry/absorbed hit changed health")
 check(hit.source==SIMD3<Float>(1570,-2460,13.6),"Front-hit source missing")
 check(client.armour==(hits<=2 ? 80:hits==3 ? 72:hits==4 ? 64:34),"Parry or armour absorption applied damage twice")
}
client.onStatus={text in
 if text=="LEGACY READY"{check(client.sendMeleeHit(to:attackerID!),"Native could not hit legacy defender")}
 if text=="LEGACY BLOCK COMPLETE"{finished=true;client.disconnect()}
 if text.hasPrefix("PARRY CASE "){
  check(hits==Int(text.split(separator:" ").last!)!,"Repeated unchanged-health event was lost")
  if hits==7{
   started=false;client.disconnect();DispatchQueue.main.async{client.connect()}
  }else if hits<8{publish()}
 }
}
session.dataTask(with:address.path("api/local/state")){data,response,error in
 precondition(error==nil && (response as? HTTPURLResponse)?.statusCode==200 && data != nil)
 DispatchQueue.main.async{client.connect()}
}.resume()
let deadline=Date().addingTimeInterval(20)
while !finished && Date()<deadline{RunLoop.main.run(until:Date().addingTimeInterval(0.005))}
check(finished,"Native parry backend timed out")
print("PASS actual native parry client: \(checks) checks; repeated unchanged-health events, malformed/duplicate/stale identity rejection and armour ownership")
