var checks=0
func check(_ value:Bool,_ message:String){precondition(value,message);checks += 1}
let ray=NativeShotTargeting.Ray(origin:.zero,direction:SIMD3(0,1,0),range:10)!
let candidates:[NativeShotTargeting.Candidate]=[
 .init(id:"edge",point:SIMD3(0.8,2,0)),.init(id:"outside",point:SIMD3(0.8001,2,0)),
 .init(id:"edge",point:SIMD3(0,2,0)),.init(id:"near",point:SIMD3(0,0,0)),
 .init(id:"far",point:SIMD3(0,10,0)),.init(id:"behind",point:SIMD3(0,-0.0001,0)),
 .init(id:"past",point:SIMD3(0,10.0001,0)),.init(id:"blocked",point:SIMD3(0,4,0)),
 .init(id:"nan",point:SIMD3(.nan,1,0)),.init(id:"",point:SIMD3(0,1,0))]
check(NativeStreamShotTargets.players(ray:ray,candidates:candidates,visible:{$1.y != 4}) == ["edge","near","far"],"Exact cylinder boundaries, stable duplicates and LOS")
check(NativeShotTargeting.select(ray:ray,aiming:true,candidates:[candidates[0]],visible:{_,_ in true})==nil,"Stream side target must exercise old cone rejection")
let many=(0..<300).map{NativeShotTargeting.Candidate(id:"p\($0)",point:SIMD3(0,1,0))}
check(NativeStreamShotTargets.players(ray:ray,candidates:many,visible:{_,_ in true}).count==128,"Bound cylinder output")
let cadence=NativeStreamShotClaims()
check(cadence.take(weapon:37,connection:"a",players:["one","two","one"],milliseconds:0)==["one","two"],"All victims in one paid event")
for time in [0.0,20,100,299,299.999] {check(cadence.take(weapon:42,connection:"a",players:["one","two"],milliseconds:time).isEmpty,"Shared per-victim 300ms cadence")}
check(cadence.take(weapon:41,connection:"a",players:["one","new"],milliseconds:300)==["one","new"],"Victims have independent clocks")
check(cadence.take(weapon:42,connection:"a",players:["two"],milliseconds:300)==["two"],"Cross-weapon cadence")
for time in [-1.0,Double.nan,Double.infinity,Double(Int64.max)] {check(cadence.take(weapon:37,connection:"a",players:["one"],milliseconds:time).isEmpty,"Invalid time")}
check(cadence.take(weapon:37,connection:"a",players:["one"],milliseconds:1).isEmpty,"Backward clock cannot burst")
check(cadence.take(weapon:22,connection:"a",players:["one"],milliseconds:600).isEmpty,"Instant weapon cannot claim stream")
check(cadence.take(weapon:37,connection:"b",players:["one"],milliseconds:0)==["one"],"New nonce resets victim times")
cadence.reset();check(cadence.take(weapon:37,connection:"b",players:["one"],milliseconds:0)==["one"],"Disconnect reset")
let bounded=NativeStreamShotClaims()
for start in stride(from:0,to:640,by:128){_ = bounded.take(weapon:37,connection:"a",players:(start..<start+128).map{"p\($0)"},milliseconds:0)}
check(bounded.retainedCount==512,"Bound retained victim history")
check(bounded.take(weapon:37,connection:"a",players:["new"],milliseconds:1).isEmpty,"Full history cannot evict into cadence bypass")
check(bounded.take(weapon:37,connection:"a",players:["new"],milliseconds:2001)==["new"] && bounded.retainedCount==1,"Old victims expire")
check(NativeStreamShotClaims.normalized(["","a","a",String(repeating:"é",count:33),"b"])==["a","b"],"Bound UTF8 identity and duplicates")

// Extract the production async method verbatim. Only the transport's callback
// delivery is controlled here, so failure/socket lifetime races are repeatable.
final class DeferredSocket {
 var messages:[URLSessionWebSocketTask.Message]=[]
 var completions:[(Error?)->Void]=[]
 func send(_ message:URLSessionWebSocketTask.Message,completionHandler:@escaping(Error?)->Void){messages.append(message);completions.append(completionHandler)}
}
final class CallbackHarness {
 var socket:DeferredSocket?=DeferredSocket(),health=100,passive=false,shots=0,resyncs=0
 let shotSequence=NativeShotSequence(),streamShotClaims=NativeStreamShotClaims()
 var inventoryConnection:String? {shotSequence.connection}
 var claims:[[String:Any]]=[]
 init(){precondition(shotSequence.negotiate("callback-a"))}
 func send(_ packet:[String:Any]){claims.append(packet)}
 func requestInventoryResync(){resyncs += 1}
 // ACTUAL_SEND_WEAPON_SHOT
}
func drain(){RunLoop.main.run(until:Date().addingTimeInterval(0.02))}
for scenario in 0..<4 {
 let harness=CallbackHarness(),socket=harness.socket!,ticket=harness.shotSequence.reserve()!
 check(harness.sendWeaponShot(weapon:41,from:.zero,to:SIMD3(0,5,0),player:nil,ticket:ticket,streamPlayers:["A","B"]),"Queue actual stream callback")
 check(socket.messages.count==1 && harness.claims.isEmpty,"No claim before same-shot success")
 if scenario==1{harness.socket=DeferredSocket()}
 if scenario==2{harness.shotSequence.reset();check(harness.shotSequence.negotiate("callback-b"),"Replace nonce")}
 socket.completions[0](scenario==3 ? NSError(domain:"fixture",code:1):nil);drain()
 if scenario==0 {
  check(harness.claims.count==2,"Actual success callback claims every victim")
  for claim in harness.claims{check(claim["s"] as? Int==ticket.sequence && claim["c"] as? String==ticket.connection,"Claims preserve exact ticket")}
 }else{check(harness.claims.isEmpty,"Failure/replaced socket/nonce cannot claim")}
 check(harness.resyncs==(scenario==3 ? 1:0),"Only current failed socket requests resync")
}

// Real URLSession client plus fresh ephemeral peer. Claims must follow the
// successful same-shot write, carry its nonce/sequence, and reset on reconnect.
let client=NativeMultiplayerClient(server:ServerAddress(CommandLine.arguments[1])!)
var nonceCount=0,finished=false,oldTicket:NativeShotTicket?
func fire(_ weapon:Int,targets:[String],instant:String?=nil)->NativeShotTicket {
 let ticket=client.reserveShot()!
 check(client.sendWeaponShot(weapon:weapon,from:.zero,to:SIMD3(0,10,0),player:instant,ticket:ticket,streamPlayers:targets),"Actual same-shot send")
 check(!client.sendWeaponShot(weapon:weapon,from:.zero,to:SIMD3(0,10,0),player:instant,ticket:ticket,streamPlayers:targets),"Duplicate ticket cannot add claims")
 return ticket
}
client.onInventoryConnection={nonce in
 guard nonce != nil else{return};nonceCount += 1
 if nonceCount==1 {
  oldTicket=fire(37,targets:["A","B","A","",String(repeating:"x",count:65)])
  _ = fire(22,targets:["ignored"],instant:"C")
  DispatchQueue.main.asyncAfter(deadline:.now()+0.1){_ = fire(42,targets:["A","B"])}
  DispatchQueue.main.asyncAfter(deadline:.now()+0.4){_ = fire(41,targets:["A","B"])}
 } else {
  check(nonceCount==2,"Only requested reconnect")
  check(!client.sendWeaponShot(weapon:37,from:.zero,to:SIMD3(0,10,0),player:nil,ticket:oldTicket!,streamPlayers:["A"]),"Old nonce cannot claim")
  let ticket=fire(42,targets:["A","B"]);check(ticket.sequence==1,"Fresh nonce sequence")
 }
}
client.onStatus={text in
 if text=="STREAM ROUND ONE" {client.requestInventoryResync()}
 if text=="STREAM COMPLETE" {finished=true;client.disconnect()}
}
check(client.reserveShot()==nil,"Unnegotiated stream cannot fire")
client.connect();let deadline=Date().addingTimeInterval(10)
while !finished && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.01))}
check(finished && nonceCount==2,"Actual stream wire complete")
print("PASS native stream claims:",checks,"geometry/cadence/wire checks, actual multi-victim same-ticket and reconnect")
