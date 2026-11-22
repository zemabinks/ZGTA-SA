import Foundation
import simd

/// Original bike impact weighting and contact-gated rollover ejection.
/// Velocity uses Rapier world units/s; damage intensity uses the source's
/// impulse/50 boundary. Reading an event consumes it once.
final class NativeBikeEjection {
    typealias V=SIMD3<Double>
    struct Event {let force:Double,velocity:V}
    let model:Int,mass:Double
    private var pending:Event?,fallenMilliseconds=0.0
    init(model:Int,mass:Double){self.model=model;self.mass=mass}
    func reset(){pending=nil;fallenMilliseconds=0}
    func take()->Event? {defer{pending=nil};return pending}
    static func force(intensity:Double,mass:Double,model:Int,way:V,forward:V,right:V,up:V)->Double {
        guard intensity.isFinite,mass.isFinite,mass>0 else{return 0}
        var strength=intensity/mass*600
        guard strength>10 else{return 0}
        let along=simd_dot(forward,way),vertical=simd_dot(up,way),across=simd_dot(right,way)
        var front=0.6,top=0.05
        if abs(along)>0.85 {front=7*pow(way.y<0.85 ? 0:way.y,2)+0.6}
        if up.y<0 {front=5}
        if model==468 {front *= 0.65;top *= 0.75}
        strength *= abs(along)*front+max(vertical,0)*top+0.45*abs(across)-1.5*min(vertical,0)
        return strength>75 ? strength:0
    }
    func impact(intensity:Double,way:V,body:NativeVehicleDamage.Body,previousVelocity:V,occupied:Bool) {
        guard occupied else{return}
        let value=Self.force(intensity:intensity,mass:mass,model:model,way:way,forward:body.forward,right:body.right,up:body.up)
        if value>(pending?.force ?? 0){pending=Event(force:value,velocity:previousVelocity)}
    }
    func step(delta:Double,up:V,velocity:V,contact:Bool,occupied:Bool) {
        guard delta.isFinite,delta>0,occupied else{fallenMilliseconds=0;return}
        if contact,pending==nil {
            fallenMilliseconds=up.y<0.35 && simd_length(velocity)<3 ? fallenMilliseconds+1000*delta:0
            if up.y < -0.1 || fallenMilliseconds>500 {pending=Event(force:0,velocity:velocity)}
        } else if !contact {fallenMilliseconds=0}
    }
}

/// Original62540 contact reduction and damage cadence around module66242.
/// Rapier data stays Y-up until an event reaches the renderer boundary.
final class NativeVehicleDamageController {
    typealias V = SIMD3<Double>
    let state:NativeVehicleDamage
    let origin:Double
    let flight:Bool
    private let mass:Double
    struct Collision {let material:Int;let impact:Double;let point:V;let normal:V}
    var onCollisions:(([Collision],NativeVehicleDamage.Body)->Void)?
    var onImpact:((Double,V,NativeVehicleDamage.Body,V)->Void)?
    private(set) var contactSeen=false
    private let world:SwiftRapierWorld
    var hinges:[Int:V] = [:]
    var random:()->Double = { Double.random(in:0..<1) }
    var onEvents:(([NativeVehicleDamage.Event],NativeVehicleDamage.Body)->Void)?
    var isOtherVehicle:((SwiftRapierWorld.ColliderID)->Bool)?
    var isRhino:((SwiftRapierWorld.ColliderID)->Bool)?
    init(world:SwiftRapierWorld,mass:Double,collisionDamage:Double,maxX:Double,flags:Int,model:Int,origin:Double,flight:Bool) {
        self.world = world;self.origin = origin;self.flight = flight;self.mass=mass
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
              contacts:[SwiftRapierWorld.ContactForceEvent],chassis:Set<SwiftRapierWorld.ColliderID>,delta:Double,drowning:Bool=false) {
        contactSeen=false
        var collisionOrder:[Int]=[],collisions:[Int:Collision]=[:]
        for contact in contacts {
            let first=chassis.contains(contact.collider1),own=first ? contact.collider1:contact.collider2
            guard chassis.contains(own),let info=world.colliderInfo(own) else {continue}
            contactSeen=true
            // Rapier's getter is Float32; the original multiplies its exposed
            // timestep, rather than the unrounded JS fixed-step constant.
            let intensity=Double(contact.totalForceMagnitude)*Double(SwiftRapierWorld.timestep)
            guard intensity>0 else {continue}
            var normal=V(contact.totalForce)*(first ? -1:1)
            let length=simd_length(normal);guard length>0 else {continue};normal /= length
            let otherID=first ? contact.collider2:contact.collider1,other=world.colliderInfo(otherID)
            onImpact?(intensity/50,normal,body(current),V(previous.linearVelocity))
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
            if other?.material != 62 {
                state.record(intensity:intensity/50,piece:max(0,info.piece),point:point,normal:normal,building:!flight && !vehicle,rhino:isRhino?(otherID) ?? false)
            }
            if !vehicle {
                let material=other?.material ?? 0,impact=intensity/50/(mass != 0 ? mass:1500)
                if collisions[material]==nil {collisionOrder.append(material)}
                if collisions[material]==nil || impact>collisions[material]!.impact {
                    collisions[material]=Collision(material:material,impact:impact,point:point,normal:normal)
                }
            }
        }
        let currentBody=body(current),previousBody=body(previous),impact=state.intensity
        if !collisions.isEmpty {onCollisions?(collisionOrder.compactMap{collisions[$0]},currentBody)}
        state.process(body:currentBody,ticks:50*delta,drowning:drowning,random:random)
        let q=current.rotation,rotation=simd_quatd(ix:Double(q.imag.x),iy:Double(q.imag.y),iz:Double(q.imag.z),r:Double(q.real))
        state.swing(body:currentBody,previous:.init(move:previousBody.move,turn:previousBody.turn),current:.init(move:currentBody.move,turn:currentBody.turn),
            hinge:{[hinges] index in hinges[index].map{rotation.act($0)}},ticks:50*delta,intensity:impact,random:random)
        if state.events.contains(where:{$0.type == "blow"}) {state.blowUp(random:random)}
        if !state.events.isEmpty {onEvents?(state.events,currentBody);state.events.removeAll()}
    }
}
