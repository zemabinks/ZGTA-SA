// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Traffic terrain/body/wheel presentation in GTA XYZ. This is separate from
/// authoritative motion, collision bodies and the local driving controller.
/// The imported vehicle supplies its own model origin; do not add it to the
/// fitted ground translation or again to seated occupants.
struct NativeAmbientTrafficPresentation {
    struct Input {
        let id:UInt16,frame:Int
        let position:SIMD2<Double>,direction:SIMD2<Double>
        let baseline:Double,length:Double,distance:Double,delta:Double
        let free:Bool,freePosition:SIMD2<Double>?,freeStamp:Double?
        let speed:Double,side:Double,aim:Double,flags:UInt8
        let residual:SIMD2<Double>,yawResidual:Double
    }
    struct State {
        var height:Double?,ground:Double=0,slope:Double=0,pitch:Double=0
        var previous=SIMD2<Double>.zero,unfelt:Double=0
        var feltAt:Int?,groundStamp:Double?
        // Stored yaw/facing use the browser world's Y-up yaw convention;
        // conversion to native clockwise GTA+Y happens only in Output.
        var yaw:Double?,facing:Double=0,steering:Double=0,spin:Double=0,wheelPhase:Double=0
    }
    struct Output {
        let position:SIMD3<Double>,heading:Double,pitch:Double
        let steering:Double,spin:Double,wheelPhase:Double
    }
    typealias DownRay=(_ origin:SIMD3<Double>,_ maximum:Double)->Double?
    enum Failure:Error{case invalidInput}
    var state=State()
    private func clamp(_ value:Double,_ lower:Double,_ upper:Double)->Double{min(upper,max(lower,value))}
    private func sign(_ value:Double)->Double{value>0 ? 1:value<0 ? -1:0}
    private func wrap(_ value:Double)->Double{atan2(sin(value),cos(value))}
    /// Two finite vertical distances are needed to replace a fitted plane.
    /// A miss leaves all plane ownership and accumulated travel unchanged.
    @discardableResult mutating func probe(_ input:Input,baseline:Double,raise:Double=0,lower:Double?=nil,ray:DownRay)->Bool {
        let reach=0.3*input.length,height=baseline+2.2+raise,maximum=6+raise+(lower ?? raise)
        let front=input.position+input.direction*reach,back=input.position-input.direction*reach
        let first=ray(SIMD3(front.x,front.y,height),maximum),second=ray(SIMD3(back.x,back.y,height),maximum)
        guard let first,let second,first.isFinite,second.isFinite else{return false}
        state.ground=height-(first+second)/2
        state.slope=atan2(second-first,2*reach);state.feltAt=input.frame;state.unfelt=0
        return true
    }
    mutating func update(_ input:Input,ray:DownRay?)throws->Output {
        guard input.frame>=0,input.delta>=0,input.length>0,
              [input.position.x,input.position.y,input.direction.x,input.direction.y,input.baseline,input.length,input.distance,input.delta,
               input.speed,input.side,input.aim,input.residual.x,input.residual.y,input.yawResidual].allSatisfy(\.isFinite)else{throw Failure.invalidInput}
        let first=state.height==nil
        let moved=first ? 0:clamp(simd_dot(input.position-state.previous,input.direction),-40,40)
        let rise=moved*clamp(tan(state.slope),-1,1)
        if !first{state.unfelt+=abs(moved)}
        if let ray {
            if input.distance<70 || (input.frame%5+Int(input.id)%5)%5==0 || first {
                let recent=input.free && state.feltAt.map{input.frame-$0<=12} == true
                let newHeight=recent && state.groundStamp != input.freeStamp && abs(state.ground+rise-input.baseline)>3
                if input.free{state.groundStamp=input.freeStamp}
                var found=false
                if recent {
                    if newHeight {
                        found=probe(input,baseline:input.baseline,ray:ray)
                        if !found{found=probe(input,baseline:state.ground+rise,raise:state.unfelt/2,ray:ray)}
                    }else{
                        found=probe(input,baseline:state.ground+rise,raise:state.unfelt/2,ray:ray)
                        if !found{found=probe(input,baseline:input.baseline,ray:ray)}
                    }
                    if !found{state.ground+=rise}
                }else{
                    let displacement=input.freePosition.map{simd_distance(input.position,$0)} ?? 0
                    let pad=input.free ? 0.5*min(40,displacement):0
                    found=probe(input,baseline:input.baseline,lower:pad,ray:ray)
                    if !found && pad>0{found=probe(input,baseline:input.baseline,raise:pad,lower:0,ray:ray)}
                    if !found{state.ground=input.baseline;state.slope=0}
                }
            }else{state.ground+=rise}
        }else{state.ground=input.baseline;state.slope=0}
        let blend=first ? 1:min(1,10*input.delta)
        let old=state.height ?? 0
        state.height=old+rise+(state.ground-old-rise)*blend
        state.pitch+=(state.slope-state.pitch)*blend;state.previous=input.position
        let correction=abs(input.speed)>2 ? (input.residual.y*input.direction.x-input.residual.x*input.direction.y)/0.25:0
        let targetFacing=input.yawResidual-(correction==0 ? 0:atan(correction/input.speed))
        state.facing+=(targetFacing-state.facing)*min(1,1-exp(-input.delta/0.1))
        let beta=input.flags&16 != 0 ? 0.07:input.flags&4 != 0 ? 0.15:0.6
        let sideYaw = !input.free && input.speed>0.2 && abs(input.aim-input.side)>0.01 ? -sign(input.aim-input.side)*atan(beta):0
        let target=atan2(-input.direction.x,input.direction.y)+sideYaw+state.facing,previousYaw=state.yaw
        let yaw:Double
        if let previousYaw,input.delta>0 {
            let bound=max(2,abs(input.speed))*input.delta/4
            yaw=previousYaw+clamp(wrap(target-previousYaw),-bound,bound)
        }else{yaw=target}
        let change=previousYaw.map{input.delta>0 ? wrap(yaw-$0):0} ?? 0
        state.spin=input.delta>0 ? change/input.delta:0
        let steering=input.speed>0.5 && input.delta>0 ? clamp(-atan(state.spin*0.6*input.length/input.speed),-0.6,0.6):0
        state.steering+=(steering-state.steering)*min(1,8*input.delta)
        state.wheelPhase-=input.speed*input.delta/0.36;state.yaw=yaw
        return .init(position:SIMD3(input.position.x+input.residual.x,input.position.y+input.residual.y,state.height!),
            heading:-yaw,pitch:state.pitch,steering:state.steering,spin:state.spin,wheelPhase:state.wheelPhase)
    }
}
