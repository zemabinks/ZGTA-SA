// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
import Darwin

@main enum ParkedConditionProbe {
    struct Failure:Error {let text:String}
    static var checks=0
    static func require(_ value:Bool,_ text:String)throws{checks+=1;if !value{throw Failure(text:text)}}
    static func field(_ owner:Any,_ name:String)->Any? {Mirror(reflecting:owner).children.first{$0.label==name}?.value}
    // Test-only introspection reaches the actual parked owner's existing damage
    // component. Inflict/burst/letGo remain its normal operations. No production
    // source is rewritten to expose internals; no physical contact is claimed.
    static func rig(_ pool:NativeOtherVehicles,_ id:String)throws->NativeUnattendedVehicle {
        guard let entries=field(pool,"entries")as?[String:Any],let entry=entries[id],let optional=field(entry,"rig"),let rig=Mirror(reflecting:optional).children.first?.value as?NativeUnattendedVehicle else{throw Failure(text:"actual parked damage owner unavailable")}
        return rig
    }
    static func definition(_ kind:String="car")throws->NativeGroundVehicle.Definition {
        var wheels:[[String:Any]]=[]
        for front in [true,false]{for left in [true,false]{wheels.append(["centre":[left ? -0.65:0.65,0.0,front ? 1.0:-1.0],"radius":0.36,"front":front,"left":left])}}
        var row:[String:Any]=["id":900,"solverSupported":true,"kind":kind,"origin":0.55,"table":["mass":1100.0,"turnMass":2600.0,"springs":1.1,"damping":0.12,"traction":0.7,"drag":1.8],"wheels":wheels,"chassis":[["kind":"box","centre":[0.0,0,0],"halfExtents":[0.7,0.32,1.3],"friction":0.5]],"bounds":["box":["min":[-0.7,-1.3,-0.32],"max":[0.7,1.3,0.32]]]]
        if kind=="bike"{let hubs:[String:[String:Any]]=["front":["at":[0.0,1,0],"radius":0.36],"rear":["at":[0.0,-1,0],"radius":0.36]];row["hubs"]=hubs;row["bike"]=["fullAnimLean":0.4,"maxLean":0.4,"desLean":0.9,"speedSteer":1.0]}
        guard let result=NativeGroundVehicle.Definition(row)else{throw Failure(text:"authored car definition")};return result
    }
    static func run()throws {
        let d=try definition()
        if !CommandLine.arguments.contains("tyres-only") {
        if !CommandLine.arguments.contains("fire-only") {for (index,variant) in ["position","heading","pitch","roll","work"].enumerated() {
            guard let world=SwiftRapierWorld(gravity:.zero)else{throw Failure(text:"actual Rapier world")}
            let pool=NativeOtherVehicles(world:world);pool.load(["900":d]);pool.random={0.37}
            var source=NativeOtherVehicles.Pose(id:"authored-"+variant,code:"900",position:SIMD3(0,0,2),heading:0,pitch:0,roll:0)
            pool.park(source,physicalPose:.init(position:SIMD3(0,2,0),rotation:.init(angle:0,axis:SIMD3(0,1,0))),linear:SIMD3(0,0,7))
            let body=try rig(pool,source.id);body.damage.inflict(101);_ = body.damage.burst(2);body.damage.letGo(2,angle:0.31)
            pool.afterStep(delta:0)
            let before=pool.snapshot(source.id)!,door=body.damage.doors[2]
            try require(before.health==899 && body.damage.wheels[2]==1 && body.damage.isOpen(2),"authored local damage did not reach actual owner")
            switch variant{case "position":source=NativeOtherVehicles.Pose(id:source.id,code:source.code,position:source.position+SIMD3(0.25,0,0),heading:0,pitch:0,roll:0);case "heading":source=NativeOtherVehicles.Pose(id:source.id,code:source.code,position:source.position,heading:0.1,pitch:0,roll:0);case "pitch":source=NativeOtherVehicles.Pose(id:source.id,code:source.code,position:source.position,heading:0,pitch:0.1,roll:0);case "roll":source=NativeOtherVehicles.Pose(id:source.id,code:source.code,position:source.position,heading:0,pitch:0,roll:0.1);default:source.work=17}
            pool.synchronize([source],excluding:nil,near:source.position,promoteNear:source.position,delta:0,now:100)
            let after=pool.snapshot(source.id)!
            try require(after.health==before.health && after.damage==before.damage,"metadata-only observation healed parked prediction: "+variant)
            try require(body.damage.doors[2].angle==door.angle && body.damage.wheels[2]==1,"metadata-only observation reset door/tyre: "+variant)
            try require(after.work==source.work,"working-part observation was lost")
            try require(simd_distance(after.physicalPose.position,before.physicalPose.position)<1e-9,"metadata observation dragged active physical body")
            // A genuine authoritative condition update remains effective.
            source.health=650;source.damage="0000000000010000000"
            pool.synchronize([source],excluding:nil,near:source.position,promoteNear:source.position,delta:0,now:200)
            try require(pool.snapshot(source.id)?.health==650 && body.damage.health==650,"genuine condition change suppressed")
            try require(body.damage.lights[0]==1 && body.damage.wheels[2]==0,"new condition did not refresh parts")
            // Authoritative occupation is a real ownership handoff even when
            // its reported condition repeats the previous baseline.
            body.damage.inflict(50);pool.afterStep(delta:0)
            if index%3==0{source.occupied=true}else if index%3==1{source.kept=true}else{source.foreignAI=true}
            pool.synchronize([source],excluding:nil,near:source.position,promoteNear:source.position,delta:0,now:300)
            try require(pool.snapshot(source.id)?.dynamic==false && pool.snapshot(source.id)?.health==650,"authority handoff retained local condition")
            source.health=1000;source.damage=""
            pool.synchronize([source],excluding:nil,near:source.position,promoteNear:source.position,delta:0,now:400)
            try require(pool.snapshot(source.id)?.health==1000 && pool.snapshot(source.id)?.damage=="","genuine repair condition was ignored")
            pool.clear()
        }}
        // The production damage owner advances on the60Hz physics grid.
        // Metadata observation cadence must not restart that engine-fire clock.
        for hz in [15,30,60,120] {
            guard let world=SwiftRapierWorld(gravity:.zero)else{throw Failure(text:"world")}
            let pool=NativeOtherVehicles(world:world);pool.load(["900":d]);pool.random={0.37}
            var source=NativeOtherVehicles.Pose(id:"fire",code:"900",position:SIMD3(0,0,2),heading:0,pitch:0,roll:0);source.health=249
            pool.park(source,physicalPose:.init(position:SIMD3(0,2,0),rotation:.init(angle:0,axis:SIMD3(0,1,0))),linear:SIMD3(0,0,7))
            let actual=try rig(pool,source.id)
            let body=NativeVehicleDamage.Body(position:.zero,right:SIMD3(1,0,0),forward:SIMD3(0,0,-1),up:SIMD3(0,1,0),move:.zero,turn:.zero)
            let reference=NativeVehicleDamage(mass:1100);reference.load(health:249,text:"")
            var published=0
            for step in 0..<(60*6) {
                while published<(step+1)*hz/60 {
                    source=NativeOtherVehicles.Pose(id:source.id,code:source.code,position:SIMD3(Float(published%2)*0.001,0,2),heading:0,pitch:0,roll:0);source.health=249
                    pool.synchronize([source],excluding:nil,near:source.position,promoteNear:source.position,delta:0,now:Double(published)*1000/Double(hz));published+=1
                }
                actual.damage.process(body:body,ticks:50.0/60,random:{0.37});reference.process(body:body,ticks:50.0/60,random:{0.37})
            }
            let actualBlows=actual.damage.events.filter{$0.type=="blow"}.count,expectedBlows=reference.events.filter{$0.type=="blow"}.count
            let actualClock=field(actual.damage,"fireTicks")as?Double,expectedClock=field(reference,"fireTicks")as?Double
            try require((expectedClock ?? 0)>5000 && actualClock==expectedClock && expectedBlows>0 && actualBlows==expectedBlows,"pose observations restarted engine-fire clock at "+String(hz)+"Hz")
            pool.clear()
        }
        }
        if !CommandLine.arguments.contains("fire-only") {for kind in ["car","bike"] {for wheel in 0..<(kind=="car" ? 4:2) {
            guard let world=SwiftRapierWorld(gravity:.zero),let actual=NativeUnattendedVehicle(world:world,definition:try definition(kind),pose:.init(position:SIMD3(0,2,0),rotation:.init(angle:0,axis:SIMD3(0,1,0))),health:1000,damage:"")else{throw Failure(text:"actual tyre fixture")}
            _ = actual.damage.burst(wheel);actual.beforeStep(delta:1.0/60)
            guard let output=actual.output else{throw Failure(text:"actual solver output")}
            try require([output.linearVelocity.x,output.linearVelocity.y,output.linearVelocity.z,output.angularVelocity.x,output.angularVelocity.y,output.angularVelocity.z].allSatisfy(\.isFinite),"authored tyre fixture returned nonfinite forces")
            try require(output.wheels.count==4 && output.wheels.allSatisfy{let slot=kind=="car" ? $0.index:($0.index<2 ? 0:1);return $0.tyre==(slot==wheel ? 1:0)},"parked puncture never reached actual solver: "+kind+" wheel "+String(wheel))
            actual.damage.load(health:1000,text:"");actual.beforeStep(delta:1.0/60)
            try require(actual.output?.wheels.allSatisfy{$0.tyre==0}==true,"actual solver did not accept repaired tyres")
            actual.dispose()
        }}}
        print("PASS \(checks) actual parked-owner/damage/tyre-solver checks with authored metadata, condition changes, authority transfers and engine-fire intervals; explicit test-only introspection, no App/contact/retail claim")
    }
    static func main(){do{try run()}catch{print("FAIL \(error)");exit(42)}}
}
