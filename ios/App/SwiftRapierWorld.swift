import Foundation
import simd
import ZGTARapier

/// Native Rapier rigid bodies and shape queries. The linked Rust library is
/// built from the official source commit used by the archived JS/Wasm engine.
/// This owner is confined to its caller's thread (normally the game main loop).
final class SwiftRapierWorld {
    typealias BodyID = UInt64
    typealias ColliderID = UInt64
    typealias JointID = UInt64
    struct SphericalJointState {
        let body1: BodyID
        let body2: BodyID
        let anchor1: SIMD3<Float>
        let anchor2: SIMD3<Float>
        let contactsEnabled: Bool
    }
    enum BodyKind: UInt32 { case fixed = 0, dynamic = 1, kinematicPosition = 2, kinematicVelocity = 3 }
    enum CombineRule: UInt32 { case average = 0, min = 1, multiply = 2, max = 3 }
    struct BodyState {
        var position: SIMD3<Float>
        var rotation: simd_quatf
        var linearVelocity: SIMD3<Float> = .zero
        var angularVelocity: SIMD3<Float> = .zero
        fileprivate var values: [Float] {
            [position.x, position.y, position.z, rotation.imag.x, rotation.imag.y,
             rotation.imag.z, rotation.real, linearVelocity.x, linearVelocity.y,
             linearVelocity.z, angularVelocity.x, angularVelocity.y, angularVelocity.z]
        }
    }
    struct Mass {
        var value: Float
        var centre: SIMD3<Float>
        var inertia: SIMD3<Float>
        init(value: Float, centre: SIMD3<Float> = .zero, inertia: SIMD3<Float>) {
            self.value = value; self.centre = centre; self.inertia = inertia
        }
        init(value: Float, centre: SIMD3<Float> = .zero, turnMass: Float) {
            self.init(value: value, centre: centre, inertia: SIMD3(repeating: turnMass))
        }
        fileprivate var values: [Float] { [value, centre.x, centre.y, centre.z, inertia.x, inertia.y, inertia.z] }
    }
    struct Hit {
        let collider: ColliderID
        let body: BodyID?
        let distance: Float
        let normal: SIMD3<Float>
        let point: SIMD3<Float>
        let triangle: Int
        let surface: Int
        let material: Int
        let coarseSurface: Int
        let coarseMaterial: Int
    }
    struct TriangleMesh {
        var vertices: [SIMD3<Float>]
        var indices: [UInt32]
        var surfaces: [Int32] = []
        var materials: [Int32] = []
    }
    struct CharacterSettings {
        var offset: Float = 0.02
        var up = SIMD3<Float>(0, 1, 0)
        var maxSlopeClimbAngle: Float = .pi / 4
        var minSlopeSlideAngle: Float = .pi / 4
        var slide = true
        var snapToGround: Float? = nil
        var relativeSnap = false
        var stepHeight: Float?
        var stepWidth: Float = 0.5
        var stepDynamicBodies = true
        var normalNudge: Float = 0.0001
        var mass: Float = 0
        var applyImpulses = false
        var timestep: Float = SwiftRapierWorld.timestep
        var groups: UInt32? = nil
        var queryFlags: UInt32 = 0
    }
    struct CharacterCollision {
        let collider: ColliderID
        let timeOfImpact: Float
        let normal: SIMD3<Float>
        let point: SIMD3<Float>
        let translationApplied: SIMD3<Float>
    }
    struct CharacterMovement {
        let translation: SIMD3<Float>
        let grounded: Bool
        let slidingDownSlope: Bool
        let collisions: [CharacterCollision]
    }
    enum MeshError: Error { case invalidHeader, invalidCounts, truncated, invalidVertex, invalidIndex }
    private let handle: OpaquePointer
    // Native bodies are created through this owner. Preserve exact type for
    // queries that distinguish fixed parents from kinematic vehicle parents;
    // ColliderInfo.dynamic alone cannot make that distinction.
    private var bodyKinds:[BodyID:BodyKind] = [:]
    static let timestep: Float = 1 / 60

    init?(gravity: SIMD3<Float> = SIMD3(0, -9.81, 0)) {
        guard zgtaphys_bridge_version() == 1,
              let handle = zgtaphys_world_new(gravity.x, gravity.y, gravity.z) else { return nil }
        self.handle = handle
    }
    deinit { zgtaphys_world_free(handle) }

    /// Original fixed-step manager ordering: parked force updates precede
    /// the core, parked damage/pose updates precede the driven contact drain.
    var beforeStep:((Double)->Void)?
    var afterStep:((Double)->Void)?
    @discardableResult
    func step() -> Bool {
        let delta=1.0/60.0
        beforeStep?(delta)
        let succeeded=zgtaphys_world_step(handle) != 0
        if succeeded {afterStep?(delta)}
        return succeeded
    }

    @discardableResult
    func addBody(kind: BodyKind = .dynamic, position: SIMD3<Float>,
                 rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                 mass: Mass = Mass(value: 1, turnMass: 1), gravityScale: Float = 0) -> BodyID? {
        let pose = [position.x, position.y, position.z, rotation.imag.x, rotation.imag.y, rotation.imag.z, rotation.real]
        let id = zgtaphys_body_new(handle, kind.rawValue, pose, mass.values, gravityScale)
        guard id != 0 else{return nil}
        bodyKinds[id]=kind
        return id
    }
    @discardableResult
    func setNextKinematicPose(_ id: BodyID, position: SIMD3<Float>,
                              rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)) -> Bool {
        zgtaphys_body_next_kinematic(handle, id, pose(position: position, rotation: rotation)) != 0
    }
    /// Original JS rbSetRotation semantics: normalize after Float conversion.
    /// Raw setBodyState remains available for exact physics state restoration.
    @discardableResult
    func setBrowserRotation(_ id: BodyID, rotation: simd_quatf, wakeUp: Bool = true) -> Bool {
        let q = rotation.vector
        return zgtaphys_body_set_browser_rotation(handle, id, [q.x,q.y,q.z,q.w], wakeUp ? 1 : 0) != 0
    }
    @discardableResult
    func setBrowserNextKinematicRotation(_ id: BodyID, rotation: simd_quatf) -> Bool {
        let q = rotation.vector
        return zgtaphys_body_set_browser_next_rotation(handle, id, [q.x,q.y,q.z,q.w]) != 0
    }
    @discardableResult
    func removeBody(_ id: BodyID) -> Bool {
        guard zgtaphys_body_remove(handle,id) != 0 else{return false}
        bodyKinds.removeValue(forKey:id)
        return true
    }
    func bodyKind(_ id:BodyID)->BodyKind? {bodyKinds[id]}
    /// Anchors are local to each body in this world's axes. Towing uses a free
    /// spherical joint with connected-body contacts disabled; no spring or
    /// angular motor is introduced by this bridge.
    func createSphericalJoint(body1:BodyID,body2:BodyID,anchor1:SIMD3<Float>,anchor2:SIMD3<Float>,
                              contactsEnabled:Bool=false,wakeUp:Bool=true)->JointID? {
        let anchors=[anchor1.x,anchor1.y,anchor1.z,anchor2.x,anchor2.y,anchor2.z]
        let id=zgtaphys_joint_spherical(handle,body1,body2,anchors,contactsEnabled ? 1:0,wakeUp ? 1:0)
        return id == 0 ? nil:id
    }
    @discardableResult
    func setJointAnchor1(_ id:JointID,anchor:SIMD3<Float>,wakeUp:Bool=true)->Bool {
        zgtaphys_joint_anchor1(handle,id,[anchor.x,anchor.y,anchor.z],wakeUp ? 1:0) != 0
    }
    @discardableResult
    func removeJoint(_ id:JointID,wakeUp:Bool=true)->Bool {
        zgtaphys_joint_remove(handle,id,wakeUp ? 1:0) != 0
    }
    func sphericalJointState(_ id:JointID)->SphericalJointState? {
        var bodies=[UInt64](repeating:0,count:2),anchors=[Float](repeating:0,count:6),contacts:UInt32=0
        guard zgtaphys_joint_info(handle,id,&bodies,&anchors,&contacts) != 0 else{return nil}
        return .init(body1:bodies[0],body2:bodies[1],anchor1:SIMD3(anchors[0],anchors[1],anchors[2]),
                     anchor2:SIMD3(anchors[3],anchors[4],anchors[5]),contactsEnabled:contacts != 0)
    }
    func jointExists(_ id:JointID)->Bool {sphericalJointState(id) != nil}
    func bodyState(_ id: BodyID) -> BodyState? {
        var result = [Float](repeating: 0, count: 13)
        guard zgtaphys_body_state(handle, id, &result) != 0 else { return nil }
        return BodyState(position: SIMD3(result[0], result[1], result[2]),
            rotation: simd_quatf(ix: result[3], iy: result[4], iz: result[5], r: result[6]),
            linearVelocity: SIMD3(result[7], result[8], result[9]),
            angularVelocity: SIMD3(result[10], result[11], result[12]))
    }
    @discardableResult
    func setBodyState(_ state: BodyState, for id: BodyID) -> Bool {
        zgtaphys_body_set_state(handle, id, state.values) != 0
    }
    @discardableResult
    func setVelocities(_ id: BodyID, linear: SIMD3<Float>, angular: SIMD3<Float>) -> Bool {
        zgtaphys_body_set_velocities(handle, id, [linear.x, linear.y, linear.z, angular.x, angular.y, angular.z]) != 0
    }
    @discardableResult
    func setMass(_ mass: Mass, for id: BodyID) -> Bool { zgtaphys_body_set_mass(handle, id, mass.values) != 0 }
    func mass(of id: BodyID) -> Float? {
        var value: Float = 0
        return zgtaphys_body_mass(handle,id,&value) != 0 ? value:nil
    }
    @discardableResult
    func recomputeMassProperties(_ id: BodyID) -> Bool { zgtaphys_body_recompute_mass(handle,id) != 0 }
    @discardableResult
    func setColliderFrictionCombine(_ id: ColliderID, _ rule: CombineRule) -> Bool {
        zgtaphys_collider_friction_combine(handle,id,rule.rawValue) != 0
    }
    @discardableResult
    func applyImpulse(_ value: SIMD3<Float>, to id: BodyID, at point: SIMD3<Float>? = nil) -> Bool {
        var values = [value.x, value.y, value.z]
        if let point { values.append(contentsOf: [point.x, point.y, point.z]) }
        return zgtaphys_body_impulse(handle, id, values, point == nil ? 0 : 2) != 0
    }
    @discardableResult
    func applyTorqueImpulse(_ value: SIMD3<Float>, to id: BodyID) -> Bool {
        zgtaphys_body_impulse(handle, id, [value.x, value.y, value.z], 1) != 0
    }

    private func pose(position: SIMD3<Float>, rotation: simd_quatf) -> [Float] {
        [position.x, position.y, position.z, rotation.imag.x, rotation.imag.y, rotation.imag.z, rotation.real]
    }
    @discardableResult
    func addSphere(radius: Float, body: BodyID? = nil, position: SIMD3<Float> = .zero,
                   friction: Float = 0.5, restitution: Float = 0) -> ColliderID? {
        let p = pose(position: position, rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
        let id = zgtaphys_collider_ball(handle, body ?? 0, radius, p, friction, restitution)
        return id == 0 ? nil : id
    }
    @discardableResult
    func addCapsule(halfHeight: Float, radius: Float, body: BodyID? = nil,
                    position: SIMD3<Float> = .zero, friction: Float = 0.5, restitution: Float = 0) -> ColliderID? {
        let p = pose(position: position, rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
        let id = zgtaphys_collider_capsule(handle, body ?? 0, halfHeight, radius, p, friction, restitution)
        return id == 0 ? nil : id
    }
    func characterMovement(collider: ColliderID, desired: SIMD3<Float>,
                           settings: CharacterSettings = CharacterSettings(),
                           excludingColliders: Set<ColliderID> = [], excludingBodies: Set<BodyID> = []) -> CharacterMovement? {
        let p: [Float] = [settings.offset, settings.up.x, settings.up.y, settings.up.z,
            settings.maxSlopeClimbAngle, settings.minSlopeSlideAngle, settings.snapToGround ?? -1,
            settings.stepHeight ?? -1, settings.stepWidth, settings.normalNudge, settings.mass, settings.timestep]
        var options: UInt32 = settings.slide ? 1 : 0
        if settings.stepDynamicBodies { options |= 2 }; if settings.applyImpulses { options |= 4 }
        if settings.relativeSnap { options |= 8 }; if settings.groups != nil { options |= 16 }
        var movement = [Float](repeating: 0, count: 5)
        var colliders = [UInt64](repeating: 0, count: 64)
        var collisions = [Float](repeating: 0, count: 640)
        var count: UInt32 = 0
        let ignoredColliders = Array(excludingColliders), ignoredBodies = Array(excludingBodies)
        guard zgtaphys_character_move_filtered(handle, collider, [desired.x, desired.y, desired.z], p,
            options, settings.groups ?? 0, settings.queryFlags, ignoredColliders, UInt32(ignoredColliders.count),
            ignoredBodies, UInt32(ignoredBodies.count), &movement, &colliders, &collisions, 64, &count) != 0 else { return nil }
        let events = (0..<Int(count)).map { index -> CharacterCollision in
            let offset = index * 10
            return CharacterCollision(collider: colliders[index], timeOfImpact: collisions[offset],
                normal: SIMD3(collisions[offset+1], collisions[offset+2], collisions[offset+3]),
                point: SIMD3(collisions[offset+4], collisions[offset+5], collisions[offset+6]),
                translationApplied: SIMD3(collisions[offset+7], collisions[offset+8], collisions[offset+9]))
        }
        return CharacterMovement(translation: SIMD3(movement[0], movement[1], movement[2]),
            grounded: movement[3] != 0, slidingDownSlope: movement[4] != 0, collisions: events)
    }
    @discardableResult
    func addBox(halfExtents: SIMD3<Float>, body: BodyID? = nil, position: SIMD3<Float> = .zero,
                rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                friction: Float = 0.5, restitution: Float = 0) -> ColliderID? {
        let id = zgtaphys_collider_box(handle, body ?? 0, [halfExtents.x, halfExtents.y, halfExtents.z],
            pose(position: position, rotation: rotation), friction, restitution)
        return id == 0 ? nil : id
    }
    @discardableResult
    func addConvexHull(vertices: [SIMD3<Float>], body: BodyID? = nil, position: SIMD3<Float> = .zero,
                       rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                       friction: Float = 0.5, restitution: Float = 0) -> ColliderID? {
        guard vertices.count >= 4, vertices.count <= 1_000_000 else { return nil }
        let points = vertices.flatMap { [$0.x, $0.y, $0.z] }
        let id = zgtaphys_collider_convex(handle, body ?? 0, points, UInt32(vertices.count),
            pose(position: position, rotation: rotation), friction, restitution)
        return id == 0 ? nil : id
    }
    @discardableResult
    func addTriangleMesh(_ mesh: TriangleMesh) -> ColliderID? {
        guard !mesh.vertices.isEmpty, !mesh.indices.isEmpty,
              mesh.vertices.count <= 1_000_000, mesh.indices.count % 3 == 0,
              mesh.indices.count / 3 <= 1_000_000,
              mesh.indices.allSatisfy({ $0 < UInt32(mesh.vertices.count) }) else { return nil }
        let count = mesh.indices.count / 3
        let points = mesh.vertices.flatMap { [$0.x, $0.y, $0.z] }
        let surfaces = mesh.surfaces.count == count ? mesh.surfaces : [Int32](repeating: 2, count: count)
        let materials = mesh.materials.count == count ? mesh.materials : [Int32](repeating: -1, count: count)
        let id = zgtaphys_collider_trimesh(handle, points, UInt32(mesh.vertices.count), mesh.indices,
            UInt32(count), surfaces, materials)
        return id == 0 ? nil : id
    }
    @discardableResult
    func removeCollider(_ id: ColliderID) -> Bool { zgtaphys_collider_remove(handle, id) != 0 }
    @discardableResult
    func setCollider(_ id: ColliderID, enabled: Bool) -> Bool {
        zgtaphys_collider_enabled(handle, id, enabled ? 1 : 0) != 0
    }
    @discardableResult
    func setColliderSurface(_ id: ColliderID, surface: Int32, material: Int32 = -1) -> Bool {
        zgtaphys_collider_surface(handle, id, surface, material) != 0
    }
    @discardableResult
    func setColliderGroups(_ id: ColliderID, collision: UInt32, solver: UInt32) -> Bool {
        zgtaphys_collider_groups(handle, id, collision, solver) != 0
    }
    func raycast(origin: SIMD3<Float>, direction: SIMD3<Float>, distance: Float,
                 excludingBody: BodyID? = nil, excludingColliders: Set<ColliderID> = [],
                 groups: UInt32 = 0xffffffff) -> Hit? {
        var geometry = [Float](repeating: 0, count: 7)
        var info = [Int32](repeating: 0, count: 3)
        var body: UInt64 = 0
        let excluded = Array(excludingColliders)
        let id = zgtaphys_raycast_groups(handle, [origin.x, origin.y, origin.z],
            [direction.x, direction.y, direction.z], distance, groups, excludingBody ?? 0,
            excluded, UInt32(excluded.count), &geometry, &info, &body)
        guard id != 0 else { return nil }
        let coarse = colliderQueryMetadata(id)
        return Hit(collider: id, body: body == 0 ? nil : body, distance: geometry[0],
            normal: SIMD3(geometry[1], geometry[2], geometry[3]), point: SIMD3(geometry[4], geometry[5], geometry[6]),
            triangle: Int(info[0]), surface: Int(info[1]), material: Int(info[2]),
            coarseSurface: coarse?.surface ?? Int(info[1]), coarseMaterial: coarse?.material ?? Int(info[2]))
    }

    enum ColliderShape {
        case sphere(radius: Float)
        case box(halfExtents: SIMD3<Float>)
        case capsule(halfHeight: Float, radius: Float)
        case other
    }
    struct ContactForceEvent {
        let collider1: ColliderID
        let collider2: ColliderID
        let body1: BodyID?
        let body2: BodyID?
        let totalForce: SIMD3<Float>
        let totalForceMagnitude: Float
        let maxForceDirection: SIMD3<Float>
        let maxForceMagnitude: Float
        let started: Bool
    }
    struct ColliderInfo {
        let id: ColliderID
        let body: BodyID?
        let dynamic: Bool
        let translation: SIMD3<Float>
        let material: Int
        let rotation: simd_quatf
        let shape: ColliderShape
        let piece: Int
    }
    struct Contact {
        let distance: Float
        let normal2: SIMD3<Float>
        let point1: SIMD3<Float>
        let point2: SIMD3<Float>
    }
    struct QueryHit {
        let collider: ColliderInfo
        let distance: Float
        let normal: SIMD3<Float>
        let point: SIMD3<Float>
    }
    @discardableResult
    func enableArchivedStepping(_ enabled: Bool = true) -> Bool {
        zgtaphys_archived_stepping(handle, enabled ? 1 : 0) != 0
    }
    @discardableResult
    func setColliderTranslation(_ id: ColliderID, position: SIMD3<Float>) -> Bool {
        zgtaphys_collider_translation(handle, id, [position.x, position.y, position.z]) != 0
    }
    /// Moves an attached shape in its parent's local frame, preserving body
    /// pose and momentum. A standalone collider keeps Rapier's no-op behavior.
    @discardableResult
    func setColliderTranslationWrtParent(_ id:ColliderID,position:SIMD3<Float>)->Bool {
        zgtaphys_collider_translation_wrt_parent(handle,id,[position.x,position.y,position.z]) != 0
    }
    func colliderInfo(_ id: ColliderID) -> ColliderInfo? {
        var position = [Float](repeating: 0, count: 3), body: UInt64 = 0, dynamic: UInt32 = 0, material: Int32 = -1
        guard zgtaphys_collider_info(handle, id, &position, &body, &dynamic, &material) != 0 else { return nil }
        var shapeData = [Float](repeating: 0, count: 7), piece: Int32 = -1
        let kind = zgtaphys_collider_shape_info(handle, id, &shapeData, &piece)
        let shape: ColliderShape
        switch kind {
        case 1: shape = .sphere(radius: shapeData[4])
        case 2: shape = .box(halfExtents: SIMD3(shapeData[4],shapeData[5],shapeData[6]))
        case 3: shape = .capsule(halfHeight: shapeData[4],radius: shapeData[5])
        default: shape = .other
        }
        return ColliderInfo(id: id, body: body == 0 ? nil : body, dynamic: dynamic != 0,
                            translation: SIMD3(position[0], position[1], position[2]), material: Int(material),
                            rotation: simd_quatf(ix: shapeData[0],iy: shapeData[1],iz: shapeData[2],r: shapeData[3]),
                            shape: shape,piece: Int(piece))
    }
    /// The original streamed world uses normalized per-collider classes for
    /// character and wheel queries, while impact effects retain raw face values.
    @discardableResult
    func setColliderQueryMetadata(_ id: ColliderID, surface: Int32, material: Int32) -> Bool {
        zgtaphys_collider_set_query_metadata(handle, id, surface, material) != 0
    }
    func colliderQueryMetadata(_ id: ColliderID) -> (surface: Int, material: Int)? {
        var values = [Int32](repeating: 0, count: 2)
        guard zgtaphys_collider_query_metadata(handle, id, &values) != 0 else { return nil }
        return (Int(values[0]),Int(values[1]))
    }
    @discardableResult
    func setColliderPiece(_ id: ColliderID, piece: Int32) -> Bool {
        zgtaphys_collider_piece(handle, id, piece) != 0
    }
    @discardableResult
    func setContactForceEvents(_ id: ColliderID, enabled: Bool = true) -> Bool {
        zgtaphys_collider_contact_events(handle, id, enabled ? 1 : 0) != 0
    }
    /// Uses actual solver impulses converted to forces by Rapier. Values remain
    /// in world Y-up axes; game damage scaling belongs to the original handler.
    func drainContactForceEvents() -> [ContactForceEvent] {
        var result: [ContactForceEvent] = []
        while true {
            let capacity = min(100000,Int(zgtaphys_contact_events_count(handle)))
            guard capacity > 0 else { return result }
            var ids = [UInt64](repeating: 0, count: capacity*4)
            var forces = [Float](repeating: 0, count: capacity*8)
            var started = [UInt32](repeating: 0, count: capacity)
            let count = Int(zgtaphys_contact_events_drain(handle, &ids, &forces, &started, UInt32(capacity)))
            guard count > 0 else { return result }
            result.reserveCapacity(result.count+count)
            for index in 0..<count {
                let i = index*4, f = index*8
                result.append(ContactForceEvent(collider1: ids[i],collider2: ids[i+1],
                    body1: ids[i+2] == 0 ? nil : ids[i+2],body2: ids[i+3] == 0 ? nil : ids[i+3],
                    totalForce: SIMD3(forces[f],forces[f+1],forces[f+2]),totalForceMagnitude: forces[f+3],
                    maxForceDirection: SIMD3(forces[f+4],forces[f+5],forces[f+6]),maxForceMagnitude: forces[f+7],
                    started: started[index] != 0))
            }
        }
    }
    func intersections(center: SIMD3<Float>, halfHeight: Float, radius: Float,
                       groups: UInt32? = nil, flags: UInt32 = 0,
                       excludingColliders: Set<ColliderID> = [], excludingBodies: Set<BodyID> = []) -> [ColliderInfo] {
        let ec = Array(excludingColliders), eb = Array(excludingBodies)
        var capacity = 64
        while true {
            var ids = [UInt64](repeating: 0, count: capacity)
            let count = zgtaphys_intersections_capsule(handle, [center.x, center.y, center.z], halfHeight, radius,
                groups ?? 0, flags, groups == nil ? 0 : 1, ec, UInt32(ec.count), eb, UInt32(eb.count), &ids, UInt32(capacity))
            if Int(count) < capacity || capacity == 100000 {
                return ids.prefix(Int(count)).compactMap { colliderInfo($0) }
            }
            capacity = min(100000, capacity * 2)
        }
    }
    func sphereIntersections(center: SIMD3<Float>, radius: Float,
                       groups: UInt32? = nil, flags: UInt32 = 0,
                       excludingColliders: Set<ColliderID> = [], excludingBodies: Set<BodyID> = []) -> [ColliderInfo] {
        let ec = Array(excludingColliders), eb = Array(excludingBodies)
        var capacity = 64
        while true {
            var ids = [UInt64](repeating: 0, count: capacity)
            let count = zgtaphys_intersections_sphere(handle, [center.x, center.y, center.z], radius,
                groups ?? 0, flags, groups == nil ? 0 : 1, ec, UInt32(ec.count), eb, UInt32(eb.count), &ids, UInt32(capacity))
            if Int(count) < capacity || capacity == 100000 {
                return ids.prefix(Int(count)).compactMap { colliderInfo($0) }
            }
            capacity = min(100000, capacity * 2)
        }
    }
    func contact(_ first: ColliderID, _ second: ColliderID, prediction: Float) -> Contact? {
        var data = [Float](repeating: 0, count: 10)
        guard zgtaphys_contact(handle, first, second, prediction, &data) != 0 else { return nil }
        return Contact(distance: data[0], normal2: SIMD3(data[1], data[2], data[3]),
                       point1: SIMD3(data[4], data[5], data[6]), point2: SIMD3(data[7], data[8], data[9]))
    }
    func projectPoint(_ collider: ColliderID, point: SIMD3<Float>, solid: Bool = true) -> SIMD3<Float>? {
        var output = [Float](repeating: 0, count: 3)
        guard zgtaphys_project_point(handle, collider, [point.x, point.y, point.z], solid ? 1 : 0, &output) != 0 else { return nil }
        return SIMD3(output[0], output[1], output[2])
    }
    func queryRay(origin: SIMD3<Float>, direction: SIMD3<Float>, distance: Float,
                  groups: UInt32? = nil, flags: UInt32 = 0, requireBody: Bool = false,
                  excludingColliders: Set<ColliderID> = [], excludingBodies: Set<BodyID> = []) -> QueryHit? {
        let ec = Array(excludingColliders), eb = Array(excludingBodies)
        var geometry = [Float](repeating: 0, count: 7)
        let options: UInt32 = (groups == nil ? 0 : 1) | (requireBody ? 2 : 0)
        let id = zgtaphys_query_ray(handle, [origin.x, origin.y, origin.z], [direction.x, direction.y, direction.z],
            distance, groups ?? 0, flags, options, ec, UInt32(ec.count), eb, UInt32(eb.count), &geometry)
        guard id != 0, let collider = colliderInfo(id) else { return nil }
        return QueryHit(collider: collider, distance: geometry[0], normal: SIMD3(geometry[1], geometry[2], geometry[3]),
                        point: SIMD3(geometry[4], geometry[5], geometry[6]))
    }
    func castBall(origin: SIMD3<Float>, direction: SIMD3<Float>, radius: Float, distance: Float,
                  groups: UInt32? = nil, flags: UInt32 = 0, requireBody: Bool = false,
                  excludingColliders: Set<ColliderID> = [], excludingBodies: Set<BodyID> = []) -> QueryHit? {
        let ec = Array(excludingColliders), eb = Array(excludingBodies)
        var geometry = [Float](repeating: 0, count: 7)
        let options: UInt32 = (groups == nil ? 0 : 1) | (requireBody ? 2 : 0)
        let id = zgtaphys_cast_ball(handle, [origin.x, origin.y, origin.z], [direction.x, direction.y, direction.z],
            radius, distance, groups ?? 0, flags, options, ec, UInt32(ec.count), eb, UInt32(eb.count), &geometry)
        guard id != 0, let collider = colliderInfo(id) else { return nil }
        return QueryHit(collider: collider, distance: geometry[0], normal: SIMD3(geometry[1], geometry[2], geometry[3]),
                        point: SIMD3(geometry[4], geometry[5], geometry[6]))
    }

    static func gtaToRapier(_ point: SIMD3<Float>) -> SIMD3<Float> { SIMD3(point.x, point.z, -point.y) }
    static func rapierToGTA(_ point: SIMD3<Float>) -> SIMD3<Float> { SIMD3(point.x, -point.z, point.y) }

    /// Retains the original SCL2 face ordering for surface/material wheel queries.
    /// Empty valid cells return an empty mesh; callers need not install a collider.
    static func decodeSCL2(_ data: Data, convertGTA: Bool = true) throws -> TriangleMesh {
        let bytes = [UInt8](data)
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset+1]) << 8 | UInt32(bytes[offset+2]) << 16 | UInt32(bytes[offset+3]) << 24
        }
        guard bytes.count >= 16, u32(0) == 0x324c4353 else { throw MeshError.invalidHeader }
        let vertices = Int(u32(4)), triangles = Int(u32(8)), flags = u32(12)
        guard vertices < 1_000_000, triangles < 1_000_000,
              vertices > 0 || triangles == 0 else { throw MeshError.invalidCounts }
        let indexStart = 16 + vertices*12, surfaceStart = indexStart + triangles*12
        guard surfaceStart + triangles <= bytes.count else { throw MeshError.truncated }
        var points: [SIMD3<Float>] = []
        points.reserveCapacity(vertices)
        for index in 0..<vertices {
            let offset = 16+index*12
            let point = SIMD3(Float(bitPattern: u32(offset)), Float(bitPattern: u32(offset+4)), Float(bitPattern: u32(offset+8)))
            guard point.x.isFinite, point.y.isFinite, point.z.isFinite else { throw MeshError.invalidVertex }
            points.append(convertGTA ? gtaToRapier(point) : point)
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(triangles*3)
        for index in 0..<triangles*3 {
            let value = u32(indexStart+index*4)
            guard value < vertices else { throw MeshError.invalidIndex }
            indices.append(value)
        }
        let padded = (triangles+3)/4*4, materialStart = surfaceStart+padded
        let surfaces: [Int32] = (0..<triangles).map { Int32(bytes[surfaceStart+$0]) }
        let materials: [Int32] = (0..<triangles).map { flags&1 != 0 && surfaceStart+2*padded <= bytes.count ? Int32(bytes[materialStart+$0]) : -1 }
        return TriangleMesh(vertices: points, indices: indices, surfaces: surfaces, materials: materials)
    }
}
