// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Nearby traffic uses original converted chassis shapes, as kinematic
/// replicas of the server world. Contacts never grant local traffic authority.
final class NativeAmbientTrafficBodies {
    struct Shape {
        let kind:String,centre:SIMD3<Float>,halfExtents:SIMD3<Float>,radius:Float
        let friction:Float,restitution:Float,piece:Int
    }
    struct Snapshot {
        let id:UInt16,generation:UInt64,model:UInt16
        let position:SIMD3<Double>,heading:Double,pitch:Double
    }
    private struct Body {let generation:UInt64,model:UInt16,body:UInt64,colliders:Set<UInt64>}
    private let world:SwiftRapierWorld
    private var bodies:[UInt16:Body]=[:]
    static let maximumBodies=24,maximumShapes=256
    var colliders:Set<UInt64>{bodies.values.reduce(into:Set<UInt64>()){$0.formUnion($1.colliders)}}
    init(world:SwiftRapierWorld){self.world=world}
    deinit{removeAll()}
    func removeAll(){for value in bodies.values{world.removeBody(value.body)};bodies=[:]}
    func trafficID(for collider:UInt64)->UInt16?{bodies.first{$0.value.colliders.contains(collider)}?.key}
    /// Native streaming policy: nearest24 inside40m. These are runtime work
    /// caps, not asserted original-game population/physics thresholds.
    func synchronize(_ frames:[Snapshot],near origin:SIMD3<Float>,enabled:Bool,shapes:(UInt16)->[Shape]?) {
        guard enabled,origin.x.isFinite,origin.y.isFinite,origin.z.isFinite else{removeAll();return}
        let wanted=Array(frames.filter{[$0.position.x,$0.position.y,$0.position.z,$0.heading,$0.pitch].allSatisfy(\.isFinite) &&
            simd_distance($0.position,SIMD3<Double>(origin))<40}.sorted{
                let a=simd_distance_squared($0.position,SIMD3<Double>(origin)),b=simd_distance_squared($1.position,SIMD3<Double>(origin))
                return a==b ? $0.id<$1.id:a<b
            }.prefix(Self.maximumBodies))
        let ids=Set(wanted.map(\.id))
        for(id,value)in bodies where !ids.contains(id){world.removeBody(value.body);bodies[id]=nil}
        for frame in wanted {
            if let old=bodies[frame.id],old.generation != frame.generation || old.model != frame.model{world.removeBody(old.body);bodies[frame.id]=nil}
            let position=SwiftRapierWorld.gtaToRapier(SIMD3<Float>(frame.position))
            // Match the actual rendered GTA Rz(-heading)*Rx(pitch), after
            // changing basis to Rapier X/up/-Y. Model origin is in the shapes.
            let rotation=simd_quatf(angle:Float(-frame.heading),axis:SIMD3(0,1,0))*simd_quatf(angle:Float(frame.pitch),axis:SIMD3(1,0,0))
            if bodies[frame.id]==nil {
                guard let shapes=shapes(frame.model),!shapes.isEmpty,shapes.count<=Self.maximumShapes,
                      let body=world.addBody(kind:.kinematicPosition,position:position,rotation:rotation)else{continue}
                var made=Set<UInt64>()
                for shape in shapes {
                    let collider:UInt64?
                    if shape.kind=="sphere"{collider=world.addSphere(radius:shape.radius,body:body,position:shape.centre,friction:shape.friction,restitution:shape.restitution)}
                    else if shape.kind=="box"{collider=world.addBox(halfExtents:shape.halfExtents,body:body,position:shape.centre,friction:shape.friction,restitution:shape.restitution)}
                    else{collider=nil}
                    guard let collider,world.setColliderGroups(collider,collision:8454127,solver:33554944),
                          world.setColliderPiece(collider,piece:Int32(clamping:shape.piece)),
                          world.setColliderSurface(collider,surface:2,material:63)else{break}
                    made.insert(collider)
                }
                guard made.count==shapes.count else{world.removeBody(body);continue}
                bodies[frame.id]=Body(generation:frame.generation,model:frame.model,body:body,colliders:made)
            }
            if let body=bodies[frame.id]?.body{world.setNextKinematicPose(body,position:position,rotation:rotation);world.setBrowserNextKinematicRotation(body,rotation:rotation)}
        }
    }
}
