import Foundation
typealias Audio = NativeVehicleAudioDynamics
let bytes = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let cases = try JSONSerialization.jsonObject(with: bytes) as! [[String:Any]]
func number(_ values: [String:Any], _ key: String) -> Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
var maximum = 0.0, count = 0
func check(_ actual: Double, _ expected: Double, _ label: String) {
    let error = abs(actual-expected); maximum = max(maximum,error)
    precondition(error < 2e-11, "\(label): \(actual) vs \(expected)")
}
for value in cases {
    let kind = value["kind"] as! String, bank = value["bank"] as! Int
    let special = Audio.Special(), boat = Audio.Boat(), remote = Audio.RemoteRoad(), reverse = Audio.Reverse()
    var pitch = -1.0
    for (frame, row) in (value["frames"] as! [[String:Any]]).enumerated() {
        let delta = number(row,"delta"), input = row["input"] as! [String:Any]
        let data = try JSONSerialization.data(withJSONObject: input)
        let layers: [Audio.Layer]
        if kind == "remote" {
            layers = remote.update(delta:delta,model:value["model"] as! Int,share:number(input,"share"),bank:bank)
            pitch = 0
        } else if kind == "reverse" {
            let box = Audio.Box(gears:[],count:0,max:0,reverse:0.4)
            layers = reverse.update(delta:delta,gas:number(input,"gas"),gear:input["gear"] as! Int,
                speed:number(input,"speed"),ground:number(input,"grounded"),box:box).map { [$0] } ?? []
            pitch = 0
        } else if ["heli","prop","jet"].contains(kind) {
            let parsed = try JSONDecoder().decode(Audio.AircraftInput.self,from:data)
            let result = Audio.aircraft(kind:kind,bank:bank,input:parsed,previousPitch:pitch,delta:delta,
                remote:value["remote"] as! Bool,random:number(row,"random"))
            pitch = result.pitch; layers = result.layers
        } else if kind == "boat" {
            layers = boat.update(delta:delta,throttle:number(input,"throttle"),afloat:input["afloat"] as! Bool,
                up:number(input,"up"),distance:number(input,"distance"),speed:number(input,"speed"),bank:bank)
            pitch = boat.pitch; check(boat.turning,number(row,"turning"),"Boat turn \(frame)")
        } else {
            let parsed = try JSONDecoder().decode(Audio.SpecialInput.self,from:data)
            layers = kind == "train" || kind == "tram" ? special.train(delta:delta,brakeBank:132,engineBank:bank,input:parsed)
                : special.update(delta:delta,kind:kind,bank:bank,input:parsed)
            pitch = special.pitch
            check(Double(special.twin),number(row,"twin"),"Train brake twin \(frame)")
            check(special.turned,number(row,"turned"),"Train brake time \(frame)")
        }
        check(pitch,number(row,"pitch"),"\(kind) pitch \(frame)")
        let expected = row["layers"] as! [[String:Any]]
        precondition(layers.count == expected.count)
        for (actual, expected) in zip(layers,expected) {
            precondition(actual.name == expected["name"] as! String && actual.sound == expected["sound"] as! String)
            check(actual.rate,number(expected,"rate"),"\(kind) \(actual.name) rate \(frame)")
            check(actual.gain,number(expected,"gain"),"\(kind) \(actual.name) gain \(frame)")
        }
        count += 1
    }
}
print("PASS: original aircraft/boat/RC/golf/hover/train/tram \(count) audio frames; max \(maximum)")
