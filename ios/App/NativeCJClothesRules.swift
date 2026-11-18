// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Conservative admission for a fixed Normal descriptor. This parses the real
/// rule grammar but does not guess unreversed IGNORE/EXCLUSIVE precedence or
/// perform wardrobe changes. A descriptor that requires any normal replacement
/// is rejected; CUTS is explicitly a cutscene-only layer and never used here.
enum NativeCJClothesRules {
    enum Failure: Error { case malformed(Int), requiresResolution(Int), limit }
    struct Report { let commands: Int; let cutsceneReplacements: Int }
    static func validateFixedNormal(models: Set<String>, data: Data) throws -> Report {
        guard !models.isEmpty, models.count <= 10, data.count <= 256 * 1024,
              let text = String(data: data, encoding: .ascii) else { throw Failure.limit }
        let components: Set<String> = ["torso","head","hands","legs","feet","necklace","watch","glasses","hat","extra1"]
        func name(_ value: String, optional: Bool = false) -> Bool {
            optional && value == "-" || !value.isEmpty && value.utf8.count <= 63 &&
                value.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
        }
        guard models.allSatisfy({ name($0) }) else { throw Failure.malformed(0) }
        var active = false, blocks = 0, commands = 0, cuts = 0
        var ignored: Set<String> = [], exclusive: Set<String> = []
        let lines = text.replacingOccurrences(of: "\r\n",with: "\n").replacingOccurrences(of: "\r",with: "\n")
        for (offset, raw) in lines.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            let tokens = line.split { $0.isWhitespace || $0 == "," }.map(String.init)
            if tokens.isEmpty { continue }
            let number = offset + 1
            if tokens == ["rule"] { guard !active, blocks == 0 else { throw Failure.malformed(number) }; active = true; blocks += 1; continue }
            if tokens == ["end"] { guard active, ignored.isEmpty, exclusive.isEmpty else { throw Failure.malformed(number) }; active = false; continue }
            guard active, commands < 4096 else { throw Failure.malformed(number) }
            commands += 1
            let tag = tokens[0], args = Array(tokens.dropFirst())
            let expected: Int
            switch tag {
            case "SETC": expected = 4
            case "TEX","HIDE","CUTS": expected = 2
            case "IGNORE","ENDIGNORE","EXCLUSIVE","ENDEXCLUSIVE": expected = 1
            default: throw Failure.malformed(number)
            }
            guard args.count == expected, args.allSatisfy({ name($0,optional: true) }) else { throw Failure.malformed(number) }
            guard name(args[0]), tag == "SETC" || args.allSatisfy({ name($0) }) else { throw Failure.malformed(number) }
            if tag == "SETC" || tag == "HIDE" { guard components.contains(args[1]) else { throw Failure.malformed(number) } }
            switch tag {
            case "IGNORE": guard ignored.insert(args[0]).inserted else { throw Failure.malformed(number) }
            case "ENDIGNORE": guard ignored.remove(args[0]) != nil else { throw Failure.malformed(number) }
            case "EXCLUSIVE": guard exclusive.insert(args[0]).inserted else { throw Failure.malformed(number) }
            case "ENDEXCLUSIVE": guard exclusive.remove(args[0]) != nil else { throw Failure.malformed(number) }
            case "CUTS": if models.contains(args[0]) { cuts += 1 }
            default:
                if models.contains(args[0]) { throw Failure.requiresResolution(number) }
            }
        }
        guard blocks == 1, !active, ignored.isEmpty, exclusive.isEmpty else { throw Failure.malformed(0) }
        return .init(commands: commands,cutsceneReplacements: cuts)
    }
}
