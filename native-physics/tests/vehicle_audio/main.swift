import Foundation
struct AudioCase: Decodable {
    struct Config: Decodable { let runUpDuration: Double; let loopStart: Double }
    struct Frame: Decodable {
        let delta: Double
        let input: NativeVehicleAudioDynamics.RoadInput
        let output: [String: Double?]
    }
    let model: Int
    let config: Config
    let frames: [Frame]
}
let cases = try JSONDecoder().decode([AudioCase].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
var maximum = 0.0, count = 0
for value in cases {
    let engine = NativeVehicleAudioDynamics.RoadEngine()
    for (i, frame) in value.frames.enumerated() {
        let actual = engine.update(delta: frame.delta, input: frame.input, runUpDuration: value.config.runUpDuration, loopStart: value.config.loopStart)
        let fields: [String: Double] = ["state":Double(actual.state),"gear":Double(actual.gear),"idle":actual.idle,"idleRate":actual.idleRate,
            "revs":actual.revs,"revsRate":actual.revsRate,"runUp":actual.runUp,"runUpRate":actual.runUpRate,"runUpFrom":actual.runUpFrom,
            "cruise":actual.cruise,"cruiseRate":actual.cruiseRate,"fall":actual.fall,"fallRate":actual.fallRate]
        for (field, actual) in fields {
            if let expected = frame.output[field] ?? nil {
                let error = abs(actual-expected); maximum = max(maximum,error)
                precondition(error < 2e-11,"Original audio mismatch model \(value.model), frame \(i), \(field): \(actual) / \(expected)")
            } else { precondition(actual == -.infinity, "Expected inactive original layer") }
        }
        count += 1
    }
}
print("PASS: original module1061 road audio \(count) frames, maximum error \(maximum)")
