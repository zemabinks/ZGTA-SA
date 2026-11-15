import Foundation
import simd

/// Native integration regressions, independent of the archived JS golden
/// measurements. These assert transition/cadence invariants, not retail parity.
@main enum CorePhysicsTransitions {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let definitions=try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/vehicles.physics.json"))
        var flat=Data()
        func word(_ value:UInt32){var little=value.littleEndian;withUnsafeBytes(of:&little){flat.append(contentsOf:$0)}}
        [UInt32(0x324c4353),4,2,1].forEach(word)
        for value:Float in [-1000,-1000,0,1000,-1000,0,1000,1000,0,-1000,1000,0]{word(value.bitPattern)}
        [UInt32(0),1,2,0,2,3].forEach(word);flat.append(contentsOf:[2,2,0,0,1,1,0,0])
        func manager()->NativeGroundVehicle {
            let result=NativeGroundVehicle()!;precondition(result.loadDefinitions(definitions)==212)
            result.installCell("floor",data:flat);precondition(result.isCellLoaded("floor"));return result
        }
        // An attachment/climb may replace this fixed step's feet location.
        // An enabled walker must never remain at its previous world location.
        do {
            let world=SwiftRapierWorld(gravity:.zero)!,controller=NativeCharacterController(world:world)!
            controller.reset(feet:.zero)
            let feet=SIMD3<Float>(12,-7,4)
            let output=controller.update(delta:1/60,displacement:.zero,geometryReady:true){_,_,input in
                var result=input;result.heldFeet=feet;return result
            }
            let collider=world.colliderInfo(controller.queries.walker)!
            precondition(simd_distance(output.feet,feet)<1e-5)
            precondition(simd_distance(collider.translation,SwiftRapierWorld.gtaToRapier(feet)+SIMD3(0,0.9,0))<1e-5)
            controller.reset(feet:SIMD3(100,200,50),active:false)
            let stopped=controller.update(delta:1,displacement:SIMD3(5,0,0),geometryReady:true)
            precondition(stopped.feet==SIMD3(100,200,50))
        }
        // Identical constant controls must give the same 300 physics steps
        // at common and non-dividing display rates, including uneven frames.
        var input=NativeVehicleDynamics.Input();input.throttle=1;input.steer=0.2
        func simulate(_ frames:[Double])->(SIMD3<Float>,Float,simd_quatf) {
            let car=manager();precondition(car.enter(model:"420",modelPosition:SIMD3(0,0,1.1),heading:0))
            for delta in frames{car.update(delta:delta,input:input,currentCell:"floor")}
            return(car.modelPosition,car.speed,car.orientation)
        }
        let reference=simulate(Array(repeating:1/60,count:300))
        var cadences=[[Double]]()
        for hz in [30,60,90,120,144]{cadences.append(Array(repeating:1/Double(hz),count:hz*5))}
        cadences.append((0..<100).flatMap{_ in [0.011,0.019,0.020]})
        for frames in cadences {
            let result=simulate(frames)
            precondition(simd_distance(reference.0,result.0)<1e-5 && abs(reference.1-result.1)<1e-5)
            precondition(simd_length(reference.2.vector-result.2.vector)<1e-5)
        }
        // A remote driver taking an already promoted parked body must replace
        // its target even if the first occupied packet is its final packet.
        do {
            let fleet=manager(),source=NativeOtherVehicles.Pose(id:"handoff",code:"420.6.1.0.",position:SIMD3(3,0,1.1),heading:0,pitch:0,roll:0)
            fleet.synchronizeOtherVehicles([source],excluding:nil,near:.zero,promoteNear:source.position,delta:1/60)
            precondition(fleet.otherVehicle(source.id)?.dynamic==true)
            var occupied=NativeOtherVehicles.Pose(id:source.id,code:source.code,position:SIMD3(30,40,2),heading:0.5,pitch:0,roll:0)
            occupied.occupied=true
            fleet.synchronizeOtherVehicles([occupied],excluding:nil,near:.zero,delta:1/60)
            precondition(fleet.otherVehicle(source.id)?.dynamic==false)
            precondition(simd_distance(fleet.otherVehicle(source.id)!.position,occupied.position)<1e-5,"Occupied handoff discarded authoritative target")
            fleet.synchronizeOtherVehicles([occupied],excluding:nil,near:.zero,delta:1/60)
            precondition(simd_distance(fleet.otherVehicle(source.id)!.position,occupied.position)<1e-5)
        }
        // A teleport is a new physical solver with the same damage owner.
        // Compare it to a cold vehicle at the destination, after warming its
        // previous suspension/gear/steering state at a distant location.
        for model in ["420","522","481","452","519","487"] {
            let warm=manager(),cold=manager(),destination=SIMD3<Float>(40,60,12)
            precondition(warm.enter(model:model,modelPosition:SIMD3(0,0,1.1),heading:0))
            for _ in 0..<120{warm.update(delta:1/60,input:input,currentCell:"floor")}
            let damage=warm.damageController!;damage.state.load(health:777,text:"");damage.hinges=[2:SIMD3(1,2,3)]
            warm.update(delta:1/120,input:input,currentCell:"floor")
            warm.teleport(modelPosition:destination,heading:0.7)
            precondition(warm.damageController === damage && warm.damageController?.state.health==777)
            precondition(warm.damageController?.hinges[2]==SIMD3(1,2,3))
            precondition(warm.output==nil && warm.forwardSpeed==0 && warm.rotorTurning==0 && !warm.landingGearUp)
            precondition(cold.enter(model:model,modelPosition:destination,heading:0.7))
            let initial=warm.modelPosition
            warm.update(delta:1/120,input:input,currentCell:"floor")
            precondition(warm.modelPosition==initial && warm.output==nil,"Old partial frame survived teleport")
            warm.update(delta:1/120,input:input,currentCell:"floor")
            cold.update(delta:1/60,input:input,currentCell:"floor")
            precondition(simd_distance(warm.modelPosition,cold.modelPosition)<0.0001,model+" stale solver position")
            precondition(abs(warm.speed-cold.speed)<0.0001,model+" stale solver velocity")
            precondition(abs((warm.output?.steering ?? 0)-(cold.output?.steering ?? 0))<1e-9)
            precondition(warm.output?.wheels.map{$0.counts}==cold.output?.wheels.map{$0.counts})
            let before=warm.modelPosition
            for delta in [Double.nan,Double.infinity,-1,0]{warm.update(delta:delta,input:input,currentCell:"floor")}
            precondition(warm.modelPosition==before)
            warm.teleport(modelPosition:SIMD3(.nan,0,0),heading:0)
            precondition(warm.modelPosition==before && warm.active)
        }
        // On-foot root displacement also survives render-rate partitioning,
        // and missing geometry consumes neither input nor shared-world time.
        for hz in [30,60,90,120,144] {
            let world=SwiftRapierWorld(gravity:.zero)!,walker=NativeCharacterController(world:world)!
            walker.reset(feet:SIMD3(0,0,10))
            var calls=0
            for _ in 0..<hz*2 {
                _=walker.update(delta:1/Double(hz),displacement:SIMD3(3/Float(hz),0,0),verticalOverride:0,geometryReady:true){_,_,input in calls+=1;return input}
            }
            precondition(calls==120 && abs(walker.state.feet.x-6)<0.0001)
            let before=walker.state.feet
            _=walker.update(delta:1/30,displacement:SIMD3(1,0,0),geometryReady:false)
            _=walker.update(delta:1/120,displacement:.zero,geometryReady:true)
            precondition(walker.state.feet==before && calls==120)
        }
        print("PASS: attached walker collider, on-foot/vehicle 30–144 Hz and uneven cadences, occupied authority handoff, six-category teleport reset/damage identity, invalid time/position guards, collision-stream pause")
    }
}
