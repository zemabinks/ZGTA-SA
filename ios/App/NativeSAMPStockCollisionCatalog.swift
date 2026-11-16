// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit

/// Owner-local external COL association. Explicit owner IDE IDs resolve exact
/// names; the original header ID is preserved and verified as a nonbinding hint.
/// Primary lookup reference: gta-reversed FileLoader.cpp blob a575e2b0625addd1d2b75e72e710efd4f5f303d5.
/// No reference implementation is copied or linked.
/// This CPU provider does not download files or register physical bodies.
struct NativeSAMPStockCollisionCatalog {
    struct Limits {
        var metadataBytes = 16 * 1024 * 1024
        var models = 30_000
        var records = 100_000
        var aliases = 100_000
        var fileBytes = 32 * 1024 * 1024
    }
    enum Failure: Error, CustomStringConvertible {
        case malformed, limit, invalidName, invalidURL, headerIdentity, size, checksum, sha256
        var description: String {
            switch self {
            case .malformed: return "Malformed stock COL catalog"
            case .limit: return "Stock COL catalog/resource limit"
            case .invalidName: return "Invalid stock COL model name or ID"
            case .invalidURL: return "Invalid stock COL asset path/origin"
            case .headerIdentity: return "Stock COL name, ID or version differs from the exact requested model"
            case .size: return "Stock COL bytes differ from the catalog"
            case .checksum: return "Stock COL CRC32 mismatch"
            case .sha256: return "Stock COL SHA-256 mismatch"
            }
        }
    }
    struct Source: Decodable {
        let archive: String?
        let file: String?
        let collection: String
        let collectionOffset: Int
        let recordOffset: Int
    }
    struct Record: Decodable {
        let path: String
        let bytes: Int
        let crc32: UInt32
        let sha256: String
        let version: Int
        let headerModelID: UInt16
        let headerName: String
        /// Identical original bytes may have multiple explicit archive aliases.
        let sources: [Source]
    }
    struct Binding: Decodable {
        let id: Int32
        let source: String
        let line: Int
        let sourceSHA256: String
    }
    struct File {
        let modelID: Int32
        let modelName: String
        let metadata: Record
        let url: URL
        let binding: Binding
    }
    enum Resolution {
        case missing(modelID: Int32, modelName: String)
        case unique(File)
        case ambiguous(modelID: Int32, modelName: String, candidates: [File])
        case noAuthoredCollision(modelID: Int32, modelName: String)
    }
    struct Coverage: Decodable {
        struct ExplicitFile: Decodable { let path: String; let bytes: Int; let sha256: String }
        let complete: Bool
        let scope: String
        let stockManifestSHA256: String
        let archiveCount: Int
        let explicitCOLFiles: [ExplicitFile]
    }
    private struct Row: Decodable { let name: String; let bindings: [Binding]; let records: [Record] }
    private struct Manifest: Decodable { let schema: Int; let models: [Row]; let coverage: Coverage? }
    private let models: [String: Row]
    private let maximumFileBytes: Int
    let coverage: Coverage?
    var modelNames: [String] { models.keys.sorted() }

    static func decode(_ data: Data, limits: Limits = .init()) throws -> Self {
        guard limits.metadataBytes > 0, limits.metadataBytes <= 32 * 1024 * 1024,
              (1...100_000).contains(limits.models), (1...100_000).contains(limits.records),
              (1...1_000_000).contains(limits.aliases), (72...32 * 1024 * 1024).contains(limits.fileBytes),
              data.count <= limits.metadataBytes else { throw Failure.limit }
        let value = try JSONDecoder().decode(Manifest.self, from: data)
        guard value.schema == 2 else { throw Failure.malformed }
        if let coverage=value.coverage {
            guard coverage.complete,coverage.scope=="stock-manifest-img-and-active-colfile",
                  validSHA(coverage.stockManifestSHA256),(1...16).contains(coverage.archiveCount),
                  coverage.explicitCOLFiles.count<=256 else{throw Failure.malformed}
            var paths=Set<String>()
            for file in coverage.explicitCOLFiles {
                guard validPath(file.path),file.path.lowercased().hasSuffix(".col"),paths.insert(file.path.lowercased()).inserted,
                      (72...32*1024*1024).contains(file.bytes),validSHA(file.sha256)else{throw Failure.malformed}
            }
        }
        guard value.models.count <= limits.models else { throw Failure.limit }
        var models: [String: Row] = [:], records = 0, aliases = 0, ids = Set<Int32>()
        for row in value.models {
            guard validName(row.name), row.name == row.name.lowercased(), models[row.name] == nil else { throw Failure.malformed }
            guard !row.bindings.isEmpty, row.bindings.count <= limits.models - ids.count else { throw Failure.limit }
            for binding in row.bindings {
                guard (0...19999).contains(binding.id), ids.insert(binding.id).inserted,
                      validPath(binding.source), binding.line > 0, binding.line <= 1_000_000,
                      binding.sourceSHA256.utf8.count == 64,
                      binding.sourceSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw Failure.malformed }
            }
            guard row.records.count <= limits.records - records else { throw Failure.limit }
            records += row.records.count
            var digests = Set<String>()
            for record in row.records {
                guard (72...limits.fileBytes).contains(record.bytes), (1...3).contains(record.version),
                      validName(record.headerName), record.headerName.lowercased() == row.name,
                      record.sha256.utf8.count == 64,
                      record.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
                      digests.insert(record.sha256).inserted else { throw Failure.malformed }
                guard validPath(record.path), record.path.hasSuffix("/" + record.sha256 + ".col") else { throw Failure.invalidURL }
                guard !record.sources.isEmpty, record.sources.count <= limits.aliases - aliases else { throw Failure.limit }
                aliases += record.sources.count
                var identities = Set<String>()
                for source in record.sources {
                    let origin: String
                    if let archive=source.archive {
                        guard source.file==nil,validName(archive),archive.lowercased().hasSuffix(".img")else{throw Failure.malformed}
                        origin=archive.lowercased()
                    }else {
                        guard let file=source.file,validPath(file),file.lowercased().hasSuffix(".col"),
                              file.split(separator:"/").last?.lowercased()==source.collection.lowercased(),
                              source.collectionOffset==0 else{throw Failure.malformed}
                        origin=file.lowercased()
                    }
                    guard validName(source.collection), source.collection.lowercased().hasSuffix(".col"),
                          source.collectionOffset >= 0, source.collectionOffset <= 4 * 1024 * 1024 * 1024,
                          source.collectionOffset % 2048 == 0,
                          source.recordOffset >= 0, source.recordOffset <= 32 * 1024 * 1024,
                          identities.insert("\(origin)/\(source.collection.lowercased())/\(source.collectionOffset)/\(source.recordOffset)").inserted else {
                        throw Failure.malformed
                    }
                }
            }
            models[row.name] = row
        }
        return Self(models: models, maximumFileBytes: limits.fileBytes, coverage:value.coverage)
    }

    func resolve(modelID: Int32, modelName: String, source: String? = nil, line: Int? = nil,
                 stockManifestSHA256: String? = nil,
                 assetBaseURL: URL, allowLocalFiles: Bool = false) throws -> Resolution {
        guard (0...19999).contains(modelID), Self.validName(modelName) else { throw Failure.invalidName }
        let name = modelName.lowercased()
        guard Self.validBase(assetBaseURL, allowLocalFiles: allowLocalFiles) else { throw Failure.invalidURL }
        guard let row = models[name] else { return .missing(modelID: modelID, modelName: name) }
        guard let binding = row.bindings.first(where: { $0.id == modelID }),
              (source == nil && line == nil) || (source == binding.source && line == binding.line) else { throw Failure.headerIdentity }
        let records = row.records
        if records.isEmpty {
            if let coverage,coverage.complete,coverage.stockManifestSHA256==stockManifestSHA256 {
                return .noAuthoredCollision(modelID:modelID,modelName:name)
            }
            return .missing(modelID: modelID, modelName: name)
        }
        var files: [File] = []
        for record in records {
            var url = assetBaseURL
            for part in record.path.split(separator: "/") { url.appendPathComponent(String(part)) }
            if url.isFileURL {
                let root = assetBaseURL.resolvingSymlinksInPath().standardizedFileURL.path
                let target = url.resolvingSymlinksInPath().standardizedFileURL.path
                guard target.hasPrefix(root.hasSuffix("/") ? root : root + "/") else { throw Failure.invalidURL }
            }
            files.append(File(modelID: modelID, modelName: name, metadata: record, url: url, binding: binding))
        }
        return files.count == 1 ? .unique(files[0]) : .ambiguous(modelID: modelID, modelName: name, candidates: files)
    }

    /// Call only after a bounded file acquisition. All advertised identity is
    /// rechecked here before the bounded geometry parser sees the bytes.
    func prepare(_ data: Data, for file: File) throws -> NativeRenderWareCollision.Model {
        guard (0...19999).contains(file.modelID), Self.validName(file.modelName),
              file.metadata.headerName.lowercased() == file.modelName,
              let row = models[file.modelName], row.bindings.contains(where: {
                  $0.id == file.modelID && $0.source == file.binding.source && $0.line == file.binding.line &&
                  $0.sourceSHA256 == file.binding.sourceSHA256
              }), row.records.contains(where: {
                  $0.sha256 == file.metadata.sha256 && $0.bytes == file.metadata.bytes &&
                  $0.crc32 == file.metadata.crc32 && $0.path == file.metadata.path &&
                  $0.headerModelID == file.metadata.headerModelID && $0.headerName == file.metadata.headerName &&
                  $0.version == file.metadata.version
              }) else { throw Failure.headerIdentity }
        guard data.count == file.metadata.bytes, data.count <= maximumFileBytes else { throw Failure.size }
        guard Self.crc32(data) == file.metadata.crc32 else { throw Failure.checksum }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == file.metadata.sha256 else { throw Failure.sha256 }
        var limits = NativeRenderWareCollision.Limits()
        limits.fileBytes = maximumFileBytes; limits.models = 1
        let models = try NativeRenderWareCollision.decode(data, limits: limits)
        guard models.count == 1, let model = models.first,
              model.name?.lowercased() == file.modelName, model.modelID == file.metadata.headerModelID,
              model.version.rawValue == file.metadata.version else { throw Failure.headerIdentity }
        return model
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb88320 : 0) }
        }
        return ~crc
    }
    private static func validName(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && !value.contains("..") &&
        value != "." && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || [95,35,40,41,43,45,46].contains($0)
        }
    }
    private static func validSHA(_ value:String)->Bool {
        value.utf8.count==64 && value.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}
    }
    private static func validPath(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 1_024 &&
        value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { validName(String($0)) }
    }
    private static func validBase(_ url: URL, allowLocalFiles: Bool) -> Bool {
        guard url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return false }
        if url.isFileURL {
            return allowLocalFiles && (url.host == nil || url.host == "" || url.host == "localhost")
        }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "") &&
            !(url.host ?? "").isEmpty && (url.port.map { (1...65535).contains($0) } ?? true)
    }
}
