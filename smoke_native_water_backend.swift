let address=ServerAddress(CommandLine.arguments[1])!,session=URLSession(configuration:.ephemeral)
let client=NativeMultiplayerClient(server:address,session:session)
var started=false,finished=false,respawns=0,checks=0
func check(_ ok:Bool,_ text:String){checks+=1;precondition(ok,text)}
client.onConnectionState={state in if state == .ready && !started{
 started=true
 guard let vehicle=client.vehicles["fixture-wreck"] else{preconditionFailure("Synthetic owned car missing")}
 client.sendPosition(SIMD3(1570,-2460,13.6),heading:0,moving:true,running:false,vehicle:vehicle)
}}
client.onRespawn={respawns+=1}
client.onStatus={text in
 if text=="LEAVE SUNKEN VEHICLE"{
  let health=client.health
  client.sendExit(SIMD3(1572,-2460,-2),parked:SIMD3(1570,-2460,-4),heading:0,pitch:0,roll:0,
   vehicle:client.vehicles["fixture-wreck"]!,vehicleHealth:800)
  check(client.health==health && health==100,"Water exit changed local life")
 }else if text=="REENTER AFTER WATER"{
  check(client.vehicles["fixture-wreck"]!.health==800,"Water exit lost parked state")
  client.sendPosition(SIMD3(1570,-2460,13.6),heading:0,moving:false,running:false,vehicle:client.vehicles["fixture-wreck"]!,vehicleHealth:800)
 }else if text=="WRECK NOW"{
  client.reportLocalHealth(0);check(client.health==0&&client.armour==25,"Wreck health was not immediate")
  client.reportLocalHealth(0)
  client.sendExit(SIMD3(1572,-2460,13.6),parked:SIMD3(1570,-2460,13.6),heading:0,pitch:0,roll:0,
   vehicle:client.vehicles["fixture-wreck"]!,vehicleHealth:0)
 }else if text=="RESPAWN AFTER WRECK"{
  check(client.health==0&&client.vehicles["fixture-wreck"]!.health==0,"Exit restored victim or hull health")
  client.respawn();check(client.health==0,"Respawn became live before authority")
 }else if text=="WRECK TRANSPORT COMPLETE"{
  check(client.health==100&&respawns==1&&client.vehicles["fixture-wreck"]!.health==0,"Respawn revived old wreck or repeated callback")
  finished=true;client.disconnect()
 }
}
client.onVitals={health,_ in
 if health==100&&respawns==0&&started&&client.vehicles["fixture-wreck"]?.health==0{
  // onRespawn is delivered after onVitals; publish on the next main turn.
  DispatchQueue.main.async{if respawns==1{client.sendPosition(SIMD3(1572,-2460,13.6),heading:0,moving:false,running:false)}}
 }
}
session.dataTask(with:address.path("api/local/state")){data,response,error in
 precondition(error==nil && (response as? HTTPURLResponse)?.statusCode==200 && data != nil)
 DispatchQueue.main.async{client.connect()}
}.resume()
let deadline=Date().addingTimeInterval(20)
while !finished&&Date()<deadline{RunLoop.main.run(until:Date().addingTimeInterval(0.005))}
check(finished,"Wreck transport timed out")
print("PASS actual native water/wreck client: \(checks) checks; immediate fatal/exit and authority-owned respawn")
