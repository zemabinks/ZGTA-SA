// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit

// Compiled with the production CPU decoder. Golden manifests and owner-local
// pixels are generated under local-only/research, never embedded in this source.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else { fail("usage: txd-tests manifest.json") }
let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
let object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
guard let cases = object as? [[String: Any]] else { fail("invalid manifest") }
var failures: [String] = []
var successCount = 0, rejectionCount = 0, decodedBytes = 0, decodedTextures = 0, decodedMips = 0, absentMips = 0
for entry in cases {
    guard let label = entry["label"] as? String, let path = entry["path"] as? String else { fail("invalid case") }
    var limits = NativeRenderWareTXD.Limits.default
    if let values = entry["limits"] as? [String: Int] {
        for (key, value) in values {
            switch key {
            case "fileBytes": limits.maximumFileBytes = value
            case "textureCount": limits.maximumTextureCount = value
            case "dimension": limits.maximumDimension = value
            case "mipLevels": limits.maximumMipLevels = value
            case "decodedBytes": limits.maximumDecodedBytes = value
            case "chunkCount": limits.maximumChunkCount = value
            default: fail("unknown limit \(key)")
            }
        }
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        // A Data subsequence may carry a nonzero startIndex; exercise that path too.
        var padded = Data([0xFA, 0xCE]); padded.append(data)
        let decoded = try NativeRenderWareTXD.decode(padded.dropFirst(2), limits: limits)
        if let reason = entry["error"] as? String {
            failures.append("\(label): accepted input expected to fail with \(reason)")
            continue
        }
        let textures: [[String: Any]] = decoded.textures.map { texture in
            let mips: [[String: Any]] = texture.mipLevels.map { mip in
                ["width": mip.width, "height": mip.height, "encodedByteCount": mip.encodedByteCount,
                 "rowBytes": mip.rowBytes, "transparent": mip.containsTransparentPixels,
                 "sha256": mip.rgba8.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } as Any? ?? NSNull()]
            }
            return ["name": texture.name, "lookupName": texture.lookupName, "maskName": texture.maskName,
                    "filterAddressing": texture.filterAddressing, "rasterFormat": texture.rasterFormat,
                    "d3dFormat": texture.d3dFormat, "depth": texture.depth, "nativeFlags": texture.nativeFlags,
                    "declaresAlpha": texture.declaresAlpha, "automaticMipmaps": texture.usesAutomaticMipmaps,
                    "transparent": texture.containsTransparentPixels, "mips": mips]
        }
        let actual: [String: Any] = ["version": decoded.version, "deviceID": decoded.deviceID,
                                     "decodedBytes": decoded.decodedByteCount, "textures": textures]
        guard let expected = entry["expected"] as? [String: Any] else { fail("\(label): expected data missing") }
        if !NSDictionary(dictionary: actual).isEqual(to: expected) {
            let actualData = try JSONSerialization.data(withJSONObject: actual, options: [.sortedKeys])
            let expectedData = try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys])
            failures.append("\(label): pixel/metadata mismatch\nexpected \(String(decoding: expectedData, as: UTF8.self))\nactual   \(String(decoding: actualData, as: UTF8.self))")
        } else {
            successCount += 1
            decodedBytes += decoded.decodedByteCount
            decodedTextures += decoded.textures.count
            decodedMips += decoded.textures.reduce(0) { $0 + $1.mipLevels.filter { $0.rgba8 != nil }.count }
            absentMips += decoded.textures.reduce(0) { $0 + $1.mipLevels.filter { $0.rgba8 == nil }.count }
        }
    } catch let error as NativeRenderWareTXD.DecodeError {
        let kind: String
        switch error {
        case .malformed: kind = "malformed"
        case .unsupported: kind = "unsupported"
        case .limitExceeded: kind = "limitExceeded"
        }
        if entry["error"] as? String == kind { rejectionCount += 1 }
        else { failures.append("\(label): unexpected \(error)") }
    } catch { failures.append("\(label): unexpected non-decoder error \(error)") }
}
let summary: [String: Any] = ["cases": cases.count, "accepted": successCount, "rejected": rejectionCount,
                             "decodedTextures": decodedTextures, "storedMips": decodedMips,
                             "absentTailMips": absentMips, "decodedRGBABytes": decodedBytes,
                             "failures": failures.count]
print(String(decoding: try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys]), as: UTF8.self))
if !failures.isEmpty { fail(failures.prefix(12).joined(separator: "\n")) }
