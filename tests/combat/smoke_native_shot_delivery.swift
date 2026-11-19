import Foundation

var now = 10.0
let gun = NativeWeaponState.Weapon(id: 22,name: "Pistol",model: "colt45",range: 35,capacity: 17,interval: 0.25,animation: "colt45",fireKind: "INSTANT_HIT")
let other = NativeWeaponState.Weapon(id: 28,name: "SMG",model: "uzi",range: 35,capacity: 50,interval: 0.1,animation: "uzi",fireKind: "INSTANT_HIT")
let inventory = NativeWeaponState(catalog: [gun,other],allowLegacySnapshots:true,clock: { now })
var revision = 1
func load(_ weapon: Int, _ clip: Int, reload: Bool = false) {
    revision += 1
    inventory.apply(["revision":revision,"selected":weapon,"weapons":[["id":weapon,"clip":clip,"rest":100]],
        "reload":reload ? ["remainingMs":1000]:[:]])
}
var ready = false, order:[String] = [], events:[(Int,Bool)] = []
func deliver(_ weapon: Int, _ left: Bool) -> Bool {
    NativeWeaponShotDelivery.deliver(weapon:weapon,left:left,inventory:inventory,readiness:{
        ready=$0;order.append("ready:\($0)")
    },emission:{ weapon,left in
        precondition(ready == (inventory.rounds > 0 && !inventory.reloading))
        order.append("emit");events.append((weapon,left))
    })
}
load(22,1)
precondition(deliver(22,false));precondition(inventory.rounds==0 && !ready && order==["ready:false","emit"])
precondition(!deliver(22,true) && events.count==1,"second hand cannot spend the last round twice")
load(22,2);order=[];events=[]
precondition(deliver(22,false) && deliver(22,true));precondition(events.map(\.1)==[false,true] && inventory.rounds==0)
precondition(order==["ready:true","emit","ready:false","emit"],"readiness precedes each fixed-step emission")
precondition(!inventory.fire(),"fallback interval cannot duplicate an animation event")
load(28,10);events=[]
precondition(!deliver(22,false) && inventory.rounds==10 && events.isEmpty,"weapon switch rejects stale event")
load(28,10,reload:true);precondition(!deliver(28,false) && inventory.rounds==10 && !ready,"reload rejects emission")
now += 1.1
precondition(!deliver(28,false),"local reload countdown cannot invent authoritative completion")
load(28,10)
precondition(deliver(28,false) && inventory.rounds==9 && ready,"completed reload allows current weapon")
for hz in [30,60,120] {
    load(28,50);events=[];now=100
    // Three animation events arrive in one display frame after a small hitch.
    // Their clock is identical: this boundary must not impose a frame timer.
    for left in [false,true,false] { precondition(deliver(28,left)) }
    precondition(inventory.rounds==47 && events.count==3,"catch-up emissions at \(hz)Hz")
}
print("PASS: native shot delivery atomically updates readiness before twin/catch-up emissions; empty, stale, reload and fallback duplicate events rejected")
