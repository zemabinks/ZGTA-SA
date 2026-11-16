import Foundation

/// Actor fire/cough timers from the archived browser controller. These own
/// effects only; each emitted fractional hit still passes through vitals.
final class NativeOriginalWorldEffects {
    struct Damage { let amount: Double; let weapon: Int; let source: String? }
    private var fireRemaining=0.0,fireStrength=0.0,fireElapsed=0.0
    private var gasRemaining=0.0,gasElapsed=0.0,gasVolumePending=false
    private(set) var fireSource:String?,gasSource:String?
    var burning:Bool {fireRemaining>0}
    var coughing:Bool {gasRemaining>0}
    @discardableResult func light(by source:String?=nil)->Bool {
        guard !burning else{return false};fireRemaining=2.333;fireStrength=1;fireSource=source;return true
    }
    func extinguish(){fireRemaining=0;fireElapsed=0}
    func douse(_ amount:Double){guard amount.isFinite,amount>=0,burning else{return};fireStrength-=2*amount;if fireStrength<=0{extinguish()}}
    func whiff(by source:String?=nil,volume:Bool=false,random:()->Double={Double.random(in:0..<1)}) {
        if !volume || gasRemaining<1 {
            let value=random();guard value.isFinite,(0...1).contains(value)else{return};gasRemaining=1+value
        }
        gasSource=source;if !gasVolumePending{gasVolumePending=volume}
    }
    func clearGas(){gasRemaining=0;gasElapsed=0;gasVolumePending=false}
    func reset(){extinguish();clearGas();fireSource=nil;gasSource=nil}
    func step(delta:Double)->[Damage] {
        guard delta.isFinite,delta>0 else{return []};var hits:[Damage]=[]
        if fireRemaining>0 {
            let elapsed=min(delta,fireRemaining);fireRemaining-=elapsed;fireElapsed+=elapsed
            if fireRemaining<=0 || fireElapsed>=0.25 {
                hits.append(Damage(amount:8.25*fireElapsed,weapon:37,source:fireSource));fireElapsed=0
            }
        }
        if gasRemaining>0 {
            gasRemaining-=delta
            if gasVolumePending {
                gasVolumePending=false;gasElapsed+=delta
                if gasElapsed>=0.3 {gasElapsed-=0.3;hits.append(Damage(amount:0.33,weapon:17,source:gasSource))}
            }
        }
        return hits
    }
}
