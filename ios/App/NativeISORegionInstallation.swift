// SPDX-License-Identifier: AGPL-3.0-only
import CryptoKit
import Darwin
import Foundation

/// Durable map section with separate authored visual and collision resources. Keeps original placement ordinals for LOD links;
/// registration with physics and admission as a complete playable world are separate.
enum NativeISORegionInstallation {
    struct Region {
        let placementPath: String
        let models: [Int: NativeRenderWareModel.Plan]
        let instances: [NativeWorldPlacement.Instance]
        let sourceSlots: [Int]
        let collisions: [Int: NativeRenderWareCollision.Model]
    }

    private struct PlacedModel: Codable {
        let slot: Int
        let id: Int
        let model: String
        let dictionary: String
        let position: SIMD3<Float>
        let rotation: SIMD4<Float>
        let interior: UInt32
        let lod: Int
        let pairBytes: Int64
        let dffSHA256: String
        let txdSHA256: String
        let collisionCollection: String?
        let collisionBytes: Int?
        let collisionSHA256: String?
    }
    private struct Index: Codable {
        let schema: Int
        let placementPath: String
        let models: [PlacedModel]
    }

    private static let placementPath = "data/maps/la/lae.ipl"
    // These adjacent exterior placements share an IDE texture dictionary and
    // have distinct authored transforms and LOD targets. LOD is kept as metadata.
    private static let selectedSlots = [62, 64]
    private static let magic = Data("ZGTA-LA1".utf8)
    private static let receiptName = "installed-lae-section-v1.zgta"
    private static let maximumPairBytes: Int64 = 25 * 1024 * 1024
    private static let indexLimit = 64 * 1024

    static func install(from url: URL, store: NativeResourceStore, cancellation: NativeISOExtraction.Cancellation,
                        progress: (String) -> Void = { _ in }) throws -> Region {
        func check() throws { if cancellation.isCancelled { throw NativeISOExtraction.Failure.cancelled } }
        try check()
        let staging = store.root.appendingPathComponent("staging", isDirectory: true)
        let output = staging.appendingPathComponent("placed-models-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: output) }
        // Check the selected source for replacement between the two coordinated ISO reads.
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let before = try sourceStamp(url)
        progress("Reading the original Los Santos object definitions and placements…")
        let world = try NativeWorldPlacement.importRegion(from: url, placementPath: placementPath, stagingParent: staging, cancellation: cancellation)
        try check()
        progress("Extracting the original world archive…")
        let records = try NativeISOArchiveModel.withExtractedArchive(from: url, stagingParent: staging, cancellation: cancellation) { archive in
            let names = try selectedSlots.map { slot -> String in
                guard world.instances.indices.contains(slot), let name = world.instances[slot].modelName else { throw fail("Unresolved world placement.") }
                return name
            }
            let collision = try archive.collisionRecords(for: Set(names), region: "lae", cancellation: cancellation)
            return try selectedSlots.map { slot -> PlacedModel in
                try check()
                guard world.instances.indices.contains(slot) else { throw fail("This disc does not contain the selected Los Santos section.") }
                let instance = world.instances[slot]
                guard instance.interior == 0, let definition = world.definitions[instance.modelID],
                      instance.modelName?.lowercased() == definition.modelName.lowercased() else { throw fail("Unresolved exterior placement at slot \(slot).") }
                progress("Converting \(definition.modelName) and its material textures…")
                let dff = definition.modelName.lowercased() + ".dff", txd = definition.textureName.lowercased() + ".txd"
                let source = try archive.sourcePair(modelName: definition.modelName, textureName: definition.textureName, cancellation: cancellation)
                let path = output.appendingPathComponent("\(slot).pair")
                try NativeISOModelInstallation.writeReceipt(dff: source.dff, txd: source.txd, to: path, modelPath: dff, texturePath: txd, cancellation: cancellation)
                let bytes = try path.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard bytes > 0, bytes <= maximumPairBytes else { throw fail("Converted placement exceeds the installed resource budget.") }
                guard let coll = collision[definition.modelName.lowercased()], coll.bytes.count <= 2 * 1024 * 1024 else { throw fail("Missing exact authored collision for \(definition.modelName).") }
                try coll.bytes.write(to: output.appendingPathComponent("\(slot).col"), options: .withoutOverwriting)
                return PlacedModel(slot: slot, id: instance.modelID, model: definition.modelName, dictionary: definition.textureName,
                                   position: instance.position, rotation: instance.rotation, interior: instance.interiorFlags, lod: instance.lodIndex,
                                   pairBytes: Int64(bytes), dffSHA256: digest(source.dff), txdSHA256: digest(source.txd),
                                   collisionCollection: coll.collection, collisionBytes: coll.bytes.count, collisionSHA256: digest(coll.bytes))
            }
        }
        guard try sourceStamp(url) == before else { throw fail("The source ISO changed during installation. Select the disc image again.") }
        try check()
        let index = Index(schema: 2, placementPath: world.placementPath, models: records)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let header = try encoder.encode(index)
        guard header.count <= indexLimit else { throw fail("The placement index exceeds its size limit.") }
        let staged = output.appendingPathComponent(receiptName)
        let fd = Darwin.open(staged.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ioError() }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        let size = withUnsafeBytes(of: UInt32(header.count).littleEndian) { Data($0) }
        for data in [magic, size, Data(SHA256.hash(data: header)), header] { try file.write(contentsOf: data) }
        for record in records {
            let source = try FileHandle(forReadingFrom: output.appendingPathComponent("\(record.slot).pair"))
            defer { try? source.close() }
            var remaining = record.pairBytes
            while remaining > 0 {
                try check()
                let data = try exact(Int(min(remaining, 512 * 1024)), from: source)
                try file.write(contentsOf: data)
                remaining -= Int64(data.count)
            }
            let collision = try FileHandle(forReadingFrom: output.appendingPathComponent("\(record.slot).col"))
            defer { try? collision.close() }
            guard let count = record.collisionBytes else { throw fail("Missing authored collision receipt.") }
            try file.write(contentsOf: exact(count, from: collision))
        }
        try file.synchronize()
        progress("Verifying the placed models and textures…")
        guard let verified = try read(staged, cancellation: cancellation) else { throw fail("The staged map section is missing.") }
        try check()
        guard Darwin.rename(staged.path, store.root.appendingPathComponent(receiptName).path) == 0 else { throw ioError() }
        return verified
    }

    static func load(from store: NativeResourceStore) throws -> Region? {
        try read(store.root.appendingPathComponent(receiptName), cancellation: nil)
    }

    private static func read(_ url: URL, cancellation: NativeISOExtraction.Cancellation?) throws -> Region? {
        let fd = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { if errno == ENOENT { return nil }; throw ioError() }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close() }
        var info = stat(); guard fstat(fd, &info) == 0 else { throw ioError() }
        guard info.st_mode & S_IFMT == S_IFREG, try exact(magic.count, from: file) == magic else { throw fail("Invalid installed map section.") }
        let size = try exact(4, from: file).withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        guard (1...indexLimit).contains(size) else { throw fail("Invalid installed placement header size.") }
        let headerDigest = try exact(SHA256.Digest.byteCount, from: file), header = try exact(size, from: file)
        guard headerDigest.elementsEqual(SHA256.hash(data: header)) else { throw fail("Installed placement index checksum mismatch.") }
        let index = try JSONDecoder().decode(Index.self, from: header)
        guard (1...2).contains(index.schema), index.placementPath == placementPath, index.models.map(\.slot) == selectedSlots,
              Set(index.models.map(\.id)).count == index.models.count, index.models.allSatisfy({ (1...maximumPairBytes).contains($0.pairBytes) }),
              index.models.allSatisfy({ index.schema == 1 ? $0.collisionBytes == nil : (32...2 * 1024 * 1024).contains($0.collisionBytes ?? 0) }),
              Int64(magic.count + 4 + headerDigest.count + size) + index.models.reduce(0, { $0 + $1.pairBytes + Int64($1.collisionBytes ?? 0) }) == info.st_size else { throw fail("Invalid installed placement manifest.") }
        var models: [Int: NativeRenderWareModel.Plan] = [:], instances: [NativeWorldPlacement.Instance] = []
        var collisions: [Int: NativeRenderWareCollision.Model] = [:]
        for record in index.models {
            if cancellation?.isCancelled == true { throw NativeISOExtraction.Failure.cancelled }
            guard (0...19_999).contains(record.id), record.position.x.isFinite, record.position.y.isFinite, record.position.z.isFinite,
                  !record.model.isEmpty, !record.dictionary.isEmpty, record.model.utf8.count <= 23, record.dictionary.utf8.count <= 23 else { throw fail("Invalid installed model identity or position.") }
            let instance = NativeWorldPlacement.Instance(modelID: record.id, modelName: record.model, interiorFlags: record.interior,
                                                        position: record.position, rotation: record.rotation, lodIndex: record.lod)
            _ = try instance.worldTransform()
            let asset = try NativeISOModelInstallation.readReceipt(from: file, fileSize: record.pairBytes, modelPath: record.model.lowercased() + ".dff",
                                                                    texturePath: record.dictionary.lowercased() + ".txd", cancellation: cancellation)
            guard asset.manifest.modelSHA256 == record.dffSHA256, asset.manifest.textureSHA256 == record.txdSHA256 else { throw fail("Placed model differs from the original source identity.") }
            if let count = record.collisionBytes {
                let bytes = try exact(count, from: file)
                guard digest(bytes) == record.collisionSHA256, record.collisionCollection?.hasSuffix(".col") == true else { throw fail("Invalid installed collision provenance or checksum.") }
                let decoded: [NativeRenderWareCollision.Model]
                do { decoded = try NativeRenderWareCollision.decode(bytes) }
                catch { throw fail(String(describing: error)) }
                guard decoded.count == 1, let model = decoded.first, model.name?.lowercased() == record.model.lowercased(), model.hasCollisionVolumes else { throw fail("The authored collision does not belong to \(record.model).") }
                collisions[record.id] = model
            }
            models[record.id] = asset.plan; instances.append(instance)
        }
        return Region(placementPath: index.placementPath, models: models, instances: instances, sourceSlots: selectedSlots, collisions: collisions)
    }

    private struct Stamp: Equatable { let size: UInt64; let inode: UInt64; let modification: Date }
    private static func sourceStamp(_ url: URL) throws -> Stamp {
        try NativeISOExtraction.withCoordinatedRead(of: url) { file in
            let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
            guard let bytes = attrs[.size] as? NSNumber, let inode = attrs[.systemFileNumber] as? NSNumber,
                  let modified = attrs[.modificationDate] as? Date else { throw fail("Could not identify the selected disc image.") }
            return Stamp(size: bytes.uint64Value, inode: inode.uint64Value, modification: modified)
        }
    }
    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func fail(_ description: String) -> NativeISOExtraction.Failure { .invalid(description) }
    private static func ioError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    private static func exact(_ size: Int, from file: FileHandle) throws -> Data {
        var data = Data()
        while data.count < size {
            guard let chunk = try file.read(upToCount: size - data.count), !chunk.isEmpty else { throw fail("Truncated installed map section.") }
            data.append(chunk)
        }
        return data
    }
}
