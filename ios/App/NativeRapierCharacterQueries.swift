import Foundation
import simd

/// Actual Rapier queries used by the archived on-foot motor, sharing the rigid
/// body world with native vehicles. The game loop owns physics stepping.
final class NativeRapierCharacterQueries: NativeCharacterQueries {
    let world: SwiftRapierWorld
    let walker: UInt64
    let probe: UInt64

    init?(world: SwiftRapierWorld) {
        guard let walker = world.addCapsule(halfHeight: 0.55, radius: 0.35) else { return nil }
        guard let probe = world.addCapsule(halfHeight: 0.325, radius: 0.33) else {
            world.removeCollider(walker); return nil
        }
        self.world = world; self.walker = walker; self.probe = probe
        world.setColliderGroups(walker, collision: 524417, solver: 0xffff0000 & 524417)
        world.setColliderGroups(probe, collision: 0, solver: 0)
        world.setCollider(walker, enabled: false)
        world.setCollider(probe, enabled: false)
    }
    deinit { world.removeCollider(walker); world.removeCollider(probe) }

    private func f(_ v: V) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }
    private func d(_ v: SIMD3<Float>) -> V { V(Double(v.x), Double(v.y), Double(v.z)) }
    private func collider(_ value: SwiftRapierWorld.ColliderInfo) -> NativeCharacterCollider {
        NativeCharacterCollider(id: value.id, body: value.body, dynamic: value.dynamic,
                                translation: d(value.translation), material: value.material)
    }
    func setEnabled(_ collider: UInt64, _ enabled: Bool) { world.setCollider(collider, enabled: enabled) }
    func setTranslation(_ collider: UInt64, _ position: V) { world.setColliderTranslation(collider, position: f(position)) }
    func intersections(center: V, halfHeight: Double, radius: Double,
                       excludingCollider: UInt64?, excludingBody: UInt64?) -> [NativeCharacterCollider] {
        world.intersections(center: f(center), halfHeight: Float(halfHeight), radius: Float(radius),
            excludingColliders: excludingCollider.map { [$0] } ?? [],
            excludingBodies: excludingBody.map { [$0] } ?? []).map(collider)
    }
    func contact(_ first: UInt64, _ second: UInt64, prediction: Double) -> NativeCharacterContact? {
        guard let value = world.contact(first, second, prediction: Float(prediction)) else { return nil }
        return NativeCharacterContact(distance: Double(value.distance), normal2: d(value.normal2),
                                      point1: d(value.point1), point2: d(value.point2))
    }
    func movement(center: V, desired: V, excludingColliders: Set<UInt64>,
                  excludingBodies: Set<UInt64>) -> NativeCharacterMovement {
        // The public client computes movement with its disabled, smaller probe
        // capsule; enabled walker dimensions remain the contact-query shape.
        world.setColliderTranslation(probe, position: f(center))
        var settings = SwiftRapierWorld.CharacterSettings()
        settings.maxSlopeClimbAngle = 0.001; settings.minSlopeSlideAngle = 0.001
        guard let value = world.characterMovement(collider: probe, desired: f(desired), settings: settings,
            excludingColliders: excludingColliders, excludingBodies: excludingBodies) else {
            return NativeCharacterMovement(translation: .zero, normals: [])
        }
        return NativeCharacterMovement(translation: d(value.translation), normals: value.collisions.map { d($0.normal) })
    }
    func ray(origin: V, distance: Double, groups: UInt32,
             excludingBodies: Set<UInt64>) -> NativeCharacterHit? {
        guard let value = world.queryRay(origin: f(origin), direction: SIMD3(0,-1,0), distance: Float(distance),
            groups: groups, excludingBodies: excludingBodies) else { return nil }
        return NativeCharacterHit(collider: collider(value.collider), distance: Double(value.distance), normal: d(value.normal))
    }
    func castBall(origin: V, radius: Double, distance: Double, groups: UInt32,
                  excludingColliders: Set<UInt64>, excludingBodies: Set<UInt64>, requireBody: Bool) -> NativeCharacterHit? {
        guard let value = world.castBall(origin: f(origin), direction: SIMD3(0,-1,0), radius: Float(radius), distance: Float(distance),
            groups: groups, requireBody: requireBody, excludingColliders: excludingColliders, excludingBodies: excludingBodies) else { return nil }
        return NativeCharacterHit(collider: collider(value.collider), distance: Double(value.distance), normal: d(value.normal))
    }
    func project(_ collider: UInt64, point: V) -> V? { world.projectPoint(collider, point: f(point), solid: true).map(d) }
}
