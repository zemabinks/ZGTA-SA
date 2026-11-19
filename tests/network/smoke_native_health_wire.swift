let session=URLSession(configuration:.ephemeral)
let address=ServerAddress(CommandLine.arguments[1])!
let client=NativeMultiplayerClient(server:address,session:session)

// Headless protocol owner records the actual authoritative placement. This
// fixture exercises transport/state, not a rendered world or physical egress.
var observedPlacement:SIMD3<Float>?
client.onTeleport={point,heading in
 precondition([point.x,point.y,point.z].allSatisfy(\.isFinite) && heading?.isFinite != false)
 observedPlacement=point
}
var phase=0,finished=false,trace:[Int]=[],firstConnection:String?,respawns=0
client.onRespawn={respawns+=1}
client.onVitals={health,armour in
 trace.append(health)
 if phase==1 && health==60 {precondition(armour==25)}
}
client.onConnectionState={state in
 if state == .ready && phase==0 {
  phase=1;firstConnection=client.inventoryConnection
  client.reportLocalHealth(60)
  precondition(client.health==60 && client.armour==25,"local damage not immediately visible")
 }
}
client.onStatus={message in
 if message=="HEALTH PHASE ONE" {
  precondition(client.health==43 && client.armour==0,"server/local damage composition failed")
  precondition(trace.contains(60) && trace.filter{$0==50}.count>=2,"pending-loss rebase was not observed")
  phase=2
  session.dataTask(with:address.path("fixture/stale")){data,response,error in
   precondition(error==nil && (response as? HTTPURLResponse)?.statusCode==200)
   let state=try! JSONSerialization.jsonObject(with:data!) as! [String:Any]
   DispatchQueue.main.async {
    client.syncVitals(from:state)
    precondition(client.health==43 && client.armour==0,"old HTTP rolled back acknowledged WS damage")
    client.reportLocalHealth(0);precondition(client.health==0);phase=3
   }
  }.resume()
 } else if message=="FATAL ACK" {
  precondition(client.health==0);client.respawn()
  precondition(client.health==0,"respawn became live before authoritative acceptance")
 } else if message=="TRY RESPAWN" {
  precondition(client.health==0 && respawns==0);client.respawn()
 } else if message=="RESPAWNED" {
  precondition(client.health==100 && client.armour==0 && respawns==1);phase=5
  client.reportLocalHealth(70);precondition(client.health==70)
 } else if message=="HEALTH REJOINED" {
  precondition(phase==5 && client.isReady && client.health==70 && client.armour==0)
  precondition(client.inventoryConnection != firstConnection,"reconnect reused the old health namespace")
  finished=true;client.disconnect()
 }
}
client.connect()
let deadline=Date().addingTimeInterval(50)
while !finished && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
precondition(finished,"native health runtime did not complete")
print("PASS native health callback trace: \(trace)")
