// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Near-camera bullet passage is independent of positioned gunshot sounds.
/// Its small bank/cooldown clock follows the scene, never packet wall time.
final class NativeBulletPass {
    typealias V=SIMD3<Double>
    struct Camera {let eye:V,right:V,up:V,forward:V}
    struct Sound {
        let sample:String,rate:Double,gain:Double,sweep:NativeAudioPanSweep
        let right:Bool,rear:Bool,distance:Double
    }
    enum Event {case sound(Sound),preload([String])}
    private var time:Double=0,last:Double = -.infinity,rotateAfter:Double=0
    private var count=0,bank=0
    private let random:()->Double
    private(set) var camera:Camera?
    init(random:@escaping()->Double={Double.random(in:0..<1)}){self.random=random}
    func update(delta:Double,camera:Camera) {
        if delta.isFinite,delta>=0{time+=min(0.1,delta)}
        self.camera=camera
    }
    static func curve(right:Bool)->NativeAudioPanSweep {
        let sign=right ? 1.0:-1.0
        return .init(values:(0..<15).map{Float(0.1*sign/hypot(0.1,1-Double($0)/7))},seconds:0.35)
    }
    func pass(from start:V,to end:V,audioAvailable:Bool)->Event? {
        guard audioAvailable,let camera,(0..<3).allSatisfy({start[$0].isFinite && end[$0].isFinite})else{return nil}
        let offset=end-start,length=simd_length(offset)
        guard length.isFinite,length>0 else{return nil}
        let direction=offset/length,along=random()*length,size=min(2+3*random(),length-along)
        let relative=start+direction*along-camera.eye
        let before=simd_dot(relative,camera.forward),after=before+simd_dot(direction,camera.forward)*size
        guard (before<0) != (after<0)else{return nil}
        let share=abs(before)/(abs(before)+abs(after)),crossing=relative+direction*(size*share)
        let side=simd_dot(crossing,camera.right),height=simd_dot(crossing,camera.up),distance=hypot(side,height)
        guard distance<2,time>=last+0.2 else{return nil}
        if count>10 {
            guard time>=rotateAfter else{return nil}
            bank=(bank+1)%4;count=0
            return .preload((0..<3).map{"\(28+bank)_\($0)"})
        }
        last=time;rotateAfter=time+0.5;count+=1
        let sample="\(28+bank)_\(Int(floor(3*random())))",right=side>=0
        let gain=pow(10,(-2+log10(1-0.5*distance))/20),rate=1+(2*random()-1)*0.03125
        return .sound(.init(sample:sample,rate:rate,gain:gain,sweep:Self.curve(right:right),right:right,rear:before<=0,distance:distance))
    }
}
