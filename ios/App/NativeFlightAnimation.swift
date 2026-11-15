import Foundation
import simd

/// Original public 54205.ap presentation state. Physics and networking supply
/// the 13-state flight record; this retains independent clip clocks, canopy
/// opening/landing, jet nozzle articulation and the original leg pendulum.
final class NativeFlightAnimation {
    struct Input { var state:Int;var pitch:Double=0;var roll:Double=0 }
    struct Canopy { var clip:String;var time:Double;var scale:Double;var pitch:Double;var roll:Double;var landed:Bool;var easing:Double;var visible:Bool }
    struct Jet { var visible:Bool;var pitch:Double;var leftRoll:Double;var rightRoll:Double;var thrust:Double;var sound:String }
    struct Frame {
        var blends:[NativeSkeletalBlend]=[]
        var figurePitch:Double=0
        var figureRoll:Double=0
        var figureControlled=false
        var bend=SIMD2<Double>.zero
        var canopy:Canopy?
        var jet:Jet?
    }
    private let duration:(String)->Double?
    private var amount:Double=0,previous=0,pitch:Double=0,roll:Double=0
    private var weights=Array(repeating:0.0,count:9),times=Array(repeating:0.0,count:9)
    private var canopyName:String?,canopyTime:Double=0,canopyOpening:Double=0
    private var thrust:Double=0,figureWasControlled=false
    private var previousPosition:SIMD3<Double>?,velocity=SIMD3<Double>.zero
    private var forward:Double=0,side:Double=0,forwardSpeed:Double=0,sideSpeed:Double=0
    private var jetVisible=false
    private let clips=["fall_skydive","fall_skydive_accel","fall_skydive_l","fall_skydive_r","para_open","para_float","para_decel","para_steerl","para_steerr"]
    private let canopyClips=[5:"para_open_o",6:"para_float_o",7:"para_decel_o",8:"para_steerl_o",9:"para_steerr_o",10:"para_land_o"]
    var showing:Bool {amount>0 || canopyName != nil || jetVisible}
    init(duration:@escaping(String)->Double?){self.duration=duration}
    func update(delta dt:Double,input:Input?,position:SIMD3<Double>,heading:Double,available:Bool=true,canopyAvailable:Bool=true,jetAvailable:Bool=true)->Frame {
        // R6 only calls ap.draw while its state or showing getter is active.
        guard input != nil || showing else{var frame=Frame();frame.bend=SIMD2(forward,side);return frame}
        let state=input?.state ?? 0
        let selected=(1...9).contains(state) ? state-1:nil
        var measured=SIMD3<Double>.zero
        if let previousPosition,dt>0 {
            measured=(position-previousPosition)/dt
            if simd_length(measured)>90 {measured=velocity}
        }
        let acceleration=measured-velocity
        velocity=measured;previousPosition=position
        if state != previous {
            if let selected,clips[selected]=="para_open" {times[selected]=0}
            previous=state
        }
        func clamp(_ value:Double,_ lower:Double,_ upper:Double)->Double{min(upper,max(lower,value))}
        amount=clamp(amount+(selected != nil ? 8:-4)*dt,0,1)
        pitch += clamp((selected != nil ? input?.pitch ?? 0:0)-pitch,-3*dt,3*dt)
        roll += clamp((selected != nil ? input?.roll ?? 0:0)-roll,-3*dt,3*dt)
        var result=Frame()
        result.figureControlled=amount>0 || figureWasControlled
        result.figurePitch=amount>0 ? pitch:0;result.figureRoll=amount>0 ? roll:0
        figureWasControlled=amount>0
        if amount>0 {
            let rate=selected==4 ? 8.0:2.0
            var total:Double=0
            for index in clips.indices {
                weights[index]=clamp(weights[index]+(index==selected ? rate:-rate)*dt,0,1)
                guard weights[index]>0 else{continue}
                let preferred="parachute/"+clips[index]
                let name=available && duration(preferred) != nil ? preferred:"ped/fall_skydive"
                guard let length=duration(name),length>0 else{continue}
                times[index]+=dt;total+=weights[index]
                result.blends.append(.init(operation:.replace,clip:name,time:clips[index]=="para_open" ? min(times[index],length):times[index].truncatingRemainder(dividingBy:length),weight:weights[index]/total*(total==weights[index] ? amount:1)))
            }
        } else {weights=Array(repeating:0,count:9);pitch=0;roll=0}
        if canopyAvailable,let name=canopyClips[state] {
            if name != canopyName {
                canopyName=name
                if name=="para_open_o" || name=="para_land_o" {canopyTime=0}
                canopyOpening=state==5 ? 0:max(canopyOpening,1)
            }
            canopyTime+=dt;canopyOpening+=dt
            let name="parachute/"+name
            if available,let length=duration(name),length>0 {
                let scale=clamp((canopyOpening-0.5)/0.5,0,1)
                do {
                    let once=state==5 || state==10
                    let time=once ? min(max(0,state==5 ? canopyOpening-0.5:canopyTime),length):canopyTime.truncatingRemainder(dividingBy:length)
                    result.canopy=Canopy(clip:name,time:time,scale:max(scale,0.001),pitch:state==10 ? 0:pitch,roll:state==10 ? 0:roll,landed:state==10,easing:min(1,8*dt),visible:scale>0)
                }
            }
        } else {canopyName=nil}
        jetVisible=jetAvailable && state>=11
        if jetVisible {
            let flying=state != 11
            let nozzlePitch=flying ? clamp(input?.pitch ?? 0,-Double.pi/2,Double.pi/2):0
            let nozzleRoll=flying ? clamp(input?.roll ?? 0,-1,1)*Double.pi/4:0
            thrust=clamp(thrust+(state==13 ? 1:-1)*2.5*dt,0,1)
            result.jet=Jet(visible:true,pitch:nozzlePitch,leftRoll:max(0,nozzleRoll),rightRoll:min(0,nozzleRoll),thrust:thrust,sound:state==13 ? "jetThrust":"jetIdle")
        }
        let flying=state==12 || state==13,scaled=50*dt
        let fwd=SIMD3(sin(heading),cos(heading),0),right=SIMD3(cos(heading),-sin(heading),0)
        if flying {
            forwardSpeed += clamp(simd_dot(acceleration,fwd),-5,5)/50*0.4
            sideSpeed += clamp(simd_dot(acceleration,right),-5,5)/50*0.4
        }
        forwardSpeed -= sin(forward)*scaled*0.01;forwardSpeed *= pow(0.98,scaled)
        sideSpeed -= sin(side)*scaled*0.01;sideSpeed *= pow(0.98,scaled)
        forward=flying ? clamp(forward+forwardSpeed*scaled,-0.7854,0.7854):forward*pow(0.8,scaled)
        side=flying ? clamp(side+sideSpeed*scaled,-0.7854,0.7854):side*pow(0.8,scaled)
        result.bend=SIMD2(forward,side)
        return result
    }
}
