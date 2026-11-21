// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Positioned weapon sounds use one spatial body layer. The local stereo
/// pair and delayed local reload tail remain the existing local-shot path.
enum NativeShotAudioPlan {
    static func spatial(_ row:[Double],random:()->Double={Double.random(in:0..<1)})->NativeVehicleAudioDynamics.Plan? {
        guard row.count>=8,row.allSatisfy(\.isFinite),row[5]>0 else{return nil}
        let pitch=row[5],spread=pitch*(0.98+0.04*random()),level=pow(10,row[6]/20)
        guard level.isFinite else{return nil}
        var layers:[NativeVehicleAudioDynamics.Layer]=[]
        func layer(_ name:String,_ sample:Double,_ rate:Double,_ gain:Double) {
            guard let sample=Int(exactly:sample),sample>=0,rate.isFinite,rate>0,gain.isFinite else{return}
            layers.append(.init(name:name,sound:"143_\(sample)",rate:rate,gain:gain))
        }
        layer("attack",row[0],pitch,0.45*level)
        layer("body",row[1],pitch,0.8*level)
        layer("space",row[2],spread,level)
        if row[4]>=0 {layer("tail",row[4],row[7]*(random()<0.5 ? 1:1.18921),0.3*level)}
        return .init(layers:layers)
    }
}
