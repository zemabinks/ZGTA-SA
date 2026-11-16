import Foundation
import simd

/// Visual/physical response to an already accepted hit. Health authority stays
/// in the multiplayer client. The clock is monotonic milliseconds.
final class NativeLocalHitReaction {
    typealias V=SIMD3<Double>
    struct Input {
        var weapon:Int,damage:Double,healthAfter:Int,now:Double
        var side=0,piece=3,quiet=false,wasAlive=true
        var still=false,crouched=false,stun=true,swimming=false,climbing=false,stealth=false
        var source:V?,target=V.zero,hasActor=true
    }
    struct Response {
        var flinch:String?,stun=false,death:String?,impulse:V?,loseHead=false
    }
    private(set) var until = -Double.infinity
    func reset(){until = -.infinity}
    func receive(_ input:Input)->Response {
        var result=Response()
        guard input.wasAlive,input.damage.isFinite,input.damage>0,input.now.isFinite else{return result}
        // These hits enter the original fire/spray effects path. Their health
        // was already handled by authority; do not invent another flinch.
        if input.weapon==37 && !input.quiet{return result}
        let quiet=input.quiet || ([41,42].contains(input.weapon) && !input.swimming)
        let side=min(3,max(0,input.side))
        if input.healthAfter>=1 {
            guard ![54,49].contains(input.weapon),!quiet else{return result}
            let reaction=NativePedestrianReaction.reaction(.init(weapon:input.weapon,side:side,piece:input.piece,
                still:input.still,crouched:input.crouched,damage:input.damage,now:input.now,until:until,stun:input.stun))
            until=reaction.until;result.flinch=reaction.kind
            result.stun=reaction.stun && !input.swimming && !input.climbing && !input.stealth
            return result
        }
        if [49,50].contains(input.weapon){result.death=["koSkidBack","koSpinR","koSkidFront","koSpinL"][side]}
        else if [24,25,26,27,30,31,38,16,35,36,39].contains(input.weapon){result.death=["koSkidFront","koSpinR","koSkidBack","koSpinL"][side]}
        else{result.death="koFront"}
        let force:[Int:Double]=[24:1,25:2,26:2,27:2,38:2,30:0.5,31:0.5]
        if input.hasActor,let strength=force[input.weapon],let source=input.source {
            var away=input.target-source;away.y=0
            if simd_length_squared(away)>1e-6 {
                let scale=5.0/70*50
                away=simd_normalize(away)*(strength*scale);away.y=scale;result.impulse=away
            }
        }
        result.loseHead=input.piece==9 && [24,25,26,27,30,31,33,34,38].contains(input.weapon)
        return result
    }
}
