import Foundation

// The helper's network initializer is compiled but never invoked by this test.
struct ServerAddress {func path(_ path:String)->URL{URL(string:"http://127.0.0.1/"+path)!}}

@main enum WeaponStateSmoke {
    static func main() {
        var time=100.0,refreshes=0
        func weapon(_ id:Int,_ capacity:Int,_ interval:Double)->NativeWeaponState.Weapon {
            .init(id:id,name:"Fixture",model:"",range:40,capacity:capacity,interval:interval,animation:"fixture",fireKind:"INSTANT_HIT")
        }
        let state=NativeWeaponState(catalog:[weapon(22,17,0.3),weapon(28,50,0.08)],allowLegacySnapshots:true,clock:{time})
        state.onNeedsRefresh={refreshes += 1}
        func apply(_ revision:Int,_ selected:Int,_ clip:Int,_ reload:Double=0) {
            state.apply(["revision":revision,"selected":selected,"weapons":[["id":22,"clip":selected==22 ? clip:1,"rest":30],["id":28,"clip":selected==28 ? clip:4,"rest":100]],"reload":["remainingMs":reload]])
        }
        apply(1,22,2)
        precondition(state.consumeAnimationShot(weapon:22) && state.rounds==1)
        precondition(state.consumeAnimationShot(weapon:22) && state.rounds==0,"Twin/catch-up emission was wall-clock gated")
        precondition(!state.consumeAnimationShot(weapon:22) && state.rounds==0)
        apply(2,28,4)
        precondition(!state.consumeAnimationShot(weapon:22) && state.rounds==4,"Stale switched-weapon event consumed another weapon")
        precondition(state.consumeAnimationShot(weapon:28) && state.rounds==3)
        precondition(!state.fire(),"Fallback allowed a second shot immediately after animation emission")
        time += 0.081
        precondition(state.fire() && state.rounds==2)
        precondition(!state.fire())
        apply(3,22,1,1800)
        precondition(!state.consumeAnimationShot(weapon:22) && state.rounds==1)
        time += 1.801
        state.tick();state.tick()
        precondition(refreshes==1)
        apply(4,22,17)
        precondition(state.consumeAnimationShot(weapon:22) && state.rounds==16)
        apply(3,28,50)
        precondition(state.selected==22 && state.rounds==16,"Old inventory revision undid prediction")
        state.apply(["revision":5,"selected":0,"weapons":[]])
        precondition(!state.consumeAnimationShot(weapon:22))
        precondition(state.consumeAnimationShot(weapon:0) && state.rounds==0)
        let unloaded=NativeWeaponState(allowLegacySnapshots:true,clock:{time})
        unloaded.apply(["revision":1,"selected":22,"weapons":[["id":22,"clip":4,"rest":0]]])
        precondition(!unloaded.consumeAnimationShot(weapon:22),"Unknown weapon emitted before catalog arrived")
        precondition(!unloaded.fire(),"Fallback fired the fist catalog entry for an unloaded selected weapon")
        for id in 1...15 {
            let melee=NativeWeaponState.Weapon(id:id,name:"Melee fixture",model:"",range:1.6,capacity:0,interval:0.35,animation:"fixture",fireKind:"MELEE")
            precondition(melee.isMelee && !melee.isGun,"Nonzero melee weapon misclassified as ammunition-driven")
            let equipped=NativeWeaponState(catalog:[melee],allowLegacySnapshots:true,clock:{time})
            equipped.apply(["revision":1,"selected":id,"weapons":[["id":id,"clip":0,"rest":0]]])
            precondition(equipped.canFire && equipped.consumeAnimationShot(weapon:id) && equipped.rounds==0,"Melee required or spent ammunition")
        }
        for (id,kind) in [(16,"PROJECTILE"),(22,"INSTANT_HIT"),(37,"AREA_EFFECT")] {
            let armed=NativeWeaponState.Weapon(id:id,name:"Ammunition fixture",model:"",range:40,capacity:1,interval:0.3,animation:"fixture",fireKind:kind)
            precondition(!armed.isMelee && armed.isGun,"Ammunition-driven attack misclassified as melee")
        }
        print("PASS: exact animation emission consumption, twin/catch-up rounds, empty clip, selection/reload transitions, stale inventory rejection, monotonic fallback cadence")
    }
}
