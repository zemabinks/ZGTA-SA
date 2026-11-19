import Foundation

@main enum NativeAmmoReconciliationSmoke {
 static func main() {
  var time=100.0,checks=0,refresh=0,resync=0
  func check(_ value: @autoclosure()->Bool,_ label:String) {checks += 1;precondition(value(),label)}
  let gun=NativeWeaponState.Weapon(id:22,name:"Pistol",model:"",range:40,capacity:17,interval:0.3,animation:"colt45",fireKind:"INSTANT_HIT")
  let smg=NativeWeaponState.Weapon(id:28,name:"SMG",model:"",range:40,capacity:500,interval:0.02,animation:"uzi",fireKind:"INSTANT_HIT")
  let state=NativeWeaponState(catalog:[gun,smg],clock:{time}),sequence=NativeShotSequence()
  state.onNeedsRefresh={refresh += 1};state.onNeedsResync={resync += 1}
  func snapshot(_ revision:Int,_ ack:Int,_ clips:[Int:Int],selected:Int=22,connection:String="A",reload:Double?=nil)->[String:Any] {
   var result:[String:Any] = ["revision":revision,"selected":selected,
    "weapons":[["id":0,"clip":0,"rest":0]]+clips.sorted{$0.key<$1.key}.map{["id":$0.key,"clip":$0.value,"rest":100]},
    "ack":["connection":connection,"processedShot":ack]]
   if let reload {result["reload"]=["weapon":selected,"remainingMs":reload]}
   return result
  }
  func connect(_ nonce:String) {sequence.reset();check(sequence.negotiate(nonce),"negotiate");state.setConnection(nonce)}
  func shoot(_ weapon:Int,_ left:Bool=false)->NativeShotTicket? {
   guard let ticket=sequence.reserve() else{return nil}
   var ready=true,delivered=false
   let accepted=NativeWeaponShotDelivery.deliver(weapon:weapon,left:left,ticket:ticket,inventory:state,
    readiness:{ready=$0},emission:{w,l,t in
     check(w==weapon && l==left && t==ticket,"same event/ticket delivered")
     check(ready==state.canFire,"readiness visible before emission")
     delivered=sequence.claim(t)
    })
   return accepted && delivered ? ticket:nil
  }
  check(!state.fire(),"unnegotiated native default must not predict")
  var legacy=snapshot(0,0,[22:17]);legacy.removeValue(forKey:"ack")
  check(!state.apply(legacy) && !state.canFire,"unacknowledged HTTP cannot enable unsafe optimism")
  connect("A");state.tick();check(resync==0 && !state.canFire,"initial snapshot has synchronization grace")
  check(state.apply(snapshot(0,0,[22:17,28:50])),"initial acknowledged inventory")
  let first=shoot(22)!,second=shoot(22,true)!
  check(first.sequence==1 && second.sequence==2 && state.rounds==15,"two pending predictions")
  check(state.apply(snapshot(0,0,[22:17,28:50])) && state.rounds==15,"same revision duplicate cannot restore pending rounds")
  check(state.apply(snapshot(1,1,[22:16,28:50])) && state.rounds==15 && state.pendingShotCount==1,"first ACK cannot undo second shot")
  check(state.apply(snapshot(1,2,[22:16,28:50])) && state.rounds==16 && state.pendingShotCount==0,"rejected second shot restores only rejected round")
  check(!state.apply(snapshot(1,1,[22:16,28:50])) && !state.apply(snapshot(0,2,[22:17,28:50])),"independent revision and watermark monotonicity")
  sequence.observeAcknowledgement(2)
  check(shoot(22) != nil,"pending old selected weapon")
  check(state.apply(snapshot(2,2,[22:16,28:50],selected:28)),"selection response")
  check(state.rounds==50 && state.pendingShotCount==1,"selection keeps pending old weapon without debiting new weapon")
  let fourth=shoot(28)!
  check(fourth.sequence==4 && state.rounds==49,"new weapon independent prediction")
  check(state.apply(snapshot(2,3,[22:16,28:50],selected:28)) && state.rounds==49,"old weapon rejection preserves later new weapon prediction")
  check(state.apply(snapshot(3,4,[22:16,28:49],selected:28)),"new weapon accepted")
  let reload=state.beginReloadRequest()
  check(!state.canFire && !state.consumeAnimationShot(weapon:28,ticket:sequence.reserve()),"reload request blocks before HTTP response")
  check(state.apply(snapshot(3,4,[22:16,28:49],selected:28)) && state.reloading,"old pre-request HTTP response cannot cancel local reload request")
  check(state.apply(snapshot(4,4,[22:16,28:49],selected:28,reload:1000)),"authoritative reload start")
  state.finishReloadRequest(id:reload,succeeded:true)
  time += 1.1;state.tick();state.tick()
  check(state.reloading && !state.canFire && refresh==1,"countdown requests refresh once but cannot invent reload completion")
  check(state.apply(snapshot(4,4,[22:16,28:49],selected:28,reload:0)) && state.reloading,"zero remaining with server reload object stays unready")
  check(state.apply(snapshot(5,4,[22:16,28:50],selected:28)) && state.canFire,"only authoritative completion reopens firing")
  let unknown=state.beginReloadRequest();state.finishReloadRequest(id:unknown,succeeded:nil)
  check(!state.canFire && resync==1,"unknown reload transport outcome freezes and requests resync")
  state.tick();check(resync==1,"one resync request per uncertainty")
  connect("B");check(!state.canFire && state.rounds==0,"reconnect has no optimistic ammo before new truth")
  check(!state.apply(snapshot(99,99,[28:1],selected:28,connection:"A")),"old socket/HTTP cannot cross new nonce")
  check(state.apply(snapshot(0,0,[28:50],selected:28,connection:"B")),"new connection permits reset server revision")
  check(shoot(28)?.sequence==1,"new sequence starts independently")
  state.setConnection("B");check(state.pendingShotCount==1 && state.rounds==49,"duplicate hello is idempotent")
  time += 2.01;state.tick();check(!state.canFire && state.rounds==49 && resync==2,"missing ACK freezes without restoring ammo")
  state.tick();check(resync==2,"timeout requests only one resync")
  connect("C");check(state.apply(snapshot(0,0,[28:49],selected:28,connection:"C")),"fresh authoritative baseline after uncertain old shot")
  state.markTransportUncertain();check(!state.canFire && resync==3,"unknown socket write freezes")
  connect("D");check(state.apply(snapshot(0,0,[28:49],selected:28,connection:"D")),"new connection settles write outcome")
  var invalid=snapshot(1,0,[28:49],selected:28,connection:"D")
  invalid["ack"]=["connection":"D","processedShot":true]
  check(!state.apply(invalid),"boolean acknowledgement is invalid")
  invalid=snapshot(1,0,[28:49],selected:28,connection:"D");invalid["weapons"]=[["id":28,"clip":49,"rest":1],["id":28,"clip":49,"rest":1]]
  check(!state.apply(invalid),"duplicate weapon IDs do not crash or replace truth")
  invalid=snapshot(1,0,[28:49],selected:28,connection:"D");invalid["revision"]=Double.infinity
  check(!state.apply(invalid),"nonfinite revision rejected")
  state.setConnection(nil);check(!state.canFire && state.pendingShotCount==0,"disconnect blocks firing and abandons old predictions")
  check(!state.apply(snapshot(100,90,[28:10],selected:28,connection:"D")),"snapshot cannot negotiate itself after disconnect")

  // Exercise the real WeaponState+ShotDelivery API with an independent server
  // baseline oracle. Delivery jitter reorders HTTP duplicates and WS ACKs.
  var frames=0
  for delay in [0.1,0.2,0.35,0.5] {
   time=0;let state=NativeWeaponState(catalog:[smg],clock:{time}),seq=NativeShotSequence()
   _=seq.negotiate("jitter");state.setConnection("jitter")
   _=state.apply(snapshot(0,0,[28:200],selected:28,connection:"jitter"))
   var serverClip=200,serverRevision=0,oracleClip=200,oracleRevision=0,oracleACK=0,predicted:[Int]=[]
   var queue:[(at:Double,state:[String:Any],rev:Int,ack:Int,clip:Int)] = []
   for tick in 0..<400 {
    time=Double(tick)*0.01
    if tick%12==0 && tick<240 {
     let ticket=seq.reserve()!
     check(state.consumeAnimationShot(weapon:28,ticket:ticket),"jitter predicted emission")
     check(seq.claim(ticket),"ticket queued exactly once");predicted.append(ticket.sequence)
     if ticket.sequence%7 != 0 {serverClip-=1;serverRevision+=1}
     let value=snapshot(serverRevision,ticket.sequence,[28:serverClip],selected:28,connection:"jitter")
     let jitter=ticket.sequence%3==0 ? -0.09:ticket.sequence%3==1 ? 0.08:0
     queue.append((time+max(0.01,delay+jitter),value,serverRevision,ticket.sequence,serverClip))
     queue.append((time+delay+0.13,value,serverRevision,ticket.sequence,serverClip))
    }
    let delivered=queue.filter{$0.at<=time}.sorted{$0.at<$1.at};queue.removeAll{$0.at<=time}
    for event in delivered {
     if event.rev>=oracleRevision && event.ack>=oracleACK {oracleRevision=event.rev;oracleACK=event.ack;oracleClip=event.clip}
     _=state.apply(event.state)
    }
    check(state.rounds==oracleClip-predicted.filter{$0>oracleACK}.count,"jitter HTTP/WS reconciliation keeps exactly unacknowledged rounds")
    frames += 1
   }
   check(state.pendingShotCount==0 && state.rounds==serverClip,"all acknowledged predictions settle")
  }
  print("PASS: real NativeWeaponState/ShotDelivery \(checks) checks, \(frames) frames100–500ms jitter; duplicate/firstACK, rejects, HTTP/WS, reload intent/completion, switch, timeout, write uncertainty and reconnect")
 }
}
