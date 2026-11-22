// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
import Darwin

enum WaterFireProbe {
    struct Failure:Error {let text:String}
    static var checks=0
    static func require(_ value:Bool,_ text:String)throws {checks+=1;if !value {throw Failure(text:text)}}
    static func clock(_ damage:NativeVehicleDamage)throws->Double {
        guard let value=Mirror(reflecting:damage).children.first(where:{$0.label=="fireTicks"})?.value as?Double else {throw Failure(text:"actual fire clock unavailable")};return value
    }
    static func row()->[String:Any] {
        var wheels=[[String:Any]]()
        for front in [true,false] {for left in [true,false] {wheels.append(["centre":[left ? -0.65:0.65,0.0,front ? 1.0:-1.0],"radius":0.36,"front":front,"left":left])}}
        return ["id":900,"solverSupported":true,"kind":"car","origin":0.55,"table":["mass":1100.0,"turnMass":2600.0,"springs":1.1,"damping":0.12,"traction":0.7,"drag":1.8],"wheels":wheels,"chassis":[["kind":"box","centre":[0.0,0,0],"halfExtents":[0.7,0.32,1.3],"friction":0.5]],"bounds":["box":["min":[-0.7,-1.3,-0.32],"max":[0.7,1.3,0.32]]]]
    }
    static func parked(_ wet:Bool)throws->(clock:Double,onWater:Bool,burning:Bool) {
        guard let world=SwiftRapierWorld(gravity:SIMD3(0,-18,0)),let definition=NativeGroundVehicle.Definition(row()),
              let rig=NativeUnattendedVehicle(world:world,definition:definition,pose:.init(position:SIMD3(0,30,0),rotation:.init(angle:0,axis:SIMD3(0,1,0))),health:249,damage:"",waterLevel:{_ in wet ? 1000:nil}) else {throw Failure(text:"real parked car unavailable")}
        defer {rig.dispose()};rig.random={0.37}
        for _ in 0..<60 {
            rig.beforeStep(delta:1.0/60)
            guard let before=rig.state else {throw Failure(text:"real parked body unavailable")}
            let reference=NativeUnattendedVehicle.Pose(position:SIMD3<Double>(before.position),rotation:NativeUnattendedVehicle.quaternion(before.rotation))
            world.step();rig.afterStep(delta:1.0/60,reference:reference)
        }
        try require(rig.damage.health>0 && !rig.damage.wrecked,"parked control became terminal")
        return (try clock(rig.damage),rig.car?.buoyancy?.onWater ?? false,rig.damage.burning)
    }
    static func driven(_ wet:Bool)throws->(clock:Double,onWater:Bool,burning:Bool) {
        guard let ground=NativeGroundVehicle() else {throw Failure(text:"real driven manager unavailable")}
        defer {ground.exit()}
        let data=try JSONSerialization.data(withJSONObject:["models":["900":row()],"materialClasses":[Int](repeating:0,count:256)])
        try require(ground.loadDefinitions(data)==1,"authored driven definition admission")
        var flat=Data();func word(_ value:UInt32){var value=value.littleEndian;withUnsafeBytes(of:&value){flat.append(contentsOf:$0)}}
        [UInt32(0x324c4353),4,2,1].forEach(word)
        for value:Float in [-1000,-1000,-100,1000,-1000,-100,1000,1000,-100,-1000,1000,-100] {word(value.bitPattern)}
        [UInt32(0),1,2,0,2,3].forEach(word);flat.append(contentsOf:[2,2,0,0,1,1,0,0])
        ground.installCell("authored",data:flat);try require(ground.isCellLoaded("authored"),"authored streaming cell admission")
        ground.waterLevel={_ in wet ? 1000:nil}
        try require(ground.enter(model:"900",modelPosition:SIMD3(0,0,30.55),heading:0),"normal driven owner admission")
        guard let damage=ground.damageController?.state else {throw Failure(text:"real driven damage owner unavailable")}
        ground.damageController?.random={0.37};damage.load(health:249,text:"")
        for _ in 0..<60 {ground.update(delta:1.0/60,input:.init(),currentCell:"authored")}
        try require(damage.health>0 && !damage.wrecked,"driven control became terminal")
        return (try clock(damage),ground.onWater,damage.burning)
    }
    static func main() {
        do {
            let kind=CommandLine.arguments[1]
            let dry:(clock:Double,onWater:Bool,burning:Bool),wet:(clock:Double,onWater:Bool,burning:Bool)
            if kind=="parked" {dry=try parked(false);wet=try parked(true)}
            else {try require(kind=="driven","unknown witness case");dry=try driven(false);wet=try driven(true)}
            try require(dry.clock>0 && !dry.onWater && dry.burning,"dry control did not burn")
            try require(wet.onWater,"real force step did not enter submerged automobile state")
            print("OBSERVED \(kind) dryClock=\(dry.clock) wetClock=\(wet.clock) wetOnWater=\(wet.onWater) wetBurning=\(wet.burning)")
            try require(wet.clock==0,"submerged \(kind) automobile kept advancing fire clock")
            try require(!wet.burning,"submerged \(kind) automobile still reports active burning")
            print("PASS \(checks) actual water/fire requirements")
        } catch {print("FAIL \(error)");exit(42)}
    }
}

#if HISTORICAL
@main enum HistoricalWaterWitness {static func main(){WaterFireProbe.main()}}
#else
import Foundation
import simd
import Darwin

@main enum WaterFirePositive {
    typealias P=WaterFireProbe
    static func ground()throws->NativeGroundVehicle {
        guard let value=NativeGroundVehicle() else {throw P.Failure(text:"actual driven manager unavailable")}
        let data=try JSONSerialization.data(withJSONObject:["models":["900":P.row()],"materialClasses":[Int](repeating:0,count:256)])
        try P.require(value.loadDefinitions(data)==1,"authored car admission")
        var flat=Data();func word(_ n:UInt32){var n=n.littleEndian;withUnsafeBytes(of:&n){flat.append(contentsOf:$0)}}
        [UInt32(0x324c4353),4,2,1].forEach(word)
        for n:Float in [-1000,-1000,-100,1000,-1000,-100,1000,1000,-100,-1000,1000,-100] {word(n.bitPattern)}
        [UInt32(0),1,2,0,2,3].forEach(word);flat.append(contentsOf:[2,2,0,0,1,1,0,0])
        value.installCell("authored",data:flat);try P.require(value.isCellLoaded("authored"),"actual authored streaming cell")
        return value
    }
    static func cadence()throws {
        for hz in [15,30,60,120] {
            let value=try ground();defer{value.exit()};var wet=false
            value.waterLevel={_ in wet ? 1000:nil}
            try P.require(value.enter(model:"900",modelPosition:SIMD3(0,0,30.55),heading:0),"normal driven owner")
            guard let damage=value.damageController?.state else {throw P.Failure(text:"actual driven damage state")}
            damage.load(health:249,text:"");value.damageController?.random={0.37};var blows=0
            value.onDamageEvents={events,_ in blows += events.filter{$0.type=="blow"}.count}
            func run(_ frames:Int) {for _ in 0..<frames {value.update(delta:1/Double(hz),input:.init(),currentCell:"authored")}}
            run(hz);try P.require(try P.clock(damage)==960 && damage.burning,"dry fixed-step phase at \(hz)Hz")
            wet=true;run(hz*6)
            try P.require(value.onWater && damage.drowning,"real driven force state did not reach shared damage owner")
            try P.require(try P.clock(damage)==0 && !damage.burning && !damage.wrecked && blows==0,"wet driven timer/terminal state diverged at \(hz)Hz")
            damage.observeAppearance("0000000000010000000");damage.observeHealth(230)
            try P.require(damage.drowning && !damage.burning && (try P.clock(damage))==0,"network condition update discarded physical drowning")
            damage.load(health:1000,text:"");run(hz)
            try P.require(damage.drowning && !damage.burning && (try P.clock(damage))==0,"repair changed physical water state")
            damage.observeHealth(249);run(hz)
            try P.require(damage.drowning && !damage.burning && (try P.clock(damage))==0 && blows==0,"damaging repaired submerged owner restarted fire")
            wet=false;run(hz)
            try P.require(!value.onWater && !damage.drowning && damage.burning && (try P.clock(damage))==960,"emerging owner did not start a fresh fixed-step burn phase at \(hz)Hz")
        }
    }
    static func classification()throws {
        let parameters=NativeVehicleBuoyancy.Parameters(["moveRes":[1.0,1.0,1.0],"turnRes":[1.0,1.0,1.0]])!
        for (model,boat) in [(900,false),(446,true),(460,true)] {
            let table=NativeVehicleDynamics.Table(model:model,values:["mass":1100.0,"turnMass":2600.0])
            let buoyancy=NativeVehicleBuoyancy(table:table,minimum:SIMD3(-0.7,-1.3,-0.32),maximum:SIMD3(0.7,1.3,0.32),parameters:boat ? parameters:nil)!
            buoyancy.waterLevel={_ in 1000}
            let body=NativeVehicleForces(move:.zero,turn:.zero,right:SIMD3(1,0,0),forward:SIMD3(0,0,-1),up:SIMD3(0,1,0),middle:.zero,place:.zero,quaternion:.init(angle:0,axis:SIMD3(0,1,0)),mass:1100,turnMass:2600,wheels:0)
            buoyancy.step(body,input:.init(),step:50.0/60,wheels:0)
            try P.require(buoyancy.onWater,"actual authored buoyancy did not observe water")
            try P.require(buoyancy.drowning == !boat,"boat/seaplane floating flag was interpreted as automobile drowning")
        }
    }
    static func main() {
        do {
            for kind in ["parked","driven"] {
                let dry:(clock:Double,onWater:Bool,burning:Bool),wet:(clock:Double,onWater:Bool,burning:Bool)
                if kind=="parked" {dry=try P.parked(false);wet=try P.parked(true)}
                else {dry=try P.driven(false);wet=try P.driven(true)}
                try P.require(!dry.onWater && dry.burning && dry.clock>0,"dry real \(kind) control")
                try P.require(wet.onWater && !wet.burning && wet.clock==0,"wet real \(kind) owner")
            }
            try cadence();try classification()
            print("PASS \(P.checks) authored actual water/fire checks. Real parked/driven physics and force classification; no engine-fire rendering, full vehicle-family, browser or retail timing claim.")
        } catch {print("FAIL \(error)");exit(42)}
    }
}

#endif
