import Foundation
import simd

var checks=0
func check(_ condition:@autoclosure()->Bool,_ message:String){checks+=1;precondition(condition(),message)}
func pump(_ seconds:Double=0.02){RunLoop.main.run(until:Date().addingTimeInterval(seconds))}
func wait(_ message:String,seconds:Double=8,_ condition:()->Bool){
    let deadline=Date().addingTimeInterval(seconds)
    while !condition() && Date()<deadline{pump()}
    precondition(condition(),message)
}
func request(_ url:URL,session:URLSession = .shared,body:[String:Any]?=nil)->[String:Any]{
    var req=URLRequest(url:url);if let body{req.httpMethod="POST";req.httpBody=try! JSONSerialization.data(withJSONObject:body);req.setValue("application/json",forHTTPHeaderField:"Content-Type")}
    var outcome:(Data?,URLResponse?,Error?)?
    session.dataTask(with:req){outcome=($0,$1,$2)}.resume()
    wait("Fixture HTTP completion timed out"){outcome != nil}
    precondition((outcome!.1 as? HTTPURLResponse)?.statusCode==200,"Fixture HTTP failure")
    return try! JSONSerialization.jsonObject(with:outcome!.0!) as! [String:Any]
}
let server=ServerAddress(CommandLine.arguments[1])!,controlURL=URL(string:CommandLine.arguments[2])!
func control(_ command:String,_ args:[String:Any]=[:])->[String:Any]{request(controlURL,body:["command":command,"args":args])}
func snapshot()->[String:Any]{control("report")["snapshot"] as! [String:Any]}
func events()->[[String:Any]]{control("report")["events"] as! [[String:Any]]}
func held(_ tag:String)->Bool{(snapshot()["held"] as! [String]).contains(tag)}
func httpRequests()->[[String:Any]]{snapshot()["requests"] as! [[String:Any]]}
func rules(_ rows:[[String:Any]]){_ = control("rules",["rules":rows])}
func release(_ tag:String){_ = control("release",["tag":tag])}
func player(_ name:String)->[String:Any]{(snapshot()["players"] as! [[String:Any]]).first{$0["name"] as? String==name}!}

final class Probe:NSObject,URLSessionTaskDelegate,URLSessionWebSocketDelegate {
    private let lock=NSLock();private var opened=0,failed=0
    var counts:(Int,Int){lock.lock();defer{lock.unlock()};return(opened,failed)}
    func urlSession(_ session:URLSession,webSocketTask:URLSessionWebSocketTask,didOpenWithProtocol protocol:String?){lock.lock();opened+=1;lock.unlock()}
    func urlSession(_ session:URLSession,webSocketTask:URLSessionWebSocketTask,didCloseWith closeCode:URLSessionWebSocketTask.CloseCode,reason:Data?){}
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){if error != nil{lock.lock();failed+=1;lock.unlock()}}
}
let account=request(server.path("api/auth/me")),guestID=account["id"] as! String
_=control("seed",["id":guestID])
var now=1000.0
let probe=Probe(),session=URLSession(configuration:.default,delegate:probe,delegateQueue:nil)
let client=NativeMultiplayerClient(server:server,session:session,clock:{now},automaticRecoveryTimer:false)

// Headless protocol owner records the actual authoritative placement. This
// fixture exercises transport/state, not a rendered world or physical egress.
var observedPlacement:SIMD3<Float>?
client.onTeleport={point,heading in
 precondition([point.x,point.y,point.z].allSatisfy(\.isFinite) && heading?.isFinite != false)
 observedPlacement=point
}
let http=NativeGameplayClient(server:server)
defer {
    client.disconnect();session.invalidateAndCancel()
    for cookie in HTTPCookieStorage.shared.cookies(for:server.url) ?? [] where cookie.name=="zgta_local" && cookie.value==guestID {
        HTTPCookieStorage.shared.deleteCookie(cookie)
    }
}
var states:[NativeMultiplayerClient.ConnectionState]=[],nonces:[String]=[],inventories:[[String:Any]]=[],chat:[String]=[]
var httpStates:[[String:Any]]=[],results:[String]=[]
client.onInventoryConnection={nonce in http.inventoryConnection=nonce;if let nonce{nonces.append(nonce)}}
client.onConnectionState={state in states.append(state);http.setConnectionReady(state == .ready)}
client.onInventory={inventories.append($0)}
client.onChat={chat=$0}
http.onState={httpStates.append($0)};http.onResult={results.append($0)}
let feet=SIMD3<Float>(1480,-1738,13)
func position(){client.sendPosition(feet,heading:0,moving:false,running:false,weapon:22)}
func advance(_ seconds:Double){for _ in 0..<Int((seconds/0.1).rounded()){now+=0.1;client.tickConnection(now:now);pump(0.003)}}
func ready(){wait("Native transport did not become ready",seconds:12){client.isReady}}
func ammo()->Int{let rows=inventories.last?["weapons"] as? [[String:Any]] ?? [];return (rows.first{$0["id"] as? Int==22}?["clip"] as? Int) ?? -1}
func marker()->String?{http.state["fixtureRequest"] as? String}
func reconnect(){
    let old=client.inventoryConnection;client.requestInventoryResync();ready()
    check(client.inventoryConnection != old,"Resync did not change nonce")
    // Like the app's next ready tick, publish a fresh absolute foot state.
    // A new server peer intentionally has no inherited spatial authority.
    position();wait("Resynced peer position missing"){
        (snapshot()["peers"] as! [[String:Any]]).contains{($0["position"] as? [String:Any])?["x"] as? Int==1480}
    }
}

check(!client.isReady && client.reserveShot()==nil,"Stopped client could reserve gameplay")
client.connect();wait("Negotiated hello missing"){client.inventoryConnection != nil}
check(!client.isReady && !http.connectionReady,"Hello alone unlocked controls/HTTP")
client.sendChat("EARLY_UNSENT");position()
check(client.reserveShot()==nil && !client.sendMeleeHit(to:"2"),"Handshake allowed combat")
pump(0.08)
check(!events().contains{$0["kind"] as? String=="packet" && $0["t"] as? String=="me"},"Position escaped readiness barrier")
_=control("baseline",["type":"inventory"]);wait("Inventory baseline not received"){!inventories.isEmpty}
check(!client.isReady,"Inventory without world baseline unlocked controls")
_=control("baseline",["type":"all"]);ready()
check(http.connectionReady && client.localName=="Recovery Guest" && ammo()==17,"Authoritative baseline not applied")
check(nonces.count==1 && states.contains(.connecting) && states.last == .ready,"Initial connection state lifecycle missing")
let firstNonce=client.inventoryConnection!
position();wait("Native position not accepted"){(snapshot()["peers"] as! [[String:Any]]).contains{($0["number"] as? Int)==(account["number"] as? Int ?? 1) && ($0["position"] as? [String:Any])?["x"] as? Int==1480}}
_=control("victim")
wait("Real victim WebSocket not ready"){(snapshot()["players"] as! [[String:Any]]).count==2 && (snapshot()["peers"] as! [[String:Any]]).contains{($0["position"] as? [String:Any])?["x"] as? Int==1484}}
let victim=(snapshot()["players"] as! [[String:Any]]).first{$0["id"] as? String != guestID}!,victimNumber=String(victim["number"] as! Int)
let staleTicket=client.reserveShot()!,shot=client.reserveShot()!
_=control("hold-baseline",["type":"inventory"])
check(client.sendWeaponShot(weapon:22,from:feet+SIMD3(0,0,1.35),to:feet+SIMD3(4,0,1.15),player:victimNumber,ticket:shot),"Ready shot was not sent")
wait("Authoritative shot/hit did not settle"){
    let health=(snapshot()["players"] as! [[String:Any]]).first{$0["id"] as? String != guestID}?["health"] as? Int ?? 100
    return player("Recovery Guest")["clip"] as? Int==16 && health<100
}
check(ammo()==17,"Fixture did not withhold the accepted shot's inventory ACK")
let damagedHealth=(snapshot()["players"] as! [[String:Any]]).first{$0["id"] as? String != guestID}!["health"] as! Int
_=control("chat",["sequence":40,"text":"BEFORE_RESTART"]);wait("Old high-sequence chat missing"){chat.contains{$0.contains("BEFORE_RESTART")}}
client.sendChat("STALE_PENDING_CHAT")
_=control("drop");wait("Abrupt disconnect not detected"){!client.isReady}
_=control("baseline",["type":"inventory"])
check(client.inventoryConnection==nil && !http.connectionReady && client.players.isEmpty && client.vehicles.isEmpty,"Peer caches/readiness survived disconnect")
client.sendChat("OFFLINE_UNSENT");position()
check(client.reserveShot()==nil && !client.sendMeleeHit(to:victimNumber),"Offline gameplay not gated")
advance(0.4);check(!client.isReady,"Established disconnect retried before bounded delay")
advance(0.3);ready()
check(client.inventoryConnection != firstNonce && ammo()==16,"Reconnect did not restore fresh authoritative inventory")
check(!client.sendWeaponShot(weapon:22,from:feet,to:feet+SIMD3(4,0,0),player:victimNumber,ticket:staleTicket),"Old shot ticket survived reconnect")
position();pump(0.1)
check(!events().contains{let say=$0["say"] as? String;return say=="STALE_PENDING_CHAT" || say=="OFFLINE_UNSENT" || say=="EARLY_UNSENT"},"Pending/offline chat replayed")

let beforeRestart=client.inventoryConnection!
_=control("offline");wait("Offline server not detected"){!client.isReady}
let attemptsBefore=probe.counts.1
advance(20);pump(0.1)
let failed=probe.counts.1-attemptsBefore
check(failed>=1 && failed<=6,"Offline retry loop was absent or unbounded")
client.setApplicationActive(false);pump(0.15);let asleep=probe.counts
advance(30)
check(probe.counts==asleep,"Inactive app continued opening transports")
_=control("restart");advance(3)
check((snapshot()["peers"] as! [[String:Any]]).isEmpty,"Inactive client rejoined after server restart")
client.setApplicationActive(true);ready()
check(client.inventoryConnection != beforeRestart,"Restart reused old connection nonce")
let resumed=request(server.path("api/auth/me"))
check(resumed["id"] as? String==guestID && client.localName=="Recovery Guest","Server restart changed guest account")
check(ammo()==16 && player("Recovery Guest")["clip"] as? Int==16,"Uncertain shot replayed/rolled back ammunition")
check((snapshot()["players"] as! [[String:Any]]).first{$0["id"] as? String != guestID}?["health"] as? Int==damagedHealth,"Damage replayed after restart")
check(snapshot()["chatSequence"] as? Int==0,"Fixture did not reset server chat sequence")
client.sendChat("AFTER_RESTART");position();wait("Reset chat sequence was suppressed"){chat.contains{$0.contains("AFTER_RESTART")}}
check(snapshot()["chatSequence"] as? Int==1,"Post-restart chat was duplicated")
check(events().filter{$0["kind"] as? String=="packet" && $0["t"] as? String=="shot"}.count==1,"Shot packet replayed")
check(events().filter{$0["kind"] as? String=="packet" && $0["t"] as? String=="hit"}.count==1,"Damage packet replayed")

// Old-connection responses must not overwrite the new peer's HTTP baseline.
// First let an old valid GET actually finish while the main callback queue is
// blocked, then change the epoch. This tests queued success, not only cancel.
rules([["kind":"state","tag":"queued-old-get","hold":true],["kind":"state","tag":"queued-new-get"]])
http.refresh();wait("Queued refresh not held"){held("queued-old-get")}
var completedTask:URLSessionTask?
let taskList=DispatchSemaphore(value:0)
URLSession.shared.getAllTasks{tasks in completedTask=tasks.first{$0.originalRequest?.url==server.path("api/local/state")};taskList.signal()}
precondition(taskList.wait(timeout:.now()+2) == .success && completedTask != nil,"Held URLSession task missing")
let released=DispatchSemaphore(value:0)
var releaseRequest=URLRequest(url:controlURL);releaseRequest.httpMethod="POST"
releaseRequest.httpBody=try! JSONSerialization.data(withJSONObject:["command":"release","args":["tag":"queued-old-get"]])
URLSession.shared.dataTask(with:releaseRequest){_,_,_ in released.signal()}.resume()
precondition(released.wait(timeout:.now()+3) == .success,"Queued response release failed")
let finishedDeadline=Date().addingTimeInterval(2)
while completedTask!.state != .completed && Date()<finishedDeadline{Thread.sleep(forTimeInterval:0.005)}
check(completedTask!.state == .completed,"Old GET did not finish before epoch change")
Thread.sleep(forTimeInterval:0.08)
let queuedStateCount=httpStates.count
http.setConnectionReady(false);http.setConnectionReady(true);http.refresh()
wait("Current GET after queued old callback missing"){marker()=="queued-new-get"}
check(httpStates.count==queuedStateCount+1 && !httpStates.contains{$0["fixtureRequest"] as? String=="queued-old-get"},"Queued old success escaped HTTP epoch")

rules([["kind":"state","tag":"old-refresh","hold":true]])
http.refresh();http.refresh();wait("Old refresh not held"){held("old-refresh")}
check(httpRequests().filter{$0["tag"] as? String=="old-refresh"}.count==1,"Concurrent refresh was not deduplicated")
let oldStateCount=httpStates.count,oldResultCount=results.count
reconnect();rules([["kind":"state","tag":"fresh-baseline"]]);http.refresh()
wait("New HTTP baseline missing"){marker()=="fresh-baseline"}
release("old-refresh");pump(0.12)
check(marker()=="fresh-baseline" && httpStates.count==oldStateCount+1 && results.count==oldResultCount,"Old refresh escaped connection epoch")

var oldCompletion=false,newCompletion:Bool?
rules([["kind":"action","tag":"old-action","hold":true]])
http.perform("weapon.select",payload:["weapon":22]){_ in oldCompletion=true}
wait("Old accepted action not held"){held("old-action")}
reconnect();rules([["kind":"action","tag":"new-action","hold":true]])
http.perform("weapon.select",payload:["weapon":22]){newCompletion=$0}
wait("New action not held"){held("new-action")}
let countBefore=httpRequests().count,statesBefore=httpStates.count,resultsBefore=results.count
release("old-action");pump(0.12)
var busyRejection:Bool?
http.perform("weapon.select",payload:["weapon":0]){busyRejection=$0}
pump(0.1)
check(!oldCompletion && newCompletion==nil && busyRejection==false,"Stale action completed or unlocked new busy action")
check(httpRequests().count==countBefore && httpStates.count==statesBefore && results.count==resultsBefore,"Stale action emitted late state/result/request")
release("new-action");wait("Current action did not complete"){newCompletion != nil}
check(newCompletion==true && marker()=="new-action","Current action baseline lost: result=\(String(describing:newCompletion)), marker=\(String(describing:marker())), status=\(results.last ?? "none")")

// Same connection: starting a mutation invalidates an older GET.
rules([["kind":"state","tag":"pre-action-get","hold":true]])
http.refresh();wait("Pre-action refresh not held"){held("pre-action-get")}
rules([["kind":"action","tag":"after-get-action"]]);var actionDone:Bool?
http.perform("weapon.select",payload:["weapon":22]){actionDone=$0}
wait("Mutation after GET failed"){actionDone != nil}
release("pre-action-get");pump(0.12)
check(actionDone==true && marker()=="after-get-action","Earlier same-connection GET rolled back mutation")

// Reentrant onState can start a new action; the old completion cannot unlock it.
rules([["kind":"action","tag":"reentrant-first"],["kind":"action","tag":"reentrant-second","hold":true]])
var firstDone:Bool?,secondDone:Bool?
let samePeerResults=results.count
http.onState={state in
    httpStates.append(state)
    if state["fixtureRequest"] as? String=="reentrant-first" {
        http.perform("weapon.select",payload:["weapon":22]){secondDone=$0}
    }
}
http.perform("weapon.select",payload:["weapon":22]){firstDone=$0}
wait("Reentrant next action not started"){held("reentrant-second")}
let reentrantCount=httpRequests().count;var third:Bool?
http.perform("weapon.select",payload:["weapon":0]){third=$0};pump(0.1)
check(firstDone==true && secondDone==nil && third==false && httpRequests().count==reentrantCount,"Old completion released reentrant busy owner")
check(results.count==samePeerResults,"Superseded same-peer action emitted stale status")
release("reentrant-second");wait("Reentrant current action did not complete"){secondDone != nil}
check(secondDone==true && marker()=="reentrant-second","Reentrant state/completion wrong")

// A peer boundary inside onState suppresses the old accepted completion even
// when readiness returns immediately with the same nonce.
rules([["kind":"action","tag":"boundary-first"],["kind":"action","tag":"boundary-second","hold":true]])
var boundaryOld=false,boundaryNew:Bool?
let boundaryResults=results.count
http.onState={state in
    httpStates.append(state)
    if state["fixtureRequest"] as? String=="boundary-first" {
        http.setConnectionReady(false);http.setConnectionReady(true)
        http.perform("weapon.select",payload:["weapon":22]){boundaryNew=$0}
    }
}
http.perform("weapon.select",payload:["weapon":22]){_ in boundaryOld=true}
wait("Replacement peer action not started"){held("boundary-second")}
check(!boundaryOld && boundaryNew==nil && results.count==boundaryResults,"Offline→online boundary allowed stale completion/result")
release("boundary-second");wait("Replacement peer action incomplete"){boundaryNew != nil}
check(boundaryNew==true,"Current peer action lost completion")

rules([["kind":"action","tag":"nonce-boundary"]])
var nonceOld=false
let previousNonce=client.inventoryConnection,nonceResults=results.count
http.onState={state in
    httpStates.append(state)
    if state["fixtureRequest"] as? String=="nonce-boundary" {client.requestInventoryResync()}
}
http.perform("weapon.select",payload:["weapon":22]){_ in nonceOld=true}
wait("onState did not replace peer"){client.inventoryConnection != previousNonce && client.isReady}
check(!nonceOld && results.count==nonceResults,"Changed nonce allowed stale completion/result")

http.setConnectionReady(false);let offlineCount=httpRequests().count;var blocked:Bool?
http.refresh();http.perform("weapon.select",payload:["weapon":22]){blocked=$0};pump(0.1)
check(blocked==false && httpRequests().count==offlineCount && http.state.isEmpty,"Offline HTTP was not fail-closed")
client.disconnect();pump(0.2)
check(client.state == .stopped && !client.isReady && client.inventoryConnection==nil,"Explicit stop retained readiness")
let stoppedPackets=events().count,stoppedOpens=probe.counts.0
advance(30);pump(0.1)
check(events().count==stoppedPackets && probe.counts.0==stoppedOpens,"Stopped client retried/replayed")
check(!client.sendMeleeHit(to:victimNumber) && client.reserveShot()==nil,"Stopped combat remained enabled")
session.invalidateAndCancel()
let metrics:[String:Any]=["checks":checks,"offlineFailures":failed,"freshNonces":Set(nonces).count,
    "ammoAfterRecovery":ammo(),"victimHealthAfterRecovery":damagedHealth,
    "shotPackets":events().filter{$0["kind"] as? String=="packet" && $0["t"] as? String=="shot"}.count,
    "hitPackets":events().filter{$0["kind"] as? String=="packet" && $0["t"] as? String=="hit"}.count,
    "savedPlayers":(snapshot()["players"] as! [[String:Any]]).count]
print("RECOVERY_METRICS "+String(data:try! JSONSerialization.data(withJSONObject:metrics,options:.sortedKeys),encoding:.utf8)!)
print("PASS native recovery: \(checks) real HTTP/WebSocket restart, baseline, retry, replay and generation checks")
