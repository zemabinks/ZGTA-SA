// SPDX-License-Identifier: AGPL-3.0-only
import Darwin
import Foundation

/// Resolves exact DFF/TXD identifiers in a single VER2 image. Builds the index
/// once per archive and reads only requested members. Source-sector allocation
/// and RenderWare stream size intentionally have separate bounds.
final class NativeISOArchiveModel {
    struct Asset {
        let dff: Data
        let txd: Data
        let model: NativeRenderWareDFF
        let textures: NativeRenderWareTXD.TextureDictionary
        let plan: NativeRenderWareModel.Plan
    }

    enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let reason) = self { return reason }; return nil }
    }

    private let entries: [String: [NativeVER2Archive.Entry]]
    private let read: (Int64, Int) throws -> Data
    private static let memberLimit = 32 * 1024 * 1024
    private static let encodedLimit = 64 * 1024 * 1024
    private static let decodedLimit = 64 * 1024 * 1024

    /// For normal resource-store access the captured lease pins its verified generation.
    convenience init(lease: NativeRawResourceLease) throws {
        try self.init(byteCount: lease.binding.bytes, read: { try lease.read(atOffset: $0, maximumBytes: $1) })
    }

    /// For a private file freshly extracted into the installer's owned staging directory.
    convenience init(archive: URL) throws {
        guard archive.isFileURL else { throw Failure.invalid("Choose a local game archive.") }
        let fd = Darwin.open(archive.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let stamp = try NativeRawResourceFileStamp.read(fd)
        try self.init(byteCount: stamp.size) { offset, count in
            guard (0...NativeRawResourceLease.maximumReadBytes).contains(count), offset >= 0, offset <= stamp.size,
                  Int64(count) <= stamp.size - offset, try NativeRawResourceFileStamp.read(file.fileDescriptor) == stamp else {
                throw Failure.invalid("The local image changed or the requested byte range is invalid.")
            }
            var data = Data(count: count)
            try data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
                var done = 0
                while done < count {
                    let n = Darwin.pread(file.fileDescriptor, buffer.baseAddress!.advanced(by: done), count - done, offset + Int64(done))
                    if n < 0 { if errno == EINTR { continue }; throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                    guard n > 0 else { throw Failure.invalid("Unexpected end of the local image.") }
                    done += n
                }
            }
            guard try NativeRawResourceFileStamp.read(file.fileDescriptor) == stamp else { throw Failure.invalid("The local image changed while reading it.") }
            return data
        }
    }

    private init(byteCount: Int64, read: @escaping (Int64, Int) throws -> Data) throws {
        self.read = read
        let rows = try NativeVER2Archive.scan(byteCount: byteCount, read: read)
        entries = Dictionary(grouping: rows, by: \.name)
    }

    /// Reads the installer archive once for a group of conversions. A caller
    /// with a verified raw generation should open its lease instead.
    static func withExtractedArchive<T>(from iso: URL, stagingParent: URL, cancellation: NativeISOExtraction.Cancellation,
                                        progress: ((NativeISOExtraction.Progress) -> Void)? = nil,
                                        _ convert: (NativeISOArchiveModel) throws -> T) throws -> T {
        let stage = stagingParent.appendingPathComponent("world-image-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        let member = try NativeISOExtraction.withCoordinatedRead(of: iso) { file in
            let extractor = try NativeISOExtraction(source: file, cancellation: cancellation)
            let matches = extractor.entries.filter { $0.path.lowercased() == "models/gta3.img" }
            guard matches.count == 1, let member = matches.first, member.source == .cabinet,
                  member.bytes >= 2048, member.bytes <= 8 * 1024 * 1024 * 1024, member.bytes.isMultiple(of: 2048) else {
                throw Failure.invalid("Expected a compatible original models/gta3.img in the installer cabinet.")
            }
            try extractor.extract(indices: [member.index], to: stage, progress: progress)
            return member
        }
        if cancellation.isCancelled { throw NativeISOExtraction.Failure.cancelled }
        let archive = try NativeISOArchiveModel(archive: stage.appendingPathComponent(member.path))
        return try convert(archive)
    }

    /// Names in numeric stream order. Only the exact region basename followed
    /// by _stream and a decimal number matches. The archive may also hold unrelated IPLs.
    func streamedPlacementNames(for region: String) -> [String] {
        let prefix = region.lowercased() + "_stream"
        guard !region.isEmpty else { return [] }
        return entries.keys.filter { name in
            guard name.hasPrefix(prefix), name.hasSuffix(".ipl"), name.utf8.count > prefix.utf8.count + 4 else { return false }
            return name.utf8.dropFirst(prefix.utf8.count).dropLast(4).allSatisfy { (48...57).contains($0) }
        }.sorted { left, right in
            let l = left.utf8.dropFirst(prefix.utf8.count).dropLast(4), r = right.utf8.dropFirst(prefix.utf8.count).dropLast(4)
            return l.count == r.count ? l.lexicographicallyPrecedes(r) : l.count < r.count
        }
    }

    /// The binary IPL reader owns the logical table extents. Preserve the
    /// allocation tail here and never strip possibly significant zero bytes.
    func readPlacement(named name: String, cancellation: NativeISOExtraction.Cancellation? = nil) throws -> Data {
        let key = name.lowercased()
        guard key.hasSuffix(".ipl"), !key.contains("/"), !key.contains("\\") else { throw Failure.invalid("Expected a binary IPL member name.") }
        return try allocatedMember(key, limit: Self.memberLimit) {
            if cancellation?.isCancelled == true { throw NativeISOExtraction.Failure.cancelled }
        }
    }

    struct CollisionRecord {
        let collection: String
        let bytes: Data
    }

    /// Regional collision collections contain named records with independent
    /// lengths. The original header ID is a hint; exact IDE model names bind COLs.
    func collisionRecords(for names: Set<String>, region: String, cancellation: NativeISOExtraction.Cancellation?) throws -> [String: CollisionRecord] {
        let requested = Set(names.map { $0.lowercased() })
        guard !requested.isEmpty, requested.count <= 256, !region.isEmpty else { throw Failure.invalid("Invalid regional collision query.") }
        let prefix = region.lowercased() + "_"
        let collections = entries.keys.filter { name in
            guard name.hasPrefix(prefix), name.hasSuffix(".col"), name.utf8.count > prefix.utf8.count + 4 else { return false }
            return name.utf8.dropFirst(prefix.utf8.count).dropLast(4).allSatisfy { (48...57).contains($0) }
        }.sorted()
        guard collections.count <= 64 else { throw Failure.invalid("Too many regional collision collections.") }
        var result: [String: CollisionRecord] = [:], remaining = 64 * 1024 * 1024
        func check() throws { if cancellation?.isCancelled == true { throw NativeISOExtraction.Failure.cancelled } }
        for collection in collections {
            let bytes = try allocatedMember(collection, limit: min(Self.memberLimit, remaining), check: check)
            remaining -= bytes.count
            var offset = 0
            while offset < bytes.count {
                try check()
                let available = bytes.count - offset
                if available < 32 || bytes[offset] == 0 {
                    guard available < 2048, bytes[offset...].allSatisfy({ $0 == 0 }) else { throw Failure.invalid("Invalid COL sector tail in \(collection).") }
                    break
                }
                let kind = bytes[offset..<(offset + 4)]
                guard kind.elementsEqual("COLL".utf8) || kind.elementsEqual("COL2".utf8) || kind.elementsEqual("COL3".utf8) else { throw Failure.invalid("Unknown record in \(collection).") }
                let declared = bytes.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self))) }
                guard declared >= 24, declared <= available - 8 else { throw Failure.invalid("Invalid record length in \(collection).") }
                let end = offset + 8 + declared
                let ascii = bytes[(offset + 8)..<(offset + 30)].prefix(while: { $0 != 0 })
                guard !ascii.isEmpty, ascii.allSatisfy({ (32...126).contains($0) }) else { throw Failure.invalid("Invalid model name in \(collection).") }
                let name = String(decoding: ascii, as: UTF8.self).lowercased()
                if requested.contains(name) {
                    let data = bytes.subdata(in: offset..<end)
                    guard result[name] == nil || result[name]?.bytes == data else { throw Failure.invalid("Ambiguous authored collision for \(name).") }
                    if result[name] == nil { result[name] = CollisionRecord(collection: collection, bytes: data) }
                }
                offset = end
            }
        }
        return result
    }

    /// Logical unpadded source streams for the durable on-device converter.
    func sourcePair(modelName: String, textureName: String, cancellation: NativeISOExtraction.Cancellation?) throws -> (dff: Data, txd: Data) {
        func check() throws { if cancellation?.isCancelled == true { throw NativeISOExtraction.Failure.cancelled } }
        try check()
        let dff = try member(memberName(modelName, suffix: ".dff"), rootKind: 0x10, limit: Self.memberLimit, check: check)
        let txd = try member(memberName(textureName, suffix: ".txd"), rootKind: 0x16, limit: Self.memberLimit, check: check)
        return (dff, txd)
    }

    /// Expects IDE basenames and explicit TXDP ancestors nearest-first. Child
    /// textures take precedence. Duplicate archive rows cannot select arbitrarily.
    func prepare(modelName: String, textureName: String, parentTextureNames: [String] = [],
                 cancellation: NativeISOExtraction.Cancellation? = nil) throws -> Asset {
        func check() throws { if cancellation?.isCancelled == true { throw NativeISOExtraction.Failure.cancelled } }
        try check()
        let dffName = try memberName(modelName, suffix: ".dff")
        guard parentTextureNames.count < 32 else { throw Failure.invalid("Texture dictionary ancestry is too deep.") }
        let dictionaries = try ([textureName] + parentTextureNames).map { try memberName($0, suffix: ".txd") }
        guard Set(dictionaries).count == dictionaries.count else { throw Failure.invalid("Cyclic texture dictionary ancestry.") }
        let source = try member(dffName, rootKind: 0x10, limit: Self.memberLimit, check: check)
        var encodedBytes = source.count, decodedBytes = 0, textureCount = 0
        var textures: [NativeRenderWareTXD.Texture] = [], names = Set<String>()
        var firstTXD = Data(), version: UInt32 = 0, deviceID: UInt16 = 0
        do {
            let model = try NativeRenderWareDFF.decode(source)
            for (index, name) in dictionaries.enumerated() {
                try check()
                let bytes = try member(name, rootKind: 0x16, limit: min(Self.memberLimit, Self.encodedLimit - encodedBytes), check: check)
                encodedBytes += bytes.count
                var limits = NativeRenderWareTXD.Limits.default
                limits.maximumDecodedBytes = Self.decodedLimit - decodedBytes
                limits.maximumTextureCount -= textureCount
                guard limits.maximumDecodedBytes > 0, limits.maximumTextureCount > 0 else { throw Failure.invalid("Texture dictionary budget exceeded.") }
                let dictionary = try NativeRenderWareTXD.decode(bytes, limits: limits)
                if index == 0 { firstTXD = bytes; version = dictionary.version; deviceID = dictionary.deviceID }
                decodedBytes += dictionary.decodedByteCount; textureCount += dictionary.textures.count
                for texture in dictionary.textures where names.insert(texture.lookupName).inserted { textures.append(texture) }
            }
            try check()
            let dictionary = NativeRenderWareTXD.TextureDictionary(version: version, deviceID: deviceID, textures: textures, decodedByteCount: decodedBytes)
            let plan = try NativeRenderWareModel.prepare(dff: model, txd: dictionary)
            guard !plan.draws.isEmpty else { throw Failure.invalid("The selected model has no compatible static draws.") }
            for issue in plan.diagnostics {
                if case .missingTexture(_, _, let name) = issue { throw Failure.invalid("Missing material texture \(name) for \(modelName).") }
            }
            try check()
            return Asset(dff: source, txd: firstTXD, model: model, textures: dictionary, plan: plan)
        } catch let error as NativeISOExtraction.Failure { throw error }
        catch let error as LocalizedError { throw error }
        catch { throw Failure.invalid(String(describing: error)) }
    }

    private func memberName(_ base: String, suffix: String) throws -> String {
        let lower = base.lowercased()
        guard !base.isEmpty, base.utf8.count + suffix.utf8.count <= 24,
              lower.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || [35, 40, 41, 43, 45, 95].contains($0) }) else {
            throw Failure.invalid("Invalid model or texture dictionary identifier.")
        }
        return lower + suffix
    }

    private func allocatedMember(_ name: String, limit: Int, check: () throws -> Void) throws -> Data {
        guard let matches = entries[name], matches.count == 1, let row = matches.first else {
            throw Failure.invalid("Missing or ambiguous archive member \(name).")
        }
        guard row.allocatedBytes >= 12, row.allocatedBytes <= limit else { throw Failure.invalid("Archive member \(name) exceeds the byte budget.") }
        let total = Int(row.allocatedBytes)
        var bytes = Data()
        bytes.reserveCapacity(total)
        while bytes.count < total {
            try check()
            let count = min(NativeRawResourceLease.maximumReadBytes, total - bytes.count)
            let part = try read(row.offset + Int64(bytes.count), count)
            guard part.count == count else { throw Failure.invalid("Truncated member \(name).") }
            bytes.append(part)
        }
        return bytes
    }

    private func member(_ name: String, rootKind: UInt32, limit: Int, check: () throws -> Void) throws -> Data {
        let bytes = try allocatedMember(name, limit: limit, check: check)
        let total = bytes.count
        func word(_ offset: Int) -> UInt32 {
            bytes.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
        }
        guard word(0) == rootKind else { throw Failure.invalid("Wrong RenderWare root in \(name).") }
        let rootBytes = Int(word(4))
        guard rootBytes <= total - 12 else { throw Failure.invalid("Truncated RenderWare root in \(name).") }
        var end = rootBytes + 12
        // A DFF may carry one top-level extension after the clump. Its payload
        // can genuinely end in zeros. Consume only declared lengths.
        if rootKind == 0x10, total - end >= 12, bytes[end..<(end + 12)].contains(where: { $0 != 0 }) {
            let length = Int(word(end + 4))
            guard word(end) == 3, length <= total - end - 12 else { throw Failure.invalid("Invalid trailing clump extension in \(name).") }
            end += 12 + length
        }
        guard total - end < 2048, bytes[end...].allSatisfy({ $0 == 0 }) else { throw Failure.invalid("Invalid sector tail in \(name).") }
        return Data(bytes.prefix(end))
    }
}
