import Foundation
import simd

@main enum SwimReloadAudioSmoke {
 static func main()throws {
    let root=URL(fileURLWithPath:CommandLine.arguments[1])
    let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/models/animations.clips.bin")))!
    let profiles=try NativeFootWeaponAnimation.load(data:Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/foot-animation.json")))
    var checks=0,historicalExecuted=false
    func check(_ value:Bool,_ message:String){precondition(value,message);checks+=1}
    func fresh(_ mode:String="water",weapon:Int=22)->(FixedVelocityHarness,WaterReloadOwner) {
        DispatchQueue.main.clear();Sink.played=[];Sink.stopped=[]
        let h=FixedVelocityHarness(library:library,mode:mode)
        h.equippedWeapon=weapon;h.footWeaponDefinitions=profiles;h.footAnimator!.arm(profiles[weapon])
        h.waterEdge=1479
        let owner=WaterReloadOwner(h);owner.audio.reloads["23"]=[11,12]
        return(h,owner)
    }
    func begin(_ h:FixedVelocityHarness,_ owner:WaterReloadOwner) {
        check(h.footAnimator!.beginReload()>0 && h.footAnimator!.reloading,"Real reload CLP must be active")
        owner.audio.reload(weapon:h.equippedWeapon)
    }
    func sameMotion(_ a:NativeCharacterController.Motion,_ b:NativeCharacterController.Motion)->Bool {
        a.displacement==b.displacement && a.jump==b.jump && a.held==b.held && a.verticalOverride==b.verticalOverride && a.heldFeet==b.heldFeet
    }
    // Each case uses actual swimmingMotion and actual controller result. Only
    // the existing fixture water-plane/query and audio output are controlled.
    for load in ["cached","pending-both","pending-first"] {
        let(h,owner)=fresh();owner.audio.deferFetch=load != "cached";begin(h,owner)
        if load=="pending-both" {DispatchQueue.main.drain();check(owner.audio.pending.count==2,"Both sample completions must be pending")}
        var callbacks=0;let bound=h.onReloadTaskCancelled!
        h.onReloadTaskCancelled={
            check(h.swimController.on && !h.footAnimator!.reloading,"Notification preceded actual swim/arm ownership transfer")
            callbacks+=1;bound()
        }
        let output=h.waterForReload()
        check(h.swimController.on && !h.footAnimator!.reloading && callbacks==1,"Owned swim tick did not end reload and notify once")
        check(h.footAnimationFrame?.shots.isEmpty==true,"Swim handoff emitted a delayed combat marker")
        check(h.equippedWeapon==22,"Swim cancellation changed inventory-selected weapon")
        let control=FixedVelocityHarness(library:library,mode:"water");control.waterEdge=1479
        check(sameMotion(output,control.waterForReload()),"Audio cancellation changed actual swim movement")
        _=h.waterForReload();check(callbacks==1,"Already-unarmed next swim tick repeated cancellation")
        DispatchQueue.main.drain();owner.audio.releaseSamples()
        check(Sink.played==(load=="cached" ? ["143_11"]:[]),"Swim retained an old delayed phase or sample completion")
        check(Sink.stopped.isEmpty,"Swim cancellation stopped an already committed voice")
    }
    let threshold=NativeSwimController()
    check(!threshold.enters(1.6) && threshold.enters(1.600001),"Exact strict swim depth threshold changed")
    for reason in ["shallow","no-water","no-owned-result","zero-delta","no-animation","no-active-reload","input-only"] {
        let(h,owner)=fresh()
        if reason != "no-active-reload" {begin(h,owner)}else{owner.audio.reload(weapon:22)}
        var callbacks=0;let bound=h.onReloadTaskCancelled!
        h.onReloadTaskCancelled={callbacks+=1;bound()}
        if reason=="shallow" {h.character!.reset(feet:SIMD3(1480,0,100.5),active:true,grounded:false)}
        if reason=="no-water" || reason=="input-only" {h.water=false}
        if reason=="no-owned-result" {
            h.swimController.enter(velocity:.zero,rising:0,depth:2);h.water=false
        }
        if reason=="zero-delta" {h.swimController.enter(velocity:.zero,rising:0,depth:2)}
        if reason=="no-animation" {h.footAnimator=nil}
        if reason=="input-only" {h.cancelGameplayInput();check(h.footAnimator!.reloading,"Input-only reset ended the reload")}
        _=h.waterForReload(delta:reason=="zero-delta" ? 0:1/60)
        check(callbacks==0,"Non-canceling/rejected water path invalidated reload: "+reason)
        DispatchQueue.main.drain();check(Sink.played==["143_11","143_12"],"Continuing reload lost its second phase: "+reason)
    }
    for compatible in [true,false] {for pending in [false,true] {
        let weapon=compatible ? 22:23
        let(h,owner)=fresh("jetpack",weapon:weapon);owner.audio.deferFetch=pending;begin(h,owner)
        if pending{DispatchQueue.main.drain()}
        var callbacks=0;let bound=h.onReloadTaskCancelled!
        h.onReloadTaskCancelled={
            check(h.personalFlight.flying && !h.footAnimator!.reloading,"Flight notification preceded actual incompatible unarm")
            callbacks+=1;bound()
        }
        check(h.flightForReload() != nil && h.personalFlight.flying,"Actual jetpack takeoff/result was not admitted")
        check(h.footAnimator!.reloading==compatible && callbacks==(compatible ? 0:1),"Jetpack compatibility selected wrong reload owner")
        DispatchQueue.main.drain();owner.audio.releaseSamples()
        let expected=compatible ? ["143_11","143_12"]:(pending ? []:["143_11"])
        check(Sink.played==expected,"Jetpack delayed audio ownership mismatch")
        check(h.equippedWeapon==weapon,"Flight cancellation selected a different inventory weapon")
    }}
    do {
        let(h,owner)=fresh("wall");begin(h,owner)
        var callbacks=0;h.onReloadTaskCancelled={callbacks+=1;owner.audio.cancelReload()}
        check(h.flightForReload()==nil && !h.personalFlight.flying,"Unworn jetpack unexpectedly took off")
        check(h.footAnimator!.reloading && callbacks==0,"Rejected flight ended the reload")
        DispatchQueue.main.drain();check(Sink.played==["143_11","143_12"],"Rejected flight lost its reload phase")
    }
    // These deliberate negatives retain the saved browser phase1 policy.
    do {
        let(h,owner)=fresh("parachute");begin(h,owner)
        h.personalFlight.dive(velocity:.zero,rising:-12,heading:0)
        var callbacks=0;h.onReloadTaskCancelled={callbacks+=1;owner.audio.cancelReload()}
        check(h.flightForReload(running:false) != nil && h.personalFlight.chuting && !h.personalFlight.flying,"Actual parachute result fixture")
        check(!h.footAnimator!.reloading && callbacks==0,"Parachute incorrectly acquired jetpack cancellation policy")
        DispatchQueue.main.drain();check(Sink.played==["143_11","143_12"],"Parachute-only state lost retained phase1")
    }
    do {
        let(h,owner)=fresh("wall");begin(h,owner)
        check(h.footAnimator!.knock() && !h.footAnimator!.reloading,"Actual knock did not end raw animation reload")
        DispatchQueue.main.drain();check(Sink.played==["143_11","143_12"],"Raw knock gained blanket delayed-phase cancellation")
    }
    // LITERAL_HISTORICAL_CONTROL
    print("PASS real water/flight reload audio:",checks,"checks; historicalExecuted:",historicalExecuted,";",library.clipCount,"owned clips; inert audio sink")
 }
}
