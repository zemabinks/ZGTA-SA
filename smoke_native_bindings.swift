import Foundation

typealias B=NativeGameBindings
typealias K=B.Key
var checks=0
func check(_ ok:@autoclosure()->Bool,_ why:String) {checks += 1;if !ok() {print("FAIL: \(why)");exit(1)}}
func keys(_ list:K...)->Set<Int> {Set(list.map(\.rawValue))}
let foot=B.Context(),car=B.Context(mode:.vehicle("car")),plane=B.Context(mode:.vehicle("plane"),landingGear:true,nozzle:true)
let climb=B.Context(mode:.climb),swim=B.Context(mode:.swim),jet=B.Context(mode:.jetpack),chute=B.Context(mode:.parachute)
check(B.keyboard(keys(.space),context:foot).sprint,"PC Space sprint")
check(!B.keyboard(keys(.shift),context:foot).sprint,"Shift is not sprint")
for key in [K.shift,.rightControl] {check(B.keyAction(key.rawValue,context:foot)==B.Action.jump,"PC jump alternative")}
for key in [K.f,.enter] {check(B.keyAction(key.rawValue,context:foot)==B.Action.enter,"PC enter alternative")}
check(B.keyAction(K.q.rawValue,context:foot)==B.Action.weaponPrevious,"Q cycles previous weapon")
check(B.keyAction(K.e.rawValue,context:foot)==B.Action.weaponNext,"E cycles next weapon")
check(B.keyAction(K.j.rawValue,context:foot)==B.Action.jobs,"Jobs remains an explicit app extension")
check(B.keyboard(keys(.alt),context:foot).walk,"Alt walking intent")
for c in [climb,swim,jet,chute,car] {check(!B.keyboard(keys(.alt),context:c).walk,"walking intent does not leak into another movement task")}
check(B.keyboard(keys(.alt,.space),context:foot).sprint,"walk modifier must not erase independent sprint input")
check(B.cameraAimUpdate(held:false,previousHeld:false,melee:false,current:true)==nil,"neutral hardware cannot cancel touch gun aim")
check(B.cameraAimUpdate(held:true,previousHeld:false,melee:false,current:false)==true,"hardware aim press takes ownership")
check(B.cameraAimUpdate(held:false,previousHeld:true,melee:false,current:true)==false,"hardware aim release clears its own aim")
check(B.cameraAimUpdate(held:true,previousHeld:true,melee:true,current:true)==false,"melee never retains gun camera aim")
check(B.cameraAimUpdate(held:true,previousHeld:true,melee:true,current:false)==nil,"guard pose does not churn gun camera state")
for (gun,melee) in [(true,false),(false,true)] {
    check(B.shouldRequestAttack(held:true,wasHeld:false,nativeGun:gun,nativeMelee:melee),"native attack request begins at edge")
    check(!B.shouldRequestAttack(held:true,wasHeld:true,nativeGun:gun,nativeMelee:melee),"native timing must not refresh intent every display tick")
}
check(B.shouldRequestAttack(held:true,wasHeld:true,nativeGun:false,nativeMelee:false),"legacy fallback retains interval-driven retry")
for (key,x,y) in [(K.up,Float(0),Float(1)),(.down,0,-1),(.left,-1,0),(.right,1,0)] {
    let f=B.keyboard(keys(key),context:foot)
    check(f.forward==y && f.sideways==x,"arrows move on foot")
}
let opposed=B.keyboard(keys(.a,.d,.w,.s),context:foot)
check(opposed.moving && opposed.sideways==0 && opposed.forward==0,"opposite keys cancel")
for key in [K.space,.rightControl] {check(B.keyboard(keys(key),context:car).handbrake,"PC vehicle handbrake alternative")}
check(B.keyboard(keys(.left),context:car).steering == -1,"vehicle arrow steers instead of camera look")
check(B.keyboard(keys(.up),context:plane).pitch == 1,"aircraft nose axis")
check(B.keyboard(keys(.a),context:plane).sideways == -1,"aircraft A/D rudder")
check(B.keyboard(keys(.a),context:plane).steering==0,"aircraft rudder is not roll")
check(B.keyboard(keys(.q),context:car).look=="left","Q vehicle look left")
check(B.keyboard(keys(.e),context:car).look=="right","E vehicle look right")
check(B.keyboard(keys(.q,.e),context:car).look=="behind","Q+E vehicle look behind")
check(B.keyboard(keys(.keypadOne),context:foot).look=="behind","PC on-foot keypad1 look behind")
check(B.keyAction(K.r.rawValue,context:car)==B.Action.radioPrevious,"vehicle R previous radio")
check(B.keyAction(K.r.rawValue,context:foot)==B.Action.reload,"foot R native reload extension")
for k in [K.control,.keypadZero] {
    check(B.keyboard(keys(k),context:foot).attack,"PC fire alternative")
    check(B.keyAction(k.rawValue,context:swim)==B.Action.dive,"swim fire input dives")
}
check(B.keyAction(K.c.rawValue,context:swim)==B.Action.dive,"swim C native touch-equivalent alternative")
check(B.keyboard(keys(.shift),context:jet).jump,"jetpack descend uses jump held")
check(B.keyAction(K.shift.rawValue,context:jet)==nil,"jetpack descend must not launch a walking jump")
check(B.keyboard(keys(.c),context:jet).flightBrake,"jetpack C brake")
check(B.keyAction(K.c.rawValue,context:climb)==nil,"climbing cannot change crouch task")
check(B.keyAction(K.shift.rawValue,context:climb)==B.Action.jump,"climb pull uses jump")
let guarded=B.Context(melee:true,guarding:true)
for k in [K.shift,.rightControl] {check(B.keyAction(k.rawValue,context:guarded)==nil,"guarded jump is block, never a jump edge")}
for k in [K.f,.enter] {check(B.keyAction(k.rawValue,context:guarded)==B.Action.meleeAlternate,"guarded enter becomes distinct special intent")}
check(B.keyAction(K.f.rawValue,context:B.Context(melee:true))==B.Action.enter,"unguarded enter keeps vehicle action")
for k in [K.control,.keypadZero] {
    check(B.keyboard(keys(k),context:B.Context(mode:.vehicle("bicycle"))).hop,"original secondary-fire alternative charges bicycle hop")
    check(!B.keyboard(keys(k),context:car).hop,"hop is bicycle-only, no fictional car weapon")
}
check(!B.keyboard(keys(.space,.rightControl),context:B.Context(mode:.vehicle("bicycle"))).hop,"brake is not bunny hop")
var x=B.Pad();x.x=true
var y=B.Pad();y.y=true
var b=B.Pad();b.b=true
var menu=B.Pad();menu.menu=true;menu.x=true;menu.y=true
for c in [foot,climb,swim] {
    check(B.padActions(x,previous:.init(),context:c)==[.jump],"console X/Square jump/pull")
    check(B.padActions(y,previous:.init(),context:c)==[.enter],"console Y/Triangle enter/drop")
    check(B.padActions(x,previous:x,context:c).isEmpty,"holding jump does not repeat edge")
}
check(B.padActions(x,previous:.init(),context:guarded).isEmpty,"aim+pad X blocks rather than jumps")
check(B.padActions(y,previous:.init(),context:guarded)==[.meleeAlternate],"aim+pad Y distinct special request")
check(B.padActions(b,previous:.init(),context:swim)==[.dive],"console B/Circle dive")
check(B.padActions(b,previous:.init(),context:climb)==[.enter],"console B/Circle drop")
check(B.padActions(x,previous:.init(),context:car).isEmpty,"vehicle X is held handbrake, no walking jump")
check(B.padActions(menu,previous:.init(),context:foot)==[.pause],"pause suppresses same-poll gameplay actions")
var shoulders=B.Pad();shoulders.lb=true;shoulders.rb=true
check(B.padActions(shoulders,previous:.init(),context:foot)==[.weaponPrevious,.weaponNext],"both weapon directions exist")
check(B.padActions(shoulders,previous:shoulders,context:foot).isEmpty,"held shoulder never opens/repeats shop")
check(B.padLook(shoulders,context:plane)==nil,"aircraft rudder must not simultaneously force camera look")
check(B.padLook(shoulders,context:car)=="behind","car shoulders retain fixed look")
var rightClick=B.Pad();rightClick.rightClick=true
for c in [foot,car,plane,swim,climb,jet,chute] {check(B.padLook(rightClick,context:c)=="behind","R3 look-behind intent survives context")}
check(B.legend(plane).contains("RUDDER") && !B.legend(plane).contains("LB/RB: LOOK"),"aircraft legend does not advertise camera on rudder")
check(B.legend(B.Context(mode:.vehicle("bicycle"))).contains("BUNNY HOP"),"bicycle legend exposes actual separate hop")
check(B.legend(climb).contains("LET GO") && B.legend(jet).contains("DESCEND"),"task-specific control legend")
for c in [foot,car,plane,climb,swim,jet,chute,B.Context(mode:.vehicle("bike")),B.Context(mode:.vehicle("bicycle"))] {
    for raw in 0...255 {
        let f=B.keyboard([raw],context:c)
        check([f.forward,f.sideways,f.steering,f.pitch,f.nozzle].allSatisfy{$0.isFinite && abs($0)<=1},"bounded mapped axis")
        if c.driving {check(!f.attack && !f.aim && !f.jump && !f.sprint,"vehicle has no fictional on-foot weapon action")}
        if let a=B.keyAction(raw,context:c),a == .jump {check(!c.driving && c.mode != .jetpack && c.mode != .parachute,"no invalid jump task")}
    }
}
// Bidirectional actual station rings, including off-only, streamed and local.
for ring in [[13],[1,2,3,4,5,6,7,8,9,10,11,13],[12,13],Array(1...13)] {
    for station in ring {
        let next=NativeRadioSelection.cycle(station,choices:ring,direction:1)!
        check(NativeRadioSelection.cycle(next,choices:ring,direction:-1)==station,"radio cycle inverse")
        check(ring.contains(next),"only an actually available station is selected")
    }
}
check(NativeRadioSelection.cycle(0,choices:[],direction:1)==nil,"no empty-ring crash")
check(NativeRadioSelection.cycle(13,choices:[12,13],direction:0)==nil,"no zero-direction retune")
// Real pending selections must advance their cursor independently of old ACKs.
check(B.weaponOrder([["id":16,"slot":8],["id":22,"slot":2],["id":0,"slot":0]],owned:[0,16,22])==[0,22,16],"actual weapon slots, not numeric IDs, place thrown weapons after guns")
do {
    let q=NativeWeaponCycleQueue(),owned=[0,22,25]
    let first=q.request(direction:1,owned:owned,selected:0)!
    check(first.weapon==22,"first weapon")
    check(q.request(direction:1,owned:owned,selected:0)==nil,"serialize second input")
    check(q.request(direction:-1,owned:owned,selected:0)==nil,"serialize reverse input")
    let second=q.complete(first.id,succeeded:true)!
    check(second.weapon==25,"second uses requested cursor, not stale selected0")
    let third=q.complete(second.id,succeeded:true)!
    check(third.weapon==22,"reverse uses last requested target")
    check(q.complete(third.id,succeeded:true)==nil && !q.busy,"queue drains")
    let pending=q.request(direction:1,owned:owned,selected:22)!
    q.cancel()
    check(q.busy && q.request(direction:1,owned:owned,selected:22)==nil,"cancel blocks racing old HTTP mutation")
    check(q.complete(pending.id,succeeded:true)==nil && !q.busy,"cancel drops pending transitions")
    let old=q.request(direction:1,owned:owned,selected:25)!
    q.disconnected()
    let fresh=q.request(direction:1,owned:owned,selected:0)!
    check(q.complete(old.id,succeeded:true)==nil && q.busy,"old connection completion cannot unblock new request")
    check(q.complete(fresh.id,succeeded:nil)==nil && !q.busy,"uncertain request stops queue")
}
do {
    let q=NativeWeaponCycleQueue()
    let first=q.request(direction:1,owned:[0,22,16],selected:0)!
    check(first.weapon==22,"pending cycle preserves supplied slot order")
    _=q.request(direction:1,owned:[0,22,16],selected:0)
    check(q.complete(first.id,succeeded:true)?.weapon==16,"next slot is thrown weapon, not a numeric sort")
}
var gate=NativeControllerInputGate()
check(!gate.accepts(active:true,axes:[0],pressed:true),"connect while held blocks input")
check(gate.accepts(active:true,axes:[0],pressed:false),"neutral re-arms")
check(!gate.accepts(active:false,axes:[0],pressed:false),"overlay/background resets gate")
check(!gate.accepts(active:true,axes:[0],pressed:true),"resume never replays held action")
var menuEdge=NativeReleaseEdge(pressed:true)
for _ in 0..<120 {check(!menuEdge.update(pressed:true),"held opening Menu/Escape cannot resume panel")}
check(!menuEdge.update(pressed:false),"release is not a close action")
check(menuEdge.update(pressed:true),"new Menu/Escape press resumes")
check(!menuEdge.update(pressed:true),"resume action occurs once")
do {
    let handoff=NativeModalKeyHandoff(pressed:true)
    for _ in 0..<120 {check(!handoff.press(),"opening held Escape is not a fresh panel edge")}
    handoff.release() // release goes to presenter during modal transition
    check(handoff.press(),"presenter key-up survives delayed modal appearance")
    check(!handoff.press(),"modal repeat still suppressed")
    handoff.release();check(handoff.press(),"panel key-up also rearms next distinct press")
}
print("PASS: \(checks) keyboard/controller/context/radio/selection checks")
