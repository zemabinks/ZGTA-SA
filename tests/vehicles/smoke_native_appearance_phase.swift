// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
import Darwin

// The carrier compiles the unchanged authored Core196 helper fixture with its
// entrypoint attribute removed. Production source files are never rewritten.
@main enum AppearancePhaseProbe {
    typealias H=ParkedHealthProbe
    static func witness(_ kind:String)throws {
        guard let world=SwiftRapierWorld(gravity:.zero)else{throw H.Failure(text:"actual Rapier world")}
        let pool=NativeOtherVehicles(world:world);pool.load(["900":try H.definition()]);pool.random={0.37};defer{pool.clear()}
        var value=H.source("appearance-phase",kind=="upside" ? 1000:249),parts=[Character](repeating:"0",count:19);parts[2]="3";parts[17]="1";value.damage=String(parts)
        let actual=try H.park(pool,value);actual.damage.letGo(2,angle:0.31)
        for _ in 0..<120 {var body=H.frame;if kind=="upside"{body.up=SIMD3(0,-1,0)};actual.damage.process(body:body,ticks:50.0/60,random:{0.37})}
        if kind=="impact"{actual.damage.record(intensity:400,piece:3,point:SIMD3(0,2,0),normal:SIMD3(1,0,0),building:false)}
        let beforeFire=try H.clock(actual.damage),door=actual.damage.doors[2],impact=actual.damage.intensity,upside=H.field(actual.damage,"upsideTicks")as?Double
        try H.require(actual.damage.isOpen(2) && actual.damage.wheels[2]==1,"authored logical state did not initialize")
        parts[11]="1";value.damage=String(parts);H.observe(pool,value)
        try H.require(actual.damage.health==Double(value.health) && actual.damage.lights[0]==1 && actual.damage.isOpen(2) && actual.damage.wheels[2]==1,"full authoritative appearance state was not admitted")
        switch kind {
        case "fire":try H.require(try H.clock(actual.damage)==beforeFire && beforeFire>0,"appearance replacement restarted continuous burn phase")
        case "door":try H.require(actual.damage.doors[2].angle==door.angle && actual.damage.doors[2].previousAngle==door.previousAngle && actual.damage.doors[2].angularVelocity==door.angularVelocity,"unchanged authoritative open door lost physical motion")
        case "impact":try H.require(actual.damage.intensity==impact && impact>0,"appearance replacement discarded pending physical impact")
        case "upside":try H.require(H.field(actual.damage,"upsideTicks")as?Double==upside && (upside ?? 0)>0,"appearance replacement restarted continuous inverted-body phase")
        default:throw H.Failure(text:"unknown appearance phase witness")
        }
    }
    #if !HISTORICAL
    static func logicalSnapshots()throws {
        // Retain the accepted initializer as a logical-state oracle. These are
        // authored wire strings and profiles, not original game resources.
        let profiles:[(Int,Int)]=[(0,900),(1,482),(2,431),(16,900),(32,900),(64,900),(128,900),(256,424),(256,425),(0,519),(0,553),(0,520)]
        let mixed=[3,0,4,1,2,0,0,1,2,0,1,1,0,1,0,1,2,0,1].map(String.init).joined()
        let texts=(0...4).map{String(repeating:String($0),count:19)}+[mixed,"bad",""]
        for (flags,model) in profiles {for text in texts {
            let actual=NativeVehicleDamage(mass:1400,flags:flags,model:model),reference=NativeVehicleDamage(mass:1400,flags:flags,model:model)
            var parts=[Character](repeating:"0",count:19);parts[2]="3";parts[17]="1"
            actual.load(health:249,text:String(parts));actual.events.removeAll();actual.letGo(2,angle:0.31);H.tick(actual,120)
            actual.record(intensity:400,piece:3,point:SIMD3(0,2,0),normal:SIMD3(1,0,0),building:false)
            actual.godly=true;actual.events.append(.init(type:"authored-existing-event"))
            let before=try H.clock(actual),events=actual.events.map(\.type)
            reference.load(health:249,text:text);actual.observeAppearance(text)
            try H.require(actual.looks==reference.looks && actual.lights==reference.lights && actual.wheels==reference.wheels,"appearance observation differs from retained logical initializer")
            try H.require((0..<11).map{actual.isOpen($0)}==(0..<11).map{reference.isOpen($0)} && actual.text()==reference.text(),"appearance observation changed full snapshot open/serialization semantics")
            try H.require(actual.health==249 && actual.godly && !actual.wrecked,"appearance observation reset independent health/protection/lifetime")
            try H.require(try H.clock(actual)==before && before>0,"full snapshot projection reset active fire phase")
            try H.require(actual.intensity==400 && actual.events.map(\.type)==events,"authoritative appearance discarded or synthesized physical work")
            // Subsequent real damage must start from the admitted panel state.
            actual.godly=false
            for piece in [9,5,19] {for damage in [actual,reference] {
                damage.record(intensity:600,piece:piece,point:SIMD3(0,2,0),normal:SIMD3(1,0,0),building:false)
                damage.process(body:H.frame,ticks:50.0/60,random:{0})
            }}
            try H.require(actual.text()==reference.text() && actual.health==reference.health,"observed logical parts diverged on subsequent real damage")
            actual.load(health:1000,text:"")
            try H.require(try H.clock(actual)==0 && actual.intensity==0 && actual.health==1000 && actual.wheels.allSatisfy{$0==0} && actual.looks.allSatisfy{$0==0},"initialization/repair load stopped resetting a new lifetime")
        }}
        // A changed authoritative closed door must still close; retaining its
        // prior open angle would keep an invalid physical state alive.
        let door=NativeVehicleDamage(mass:1400);door.load(health:249,text:"");door.letGo(2,angle:0.31);door.observeAppearance(String(repeating:"0",count:19))
        try H.require(!door.isOpen(2) && door.doors[2].angle==0 && door.doors[2].previousAngle==0,"changed authoritative closed door retained prior hinge motion")
    }
    #endif
    static func main(){do {
        if CommandLine.arguments.count==2 {try witness(CommandLine.arguments[1])}
        else {
            for name in ["fire","door","impact","upside"]{try witness(name)}
            #if !HISTORICAL
            try logicalSnapshots()
            #endif
        }
        print("PASS \(H.checks) actual appearance/continuous-state checks with authored full snapshots and retained initializer semantics; read-only introspection, no App/contact/retail timing or traffic collision response claim")
    }catch{print("FAIL \(error)");exit(42)}}
}
