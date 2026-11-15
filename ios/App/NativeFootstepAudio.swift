import Foundation

/// Original19737 cv.step/cv.land and24163 skate sound planning. Animation
/// phase callbacks select events; distance accumulation is not a substitute.
struct NativeFootstepAudio {
    struct Bank:Decodable {let bank:Int;let first:Int;let count:Int}
    struct Configuration:Decodable {let materials:[Int];let banks:[String:Bank];let water:Int}
    struct Plan {let sample:String;let rate:Double;let gain:Double;var start:Double = 0}
    let configuration:Configuration
    func step(_ kind:String,mine:Bool = true,material:Int? = nil,surface:Int? = nil,wading:Bool = false,random:()->Double = {Double.random(in:0..<1)}) -> Plan? {
        if kind.hasPrefix("skate") {
            let ground=mine ? surface ?? -1:-1
            guard ground != 4 && ground != 5 else{return nil}
            let decibels=(ground == 3 ? 20*log10(0.5):0)+floor((2*random()-1)*3+0.5)
            return Plan(sample:kind.hasSuffix("L") ? "0_7":"0_8",rate:kind.hasPrefix("skateWalk") ? 1:0.75,gain:0.9*pow(10,decibels/20))
        }
        let sneak=kind == "sneak"
        let profiles:[String:(Double,Double)]=["walk":(-12,0.9),"run":(-6,1.1),"sprint":(0,1.2),"crouch":(-18,0.8)]
        let profile=profiles[sneak ? "walk":kind] ?? profiles["walk"]!
        var ground=0
        if mine {
            if wading {ground=configuration.water}
            else if let material,material >= 0{ground=configuration.materials.indices.contains(material) ? configuration.materials[material]:0}
            else if surface == 3{ground=1}
            else if surface == 4{ground=2}
        }
        let gain=0.9*pow(10,(profile.0-(sneak ? 6:0))/20)
        let rate=(profile.1-(sneak ? 0.1:0))*(1+(2*random()-1)*0.0588)
        if ground == configuration.water{return Plan(sample:"128_\(Int(floor(random()*5)))",rate:rate,gain:gain,start:0.5)}
        let bank=configuration.banks[String(ground)] ?? configuration.banks["0"]
        let number=(bank?.first ?? 1)+Int(floor(random()*Double(bank?.count ?? 5)))
        return Plan(sample:"\(bank?.bank ?? 0)_\(number)",rate:rate,gain:gain)
    }
    func land(_ kind:String,water:Bool = false,random:()->Double = {Double.random(in:0..<1)}) -> Plan {
        if water {let sample="128_\(Int(floor(random()*5)))";return Plan(sample:sample,rate:1+(2*random()-1)*0.0588,gain:0.8,start:0.5)}
        return Plan(sample:kind == "collapse" ? "0_0":"0_6",rate:1+(2*random()-1)*0.0588,gain:0.8)
    }
}
