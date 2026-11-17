// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit

/// A portable description of prepared resources, never executable game code.
/// Asset identities are independent of app build number and development host.
struct NativeResourceManifest: Codable {
    struct Resource: Codable, Equatable {
        let path: String
        let bytes: Int64
        let sha256: String
        let required: Bool
    }
    let schema: Int
    let profile: String
    let contentID: String
    let resources: [Resource]
    static let filename = "zgta-resources.json"
    static let profileName = "zgta-prepared-v1"
    static let requiredPaths: Set<String> = [
        "game/world/index.json", "game/native/models/index.json",
        "game/native/vehicles.physics.json", "game/native/foot-animation.json",
        "game/native/models/animations.clips.bin", "game/native/weapons.json",
        "game/native/seating.json", "game/native/riders.json"
    ]
    enum Failure: Error, CustomStringConvertible, LocalizedError {
        case invalid(String)
        var description: String { if case .invalid(let reason) = self { return reason }; return "Invalid resource manifest" }
        var errorDescription:String? { description }
    }
    static func validDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func validPath(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 512,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,47,95].contains($0) }),
              value.hasPrefix("game/") || value.hasPrefix("reference/weapons/") || value.hasPrefix("tools/map/") else { return false }
        return value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    static func isResourceNamespace(_ path:String)->Bool {
        path.hasPrefix("game/") || path.hasPrefix("reference/weapons/") || path.hasPrefix("tools/map/")
    }
    static func validRequestQuery(_ url:URL)->Bool {
        guard let items=URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems else{return true}
        return items.count==1 && items[0].name=="v" && items[0].value.map{ value in
            (1...64).contains(value.utf8.count) && value.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}
        } == true
    }
    func validate() throws {
        guard schema == 1, profile == Self.profileName, Self.validDigest(contentID),
              !resources.isEmpty, resources.count <= 200_000 else { throw Failure.invalid("Unsupported prepared-resource profile") }
        var seen = Set<String>(), total: Int64 = 0
        for item in resources {
            guard Self.validPath(item.path), Self.validDigest(item.sha256),
                  item.bytes > 0, item.bytes <= 2_147_483_648,
                  seen.insert(item.path).inserted else { throw Failure.invalid("Invalid or duplicate resource: \(item.path)") }
            total += item.bytes
            guard total <= 256 * 1_024 * 1_024 * 1_024 else { throw Failure.invalid("Prepared resource catalogue exceeds the supported bound") }
        }
        guard Self.requiredPaths.isSubset(of: Set(resources.filter(\.required).map(\.path))) else {
            throw Failure.invalid("The package is missing required native runtime resources")
        }
        guard identity == contentID else { throw Failure.invalid("Prepared resource catalogue identity mismatch") }
    }
    var totalBytes: Int64 { resources.reduce(0) { $0 + $1.bytes } }
    var identity: String {
        var hash = SHA256()
        hash.update(data: Data("zgta-prepared-v1\n".utf8))
        for item in resources.sorted(by: { $0.path < $1.path }) {
            hash.update(data: Data("\(item.path)\u{0}\(item.bytes)\u{0}\(item.sha256)\u{0}\(item.required ? 1 : 0)\n".utf8))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 64 * 1_024 * 1_024 else { throw Failure.invalid("Resource catalogue is too large") }
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        try manifest.validate()
        return manifest
    }
}
