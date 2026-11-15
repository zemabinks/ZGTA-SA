import Foundation
import simd

/// Original module3104 nine-point buoyancy, boat thrust/drag and car sinking.
/// The surface providers separate base water from wave displacement exactly
/// as the public browser's waterLevel/sea.rise boundary does.
final class NativeVehicleBuoyancy {
    typealias V=SIMD3<Double>
    struct Parameters {
        let thrustY:Double,thrustZ:Double,thrustAppZ:Double,aqPlaneForce:Double,aqPlaneLimit:Double,aqPlaneOffset:Double,waveAudio:Double
        let moveRes:[Double],turnRes:[Double]
        init?(_ values:[String:Any]) {
            func n(_ key:String)->Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
            guard let move=values["moveRes"] as? [Double],move.count==3,
                  let turn=values["turnRes"] as? [Double],turn.count==3 else { return nil }
            thrustY=n("thrustY");thrustZ=n("thrustZ");thrustAppZ=n("thrustAppZ");aqPlaneForce=n("aqPlaneForce")
            aqPlaneLimit=n("aqPlaneLimit");aqPlaneOffset=n("aqPlaneOffset");waveAudio=n("waveAudio");moveRes=move;turnRes=turn
        }
    }
    struct Wave { var height:Double;var normal:V }
    var waterLevel:(V)->Double?={ _ in nil }
    var wave:((V)->Wave)?
    private let parameters:Parameters?
    private let table:NativeVehicleDynamics.Table
    private let boundsMin:V,boundsMax:V,minimum:V,maximum:V,half:V
    private let extent:Double,radius:Double,initialLift:Double
    private let seaplane:Bool,hover:Bool,boat:Bool
    private var lift:Double,steerInput=0.0,brakeInput=0.0,previousImmersion=0.0,slam=0.0
    private(set) var touching=false,onWater=false,dead=false,upsideDown=false,propeller=false,wake=false
    private(set) var rudder=0.0,gas=0.0,immersion=0.0
    var lost:Bool { dead || upsideDown }
    var hasBoat:Bool { parameters != nil }
    init?(table:NativeVehicleDynamics.Table,minimum:V,maximum:V,parameters:Parameters?) {
        self.table=table;self.parameters=parameters;boundsMin=minimum;boundsMax=maximum
        seaplane=table.model==460;hover=table.model==539;boat=parameters != nil && !seaplane
        var low=minimum,high=maximum
        if boat {
            let tuning=Self.hulls[table.model] ?? V(1.05,0.9,0)
            low.y *= tuning.y;low.z -= tuning.z;high.y *= tuning.x
        } else if seaplane { low.x *= 0.3;high.x *= 0.3;low.y=high.y*(-0.6);high.y *= 1.4;low.z -= 0.1 }
        self.minimum=low;self.maximum=high;half=(high-low)/2
        extent=high.z-low.z;radius=max(half.x,max(half.y,half.z))
        guard extent>0,radius>0 else { return nil }
        initialLift=100/(table.submerged != 0 ? table.submerged:100)*0.008*table.mass;lift=initialLift
    }
    @discardableResult func takeSlam()->Double { let value=slam;slam=0;return value }
    private static let hulls:[Int:V]=[446:V(0.9,0.9,0),452:V(1.25,0.83,0),453:V(1,0.9,0),493:V(1,0.9,0),454:V(1.3,0.82,0.2),472:V(1.1,0.9,0.3),473:V(1.3,0.9,0.2),484:V(1.1,0.9,0),595:V(1.25,0.8,0.1)]
    private static let speedboat=[[0.7,0.9,0.7],[0.95,1,0.95],[0.6,0.7,0.6]]
    private static let dinghy=[[0.65,0.85,0.65],[0.85,1.1,0.85],[0.65,0.95,0.65]]
    private static let defaultWeights=[[0.75,0.9,0.75],[0.95,1,0.95],[0.4,0.7,0.4]]
    private var weights:[[Double]] {
        if [446,452,493,595].contains(table.model) { return Self.speedboat }
        if [472,473].contains(table.model) { return Self.dinghy }
        if table.model==484 { return [[0.55,0.95,0.55],[0.75,1.1,0.75],[0.3,0.8,0.3]] }
        return Self.defaultWeights
    }
    private func surface(_ point:V)->Wave? {
        guard let level=waterLevel(point) else { return nil }
        if let wave { let value=wave(point);return Wave(height:level+value.height,normal:value.normal) }
        return Wave(height:level,normal:V(0,1,0))
    }
    private func buoyancy(_ body:NativeVehicleForces,_ step:Double)->(Double,V) {
        let scale=1/(9*extent),up=V(0,1,0),weights=self.weights
        var force=0.0,counter=1.0,weighted=V.zero;immersion=0;touching=false
        for across in 0..<3 { for along in 0..<3 {
            let x=minimum.x+half.x*Double(across),y=minimum.y+half.y*Double(along)
            let relative=body.axes(x,y,0),point=body.place+relative
            guard let water=surface(point) else { continue }
            let height=NativeVehicleForces.clamp(water.height-point.y,minimum.z,maximum.z),depth=height-minimum.z
            if depth<=0 { continue };touching=true
            let weight=parameters != nil ? weights[along][across]:1,adjusted=depth-(1-weight)
            if adjusted<0 { continue }
            let amount=boat ? pow(adjusted*weight,2):adjusted
            immersion += amount
            let centre=V(x*half.x/radius,y*half.y/radius,(height+minimum.z)*half.z/radius/2)
            weighted=weighted*(1-1/counter)+centre*(amount/counter);counter += 1
            if parameters==nil {
                let impulse=step*lift*amount*scale;force += impulse;body.pushTurn(up*impulse,at:relative)
            } else {
                let normal=(water.normal+up*2)/3
                let impulse=max(0,1-simd_dot(body.speed(at:relative),normal)*table.damping)*step*lift*amount*scale
                force += impulse;body.pushTurn(normal*impulse,at:body.axes(x,y,height))
            }
        } }
        immersion *= scale
        return (force,body.axes(weighted.x,weighted.y,weighted.z))
    }
    func step(_ body:NativeVehicleForces,input:NativeVehicleDynamics.Input,step:Double,wheels:Int) {
        let level=waterLevel(body.place)
        if level==nil || body.place.y+minimum.z-radius-2>level! {
            if touching && parameters==nil { lift=initialLift }
            touching=false;onWater=false;propeller=false;upsideDown=false;wake=false;previousImmersion=0
            if parameters==nil && level==nil { dead=false };return
        }
        let (force,centre)=buoyancy(body,step)
        if let parameters { boatStep(body,input,step,force,centre,parameters) }
        else if touching {
            var share=force/(0.008*step*table.mass)
            if 0.008*table.mass>lift { share *= 0.008400000000000001*table.mass/lift }
            let damping=pow(max(0.5,1-share/20),step),hovering=hover && body.up.y>0.3
            if !hovering { body.move *= damping;body.turn *= damping }
            body.pushMove(V(0,1,0)*force)
            if hovering { onWater=false;return }
            onWater=share>=1 || share>0.6 && wheels<4
            if onWater {
                body.move.y=max(-0.1,body.move.y)
                if lift>0.0064*table.mass { lift -= 0.000008*table.mass*step }
                if lift<0.008*table.mass { dead=true }
            }
        } else { onWater=false;lift=initialLift }
    }
    private func boatStep(_ body:NativeVehicleForces,_ input:NativeVehicleDynamics.Input,_ step:Double,_ force:Double,_ centre:V,_ parameters:Parameters) {
        let worldUp=V(0,1,0),mass=table.mass
        onWater=force>step*mass*0.0008
        upsideDown=onWater && body.up.y<(-0.6) && abs(body.move.x)<0.05 && abs(body.move.z)<0.05
        if boat && onWater && body.up.y>0 && step>0 { slam=max(slam,floor((immersion-previousImmersion)/step*10000)*parameters.waveAudio) }
        previousImmersion=immersion
        let flipped=seaplane && body.up.y<(-0.5) && abs(body.move.x)<0.2 && abs(body.move.z)<0.2
        body.pushMove(worldUp*(force*(flipped ? 0.03:1)))
        let throttle=NativeVehicleForces.clamp(input.throttle,-1,1)
        if seaplane { gas=throttle<(-0.05) ? 0.3*throttle:max(0,throttle) }
        else {
            brakeInput=NativeVehicleForces.clamp(brakeInput+((input.brake ?? max(0,-throttle))-brakeInput)*(1-pow(0.9,step)),0,1)
            if brakeInput>=0.05 { gas = -0.3*brakeInput }
            else { brakeInput=0;gas=NativeVehicleForces.clamp(input.accelerate ?? max(0,throttle),0,1) }
        }
        steerInput=NativeVehicleForces.clamp(steerInput+(-input.steer-steerInput)*min(1,0.2*step),-1,1)
        rudder=table.lock*Double.pi/180*steerInput*abs(steerInput)
        if onWater && body.up.y>0 && (seaplane || gas>0.05) {
            let amount=min(simd_length_squared(body.move)*parameters.aqPlaneForce*force*0.5*(seaplane ? gas+1:gas),step*parameters.aqPlaneLimit*mass/125)
            let lift=body.up*amount;body.pushMove(lift);body.pushTurn(lift,at:centre-body.forward*parameters.aqPlaneOffset)
        }
        propeller=false;wake=false
        if body.up.y>(-0.6) {
            let speed=simd_dot(body.move,body.forward),motion=abs(gas)>0.05 ? 1:hypot(body.move.x,body.move.z)
            if abs(gas)>0.05 || motion>0.01 {
                wake=boat && onWater && motion>0.05
                let steeringShare=NativeVehicleForces.clamp(1-speed*table.bias*(input.handbrake ? 0.5:1),0,1)
                let sine=sin(-steeringShare*rudder),cosine=cos(-steeringShare*rudder)
                let point=body.axes(0,boundsMin.y*parameters.thrustY,boundsMin.z*parameters.thrustZ),worldPoint=body.place+point
                if let water=surface(worldPoint),worldPoint.y-0.5<water.height {
                    propeller=true
                    let depth=min(pow(water.height-worldPoint.y+0.5,2),1),power=abs(gas)
                    var rudderOnly=power<0.01 || seaplane
                    if !rudderOnly {
                        rudderOnly=power<0.5
                        var thrust=body.axes(-sine,cosine,-abs(rudder))*(depth*gas*0.0032*table.acceleration*mass)
                        if thrust.y>0.2 { thrust.y=pow(1.2-thrust.y,2)+0.2 }
                        thrust *= step;body.pushMove(thrust)
                        body.pushTurn(thrust,at:point-body.up*parameters.thrustAppZ)
                        body.pushTurn(body.right*(-simd_dot(thrust,body.right)*table.traction),at:body.up)
                    }
                    if rudderOnly {
                        var turningForce: Double=Swift.min(speed*table.loss,0.01*body.turnMass)
                        if power>0.01 { turningForce *= (0.55-power)*2.6 }
                        if gas<0 && turningForce>0 || gas>0 && turningForce<0 { turningForce = -turningForce }
                        let sideways: Double = -sine*turningForce
                        var rudderForce=body.axes(sideways,0,0)
                        rudderForce *= depth*step
                        body.pushMove(rudderForce);body.pushTurn(rudderForce,at:point)
                        body.pushTurn(body.right*(-(max(step,0.01)/max(steeringShare,0.01)*turningForce*sine*0.75)),at:body.up)
                    }
                }
            }
        }
        if table.suspBias != 0 {
            let side=simd_cross(body.forward,worldUp),force = -simd_dot(side,body.move)*table.suspBias*step*immersion*mass*0.1
            body.pushMove(V(side.x+0.3*body.forward.x,0,side.z+0.3*body.forward.z)*force)
        }
        if input.handbrake {
            let speed=simd_dot(body.move,body.forward)
            if speed>0 { body.pushMove(body.forward*(-speed*table.lower*step*immersion*mass*0.1)) }
        }
        if onWater {
            let speed=simd_dot(body.move,body.forward)
            let resistance=1/abs(immersion*immersion*table.springs*(mass/1000)*(seaplane ? 30:1)*(speed*speed+0.05)+1)
            let x=pow(parameters.moveRes[0]*resistance,0.5*step),y=pow(parameters.moveRes[1]*resistance,0.5*step),z=pow(parameters.moveRes[2]*resistance,0.5*step)
            let local=V(simd_dot(body.move,body.right)*x,speed*y,simd_dot(body.move,body.up)*z)
            body.move=body.axes(local.x,local.y,local.z)
            body.pushTurn(body.forward*((y-1)*local.y*mass),at:-body.up)
            body.move.y *= body.move.y<=0 ? (1-z)*0.5+z:z
        }
        let roll=simd_dot(body.turn,body.right)
        let local=V(roll,simd_dot(body.turn,body.forward)*pow(parameters.turnRes[1],step),simd_dot(body.turn,body.up)*pow(parameters.turnRes[2],step))
        body.turn=body.axes(local.x,local.y,local.z)
        body.turn += body.right*(pow(parameters.turnRes[0],step)/(roll*roll*1000+1)*roll-roll)
    }
}
