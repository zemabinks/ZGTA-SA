// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit

/// Pure preparation boundary shared by a future installed/raw-IMG or prepared
/// development provider. All acquisition, source trust and runtime admission
/// remain with that provider. A successful candidate is not registered as0.
enum NativeCJResources {
    struct ComponentSource { let modelName: String; let dff: Data }
    struct Input {
        let template: Data
        let components: [NativeCJAssembly.Component: ComponentSource]
        let dictionaries: [String: Data]
        let recipes: [NativeCJTextures.Recipe]
        let clothesRules: Data
    }
    struct Prepared {
        let assembly: NativeCJAssembly.Plan
        let textures: NativeRenderWareTXD.TextureDictionary
        let rules: NativeCJClothesRules.Report
        let sourceSHA256: [String: String]
        let contentIdentity: String
    }
    enum Failure: Error { case limit, invalid(String) }
    static func prepare(_ input: Input) throws -> Prepared {
        guard input.template.count <= 64 * 1024, input.components.count == 5,
              input.dictionaries.count <= 16, input.clothesRules.count <= 256 * 1024 else { throw Failure.limit }
        func name(_ s: String) -> Bool {
            !s.isEmpty && s.utf8.count <= 63 && s.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
        }
        var total = input.template.count + input.clothesRules.count
        var parts: [NativeCJAssembly.Part] = [], hashes: [String: String] = [:]
        hashes["template"] = digest(input.template); hashes["rules"] = digest(input.clothesRules)
        for component in NativeCJAssembly.Component.allCases {
            guard let source = input.components[component], name(source.modelName), source.dff.count <= 4 * 1024 * 1024 else { throw Failure.invalid("component source") }
            total += source.dff.count
            guard total <= 32 * 1024 * 1024 else { throw Failure.limit }
            parts.append(.init(component: component,normal: try NativeCJAssembly.normalClump(from: source.dff)))
            hashes["part:\(component.rawValue):\(source.modelName)"] = digest(source.dff)
        }
        let rules = try NativeCJClothesRules.validateFixedNormal(models: Set(input.components.values.map(\.modelName)),data: input.clothesRules)
        var dictionaries: [String: NativeRenderWareTXD.TextureDictionary] = [:], decoded = 0
        for (key, raw) in input.dictionaries {
            guard name(key), raw.count <= 4 * 1024 * 1024 else { throw Failure.invalid("dictionary source") }
            total += raw.count; guard total <= 32 * 1024 * 1024 else { throw Failure.limit }
            let dictionary = try NativeCJTextures.decodeDictionary(raw,maximumDecodedBytes: 64 * 1024 * 1024 - decoded)
            decoded += dictionary.decodedByteCount; guard decoded <= 64 * 1024 * 1024 else { throw Failure.limit }
            dictionaries[key] = dictionary; hashes["dictionary:\(key)"] = digest(raw)
        }
        let textures = try NativeCJTextures.compose(input.recipes,dictionaries: dictionaries)
        guard Set(textures.textures.map(\.name)) == Set(["torso","head","legs","feet"]) else { throw Failure.invalid("complete body texture outputs") }
        let template = try NativeRenderWareDFF.decode(input.template)
        let body = try NativeCJAssembly.prepare(template: template,parts: parts)
        let recipeDescription: [[String: Any]] = input.recipes.map { recipe in
            ["output": recipe.output,"base": [recipe.base.dictionary,recipe.base.texture],
             "cuts": recipe.nonzeroAlphaCuts.map { [$0.dictionary,$0.texture] }]
        }
        hashes["recipe-v1"] = digest(try JSONSerialization.data(withJSONObject: recipeDescription,options: [.sortedKeys]))
        let identity = digest(try JSONSerialization.data(withJSONObject: hashes,options: [.sortedKeys]))
        return .init(assembly: body,textures: textures,rules: rules,sourceSHA256: hashes,contentIdentity: identity)
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x",$0) }.joined() }
}
