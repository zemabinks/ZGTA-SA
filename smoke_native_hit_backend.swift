let address=ServerAddress(CommandLine.arguments[1])!,session=URLSession(configuration:.ephemeral)
let client=NativeMultiplayerClient(server:address,session:session)
var started=false,finished=false,hits=0,checks=0
func check(_ ok:Bool,_ message:String){checks+=1;precondition(ok,message)}
func publish(_ down:Int=0){client.sendPosition(SIMD3<Float>(1572,-2460,13.6),heading:0,moving:false,running:false,down:down)}
client.onConnectionState={state in if state == .ready && !started{started=true;publish()}}
client.onIncomingHit={hit in
 hits+=1;check(hits<=2,"Duplicate event replayed reaction")
 check(hit.weapon==0 && hit.damage>0 && hit.wasAlive,"Actual accepted hit lost weapon/damage/prior life")
 check(hit.source==SIMD3<Float>(1570,-2460,13.6) && hit.sourceID != nil,"Event-time attacker position missing")
 check(hit.authoritativeHealth==client.health,"Reaction applied before matching health authority")
 if hits==1{check(client.health==100-Int(hit.damage),"Nonfatal health applied twice")}
 else{check(client.health==0 && hit.wasAlive,"Snapshot-before-fatal hit suppressed actual death cause")}
}
client.onStatus={text in
 if text=="FIRST HIT COMPLETE"{check(hits==1,"First duplicate changed reaction count");publish(2)}
 if text=="DOWN OBSERVED"{publish()}
 if text=="FATAL HIT COMPLETE"{check(hits==2,"Fatal duplicate changed reaction count");finished=true;client.disconnect()}
}
session.dataTask(with:address.path("api/local/state")){data,response,error in
 precondition(error==nil && (response as? HTTPURLResponse)?.statusCode==200 && data != nil)
 DispatchQueue.main.async{client.connect()}
}.resume()
let deadline=Date().addingTimeInterval(20)
while !finished && Date()<deadline{RunLoop.main.run(until:Date().addingTimeInterval(0.005))}
check(finished,"Actual native hit backend timed out")
print("PASS actual native hit client: \(checks) checks; accepted event context, single health/reaction ownership, fatal snapshot race and down tags")
