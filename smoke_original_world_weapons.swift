import Foundation
var checks=0
func check(_ c:@autoclosure()->Bool,_ m:String){checks+=1;if !c(){fatalError(m)}}
var clock=0.0
let definitions:[NativeOriginalWorldArsenal.Definition]=[
 .init(id:0,slot:0,capacity:0,kind:"MELEE",wait:0,reload:0),
 .init(id:22,slot:2,capacity:17,kind:"INSTANT_HIT",wait:0,reload:1),
 .init(id:24,slot:2,capacity:7,kind:"INSTANT_HIT",wait:0,reload:1),
 .init(id:31,slot:5,capacity:50,kind:"INSTANT_HIT",wait:0,reload:1),
 .init(id:46,slot:11,capacity:0,kind:"MELEE",wait:0,reload:0)]
let catalog:[NativeWeaponState.Weapon]=[22,24,31].map{id in .init(id:id,name:"QA\(id)",model:"",range:40,capacity:id==22 ? 17:id==24 ? 7:50,interval:0.1,animation:"fixture",fireKind:"INSTANT_HIT")}
let original=NativeWeaponState(catalog:catalog,policy:.originalWorld,originalDefinitions:definitions,clock:{clock})
check(!original.synchronized && !original.canFire,"no unnegotiated fire")
check(original.applyOriginalGuns([[22,20]]),"original guns")
check(original.synchronized&&original.selected==0,"original holster")
check(original.selectOriginalWeapon(22)&&original.canFire,"original selected")
check(original.rounds==17&&original.reserve==3,"original split")
check(original.consumeAnimationShot(weapon:22),"unacknowledged original source shot")
check(original.rounds==16&&original.reserve==3&&original.pendingShotCount==0,"original ammo without ACK namespace")
check(original.reloadOriginal(),"local original reload")
check(original.rounds==17&&original.reserve==2&&original.reloading && !original.canFire,"actual original reload deadline")
check(!original.consumeAnimationShot(weapon:22),"no early reload shot")
clock=1.1;original.tick();check(!original.reloading&&original.canFire,"reload completed")
check(original.consumeAnimationShot(weapon:22)&&original.rounds==16,"postreload shot")
let guns=original.outgoingOriginalGuns(flush:true);check(guns==[[22,18]],"outgoing carried totals")
original.originalGunsSent(guns!);check(original.outgoingOriginalGuns(flush:true)==nil,"sent baseline")
check(original.rearmOriginalWeapons([[24,8]]),"server granted inventory")
check(original.selected==0&&original.selectOriginalWeapon(24)&&original.rounds==7&&original.reserve==1,"source same-slot replacement")
check(original.applyOriginalGuns([[22,100]]),"later carried baseline")
check(original.selected==24&&original.weapons.map(\.id)==[0,24],"periodic guns does not grant invented inventory")
check(original.applyOriginalGuns([[31,80]],back:true),"staged return")
check(original.selected==24&&original.outgoingOriginalGuns(flush:true)==nil,"staged return waits")
original.reviveOriginalWeapons();check(original.selected==0&&original.selectOriginalWeapon(31)&&original.rounds==50&&original.reserve==30,"revive inventory")
check(!original.apply(["revision":1,"selected":22,"weapons":[["id":22,"clip":17,"rest":9]],"ack":["connection":"forged","processedShot":0]]),"selfhost snapshot cannot cross original policy")
original.setConnection(nil);check(!original.synchronized&&original.weapons.map(\.id)==[0],"original disconnect clears owner")
let selfhost=NativeWeaponState(catalog:catalog,clock:{clock})
check(!selfhost.applyOriginalGuns([[22,20]]),"original inventory cannot unlock selfhost")
check(!selfhost.selectOriginalWeapon(22)&&selfhost.cycleOriginalWeapon(1)==nil && !selfhost.reloadOriginal(),"original actions cannot cross selfhost policy")
check(!selfhost.canFire&&selfhost.outgoingOriginalGuns(flush:true)==nil,"default strict owner")
selfhost.setConnection("selfhost")
check(!selfhost.canFire && !selfhost.apply(["revision":1,"selected":22,"weapons":[["id":22,"clip":17,"rest":9]]]),"default still requires actual ACK")
check(selfhost.apply(["revision":1,"selected":22,"weapons":[["id":22,"clip":17,"rest":9]],"ack":["connection":"selfhost","processedShot":0]]),"actual independent ACK accepted")
check(selfhost.canFire && !selfhost.consumeAnimationShot(weapon:22),"default still needs reserved ticket")
let legacy=NativeWeaponState(catalog:catalog,policy:.legacySAMP,originalDefinitions:definitions,clock:{clock})
check(legacy.giveClientWeapon(22,amount:20),"Legacy GiveWeapon")
check(!legacy.canFire && !legacy.synchronized,"Legacy weapons cannot bypass session readiness")
legacy.setClientWeaponReady(true);check(legacy.canFire&&legacy.selected==22&&legacy.rounds==17&&legacy.reserve==3,"Legacy actual ready without fake inventory ACK")
check(!legacy.applyOriginalGuns([[22,999]])&&legacy.outgoingOriginalGuns(flush:true)==nil,"Legacy does not impersonate original service guns protocol")
check(legacy.setClientAmmo(22,amount:5)&&legacy.rounds==5&&legacy.reserve==0,"Legacy SetAmmo changes total")
check(legacy.setClientAmmo(22,amount:0)&&legacy.selected==0&&legacy.weapons.map(\.id)==[0],"Legacy zero ammo removes inventory")
check(legacy.setClientAmmo(22,amount:9)&&legacy.selected==0,"Legacy zero slot can receive later ammo without forcing selection")
check(legacy.selectOriginalWeapon(22)&&legacy.rounds==9,"Legacy armed weapon RPC")
check(legacy.consumeAnimationShot(weapon:22)&&legacy.rounds==8&&legacy.pendingShotCount==0,"Legacy local shot has no fake ACK")
check(legacy.giveClientWeapon(24,amount:8)&&legacy.selected==24&&legacy.rounds==7,"Legacy same-slot replacement")
check(legacy.resetClientWeapons()&&legacy.selected==0&&legacy.weapons.map(\.id)==[0]&&legacy.synchronized,"Legacy ResetWeapons retains actual session readiness")
check(!legacy.setClientAmmo(31,amount:10),"SetAmmo does not invent an unowned weapon")
check(!selfhost.giveClientWeapon(22,amount:999) && !selfhost.setClientAmmo(22,amount:1) && !selfhost.resetClientWeapons(),"Client RPCs cannot mutate independent ACK inventory")
legacy.setConnection(nil);check(!legacy.synchronized && !legacy.canFire,"Legacy disconnect clears and locks owner")
enum Arrival {
 case guns([[Int]],Bool),give(Int,Int),rearm([[Int]]),remove(Int),reset,select(Int),revive
 func send(_ target:NativeWeaponState){
  switch self {
  case .guns(let rows,let back):_=target.applyOriginalGuns(rows,back:back)
  case .give(let id,let amount):_=target.giveClientWeapon(id,amount:amount)
  case .rearm(let rows):_=target.rearmOriginalWeapons(rows)
  case .remove(let id):_=target.removeClientWeapon(id)
  case .reset:_=target.resetClientWeapons()
  case .select(let id):_=target.selectOriginalWeapon(id)
  case .revive:target.reviveOriginalWeapons()
  }
 }
}
let document:[String:Any]=["schema":1,"protocol":38,"definitions":definitions.map{["id":$0.id,"slot":$0.slot,"capacity":$0.capacity,"kind":$0.kind,"wait":$0.wait,"reload":$0.reload] as [String:Any]}]
let arrivals:[[Arrival]]=[
 [.give(22,20),.guns([[24,8]],false)],
 [.rearm([[24,8]]),.guns([[22,20]],false)],
 [.reset,.guns([[22,20]],false)],
 [.guns([[22,20]],false),.guns([[31,80]],true),.revive,.remove(31)],
 [.guns([[22,20]],false),.remove(22),.select(0),.rearm([[24,8]]),.guns([[31,80]],true),.revive,.select(31)],
 [.guns([[22,20]],false),.give(46,1),.remove(46)],
 [.guns([[22,20]],false),.give(31,100),.reset,.rearm([[24,8]]),.guns([[22,30]],false)]
]
for (index,events)in arrivals.enumerated(){
 let ready=NativeWeaponState(catalog:catalog,policy:.originalWorld,originalDefinitions:definitions,clock:{clock})
 let delayed=NativeWeaponState(catalog:catalog,policy:.originalWorld,clock:{clock})
 for event in events{event.send(ready);event.send(delayed)}
 check(!delayed.synchronized && !delayed.canFire,"metadata delay cannot unlock ammo\(index)")
 check(delayed.installClientWeaponCatalog(document),"real sidecar completion\(index)")
 check(ready.weapons.map(\.id)==delayed.weapons.map(\.id)&&ready.selected==delayed.selected,"arrival order preserves owned/selected\(index)")
 check(ready.rounds==delayed.rounds&&ready.reserve==delayed.reserve&&ready.synchronized==delayed.synchronized,"arrival order preserves ammo/baseline\(index)")
 check(ready.outgoingOriginalGuns(flush:true)==delayed.outgoingOriginalGuns(flush:true),"arrival order preserves wire inventory\(index)")
}
let beforeMetadata=NativeWeaponState(catalog:catalog,policy:.originalWorld,clock:{clock})
_=beforeMetadata.giveClientWeapon(22,amount:20);beforeMetadata.setConnection(nil);_=beforeMetadata.applyOriginalGuns([[24,8]])
check(beforeMetadata.installClientWeaponCatalog(document)&&beforeMetadata.weapons.map(\.id)==[0,24],"connection change drops old queued commands")
let bounded=NativeWeaponState(catalog:catalog,policy:.originalWorld,clock:{clock});var overflows=0;bounded.onNeedsResync={overflows+=1}
for _ in 0..<128{check(bounded.giveClientWeapon(22,amount:1),"bounded queued accepted")}
check(!bounded.applyOriginalGuns([[24,8]]) && !bounded.rearmOriginalWeapons([[24,8]])&&overflows==1,"shared FIFO bound and one resync")
bounded.setConnection(nil);check(bounded.applyOriginalGuns([[24,8]])&&bounded.installClientWeaponCatalog(document)&&bounded.weapons.map(\.id)==[0,24],"new session recovers after queue overflow")
let reentrant=NativeWeaponState(catalog:catalog,policy:.originalWorld,clock:{clock})
_=reentrant.giveClientWeapon(22,amount:20);_=reentrant.rearmOriginalWeapons([[24,8]])
var cancelled=false;reentrant.onChange={if !cancelled&&reentrant.selected==22{cancelled=true;reentrant.setConnection(nil)}}
check(reentrant.installClientWeaponCatalog(document)&&cancelled&&reentrant.weapons.map(\.id)==[0] && !reentrant.synchronized,"reentrant disconnect cancels old FIFO tail")
let utility=NativeWeaponState(catalog:catalog,policy:.originalWorld,originalDefinitions:definitions,clock:{clock})
_=utility.applyOriginalGuns([]);check(utility.giveClientWeapon(46,amount:1)&&utility.selected==46,"local parachute inventory")
check(utility.removeClientWeapon(46)&&utility.selected==0 && !utility.removeClientWeapon(46),"remove consumes local canopy once")
check(!selfhost.removeClientWeapon(22)&&selfhost.rounds==17,"remove cannot mutate independent authority")
let replace=NativeWeaponState(catalog:catalog,policy:.originalWorld,originalDefinitions:definitions,clock:{clock})
_=replace.applyOriginalGuns([[22,20]]);_=replace.setClientAmmo(22,amount:0);_=replace.rearmOriginalWeapons([[24,8]])
check(!replace.setClientAmmo(22,amount:10),"explicit replacement invalidates old zero-ammo slots")
print("PASS actual NativeWeaponState original/default/legacy policy and arrival FIFO: \(checks) checks")
