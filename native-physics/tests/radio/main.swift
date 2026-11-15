import Foundation

struct RadioFixtures: Decodable {
    struct Day: Decodable { let station: Int; let day: Int; let pieces: [NativeRadioProgram.Piece] }
    struct Query: Decodable {
        let milliseconds: Double
        let cursor: NativeRadioProgram.Cursor
        let after: NativeRadioProgram.Cursor
    }
    let cases: [Day]
    let cursors: [Query]
}
let root = CommandLine.arguments[1]
let program = try NativeRadioProgram(data: Data(contentsOf: URL(fileURLWithPath: root + "/program.json")))
let fixtures = try JSONDecoder().decode(RadioFixtures.self, from: Data(contentsOf: URL(fileURLWithPath: root + "/timeline.json")))
var count = 0
for value in fixtures.cases {
    let actual = program.day(station: value.station, day: value.day)
    guard actual == value.pieces else {
        let mismatch = zip(actual, value.pieces).first { $0 != $1 }
        fatalError("Program mismatch station \(value.station), day \(value.day), counts \(actual.count)/\(value.pieces.count), first \(String(describing: mismatch))")
    }
    count += actual.count
}
for value in fixtures.cursors {
    let actual = program.at(station: value.cursor.station, milliseconds: value.milliseconds)
    precondition(actual == value.cursor, "Sample-clock seek mismatch")
    precondition(program.after(actual!) == value.after, "Day transition mismatch")
}
precondition(program.at(station: -1, milliseconds: 0) == nil)
precondition(program.at(station: 13, milliseconds: 0) == nil)
precondition(program.at(station: 1, milliseconds: .nan) == nil)
precondition(program.at(station: 1, milliseconds: -1) == nil)
for (model, values) in program.document.vehicleDefaults {
    let actual = program.defaultStation(model: Int(model)!)
    precondition(actual.type == values[1] && actual.station == (values[1] == 2 ? 13 : values[0]))
}
print("PASS: \(fixtures.cases.count) original station-days, \(count) pieces, \(fixtures.cursors.count) sample-clock seeks/day transitions and all vehicle station defaults match exactly")
