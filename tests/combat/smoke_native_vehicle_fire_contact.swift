// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

var checks=0,referenceCases=0
func check(_ value:Bool,_ name:String){checks+=1;if !value{fputs("FAIL: "+name+"\n",stderr);exit(42)}}
func near(_ a:Double,_ b:Double)->Bool{abs(a-b)<1e-8}

final class Renderer {
    let weaponEffects=NativeWeaponEffects()
    var camera=SIMD3<Float>.zero
    var vehicleThermalHot:[String:(position:SIMD3<Double>,time:Double)]=[:]
    var particleDrawDelta=0.0,deferredVehicleSurfaces:[Int]?=[]
    func beginDraw(delta:Float) {
        // ACTUAL_DRAW_BOUNDARY
    }
    var swimming=false,underwater=false,hasOriginalWorldGas=false,burning=false
    func setOriginalActorEffects(burning:Bool,coughing:Bool){self.burning=burning}
    // ACTUAL_GETTER
    func publish(_ emissions:[NativeVehicleThermalEffects.Emission],now:Double,token:String="parked:taxi") {
        let context=(token:token,unused:0)
        // ACTUAL_CACHE_PUBLICATION
    }
    func renderCondition(health:Double,burning:Bool,engine:SIMD3<Double> = SIMD3(0,0,1),now:Double=ProcessInfo.processInfo.systemUptime,token:String="parked:taxi") {
        var state=NativeVehicleThermalEffects.State()
        let emissions=NativeVehicleThermalEffects.sample(.init(model:420,kind:"car",health:health,burning:burning,engine:engine,transform:matrix_identity_double4x4,velocity:.zero,delta:1.0/60),state:&state)
        publish(emissions,now:now,token:token)
    }
}
final class Network {
    let vitals=NativeOriginalWorldVitals()
    var usesOriginalWorldProtocol=true,isReady=true,applications=0
    var health:Int{vitals.displayHealth}
    @discardableResult func applyOriginalDamage(_ hit:NativeOriginalWorldVitals.Hit,context:NativeOriginalWorldVitals.Context)->NativeOriginalWorldVitals.Result {
        applications+=1;return vitals.hurt(hit,context:context)
    }
}
final class Game {
    let network=Network(),originalEffects=NativeOriginalWorldEffects()
    var renderer:Renderer?=Renderer(),currentVehicle:String?
    var fatalPolls=0
    func processOriginalFatal(){fatalPolls+=1}
    // ACTUAL_GAMEPLAY
    func frame(_ steps:[Double]){stepOriginalGameplay(steps)}
}
func touch(_ feet:SIMD3<Float>,_ point:SIMD3<Double>,_ sample:Double=0,_ now:Double=0)->Bool {
    NativeOriginalWorldEffects.vehicleFireTouches(atFeet:feet,point:point,sampledAt:sample,now:now)
}
func touch(_ point:SIMD3<Double>,_ sample:Double=0,_ now:Double=0)->Bool{touch(.zero,point,sample,now)}
for axis in 0..<3 {
    for distance in [0.0,1.0,1.9999,2.0,2.0001,-1.9999,-2.0,-2.0001] {
        var point=SIMD3<Double>(0,0,1);point[axis]+=distance
        check(touch(point)==(abs(distance)<2),"strict2m sphere axis\(axis) distance\(distance)")
    }
}
check(touch(SIMD3(10,-20,30),SIMD3(10,-20,31)),"GTA Z-up body centre")
check(!touch(SIMD3(10,-20,30),SIMD3(10,-19,30+2.8)),"no accidental browser-axis conversion")
check(touch(SIMD3(0,0,1),0,0.199999),"recent preceding draw survives until next gameplay tick")
check(!touch(SIMD3(0,0,1),0,0.2),"expired cache strict boundary")
check(!touch(SIMD3(0,0,1),1,0),"future/old-session clock rejected")
for number in [Double.nan,Double.infinity,-Double.infinity] {
    check(!touch(SIMD3(number,0,1)),"invalid heat position")
    check(!touch(SIMD3(0,0,1),number,1),"invalid sample clock")
    check(!touch(SIMD3(0,0,1),0,number),"invalid current clock")
    check(!touch(SIMD3(Float(number),0,0),SIMD3(0,0,1)),"invalid actor position")
}
do {
    let r=Renderer();check(!r.hasOriginalWorldFire,"empty original environment")
    r.renderCondition(health:500,burning:false);check(r.vehicleThermalHot.isEmpty && !r.hasOriginalWorldFire,"smoke is not a damaging fire")
    r.renderCondition(health:249,burning:true);check(r.hasOriginalWorldFire,"real sampled fire reaches actual getter")
    r.renderCondition(health:1000,burning:false);check(r.vehicleThermalHot.isEmpty && !r.hasOriginalWorldFire,"repair clears same occurrence heat immediately")
    r.renderCondition(health:249,burning:false);check(r.vehicleThermalHot.isEmpty && !r.hasOriginalWorldFire,"submerged physical burning suppression remains authoritative")
    r.renderCondition(health:249,burning:true,engine:SIMD3(30,0,1));check(!r.hasOriginalWorldFire,"far occurrence cannot ignite actor")
    r.renderCondition(health:249,burning:true,now:ProcessInfo.processInfo.systemUptime-1);check(!r.hasOriginalWorldFire,"no stale heat after culling")
    r.renderCondition(health:249,burning:true);r.beginDraw(delta:1.0/144);check(!r.hasOriginalWorldFire,"actual next draw with no submitted vehicle retires preceding heat")
    r.renderCondition(health:249,burning:true,token:"unused")
    r.beginDraw(delta:1.0/15)
    r.renderCondition(health:249,burning:true,token:"visible")
    check(r.vehicleThermalHot.count==1 && r.vehicleThermalHot["visible"] != nil,"new draw contains only its submitted occurrence")
    r.renderCondition(health:1000,burning:false,token:"visible")
    check(!r.hasOriginalWorldFire,"repair after frame replacement removes current heat")
    r.weaponEffects.groundHeight={_,_,_ in 0};r.weaponEffects.receiveBlast(weapon:18,position:SIMD3(0,0,0))
    check(r.hasOriginalWorldFire,"existing weapon-fire fallback retained without vehicle heat")
}
for rate in [15,30,60,120,144] {
    let game=Game(),r=game.renderer!
    r.renderCondition(health:249,burning:true);game.frame([1/Double(rate)])
    check(game.originalEffects.burning && r.burning,"actual controller ignites from vehicle heat at\(rate)Hz")
    check(game.originalEffects.fireSource==nil,"environmental fire is unattributed")
    r.renderCondition(health:1000,burning:false)
    game.frame(Array(repeating:1/Double(rate),count:rate*4))
    check(near(game.network.vitals.health,100-2.333*8.25),"one fractional burn interval after contact at\(rate)Hz")
    check(!game.originalEffects.burning && !r.burning,"effect ends without stale re-ignition at\(rate)Hz")
}
for condition in ["independent-server","not-ready","seated","swimming"] {
    let game=Game();game.renderer!.renderCondition(health:249,burning:true)
    if condition=="independent-server"{game.network.usesOriginalWorldProtocol=false}
    if condition=="not-ready"{game.network.isReady=false}
    if condition=="seated"{game.currentVehicle="taxi"}
    if condition=="swimming"{game.renderer!.swimming=true}
    game.frame(Array(repeating:1.0/60,count:120))
    check(!game.originalEffects.burning && game.network.applications==0 && game.network.vitals.health==100,"\(condition) must not gain local duplicate/environment damage")
}
do {
    let game=Game();game.renderer!.renderCondition(health:249,burning:true);game.frame([1.0/60]);game.renderer!.swimming=true;game.frame([1.0/60])
    check(!game.originalEffects.burning && !game.renderer!.burning,"water extinguishes existing vehicle ignition")
}
if CommandLine.arguments.count>1 {
    let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
    let root=try JSONSerialization.jsonObject(with:data)as! [String:Any]
    check(root["status"]as?String=="PASS_CONTROLLED_SHIPPED_HEAT_PREDICATE","matching controlled callable record")
    for row in root["cases"]as! [[String:Any]] where (row["people"]as! [[String:Any]]).isEmpty {
        func vec(_ values:[NSNumber])->SIMD3<Double>{SIMD3(values[0].doubleValue,values[1].doubleValue,values[2].doubleValue)}
        let feet=SIMD3<Float>(vec(row["feet"]as! [NSNumber]))
        let points=(row["hot"]as! [[NSNumber]]).map(vec)
        check(points.contains{touch(feet,$0)}==row["burning"]as! Bool,"selected original hot sphere \(row["name"]!)");referenceCases+=1
    }
    check(referenceCases>30,"hot-only reference coverage present; raw people explicitly excluded")
}
print("PASS vehicle fire contact: \(checks) checks; \(referenceCases) controlled hot-only records. No retail/GPU claim.")
