import Foundation

/// Public 49368.be's directional damage reaction and stun cooldown rules.
enum NativePedestrianReaction {
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
