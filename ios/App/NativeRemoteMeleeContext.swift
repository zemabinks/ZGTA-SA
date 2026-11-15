import Foundation
import simd

/// Original public remote-pedestrian ground-strike visual inference. This is
/// deliberately separate from melee targeting, LOS and server damage rules.
enum NativeRemoteMeleeContext {
    struct Person {
        var id:String
        var position:SIMD3<Double>
        var walking=true
        var down=false
        var life:Double=100
    }
    static func nearFlooredTarget(attackerID:String,position:SIMD3<Double>,heading:Double,
                                  own:Person?,people:[Person])->Bool {
        guard position.x.isFinite,position.y.isFinite,heading.isFinite else{return false}
        let forward=SIMD2(sin(heading),cos(heading))
        func matches(_ person:Person)->Bool {
            guard person.id != attackerID,person.walking,person.down || person.life<=0 else{return false}
            let offset=SIMD2(person.position.x-position.x,person.position.y-position.y)
            let distance=hypot(offset.x,offset.y)
            return distance<2.1 && (distance<0.3 || simd_dot(forward,offset)/distance>0.5)
        }
        // The public clause tests the local walking player first, then other
        // person actors. Its visual inference has no height or visibility test.
        if let own,matches(own){return true}
        return people.contains(where:matches)
    }
}
