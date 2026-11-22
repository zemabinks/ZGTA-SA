import Foundation
var checks=0
func check(_ c:@autoclosure()->Bool,_ m:String){checks+=1;if !c(){fatalError(m)}}
let server=ServerAddress(CommandLine.arguments[1])!
let flavor=NativeMultiplayerClient.Flavor.originalWorld(build:"202611100434",deviceID:String(repeating:"a",count:32))
var clients:[NativeMultiplayerClient]=[],auth=0,readyCount=0,respawns=0,gunEvents=0,hitEvents=0
var trafficKinds:[Int]=[],trafficLevels:[Double]=[],trafficResets=0,forcedSeats=0
var trafficCrews=0
for value:Any in [true,-1,0.5,"17",65536] {
 var row:[Any]=["authored","owner","420.1.2.0.",0,0,0,0]
 while row.count<15{row.append(NSNull())};row[14]=value
 check(RemoteVehicle(row:row)?.trafficSourceID==nil,"Invalid numeric traffic provenance accepted")
}
let definitions:[NativeOriginalWorldArsenal.Definition]=[
 .init(id:22,slot:2,capacity:17,kind:"INSTANT_HIT",wait:0,reload:1),.init(id:24,slot:2,capacity:7,kind:"INSTANT_HIT",wait:0,reload:1)]
let weapons=NativeWeaponState(catalog:[.init(id:22,name:"QA",model:"",range:40,capacity:17,interval:0.1,animation:"fixture",fireKind:"INSTANT_HIT"),.init(id:24,name:"QA2",model:"",range:40,capacity:7,interval:0.1,animation:"fixture",fireKind:"INSTANT_HIT")],policy:.originalWorld,originalDefinitions:definitions)
func strictDefault(){
 print("WIRE strict default phase");fflush(stdout)
 let client=NativeMultiplayerClient(server:server);clients.append(client)
 client.onAmbientTrafficConfiguration={level,_ in check(level==0,"Unnegotiated default flavor consumed original traffic")}
 client.onAmbientTrafficEvent={_,_,_ in fatalError("Original traffic entered strict default")}
 client.onOriginalGuns={_,_ in fatalError("Original inventory entered strict default")}
 client.onOriginalCommand={packet in if packet["t"]as?String=="gangs"{fatalError("Unnegotiated default consumed traffic crew configuration")}}
 client.onStatus={text in
  if text.contains("NEEDS NATIVE INVENTORY"){
   check(!client.isReady&&client.inventoryConnection==nil&&client.reserveShot()==nil,"Default cannot downgrade")
   check(!client.sendWeaponShot(weapon:22,from:.zero,to:.zero,player:nil),"Default cannot fire without ticket")
   client.onStatus=nil;client.disconnect();negotiatedDefault()
  }
 }
 client.connect()
}
func negotiatedDefault(){
 print("WIRE negotiated default population phase");fflush(stdout)
 let client=NativeMultiplayerClient(server:server);clients.append(client)
 var kinds:[Int]=[],levels:[Double]=[],crews=0
 client.onAmbientTrafficConfiguration={level,hash in
  if level>0{levels.append(level);check(hash=="1234abcd","Negotiated default traffic graph identity")}
 }
 client.onAmbientTrafficEvent={event,_,_ in
  switch event {
  case .base:kinds.append(4)
  case .more:kinds.append(9)
  case .crew:kinds.append(33)
  case .free:kinds.append(36)
  case .ahead:kinds.append(34)
  case .fast:kinds.append(37)
  case .plates:kinds.append(6)
  case .shots:kinds.append(31)
  case .gone:kinds.append(5)
  }
 }
 client.onOriginalCommand={packet in
  if packet["t"]as?String=="gangs"{crews+=1;check((packet["g"]as?[[Any]])?.count==1,"Negotiated default crew rows")}
 }
 client.onOriginalGuns={_,_ in fatalError("Negotiated default switched to original inventory")}
 client.onConnectionState={state in
  guard state == .ready else{return}
  check(client.inventoryConnection=="traffic-peer-000000000000" && !client.usesClientOwnedWeapons,"Negotiated default lost strict inventory ownership")
  check(levels==[1] && kinds==[4,9,33,36,34,37,6,31,5] && crews==1,"Negotiated default traffic/crew dispatch")
  check(!client.canRequestTrafficVehicle,"Population-only negotiation granted interactive traffic")
  client.disconnect();trafficOnly()
 }
 client.connect()
}
func trafficOnly(){
 print("WIRE independent traffic-only phase");fflush(stdout)
 let client=NativeMultiplayerClient(server:server);clients.append(client)
 var kinds=0,configured=false,revoked=false,requested=false,pedConfigurations=0,pedEvents=0
 client.onAmbientPedestrianConfiguration={level,_ in if level>0{pedConfigurations+=1}}
 client.onAmbientPedestrianEvent={_,_,_ in pedEvents+=1}
 client.onAmbientTrafficConfiguration={level,hash in
  if level>0{check(level==1&&hash=="1234abcd","Traffic-only graph identity");configured=true}
  else if configured{revoked=true}
 }
 client.onAmbientTrafficEvent={_,_,_ in kinds+=1}
 client.onConnectionState={state in
  guard state == .ready,!requested else{return};requested=true
  check(configured&&kinds==9&&client.canRequestTrafficVehicle,"Independent traffic-only channel not negotiated")
  check(client.inventoryConnection=="traffic-only-000000000000" && !client.usesClientOwnedWeapons,"Traffic-only hello changed weapon authority")
  check(client.requestTrafficVehicle(17),"Ready traffic-only client refused materialization request")
 }
 client.onStatus={text in
  guard text=="TRAFFIC MATERIALIZATION REQUEST SEEN"else{return}
  check(revoked && !client.canRequestTrafficVehicle && kinds==9,"Traffic capability revocation did not retire its old scene configuration")
  check(pedConfigurations==0&&pedEvents==0,"Traffic-only capability admitted an unnegotiated pedestrian channel")
  client.disconnect()
  check(!client.canRequestTrafficVehicle && !client.requestTrafficVehicle(17),"Disconnected session retained interactive traffic authority")
  invalidTrafficCapability()
 }
 client.connect()
}
func invalidTrafficCapability(){
 print("WIRE invalid independent traffic capability phase");fflush(stdout)
 let client=NativeMultiplayerClient(server:server);clients.append(client)
 client.onAmbientTrafficConfiguration={level,_ in check(level==0,"Boolean traffic capability enabled traffic")}
 client.onAmbientTrafficEvent={_,_,_ in fatalError("Boolean capability admitted traffic binary state")}
 client.onConnectionState={state in
  guard state == .ready else{return}
  check(!client.canRequestTrafficVehicle && !client.requestTrafficVehicle(17),"Boolean capability granted materialization authority")
  client.disconnect();reentrantTrafficConfiguration()
 }
 client.connect()
}
func reentrantTrafficConfiguration(){
 print("WIRE traffic configuration callback lifetime phase");fflush(stdout)
 let client=NativeMultiplayerClient(server:server);clients.append(client)
 var teleports=0,configurations=0
 client.onTeleport={_,_ in teleports+=1}
 client.onAmbientTrafficConfiguration={level,_ in
  guard level>0 else{return};configurations+=1;client.disconnect()
  DispatchQueue.main.asyncAfter(deadline:.now()+0.05){
   check(configurations==1&&teleports==0,"Retired traffic configuration callback applied its old hello teleport")
   check(!client.isReady && !client.canRequestTrafficVehicle,"Configuration callback revived its retired connection")
   print("PASS original/default protocol actual native WebSocket flow: \(checks) checks");exit(0)
  }
 }
 client.connect()
}
func connected(){
 print("WIRE original join phase");fflush(stdout)
 let client=NativeMultiplayerClient(server:server,flavor:flavor);clients.append(client)
 client.onOriginalCommand={packet in
  guard packet["t"]as?String=="gangs"else{return}
  trafficCrews+=1
  check((packet["g"]as?[[Any]])?.count==1,"Original traffic crew configuration lost raw typed rows")
 }
 client.onAmbientTrafficConfiguration={level,hash in
  if level==0{trafficResets+=1;trafficKinds=[]}
  else{trafficLevels.append(level);if level==1{check(hash=="1234abcd","Original traffic graph identity")};if level==2||level==3{check(hash==nil,"Level update invented a graph identity")}}
 }
 client.onAmbientTrafficEvent={event,now,received in
  check(now.isFinite&&now>0&&received.isFinite&&received>0,"Traffic callback clock domains")
  switch event {
  case .base(_,let rows):check(rows.count==1&&rows[0].identity.id==17&&rows[0].identity.model==420,"Real wire traffic base");trafficKinds.append(4)
  case .more(let rows):check(rows[0].side == -1&&rows[0].health==900,"Real wire traffic metadata");trafficKinds.append(9)
  case .crew(let rows):check(rows[0].count==0,"Traffic driver with zero additional crew");trafficKinds.append(33)
  case .free(_,let rows):check(rows[0].position==SIMD3(4,5,6)&&rows[0].speed == -2&&rows[0].turn == -0.25,"Signed free traffic and GTA axes");trafficKinds.append(36)
  case .ahead(let rows):check(rows[0].legs.count==2&&rows[0].legs[1].lane==2,"Traffic route window");trafficKinds.append(34)
  case .fast(let rows):check(rows[0].speed==1&&rows[0].wanted==2,"Traffic speed metadata");trafficKinds.append(37)
  case .plates(let rows):check(rows[0].text=="QA","Traffic plate text");trafficKinds.append(6)
  case .shots(let rows):check(rows[0].target==SIMD3(1,2,3)&&rows[0].weapon==22,"Traffic shot observation");trafficKinds.append(31)
  case .gone(let ids):check(ids==[17],"Traffic removal identity");trafficKinds.append(5)
  }
 }
 client.onInventoryConnection={nonce in check(nonce==nil,"No fabricated inventory nonce");weapons.setConnection(nonce)}
 client.onOriginalGuns={rows,back in gunEvents+=1;check(weapons.applyOriginalGuns(rows,back:back),"Validated guns delivered")}
 client.onRespawn={
  respawns+=1
  if respawns==1 {
   check(!client.originalRespawnWasDead && abs(client.originalHealth-82.75)<1e-8 && abs(client.originalArmour-1.45)<1e-8,"Alive escape preserves fractional health/armour")
   check(weapons.weapons.map(\.id)==[0,22],"Alive escape does not revive staged equipment")
   check(weapons.selectOriginalWeapon(22)&&weapons.consumeAnimationShot(weapon:22),"Actual original local ammo event")
   check(client.sendWeaponShot(weapon:22,from:SIMD3(1,2,3),to:SIMD3(21,22,23),player:"7"),"Actual original shot send")
   let grouped:[NativeLocalShots.Claim]=[
    .init(origin:SIMD3(1,2,3),end:SIMD3(21,22,23),kind:1,target:.init(id:"7",kind:1,piece:9),pellets:8),
    .init(origin:SIMD3(1,2,3),end:SIMD3(25,26,27),kind:3,target:.init(id:"t42",kind:3,wheel:0),pellets:7)]
   check(client.sendOrdinaryShotBatch(weapon:25,claims:grouped,ticket:nil),"Actual original grouped transport")
   let invalid=NativeLocalShots.Claim(origin:SIMD3(.nan,0,0),end:.zero,kind:0,target:nil,pellets:1)
   check(!client.sendOrdinaryShotBatch(weapon:25,claims:[grouped[0],invalid],ticket:nil),"Invalid entire batch cannot partially queue")
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
  if id=="arbitrary-registered"{
   forcedSeats+=1;check(accepted&&client.vehicles[id]?.trafficSourceID==17,"Explicit spawned seating retains arbitrary registered/traffic identities");return
  }
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
   check(trafficKinds==[4,9,33,36,34,37,6,31,5]&&trafficLevels==[1,3,2],"Typed traffic delivery/configuration order")
   check(trafficCrews==1,"Original traffic crew configuration was swallowed")
   check(client.vehicles["taxi"]?.trafficSourceID==17,"Registered traffic provenance")
   check(gunEvents==1&&client.localName=="Original fixture"&&client.cash==50,"Readiness waits for valid guns/world")
   check(abs(client.originalHealth-83.25)<1e-8 && abs(client.originalArmour-2.45)<1e-8 && client.health==84 && client.armour==3,"Hello retains fractional vitals beneath display ceiling")
   check(client.orderedPlayers.count==1&&abs(client.orderedPlayers[0].position.x-21)<0.001&&abs(client.orderedPlayers[0].heading+1.5)<0.001,"Actual binary baseline+delta")
  }else{
   check(trafficKinds.isEmpty&&trafficResets>0,"Reconnect retained old traffic records")
   check(readyCount==2&&client.orderedPlayers.isEmpty&&client.vehicles.isEmpty,"Reconnect clears binary and vehicle worlds")
   check(client.localName=="Original reconnected"&&weapons.weapons.map(\.id)==[0],"Fresh original inventory baseline")
   client.sendPosition(SIMD3(1,2,3),heading:0,moving:false,running:false)
  }
 }
 client.onStatus={text in
  if text=="FRACTIONAL HITS"{check(hitEvents==12 && abs(client.originalHealth-82.75)<1e-8 && abs(client.originalArmour-1.45)<1e-8,"Repeated subunit hits accumulate; fall/drown bypass armour");client.respawn()}
  if text=="REQUEST RESPAWN"{check(client.health==0&&respawns==1,"No optimistic revival");client.respawn()}
  if text=="ORIGINAL SERVER DECLINED RESPAWN"{check(client.health==0&&respawns==1,"Declined respawn preserves defeat");client.respawn()}
  if text=="RECONNECT NOW"{check(respawns==2&&client.players["88"] != nil&&forcedSeats==1,"Missing baseline or authoritative seating command");client.requestInventoryResync()}
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
