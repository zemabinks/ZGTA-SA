// SPDX-License-Identifier: AGPL-3.0-only
// Actual Effects helper, authored snapshots and explicit collision availability.
import Foundation
import simd

var checks=0,cases=0
func check(_ ok:Bool,_ message:String){if !ok{fputs("FAIL: "+message+"\n",stderr);exit(23)};checks+=1}
func rows(_ weapon:Int,age:Float=0,lifetime:Float=0.5,lying:Bool=false)->[[String:Any]] {
    [["id":"projectile-1","weapon":weapon,"position":[10.0,20.0,30.0],"velocity":[1.0,2.0,3.0],
      "age":age,"lifetime":lifetime,"rocket":[19,20,35,36].contains(weapon),"lying":lying]]
}
for weapon in [16,17,18,19,20,35,36,39] {
    cases+=1;let effect=NativeWeaponEffects();var traces=0,booms=0,trails=0
    effect.synchronizeServer(rows(weapon));effect.geometryAvailable={_,_,_ in false}
    effect.trace={_,_,_ in traces+=1;return nil};effect.onDetonation={_ in booms+=1};effect.onTrail={_,_,_ in trails+=1}
    effect.update(delta:0.25)
    check(effect.projectiles.count==1,"pre-expiry prediction retained")
    check(abs(effect.projectiles[0].age-0.25)<0.00001,"unknown coverage cannot freeze projectile age")
    check(effect.projectiles[0].position==SIMD3(10,20,30) && effect.projectiles[0].velocity==SIMD3(1,2,3),"unknown coverage cannot invent travel or momentum")
    effect.update(delta:0.25)
    check(effect.projectiles.isEmpty,"uncovered expired prediction retires")
    check(traces==0 && booms==0 && trails==0,"uncovered expiry cannot invent collision, blast or trail")
    for _ in 0..<4{effect.update(delta:0.25)}
    check(booms==0,"expired prediction cannot replay")
    effect.synchronizeServer(rows(weapon,age:0.1))
    check(effect.projectiles.count==1 && abs(effect.projectiles[0].age-0.1)<0.00001,"real server snapshot remains authoritative after local expiry")
}
for rate in [15,30,60,120,144] {
    cases+=1;let effect=NativeWeaponEffects();effect.synchronizeServer(rows(16,lifetime:0.75));effect.geometryAvailable={_,_,_ in false}
    for _ in 0..<(rate/2){effect.advance(delta:1/Double(rate))}
    check(effect.projectiles.count==1,"pre-fuse display schedule retains projectile")
    check(abs(Double(effect.projectiles[0].age)-floor(Double(rate/2)/Double(rate)*60)/60)<0.0001,"fixed prediction clock advances through streaming wait")
    for _ in 0..<rate{effect.advance(delta:1/Double(rate))}
    check(effect.projectiles.isEmpty,"all display schedules retire unavailable prediction")
}
do {
    cases+=1;let effect=NativeWeaponEffects();var covered=false,booms=0
    effect.synchronizeServer(rows(16,lifetime:0.5));effect.geometryAvailable={_,_,_ in covered};effect.onDetonation={_ in booms+=1}
    effect.update(delta:0.25);covered=true;effect.update(delta:0.25)
    check(effect.projectiles.isEmpty && booms==1,"restored known coverage retains ordinary fuse branch")
    effect.update(delta:0.25);check(booms==1,"known fuse emits once per admitted prediction")
}
for weapon in [16,17,18,35,39] {
    cases+=1;let effect=NativeWeaponEffects();var booms=0
    effect.synchronizeServer(rows(weapon,lifetime:0.5,lying:true));effect.geometryAvailable={_,_,_ in false};effect.onDetonation={_ in booms+=1}
    effect.update(delta:0.5)
    check(effect.projectiles.isEmpty,"known resting prediction expires without a movement-coverage request")
    check(booms==([17,39].contains(weapon) ? 0:1),"resting gas/satchel expiry and explosive policy preserved")
}
do {
    cases+=1;let effect=NativeWeaponEffects();effect.synchronizeServer(rows(18));effect.geometryAvailable={_,_,_ in false};effect.update(delta:0.5)
    check(effect.fires.isEmpty,"uncovered local molotov expiry cannot create fire")
    effect.groundHeight={_,_,_ in 0};effect.receiveBlast(weapon:18,position:SIMD3(1,2,0))
    check(effect.fires.count==1 && !effect.fires[0].flames.isEmpty,"actual authoritative molotov echo still creates its own fire")
}
do {
    cases+=1;let effect=NativeWeaponEffects();effect.synchronizeServer(rows(16));effect.geometryAvailable={_,_,_ in false}
    effect.advance(delta:0.6);check(effect.projectiles[0].age==0,"suspension-sized rejected delta does not extrapolate time")
    effect.clear();effect.advance(delta:0.25);check(effect.projectiles.isEmpty,"session clear retains no old prediction clock")
}
print("Projectile clock PASS \(checks) checks / \(cases) cases; no live damage or rendering claim")
