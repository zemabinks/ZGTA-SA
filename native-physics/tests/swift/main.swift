import Foundation
import simd

func close(_ a: Float, _ b: Float, _ tolerance: Float = 0.01) { precondition(abs(a-b) < tolerance, "\(a) vs \(b)") }
let world = SwiftRapierWorld(gravity: SIMD3(0, -9.81, 0))!
let floor = world.addBox(halfExtents: SIMD3(20, 0.1, 20))!
let body = world.addBody(position: SIMD3(0, 5, 0), mass: .init(value: 10, turnMass: 2), gravityScale: 1)!
let shape = world.addBox(halfExtents: SIMD3(repeating: 0.5), body: body)!
for _ in 0..<240 { precondition(world.step()) }
close(world.bodyState(body)!.position.y, 0.6, 0.05)
let own = world.raycast(origin: SIMD3(0, 8, 0), direction: SIMD3(0, -1, 0), distance: 20)!
precondition(own.collider == shape && own.body == body)
let down = world.raycast(origin: SIMD3(0, 8, 0), direction: SIMD3(0, -1, 0), distance: 20, excludingBody: body)!
precondition(down.collider == floor)
close(down.distance, 7.9)
precondition(world.removeBody(body))
let impulseBody = world.addBody(position: SIMD3(0, 5, 0), mass: .init(value: 10, turnMass: 2))!
precondition(world.applyImpulse(SIMD3(10, 0, 0), to: impulseBody))
close(world.bodyState(impulseBody)!.linearVelocity.x, 1)
precondition(world.applyTorqueImpulse(SIMD3(0, 4, 0), to: impulseBody))
close(world.bodyState(impulseBody)!.angularVelocity.y, 2)
let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "local-only/site/game/world/c59.col.bin"
let data = try Data(contentsOf: URL(fileURLWithPath: path))
let mesh = try SwiftRapierWorld.decodeSCL2(data)
precondition(mesh.indices.count / 3 == mesh.surfaces.count)
precondition(mesh.materials.count == mesh.surfaces.count)
let archiveWorld = SwiftRapierWorld()!
precondition(archiveWorld.addTriangleMesh(mesh) != nil)
let street = archiveWorld.raycast(origin: SwiftRapierWorld.gtaToRapier(SIMD3(1480, -1738, 18)), direction: SIMD3(0, -1, 0), distance: 20)!
precondition(street.distance > 0 && street.distance < 10)
precondition(street.surface >= 0)
let p = SIMD3<Float>(12, -33, 45)
precondition(SwiftRapierWorld.rapierToGTA(SwiftRapierWorld.gtaToRapier(p)) == p)
let characterWorld = SwiftRapierWorld(gravity: .zero)!
let characterFloor = characterWorld.addBox(halfExtents: SIMD3(20, 0.1, 20))!
precondition(characterWorld.addBox(halfExtents: SIMD3(0.1, 3, 3), position: SIMD3(1.5, 2, 0)) != nil)
let characterBody = characterWorld.addBody(kind: .kinematicPosition, position: SIMD3(0, 0.97, 0))!
let capsule = characterWorld.addCapsule(halfHeight: 0.5, radius: 0.35, body: characterBody)!
let motion = characterWorld.characterMovement(collider: capsule, desired: SIMD3(2, -0.3, 0))!
precondition(motion.grounded && !motion.collisions.isEmpty)
precondition(motion.translation.x > 0.8 && motion.translation.x < 1.2)
print("PASS: Swift C-module link, native body contact/impulses, own-body ray filtering, real archived SCL2 street and metadata")
// Query-only BVH must still include static colliders after a physics step has
// cleared their change flags, and disabled probes remain valid query shapes.
characterWorld.step()
let afterStep = characterWorld.characterMovement(collider: capsule, desired: SIMD3(2,-0.3,0))!
precondition(afterStep.grounded && afterStep.translation.x < 1.2)
let adapter = NativeRapierCharacterQueries(world: characterWorld)!
adapter.setEnabled(adapter.walker,true)
adapter.setTranslation(adapter.walker,SIMD3(0,0.97,0))
let nearby = adapter.intersections(center: SIMD3(0,0.95,0),halfHeight: 0.55,radius: 0.35,
    excludingCollider: adapter.walker,excludingBody: characterBody)
precondition(!nearby.contains(where: { $0.id == adapter.probe || $0.id == adapter.walker }))
precondition(nearby.contains(where: { $0.body == nil }))
let projected = characterWorld.projectPoint(characterFloor,point: SIMD3(0,3,0))!
close(projected.y,0.1)
let cast = characterWorld.castBall(origin: SIMD3(5,3,0),direction: SIMD3(0,-1,0),radius: 0.35,distance: 10)!
close(cast.distance,2.55)
precondition(cast.normal.y > 0.99)
precondition(characterWorld.castBall(origin: SIMD3(5,3,0),direction: SIMD3(0,-1,0),radius: 0.35,
    distance: 10,requireBody: true) == nil)
let fixedBody = characterWorld.addBody(kind: .fixed,position: SIMD3(6,1,0))!
let fixedShape = characterWorld.addBox(halfExtents: SIMD3(repeating: 0.5),body: fixedBody)!
let bodyCast = characterWorld.castBall(origin: SIMD3(6,3,0),direction: SIMD3(0,-1,0),radius: 0.35,distance: 10,requireBody: true)!
precondition(bodyCast.collider.body == fixedBody && !bodyCast.collider.dynamic)
precondition(characterWorld.castBall(origin: SIMD3(6,3,0),direction: SIMD3(0,-1,0),radius: 0.35,
    distance: 10,requireBody: true,excludingBodies: [fixedBody]) == nil)
let overlap = characterWorld.addSphere(radius: 0.4,position: SIMD3(6.7,1,0))!
let contact = characterWorld.contact(fixedShape,overlap,prediction: 0.5)!
precondition(contact.distance < 0 && contact.normal2.x < -0.9)
precondition(characterWorld.queryRay(origin: SIMD3(6,3,0),direction: SIMD3(0,-1,0),distance: 10,
    flags: 3,excludingBodies: [characterBody]) == nil) // ONLY_DYNAMIC
let ignoredWall = afterStep.collisions.first(where: { abs($0.normal.x) > 0.9 })!.collider
let passWall = characterWorld.characterMovement(collider: capsule,desired: SIMD3(2,0,0),
    excludingColliders: [ignoredWall,adapter.walker])!
precondition(passWall.translation.x > 1.95)
let walkingWorld = SwiftRapierWorld(gravity: SIMD3(0,-18,0))!
walkingWorld.addBox(halfExtents: SIMD3(20,0.1,20))
let walker = NativeCharacterController(world: walkingWorld)!
walker.reset(feet: SIMD3(0,0,0.1))
let hold = walker.update(delta: 1,displacement: SIMD3(2,0,0),jump: 6.07,geometryReady: false)
close(hold.feet.x,0)
for _ in 0..<120 { _ = walker.update(delta: 1/60,displacement: SIMD3(0.01,0,0),geometryReady: true) }
precondition(walker.state.grounded && walker.state.feet.x > 1)
let jump = walker.update(delta: 1/60,displacement: .zero,jump: 6.07,geometryReady: true)
precondition(jump.rising > 5 && jump.feet.z > 0.15)
print("PASS: native character contact/project/cast filters, disabled-probe KCC after world step, shared-world coordinator walking/jump and missing-cell hold")
let denseWorld = SwiftRapierWorld(gravity: .zero)!
for _ in 0..<70 { precondition(denseWorld.addSphere(radius: 0.2) != nil) }
precondition(denseWorld.intersections(center: .zero,halfHeight: 0.5,radius: 0.5).count == 70)
print("PASS: intersection result growth preserves all nearby colliders")

let rawDirectionHit = characterWorld.queryRay(origin: SIMD3(5,3,0),direction: SIMD3(0,-2,0),distance: 10)!
close(rawDirectionHit.distance,1.45)
let rawDirectionCast = characterWorld.castBall(origin: SIMD3(5,3,0),direction: SIMD3(0,-2,0),radius: 0.35,distance: 10)!
close(rawDirectionCast.distance,1.275)
print("PASS: raw ray/cast direction preserves original binding time-of-impact semantics")

let rotationWorld = SwiftRapierWorld(gravity: .zero)!
let rawRotation = simd_quatf(ix: 0.1,iy: 0.2,iz: 0.3,r: 0.9273618)
let rotated = rotationWorld.addBody(position: .zero,rotation: rawRotation)!
precondition(rotationWorld.bodyState(rotated)!.rotation.vector == rawRotation.vector)
print("PASS: raw Float quaternion preserves original binding components")
// Optional motion helpers execute on the physics clock, including held ledge
// motion. They must not inherit the render frame rate or double-step the world.
let helperWorld = SwiftRapierWorld(gravity: SIMD3(0,-9.81,0))!
helperWorld.addBox(halfExtents: SIMD3(20,0.1,20))
let helper = NativeCharacterController(world: helperWorld)!
helper.reset(feet: SIMD3(0,0,0.12),grounded: true)
var helperCalls = 0
var requestedTravel: Float = 0
let holdTarget = SIMD3<Float>(3,4,2)
let heldOutput = helper.update(delta: 1/30,displacement: SIMD3(0.02,0,0),geometryReady: true) { dt,_,intended in
    precondition(abs(dt-1/60) < 1e-12)
    helperCalls += 1; requestedTravel += intended.displacement.x
    var result = intended; result.heldFeet = holdTarget; return result
}
precondition(helperCalls == 2)
close(requestedTravel,0.02,0.000001)
precondition(simd_distance(heldOutput.feet,holdTarget) < 0.000001)
_ = helper.update(delta: 1/30,displacement: .zero,geometryReady: false) { _,_,value in helperCalls += 1; return value }
precondition(helperCalls == 2)
helper.reset(feet: SIMD3(0,0,0.12),grounded: true)
_ = helper.update(delta: 1/120,displacement: .zero,jump: 6.07,geometryReady: true)
helper.reset(feet: SIMD3(0,0,0.12),grounded: true)
let cleared = helper.update(delta: 1/60,displacement: .zero,geometryReady: true)
precondition(cleared.rising == 0)
print("PASS: optional motion callback uses fixed physics ticks, held ledge feet, missing-cell hold and teleport jump reset")

let metadataWorld = SwiftRapierWorld(gravity: .zero)!
let taggedMesh = SwiftRapierWorld.TriangleMesh(vertices: [SIMD3(-2,0,-2),SIMD3(2,0,-2),SIMD3(2,0,2),SIMD3(-2,0,2)],
    indices: [0,2,1,0,3,2],surfaces: [7,9],materials: [55,66])
let tagged = metadataWorld.addTriangleMesh(taggedMesh)!
precondition(metadataWorld.setColliderQueryMetadata(tagged,surface: 2,material: 34))
let rawFace = metadataWorld.raycast(origin: SIMD3(1,2,0),direction: SIMD3(0,-1,0),distance: 5)!
precondition(rawFace.surface == 7 && rawFace.material == 55 && rawFace.coarseSurface == 2 && rawFace.coarseMaterial == 34)
let otherFace = metadataWorld.raycast(origin: SIMD3(-1,2,0),direction: SIMD3(0,-1,0),distance: 5)!
precondition(otherFace.surface == 9 && otherFace.material == 66 && otherFace.coarseMaterial == 34)
let characterClass = metadataWorld.queryRay(origin: SIMD3(1,2,0),direction: SIMD3(0,-1,0),distance: 5)!
precondition(characterClass.collider.material == 34)
print("PASS: coarse world query classes stay separate from raw mixed-triangle impact metadata")
