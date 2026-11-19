import Foundation
import simd

/// Original19737.G/beforeStep/ea/el physics for a parked vehicle promoted to
/// local simulation. No contact-event queue is consumed by this controller.
final class NativeUnattendedVehicle {
    typealias V=SIMD3<Double>
    struct Pose {var position:V;var rotation:simd_quatd}
    let world:SwiftRapierWorld
    let definition:NativeGroundVehicle.Definition
    let body:SwiftRapierWorld.BodyID
    private(set) var colliders:Set<SwiftRapierWorld.ColliderID> = []
    let car:NativeVehicleDynamics?
    let bike:NativeBikeDynamics?
    let damage:NativeVehicleDamage
    var fallen=false
    var onSparks:((NativeVehicleDamage.Event,NativeVehicleDamage.Body)->Void)?
    var random:()->Double={Double.random(in:0..<1)}
    private(set) var speedWas:V?
    private(set) var output:NativeVehicleDynamics.Output?
    private(set) var frontSpin=0.0,rearSpin=0.0
    var mass:Double {bike?.mass ?? car!.mass}
    var turnMass:Double {bike?.turnMass ?? car!.turnMass}
    var centre:V {bike?.centre ?? car!.centre}
    var rotor:Double {car?.flight?.turning ?? 0}
    var gearUp:Bool {car?.flight?.gearUp ?? false}
    init?(world:SwiftRapierWorld,definition:NativeGroundVehicle.Definition,pose:Pose,
          linear:V?=nil,angular:V?=nil,health:Double,damage:String,fallen:Bool=false,rotor:Double=0,gearUp:Bool=false,
          waterLevel:@escaping(V)->Double?={_ in nil},waterWave:@escaping(V)->NativeVehicleBuoyancy.Wave={_ in .init(height:0,normal:V(0,1,0))}) {
        guard definition.configuration.kind != "train" else{return nil}
        self.world=world;self.definition=definition
        if var configuration=definition.bikeConfiguration {configuration.pedalled=false;bike=NativeBikeDynamics(configuration:configuration);car=nil}
        else {bike=nil;car=NativeVehicleDynamics(configuration:definition.configuration)}
        guard bike != nil || car != nil else{return nil}
        if let car {
            if let parameters=definition.flightParameters {
                car.flight=NativeFlightDynamics(parameters:parameters,kind:definition.configuration.kind,rearExtent:definition.rearExtent,
                    jets:definition.configuration.table.model==520,hover:definition.configuration.table.model==539)
                car.flight?.setTurning(rotor)
                car.flight?.setGear(gearUp && [476,519,577,520,553,592].contains(definition.configuration.table.model))
            }
            car.buoyancy=NativeVehicleBuoyancy(table:definition.configuration.table,minimum:definition.buoyancyMinimum,maximum:definition.buoyancyMaximum,parameters:definition.boatParameters)
            car.buoyancy?.waterLevel=waterLevel;car.buoyancy?.wave=waterWave
        }
        let mass=SwiftRapierWorld.Mass(value:Float(bike?.mass ?? car!.mass),centre:SIMD3<Float>(bike?.centre ?? car!.centre),turnMass:Float(bike?.turnMass ?? car!.turnMass))
        let rotation=simd_quatf(vector:SIMD4<Float>(pose.rotation.vector))
        guard let body=world.addBody(position:SIMD3<Float>(pose.position),rotation:rotation,mass:mass) else{return nil}
        self.body=body
        for shape in definition.chassis {
            let collider:SwiftRapierWorld.ColliderID?
            if shape.kind=="sphere" {collider=world.addSphere(radius:shape.radius,body:body,position:shape.centre,friction:shape.friction,restitution:shape.restitution)}
            else {collider=world.addBox(halfExtents:shape.halfExtents,body:body,position:shape.centre,friction:shape.friction,restitution:shape.restitution)}
            guard let collider else{world.removeBody(body);return nil}
            world.setColliderGroups(collider,collision:8454127,solver:33554944)
            world.setColliderPiece(collider,piece:Int32(shape.piece));world.setColliderSurface(collider,surface:2,material:63)
            colliders.insert(collider)
        }
        world.setBrowserRotation(body,rotation:rotation)
        if linear != nil || angular != nil {world.setVelocities(body,linear:SIMD3<Float>(linear ?? .zero),angular:SIMD3<Float>(angular ?? .zero))}
        let table=definition.configuration.table
        self.damage=NativeVehicleDamage(mass:table.mass,collisionDamage:definition.collisionDamage,maxX:definition.damageWidth,flags:table.modelFlags,model:table.model)
        self.damage.load(health:health,text:damage);self.damage.events.removeAll()
        car?.setTyres(self.damage.wheels);bike?.setTyres(self.damage.wheels)
        self.fallen=definition.configuration.kind=="bike" && (fallen || Self.toppled(pose.rotation) || (linear.map{simd_length($0)>1.5} ?? false))
    }
    func dispose(){world.removeBody(body);colliders.removeAll()}
    /// Presentation counters survive a kinematic/dynamic owner handoff. They
    /// do not change wheel forces, angular velocity or the chassis transform.
    func restoreWheelSpin(front:Double,rear:Double) {
        frontSpin=front.isFinite ? front:0;rearSpin=rear.isFinite ? rear:0
    }
    static func toppled(_ q:simd_quatd)->Bool {abs(q.act(V(1,0,0)).y)>0.479425538604203 || q.act(V(0,1,0)).y<0}
    static func rotation(heading:Double,pitch:Double,roll:Double)->simd_quatd {
        let c1=cos(pitch/2),c2=cos(-heading/2),c3=cos(-roll/2),s1=sin(pitch/2),s2=sin(-heading/2),s3=sin(-roll/2)
        return .init(ix:s1*c2*c3+c1*s2*s3,iy:c1*s2*c3-s1*c2*s3,iz:c1*c2*s3-s1*s2*c3,r:c1*c2*c3+s1*s2*s3)
    }
    static func euler(_ q:simd_quatd)->(pitch:Double,heading:Double,roll:Double) {
        let x=q.imag.x,y=q.imag.y,z=q.imag.z,w=q.real,x2=x+x,y2=y+y,z2=z+z
        let m23=y*z2-w*x2,pitch=asin(-min(1,max(-1,m23)))
        if abs(m23)<0.9999999 {return(pitch,atan2(x*z2+w*y2,1-(x*x2+y*y2)),atan2(x*y2+w*z2,1-(x*x2+z*z2)))}
        return(pitch,atan2(-(x*z2-w*y2),1-(y*y2+z*z2)),0)
    }
    var state:SwiftRapierWorld.BodyState? {world.bodyState(body)}
    static func quaternion(_ q:simd_quatf)->simd_quatd {.init(ix:Double(q.imag.x),iy:Double(q.imag.y),iz:Double(q.imag.z),r:Double(q.real))}
    static func controls(velocity:V,wetness:Double,held:Bool,fallen:Bool)->NativeVehicleDynamics.Input {
        var input=NativeVehicleDynamics.Input();input.nobody=true;input.abandoned = !held;input.riderless=fallen && !held
        let brake=held ? 0:simd_length(velocity)<5 ? 0.2:0.0
        input.pedals=SIMD2(0,brake);input.drive = .init(throttle:0,steer:0,handbrake:false,pedals:SIMD2(0,brake));input.wetness=wetness
        return input
    }
    func beforeStep(delta:Double,wetness:Double=0,held:Bool=false) {
        guard let current=state else{return}
        speedWas=V(current.linearVelocity)
        let input=Self.controls(velocity:speedWas!,wetness:wetness,held:held,fallen:fallen)
        let state=NativeVehicleDynamics.BodyState(position:V(current.position),rotation:Self.quaternion(current.rotation),linearVelocity:V(current.linearVelocity),angularVelocity:V(current.angularVelocity))
        let ray:(V,V,Double)->NativeVehicleDynamics.RayHit? = {[world,body] origin,direction,distance in
            guard let hit=world.raycast(origin:SIMD3<Float>(origin),direction:SIMD3<Float>(direction),distance:Float(distance),excludingBody:body) else{return nil}
            return .init(distance:Double(hit.distance),normal:V(hit.normal),surface:hit.coarseSurface,material:hit.coarseMaterial)
        }
        let gravity=world.legacyGravity.map(Double.init)
        let result=bike?.step(delta:delta,input:input,body:state,gravity:gravity,raycast:ray) ?? car!.step(delta:delta,input:input,body:state,gravity:gravity ?? 0.008,raycast:ray)
        output=result;world.setVelocities(body,linear:SIMD3<Float>(result.linearVelocity),angular:SIMD3<Float>(result.angularVelocity))
    }
    @discardableResult func shove(direction:SIMD2<Double>,point:V,speed:Double)->Double {
        guard mass>0,turnMass>0,let current=state else{return 0}
        let rotation=Self.quaternion(current.rotation),arm=point-(rotation.act(centre)+V(current.position)),axis=V(direction.x,0,direction.y)
        let velocity=V(current.linearVelocity),spin=V(current.angularVelocity)
        let moving=velocity.x*direction.x+velocity.z*direction.y+(spin.y*arm.z-spin.z*arm.y)*direction.x+(spin.x*arm.y-spin.y*arm.x)*direction.y
        guard speed>moving else{return 0}
        let damp=1/(max(0,mass-2000)/5000+1),cross=simd_cross(arm,axis)
        let effective=1/(simd_length_squared(cross)/(damp*turnMass)+1/(damp*mass))
        let bounce=((definition.configuration.kind=="boat" ? 0.1:0.05)+0.05)/2
        let force=effective*(1+bounce)*70*(speed-moving)/(effective+70)/damp
        world.applyImpulse(SIMD3<Float>(axis*force),to:body,at:SIMD3<Float>(point))
        if let previous=speedWas {speedWas=previous+axis*(force/mass)}
        return force
    }
    /// Originalea deliberately uses the old displayed group pose for axes and
    /// damage origin, while velocity/support position come from the new body.
    func afterStep(delta:Double,reference:Pose) {
        guard let current=state else{return}
        let velocity=V(current.linearVelocity),spin=V(current.angularVelocity)
        let gravity=world.legacyGravityAcceleration ?? 18
        var difference=speedWas.map{velocity-$0} ?? V(0,-gravity*delta,0);difference.y += gravity*delta
        let length=simd_length(difference),intensity=definition.rigidMass*length/50
        let right=reference.rotation.act(V(1,0,0)),up=reference.rotation.act(V(0,1,0)),forward=reference.rotation.act(V(0,0,-1))
        if intensity>0,simd_length_squared(difference)>0.000001 {
            let normal=difference/length,extent=abs(simd_dot(normal,forward))*definition.length/2+abs(simd_dot(normal,right))*definition.width/2
            damage.record(intensity:intensity,piece:0,point:V(current.position)-normal*extent,normal:normal,building:normal.y>0.7)
        }
        let frame=NativeVehicleDamage.Body(position:reference.position+up*definition.configuration.origin,right:right,forward:forward,up:up,move:velocity/50,turn:spin/50)
        damage.process(body:frame,ticks:50*delta,random:random)
        for event in damage.events where event.type=="sparks" {onSparks?(event,frame)}
        damage.events.removeAll()
        if definition.configuration.kind=="car" || definition.configuration.kind=="trailer",let output {
            for front in [true,false] {
                let axle=output.wheels.filter{($0.index==0 || $0.index==2)==front}
                let speed=axle.isEmpty ? 0:axle.reduce(0){$0+$1.spin}/Double(axle.count)
                if front {frontSpin -= speed*delta/0.36}else{rearSpin -= speed*delta/0.36}
            }
        }
    }
}
