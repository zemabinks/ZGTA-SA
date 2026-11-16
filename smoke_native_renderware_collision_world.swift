// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
import ZGTARapier

private enum WorldTestFailure: Error { case check(String) }
private func check(_ value: @autoclosure () -> Bool, _ reason: String) throws {
    if !value() { throw WorldTestFailure.check(reason) }
}
private func rejects(_ reason: String, _ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw WorldTestFailure.check("expected rejection: " + reason)
}
private typealias COL = NativeRenderWareCollision
private typealias CW = NativeRenderWareCollisionWorld
private func surface(_ material: UInt8, piece: UInt8? = nil) -> COL.Surface {
    COL.Surface(material: material,flags: piece,brightness: piece == nil ? nil : 123,lighting: 0xab)
}
private func authored(_ mesh: COL.Mesh = .init(vertices: [],faces: []), spheres: [COL.Sphere] = [],
                      boxes: [COL.Box] = [], shadow: COL.Mesh? = nil) -> COL.Model {
    COL.Model(version: .col3,name: "own_generated",modelID: 0,
        bounds: .init(minimum: SIMD3(repeating: -10),maximum: SIMD3(repeating: 10),center: .zero,radius: 20),
        flags: UInt32((mesh.faces.isEmpty && spheres.isEmpty && boxes.isEmpty ? 0 : 2)+(shadow == nil ? 0 : 16)),
        spheres: spheres,boxes: boxes,mesh: mesh,faceGroups: [],shadowMesh: shadow)
}
private func floorMesh(_ half: Float = 2, height: Float = 0) -> COL.Mesh {
    COL.Mesh(vertices: [SIMD3(-half,-half,height),SIMD3(half,-half,height),SIMD3(half,half,height),SIMD3(-half,half,height)],
        faces: [.init(a: 0,b: 1,c: 2,surface: surface(12)),.init(a: 0,b: 2,c: 3,surface: surface(13))])
}
private func ray(_ world: SwiftRapierWorld, _ origin: SIMD3<Float>, _ direction: SIMD3<Float>, _ length: Float,
                 excluding: Set<SwiftRapierWorld.ColliderID> = []) -> SwiftRapierWorld.Hit? {
    world.raycast(origin: CW.toRapier(origin),direction: CW.toRapier(direction),distance: length,excludingColliders: excluding)
}

private func cBoundaryTests() throws -> Int {
    guard let raw = zgtaphys_world_new(0,-9.81,0) else { throw WorldTestFailure.check("C world") }
    defer { zgtaphys_world_free(raw) }
    let pose: [Float] = [0,0,0,0,0,0,1], mass: [Float] = [1,0,0,0,1,1,1]
    let body = zgtaphys_body_new(raw,2,pose,mass,0)
    try check(body != 0,"C parent")
    let vertices: [Float] = [-1,0,-1, 1,0,-1, -1,0,1, 1,0,1]
    let indices: [UInt32] = [0,2,1,1,2,3], surfaces: [Int32] = [41,42], materials: [Int32] = [5,6]
    func create(parent: UInt64? = nil, points: [Float]? = nil, faces: [UInt32]? = nil,
                local: [Float]? = nil, friction: Float = 0.8, restitution: Float = 0) -> UInt64 {
        zgtaphys_collider_trimesh_parented(raw,parent ?? body,points ?? vertices,4,faces ?? indices,2,
            surfaces,materials,local ?? pose,friction,restitution)
    }
    var checks = 0
    func zero(_ id: UInt64, _ reason: String) throws { try check(id == 0,reason); checks += 1 }
    try zero(create(parent: 0),"parent zero")
    try zero(create(parent: UInt64.max),"unknown parent")
    try zero(zgtaphys_collider_trimesh_parented(nil,body,vertices,4,indices,2,surfaces,materials,pose,0.8,0),"null world")
    try zero(zgtaphys_collider_trimesh_parented(raw,body,nil,4,indices,2,surfaces,materials,pose,0.8,0),"null vertices")
    try zero(zgtaphys_collider_trimesh_parented(raw,body,vertices,4,nil,2,surfaces,materials,pose,0.8,0),"null indices")
    try zero(zgtaphys_collider_trimesh_parented(raw,body,vertices,1_000_001,indices,2,surfaces,materials,pose,0.8,0),"vertex budget before read")
    try zero(zgtaphys_collider_trimesh_parented(raw,body,vertices,4,indices,1_000_001,surfaces,materials,pose,0.8,0),"face budget before read")
    try zero(create(faces: [0,2,9,1,2,3]),"index bounds")
    var bad = vertices; bad[0] = .nan; try zero(create(points: bad),"NaN vertex")
    bad = vertices; bad[0] = 1_000_001; try zero(create(points: bad),"coordinate bound")
    try zero(create(local: [0,0,0,0,0,0,0]),"zero quaternion")
    try zero(create(local: [0,0,0,0,0,0,2]),"nonunit quaternion")
    try zero(create(local: [.nan,0,0,0,0,0,1]),"NaN pose")
    try zero(create(local: [1_000_001,0,0,0,0,0,1]),"pose coordinate bound")
    try zero(create(friction: -.infinity),"friction finite")
    try zero(create(friction: -1),"friction nonnegative")
    try zero(create(restitution: 2),"restitution bound")
    let mesh = create(); try check(mesh != 0,"valid parented mesh")
    try check(zgtaphys_world_step(raw) != 0,"C step")
    var geometry = [Float](repeating: 0,count: 7), info = [Int32](repeating: 0,count: 3), hitBody: UInt64 = 0
    let hit = zgtaphys_raycast(raw,[-0.5,2,-0.5],[0,-1,0],4,0,nil,0,&geometry,&info,&hitBody)
    try check(hit == mesh && hitBody == body && info[1] == 41 && info[2] == 5,"C face metadata/parent")
    let moved: [Float] = [3,1,0,0,0,0,1]
    try check(zgtaphys_body_next_kinematic(raw,body,moved) != 0 && zgtaphys_world_step(raw) != 0,"C kinematic move")
    let newHit = zgtaphys_raycast(raw,[2.5,3,-0.5],[0,-1,0],4,0,nil,0,&geometry,&info,&hitBody)
    try check(newHit == mesh && hitBody == body && abs(geometry[0]-2) < 0.0001,"C parented translation")
    try check(zgtaphys_body_remove(raw,body) != 0,"C remove")
    try zero(create(),"removed parent cannot revive")
    var position = [Float](repeating: 0,count: 3), parent: UInt64 = 0, dynamic: UInt32 = 0, material: Int32 = 0
    try check(zgtaphys_collider_info(raw,mesh,&position,&parent,&dynamic,&material) == 0,"attached mesh removed with parent")
    let secondPose: [Float] = [10,0,0,0,0,0,1]
    let second = zgtaphys_body_new(raw,2,secondPose,mass,0)
    let localTurn = simd_quatf(angle: 0.3,axis: SIMD3<Float>(1,0,0))
    let localPose: [Float] = [0,2,0,localTurn.imag.x,localTurn.imag.y,localTurn.imag.z,localTurn.real]
    let shifted = zgtaphys_collider_trimesh_parented(raw,second,vertices,4,indices,2,surfaces,materials,localPose,0.8,0)
    try check(shifted != 0 && zgtaphys_world_step(raw) != 0,"nonidentity collider-local pose")
    let localPoint = SIMD3<Float>(10,2,0)+localTurn.act(SIMD3(-0.5,0,-0.5))
    let localNormal = localTurn.act(SIMD3<Float>(0,1,0)), origin = localPoint+localNormal*2
    let localHit = zgtaphys_raycast(raw,[origin.x,origin.y,origin.z],[-localNormal.x,-localNormal.y,-localNormal.z],4,0,nil,0,&geometry,&info,&hitBody)
    try check(localHit == shifted && hitBody == second && abs(geometry[0]-2) < 0.0001,"local pose remains relative to body")
    _ = zgtaphys_body_remove(raw,second)
    return checks
}

@main struct CollisionWorldSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2])
        let boundaryChecks = try cBoundaryTests()
        guard let world = SwiftRapierWorld() else { throw WorldTestFailure.check("native world") }
        let owner = try CW(world: world,surfaceClass: { 100+Int32($0.material) })
        let floor = try owner.insert(.init(id: 1,model: authored(floorMesh(),shadow: floorMesh(height: 5))))
        try check(owner.colliderCount == 1 && owner.meshFaceCount == 2,"only main mesh creates collider")
        let floorIDs = owner.colliderIDs(for: floor)!
        try check(world.colliderInfo(floorIDs[0])?.body == owner.bodyID(for: 1),"real parented native collider")
        try check(world.step(),"initial step")
        let first = ray(world,SIMD3(0.75,-0.25,10),SIMD3(0,0,-1),20)!
        try check(first.collider == floorIDs[0] && abs(first.distance-10) < 0.0001,"shadow never becomes floor")
        try check(first.material == 12 && first.surface == 112 && first.triangle == 0,"main face material/class")
        let tag = owner.metadata(collider: first.collider,triangle: first.triangle)!
        try check(tag.entityID == 1 && tag.surface?.material == 12 && tag.surface?.flags == nil,"face metadata preserved")
        try check(owner.metadata(collider: first.collider,triangle: 99) == nil,"invalid triangle metadata rejected")
        let downward = world.addCapsule(halfHeight: 0.2,radius: 0.1,position: CW.toRapier(SIMD3(0.5,0.5,1)))!
        try check(world.step(),"capsule query step")
        let landing = world.characterMovement(collider: downward,desired: CW.toRapier(SIMD3(0,0,-2)))!
        try check(landing.grounded && landing.translation.y > -1 && landing.translation.y < 0,"character lands on authored floor")
        _ = world.removeCollider(downward)
        let wallBox = COL.Box(minimum: SIMD3(-0.15,-2,0),maximum: SIMD3(0.15,2,3),surface: surface(45,piece: 7))
        let wall = try owner.insert(.init(id: 2,model: authored(boxes: [wallBox]),
            transform: .init(position: SIMD3(3,0,0)),cameraCollision: false))
        try check(world.step(),"wall step")
        let wallIDs = owner.colliderIDs(for: wall)!
        let wallHit = ray(world,SIMD3(0,0,1),SIMD3(1,0,0),5)!
        try check(wallHit.collider == wallIDs[0] && wallHit.material == 45,"wall hit")
        try check(world.colliderInfo(wallIDs[0])?.piece == 7 && owner.metadata(collider: wallIDs[0])?.piece == 7,"piece metadata")
        try check(owner.cameraExcludedColliderIDs == Set(wallIDs),"camera-only exclusion IDs")
        try check(ray(world,SIMD3(0,0,1),SIMD3(1,0,0),5,excluding: owner.cameraExcludedColliderIDs) == nil,"camera ignores disabled wall")
        let side = world.addCapsule(halfHeight: 0.2,radius: 0.1,position: CW.toRapier(SIMD3(1,0,1)))!
        try check(world.step(),"side capsule step")
        let blocked = world.characterMovement(collider: side,desired: CW.toRapier(SIMD3(4,0,0)))!
        try check(blocked.translation.x < 2 && blocked.collisions.contains(where: { wallIDs.contains($0.collider) }),"camera-disabled wall remains physical to ped")
        _ = world.removeCollider(side)
        let car = world.addBody(kind: .dynamic,position: CW.toRapier(SIMD3(1,0,1)),gravityScale: 0)!
        _ = world.addSphere(radius: 0.2,body: car)
        try check(world.setVelocities(car,linear: CW.toRapier(SIMD3(6,0,0)),angular: .zero),"vehicle proxy velocity")
        for _ in 0..<60 { try check(world.step(),"vehicle contact step") }
        let carPosition = CW.toGTA(world.bodyState(car)!.position)
        try check(carPosition.x < 3 && carPosition.x > 1,"camera-disabled wall remains physical to vehicle body")
        _ = world.removeBody(car)
        try owner.setCameraCollision(wall,enabled: true)
        try check(owner.cameraExcludedColliderIDs.isEmpty,"camera enabled without group changes")
        try owner.move(wall,to: .init(position: SIMD3(4,0,0)))
        try check(world.step(),"wall move step")
        try check(abs(ray(world,SIMD3(0,0,1),SIMD3(1,0,0),6)!.distance-3.85) < 0.001,"attached box follows body")
        try check(owner.motion(entityID: 2)!.linearVelocity.x > 59,"actual kinematic velocity exposed")

        guard let movingWorld = SwiftRapierWorld() else { throw WorldTestFailure.check("moving world") }
        let moving = try CW(world: movingWorld)
        let platform = try moving.insert(.init(id: 50,model: authored(floorMesh())))
        let platformCollider = moving.colliderIDs(for: platform)![0]
        let ball = movingWorld.addBody(kind: .dynamic,position: CW.toRapier(SIMD3(0,0,0.5)),gravityScale: 1)!
        let ballCollider = movingWorld.addSphere(radius: 0.2,body: ball)!
        for _ in 0..<120 { try check(movingWorld.step(),"settling") }
        try check(abs(CW.toGTA(movingWorld.bodyState(ball)!.position).z-0.2) < 0.01,"dynamic body rests on parented triangles")
        try moving.move(platform,to: .init(position: SIMD3(0.1,0,0)))
        try check(movingWorld.step(),"moving platform step")
        let platformMotion = moving.motion(entityID: 50)!, carried = CW.toGTA(movingWorld.bodyState(ball)!.linearVelocity).x
        try check(abs(platformMotion.linearVelocity.x-6) < 0.001,"mesh kinematic contact velocity")
        try check(carried > 0.0001,"moving triangle contact transmits velocity")
        try check(movingWorld.contact(ballCollider,platformCollider,prediction: 0.1) != nil,"real moving triangle contact")
        let turn = simd_quatf(angle: 0.4,axis: SIMD3(0,0,1))*simd_quatf(angle: 0.3,axis: SIMD3(1,0,0))*simd_quatf(angle: -0.25,axis: SIMD3(0,1,0))
        let tilted = CW.Transform(position: SIMD3(10,10,1),rotation: turn)
        try moving.move(platform,to: tilted); try check(movingWorld.step(),"full-basis rotated mesh step")
        let point = tilted.position+turn.act(SIMD3(0.75,-0.25,0)), normal = turn.act(SIMD3(0,0,1))
        let tiltedHit = ray(movingWorld,point+normal*2,-normal,4)!
        try check(tiltedHit.collider == platformCollider && abs(tiltedHit.distance-2) < 0.001,"full GTA basis applied once")
        try check(simd_dot(CW.toGTA(tiltedHit.normal),normal) > 0.9999,"rotated authored normal")
        let motion = moving.motion(entityID: 50)!
        try check(abs(simd_dot(motion.transform.rotation.vector,turn.vector)) > 0.99999,"full quaternion basis roundtrip")
        try check(moving.entityID(forBody: motion.bodyID) == 50,"body -> entity support mapping")
        let expectedPointVelocity = motion.linearVelocity+simd_cross(motion.angularVelocity,point-motion.transform.position)
        try check(simd_distance(motion.velocity(at: point),expectedPointVelocity) < 0.00001,"support point velocity")
        try rejects("non-finite pose") { try moving.move(platform,to: .init(position: SIMD3(.nan,0,0))) }
        try rejects("nonunit pose") { try moving.move(platform,to: .init(rotation: simd_quatf(ix: 0,iy: 0,iz: 0,r: 2))) }
        try rejects("duplicate ID") { _ = try moving.insert(.init(id: 50,model: authored(floorMesh()))) }
        let oldBody = moving.bodyID(for: 50)!, oldIDs = moving.colliderIDs(for: platform)!
        try check(moving.remove(platform),"remove owned object")
        try check(movingWorld.bodyState(oldBody) == nil && oldIDs.allSatisfy({ movingWorld.colliderInfo($0) == nil }),"native mesh ownership cleanup")
        let reused = try moving.insert(.init(id: 50,model: authored(floorMesh())))
        try check(reused.generation != platform.generation && !moving.remove(platform),"stale removal cannot affect reused ID")
        try rejects("stale move") { try moving.move(platform,to: .init()) }
        try check(moving.metadata(collider: oldIDs[0]) == nil,"stale collider metadata")
        let other = try CW(world: movingWorld)
        _ = try other.insert(.init(id: 50,model: authored(floorMesh())))
        try rejects("foreign owner handle") { try other.move(reused,to: .init()) }
        try check(!other.remove(reused),"foreign removal rejected")
        other.removeAll(); moving.removeAll(); owner.removeAll()
        try check(owner.instanceCount == 0 && owner.colliderCount == 0 && owner.meshFaceCount == 0 && owner.meshVertexCount == 0,"budgets restored")
        try rejects("shadow only has no physical fallback") { _ = try owner.insert(.init(id: 99,model: authored(shadow: floorMesh(height: 5)))) }
        var cap = CW.Limits(); cap.instances = 1
        let limited = try CW(world: world,limits: cap)
        let single = try limited.insert(.init(id: 10,model: authored(floorMesh())))
        try rejects("instance cap") { _ = try limited.insert(.init(id: 11,model: authored(floorMesh()))) }
        try check(limited.instanceCount == 1 && limited.colliderCount == 1,"failed insert has no registration leak")
        _ = limited.remove(single)
        for (name,change) in [("colliders",{(l: inout CW.Limits)in l.colliders=1;l.shapesPerInstance=1}),
                              ("faces",{(l: inout CW.Limits)in l.meshFaces=1}),
                              ("vertices",{(l: inout CW.Limits)in l.meshVertices=3})] {
            var values = CW.Limits();change(&values);let bounded = try CW(world: world,limits: values)
            let model = name == "colliders" ? authored(spheres: [.init(center: .zero,radius: 1,surface: surface(1,piece: 2)),.init(center: SIMD3(3,0,0),radius: 1,surface: surface(1,piece: 2))]) : authored(floorMesh())
            try rejects(name) { _ = try bounded.insert(.init(id: 1,model: model)) }
            try check(bounded.instanceCount == 0 && bounded.colliderCount == 0,"bounded insert atomicity")
        }
        var ownerFiles = 0, actualModels = 0, shapes = 0, mainFaces = 0, shadowFaces = 0
        let archive = root.appendingPathComponent("local-only/site/game")
        let ownerPaths = FileManager.default.fileExists(atPath: archive.path) ?
            try FileManager.default.contentsOfDirectory(at: archive,includingPropertiesForKeys: nil) : []
        for path in ownerPaths.filter({ $0.pathExtension == "dff" }).sorted(by: {$0.path<$1.path}) {
            ownerFiles += 1
            for embedded in try COL.embedded(inDFF: Data(contentsOf: path)) {
                for model in embedded.models {
                    let id = UInt64(1000+actualModels), handle = try owner.insert(.init(id: id,model: model,cameraCollision: false))
                    let ids = owner.colliderIDs(for: handle)!, count = model.spheres.count+model.boxes.count+(model.mesh.faces.isEmpty ? 0:1)
                    try check(ids.count == count,"actual authored shape count \(path.lastPathComponent)")
                    try check(ids.allSatisfy({ world.colliderInfo($0)?.body == owner.bodyID(for: id) }),"actual native parent ownership")
                    try check(owner.cameraExcludedColliderIDs.count == count,"actual camera exclusions")
                    shapes += count;mainFaces += model.mesh.faces.count;shadowFaces += model.shadowMesh?.faces.count ?? 0
                    try check(owner.remove(handle),"actual removal")
                    try check(ids.allSatisfy({ world.colliderInfo($0) == nil }),"actual collider cleanup")
                    actualModels += 1
                }
            }
        }
        let report: [String: Any] = ["nativeCABI": true,"boundaryChecks": boundaryChecks,"floorAndWall": true,
            "cameraExclusionsPreservePedAndVehicleCollision": true,"parentedKinematicTriangles": true,
            "movingContactVelocity": Double(carried),"fullGTAQuaternionBasis": true,"staleAndForeignHandlesRejected": true,
            "ownerDFFs": ownerFiles,"actualModels": actualModels,"actualPhysicalColliders": shapes,
            "actualMainFaces": mainFaces,"excludedShadowFaces": shadowFaces,"remainingOwnedInstances": owner.instanceCount]
        try JSONSerialization.data(withJSONObject: report,options: [.prettyPrinted,.sortedKeys]).write(to: out.appendingPathComponent("report.json"))
        print("PASS authored COL world / parented mesh / native contact and \(actualModels) owner models")
    }
}
