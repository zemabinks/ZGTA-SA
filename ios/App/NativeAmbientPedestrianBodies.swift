// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Nearby NPC contact bodies share the character/vehicle Rapier world. They
/// are kinematic replicas of authoritative actors, never client AI authority.
final class NativeAmbientPedestrianBodies {
    private struct Body {let identity:String,body:UInt64,collider:UInt64}
    private let world:SwiftRapierWorld
    private var bodies:[UInt16:Body]=[:]
    var colliders:Set<UInt64>{Set(bodies.values.map(\.collider))}
    init(world:SwiftRapierWorld){self.world=world}
    deinit{removeAll()}
    func removeAll(){for value in bodies.values{world.removeBody(value.body)};bodies.removeAll()}
    func synchronize(_ frames:[NativeAmbientPedestrians.Frame],near origin:SIMD3<Float>,enabled:Bool) {
        let wanted=enabled ? frames.filter{!$0.dead && !$0.down && simd_distance(SIMD3<Float>($0.position),origin)<30}:[]
        let ids=Set(wanted.map(\.id))
        for(id,value)in bodies where !ids.contains(id){world.removeBody(value.body);bodies[id]=nil}
        for frame in wanted {
            let identity="\(frame.skin):\(frame.seed)"
            if let value=bodies[frame.id],value.identity != identity{world.removeBody(value.body);bodies[frame.id]=nil}
            let center=SwiftRapierWorld.gtaToRapier(SIMD3<Float>(frame.position)+SIMD3(0,0,0.9))
            if bodies[frame.id]==nil {
                guard let body=world.addBody(kind:.kinematicPosition,position:center)else{continue}
                guard let collider=world.addCapsule(halfHeight:0.55,radius:0.3,body:body)else{world.removeBody(body);continue}
                // Same parked/contact category used by replicated vehicles.
                guard world.setColliderGroups(collider,collision:8454127,solver:0xffffffff)else{world.removeBody(body);continue}
                bodies[frame.id]=Body(identity:identity,body:body,collider:collider)
            }
            if let value=bodies[frame.id]{world.setNextKinematicPose(value.body,position:center)}
        }
    }
}
