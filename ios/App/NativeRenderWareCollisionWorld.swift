// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Thread-confined owner of authored COL instances in an existing Rapier world.
/// It does not install world step callbacks or change collision/solver groups.
final class NativeRenderWareCollisionWorld {
    typealias EntityID = UInt64
    typealias COL = NativeRenderWareCollision
    struct Limits {
        var instances = 2_048
        var colliders = 65_536
        var shapesPerInstance = 4_096
        var meshFaces = 1_000_000
        var meshVertices = 1_000_000
        var coordinateMagnitude: Float = 1_000_000
    }
    enum Failure: Error, CustomStringConvertible {
        case invalid(String), limit(String), duplicateID, staleHandle, bridge(String)
        var description: String {
            switch self {
            case .invalid(let s): return "Invalid authored collision instance: \(s)"
            case .limit(let s): return "Authored collision limit: \(s)"
            case .duplicateID: return "Authored collision entity ID already registered"
            case .staleHandle: return "Stale or foreign authored collision handle"
            case .bridge(let s): return "Authored collision native bridge failure: \(s)"
            }
        }
    }
    struct Transform {
        var position: SIMD3<Float> = .zero
        var rotation = simd_quatf(ix: 0,iy: 0,iz: 0,r: 1)
    }
    struct Instance {
        let id: EntityID
        let model: COL.Model
        var transform = Transform()
        var cameraCollision = true
        /// Explicit Rapier coefficients; no GTA surface coefficient is inferred.
        var friction: Float = 0.8
        var restitution: Float = 0
    }
    struct Handle: Hashable {
        let entityID: EntityID
        let generation: UInt64
        fileprivate let owner: UUID
    }
    enum Primitive: Equatable { case sphere(Int), box(Int), triangles }
    struct Metadata {
        let entityID: EntityID
        let bodyID: SwiftRapierWorld.BodyID
        let primitive: Primitive
        let triangle: Int?
        let surface: COL.Surface?
        var piece: Int? { surface?.flags.map(Int.init) }
    }
    struct Motion {
        let entityID: EntityID
        let bodyID: SwiftRapierWorld.BodyID
        let transform: Transform
        let linearVelocity: SIMD3<Float>
        let angularVelocity: SIMD3<Float>
        func velocity(at point: SIMD3<Float>) -> SIMD3<Float> {
            linearVelocity + simd_cross(angularVelocity,point-transform.position)
        }
    }
    private struct Entry {
        let handle: Handle
        var instance: Instance
        let body: SwiftRapierWorld.BodyID
        let colliders: [SwiftRapierWorld.ColliderID]
        let faces: Int
        let vertices: Int
    }
    private let world: SwiftRapierWorld
    private let limits: Limits
    /// COL has a raw material ID, not the browser's normalized query class.
    /// A caller may supply that classification explicitly; nil stays -1.
    private let surfaceClass: (COL.Surface) -> Int32?
    private let owner = UUID()
    private var nextGeneration: UInt64 = 1
    private var entries: [EntityID: Entry] = [:]
    private var byCollider: [SwiftRapierWorld.ColliderID: (EntityID,Primitive)] = [:]
    private var byBody: [SwiftRapierWorld.BodyID: EntityID] = [:]
    private(set) var colliderCount = 0
    private(set) var meshFaceCount = 0
    private(set) var meshVertexCount = 0
    var instanceCount: Int { entries.count }

    init(world: SwiftRapierWorld, limits: Limits = .init(), surfaceClass: @escaping (COL.Surface)->Int32? = { _ in nil }) throws {
        guard limits.instances > 0, limits.colliders > 0, limits.shapesPerInstance > 0,
              limits.meshFaces > 0, limits.meshVertices > 0,
              limits.coordinateMagnitude.isFinite, limits.coordinateMagnitude > 0,
              limits.coordinateMagnitude <= 1_000_000 else { throw Failure.limit("invalid budgets") }
        self.world = world; self.limits = limits; self.surfaceClass = surfaceClass
    }
    deinit { removeAll() }

    @discardableResult
    func insert(_ instance: Instance) throws -> Handle {
        guard entries[instance.id] == nil else { throw Failure.duplicateID }
        let transform = try validated(instance.transform)
        try validate(instance.model)
        let model = instance.model
        let shapeCount = model.spheres.count+model.boxes.count+(model.mesh.faces.isEmpty ? 0 : 1)
        guard model.hasCollisionVolumes else { throw Failure.invalid("model has no authored physical volumes") }
        guard instance.friction.isFinite, instance.friction >= 0, instance.restitution.isFinite,
              (0...1).contains(instance.restitution) else { throw Failure.invalid("contact coefficients") }
        guard entries.count < limits.instances, shapeCount <= limits.shapesPerInstance,
              shapeCount <= limits.colliders-colliderCount,
              model.mesh.faces.count <= limits.meshFaces-meshFaceCount,
              model.mesh.vertices.count <= limits.meshVertices-meshVertexCount else { throw Failure.limit("instance resources") }
        guard nextGeneration < UInt64.max else { throw Failure.limit("generation counter exhausted") }
        guard let body = world.addBody(kind: .kinematicPosition,position: Self.toRapier(transform.position),
            rotation: Self.toRapier(transform.rotation)) else { throw Failure.bridge("kinematic body") }
        var colliders: [SwiftRapierWorld.ColliderID] = [], kinds: [Primitive] = []
        var committed = false
        defer { if !committed { _ = world.removeBody(body) } }
        func add(_ id: SwiftRapierWorld.ColliderID?, kind: Primitive, surface: COL.Surface?) throws {
            guard let id else { throw Failure.bridge("collider creation") }
            colliders.append(id); kinds.append(kind)
            if let surface {
                guard world.setColliderSurface(id,surface: surfaceClass(surface) ?? -1,material: Int32(surface.material)),
                      world.setColliderPiece(id,piece: surface.flags.map(Int32.init) ?? -1) else {
                    throw Failure.bridge("primitive metadata")
                }
            }
            guard world.setColliderFrictionCombine(id,.average) else { throw Failure.bridge("friction rule") }
        }
        for (index,sphere) in model.spheres.enumerated() {
            try add(world.addSphere(radius: sphere.radius,body: body,position: Self.toRapier(sphere.center),
                friction: instance.friction,restitution: instance.restitution),kind: .sphere(index),surface: sphere.surface)
        }
        for (index,box) in model.boxes.enumerated() {
            let half = (box.maximum-box.minimum)*0.5, center = (box.maximum+box.minimum)*0.5
            try add(world.addBox(halfExtents: SIMD3(half.x,half.z,half.y),body: body,position: Self.toRapier(center),
                friction: instance.friction,restitution: instance.restitution),kind: .box(index),surface: box.surface)
        }
        if !model.mesh.faces.isEmpty {
            let mesh = SwiftRapierWorld.TriangleMesh(vertices: model.mesh.vertices.map(Self.toRapier),
                indices: model.mesh.faces.flatMap { [$0.a,$0.b,$0.c] },
                surfaces: model.mesh.faces.map { surfaceClass($0.surface) ?? -1 },
                materials: model.mesh.faces.map { Int32($0.surface.material) })
            try add(world.addTriangleMesh(mesh,body: body,friction: instance.friction,restitution: instance.restitution),
                kind: .triangles,surface: nil)
        }
        let handle = Handle(entityID: instance.id,generation: nextGeneration,owner: owner)
        nextGeneration += 1
        var stored = instance; stored.transform = transform
        entries[instance.id] = Entry(handle: handle,instance: stored,body: body,colliders: colliders,
            faces: model.mesh.faces.count,vertices: model.mesh.vertices.count)
        byBody[body] = instance.id
        for (collider,kind) in zip(colliders,kinds) { byCollider[collider] = (instance.id,kind) }
        colliderCount += colliders.count; meshFaceCount += model.mesh.faces.count; meshVertexCount += model.mesh.vertices.count
        committed = true
        return handle
    }
    func move(_ handle: Handle, to target: Transform) throws {
        let entry = try require(handle), pose = try validated(target)
        guard world.setNextKinematicPose(entry.body,position: Self.toRapier(pose.position),rotation: Self.toRapier(pose.rotation)) else {
            throw Failure.bridge("next kinematic pose")
        }
        entries[handle.entityID]?.instance.transform = pose
    }
    func setCameraCollision(_ handle: Handle, enabled: Bool) throws {
        _ = try require(handle); entries[handle.entityID]?.instance.cameraCollision = enabled
    }
    /// Query exclusions only. These shapes retain their physical groups and
    /// continue colliding with pedestrian and vehicle bodies.
    var cameraExcludedColliderIDs: Set<SwiftRapierWorld.ColliderID> {
        var result = Set<SwiftRapierWorld.ColliderID>()
        for entry in entries.values where !entry.instance.cameraCollision {
            for id in entry.colliders where world.colliderInfo(id)?.body == entry.body { result.insert(id) }
        }
        return result
    }
    func colliderIDs(for handle: Handle) -> [SwiftRapierWorld.ColliderID]? {
        guard let entry = try? require(handle) else { return nil }; return entry.colliders
    }
    func bodyID(for entityID: EntityID) -> SwiftRapierWorld.BodyID? {
        guard let entry = entries[entityID], world.bodyState(entry.body) != nil else { return nil }; return entry.body
    }
    func entityID(forBody body: SwiftRapierWorld.BodyID) -> EntityID? {
        guard world.bodyState(body) != nil else { return nil }; return byBody[body]
    }
    func metadata(collider: SwiftRapierWorld.ColliderID, triangle: Int? = nil) -> Metadata? {
        guard let (entityID,kind) = byCollider[collider], let entry = entries[entityID],
              world.colliderInfo(collider)?.body == entry.body else { return nil }
        let surface: COL.Surface?, face: Int?
        switch kind {
        case .sphere(let index): surface = entry.instance.model.spheres[index].surface; face = nil
        case .box(let index): surface = entry.instance.model.boxes[index].surface; face = nil
        case .triangles:
            if let triangle {
                guard entry.instance.model.mesh.faces.indices.contains(triangle) else { return nil }
                surface = entry.instance.model.mesh.faces[triangle].surface; face = triangle
            } else { surface = nil; face = nil }
        }
        return Metadata(entityID: entityID,bodyID: entry.body,primitive: kind,triangle: face,surface: surface)
    }
    /// Actual post-step native pose/velocities in GTA axes, suitable for moving
    /// support registration. move() stages a target; the owner still calls step().
    func motion(entityID: EntityID) -> Motion? {
        guard let entry = entries[entityID], let state = world.bodyState(entry.body) else { return nil }
        return Motion(entityID: entityID,bodyID: entry.body,
            transform: Transform(position: Self.toGTA(state.position),rotation: Self.toGTA(state.rotation)),
            linearVelocity: Self.toGTA(state.linearVelocity),angularVelocity: Self.toGTA(state.angularVelocity))
    }
    @discardableResult
    func remove(_ handle: Handle) -> Bool {
        guard handle.owner == owner, let entry = entries[handle.entityID], entry.handle == handle else { return false }
        _ = world.removeBody(entry.body) // Native removal also drops attached meshes/tags.
        entries.removeValue(forKey: handle.entityID); byBody.removeValue(forKey: entry.body)
        for id in entry.colliders { byCollider.removeValue(forKey: id) }
        colliderCount -= entry.colliders.count; meshFaceCount -= entry.faces; meshVertexCount -= entry.vertices
        return true
    }
    func removeAll() { for handle in entries.values.map(\.handle) { _ = remove(handle) } }
    private func require(_ handle: Handle) throws -> Entry {
        guard handle.owner == owner, let entry = entries[handle.entityID], entry.handle == handle,
              world.bodyState(entry.body) != nil else { throw Failure.staleHandle }
        return entry
    }
    private func point(_ p: SIMD3<Float>) -> Bool {
        (0..<3).allSatisfy { p[$0].isFinite && abs(p[$0]) <= limits.coordinateMagnitude }
    }
    private func validated(_ transform: Transform) throws -> Transform {
        let q = transform.rotation.vector, norm = simd_length_squared(q)
        guard point(transform.position), (0..<4).allSatisfy({ q[$0].isFinite }), norm.isFinite,
              abs(norm-1) <= 0.001 else { throw Failure.invalid("non-finite/non-unit GTA pose") }
        return Transform(position: transform.position,rotation: simd_quatf(vector: simd_normalize(q)))
    }
    private func validate(_ model: COL.Model) throws {
        guard model.spheres.count <= limits.shapesPerInstance, model.boxes.count <= limits.shapesPerInstance,
              model.mesh.vertices.count <= limits.meshVertices, model.mesh.faces.count <= limits.meshFaces else { throw Failure.limit("model geometry") }
        guard point(model.bounds.minimum), point(model.bounds.maximum), point(model.bounds.center),
              model.bounds.radius.isFinite, model.bounds.radius >= 0, model.bounds.radius <= limits.coordinateMagnitude else { throw Failure.invalid("model bounds") }
        for s in model.spheres {
            guard point(s.center), s.radius.isFinite, s.radius > 0, s.radius <= limits.coordinateMagnitude else { throw Failure.invalid("sphere") }
        }
        for b in model.boxes {
            guard point(b.minimum), point(b.maximum), (0..<3).allSatisfy({ b.minimum[$0] < b.maximum[$0] }) else { throw Failure.invalid("box") }
        }
        guard model.mesh.vertices.allSatisfy(point), model.mesh.faces.allSatisfy({ face in
            Int(face.a) < model.mesh.vertices.count && Int(face.b) < model.mesh.vertices.count && Int(face.c) < model.mesh.vertices.count
        }) else { throw Failure.invalid("main mesh") }
    }
    // Proper GTA Z-up -> Rapier Y-up basis. Quaternion vector permutation is
    // exactly C*R*C^-1 for every axis, not just yaw; no Euler reinterpretation.
    static func toRapier(_ p: SIMD3<Float>) -> SIMD3<Float> { SwiftRapierWorld.gtaToRapier(p) }
    static func toGTA(_ p: SIMD3<Float>) -> SIMD3<Float> { SwiftRapierWorld.rapierToGTA(p) }
    static func toRapier(_ q: simd_quatf) -> simd_quatf { simd_quatf(ix: q.imag.x,iy: q.imag.z,iz: -q.imag.y,r: q.real) }
    static func toGTA(_ q: simd_quatf) -> simd_quatf { simd_quatf(ix: q.imag.x,iy: -q.imag.z,iz: q.imag.y,r: q.real) }
}
