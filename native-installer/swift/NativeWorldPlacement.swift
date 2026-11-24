// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Native reader for the PC game's text object definitions and INST placements.
/// The local ordinal of each INST row is its LOD address, including duplicate placements.
enum NativeWorldPlacement {
    struct Definition: Equatable {
        let modelID: Int
        let modelName: String
        let textureName: String
        let drawDistances: [Float]
        let flags: UInt32
        let animation: String?
        let timeOn: Int?
        let timeOff: Int?
    }

    struct Instance: Equatable {
        let modelID: Int
        let modelName: String?
        let interiorFlags: UInt32
        let position: SIMD3<Float>
        let rotation: SIMD4<Float>
        let lodIndex: Int
        var interior: UInt8 { UInt8(truncatingIfNeeded: interiorFlags) }

        func worldTransform() throws -> simd_float4x4 {
            let norm = simd_length_squared(rotation)
            guard norm.isFinite, norm > 0, position.x.isFinite, position.y.isFinite, position.z.isFinite else {
                throw invalid("Invalid transform for model \(modelID).")
            }
            // IPLs store the inverse rotation from model space to GTA world space.
            // The classic placement loader uses heading-only storage for upright objects.
            let tilted = max(abs(rotation.x), abs(rotation.y)) > 0.05 ||
                         (interiorFlags & 0x200 != 0 && rotation.x != 0 && rotation.y != 0)
            let orientation: simd_quatf
            if tilted {
                orientation = simd_quatf(vector: rotation / sqrt(norm)).conjugate
            } else {
                let angle = 2 * acos(max(-1, min(1, rotation.w)))
                orientation = simd_quatf(angle: rotation.z < 0 ? angle : -angle, axis: SIMD3(0, 0, 1))
            }
            var transform = simd_float4x4(orientation)
            transform.columns.3 = SIMD4(position, 1)
            return transform
        }
    }

    struct Region {
        let placementPath: String
        let definitions: [Int: Definition]
        let instances: [Instance]
        var textureParents: [String: String] = [:]

        func parentTextureNames(for dictionary: String) throws -> [String] {
            var current = dictionary.lowercased(), visited: Set<String> = [current], result: [String] = []
            while let parent = textureParents[current] {
                guard result.count < 32, visited.insert(parent).inserted else { throw invalid("Cyclic or excessive TXD parent chain for \(dictionary).") }
                result.append(parent)
                current = parent
            }
            return result
        }

        /// Binary INST rows use the active IDE model ID. Their LOD link indexes
        /// the region's original text instances, even in a short streamed member.
        func resolvedStream(named member: String, instances streamed: [Instance]) throws -> [Instance] {
            let stem = URL(fileURLWithPath: placementPath).deletingPathExtension().lastPathComponent.lowercased()
            let prefix = "\(stem)_stream", filename = member.lowercased()
            guard filename.hasPrefix(prefix), filename.hasSuffix(".ipl"),
                  filename.utf8.count > prefix.utf8.count + 4 else { throw invalid("Stream \(member) does not belong to \(stem).") }
            let suffix = filename.dropFirst(prefix.count).dropLast(4)
            guard suffix.utf8.allSatisfy({ (48...57).contains($0) }) else { throw invalid("Invalid stream name \(member).") }
            return try streamed.enumerated().map { slot, source in
                guard let definition = definitions[source.modelID],
                      source.lodIndex == -1 || instances.indices.contains(source.lodIndex) else {
                    throw invalid("Unresolved model or parent LOD in \(member) at INST \(slot).")
                }
                return Instance(modelID: source.modelID, modelName: definition.modelName, interiorFlags: source.interiorFlags,
                                position: source.position, rotation: source.rotation, lodIndex: source.lodIndex)
            }
        }
    }

    private static let maxFile = 2 * 1024 * 1024
    private static let maxTotal = 24 * 1024 * 1024
    private static let maxRows = 65_536
    private static let separator = CharacterSet(charactersIn: ", \t")
    private static let nameCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-()")
    private static func invalid(_ reason: String) -> NativeISOExtraction.Failure { .invalid(reason) }

    private static func lines(_ data: Data, path: String, _ handle: (Int, String) throws -> Void) throws {
        guard !data.isEmpty, data.count <= maxFile, !data.contains(0) else { throw invalid("Unsupported text file size or encoding in \(path).") }
        guard let text = String(data: data, encoding: .isoLatin1) else { throw invalid("Unsupported text encoding in \(path).") }
        var number = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            number += 1
            guard number <= maxRows, raw.utf8.count <= 8192 else { throw invalid("Text record limit in \(path).") }
            let line = raw.prefix(while: { $0 != "#" }).trimmingCharacters(in: .whitespaces)
            if !line.isEmpty { try handle(number, line) }
        }
    }

    private static func records(_ data: Data, path: String, supported: Set<String>,
                                _ handle: (String, [String], Int) throws -> Void) throws {
        var section: String?
        try lines(data, path: path) { number, line in
            if section == nil {
                guard line != "end", line.utf8.count <= 16,
                      line.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) }) else {
                    throw invalid("Invalid section in \(path) line \(number).")
                }
                section = line.lowercased()
            } else if line.lowercased() == "end" {
                section = nil
            } else if let section, supported.contains(section) {
                let fields = line.components(separatedBy: separator).filter { !$0.isEmpty }
                try handle(section, fields, number)
            }
        }
        guard section == nil else { throw invalid("Unterminated section in \(path).") }
    }

    private static func validName(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 23 && text.unicodeScalars.allSatisfy(nameCharacters.contains)
    }

    static func readDefinitions(_ data: Data, path: String, into definitions: inout [Int: Definition], parents: inout [String: String]) throws {
        try records(data, path: path, supported: ["objs", "tobj", "anim", "txdp"]) { section, fields, number in
            let error = invalid("Invalid \(section) definition in \(path) line \(number).")
            if section == "txdp" {
                guard fields.count == 2, fields.allSatisfy(validName) else { throw error }
                let child = fields[0].lowercased(), parent = fields[1].lowercased()
                if let previous = parents[child], previous != parent { throw invalid("Conflicting TXD parents for \(child).") }
                guard parents.count < maxRows else { throw error }
                parents[child] = parent
                return
            }
            guard fields.count >= 5, let id = Int(fields[0]), (0...19_999).contains(id),
                  validName(fields[1]), validName(fields[2]) else { throw error }
            let timed = section == "tobj"
            let animated = section == "anim"
            let flagsAt = fields.count - (timed ? 3 : 1)
            let distanceStart: Int
            if animated {
                guard fields.count == 6, validName(fields[3]) else { throw error }
                distanceStart = 4
            } else if flagsAt == 4 {
                distanceStart = 3
            } else {
                guard let count = Int(fields[3]), (1...3).contains(count), flagsAt == 4 + count else { throw error }
                distanceStart = 4
            }
            guard let flags = UInt32(fields[flagsAt]) else { throw error }
            let distances = try fields[distanceStart..<flagsAt].map { field -> Float in
                guard let distance = Float(field), distance.isFinite, distance >= 0 else { throw error }
                return distance
            }
            let on = timed ? Int(fields[flagsAt + 1]) : nil
            let off = timed ? Int(fields[flagsAt + 2]) : nil
            if timed {
                guard let on, let off, (0...24).contains(on), (0...24).contains(off) else { throw error }
            }
            let definition = Definition(modelID: id, modelName: fields[1], textureName: fields[2], drawDistances: distances,
                                        flags: flags, animation: animated ? fields[3] : nil, timeOn: on, timeOff: off)
            guard definitions[id] == nil else { throw invalid("Duplicate IDE object ID \(id) in \(path).") }
            definitions[id] = definition
        }
    }

    static func readInstances(_ data: Data, path: String) throws -> [Instance] {
        var result: [Instance] = []
        try records(data, path: path, supported: ["inst"]) { _, fields, number in
            let error = invalid("Invalid INST placement in \(path) line \(number).")
            guard fields.count == 11, let id = Int(fields[0]), (0...19_999).contains(id),
                  validName(fields[1]), let interior = UInt32(fields[2]), let lod = Int(fields[10]),
                  (-1..<maxRows).contains(lod) else { throw error }
            let values = try fields[3..<10].map { field -> Float in
                guard let value = Float(field), value.isFinite else { throw error }
                return value
            }
            let rotation = SIMD4(values[3], values[4], values[5], values[6])
            let norm = (rotation * rotation).sum()
            guard norm > 0, norm.isFinite else { throw error }
            result.append(.init(modelID: id, modelName: fields[1], interiorFlags: interior,
                                position: SIMD3(values[0], values[1], values[2]), rotation: rotation, lodIndex: lod))
        }
        for (index, value) in result.enumerated() where value.lodIndex >= 0 {
            guard result.indices.contains(value.lodIndex), value.lodIndex != index else {
                throw invalid("Invalid text LOD reference at INST \(index) in \(path).")
            }
        }
        return result
    }

    /// Consumes active IDE declarations in original load order. All file paths
    /// for extraction come from the validated cabinet catalogue.
    static func importRegion(from url: URL, placementPath: String, stagingParent: URL,
                             cancellation: NativeISOExtraction.Cancellation) throws -> Region {
        try NativeISOExtraction.withCoordinatedRead(of: url) { file in
            let source = try NativeISOExtraction(source: file, cancellation: cancellation)
            return try importRegion(source: source, placementPath: placementPath, stagingParent: stagingParent)
        }
    }

    static func importRegion(source: NativeISOExtraction, placementPath: String, stagingParent: URL) throws -> Region {
        let catalogue = try source.gameResources()
        let members = Dictionary(uniqueKeysWithValues: catalogue.filter { $0.source == .cabinet }.map { ($0.path.lowercased(), $0) })
        let requested = placementPath.lowercased()
        let stage = stagingParent.appendingPathComponent("world-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stage) }
        func extract(_ paths: [String], to folder: String) throws -> [(String, URL)] {
            var total = 0
            let entries = try paths.map { path -> NativeISOExtraction.Entry in
                guard let entry = members[path], entry.bytes > 0, entry.bytes <= UInt64(maxFile) else {
                    throw invalid("Missing or oversized world source \(path).")
                }
                total += Int(entry.bytes)
                guard total <= maxTotal else { throw invalid("World source selection exceeds the size limit.") }
                return entry
            }
            let destination = stage.appendingPathComponent(folder, isDirectory: true)
            try source.extract(indices: entries.map(\.index), to: destination)
            return entries.map { ($0.path, destination.appendingPathComponent($0.path)) }
        }
        func check() throws {
            if source.cancellation.isCancelled { throw NativeISOExtraction.Failure.cancelled }
        }
        var definitionPaths: [String] = [], seen = Set<String>(), activeIPL = false
        for (path, local) in try extract(["data/default.dat", "data/gta.dat"], to: "configuration") {
            try lines(Data(contentsOf: local), path: path) { number, line in
                let fields = line.split(whereSeparator: \.isWhitespace)
                let directive = fields[0].lowercased()
                guard directive == "ide" || directive == "ipl" else { return }
                guard fields.count == 2 else { throw invalid("Invalid \(directive) declaration in \(path) line \(number).") }
                let key = fields[1].replacingOccurrences(of: "\\", with: "/").lowercased()
                guard NativeRawResourceSelection.isGameResourcePath(key), key.hasPrefix("data/") else {
                    throw invalid("Invalid world source path in \(path) line \(number).")
                }
                if directive == "ipl", key.hasSuffix(".zon") { return }
                guard key.hasSuffix(".\(directive)") else { throw invalid("Unexpected world source type in \(path) line \(number).") }
                if directive == "ide", seen.insert(key).inserted {
                    guard definitionPaths.count < 256 else { throw invalid("Too many active IDE files.") }
                    definitionPaths.append(key)
                }
                if directive == "ipl", key == requested { activeIPL = true }
            }
        }
        guard activeIPL else { throw invalid("The chosen IPL is not active in this disc's configuration.") }
        var definitions: [Int: Definition] = [:], instances: [Instance] = [], parents: [String: String] = [:]
        for (path, local) in try extract(definitionPaths + [requested], to: "world") {
            try check()
            let data = try Data(contentsOf: local)
            if path.lowercased() == requested {
                instances = try readInstances(data, path: path)
            } else {
                try readDefinitions(data, path: path, into: &definitions, parents: &parents)
            }
        }
        for (slot, instance) in instances.enumerated() {
            guard let definition = definitions[instance.modelID],
                  definition.modelName.lowercased() == instance.modelName?.lowercased() else {
                throw invalid("Unresolved model ID/name pair at \(requested) INST \(slot).")
            }
        }
        try check()
        let region = Region(placementPath: requested, definitions: definitions, instances: instances, textureParents: parents)
        for child in parents.keys { _ = try region.parentTextureNames(for: child) }
        return region
    }
}
