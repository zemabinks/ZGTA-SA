import Foundation
import simd

/// Native integration invariants, independent of retail tuning and JS goldens.
@main enum VehicleLifecycleSmoke {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let data=try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/vehicles.physics.json"))
        var floor=Data()
        func word(_ value:UInt32){var little=value.littleEndian;withUnsafeBytes(of:&little){floor.append(contentsOf:$0)}}
        [UInt32(0x324c4353),4,2,1].forEach(word)
        for value:Float in [-1000,-1000,0,1000,-1000,0,1000,1000,0,-1000,1000,0]{word(value.bitPattern)}
        [UInt32(0),1,2,0,2,3].forEach(word);floor.append(contentsOf:[2,2,0,0,1,1,0,0])
        var failures:[String]=[],checks=0
        func check(_ value:Bool,_ label:String){checks+=1;if !value{failures.append(label);print("FAIL",label)}}
        func manager()->NativeGroundVehicle {
            let value=NativeGroundVehicle()!;precondition(value.loadDefinitions(data)==212)
            value.installCell("floor",data:floor);return value
        }
        // Taking local ownership must remove even an already promoted body.
        do {
            let fleet=manager(),source=NativeOtherVehicles.Pose(id:"own",code:"420",position:SIMD3(3,0,1),heading:0,pitch:0,roll:0)
            fleet.synchronizeOtherVehicles([source],excluding:nil,near:.zero,promoteNear:source.position,delta:1/60)
            let old=fleet.otherColliders
            precondition(fleet.otherVehicle(source.id)?.dynamic==true && !old.isEmpty)
            fleet.synchronizeOtherVehicles([source],excluding:source.id,near:.zero,promoteNear:source.position,delta:1/60)
            check(fleet.otherVehicle(source.id)==nil,"excluded promoted vehicle survived ownership handoff")
            check(fleet.otherColliders.isEmpty,"excluded vehicle retained ghost colliders")
            check(old.allSatisfy{fleet.world.colliderInfo($0)==nil},"excluded vehicle body was not removed from native world")
        }
        // An externally held/AI-owned vehicle must stop local parked prediction.
        for authority in ["kept","foreignAI"] {
            let fleet=manager(),source=NativeOtherVehicles.Pose(id:authority,code:"420",position:SIMD3(3,0,1),heading:0,pitch:0,roll:0)
            fleet.synchronizeOtherVehicles([source],excluding:nil,near:.zero,promoteNear:source.position,delta:1/60)
            var target=NativeOtherVehicles.Pose(id:source.id,code:source.code,position:SIMD3(30,40,2),heading:0.5,pitch:0,roll:0)
            target.kept=authority=="kept";target.foreignAI=authority=="foreignAI"
            fleet.synchronizeOtherVehicles([target],excluding:nil,near:.zero,promoteNear:target.position,delta:1/60)
            check(fleet.otherVehicle(source.id)?.dynamic==false,authority+" failed to revoke parked physics ownership")
            check(simd_distance(fleet.otherVehicle(source.id)!.position,target.position)<1e-5,authority+" discarded authoritative pose")
        }
        // Browser hear([], true) retains a promoted body, but an explicit
        // gone(id) or disposed world removes it. Do not conflate those events.
        for model in ["420","522","481","430","519","487","435"] {
            let fleet=manager(),source=NativeOtherVehicles.Pose(id:"departed",code:model,position:SIMD3(3,0,2),heading:0,pitch:0,roll:0)
            var packets=0;fleet.onOtherMove={_,_ in packets += 1}
            fleet.synchronizeOtherVehicles([source],excluding:nil,near:.zero,promoteNear:source.position,delta:1/60)
            let old=fleet.otherColliders
            precondition(fleet.otherVehicle(source.id)?.dynamic==true && !old.isEmpty)
            let body=old.first.flatMap{fleet.world.colliderInfo($0)?.body}!
            fleet.world.setVelocities(body,linear:SIMD3(3,0,0),angular:SIMD3(0,0.5,0))
            fleet.synchronizeOtherVehicles([],excluding:nil,near:.zero,delta:1/60)
            check(fleet.otherVehicle(source.id)?.dynamic==true,model+" ordinary omission incorrectly revoked local prediction")
            fleet.shoveOtherVehicle(body:body,direction:SIMD2(1,0),point:SIMD3(3,2,0),speed:4)
            check(fleet.removeOtherVehicle(id:source.id),model+" explicit disappearance was ignored")
            check(!fleet.removeOtherVehicle(id:source.id),model+" disappearance was not idempotent")
            check(fleet.otherVehicle(source.id)==nil && fleet.otherColliders.isEmpty,model+" disappeared vehicle retained prediction/colliders")
            check(fleet.world.bodyState(body)==nil && old.allSatisfy{fleet.world.colliderInfo($0)==nil},model+" disappeared vehicle retained native handles")
            let before=packets
            for _ in 0..<4 {fleet.synchronizeOtherVehicles([],excluding:nil,near:.zero,delta:1/60);fleet.world.step()}
            check(packets==before,model+" queued shove/step emitted a packet after disappearance")
            fleet.synchronizeOtherVehicles([source],excluding:nil,near:.zero,promoteNear:source.position,delta:1/60)
            check(fleet.otherVehicle(source.id)?.dynamic==true,model+" same-id replacement failed to initialize")
            check(old.isDisjoint(with:fleet.otherColliders),model+" replacement reused stale native handles")
            fleet.clearOtherVehicles()
            check(fleet.otherVehicle(source.id)==nil && fleet.otherColliders.isEmpty,model+" session/world teardown retained parked body")
            let afterClear=packets
            for _ in 0..<4 {fleet.synchronizeOtherVehicles([],excluding:nil,near:.zero,delta:1/60);fleet.world.step()}
            check(packets==afterClear,model+" cleared world emitted old movement")
        }
        do {
            let fleet=manager();precondition(fleet.enter(model:"420",modelPosition:SIMD3(0,0,2),heading:0))
            let owned=fleet.chassisColliders
            check(!fleet.removeOtherVehicle(id:"owned"),"Explicit parked removal touched a missing/owned entry")
            fleet.clearOtherVehicles()
            check(fleet.active && owned==fleet.chassisColliders && owned.allSatisfy{fleet.world.colliderInfo($0) != nil},"Parked teardown removed active owned chassis")
        }
        // Invalid requested entry must leave the existing body/damage intact.
        do {
            let car=manager();precondition(car.enter(model:"420",modelPosition:SIMD3(0,0,8),heading:0))
            let old=car.chassisColliders,position=car.modelPosition,damage=car.damageController
            let invalid=[
                car.enter(model:"420",modelPosition:SIMD3(.nan,0,0),heading:0),
                car.enter(model:"420",modelPosition:.zero,heading:.infinity),
                car.enter(model:"420",modelPosition:.zero,heading:0,bodyPose:.init(position:.zero,rotation:simd_quatd(ix:0,iy:0,iz:0,r:0)))
            ]
            check(invalid.allSatisfy{!$0},"nonfinite or zero-quaternion vehicle entry was accepted")
            check(car.active && car.model=="420" && car.modelPosition==position,"invalid entry discarded current vehicle")
            check(car.damageController === damage,"invalid entry replaced damage owner")
            check(old.allSatisfy{car.world.colliderInfo($0) != nil},"invalid entry destroyed current chassis")
        }
        // A zero-health authority snapshot disables all propulsion/control
        // channels, including aircraft lift, while the existing hull coasts.
        for model in ["420","522","519","487"] {
            let driven=manager(),coasting=manager()
            let spawnHeight:Float=model=="420" || model=="522" ? 1.1:100
            for car in [driven,coasting]{precondition(car.enter(model:model,modelPosition:SIMD3(0,0,spawnHeight),heading:0))}
            var warm=NativeVehicleDynamics.Input();warm.throttle=0.7
            for _ in 0..<80 {for car in [driven,coasting]{car.update(delta:1/60,input:warm,currentCell:"floor")}}
            let rotor=driven.rotorTurning
            for car in [driven,coasting]{car.damageController!.state.load(health:0,text:"")}
            var held=NativeVehicleDynamics.Input();held.throttle=1;held.steer=1;held.pitch=1;held.roll=1;held.yaw=1;held.jets=1
            var released=NativeVehicleDynamics.Input();released.nobody=true;released.handbrake=true
            for _ in 0..<30 {driven.update(delta:1/60,input:held,currentCell:"floor");coasting.update(delta:1/60,input:released,currentCell:"floor")}
            check(simd_distance(driven.modelPosition,coasting.modelPosition)<1e-5,model+" zero-health propulsion/control remained active")
            check(simd_length(driven.orientation.vector-coasting.orientation.vector)<1e-5,model+" zero-health angular control remained active")
            if model=="487" {check(driven.rotorTurning<rotor,"zero-health helicopter rotor kept running")}
        }
        precondition(failures.isEmpty,"Vehicle lifecycle regressions: \(failures.joined(separator:", "))")
        print("PASS: \(checks) native vehicle lifecycle checks: promoted exclusion, explicit disappearance/world teardown, replacement, external authority, invalid entry preservation, zero-health coasting")
    }
}
