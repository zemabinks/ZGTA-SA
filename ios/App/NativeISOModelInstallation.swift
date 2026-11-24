// SPDX-License-Identifier: AGPL-3.0-only
import CryptoKit
import Darwin
import Foundation

/// A typed, partial installation in the same resource store as the playable world.
/// Source clumps retain their frames and material slots. Texture mips are converted
/// once during import and reopened as tightly packed RGBA8 for the game renderer.
enum NativeISOModelInstallation {
    struct Asset {
        let manifest: Manifest
        let dff: Data
        let txd: Data
        let model: NativeRenderWareDFF
        let textures: NativeRenderWareTXD.TextureDictionary
        let plan: NativeRenderWareModel.Plan
    }

    struct Manifest: Codable {
        let schema: Int
        let modelPath: String
        let texturePath: String
        let modelBytes: Int
        let textureBytes: Int
        let rgbaBytes: Int
        let modelSHA256: String
        let textureSHA256: String
        let rgbaSHA256: String
        let dictionaryVersion: UInt32
        let deviceID: UInt16
        fileprivate let textures: [TextureRecord]
    }

    fileprivate struct TextureRecord: Codable {
        let name: String
        let maskName: String
        let filterAddressing: UInt32
        let rasterFormat: UInt32
        let d3dFormat: UInt32
        let depth: UInt8
        let nativeFlags: UInt8
        let levels: [MipRecord]
    }

    fileprivate struct MipRecord: Codable {
        let width: Int
        let height: Int
        let encodedBytes: Int
        let containsTransparentPixels: Bool
    }

    private static let modelPath = "models/grass/plant1.dff"
    private static let texturePath = "models/grass/plant1.txd"
    private static let receiptName = "installed-static-model-v1.zgta"
    private static let magic = Data("ZGTA-RW1".utf8)
    private static let headerLimit = 128 * 1024
    private static let sourceLimit = 4 * 1024 * 1024
    private static let rgbaLimit = 16 * 1024 * 1024
    private static let maxTextures = 128
    private static let maxDimension = 2048

    private static func invalid(_ reason: String) -> NativeISOExtraction.Failure { .invalid(reason) }

    private static func check(_ cancellation: NativeISOExtraction.Cancellation?) throws {
        if cancellation?.isCancelled == true { throw NativeISOExtraction.Failure.cancelled }
    }

    static func install(from url: URL, store: NativeResourceStore, cancellation: NativeISOExtraction.Cancellation,
                        progress: (String) -> Void = { _ in }) throws -> Asset {
        try check(cancellation)
        let stage = store.root.appendingPathComponent("staging/model-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        let paths = try NativeISOExtraction.withCoordinatedRead(of: url) { file in
            progress("Locating the model and texture dictionary in the installer…")
            let extractor = try NativeISOExtraction(source: file, cancellation: cancellation)
            func entry(_ path: String) throws -> NativeISOExtraction.Entry {
                let matches = extractor.entries.filter { $0.path.lowercased() == path }
                guard matches.count == 1, let match = matches.first, match.source == .cabinet else {
                    throw invalid("Expected one installer cabinet member named \(path). Select a compatible PC disc image.")
                }
                guard match.bytes > 0, match.bytes <= UInt64(sourceLimit) else { throw invalid("Unsupported size for \(path).") }
                return match
            }
            let model = try entry(modelPath), texture = try entry(texturePath)
            progress("Extracting the original model and textures…")
            try extractor.extract(indices: [model.index, texture.index], to: stage)
            return (model, texture)
        }
        try check(cancellation)
        progress("Converting the texture mipmaps for Metal…")
        let dff = try readMember(paths.0, in: stage), txd = try readMember(paths.1, in: stage)
        let stagedReceipt = stage.appendingPathComponent(receiptName)
        try writeReceipt(dff: dff, txd: txd, to: stagedReceipt, cancellation: cancellation)
        try check(cancellation)
        progress("Verifying the installed geometry and its material textures…")
        guard let verified = try readReceipt(stagedReceipt, cancellation: cancellation) else { throw invalid("The staged installation is missing.") }
        try check(cancellation)
        let destination = store.root.appendingPathComponent(receiptName)
        guard Darwin.rename(stagedReceipt.path, destination.path) == 0 else { throw posixError() }
        return verified
    }

    /// Reads from one open descriptor so an overlapping replacement cannot mix generations.
    static func load(from store: NativeResourceStore) throws -> Asset? {
        try readReceipt(store.root.appendingPathComponent(receiptName), cancellation: nil)
    }

    private static func readMember(_ entry: NativeISOExtraction.Entry, in stage: URL) throws -> Data {
        let url = stage.appendingPathComponent(entry.path)
        guard let (file, size) = try openRegular(url) else { throw invalid("Missing extracted resource \(entry.path).") }
        defer { try? file.close() }
        guard size == Int64(entry.bytes), size > 0, size <= sourceLimit else { throw invalid("Size mismatch for \(entry.path).") }
        return try readExactly(Int(size), from: file)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func writeReceipt(dff: Data, txd: Data, to url: URL, modelPath: String = NativeISOModelInstallation.modelPath,
                             texturePath: String = NativeISOModelInstallation.texturePath, cancellation: NativeISOExtraction.Cancellation) throws {
        guard (1...sourceLimit).contains(dff.count), (1...sourceLimit).contains(txd.count) else {
            throw invalid("The original model or texture dictionary exceeds the partial-install size limit.")
        }
        var limits = NativeRenderWareTXD.Limits.default
        limits.maximumFileBytes = sourceLimit; limits.maximumDecodedBytes = rgbaLimit
        limits.maximumTextureCount = maxTextures; limits.maximumDimension = maxDimension
        let dictionary: NativeRenderWareTXD.TextureDictionary
        do { dictionary = try NativeRenderWareTXD.decode(txd, limits: limits) }
        catch { throw invalid(String(describing: error)) }
        var rgba = Data()
        rgba.reserveCapacity(dictionary.decodedByteCount)
        let records = try dictionary.textures.map { texture in
            try check(cancellation)
            let levels = texture.mipLevels.map { level in
                if let bytes = level.rgba8 { rgba.append(bytes) }
                return MipRecord(width: level.width, height: level.height, encodedBytes: level.encodedByteCount,
                                 containsTransparentPixels: level.containsTransparentPixels)
            }
            return TextureRecord(name: texture.name, maskName: texture.maskName, filterAddressing: texture.filterAddressing,
                                 rasterFormat: texture.rasterFormat, d3dFormat: texture.d3dFormat, depth: texture.depth,
                                 nativeFlags: texture.nativeFlags, levels: levels)
        }
        let manifest = Manifest(schema: 1, modelPath: modelPath, texturePath: texturePath, modelBytes: dff.count,
                                textureBytes: txd.count, rgbaBytes: rgba.count, modelSHA256: digest(dff), textureSHA256: digest(txd),
                                rgbaSHA256: digest(rgba), dictionaryVersion: dictionary.version, deviceID: dictionary.deviceID, textures: records)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let header = try encoder.encode(manifest)
        guard header.count <= headerLimit else { throw invalid("Installed texture metadata is too large.") }
        let fd = Darwin.open(url.path, O_CREAT | O_EXCL | O_WRONLY | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw posixError() }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        let headerSize = withUnsafeBytes(of: UInt32(header.count).littleEndian) { Data($0) }
        for section in [magic, headerSize, Data(SHA256.hash(data: header)), header, dff, txd, rgba] {
            try check(cancellation)
            try file.write(contentsOf: section)
        }
        try file.synchronize()
    }

    static func readReceipt(_ url: URL, modelPath: String = NativeISOModelInstallation.modelPath, texturePath: String = NativeISOModelInstallation.texturePath,
                            cancellation: NativeISOExtraction.Cancellation?) throws -> Asset? {
        guard let (file, fileSize) = try openRegular(url) else { return nil }
        defer { try? file.close() }
        return try readReceipt(from: file, fileSize: fileSize, modelPath: modelPath, texturePath: texturePath, cancellation: cancellation)
    }

    /// Reads exactly one verified pair, including when embedded in an atomic region installation.
    static func readReceipt(from file: FileHandle, fileSize: Int64, modelPath: String, texturePath: String,
                            cancellation: NativeISOExtraction.Cancellation?) throws -> Asset {
        guard try readExactly(magic.count, from: file) == magic else { throw invalid("Unknown installed model format.") }
        let headerBytes = try readExactly(4, from: file).enumerated().reduce(0) { $0 | (Int($1.element) << (8 * $1.offset)) }
        guard (1...headerLimit).contains(headerBytes) else { throw invalid("Invalid installed model header size.") }
        let headerDigest = try readExactly(SHA256.Digest.byteCount, from: file)
        let header = try readExactly(headerBytes, from: file)
        guard headerDigest.elementsEqual(SHA256.hash(data: header)) else { throw invalid("Installed model manifest checksum mismatch.") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: header)
        guard manifest.schema == 1, manifest.modelPath == modelPath, manifest.texturePath == texturePath,
              (1...sourceLimit).contains(manifest.modelBytes), (1...sourceLimit).contains(manifest.textureBytes),
              (1...rgbaLimit).contains(manifest.rgbaBytes), (1...maxTextures).contains(manifest.textures.count),
              manifest.deviceID == 0 || manifest.deviceID == 2,
              Int64(magic.count + 4 + headerDigest.count + headerBytes + manifest.modelBytes + manifest.textureBytes + manifest.rgbaBytes) == fileSize else {
            throw invalid("Invalid installed model manifest or payload sizes.")
        }
        let dff = try readExactly(manifest.modelBytes, from: file), txd = try readExactly(manifest.textureBytes, from: file)
        let rgba = try readExactly(manifest.rgbaBytes, from: file)
        try check(cancellation)
        guard digest(dff) == manifest.modelSHA256, digest(txd) == manifest.textureSHA256, digest(rgba) == manifest.rgbaSHA256 else {
            throw invalid("Installed model or texture checksum mismatch.")
        }
        let textures = try restoreTextures(manifest, rgba: rgba)
        do {
            let model = try NativeRenderWareDFF.decode(dff)
            let plan = try NativeRenderWareModel.prepare(dff: model, txd: textures)
            guard !plan.draws.isEmpty, !plan.textures.isEmpty,
                  !plan.diagnostics.contains(where: { if case .missingTexture = $0 { return true }; return false }) else {
                throw invalid("The installed clump has no complete textured draw.")
            }
            return Asset(manifest: manifest, dff: dff, txd: txd, model: model, textures: textures, plan: plan)
        } catch let error as NativeISOExtraction.Failure { throw error }
        catch { throw invalid(String(describing: error)) }
    }

    private static func restoreTextures(_ manifest: Manifest, rgba: Data) throws -> NativeRenderWareTXD.TextureDictionary {
        var offset = 0
        let textures: [NativeRenderWareTXD.Texture] = try manifest.textures.map { texture in
            guard (1...13).contains(texture.levels.count), let base = texture.levels.first,
                  (1...maxDimension).contains(base.width), (1...maxDimension).contains(base.height), base.encodedBytes > 0 else {
                throw invalid("Invalid installed mip chain.")
            }
            let levels: [NativeRenderWareTXD.MipLevel] = try texture.levels.enumerated().map { index, mip in
                guard mip.width == max(1, base.width >> index), mip.height == max(1, base.height >> index),
                      (0...manifest.textureBytes).contains(mip.encodedBytes) else { throw invalid("Invalid installed mip dimensions.") }
                let size = mip.encodedBytes == 0 ? 0 : mip.width * mip.height * 4
                guard size <= rgba.count - offset else { throw invalid("Installed mip exceeds the converted texture payload.") }
                let pixels = size == 0 ? nil : rgba.subdata(in: offset..<(offset + size))
                offset += size
                return .init(width: mip.width, height: mip.height, encodedByteCount: mip.encodedBytes,
                             rgba8: pixels, containsTransparentPixels: mip.containsTransparentPixels)
            }
            return .init(name: texture.name, maskName: texture.maskName, filterAddressing: texture.filterAddressing,
                         rasterFormat: texture.rasterFormat, d3dFormat: texture.d3dFormat, depth: texture.depth,
                         nativeFlags: texture.nativeFlags, mipLevels: levels)
        }
        guard offset == rgba.count else { throw invalid("Unexpected trailing converted texture data.") }
        return .init(version: manifest.dictionaryVersion, deviceID: manifest.deviceID, textures: textures, decodedByteCount: offset)
    }

    private static func openRegular(_ url: URL) throws -> (FileHandle, Int64)? {
        let fd = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { if errno == ENOENT { return nil }; throw posixError() }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard Darwin.fstat(fd, &info) == 0 else { throw posixError() }
        guard info.st_mode & S_IFMT == S_IFREG else { throw invalid("Expected a regular local resource file.") }
        return (file, info.st_size)
    }

    private static func readExactly(_ count: Int, from file: FileHandle) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let chunk = try file.read(upToCount: count - result.count), !chunk.isEmpty else { throw invalid("Truncated installed resource.") }
            result.append(chunk)
        }
        return result
    }

    private static func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
