let address=ServerAddress(CommandLine.arguments[1])!,session=URLSession(configuration:.ephemeral)
let client=NativeMultiplayerClient(server:address,session:session)
var started=false,finished=false,checks=0
func check(_ ok:Bool,_ text:String){checks+=1;precondition(ok,text)}
client.onConnectionState={state in if state == .ready && !started{
 started=true
 client.reportImpactDamage(20);check(client.health==100&&client.armour==5,"Crash bypassed immediate armour prediction")
 client.reportLocalHealth(90);check(client.health==90&&client.armour==5,"Fall consumed armour")
 client.reportImpactDamage(20);check(client.health==75&&client.armour==0,"Mixed ordered crash/fall prediction differed")
}}
client.onStatus={text in
 if text=="MIXED IMPACT ACK"{
  check(client.health==75&&client.armour==0,"Partial acknowledgements doubled or restored impact damage")
  client.reportImpactDamage(200);check(client.health==0&&client.armour==0,"Fatal impact was not immediate")
 }else if text=="FATAL IMPACT ACK"{
  check(client.health==0&&client.armour==0,"Fatal impact acknowledgement changed predicted result")
  finished=true;client.disconnect()
 }
}
session.dataTask(with:address.path("api/local/state")){data,response,error in
 precondition(error==nil && (response as? HTTPURLResponse)?.statusCode==200 && data != nil)
 DispatchQueue.main.async{client.connect()}
}.resume()
let deadline=Date().addingTimeInterval(20)
while !finished&&Date()<deadline{RunLoop.main.run(until:Date().addingTimeInterval(0.005))}
check(finished,"Impact health transport timed out")
print("PASS actual native armour impact client: \(checks) checks; responsive shared health/armour prediction and matching ACKs")
