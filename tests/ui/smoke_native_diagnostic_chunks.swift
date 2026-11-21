// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
var checks = 0
func require(_ value: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !value() { fatalError(message) }
}
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sizes = [1, 511, 512, 513, 1024, 8193, NativeDiagnosticChunks.maximumRecordBytes]
var rows: [[String: Any]] = []
for size in sizes {
    // Authored byte sequence includes non-UTF8 values; transport is byte exact.
    let data = Data((0..<size).map { UInt8(($0 * 37 + 19) % 256) })
    let identity = UUID()
    let lines = try NativeDiagnosticChunks.encode(data, identifier: identity)
    require(lines.count == (size + 511) / 512, "Incorrect boundary chunk count")
    for line in lines {
        require(line.utf8.count <= NativeDiagnosticChunks.maximumLineBytes, "Diagnostic exceeds declared line budget")
        require(line.utf8.count + "FootContactRecord ".utf8.count < 1024, "Diagnostic would be truncated by transport")
    }
    let file = "payload-\(size).bin"
    try data.write(to: directory.appendingPathComponent(file))
    rows.append(["id": identity.uuidString.lowercased(), "file": file, "lines": lines])
}
let unicode = Data(String(repeating: "é雪🙂", count: 1025).utf8)
let identity = UUID()
let lines = try NativeDiagnosticChunks.encode(unicode, identifier: identity)
try unicode.write(to: directory.appendingPathComponent("unicode.bin"))
rows.append(["id": identity.uuidString.lowercased(), "file": "unicode.bin", "lines": lines])
// A slash-dense base64 payload must still fit one bounded transport line.
let dense=Data(repeating:255,count:NativeDiagnosticChunks.maximumRecordBytes)
let denseID=UUID(),denseLines=try NativeDiagnosticChunks.encode(dense,identifier:denseID)
for line in denseLines {
    require(line.utf8.count + "FootContactRecord ".utf8.count < 1024,"Slash escaping exceeded transport budget")
}
try dense.write(to:directory.appendingPathComponent("slash-dense.bin"))
rows.append(["id":denseID.uuidString.lowercased(),"file":"slash-dense.bin","lines":denseLines])
for invalid in [Data(), Data(repeating: 0, count: NativeDiagnosticChunks.maximumRecordBytes + 1)] {
    do { _ = try NativeDiagnosticChunks.encode(invalid); fatalError("Invalid diagnostic size was accepted") }
    catch NativeDiagnosticChunks.Failure.payload { checks += 1 }
}
try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]).write(to: directory.appendingPathComponent("authored-records.json"))
print("PASS bounded diagnostic encoder: \(checks) checks, \(rows.count) authored records; actual logger acceptance remains separate")
