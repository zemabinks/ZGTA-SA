import Foundation

@main enum AmmoReconciliationSmoke {
 static func main() {
  var now=100.0,checks=0
  let state=NativeInventoryPrediction(clock:{now})
  func snapshot(_ revision:Int,_ ack:Int,_ clip:Int,_ selected:Int=22,_ reload:Bool=false,_ connection:String="A")->NativeInventoryPrediction.Snapshot {
   .init(connection:connection,processedShot:ack,revision:revision,selected:selected,reloading:reload,
     weapons:[22:.init(clip:selected==22 ? clip:17,reserve:50),28:.init(clip:selected==28 ? clip:50,reserve:100)])
  }
  func check(_ value:Bool,_ message:String){precondition(value,message);checks+=1}
  state.connected("A");check(!state.predict(weapon:22,sequence:1),"Unsynchronized connection predicted ammo")
  check(state.apply(snapshot(0,0,17)) == .applied,"Initial snapshot")
  check(state.predict(weapon:22,sequence:1),"First shot");now+=0.12
  check(state.predict(weapon:22,sequence:2),"Second in-flight shot")
  check(state.rounds(22)?.clip==15,"Two predicted rounds")
  check(state.apply(snapshot(0,0,17)) == .applied,"Duplicate pre-shot snapshot")
  check(state.rounds(22)?.clip==15,"Same revision undid prediction")
  check(state.apply(snapshot(1,1,16)) == .applied,"First accepted ACK")
  check(state.rounds(22)?.clip==15 && state.pending.map(\.sequence)==[2],"First ACK undid later prediction")
  check(state.apply(snapshot(1,2,16)) == .applied,"Rejected shot watermark")
  check(state.rounds(22)?.clip==16 && state.pending.isEmpty,"Rejected shot did not restore ammo")
  check(state.apply(snapshot(1,1,16)) == .staleAcknowledgement,"Stale ACK accepted")
  check(state.apply(snapshot(0,0,17)) == .staleRevision,"Old refresh accepted")
  check(!state.predict(weapon:22,sequence:2),"Acknowledged sequence replayed")
  check(state.predict(weapon:22,sequence:3),"Before weapon switch")
  check(state.apply(snapshot(2,2,50,28)) == .applied,"Selection action snapshot")
  check(state.rounds(28)?.clip==50 && state.rounds(22)?.clip==16,"Selection lost pending old-weapon evidence")
  check(!state.predict(weapon:22,sequence:4),"Old selected weapon still fired")
  check(state.apply(snapshot(2,3,50,28)) == .applied,"Server rejected old-weapon shot")
  check(state.predict(weapon:28,sequence:4),"New weapon prediction")
  check(state.apply(snapshot(3,3,50,28,true)) == .applied,"Reload start snapshot")
  check(state.rounds(28)?.clip==49 && !state.predict(weapon:28,sequence:5),"Reload bypassed or erased in-flight shot")
  check(state.apply(snapshot(3,4,50,28,true)) == .applied,"Rejected reload shot")
  check(state.rounds(28)?.clip==50,"Reload reject did not restore clip")
  check(state.apply(snapshot(4,4,50,28,false)) == .applied,"Reload complete")
  check(state.predict(weapon:28,sequence:5),"After reload")
  now+=2.1;check(state.needsResync && !state.predict(weapon:28,sequence:6),"Missing ACK did not freeze prediction")
  check(state.rounds(28)?.clip==49,"Timeout invented ammunition")
  check(state.apply(snapshot(5,5,49,28)) == .applied && !state.needsResync,"Resync ACK did not recover")
  state.connected("B");check(state.pending.isEmpty && !state.synchronized,"Reconnect inherited pending shots")
  check(state.apply(snapshot(6,5,48,28,false,"A")) == .wrongConnection,"Old socket snapshot crossed reconnect")
  check(state.apply(snapshot(0,0,17,22,false,"B")) == .applied,"Fresh server revision rejected on reconnect")
  check(state.predict(weapon:22,sequence:1),"Fresh socket counter could not restart")
  var invalid=snapshot(0,0,17,22,false,"B");invalid.weapons[22] = .init(clip:Int.max,reserve:Int.max)
  check(state.apply(invalid) == .invalid,"Invalid rounds caused overflow or entered truth")
  state.disconnected();check(state.rounds(22)==nil && !state.predict(weapon:22,sequence:2),"Disconnected state restored playable ammo")
  do {
   let bounded=NativeInventoryPrediction(capacity:4,clock:{now});bounded.connected("bounded")
   var initial=NativeInventoryPrediction.Snapshot(connection:"bounded",processedShot:0,revision:0,selected:22,reloading:false,weapons:[22:.init(clip:10,reserve:0)])
   _=bounded.apply(initial)
   for sequence in 1...4{check(bounded.predict(weapon:22,sequence:sequence),"Valid pending capacity rejected")}
   check(!bounded.predict(weapon:22,sequence:5) && bounded.needsResync,"Pending overflow did not freeze safely")
   initial.revision=2;initial.processedShot=2;initial.weapons[22]?.clip=8
   check(bounded.apply(initial) == .applied && !bounded.needsResync && bounded.rounds(22)?.clip==6,"Bounded resync changed pending round count")
  }
  // Differential schedule: server processes in sequence; ACK delivery jitter
  // deliberately reorders snapshots and HTTP duplicates. Predicted clip must
  // equal newest accepted server baseline minus exactly its unacknowledged set.
  var frames=0
  for delay in [0.1,0.2,0.35,0.5] {
   now=0
   let candidate=NativeInventoryPrediction(clock:{now});candidate.connected("jitter")
   var initial=NativeInventoryPrediction.Snapshot(connection:"jitter",processedShot:0,revision:0,selected:28,reloading:false,weapons:[28:.init(clip:200,reserve:0)])
   _=candidate.apply(initial)
   var queue:[(at:Double,snapshot:NativeInventoryPrediction.Snapshot)] = [],predicted:[Int]=[],oracleACK=0,oracleRevision=0,oracleClip=200
   var serverClip=200,serverRevision=0,nextSequence=0
   for tick in 0..<400 {
    now=Double(tick)*0.01
    if tick%12==0 && tick<240 {
     nextSequence+=1
     check(candidate.predict(weapon:28,sequence:nextSequence),"Jitter prediction rejected")
     predicted.append(nextSequence)
     let accepted=nextSequence%7 != 0
     if accepted{serverClip-=1;serverRevision+=1}
     initial.revision=serverRevision;initial.processedShot=nextSequence;initial.weapons[28]?.clip=serverClip
     let jitter=nextSequence%3==0 ? -0.09:nextSequence%3==1 ? 0.08:0
     queue.append((now+max(0.01,delay+jitter),initial))
     queue.append((now+delay+0.13,initial))
    }
    let deliveries=queue.filter{$0.at<=now}.sorted{$0.at<$1.at};queue.removeAll{$0.at<=now}
    for event in deliveries {
     if event.snapshot.revision>=oracleRevision && event.snapshot.processedShot>=oracleACK {
      oracleRevision=event.snapshot.revision;oracleACK=event.snapshot.processedShot;oracleClip=event.snapshot.weapons[28]!.clip
     }
     _=candidate.apply(event.snapshot)
    }
    let expected=oracleClip-predicted.filter{$0>oracleACK}.count
    check(candidate.rounds(28)?.clip==expected,"Jitter reconciliation double-counted or restored an unacked shot")
    frames+=1
   }
   check(candidate.pending.isEmpty && candidate.rounds(28)?.clip==serverClip,"Settled ACK did not match authoritative ammo")
  }
  print("PASS native prediction engine: \(checks) checks, \(frames) frames with 100–500 ms jitter; duplicate/stale/first-ACK preservation, rejects, selection/reload, timeout/resync, bounds and reconnect. Deterministic engine gate; transport integration has separate tests.")
 }
}
