// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
final class BootstrapClock {var now=0.0}
final class BootstrapNetwork {
    let clock:BootstrapClock
    var recovery=NativeConnectionRecovery()
    var usesClientOwnedWeapons=false
    private(set) var resyncs=0
    var state:NativeConnectionRecovery.State {recovery.state}
    init(_ clock:BootstrapClock){self.clock=clock;_=recovery.start(now:clock.now)}
    func requestInventoryResync(){resyncs+=1;_=recovery.restart(now:clock.now)}
    func received(_ baseline:NativeConnectionRecovery.Baseline){_=recovery.received(baseline,generation:recovery.generation,now:clock.now)}
    func heartbeat(){recovery.received(generation:recovery.generation,now:clock.now);_=recovery.tick(now:clock.now)}
}
final class BootstrapGame {
    let network:BootstrapNetwork,weapons:NativeWeaponState
    init(_ clock:BootstrapClock){
        network=BootstrapNetwork(clock)
        weapons=NativeWeaponState(catalog:[.init(id:22,name:"Authored inventory",model:"",range:35,capacity:17,interval:0.1,animation:"fixture",fireKind:"INSTANT_HIT")],clock:{clock.now})
        // ACTUAL_INVENTORY_RESYNC_CALLBACK
    }
}
@main enum Main {
    static func main(){
        var checks=0
        func check(_ value:Bool,_ why:String){checks+=1;if !value{print("FAIL \(why)");exit(1)}}
        let clock=BootstrapClock(),game=BootstrapGame(clock),nonce="bootstrap-ack-session-000000"
        game.weapons.setConnection(nonce);game.network.received(.hello);game.network.received(.world)
        for tick in 1...13 {clock.now=Double(tick)*0.25;game.network.heartbeat();game.weapons.tick()}
        check(game.network.resyncs==0,"A healthy connecting transport was restarted by the shorter inventory baseline timer: \(game.network.resyncs)")
        check(game.network.state == .connecting && !game.weapons.canFire,"Delayed baseline cannot enable firing")
        let snapshot:[String:Any]=["revision":0,"selected":22,"weapons":[["id":22,"clip":17,"rest":0]],"ack":["connection":nonce,"processedShot":0]]
        check(game.weapons.apply(snapshot),"Actual delayed inventory baseline was rejected")
        game.network.received(.inventory);game.weapons.tick()
        check(game.network.state == .ready && game.weapons.canFire,"Valid baseline must complete without reconnecting")
        let sequence=NativeShotSequence();check(sequence.negotiate(nonce),"Authoritative test sequence")
        let ticket=sequence.reserve()!;check(game.weapons.consumeAnimationShot(weapon:22,ticket:ticket),"Actual predicted round")
        check(game.weapons.rounds==16 && game.weapons.pendingShotCount==1,"One unsettled round remains separately predicted")
        for tick in 1...9 {clock.now=3.25+Double(tick)*0.25;game.network.heartbeat();game.weapons.tick()}
        check(game.network.resyncs==1,"An uncertain accepted-session write must still request one reconnect")
        check(!game.weapons.canFire,"Unsettled write cannot enable further firing")
        for _ in 0..<5{game.weapons.tick()}
        check(game.network.resyncs==1,"Repeated frame ticks cannot repeat a notified reconnect")
        let timeoutClock=BootstrapClock(),timeout=BootstrapGame(timeoutClock)
        timeout.weapons.setConnection(nonce);timeout.network.received(.hello);timeout.network.received(.world)
        var timedOut=false
        for tick in 1...41 {
            timeoutClock.now=Double(tick)*0.25
            timeout.network.recovery.received(generation:timeout.network.recovery.generation,now:timeoutClock.now)
            if case .timeout=timeout.network.recovery.tick(now:timeoutClock.now){timedOut=true}
            timeout.weapons.tick()
        }
        check(timedOut && timeout.network.resyncs==0,"Transport retains its bounded incomplete-baseline deadline")
        let owned=BootstrapGame(BootstrapClock());owned.network.usesClientOwnedWeapons=true
        owned.weapons.onNeedsResync?()
        check(owned.network.resyncs==1,"Client-owned queue recovery remains available before its baseline")
        print("PASS \(checks) actual recovery/inventory/controller policy checks; injected monotonic clocks and socket boundary, no real transport or App acceptance")
    }
}
