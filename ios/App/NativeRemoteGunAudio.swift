// SPDX-License-Identifier: AGPL-3.0-only
import simd

/// Remote held sound ownership follows firing-marker refreshes. Native audio
/// playback is separate; this owner advances even when no audio is available.
final class NativeRemoteGunAudio {
    struct Event {
        let key:String,kind:String,position:SIMD3<Double>
        let held:Bool,tail:Bool
    }
    private struct Voice {let kind:String;var position:SIMD3<Double>;var idle:Double=0}
    private var voices:[String:Voice]=[:],order:[String]=[]
    static func kind(_ weapon:Int)->String?{[37:"flame",38:"minigun",41:"spray",42:"foam"][weapon]}
    func hold(identity:String,weapon:Int,at position:SIMD3<Double>)->Event?{
        guard let kind=Self.kind(weapon),NativeOrdinaryShot.finite(position)else{return nil}
        let key=kind+":"+identity
        if voices[key]==nil{order.append(key)}
        voices[key]=Voice(kind:kind,position:position)
        return .init(key:key,kind:kind,position:position,held:true,tail:false)
    }
    func advance(delta:Double)->[Event]{
        guard delta.isFinite,delta>=0 else{return []}
        let dt=delta;var result:[Event]=[]
        for key in order {
            guard var voice=voices[key]else{continue}
            if voice.idle+dt<0.2 {voice.idle+=dt;voices[key]=voice}
            else {
                voices[key]=nil
                result.append(.init(key:key,kind:voice.kind,position:voice.position,held:false,tail:voice.kind=="minigun"))
            }
        }
        order.removeAll{voices[$0]==nil};return result
    }
    func clear()->[Event]{
        let result=order.compactMap{key->Event? in
            guard let voice=voices[key]else{return nil}
            return .init(key:key,kind:voice.kind,position:voice.position,held:false,tail:false)
        }
        voices.removeAll();order.removeAll();return result
    }
}
