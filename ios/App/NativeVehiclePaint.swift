// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Browser wire colours are palette indices or tagged 24-bit RGB values.
/// The palette itself is imported from the owner's pinned browser catalogue.
struct NativeVehiclePaint {
    struct Metadata: Decodable {
        let version: Int
        let vertexRGB: String
        let palette: [[Int]]
        let defaults: [Int]
        let colorVariants: [[Int]]
        let customFlag: Int
        let customLimit: Int
    }
    let metadata: Metadata
    private let palette: [SIMD3<Float>]

    init?(_ metadata: Metadata) {
        guard metadata.version == 1, metadata.vertexRGB == "neutral-paint-slot-rgb",
              (1...1024).contains(metadata.palette.count), metadata.defaults.count == 2,
              metadata.customFlag == 0x1000000, metadata.customLimit == 0x2000000,
              metadata.palette.allSatisfy({ $0.count == 3 && $0.allSatisfy { (0...255).contains($0) } }),
              metadata.defaults.allSatisfy({ Self.valid($0, count: metadata.palette.count) }),
              metadata.colorVariants.count <= 256, metadata.colorVariants.allSatisfy({
                  $0.count == 4 && $0.allSatisfy { Self.valid($0, count: metadata.palette.count) }
              }) else { return nil }
        self.metadata = metadata
        palette = metadata.palette.map { Self.linear(SIMD3($0[0], $0[1], $0[2])) }
    }

    private static func valid(_ value: Int, count: Int) -> Bool {
        (0..<count).contains(value) || (0x1000000..<0x2000000).contains(value)
    }
    private static func linear(_ rgb: SIMD3<Int>) -> SIMD3<Float> {
        func component(_ byte: Int) -> Float {
            let value = Double(byte) / 255
            return Float(value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4))
        }
        return SIMD3(component(rgb.x), component(rgb.y), component(rgb.z))
    }

    // Match the numeric tokens accepted by the original code normalizer.
    // Empty tokens are zero; absent tokens use the model's own defaults.
    private static func integer(_ token: Substring) -> Int? {
        guard token.utf8.count <= 64 else { return nil }
        let whitespace = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))
        let text = String(token).trimmingCharacters(in: whitespace)
        if text.isEmpty { return 0 }
        let lower = text.lowercased()
        if lower.hasPrefix("0x") || lower.hasPrefix("0b") || lower.hasPrefix("0o") {
            let radix = lower.hasPrefix("0x") ? 16 : lower.hasPrefix("0b") ? 2 : 8
            return Int(lower.dropFirst(2), radix: radix)
        }
        guard let number = Double(text), number.isFinite else { return nil }
        return Int(exactly: number)
    }

    func colors(code: String?, model: Int) -> [Int] {
        guard let code, code.utf8.count <= 512 else { return metadata.defaults }
        let tokens = code.split(separator: ".", omittingEmptySubsequences: false)
        guard let first = tokens.first, Self.integer(first) == model else { return metadata.defaults }
        return (0..<2).map { index in
            let field = index + 1
            guard tokens.indices.contains(field), let value = Self.integer(tokens[field]),
                  Self.valid(value, count: palette.count) else { return metadata.defaults[index] }
            return value
        }
    }

    func color(slot: Int, colors: [Int]) -> SIMD3<Float>? {
        guard (0...3).contains(slot), colors.count == 2 else { return nil }
        let variant = metadata.colorVariants.first { $0[0] == colors[0] && $0[1] == colors[1] } ?? metadata.colorVariants.first
        let value = slot < 2 ? colors[slot] : variant.map { $0[slot] } ?? colors[slot - 2]
        if palette.indices.contains(value) { return palette[value] }
        guard (0x1000000..<0x2000000).contains(value) else { return nil }
        return Self.linear(SIMD3((value >> 16) & 255, (value >> 8) & 255, value & 255))
    }
}
