import Foundation
import simd

/// Original62540 contact reduction and damage cadence around module66242.
/// Rapier data stays Y-up until an event reaches the renderer boundary.
final class NativeVehicleDamageController {
    typealias V = SIMD3<Double>
    let state:NativeVehicleDamage
    let origin:Double
    let flight:Bool
    private let world:SwiftRapierWorld
    var hinges:[Int:V] = [:]
    var random:()->Double = { Double.random(in:0..<1) }
    var onEvents:(([NativeVehicleDamage.Event],NativeVehicleDamage.Body)->Void)?
    var isOtherVehicle:((SwiftRapierWorld.ColliderID)->Bool)?
    var isRhino:((SwiftRapierWorld.ColliderID)->Bool)?
    init(world:SwiftRapierWorld,mass:Double,collisionDamage:Double,maxX:Double,flags:Int,model:Int,origin:Double,flight:Bool) {
        self.world = world;self.origin = origin;self.flight = flight
        state = NativeVehicleDamage(mass:mass,collisionDamage:collisionDamage,maxX:maxX,flags:flags,model:model)
    }
    func body(_ value:SwiftRapierWorld.BodyState)->NativeVehicleDamage.Body {
        let q=value.rotation
        let rotation=simd_quatd(ix:Double(q.imag.x),iy:Double(q.imag.y),iz:Double(q.imag.z),r:Double(q.real))
        let up=rotation.act(V(0,1,0))
        return .init(position:V(value.position)+up*origin,right:rotation.act(V(1,0,0)),forward:rotation.act(V(0,0,-1)),up:up,
            move:V(value.linearVelocity)/50,turn:V(value.angularVelocity)/50)
    }
    func step(previous:SwiftRapierWorld.BodyState,current:SwiftRapierWorld.BodyState,
              contacts:[SwiftRapierWorld.ContactForceEvent],chassis:Set<SwiftRapierWorld.ColliderID>,delta:Double) {
        for contact in contacts {
            let first=chassis.contains(contact.collider1),own=first ? contact.collider1:contact.collider2
            guard chassis.contains(own),let info=world.colliderInfo(own) else {continue}
            // Rapier's getter is Float32; the original multiplies its exposed
            // timestep, rather than the unrounded JS fixed-step constant.
            let intensity=Double(contact.totalForceMagnitude)*Double(SwiftRapierWorld.timestep)
            guard intensity>0 else {continue}
            var normal=V(contact.totalForce)*(first ? -1:1)
            let length=simd_length(normal);guard length>0 else {continue};normal /= length
            let otherID=first ? contact.collider2:contact.collider1,other=world.colliderInfo(otherID)
            guard other?.material != 62 else {continue}
            let support:Double
            switch info.shape {
            case .sphere(let radius):support=Double(radius)
            case .box(let half):
                let q=info.rotation
                let conjugate=simd_quatd(ix:-Double(q.imag.x),iy:-Double(q.imag.y),iz:-Double(q.imag.z),r:Double(q.real))
                let local=conjugate.act(normal)
                support=abs(local.x)*Double(half.x)+abs(local.y)*Double(half.y)+abs(local.z)*Double(half.z)
            case .capsule(_,let radius):support=Double(radius)
            default:support=0
            }
            let point=V(info.translation)-normal*support
            let vehicle=isOtherVehicle?(otherID) ?? (other?.dynamic == true && other?.material == 63)
            state.record(intensity:intensity/50,piece:max(0,info.piece),point:point,normal:normal,building:!flight && !vehicle,rhino:isRhino?(otherID) ?? false)
        }
        let currentBody=body(current),previousBody=body(previous),impact=state.intensity
        state.process(body:currentBody,ticks:50*delta,random:random)
        let q=current.rotation,rotation=simd_quatd(ix:Double(q.imag.x),iy:Double(q.imag.y),iz:Double(q.imag.z),r:Double(q.real))
        state.swing(body:currentBody,previous:.init(move:previousBody.move,turn:previousBody.turn),current:.init(move:currentBody.move,turn:currentBody.turn),
            hinge:{[hinges] index in hinges[index].map{rotation.act($0)}},ticks:50*delta,intensity:impact,random:random)
        if state.events.contains(where:{$0.type == "blow"}) {state.blowUp(random:random)}
        if !state.events.isEmpty {onEvents?(state.events,currentBody);state.events.removeAll()}
    }
}
