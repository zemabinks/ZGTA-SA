import Foundation

/// Public 49368.be's directional damage reaction and stun cooldown rules.
enum NativePedestrianReaction {
    /// Incoming source in GTA Z-up, heading clockwise from+Y. Preserve the
    /// original strict sector ties instead of rounding to the nearest bin.
    static func incomingSide(from:SIMD3<Double>,position:SIMD3<Double>,heading:Double)->Int {
        guard (0..<3).allSatisfy({from[$0].isFinite && position[$0].isFinite}),heading.isFinite else{return 0}
        // Preserve the source's actual X/up/-Y subtraction and negation,
        // including signed zeros. Replacing this with heading-bearing
        // reverses the coincident/vertical-only source's selected sector.
        let dx=from.x-position.x,dz=(-from.y)-(-position.y)
        let relative=atan2(-dx,-dz)+heading
        let period=2*Double.pi,shifted=relative+Double.pi
        let angle=(shifted.truncatingRemainder(dividingBy:period)+period).truncatingRemainder(dividingBy:period)-Double.pi
        if abs(angle)<Double.pi/4{return 0}
        if abs(angle)>3*Double.pi/4{return 2}
        return angle>0 ? 1:3
    }
    static func deathKind(weapon:Int,side:Int)->String {
        let side=min(3,max(0,side))
        if weapon==49 || weapon==50{return ["koSkidBack","koSpinR","koSkidFront","koSpinL"][side]}
        if [24,25,26,27,30,31,38,16,35,36,39].contains(weapon){return ["koSkidFront","koSpinR","koSkidBack","koSpinL"][side]}
        return "koFront"
    }
    static func losesHead(weapon:Int,piece:Int?)->Bool {
        piece==9 && [24,25,26,27,30,31,33,34,38].contains(weapon)
    }
    struct Input {
        var weapon: Int
        var side: Int = 0
        var piece: Int = 3
        var still = false
        var crouched = false
        var damage: Double = 0
        var now: Double
        var until: Double = -.infinity
        var stun = true
    }
    struct Result { var kind: String?;var until: Double;var stun = false }
    static func reaction(_ input: Input) -> Result {
        let weapon=input.weapon,side=min(3,max(0,input.side))
        let normallyFlinches=(22...33).contains(weapon) || (!input.stun && (22...46).contains(weapon))
        let knocksStationary=input.stun && [24,25,26,27,33].contains(weapon) && input.still && !input.crouched
        var until=input.until
        if !normallyFlinches || knocksStationary {
            if weapon>=22 {
                if input.now<=until{return Result(kind:nil,until:until)}
                until=input.now+2500
            }
            if weapon<22 || weapon>46 {
                let kind=side==0 && input.damage>20 ? "hitWalk" : side==2 && weapon<=15 ? "hitBehind" : ["hitFront","hitL","hitBack","hitR"][side]
                return Result(kind:kind,until:until)
            }
            func suffix(_ arm:Int)->String {side==2 ? "Bk" : side==arm ? (arm==1 ? "Lt":"Rt") : "Ft"}
            let kind: String
            switch input.piece {
            case 5:kind="damArmL"+suffix(1)
            case 6:kind="damArmR"+suffix(3)
            case 7:kind="damLegL"+suffix(1)
            case 8:kind="damLegR"+suffix(3)
            case 3,4:kind="damStomach"+["Ft","Lt","Bk","Rt"][side]
            default:kind=["hitFront","hitL","hitBack","hitR"][side]
            }
            return Result(kind:kind,until:until,stun:true)
        }
        if input.now<=until {return Result(kind:nil,until:until)}
        return Result(kind:["flinch","flinchL","flinchB","flinchR"][side],until:input.now+(weapon==31 ? 2500:1500))
    }
}
