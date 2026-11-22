// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Presentation only. The caller supplies the admitted damage state; sampling
/// never changes health, physics, ownership or the multiplayer condition.
enum NativeVehicleThermalEffects {
    typealias V=SIMD3<Double>
    struct State {var alight=0.0}
    struct Input {
        var model:Int,kind:String?,electric=false
        var health:Double,burning:Bool
        /// Both points and velocities use GTA Z-up. The model transform already
        /// includes the chassis origin, exactly as the geometry draw does.
        var engine:V,transform:simd_double4x4,velocity:V,delta:Double
    }
    struct Emission {
        enum Kind {case smoke(strength:Double,electric:Bool),fire(system:String),aircraftSmoke(rc:Bool)}
        let kind:Kind,position:V,velocity:V,delta:Double
    }
    static func point(_ local:V,transform:simd_double4x4)->V {
        let world=transform*SIMD4(local,1)
        return V(world.x,world.y,world.z)
    }
    static func sample(_ input:Input,state:inout State,effectsAvailable:Bool=true,
                       random:()->Double={Double.random(in:0..<1)})->[Emission] {
        guard effectsAvailable,input.delta.isFinite,input.delta>0,input.health.isFinite,
              (0..<4).allSatisfy({column in (0..<4).allSatisfy{input.transform[column][$0].isFinite}}),
              (0..<3).allSatisfy({input.engine[$0].isFinite && input.velocity[$0].isFinite}) else{return []}
        func event(_ kind:Emission.Kind,_ at:V)->Emission {
            .init(kind:kind,position:at,velocity:input.velocity,delta:input.delta)
        }
        if !input.burning {
            state.alight=0
            guard input.health>=250,input.health<650,!Set(["plane","boat","train"]).contains(input.kind ?? "car") else{return []}
            return [event(.smoke(strength:1-(input.health-250)/400,electric:input.electric),input.engine)]
        }
        state.alight+=input.delta
        switch input.kind ?? "car" {
        case "plane","heli":
            let count=max(0,Int(floor(12.5*input.delta+random())))
            let rc=Set([464,465,501]).contains(input.model)
            var result=(0..<count).map{_ in event(.aircraftSmoke(rc:rc),point(.zero,transform:input.transform))}
            if state.alight>2.5{result.append(event(.fire(system:"fire_large"),input.engine))}
            return result
        case "bike":
            guard !Set([481,509,510]).contains(input.model)else{return []}
            return [event(.fire(system:"fire_bike"),input.engine)]
        case "boat":
            let local:V
            switch input.model {
            case 452:local=V(0.4,-2.4,0.8)
            case 453:local=V(2,-1,0.5)
            default:local=V(-1.5,-0.5,1.2)
            }
            return [event(.fire(system:"fire_car"),point(local,transform:input.transform))]
        default:return [event(.fire(system:"fire_car"),input.engine)]
        }
    }
    /// Reuses the actual data-driven particle owner. Missing optional systems
    /// stay absent; this does not manufacture replacement sprites or assets.
    static func render(_ emissions:[Emission],into effects:NativeParticleEffects,
                       random:()->Double={Double.random(in:0..<1)}) {
        for event in emissions {
            switch event.kind {
            case .smoke(let strength,let electric):
                let name=electric && effects.has("overheat_car_electric") ? "overheat_car_electric":"overheat_car"
                effects.burst(name,at:event.position,delta:event.delta,options:.init(time:strength,velocity:event.velocity))
            case .fire(let system):
                let name=effects.has(system) ? system:"fire_car"
                effects.burst(name,at:event.position,delta:event.delta,options:.init(velocity:event.velocity))
            case .aircraftSmoke(let rc):
                guard effects.has("prt_smoke_huge")else{continue}
                let radius=rc ? 0.7:2,spread=rc ? 0.5:1.5
                let x=(2*random()-1)*radius,y = -(2*random()-1)*radius
                let vx=(2*random()-1)*spread,vz=random()*(rc ? 0.4:1),vy = -(2*random()-1)*spread
                effects.spawn("prt_smoke_huge",at:event.position+V(x,y,0),velocity:V(vx,vy,vz),
                    options:.init(tint:rc ? V(0,0,pow((0.15+0.055)/1.055,2.4)):.zero,mult:.init(size:rc ? 0.3:1,life:0.3,alpha:0.4)))
            }
        }
    }
}
