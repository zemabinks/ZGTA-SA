import Foundation
import simd

func v(_ value: Any) -> SIMD3<Float> {
    let a = value as! [Double]; return SIMD3(Float(a[0]),Float(a[1]),Float(a[2]))
}
let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String:Any]
let frames = fixture["frames"] as! [[String:Any]]
let world = SwiftRapierWorld(gravity: SIMD3(0,-9.81,0))!
let floor = world.addBox(halfExtents: SIMD3(20,0.1,20))!
let body = world.addBody(position: SIMD3(0,3,0),mass: .init(value: 10,turnMass: 2),gravityScale: 1)!
let sphere = world.addSphere(radius: 0.5,body: body)!
precondition(world.setContactForceEvents(sphere))
precondition(world.setColliderSurface(sphere,surface: 2,material: 34))
precondition(world.setColliderPiece(sphere,piece: 7))
let info = world.colliderInfo(sphere)!
precondition(info.piece == 7 && info.material == 34 && info.body == body && info.dynamic)
if case .sphere(let radius) = info.shape { precondition(radius == 0.5) } else { preconditionFailure("Lost original shape") }
var maxPosition: Float = 0, maxVelocity: Float = 0, maxForce: Float = 0
var totalEvents = 0, sawStarted = false, sawPersistent = false
for (index,frame) in frames.enumerated() {
    precondition(world.step())
    let state = world.bodyState(body)!, reference = frame["events"] as! [[String:Any]]
    maxPosition = max(maxPosition,simd_length(state.position-v(frame["position"]!)))
    maxVelocity = max(maxVelocity,simd_length(state.linearVelocity-v(frame["velocity"]!)))
    let events = world.drainContactForceEvents()
    precondition(events.count == reference.count,"Contact event count at frame \(index)")
    for (event,expected) in zip(events,reference) {
        precondition(Set([event.collider1,event.collider2]) == Set([floor,sphere]))
        precondition(event.collider1 == sphere ? event.body1 == body && event.body2 == nil : event.body2 == body && event.body1 == nil)
        precondition((event.collider1 == sphere ? "body" : "floor") == expected["first"] as! String)
        maxForce = max(maxForce,simd_length(event.totalForce-v(expected["force"]!)))
        maxForce = max(maxForce,abs(event.totalForceMagnitude-Float(expected["magnitude"] as! Double)))
        maxForce = max(maxForce,simd_length(event.maxForceDirection-v(expected["maxDirection"]!)))
        maxForce = max(maxForce,abs(event.maxForceMagnitude-Float(expected["maxMagnitude"] as! Double)))
        precondition(event.totalForceMagnitude > 0 && event.maxForceMagnitude > 0)
        precondition(event.totalForceMagnitude+0.001 >= simd_length(event.totalForce))
        sawStarted = sawStarted || event.started; sawPersistent = sawPersistent || !event.started
        totalEvents += 1
    }
    precondition(world.drainContactForceEvents().isEmpty,"Events drained twice")
}
precondition(totalEvents > 0 && sawStarted && sawPersistent)
precondition(maxPosition < 0.001 && maxVelocity < 0.01 && maxForce < 0.1,"Native contact-force fields diverged from archived engine")
precondition(world.setContactForceEvents(sphere,enabled: false))
world.step(); precondition(world.drainContactForceEvents().isEmpty)
precondition(world.setContactForceEvents(sphere))
world.step() // Leave events undrained, then ensure the next step auto-clears them.
var state = world.bodyState(body)!
state.position.y = 10; state.linearVelocity = .zero
world.setBodyState(state,for: body); world.step()
precondition(world.drainContactForceEvents().isEmpty)
state.position.y = 0.59; world.setBodyState(state,for: body); world.step()
world.removeBody(body)
let removed = world.drainContactForceEvents()
precondition(!removed.isEmpty && removed.contains(where: { $0.body1 == body || $0.body2 == body }))
let report: [String:Any] = ["frames":frames.count,"events":totalEvents,"maxPositionError":maxPosition,
    "maxVelocityError":maxVelocity,"maxContactFieldError":maxForce]
try JSONSerialization.data(withJSONObject: report,options: [.prettyPrinted,.sortedKeys])
    .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("PASS: \(frames.count) archived engine contact frames, \(totalEvents) native force events, max position \(maxPosition), velocity \(maxVelocity), force-field error \(maxForce)")
print("PASS: event toggle/auto-clear/drain ownership, removed-body IDs and exact collider shape/piece/material")
