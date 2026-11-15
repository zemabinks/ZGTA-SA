import Foundation

/// A voice retains its unscaled gain and clock while preferences change.
/// Muting therefore neither restarts it nor loses the level needed to restore.
struct NativeAudioEnvelope {
    struct Fade {let begins:Double;let ends:Double;let from:Float;let to:Float}
    let gain:Float
    let started:Double
    let rise:Double
    var fade:Fade?
    func level(at now:Double,baseVolume:Float,multiplier:Float)->Float {
        var source=gain
        var rising=rise>0 ? Float(min(1,max(0,(now-started)/rise))):1
        if let fade,now>=fade.begins,fade.ends>fade.begins {
            let share=Float(min(1,max(0,(now-fade.begins)/(fade.ends-fade.begins))))
            source=fade.from*pow(fade.to/max(fade.from,0.0001),share)
            rising=1
        }
        return min(1,max(0,source*baseVolume))*rising*min(1,max(0,multiplier))
    }
    func animating(at now:Double)->Bool {
        now<started+max(0,rise) || fade.map{now<$0.ends} == true
    }
}
