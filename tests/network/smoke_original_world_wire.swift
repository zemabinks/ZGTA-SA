import Foundation
var checks=0
func check(_ c:@autoclosure()->Bool,_ m:String){checks+=1;if !c(){fatalError(m)}}
let server=ServerAddress(CommandLine.arguments[1])!
let flavor=NativeMultiplayerClient.Flavor.originalWorld(build:"202611100434",deviceID:String(repeating:"a",count:32))
var clients:[NativeMultiplayerClient]=[],auth=0,readyCount=0,respawns=0,gunEvents=0,hitEvents=0
let definitions:[NativeOriginalWorldArsenal.Definition]=[
 .init(id:22,slot:2,capacity:17,kind:"INSTANT_HIT",wait:0,reload:1),.init(id:24,slot:2,capacity:7,kind:"INSTANT_HIT",wait:0,reload:1)]
let weapons=NativeWeaponState(catalog:[.init(id:22,name:"QA",model:"",range:40,capacity:17,interval:0.1,animation:"fixture",fireKind:"INSTANT_HIT"),.init(id:24,name:"QA2",model:"",range:40,capacity:7,interval:0.1,animation:"fixture",fireKind:"INSTANT_HIT")],policy:.originalWorld,originalDefinitions:definitions)
func strictDefault(){
 print("WIRE strict default phase");fflush(stdout)
 let client=NativeMultiplayerClient(server:server);clients.append(client)
 client.onOriginalGuns={_,_ in fatalError("Original inventory entered strict default")}
 client.onStatus={text in
  if text.contains("NEEDS NATIVE INVENTORY"){
   check(!client.isReady&&client.inventoryConnection==nil&&client.reserveShot()==nil,"Default cannot downgrade")
   check(!client.sendWeaponShot(weapon:22,from:.zero,to:.zero,player:nil),"Default cannot fire without ticket")
   client.onStatus=nil;client.disconnect();print("PASS original protocol actual native WebSocket flow: \(checks) checks");exit(0)
  }
 }
 client.connect()
}
func connected(){
 print("WIRE original join phase");fflush(stdout)
 let client=NativeMultiplayerClient(server:server,flavor:flavor);clients.append(client)
 client.onInventoryConnection={nonce in check(nonce==nil,"No fabricated inventory nonce");weapons.setConnection(nonce)}
 client.onOriginalGuns={rows,back in gunEvents+=1;check(weapons.applyOriginalGuns(rows,back:back),"Validated guns delivered")}
 client.onRespawn={
  respawns+=1
  if respawns==1 {
   check(!client.originalRespawnWasDead && abs(client.originalHealth-82.75)<1e-8 && abs(client.originalArmour-1.45)<1e-8,"Alive escape preserves fractional health/armour")
   check(weapons.weapons.map(\.id)==[0,22],"Alive escape does not revive staged equipment")
   check(weapons.selectOriginalWeapon(22)&&weapons.consumeAnimationShot(weapon:22),"Actual original local ammo event")
   check(client.sendWeaponShot(weapon:22,from:SIMD3(1,2,3),to:SIMD3(21,22,23),player:"7"),"Actual original shot send")
   check(client.recordMeleeStrike(weapon:0)&&client.sendMeleeHit(to:"7"),"Actual original melee")
   let rows=weapons.outgoingOriginalGuns(flush:true)!;check(client.sendOriginalGuns(rows),"Actual original guns send");weapons.originalGunsSent(rows)
   client.requestEnter(client.vehicles["taxi"]!)
  } else {
   check(respawns==2 && client.originalRespawnWasDead && client.health==100&&client.armour==0,"Approved dead original respawn vitals")
   weapons.reviveOriginalWeapons();check(weapons.weapons.map(\.id)==[0,24],"Original staged revive weapons")
  }
 }
 client.onIncomingHit={_ in hitEvents+=1}
 client.onEnter={id,accepted in
  check(id=="taxi"&&accepted,"Vehicle enter ACK")
  let vehicle=client.vehicles[id]!
  client.sendPosition(SIMD3(1,2,3),heading:0.7,moving:false,running:false,vehicle:vehicle)
  client.sendExit(SIMD3(4,5,6),parked:SIMD3(1,2,3),heading:0.7,pitch:0.1,roll:0.2,vehicle:vehicle,vehicleHealth:900,vehicleDamage:"fixture",footHeading:1.9)
  client.sendChat("/help");client.sendPosition(SIMD3(4,5,6),heading:1.9,moving:false,running:false,weapon:22)
  client.reportLocalHealth(0);client.reportLocalHealth(0)
 }
 client.onConnectionState={state in
  guard state == .ready else{return};readyCount+=1
  check(client.usesClientOwnedWeapons&&client.inventoryConnection==nil&&client.reserveShot()==nil,"Original explicit owner without ACK")
  if readyCount==1 {
   check(gunEvents==1&&client.localName=="Original fixture"&&client.cash==50,"Readiness waits for valid guns/world")
   check(abs(client.originalHealth-83.25)<1e-8 && abs(client.originalArmour-2.45)<1e-8 && client.health==84 && client.armour==3,"Hello retains fractional vitals beneath display ceiling")
   check(client.orderedPlayers.count==1&&abs(client.orderedPlayers[0].position.x-21)<0.001&&abs(client.orderedPlayers[0].heading+1.5)<0.001,"Actual binary baseline+delta")
  }else{
   check(readyCount==2&&client.orderedPlayers.isEmpty&&client.vehicles.isEmpty,"Reconnect clears binary and vehicle worlds")
   check(client.localName=="Original reconnected"&&weapons.weapons.map(\.id)==[0],"Fresh original inventory baseline")
   client.sendPosition(SIMD3(1,2,3),heading:0,moving:false,running:false)
  }
 }
 client.onStatus={text in
  if text=="FRACTIONAL HITS"{check(hitEvents==12 && abs(client.originalHealth-82.75)<1e-8 && abs(client.originalArmour-1.45)<1e-8,"Repeated subunit hits accumulate; fall/drown bypass armour");client.respawn()}
  if text=="REQUEST RESPAWN"{check(client.health==0&&respawns==1,"No optimistic revival");client.respawn()}
  if text=="ORIGINAL SERVER DECLINED RESPAWN"{check(client.health==0&&respawns==1,"Declined respawn preserves defeat");client.respawn()}
  if text=="RECONNECT NOW"{check(respawns==2&&client.players["88"] != nil,"Missing baseline recovery");client.requestInventoryResync()}
  if text=="RECONNECTED COMPLETE"{client.onStatus=nil;client.disconnect();strictDefault()}
 }
 client.connect()
}
func badVersion(){
 print("WIRE future protocol phase");fflush(stdout)
 let client=NativeMultiplayerClient(server:server,flavor:flavor);clients.append(client)
 client.onAuthenticationRequired={fatalError("Unsupported version treated as login")}
 client.onStatus={text in if text.contains("UNSUPPORTED") {check(!client.isReady&&client.state == .stopped,"Future protocol cannot unlock gameplay");client.onStatus=nil;connected()}}
 client.connect()
}
let guest=NativeMultiplayerClient(server:server,flavor:flavor);clients.append(guest)
guest.onAuthenticationRequired={auth+=1;check(auth==1 && !guest.isReady&&guest.state == .stopped,"Guest login cannot bypass service");guest.onAuthenticationRequired=nil;badVersion()}
print("WIRE guest phase");fflush(stdout)
guest.connect()
DispatchQueue.main.asyncAfter(deadline:.now()+20){fatalError("Native original fixture timeout")}
dispatchMain()
