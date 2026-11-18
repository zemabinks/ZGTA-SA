// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Exact, explicit dictionary/texture joins for segmented player materials.
/// No atlas resizing, dictionary-name guessing, transparent-skin substitution
/// or unverified initial-wardrobe descriptor is hidden in this compositor.
enum NativeCJTextures {
    struct Source: Hashable { let dictionary: String; let texture: String }
    struct Recipe {
        let output: String
        let base: Source
        /// PC clothing's inspected nonzero-alpha cut copies the entire texel;
        /// it is not ordinary source-over blending. Order is explicit.
        let nonzeroAlphaCuts: [Source]
    }
    struct Limits {
        var outputs = 16
        var cutsPerOutput = 32
        var decodedOutputBytes = 32 * 1024 * 1024
    }
    enum Failure: Error { case invalid(String), missing(Source), limit }
    /// Optional IMG-sector allocation padding is accepted only at the outer
    /// dictionary boundary. Payload zeros are never trimmed with rstrip.
    static func decodeDictionary(_ data: Data, maximumBytes: Int = 4 * 1024 * 1024,
                                 maximumDecodedBytes: Int = 64 * 1024 * 1024) throws -> NativeRenderWareTXD.TextureDictionary {
        guard maximumBytes > 0, maximumDecodedBytes > 0, data.count >= 12, data.count <= maximumBytes else { throw Failure.limit }
        let b = [UInt8](data)
        func u32(_ at: Int) -> UInt32 { UInt32(b[at]) | UInt32(b[at+1]) << 8 | UInt32(b[at+2]) << 16 | UInt32(b[at+3]) << 24 }
        let count = Int(u32(4))
        guard u32(0) == 22, count <= b.count - 12 else { throw Failure.invalid("dictionary bounds") }
        let end = count + 12
        if end != b.count {
            guard b.count % 2048 == 0, b.count - end < 2048,
                  b[end...].allSatisfy({ $0 == 0 }) else { throw Failure.invalid("dictionary allocation tail") }
        }
        var limits = NativeRenderWareTXD.Limits.default
        limits.maximumTextureCount = 64; limits.maximumDecodedBytes = maximumDecodedBytes
        return try NativeRenderWareTXD.decode(Data(b[..<end]),limits: limits)
    }
    static func compose(_ recipes: [Recipe], dictionaries: [String: NativeRenderWareTXD.TextureDictionary],
                        limits: Limits = .init()) throws -> NativeRenderWareTXD.TextureDictionary {
        guard limits.outputs > 0, limits.cutsPerOutput >= 0, limits.decodedOutputBytes > 0,
              !recipes.isEmpty, recipes.count <= limits.outputs else { throw Failure.limit }
        var names: Set<String> = [], outputs: [NativeRenderWareTXD.Texture] = [], byteCount = 0
        func texture(_ source: Source) throws -> NativeRenderWareTXD.Texture {
            for value in [source.dictionary,source.texture] {
                guard !value.isEmpty, value.utf8.count <= 63,
                      value.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }) else {
                    throw Failure.invalid("source identity")
                }
            }
            guard let dictionary = dictionaries[source.dictionary] else { throw Failure.missing(source) }
            let matches = dictionary.textures.filter { $0.lookupName == source.texture.lowercased() }
            guard matches.count == 1 else { throw Failure.missing(source) }
            return matches[0]
        }
        for recipe in recipes {
            guard !recipe.output.isEmpty, recipe.output.utf8.count <= 31,
                  recipe.output.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }),
                  names.insert(recipe.output).inserted, recipe.nonzeroAlphaCuts.count <= limits.cutsPerOutput else {
                throw Failure.invalid("output name/cut count")
            }
            let base = try texture(recipe.base), cuts = try recipe.nonzeroAlphaCuts.map(texture)
            guard !base.mipLevels.isEmpty, base.mipLevels.count <= 13,
                  cuts.allSatisfy({ $0.mipLevels.count == base.mipLevels.count }) else { throw Failure.invalid("mip count") }
            var levels: [NativeRenderWareTXD.MipLevel] = []
            for (i, mip) in base.mipLevels.enumerated() {
                if i > 0 {
                    let previous = base.mipLevels[i-1]
                    guard previous.width > 1 || previous.height > 1,
                          mip.width == max(1,previous.width/2), mip.height == max(1,previous.height/2) else { throw Failure.invalid("mip dimensions") }
                }
                guard mip.width > 0, mip.height > 0, mip.width <= 4096, mip.height <= 4096,
                      let source = mip.rgba8, source.count == mip.width * mip.height * 4,
                      source.count <= limits.decodedOutputBytes - byteCount else { throw Failure.limit }
                var rgba = [UInt8](source)
                for cut in cuts {
                    let overlay = cut.mipLevels[i]
                    guard overlay.width == mip.width, overlay.height == mip.height,
                          let data = overlay.rgba8, data.count == rgba.count else { throw Failure.invalid("cut dimensions/body") }
                    let pixels = [UInt8](data)
                    for at in stride(from: 0, to: rgba.count, by: 4) where pixels[at+3] != 0 {
                        for channel in 0..<4 { rgba[at+channel] = pixels[at+channel] }
                    }
                }
                let transparent = stride(from: 3, to: rgba.count, by: 4).contains { rgba[$0] != 255 }
                levels.append(.init(width: mip.width,height: mip.height,encodedByteCount: rgba.count,
                    rgba8: Data(rgba),containsTransparentPixels: transparent)); byteCount += rgba.count
            }
            let alpha = levels.contains { $0.containsTransparentPixels }
            outputs.append(.init(name: recipe.output,maskName: "",filterAddressing: base.filterAddressing,
                rasterFormat: 0x500,d3dFormat: 21,depth: 32,nativeFlags: alpha ? 1 : 0,mipLevels: levels))
        }
        return .init(version: 0x36003,deviceID: 2,textures: outputs,decodedByteCount: byteCount)
    }
}
