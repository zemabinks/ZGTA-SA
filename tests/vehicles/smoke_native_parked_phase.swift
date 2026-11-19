// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
import Darwin

@main enum ParkedPhaseGate {
    struct Failure:Error {var message:String}
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws {checks+=1;if !value{throw Failure(message:message)}}
    static func near(_ a:Double,_ b:Double,_ message:String)throws {try check(a.isFinite && b.isFinite && abs(a-b)<1e-9,message)}
    static func definition(_ id:Int)throws->NativeGroundVehicle.Definition {
        var wheels:[[String:Any]]=[]
        for front in [true,false] {for left in [true,false] {
            wheels.append(["centre":[left ? -0.65:0.65,0.0,front ? 1.0:-1.0],"radius":0.36,"front":front,"left":left])
        }}
        let row:[String:Any]=["id":id,"solverSupported":true,"kind":"car","origin":0.55,
            "table":["mass":1100.0,"turnMass":2600.0,"springs":1.1,"damping":0.12,"traction":0.7,"drag":1.8],
            "wheels":wheels,"chassis":[["kind":"box","centre":[0.0,0,0],"halfExtents":[0.7,0.32,1.3],"friction":0.5]],
            "bounds":["box":["min":[-0.7,-1.3,-0.32],"max":[0.7,1.3,0.32]]]]
        guard let value=NativeGroundVehicle.Definition(row)else{throw Failure(message:"authored definition")}
        return value
    }
    static func run()throws {
        let historical=CommandLine.arguments.contains("historical")
        let d=try definition(900),replacement=try definition(901)
        guard let world=SwiftRapierWorld(gravity:SIMD3(0,-18,0))else{throw Failure(message:"actual Rapier world")}
        guard let floor=world.addBox(halfExtents:SIMD3(100,0.1,100),position:SIMD3(0,-0.1,0),friction:0.8)else{throw Failure(message:"authored floor")}
        world.setColliderGroups(floor,collision:131071,solver:0xffffffff);world.step()
        let pool=NativeOtherVehicles(world:world);pool.load(["900":d,"901":replacement]);pool.random={0.37}
        let source=NativeOtherVehicles.Pose(id:"authored-car",code:"900",position:SIMD3(0,0,0.55),heading:0,pitch:0,roll:0)
        pool.park(source,physicalPose:.init(position:SIMD3(0,0.55,0),rotation:.init(angle:0,axis:SIMD3(0,1,0))),linear:SIMD3(0,0,7))
        try check(pool.snapshot(source.id)?.dynamic==true,"parked solver created")
        for frame in 0..<90 {
            pool.synchronize([source],excluding:nil,near:.zero,delta:1/60,now:Double(frame)*1000/60)
            pool.beforeStep(delta:1/60);world.step();pool.afterStep(delta:1/60)
        }
        guard let moving=pool.snapshot(source.id)else{throw Failure(message:"moving snapshot")}
        try check(moving.dynamic && abs(moving.frontSpin)+abs(moving.rearSpin)>0.1,"real solver did not roll authored wheels")
        var occupied=NativeOtherVehicles.Pose(id:source.id,code:source.code,position:moving.position,heading:moving.heading,pitch:moving.pitch,roll:moving.roll)
        occupied.occupied=true
        pool.synchronize([occupied],excluding:nil,near:moving.position,delta:0,now:2000)
        let parked=pool.snapshot(source.id)!
        try check(!parked.dynamic,"occupied demotion")
        try near(parked.frontSpin,moving.frontSpin,"demotion lost wheel phase")
        try near(parked.rearSpin,moving.rearSpin,"demotion lost rear wheel phase")
        try check(!historical,"historical unexpectedly retained phase")
        for cycle in 0..<12 {
            occupied.occupied=false
            pool.synchronize([occupied],excluding:nil,near:occupied.position,promoteNear:occupied.position,delta:0,now:2100+Double(cycle)*10)
            let promoted=pool.snapshot(source.id)!
            try check(promoted.dynamic,"re-promotion did not create solver")
            try near(promoted.frontSpin,moving.frontSpin,"promotion lost front phase")
            try near(promoted.rearSpin,moving.rearSpin,"promotion lost rear phase")
            try check(simd_distance(promoted.physicalPose.position,parked.physicalPose.position)<1e-5,"phase restore displaced chassis")
            occupied.occupied=true
            pool.synchronize([occupied],excluding:nil,near:occupied.position,delta:0,now:2105+Double(cycle)*10)
            let held=pool.snapshot(source.id)!
            try near(held.frontSpin,moving.frontSpin,"repeated demotion lost phase")
            try near(held.rearSpin,moving.rearSpin,"repeated demotion lost rear phase")
        }
        var changed=occupied;changed=NativeOtherVehicles.Pose(id:source.id,code:"901",position:occupied.position,heading:0,pitch:0,roll:0)
        pool.synchronize([changed],excluding:nil,near:changed.position,delta:0,now:2500)
        try near(pool.snapshot(source.id)!.frontSpin,0,"new model inherited old front phase")
        try near(pool.snapshot(source.id)!.rearSpin,0,"new model inherited old rear phase")
        pool.synchronize([],excluding:nil,near:.zero,delta:0,now:2510)
        try check(pool.snapshot(source.id)==nil,"despawn retained presentation owner")
        pool.synchronize([source],excluding:nil,near:.zero,delta:0,now:2520)
        try near(pool.snapshot(source.id)!.frontSpin,0,"recreated id inherited front phase")
        pool.clear()
        let rig=NativeUnattendedVehicle(world:world,definition:d,pose:.init(position:SIMD3(5,1,5),rotation:.init(angle:0.4,axis:SIMD3(0,1,0))),linear:SIMD3(1,2,3),angular:SIMD3(0.1,0.2,0.3),health:1000,damage:"")!
        let before=rig.state!,colliders=rig.colliders
        rig.restoreWheelSpin(front:7.25,rear:-2.5)
        try near(rig.frontSpin,7.25,"direct front phase restore");try near(rig.rearSpin,-2.5,"direct rear phase restore")
        let after=rig.state!
        try check(before.position==after.position && before.rotation.vector==after.rotation.vector,"visual restore changed physical pose")
        try check(before.linearVelocity==after.linearVelocity && before.angularVelocity==after.angularVelocity,"visual restore changed momentum")
        try check(rig.colliders==colliders,"visual restore recreated collision geometry")
        rig.restoreWheelSpin(front:.nan,rear:.infinity)
        try near(rig.frontSpin,0,"invalid front phase accepted");try near(rig.rearSpin,0,"invalid rear phase accepted")
        rig.dispose()
    }
    static func main(){do{try run();print("PASS \(checks) actual Rapier parked-phase handoff checks; no retail/rendered claim")}catch{print("FAIL \(checks) \(error)");exit(2)}}
}
