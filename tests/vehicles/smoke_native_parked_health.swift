// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
import Darwin

@main enum ParkedHealthProbe {
    struct Failure:Error {let text:String}
    static var checks=0
    static func require(_ condition:Bool,_ text:String)throws {checks+=1;if !condition{throw Failure(text:text)}}
    static func field(_ owner:Any,_ name:String)->Any? {Mirror(reflecting:owner).children.first{$0.label==name}?.value}
    static func rig(_ pool:NativeOtherVehicles,_ id:String)throws->NativeUnattendedVehicle {
        guard let entries=field(pool,"entries")as?[String:Any],let entry=entries[id],let optional=field(entry,"rig"),let actual=Mirror(reflecting:optional).children.first?.value as?NativeUnattendedVehicle else{throw Failure(text:"actual parked owner unavailable")};return actual
    }
    static func definition()throws->NativeGroundVehicle.Definition {
        var wheels:[[String:Any]]=[]
        for front in [true,false]{for left in [true,false]{wheels.append(["centre":[left ? -0.65:0.65,0.0,front ? 1.0:-1.0],"radius":0.36,"front":front,"left":left])}}
        let row:[String:Any]=["id":900,"solverSupported":true,"kind":"car","origin":0.55,"table":["mass":1100.0,"turnMass":2600.0,"springs":1.1,"damping":0.12,"traction":0.7,"drag":1.8],"wheels":wheels,"chassis":[["kind":"box","centre":[0.0,0,0],"halfExtents":[0.7,0.32,1.3],"friction":0.5]],"bounds":["box":["min":[-0.7,-1.3,-0.32],"max":[0.7,1.3,0.32]]]]
        guard let value=NativeGroundVehicle.Definition(row)else{throw Failure(text:"authored car definition")};return value
    }
    static let frame=NativeVehicleDamage.Body(position:.zero,right:SIMD3(1,0,0),forward:SIMD3(0,0,-1),up:SIMD3(0,1,0),move:.zero,turn:.zero)
    static func tick(_ damage:NativeVehicleDamage,_ count:Int) {for _ in 0..<count{damage.process(body:frame,ticks:50.0/60,random:{0.37})}}
    static func clock(_ damage:NativeVehicleDamage)throws->Double {guard let value=field(damage,"fireTicks")as?Double else{throw Failure(text:"actual fire-clock observation")};return value}
    static func source(_ id:String,_ health:Int)->NativeOtherVehicles.Pose {var value=NativeOtherVehicles.Pose(id:id,code:"900",position:SIMD3(0,0,2),heading:0,pitch:0,roll:0);value.health=health;return value}
    static func park(_ pool:NativeOtherVehicles,_ value:NativeOtherVehicles.Pose)throws->NativeUnattendedVehicle {
        pool.park(value,physicalPose:.init(position:SIMD3(0,2,0),rotation:.init(angle:0,axis:SIMD3(0,1,0))),linear:SIMD3(0,0,7));return try rig(pool,value.id)
    }
    static func observe(_ pool:NativeOtherVehicles,_ value:NativeOtherVehicles.Pose,_ now:Double=2100) {pool.synchronize([value],excluding:nil,near:value.position,promoteNear:value.position,delta:0,now:now)}
    static func witness(_ kind:String)throws {
        guard let world=SwiftRapierWorld(gravity:.zero)else{throw Failure(text:"actual Rapier world")}
        let pool=NativeOtherVehicles(world:world);pool.load(["900":try definition()]);pool.random={0.37};defer{pool.clear()}
        var value=source("condition-"+kind,kind=="appearance-health" ? 1000:249),actual=try park(pool,value)
        if kind=="appearance-health" {
            actual.damage.inflict(101);pool.afterStep(delta:0);value.damage="0000000000010000000";observe(pool,value)
            try require(actual.damage.lights[0]==1,"genuine appearance update was not admitted")
            try require(actual.damage.health==899 && pool.snapshot(value.id)?.health==899,"appearance-only update healed pending health")
            return
        }
        actual.damage.letGo(2,angle:0.31);_ = actual.damage.burst(2);pool.afterStep(delta:0)
        let appearance=pool.snapshot(value.id)!.damage,door=actual.damage.doors[2]
        let reference=NativeVehicleDamage(mass:1100);reference.load(health:249,text:"");tick(actual.damage,120);tick(reference,120);reference.inflict(19)
        value.health=230;observe(pool,value)
        try require(actual.damage.health==230 && pool.snapshot(value.id)?.health==230,"actual health update was not admitted")
        switch kind {
        case "clock":try require(try clock(actual.damage)==clock(reference),"genuine health-only update restarted an already burning owner")
        case "appearance":try require(actual.damage.wheels[2]==1 && pool.snapshot(value.id)?.damage==appearance,"genuine health-only update cleared pending appearance")
        case "door":try require(actual.damage.isOpen(2) && actual.damage.doors[2].angle==door.angle && actual.damage.doors[2].previousAngle==door.previousAngle,"genuine health-only update reset physical door motion")
        default:throw Failure(text:"unknown historical witness")
        }
    }
    static func cadence()throws {
        for hz in [15,30,60,120] {
            guard let world=SwiftRapierWorld(gravity:.zero)else{throw Failure(text:"world")}
            let pool=NativeOtherVehicles(world:world);pool.load(["900":try definition()]);pool.random={0.37};defer{pool.clear()}
            var value=source("cadence-"+String(hz),249);let actual=try park(pool,value),reference=NativeVehicleDamage(mass:1100);reference.load(health:249,text:"")
            _ = actual.damage.burst(2);actual.damage.letGo(2,angle:0.31);pool.afterStep(delta:0)
            var published=0
            for step in 0..<360 {
                while published<(step+1)*hz/60 {value.health=published%2==0 ? 230:249;observe(pool,value,Double(published)*1000/Double(hz));published+=1}
                tick(actual.damage,1);tick(reference,1)
            }
            try require(try clock(actual.damage)==clock(reference),"genuine health cadence changed fire phase at "+String(hz)+"Hz")
            try require(actual.damage.events.filter{$0.type=="blow"}.count==reference.events.filter{$0.type=="blow"}.count && !reference.events.isEmpty,"genuine health cadence changed damage-owner blow events")
            try require(actual.damage.wheels[2]==1 && actual.damage.isOpen(2) && actual.damage.doors[2].angle==0.31,"genuine health cadence reset tyre/door")
            try require(pool.snapshot(value.id)?.health==value.health,"cadence lost authoritative health")
        }
    }
    static func thresholdsAndOwnership()throws {
        guard let world=SwiftRapierWorld(gravity:.zero)else{throw Failure(text:"world")}
        let pool=NativeOtherVehicles(world:world);pool.load(["900":try definition()]);pool.random={0.37};defer{pool.clear()}
        var value=source("threshold",249);let actual=try park(pool,value)
        _ = actual.damage.burst(1);actual.damage.letGo(2,angle:0.31);pool.afterStep(delta:0);tick(actual.damage,120)
        value.health=250;observe(pool,value);tick(actual.damage,1)
        try require(try clock(actual.damage)==0 && !actual.damage.burning,"health recovery did not leave burning branch")
        try require(actual.damage.wheels[1]==1 && actual.damage.isOpen(2),"health recovery reset unrelated condition")
        value.health=249;observe(pool,value);tick(actual.damage,1)
        let reference=NativeVehicleDamage(mass:1100);reference.load(health:249,text:"");tick(reference,1)
        try require(try clock(actual.damage)==clock(reference),"reentering burning inherited stale phase")
        actual.damage.events.append(.init(type:"authored-pending-event"));value.health=230;observe(pool,value)
        try require(actual.damage.events.contains{$0.type=="authored-pending-event"},"health observation dropped pending independent event")
        value.health=1000;observe(pool,value);tick(actual.damage,1)
        try require(try clock(actual.damage)==0 && actual.damage.health==1000 && actual.damage.wheels[1]==1 && actual.damage.isOpen(2),"health-only repair did not preserve unrelated parts")
        value.health=0;observe(pool,value)
        try require(pool.snapshot(value.id)?.health==0 && pool.snapshot(value.id)?.dynamic==false,"terminal health failed to demote owned parked body")
        for flag in ["occupied","kept","foreignAI"] {
            var handoff=source("handoff-"+flag,249);let owner=try park(pool,handoff);_ = owner.damage.burst(2);owner.damage.letGo(2,angle:0.31);pool.afterStep(delta:0)
            handoff.health=230;observe(pool,handoff);if flag=="occupied"{handoff.occupied=true}else if flag=="kept"{handoff.kept=true}else{handoff.foreignAI=true};observe(pool,handoff,2200)
            try require(pool.snapshot(handoff.id)?.dynamic==false && pool.snapshot(handoff.id)?.health==230 && pool.snapshot(handoff.id)?.damage=="","authority handoff retained pending local condition: "+flag)
        }
        var repair=source("full-repair",249);let repaired=try park(pool,repair);_ = repaired.damage.burst(2);repaired.damage.letGo(2,angle:0.31);pool.afterStep(delta:0);repair.health=1000;repair.damage=String(repeating:"0",count:19);observe(pool,repair)
        try require(repaired.damage.health==1000 && repaired.damage.wheels.allSatisfy{$0==0} && !repaired.damage.isOpen(2),"genuine full repair stopped refreshing condition")
        // A new registry lifetime is initialized rather than reconciled with
        // a removed owner's fire clock, physical doors or pending puncture.
        var fresh=source("fresh-lifetime",249);let first=try park(pool,fresh);tick(first.damage,120);pool.remove(fresh.id);fresh.health=230;let second=try park(pool,fresh)
        try require(try clock(second.damage)==0 && second.damage.wheels.allSatisfy{$0==0} && !second.damage.isOpen(2),"new vehicle lifetime inherited condition")
    }
    static func main(){do {
        if CommandLine.arguments.count==2{try witness(CommandLine.arguments[1])}
        else{for name in ["clock","appearance","door","appearance-health"]{try witness(name)};try cadence();try thresholdsAndOwnership()}
        print("PASS \(checks) actual parked health/appearance ownership checks; fixed60Hz damage with15/30/60/120Hz observations. Authored data and read-only introspection; no App, contact, parked explosion delivery or retail claim.")
    }catch{print("FAIL \(error)");exit(42)}}
}
