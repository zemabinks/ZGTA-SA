// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit

/// An explicit fixed-body resource graph, not an inferred retail wardrobe.
/// Actual source hashes and asset bytes belong only to the owner descriptor.
struct NativeCJProfile: Codable {
    struct File: Codable, Equatable {
        let role: String
        let path: String
        let bytes: Int
        let sha256: String
        let crc32: UInt32
    }
    static let name = "cj-normal-vest-denim-v1"
    static let prefix = "game/native/" + name + "/"
    static let descriptorPath = prefix + "profile.json"
    static let maximumDescriptorBytes = 65_536
    static let filenames: [String: String] = [
        "template": "player.dff", "part:torso": "vest.dff", "part:head": "head.dff",
        "part:hands": "hands.dff", "part:legs": "jeans.dff", "part:feet": "sneaker.dff",
        "dictionary:player_torso": "player_torso.txd", "dictionary:vest": "vest.txd",
        "dictionary:player_face": "player_face.txd", "dictionary:jeansdenim": "jeansdenim.txd",
        "dictionary:sneakerbincblk": "sneakerbincblk.txd", "rules": "clothes.dat"
    ]
    let schema: Int
    let profile: String
    let variant: String
    let legacyID: Int
    let nativeID: Int
    let model: String
    let animationStyleModel: String
    let contentIdentity: String
    let files: [File]
    enum Failure: Error { case invalid(String) }
    static func decode(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= maximumDescriptorBytes else { throw Failure.invalid("descriptor bytes") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }
    func validate() throws {
        guard schema == 1, profile == Self.name, variant == "Normal", legacyID == 0, nativeID == 0,
              model == "null", animationStyleModel == "null", Self.digest(contentIdentity),
              files.count == Self.filenames.count else { throw Failure.invalid("fixed profile identity") }
        var roles = Set<String>(), paths = Set<String>(), total = 0
        for file in files {
            guard let filename = Self.filenames[file.role], file.path == Self.prefix + filename,
                  roles.insert(file.role).inserted, paths.insert(file.path).inserted,
                  file.bytes >= 12, file.bytes <= 4 * 1024 * 1024, Self.digest(file.sha256) else {
                throw Failure.invalid("file identity or bound")
            }
            if file.role == "template", file.bytes > 65_536 { throw Failure.invalid("template bound") }
            if file.role == "rules", file.bytes > 256 * 1024 { throw Failure.invalid("rules bound") }
            total += file.bytes
            guard total <= 32 * 1024 * 1024 else { throw Failure.invalid("encoded body budget") }
        }
        guard roles == Set(Self.filenames.keys) else { throw Failure.invalid("incomplete body graph") }
    }
    func prepare(_ dataByRole: [String: Data]) throws -> NativeCJResources.Prepared {
        try validate()
        guard Set(dataByRole.keys) == Set(Self.filenames.keys) else { throw Failure.invalid("incomplete acquired body") }
        for file in files {
            guard let data = dataByRole[file.role], data.count == file.bytes,
                  Self.hash(data) == file.sha256, Self.crc(data) == file.crc32 else {
                throw Failure.invalid("body checksum: " + file.role)
            }
        }
        let names: [NativeCJAssembly.Component: String] = [.torso:"vest", .head:"head", .hands:"hands", .legs:"jeans", .feet:"sneaker"]
        var components: [NativeCJAssembly.Component: NativeCJResources.ComponentSource] = [:]
        for component in NativeCJAssembly.Component.allCases {
            components[component] = .init(modelName:names[component]!, dff:dataByRole["part:" + component.rawValue]!)
        }
        var dictionaries: [String: Data] = [:]
        for (role, data) in dataByRole where role.hasPrefix("dictionary:") { dictionaries[String(role.dropFirst(11))] = data }
        let prepared = try NativeCJResources.prepare(.init(template:dataByRole["template"]!, components:components,
            dictionaries:dictionaries, recipes:Self.recipes, clothesRules:dataByRole["rules"]!))
        guard prepared.contentIdentity == contentIdentity else { throw Failure.invalid("prepared body content identity") }
        return prepared
    }
    static var recipes: [NativeCJTextures.Recipe] {
        [.init(output:"torso", base:.init(dictionary:"player_torso", texture:"torso"), nonzeroAlphaCuts:[.init(dictionary:"vest", texture:"vest")]),
         .init(output:"head", base:.init(dictionary:"player_face", texture:"face"), nonzeroAlphaCuts:[]),
         .init(output:"legs", base:.init(dictionary:"jeansdenim", texture:"legs"), nonzeroAlphaCuts:[]),
         .init(output:"feet", base:.init(dictionary:"sneakerbincblk", texture:"sneakerbincblk"), nonzeroAlphaCuts:[])]
    }
    private static func digest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data:data).map { String(format:"%02x", $0) }.joined() }
    private static let table: [UInt32] = (0..<256).map { n in
        var value = UInt32(n); for _ in 0..<8 { value = (value >> 1) ^ (value & 1 == 1 ? 0xedb88320 : 0) }; return value
    }
    private static func crc(_ data: Data) -> UInt32 {
        var value: UInt32 = 0xffffffff
        for byte in data { value = table[Int((value ^ UInt32(byte)) & 255)] ^ (value >> 8) }
        return value ^ 0xffffffff
    }
}
