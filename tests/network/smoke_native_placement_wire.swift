// SPDX-License-Identifier: AGPL-3.0-only
// Same-file access invokes real private boundaries for stale-generation and
// forged-producer controls; no production test API or App dependency is added.
extension NativeMultiplayerClient {
    func placementFixtureSend(_ value:[String:Any]){send(value)}
    func placementFixtureOldTransport(_ value:[String:Any]){handle(value,generation:transportGeneration &- 1)}
    func placementFixtureCurrent(_ value:[String:Any]){handle(value,generation:transportGeneration)}
}
let origin=URL(string:CommandLine.arguments[1])!
let httpSession=URLSession(configuration:.ephemeral)
var checks=0
func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
func pump(_ seconds:Double=0.03){RunLoop.main.run(until:Date().addingTimeInterval(seconds))}
func wait(_ name:String,_ predicate:()->Bool){let deadline=Date().addingTimeInterval(7);while !predicate() && Date()<deadline{pump(0.005)};check(predicate(),"Timeout: \(name)")}
func request(_ endpoint:String,_ input:[String:Any]=[:])->[String:Any]{
 var req=URLRequest(url:origin.appendingPathComponent(endpoint));req.httpMethod="POST";req.httpBody=try!JSONSerialization.data(withJSONObject:input)
 var answer:[String:Any]?
 httpSession.dataTask(with:req){data,response,error in
  precondition(error==nil && (response as? HTTPURLResponse)?.statusCode==200)
  let value=try!JSONSerialization.jsonObject(with:data!)as![String:Any]
  DispatchQueue.main.async{answer=value}
 }.resume();wait("fixture HTTP \(endpoint)"){answer != nil};return answer!
}
func make(_ mode:String)->NativeMultiplayerClient{
 _=request("configure",["mode":mode]);return NativeMultiplayerClient(server:ServerAddress(origin.absoluteString)!,session:URLSession(configuration:.ephemeral),automaticRecoveryTimer:false)
}
func rows()->[[String:Any]]{request("seen")["packets"]as![[String:Any]]}
func meRows()->[[String:Any]]{rows().filter{$0["t"]as?String=="me"}}
let cab=RemoteVehicle(row:["fixture-cab","Authored cab","400",100,200,20,0,0,0,930,""])!
var client=make("strict"),teleports=0,markers=Set<String>(),cleanupWrites=false,disconnectDuringPlacement=false,vehicleCallbacks=0
var nonce=""
client.onVehicles={_ in vehicleCallbacks+=1}
client.onStatus={text in if text.hasPrefix("MARKER-"){markers.insert(text)}}
client.onInventoryConnection={connection in
 if let connection{nonce=connection;check(client.positionAcknowledgements && client.isPlacing && !client.isReady,"Hello callback lacks placement barrier")}
}
client.onTeleport={point,heading in
 teleports+=1
 check(client.positionAcknowledgements && client.isPlacing && !client.isReady,"Pose callback ran outside strict barrier")
 check(client.passengerSeat==nil && client.pendingVehicleEntry==nil,"TP callback retained seat/boarding ownership")
 if cleanupWrites {
  let previous=client.vehicles[cab.id]?.position,callbacks=vehicleCallbacks
  client.sendPosition(SIMD3(999,999,999),heading:0,moving:true,running:false)
  client.sendExit(SIMD3(999,999,999),parked:SIMD3(888,888,888),heading:0,pitch:0,roll:0,vehicle:cab,vehicleHealth:1)
  client.sendPassengerExit(SIMD3(999,999,999),heading:0)
  client.sendVehicleMove(cab.id,state:["x":999]);client.cancelVehicleEntry()
  client.placementFixtureSend(["t":"me","x":999,"placement":["connection":nonce,"revision":999]])
  check(!client.requestEnter(cab,seat:1) && client.reserveShot()==nil,"Placement callback granted gameplay")
  check(client.vehicles[cab.id]?.position==previous && vehicleCallbacks==callbacks,"Blocked exit mutated parked vehicle/UI callbacks")
 }
 if disconnectDuringPlacement {client.disconnect();return}
 if teleports==1{check(point==SIMD3(100.125,200.5,20.75) && heading == -0.75,"Hello precision/units changed")}
 else{check(point==SIMD3(300,400,20) && abs(heading! + .pi/2)<1e-6,"TP degrees/point changed")}
}
client.connect();wait("strict ready"){client.isReady}
check(client.positionAcknowledgements && !client.isPlacing && client.appliedPlacementRevision==0 && client.placementConnection==nonce,"Fresh placement not committed")
func sendAllPositions(){
 client.sendPosition(SIMD3(101,201,20),heading:0.3,moving:true,running:false)
 client.sendPosition(SIMD3(102,202,20),heading:0.4,moving:true,running:false,vehicle:cab,vehicleWork:1234)
 client.sendPosition(SIMD3(103,203,20),heading:0.5,moving:true,running:false,swimState:2,swimRatio:0.5)
 client.sendPosition(SIMD3(104,204,20),heading:0.6,moving:true,running:false,action:61)
 client.sendExit(SIMD3(105,205,20),parked:cab.position,heading:0.7,pitch:0,roll:0,vehicle:cab,vehicleHealth:930)
 check(client.requestEnter(cab,seat:1),"Ordinary passenger request rejected")
 wait("ordinary passenger seat"){client.passengerSeat != nil}
 client.sendPassengerPosition(SIMD3(106,206,20),heading:0.8,action:1,velocity:.zero,paused:false)
 client.sendPassengerExit(SIMD3(107,207,20),heading:0.9)
 client.placementFixtureSend(["t":"me","walking":true,"x":108,"placement":["connection":"forged","revision":999]])
}
sendAllPositions();wait("all position producers"){meRows().count==8}
for packet in meRows(){let envelope=packet["placement"]as![String:Any];check(envelope["connection"]as?String==nonce && envelope["revision"]as?Int==0,"Position producer omitted/forged applied envelope")}
check(client.requestEnter(cab,seat:1),"Pre-TP seat request failed");wait("pre-TP passenger"){client.passengerSeat != nil}
cleanupWrites=true
let before=meRows().count
let marker=request("teleport",["revision":1])["marker"]as!Int
wait("TP marker"){markers.contains("MARKER-\(marker)")}
check(teleports==2 && client.appliedPlacementRevision==1 && !client.isPlacing && client.isReady,"Valid TP did not commit")
check(meRows().count==before,"Cleanup leaked position or parked reports")
let duplicateMarker=request("duplicate")["marker"]as!Int;wait("duplicate hello marker"){markers.contains("MARKER-\(duplicateMarker)")}
check(teleports==2 && client.positionAcknowledgements && client.appliedPlacementRevision==1,"Duplicate hello rewound/downgraded")
let base:[String:Any]=["t":"tp","x":300,"y":400,"z":20,"h":90]
var malformed:[[String:Any]]=[]
for envelope in [NSNull(),true,[],[:],["connection":nonce,"revision":0],["connection":nonce,"revision":1],["connection":nonce,"revision":true],["connection":nonce,"revision":0.5],["connection":"old-placement-nonce-000","revision":2]]as[Any]{var p=base;p["placement"]=envelope;malformed.append(p)}
for field in ["x","y","z","h"]{for bad in [true,NSNull(),"1",[]]as[Any]{var p=base;p["placement"]=["connection":nonce,"revision":2];p[field]=bad;malformed.append(p)}}
let invalidMarker=request("emit",["packets":malformed])["marker"]as!Int;wait("invalid TP marker"){markers.contains("MARKER-\(invalidMarker)")}
check(teleports==2 && client.appliedPlacementRevision==1 && client.isReady,"Malformed/old TP changed state")
var old=base;old["placement"]=["connection":nonce,"revision":2]
client.placementFixtureOldTransport(old)
var nonfinite=old;nonfinite["x"]=Double.infinity;client.placementFixtureCurrent(nonfinite)
check(teleports==2 && client.appliedPlacementRevision==1,"Stale transport/nonfinite direct parser placement escaped")
sendAllPositions();wait("new revision producers"){meRows().count==16}
for packet in meRows().suffix(8){let envelope=packet["placement"]as![String:Any];check(envelope["connection"]as?String==nonce && envelope["revision"]as?Int==1,"New pose producer retained old envelope")}
let entryRequests=rows().filter{$0["t"]as?String=="enter"}.compactMap{$0["request"]as?Int}
check(zip(entryRequests,entryRequests.dropFirst()).allSatisfy{$0.0<$0.1},"Same-peer TP reused an entry request ID")
// Hold a real pre-TP entry response, then start a newer request on the same
// socket after placement. Both delayed positive and negative old ACKs must be
// unable to complete, cancel or grant that newer seat.
_=request("holdEntry")
check(client.requestEnter(cab,seat:1),"Pre-TP held entry failed")
let oldEntry=client.pendingVehicleEntry!
wait("old held entry reached peer"){rows().contains{$0["t"]as?String=="enter" && $0["request"]as?Int==oldEntry.request}}
let dropMarker=request("teleport",["revision":2])["marker"]as!Int
wait("second TP"){client.appliedPlacementRevision==2}
check(teleports==3,"Second valid TP missing")
var entryCallbacks=0;client.onPassengerEnter={_,_,_ in entryCallbacks+=1}
check(client.requestEnter(cab,seat:1),"Post-TP held entry failed")
let newEntry=client.pendingVehicleEntry!
check(newEntry.request>oldEntry.request,"Placement reused pending entry identity")
wait("new held entry reached peer"){rows().contains{$0["t"]as?String=="enter" && $0["request"]as?Int==newEntry.request}}
for accepted in [true,false]{
 let mark=request("replyEntry",["request":oldEntry.request,"accepted":accepted])["marker"]as!Int
 wait("delayed old entry ACK"){markers.contains("MARKER-\(mark)")}
 check(client.pendingVehicleEntry==newEntry && client.passengerSeat==nil && entryCallbacks==0,"Old entry ACK completed/canceled newer request")
}
let currentMark=request("replyEntry",["request":newEntry.request,"accepted":true])["marker"]as!Int
wait("current entry ACK"){markers.contains("MARKER-\(currentMark)")}
check(client.pendingVehicleEntry==nil && client.passengerSeat != nil && entryCallbacks==1,"Current post-TP entry ACK failed")
client.sendPassengerExit(SIMD3(107,207,20),heading:0.9)
disconnectDuringPlacement=true
_=request("teleport",["revision":3]);wait("callback disconnect"){client.state == .stopped}
check(client.appliedPlacementRevision==nil && !client.positionAcknowledgements && !client.isPlacing && !client.isReady,"Disconnected callback committed stale placement")
let stoppedRows=meRows().count;client.sendPosition(.zero,heading:0,moving:true,running:false);pump();check(meRows().count==stoppedRows,"Stopped client queued pose")
let oldNonce=nonce;disconnectDuringPlacement=false;cleanupWrites=false
// A replacement socket receives fresh pose/nonce; no pending position replay.
teleports=0;client.connect();wait("fresh replacement ready"){client.isReady}
check(nonce != oldNonce && client.appliedPlacementRevision==0 && teleports==1,"Reconnect retained placement state")
check(meRows().isEmpty,"Reconnect replayed queued positions")
// A server cannot silently establish a second namespace on one live socket.
_=request("emit",["packets":[["t":"hello","inventoryAck":1,"inventoryConnection":"different-connection-000000"]]])
wait("same socket namespace violation"){client.state == .reconnecting}
check(!client.isReady && client.inventoryConnection==nil && client.appliedPlacementRevision==nil,"Same-socket nonce change retained authority")
client.disconnect()
// Disconnect directly in the namespace callback must suppress the still-pending
// hello pose and all queued baseline callbacks for the old task.
let reentrant=make("strict");var reentrantTeleports=0
reentrant.onInventoryConnection={value in if value != nil{check(reentrant.isPlacing,"Reentrant namespace callback lost barrier");reentrant.disconnect()}}
reentrant.onTeleport={_,_ in reentrantTeleports+=1}
reentrant.connect();wait("namespace disconnect"){reentrant.state == .stopped};pump(0.1)
check(reentrantTeleports==0 && reentrant.appliedPlacementRevision==nil && !reentrant.positionAcknowledgements,"Reentrant namespace callback applied old hello")
for mode in ["bad-bool","bad-revision","bad-spot","bad-nonce","bad-health"]{
 let bad=make(mode);var callbacks=0
 bad.onTeleport={_,_ in callbacks+=1};bad.onInventoryConnection={if $0 != nil{callbacks+=1}}
 bad.connect();wait("invalid hello \(mode)"){bad.state == .reconnecting}
 check(callbacks==0 && !bad.isReady && bad.inventoryConnection==nil && bad.appliedPlacementRevision==nil,"Malformed strict hello partially unlocked")
 bad.disconnect()
}
let ownerless=make("strict")
ownerless.connect();wait("missing strict placement owner"){ownerless.state == .reconnecting}
check(!ownerless.isReady && ownerless.inventoryConnection==nil && ownerless.appliedPlacementRevision==nil,"Missing owner silently committed a placement")
ownerless.disconnect()
let legacy=make("legacy");var legacyTeleports=0
legacy.onTeleport={_,_ in legacyTeleports+=1;check(!legacy.positionAcknowledgements && !legacy.isPlacing,"Legacy callback became strict")}
legacy.connect();wait("legacy ready"){legacy.isReady};legacy.sendPosition(.zero,heading:0,moving:false,running:false)
wait("legacy position"){meRows().count==1};check(meRows()[0]["placement"]==nil,"Legacy pose unexpectedly tagged")
_=request("emit",["packets":[base]]);wait("legacy TP"){legacyTeleports==2};legacy.disconnect()
for mode in ["dead","dead-late"]{
let dead=make(mode);var respawns=0,respawnRevision:Int?,deadMarkers=Set<String>()
dead.onStatus={if $0.hasPrefix("MARKER-"){deadMarkers.insert($0)}}
dead.onTeleport={_,_ in check(dead.isPlacing && !dead.isReady,"Respawn placement lacks barrier")}
dead.onRespawn={respawns+=1;respawnRevision=dead.appliedPlacementRevision;check(dead.positionAcknowledgements && !dead.isPlacing,"Respawn ACK preceded applied TP")}
dead.connect();wait("dead ready"){dead.isReady};check(dead.health==0,"Hello healed dead account")
dead.respawn();wait("rejected respawn"){deadMarkers.contains("MARKER-1")};check(dead.health==0 && respawns==0 && dead.appliedPlacementRevision==0,"Rejected respawn moved/healed actor")
dead.respawn();wait("accepted respawn and newer placement"){dead.appliedPlacementRevision==2 && deadMarkers.contains("MARKER-2")}
check(dead.health==100 && respawns==1 && respawnRevision==(mode=="dead" ? 1:2),"Respawn ACK ordering/exactly-once failed")
dead.disconnect()
}
httpSession.invalidateAndCancel()
print("PASS actual NativeMP placement wire: \(checks) checks; all me producers, malformed/old transport, callback disconnect, legacy and respawn ordering")
