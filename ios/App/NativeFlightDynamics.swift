import Foundation
import simd

/// Literal normalized-force translation of archived module89888. It supports
/// the original plane, helicopter, Hydra nozzle and Vortex hover branches.
final class NativeFlightDynamics {
    typealias V=SIMD3<Double>
    struct Parameters {
        let thrust:Double,thrustFallOff:Double,yaw:Double,yawStab:Double,sideSlip:Double
        var roll:Double,rollStab:Double,pitch:Double,pitchStab:Double,formLift:Double,attackLift:Double
        let gearUpR:Double,gearDownL:Double,windMult:Double,moveRes:Double
        var turnRes:[Double],speedRes:[Double]
        init?(_ values:[String:Any]) {
            func n(_ key:String)->Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
            guard let turnRes=values["turnRes"] as? [Double],turnRes.count==3,
                  let speedRes=values["speedRes"] as? [Double],speedRes.count==3 else { return nil }
            thrust=n("thrust");thrustFallOff=n("thrustFallOff");yaw=n("yaw");yawStab=n("yawStab");sideSlip=n("sideSlip")
            roll=n("roll");rollStab=n("rollStab");pitch=n("pitch");pitchStab=n("pitchStab");formLift=n("formLift");attackLift=n("attackLift")
            gearUpR=n("gearUpR");gearDownL=n("gearDownL");windMult=n("windMult");moveRes=n("moveRes")
            self.turnRes=turnRes;self.speedRes=speedRes
        }
    }
    let kind:String
    let parameters:Parameters
    let jets:Bool
    let hover:Bool
    let rearExtent:Double
    private(set) var rotor=0.0
    private(set) var gearUp=false
    private(set) var nozzle=0.0
    private(set) var throttle=0.0
    private var propeller=0.0,pitchInput=0.0,rollInput=0.0,yawInput=0.0
    var turning:Double { kind=="heli" ? rotor:propeller }
    var drag:Double { kind=="plane" && gearUp ? parameters.gearUpR:1 }
    init(parameters:Parameters,kind:String,rearExtent:Double,jets:Bool=false,hover:Bool=false) {
        self.parameters=parameters;self.kind=kind;self.rearExtent=rearExtent;self.jets=jets;self.hover=hover
        nozzle=jets ? 5000:0
    }
    func setGear(_ value:Bool) { gearUp=value }
    func setTurning(_ value:Double) {
        if kind=="heli" { rotor=Self.clamp(value,0,0.22) }
        else { propeller=Self.clamp(value,0,0.34) }
    }
    private static func clamp(_ v:Double,_ low:Double,_ high:Double)->Double { min(high,max(low,v)) }
    private func stopTurning(_ amount:Double,_ step:Double)->Double {
        if kind=="heli" { return max(0,min(amount,0.22)-0.00055*step) }
        let limited=min(amount,0.34);return max(0,limited-(limited>0.18 ? 0.003:0.001)*step)
    }
    private func dampAxes(_ body:NativeVehicleForces,_ step:Double,_ speed:Double,_ values:Parameters) {
        let axes=[body.right,body.forward,body.up], components=axes.map { simd_dot(body.turn,$0) }
        body.turn = .zero
        for index in 0..<3 {
            let component=components[index],resistance=values.speedRes[index]
            let damped:Double
            if resistance<=0 { damped=component*pow(values.turnRes[index],step*speed) }
            else { damped=component+(pow(values.turnRes[index]/(component*component*resistance+1),step)*component-component)*speed }
            body.turn += axes[index]*damped
        }
        let moveLength=simd_length(body.move),turnLength=simd_length(body.turn)
        if moveLength>1.5 { body.move *= 1.5/moveLength }
        if turnLength>0.2 { body.turn *= 0.2/turnLength }
    }
    private func helicopter(_ body:NativeVehicleForces,_ input:NativeVehicleDynamics.Input,_ step:Double,direction:V?=nil) {
        let e=parameters
        var controls=e
        if direction != nil {
            controls.pitch=0.001;controls.roll=0.001;controls.formLift=0.5;controls.attackLift=0.001
            controls.turnRes=[0.992,0.992,0.992];controls.speedRes=[2,2,7]
        }
        body.move *= pow(e.moveRes,step)
        if let direction {
            var speed=simd_dot(body.move,direction);if speed>0 { speed *= 2 }
            body.move.y += (0.5-body.move.y)*0.008*step
            let power=Self.clamp(input.throttle,-1,1)*e.thrust+0.45-speed*e.thrustFallOff
            body.move += direction*(0.008*power*step)
        } else {
            var power=Self.clamp(input.throttle,-1,1);if power<0 { power *= 2 }
            power=e.thrust*power+0.95-e.thrustFallOff*simd_dot(body.move,body.up)
            body.move += body.up*(0.008*power*step)
        }
        func attitude(_ value:Double)->Double {
            body.up.y>0 ? Self.clamp(value,-controls.formLift,controls.formLift) : value<0 ? -controls.formLift:controls.formLift
        }
        body.torque(body.up,-attitude(body.right.y)*controls.attackLift*step,at:body.right)
        body.torque(body.up,-attitude(body.forward.y)*controls.attackLift*step,at:body.forward)
        let pitch=Self.clamp(input.pitch,-1,1),roll=Self.clamp(input.roll,-1,1),yaw=Self.clamp(input.yaw,-1,1)
        body.torque(body.up,pitch*controls.pitch*step,at:body.forward)
        body.torque(body.up,-roll*controls.roll*step,at:body.right)
        let side = -simd_dot(body.move,body.right),signedSquared=side*abs(side)
        body.move += body.right*(e.sideSlip*signedSquared*step)
        body.torque(body.right,(e.yawStab*signedSquared+e.yaw*yaw)*step,at:-body.forward)
        body.torque(body.forward,yaw*e.yaw*step,at:body.right)
        if direction != nil { dampAxes(body,step,simd_length(body.move)+1,controls);return }
        let resistance=e.turnRes.map { pow($0,step) }
        var local=body.quaternion.conjugate.act(body.turn)
        let yawSpeed=local.y,damping=pow(resistance[2]/(e.speedRes[2]*yawSpeed*yawSpeed+1),step)
        local=V(local.x*resistance[0],yawSpeed*damping,local.z*resistance[1])
        body.turn=body.quaternion.act(local)
        body.torque(body.right,-(yawSpeed*damping-yawSpeed),at:body.forward)
    }
    private func plane(_ body:NativeVehicleForces,_ input:NativeVehicleDynamics.Input,_ step:Double,direction:V?=nil) {
        let e=parameters
        var roll=Self.clamp(input.roll,-1,1),pitch = -Self.clamp(input.pitch,-1,1)
        let angle=atan2(-pitch,roll),quarter=Double.pi/4
        var square=1.0
        if roll != 0 || pitch != 0 {
            if angle>(-quarter) && angle<=quarter { square=1/cos(angle) }
            else if angle>quarter && angle<=3*quarter { square=1/cos(angle-Double.pi/2) }
            else if angle>3*quarter { square=1/cos(angle-Double.pi) }
            else if angle<=(-3*quarter) { square=1/cos(angle+Double.pi) }
            else { square=1/cos(angle+Double.pi/2) }
        }
        roll *= square;pitch *= square
        let yaw=Self.clamp(input.yaw,-1,1),speed=simd_dot(body.move,body.forward),throttle=Self.clamp(input.throttle,-1,1)
        var power=speed>0 || throttle>0 ? throttle*e.thrust:min(throttle-8*e.thrustFallOff*speed,0)*e.thrust
        if hover {
            power=throttle>0 ? throttle*e.thrust:throttle<0 && speed<0.02 ? min(throttle-7.76*speed,0)*e.thrust:0
            if throttle>0 && speed>0 && e.thrustFallOff<1 {
                let falloff=e.thrustFallOff
                power *= max(0,1-(falloff<0 ? 3*pow(speed+falloff,2):0.65*pow(speed-falloff,2)))
            }
        }
        if direction != nil {
            let ground=throttle<=0 && body.wheels>0
            power=ground ? (throttle != 0 && speed<0.02 ? min(throttle-7.76*speed,0)*e.thrust:0):(1+throttle)*e.thrust*0.5
            if !ground && speed>0 && e.thrustFallOff<1 {
                let falloff=e.thrustFallOff
                power *= max(0,1-(falloff<0 ? 3*pow(speed+falloff,2):0.65*pow(speed-falloff,2)))
            }
        }
        body.move += (direction ?? body.forward)*(0.008*power*step)
        let side = -simd_dot(body.move,body.right)
        body.move += body.right*(e.sideSlip*side*abs(side)*step)
        let rear=body.forward*rearExtent,tailSpeed=body.speed(at:rear),tailSide = -simd_dot(tailSpeed,body.right)
        let steeringSpeed=hover ? (speed>0 ? max(speed,power):min(speed,power)):speed
        body.pushTurn(body.right*((e.yawStab*tailSide*abs(tailSide)+e.yaw*yaw*steeringSpeed)*body.turnMass*step),at:rear)
        body.torque(body.right,roll*e.roll*speed*step,at:body.up)
        var horizon=V(-body.forward.z,0,body.forward.x);if body.up.y<=0 { horizon = -horizon }
        let stabilization=e.rollStab*(body.right.y>0 ? -1.0:1)*(1-simd_dot(body.right,horizon))*(1-abs(body.forward.y))*(direction != nil ? 0.5:1)
        body.torque(body.right,stabilization*step,at:body.up)
        let tailVertical = -simd_dot(tailSpeed,body.up)
        body.pushTurn(body.up*((e.pitchStab*tailVertical*abs(tailVertical)+e.pitch*pitch*speed)*body.turnMass*step),at:rear)
        let vertical=simd_dot(body.move,body.up)/max(0.01,simd_length(body.move))
        let form=e.formLift*(gearUp ? 1:e.gearDownL)
        let attack=direction != nil ? -asin(Self.clamp(vertical,-1,1)):-vertical
        body.move += body.up*((form+e.attackLift*attack)*speed*speed*step)
        if direction != nil { dampAxes(body,step,2*simd_length(body.move),e);return }
        let resistance=e.turnRes.map { pow($0,step) }
        var local=body.quaternion.conjugate.act(body.turn);let rollSpeed = -local.z
        local=V(local.x*resistance[0],local.y*resistance[2],local.z)
        body.turn=body.quaternion.act(local)
        body.turn += body.forward*(rollSpeed/(e.speedRes[1]*rollSpeed*rollSpeed+1)*resistance[1]-rollSpeed)
        let moveLength=simd_length(body.move),turnLength=simd_length(body.turn)
        if moveLength>1.5 { body.move *= 1.5/moveLength };if turnLength>0.2 { body.turn *= 0.2/turnLength }
    }
    func step(_ body:NativeVehicleForces,input:NativeVehicleDynamics.Input,step:Double) {
        if jets { nozzle=Self.clamp(nozzle+input.jets*25*step,0,5000) }
        throttle=input.nobody ? 0:Self.clamp(input.throttle,-1,1)
        let share=min(1,0.2*step)
        pitchInput += (Self.clamp(input.pitch,-1,1)-pitchInput)*share
        rollInput += (Self.clamp(input.roll,-1,1)-rollInput)*share
        yawInput += (Self.clamp(input.yaw,-1,1)-yawInput)*share
        var controls=input;controls.pitch=pitchInput;controls.roll=rollInput;controls.yaw=yawInput
        if jets {
            let target=input.nobody ? 0:0.22*(0.45+0.55*max(0,controls.throttle))
            rotor += Self.clamp(target-rotor,-0.004*step,0.004*step)
            if input.nobody { propeller=stopTurning(propeller,step);return }
            let gas=Self.clamp(controls.throttle,-1,1)
            propeller += (0.18+gas*(gas>0 ? 0.34-0.18:0.18-0.05)-propeller)*min(1,0.01*step)
            let angle=nozzle/5000*(Double.pi/2),direction=body.up*sin(angle)+body.forward*cos(angle)
            if nozzle>3000 { helicopter(body,controls,step,direction:direction) }
            else { plane(body,controls,step,direction:direction) }
        } else if kind=="heli" {
            if input.nobody { rotor=stopTurning(rotor,step);return }
            if rotor<0.22 { rotor=min(0.22,rotor+0.001*step) }
            let moving=abs(body.move.x)>0.02 || abs(body.move.y)>0.02 || abs(body.move.z)>0.02
            if rotor>0.15 && (body.wheels<4 || controls.throttle>0 || moving) { helicopter(body,controls,step) }
        } else {
            let target=0.22*(0.45+0.55*max(0,controls.throttle))
            rotor += Self.clamp(target-rotor,-0.004*step,0.004*step)
            let gas=Self.clamp(controls.throttle,-1,1)
            if input.nobody { propeller=stopTurning(propeller,step) }
            else { propeller += (0.18+gas*(gas>0 ? 0.34-0.18:0.18-0.05)-propeller)*min(1,0.01*step) }
            plane(body,controls,step)
        }
    }
}
