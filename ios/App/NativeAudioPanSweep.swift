// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// AudioParam value-curve interpolation, evaluated by the audio callback.
/// Values retain the original Float32 curve rather than a display-rate pan.
struct NativeAudioPanSweep {
    let values:[Float],seconds:Double
    func value(at time:Double)->Double {
        guard values.count>1,seconds.isFinite,seconds>0 else{return Double(values.first ?? 0)}
        let position=min(1,max(0,time/seconds))*Double(values.count-1)
        let index=min(values.count-1,Int(position)),next=min(values.count-1,index+1)
        return Double(values[index])+(Double(values[next])-Double(values[index]))*(position-Double(index))
    }
    /// StereoPanner's mono/stereo laws; matrix columns are source L/R.
    static func matrix(pan:Double,mono:Bool)->SIMD4<Double> {
        let value=min(1,max(-1,pan))
        let angle=(mono ? (value+1)/2:value<=0 ? value+1:value)*Double.pi/2
        let left=cos(angle),right=sin(angle)
        if mono{return SIMD4(left,0,right,0)}
        return value<=0 ? SIMD4(1,left,0,right):SIMD4(left,0,right,1)
    }
}
