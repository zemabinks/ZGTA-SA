// SPDX-License-Identifier: AGPL-3.0-only
// Independently implemented from this project's owner-local model/skeleton
// exporters. This CPU decoder does not contain or redistribute game assets.
import Foundation
import simd

/// Bounded decoder for little-endian, non-native PC RenderWare clumps.
/// Coordinates, winding, material colours and frame names are preserved. Engine
/// coordinate conversion, vehicle visibility rules, texture resolution and GPU
/// resource creation belong to the caller, not the file decoder.
struct NativeRenderWareDFF {
    struct Limits {
        var fileBytes = 64 * 1024 * 1024
        var chunks = 65_536
        var frames = 2_048
        var geometries = 1_024
        var atomics = 4_096
        var verticesPerGeometry = 100_000
        var trianglesPerGeometry = 200_000
        var totalVertices = 1_000_000
        var totalTriangles = 2_000_000
        var materialsPerGeometry = 4_096
        var morphTargets = 16
        var textureCoordinateSets = 8
        var bones = 256
        var stringBytes = 1_024
    }

    enum Failure: Error, CustomStringConvertible {
        case malformed(String)
        case limit(String)
        case unsupported(String)
        var description: String {
            switch self {
            case .malformed(let message): return "Malformed DFF: \(message)"
            case .limit(let message): return "DFF limit: \(message)"
            case .unsupported(let message): return "Unsupported DFF: \(message)"
            }
        }
    }

    struct HAnimNode {
        let id: UInt32
        let index: Int
        let flags: UInt32
    }
    struct HAnim {
        let version: UInt32
        let id: UInt32
        let flags: UInt32
        let keyFrameSize: UInt32
        let nodes: [HAnimNode]
    }
    struct Frame {
        let name: String?
        let parent: Int // -1 denotes the clump root.
        let flags: UInt32
        let localTransform: simd_float4x4
        let worldTransform: simd_float4x4
        let hierarchy: HAnim?
    }
    struct Material {
        let flags: UInt32
        let color: SIMD4<UInt8>
        let textureName: String?
        let maskName: String?
        let textureFilterAndAddressing: UInt32?
        let surface: SIMD3<Float>? // ambient, specular, diffuse, in file order.
    }
    struct Triangle {
        let a: UInt16
        let b: UInt16
        let c: UInt16
        let material: UInt16
    }
    struct MorphTarget {
        let boundingSphere: SIMD4<Float>
        let positions: [SIMD3<Float>]
        let normals: [SIMD3<Float>]
    }
    struct Skin {
        let boneCount: Int
        let usedBones: [UInt8]
        let maximumWeights: Int
        let indices: [SIMD4<UInt8>]
        let weights: [SIMD4<Float>]
        /// RenderWare matrices have padding in each fourth component. These
        /// matrices restore the affine row (0,0,0,1), as the project exporter does.
        let inverseBindMatrices: [simd_float4x4]
    }
    struct Geometry {
        let flags: UInt16
        let vertexCount: Int
        let textureCoordinates: [[SIMD2<Float>]]
        let prelitColors: [SIMD4<UInt8>]
        let triangles: [Triangle]
        /// Includes material-list references resolved into their original slots.
        let materials: [Material]
        let morphTargets: [MorphTarget]
        let skin: Skin?
        var positions: [SIMD3<Float>] { morphTargets.first?.positions ?? [] }
        var normals: [SIMD3<Float>] { morphTargets.first?.normals ?? [] }
    }
    struct Atomic {
        let frame: Int
        let geometry: Int
        let flags: UInt32
        let unused: UInt32
    }

    let version: UInt32
    let frames: [Frame]
    let geometries: [Geometry]
    let atomics: [Atomic]

    static func decode(_ data: Data, limits: Limits = Limits()) throws -> Self {
        try DFFDecoder(data, limits: limits).decode()
    }
}

private struct DFFChunk {
    let kind: UInt32
    let start: Int
    let end: Int
    let version: UInt32
}

/// All integer reads are explicitly little endian, including unaligned reads.
/// Never bind an untrusted byte buffer to a native pointer or simd type.
private struct DFFReader {
    let bytes: [UInt8]
    var offset: Int
    let end: Int
    var remaining: Int { end - offset }
    mutating func require(_ count: Int) throws {
        guard count >= 0, count <= remaining else {
            throw NativeRenderWareDFF.Failure.malformed("truncated field at \(offset)")
        }
    }
    mutating func skip(_ count: Int) throws { try require(count); offset += count }
    mutating func u8() throws -> UInt8 {
        try require(1); defer { offset += 1 }; return bytes[offset]
    }
    mutating func u16() throws -> UInt16 {
        try require(2); defer { offset += 2 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }
    mutating func u32() throws -> UInt32 {
        try require(4); defer { offset += 4 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
            UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
    mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
    mutating func f32() throws -> Float {
        let value = Float(bitPattern: try u32())
        guard value.isFinite else {
            throw NativeRenderWareDFF.Failure.malformed("non-finite float at \(offset - 4)")
        }
        return value
    }
    mutating func v2() throws -> SIMD2<Float> { try SIMD2(f32(), f32()) }
    mutating func v3() throws -> SIMD3<Float> { try SIMD3(f32(), f32(), f32()) }
    mutating func v4() throws -> SIMD4<Float> { try SIMD4(f32(), f32(), f32(), f32()) }
    mutating func rgba() throws -> SIMD4<UInt8> { try SIMD4(u8(), u8(), u8(), u8()) }
    mutating func finished(_ field: String) throws {
        guard offset == end else {
            throw NativeRenderWareDFF.Failure.malformed("unexpected \(field) bytes at \(offset)")
        }
    }
}

private final class DFFDecoder {
    typealias DFF = NativeRenderWareDFF
    let bytes: [UInt8]
    let limits: DFF.Limits
    var chunksRead = 0
    var totalVertices = 0
    var totalTriangles = 0

    init(_ data: Data, limits: DFF.Limits) throws {
        guard limits.fileBytes > 0, data.count <= limits.fileBytes else {
            throw DFF.Failure.limit("file bytes")
        }
        self.bytes = Array(data)
        self.limits = limits
    }
    func reader(_ chunk: DFFChunk) -> DFFReader {
        DFFReader(bytes: bytes, offset: chunk.start, end: chunk.end)
    }
    func count(_ value: UInt32, maximum: Int, field: String) throws -> Int {
        guard maximum >= 0, UInt64(value) <= UInt64(maximum) else {
            throw DFF.Failure.limit(field)
        }
        return Int(value)
    }
    func children(start: Int, end: Int, sectorPadding: Bool = false) throws -> [DFFChunk] {
        var input = DFFReader(bytes: bytes, offset: start, end: end)
        var result: [DFFChunk] = []
        while input.remaining > 0 {
            // IMG extraction can retain the final sector's unused zero bytes.
            // Permit a bounded final pad only at the complete stream boundary;
            // a chunk's declared payload is always parsed with strict bounds.
            if sectorPadding, bytes[input.offset..<end].allSatisfy({ $0 == 0 }) {
                guard bytes.count % 2048 == 0, input.remaining < 2048 else {
                    throw DFF.Failure.malformed("invalid IMG sector padding")
                }
                break
            }
            try input.require(12)
            let kind = try input.u32()
            let length = try input.u32()
            let library = try input.u32()
            guard UInt64(length) <= UInt64(input.remaining) else {
                throw DFF.Failure.malformed("chunk \(kind) exceeds its parent")
            }
            chunksRead += 1
            guard chunksRead <= limits.chunks else { throw DFF.Failure.limit("chunk count") }
            let version = library & 0xffff0000 == 0 ? library << 8 :
                ((library >> 14) & 0x3ff00) + 0x30000 | ((library >> 16) & 0x3f)
            result.append(DFFChunk(kind: kind, start: input.offset,
                                   end: input.offset + Int(length), version: version))
            try input.skip(Int(length))
        }
        return result
    }
    func children(_ chunk: DFFChunk) throws -> [DFFChunk] {
        try children(start: chunk.start, end: chunk.end)
    }
    func one(_ children: [DFFChunk], _ kind: UInt32, optional: Bool = false) throws -> DFFChunk? {
        let matches = children.filter { $0.kind == kind }
        guard matches.count <= 1, optional || matches.count == 1 else {
            throw DFF.Failure.malformed("missing or duplicate chunk \(kind)")
        }
        return matches.first
    }
    func required(_ children: [DFFChunk], _ kind: UInt32) throws -> DFFChunk {
        // one() checks presence before the optional is unwrapped.
        try one(children, kind)!
    }
    func string(_ chunk: DFFChunk) throws -> String {
        guard chunk.end - chunk.start <= limits.stringBytes else { throw DFF.Failure.limit("string bytes") }
        let raw = bytes[chunk.start..<chunk.end].prefix { $0 != 0 }
        guard !raw.contains(where: { $0 < 32 || $0 == 127 }) else {
            throw DFF.Failure.malformed("control byte in name")
        }
        // PC model names are normally ASCII, but preserve extended legacy names.
        return String(data: Data(raw), encoding: .utf8) ??
            String(data: Data(raw), encoding: .isoLatin1) ?? ""
    }

    func decode() throws -> DFF {
        guard bytes.count >= 12 else { throw DFF.Failure.malformed("missing clump header") }
        if bytes[0...3].elementsEqual([0, 0, 0, 0x10]) {
            throw DFF.Failure.unsupported("big-endian RenderWare")
        }
        let top = try children(start: 0, end: bytes.count, sectorPadding: true)
        guard top.count == 1 || top.count == 2, top.first?.kind == 0x10,
              top.count == 1 || top[1].kind == 3 else {
            throw DFF.Failure.malformed("expected clump and optional top-level extension")
        }
        if top.count == 2 { _ = try children(top[1]) }
        let root = top[0]
        guard root.version >= 0x30000, root.version < 0x40000 else {
            throw DFF.Failure.unsupported("RenderWare version \(root.version)")
        }
        let parts = try children(root)
        // Light/camera attachments also have STRUCT chunks directly in the
        // clump; only the first STRUCT is the clump header.
        guard let clumpHeader = parts.first, clumpHeader.kind == 1 else {
            throw DFF.Failure.malformed("missing clump struct")
        }
        var clump = reader(clumpHeader)
        let atomicCount = try count(clump.u32(), maximum: limits.atomics, field: "atomics")
        var lightCount = 0, cameraCount = 0
        if root.version > 0x33000 {
            lightCount = try count(clump.u32(), maximum: limits.frames, field: "clump lights")
            cameraCount = try count(clump.u32(), maximum: limits.frames, field: "clump cameras")
        }
        try clump.finished("clump struct")
        let frames = try decodeFrames(required(parts, 0xe))
        var lights = 0, cameras = 0, attachment = 1
        while attachment < parts.count {
            if parts[attachment].kind == 1 {
                guard attachment + 1 < parts.count,
                      parts[attachment + 1].kind == 0x12 || parts[attachment + 1].kind == 5 else {
                    throw DFF.Failure.malformed("unpaired clump attachment struct")
                }
                var binding = reader(parts[attachment])
                let frame = Int(try binding.u32())
                try binding.finished("light/camera frame binding")
                guard frame < frames.count else { throw DFF.Failure.malformed("light/camera frame index") }
                // Lights/cameras are not geometry. Validate their chunk framing
                // and retain the mesh instead of rejecting aircraft/boat clumps.
                _ = try required(children(parts[attachment + 1]), 1)
                if parts[attachment + 1].kind == 0x12 { lights += 1 } else { cameras += 1 }
                attachment += 2
            } else if parts[attachment].kind == 0x12 || parts[attachment].kind == 5 {
                throw DFF.Failure.malformed("unbound clump light/camera")
            } else { attachment += 1 }
        }
        guard lights == lightCount, cameras == cameraCount else { throw DFF.Failure.malformed("light/camera count") }
        let list = try children(required(parts, 0x1a))
        var geometryList = reader(try required(list, 1))
        let geometryCount = try count(geometryList.u32(), maximum: limits.geometries, field: "geometries")
        try geometryList.finished("geometry list")
        let geometryChunks = list.filter { $0.kind == 0xf }
        guard geometryChunks.count == geometryCount else { throw DFF.Failure.malformed("geometry count") }
        let geometries = try geometryChunks.map(decodeGeometry)
        let atomicChunks = parts.filter { $0.kind == 0x14 }
        guard atomicChunks.count == atomicCount else { throw DFF.Failure.malformed("atomic count") }
        var atomics: [DFF.Atomic] = []
        for atomic in atomicChunks {
            var data = reader(try required(children(atomic), 1))
            let frame = try data.u32(), geometry = try data.u32()
            let flags = try data.u32(), unused = try data.u32()
            try data.finished("atomic struct")
            guard Int(frame) < frames.count, Int(geometry) < geometries.count else {
                throw DFF.Failure.malformed("atomic frame/geometry index")
            }
            atomics.append(DFF.Atomic(frame: Int(frame), geometry: Int(geometry), flags: flags, unused: unused))
        }
        try validateSkinHierarchies(frames: frames, geometries: geometries, atomics: atomics)
        return DFF(version: root.version, frames: frames, geometries: geometries, atomics: atomics)
    }

    func decodeFrames(_ chunk: DFFChunk) throws -> [DFF.Frame] {
        let parts = try children(chunk)
        var data = reader(try required(parts, 1))
        let size = try count(data.u32(), maximum: limits.frames, field: "frames")
        try data.require(size * 56)
        var transforms: [simd_float4x4] = [], parents: [Int] = [], flags: [UInt32] = []
        for index in 0..<size {
            let x = try data.v3(), y = try data.v3(), z = try data.v3(), t = try data.v3()
            let parent = Int(try data.i32()), frameFlags = try data.u32()
            guard parent >= -1, parent < size, parent != index else { throw DFF.Failure.malformed("frame parent") }
            transforms.append(simd_float4x4(SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(t, 1)))
            parents.append(parent); flags.append(frameFlags)
        }
        try data.finished("frame list")
        let extensions = parts.filter { $0.kind == 3 }
        guard extensions.count == size else { throw DFF.Failure.malformed("frame extension count") }
        var names: [String?] = [], hierarchies: [DFF.HAnim?] = []
        for item in extensions {
            let plugins = try children(item)
            names.append(try one(plugins, 0x253f2fe, optional: true).map(string))
            hierarchies.append(try one(plugins, 0x11e, optional: true).map(decodeHAnim))
        }
        // Iterative ancestry traversal bounds stack use even for a hostile chain.
        var worlds = [simd_float4x4?](repeating: nil, count: size)
        for index in 0..<size {
            var path: [Int] = [], seen = Set<Int>(), at = index
            while at >= 0, worlds[at] == nil {
                guard seen.insert(at).inserted else { throw DFF.Failure.malformed("frame parent cycle") }
                path.append(at); at = parents[at]
            }
            var parent = at >= 0 ? worlds[at]! : matrix_identity_float4x4
            for node in path.reversed() {
                let world = parent * transforms[node]
                guard finite(world) else { throw DFF.Failure.malformed("non-finite world transform") }
                worlds[node] = world; parent = world
            }
        }
        return (0..<size).map { DFF.Frame(name: names[$0], parent: parents[$0], flags: flags[$0],
                                         localTransform: transforms[$0], worldTransform: worlds[$0]!,
                                         hierarchy: hierarchies[$0]) }
    }
    func finite(_ value: simd_float4x4) -> Bool {
        (0..<4).allSatisfy { column in (0..<4).allSatisfy { value[column][$0].isFinite } }
    }
    func decodeHAnim(_ chunk: DFFChunk) throws -> DFF.HAnim {
        var data = reader(chunk)
        let version = try data.u32(), id = try data.u32()
        let count = try count(data.u32(), maximum: limits.bones, field: "HAnim nodes")
        var flags: UInt32 = 0, keyFrameSize: UInt32 = 0, nodes: [DFF.HAnimNode] = []
        if count > 0 {
            flags = try data.u32(); keyFrameSize = try data.u32()
            try data.require(count * 12)
            var ids = Set<UInt32>(), indices = Set<Int>()
            for _ in 0..<count {
                let nodeID = try data.u32(), index = Int(try data.u32()), nodeFlags = try data.u32()
                guard index < count, ids.insert(nodeID).inserted, indices.insert(index).inserted else {
                    throw DFF.Failure.malformed("HAnim node/palette index")
                }
                nodes.append(DFF.HAnimNode(id: nodeID, index: index, flags: nodeFlags))
            }
        }
        try data.finished("HAnim plugin")
        return DFF.HAnim(version: version, id: id, flags: flags, keyFrameSize: keyFrameSize, nodes: nodes)
    }

    func decodeGeometry(_ chunk: DFFChunk) throws -> DFF.Geometry {
        let parts = try children(chunk), info = try required(parts, 1)
        var data = reader(info)
        let flags = try data.u16(), specifiedUVSets = Int(try data.u8()), native = try data.u8()
        guard native == 0 else { throw DFF.Failure.unsupported("platform-native geometry (\(native))") }
        let triangleCount = try count(data.u32(), maximum: limits.trianglesPerGeometry, field: "geometry triangles")
        let vertexCount = try count(data.u32(), maximum: limits.verticesPerGeometry, field: "geometry vertices")
        let morphCount = try count(data.u32(), maximum: limits.morphTargets, field: "morph targets")
        guard morphCount > 0 else { throw DFF.Failure.malformed("missing morph target") }
        totalVertices += vertexCount; totalTriangles += triangleCount
        guard totalVertices <= limits.totalVertices, totalTriangles <= limits.totalTriangles else {
            throw DFF.Failure.limit("total mesh elements")
        }
        // RenderWare < 3.4 stores surface properties in the geometry header.
        if info.version < 0x34000 { _ = try data.v3() }
        let uvCount = specifiedUVSets > 0 ? specifiedUVSets : (flags & 0x80 != 0 ? 2 : (flags & 4 != 0 ? 1 : 0))
        guard uvCount <= limits.textureCoordinateSets else { throw DFF.Failure.limit("texture coordinate sets") }
        var prelit: [SIMD4<UInt8>] = []
        if flags & 8 != 0 {
            try data.require(vertexCount * 4)
            prelit.reserveCapacity(vertexCount)
            for _ in 0..<vertexCount { prelit.append(try data.rgba()) }
        }
        var uvs: [[SIMD2<Float>]] = []
        for _ in 0..<uvCount {
            try data.require(vertexCount * 8)
            var layer: [SIMD2<Float>] = []; layer.reserveCapacity(vertexCount)
            for _ in 0..<vertexCount { layer.append(try data.v2()) }; uvs.append(layer)
        }
        try data.require(triangleCount * 8)
        var triangles: [DFF.Triangle] = []; triangles.reserveCapacity(triangleCount)
        for _ in 0..<triangleCount {
            let b = try data.u16(), a = try data.u16(), material = try data.u16(), c = try data.u16()
            guard Int(a) < vertexCount, Int(b) < vertexCount, Int(c) < vertexCount else {
                throw DFF.Failure.malformed("triangle vertex index")
            }
            triangles.append(DFF.Triangle(a: a, b: b, c: c, material: material))
        }
        var morphs: [DFF.MorphTarget] = []
        for index in 0..<morphCount {
            let sphere = try data.v4(), hasPositions = try data.u32(), hasNormals = try data.u32()
            guard sphere.w >= 0, hasPositions <= 1, hasNormals <= 1 else { throw DFF.Failure.malformed("morph header") }
            guard index != 0 || hasPositions == 1 || vertexCount == 0 else {
                throw DFF.Failure.malformed("base morph has no positions")
            }
            var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = []
            if hasPositions != 0 {
                try data.require(vertexCount * 12); positions.reserveCapacity(vertexCount)
                for _ in 0..<vertexCount { positions.append(try data.v3()) }
            }
            if hasNormals != 0 {
                try data.require(vertexCount * 12); normals.reserveCapacity(vertexCount)
                for _ in 0..<vertexCount { normals.append(try data.v3()) }
            }
            morphs.append(DFF.MorphTarget(boundingSphere: sphere, positions: positions, normals: normals))
        }
        try data.finished("geometry struct")
        let materials = try decodeMaterials(required(parts, 8))
        guard triangles.allSatisfy({ Int($0.material) < materials.count }) else {
            throw DFF.Failure.malformed("triangle material index")
        }
        var skin: DFF.Skin?
        if let extensionChunk = try one(parts, 3, optional: true) {
            let plugins = try children(extensionChunk)
            if let skinChunk = try one(plugins, 0x116, optional: true) {
                skin = try decodeSkin(skinChunk, vertexCount: vertexCount)
            }
        }
        return DFF.Geometry(flags: flags, vertexCount: vertexCount, textureCoordinates: uvs, prelitColors: prelit,
                            triangles: triangles, materials: materials, morphTargets: morphs, skin: skin)
    }

    func decodeMaterials(_ chunk: DFFChunk) throws -> [DFF.Material] {
        let parts = try children(chunk)
        var data = reader(try required(parts, 1))
        let size = try count(data.u32(), maximum: limits.materialsPerGeometry, field: "materials")
        try data.require(size * 4)
        var references: [Int] = []
        for slot in 0..<size {
            let reference = Int(try data.i32())
            guard reference >= -1, reference < slot else { throw DFF.Failure.malformed("material reference") }
            references.append(reference)
        }
        try data.finished("material list")
        let materialChunks = parts.filter { $0.kind == 7 }
        guard materialChunks.count == references.filter({ $0 == -1 }).count else {
            throw DFF.Failure.malformed("material chunk count")
        }
        var materials: [DFF.Material] = [], next = 0
        for reference in references {
            if reference >= 0 { materials.append(materials[reference]) }
            else { materials.append(try decodeMaterial(materialChunks[next])); next += 1 }
        }
        return materials
    }
    func decodeMaterial(_ chunk: DFFChunk) throws -> DFF.Material {
        let parts = try children(chunk), info = try required(parts, 1)
        var data = reader(info)
        let flags = try data.u32(), color = try data.rgba()
        _ = try data.u32()
        let textured = try data.u32()
        guard textured <= 1 else { throw DFF.Failure.malformed("material texture flag") }
        let surface = info.version >= 0x30400 ? try data.v3() : nil
        try data.finished("material struct")
        var name: String?, mask: String?, filter: UInt32?
        let texture = try one(parts, 6, optional: true)
        guard (texture != nil) == (textured != 0) else { throw DFF.Failure.malformed("material texture chunk") }
        if let texture {
            let textureParts = try children(texture)
            var info = reader(try required(textureParts, 1))
            filter = try info.u32(); try info.finished("texture struct")
            let strings = textureParts.filter { $0.kind == 2 }
            guard strings.count == 2 else { throw DFF.Failure.malformed("texture name/mask count") }
            name = try string(strings[0]); mask = try string(strings[1])
        }
        return DFF.Material(flags: flags, color: color, textureName: name, maskName: mask,
                            textureFilterAndAddressing: filter, surface: surface)
    }

    func decodeSkin(_ chunk: DFFChunk, vertexCount: Int) throws -> DFF.Skin {
        var data = reader(chunk)
        let bones = Int(try data.u8()), used = Int(try data.u8()), maxWeights = Int(try data.u8())
        _ = try data.u8()
        guard bones > 0, bones <= limits.bones, used <= bones, maxWeights <= 4 else {
            throw DFF.Failure.malformed("skin counts")
        }
        // The old pre-3.4 skin layout inserts a sentinel before each matrix and
        // does not carry an explicit used-bone palette. Reject rather than guess.
        guard used > 0 else { throw DFF.Failure.unsupported("legacy skin without used-bone palette") }
        try data.require(used + vertexCount * 20 + bones * 64)
        var usedBones: [UInt8] = [], seen = Set<UInt8>()
        for _ in 0..<used {
            let bone = try data.u8()
            guard Int(bone) < bones, seen.insert(bone).inserted else { throw DFF.Failure.malformed("used bone index") }
            usedBones.append(bone)
        }
        var indices: [SIMD4<UInt8>] = [], weights: [SIMD4<Float>] = []
        indices.reserveCapacity(vertexCount); weights.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            let index = try data.rgba()
            guard (0..<4).allSatisfy({ Int(index[$0]) < bones }) else { throw DFF.Failure.malformed("skin bone index") }
            indices.append(index)
        }
        for _ in 0..<vertexCount {
            let weight = try data.v4(), sum = weight.x + weight.y + weight.z + weight.w
            guard (0..<4).allSatisfy({ weight[$0] >= 0 && weight[$0] <= 1.0001 }),
                  sum.isFinite, abs(sum - 1) <= 0.01,
                  (0..<4).filter({ weight[$0] > 0.000001 }).count <= maxWeights else {
                throw DFF.Failure.malformed("skin weights")
            }
            weights.append(weight)
        }
        var inverse: [simd_float4x4] = []
        for _ in 0..<bones {
            // The fourth word of each RW vector is padding/flags, not a float.
            // Some original models contain NaN bit patterns in those words.
            // Validate all twelve actual matrix components and ignore padding.
            let x = try data.v3(); try data.skip(4)
            let y = try data.v3(); try data.skip(4)
            let z = try data.v3(); try data.skip(4)
            let t = try data.v3(); try data.skip(4)
            inverse.append(simd_float4x4(SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(t, 1)))
        }
        // The modern PC skin plugin ends with three split-mesh counters. Actual
        // split-mesh remapping is platform-specific and not supported here.
        if data.remaining != 0 {
            guard data.remaining == 12 else { throw DFF.Failure.unsupported("skin split-mesh payload") }
            let boneLimit = try data.u32(), meshes = try data.u32(), rle = try data.u32()
            guard boneLimit == 0, meshes == 0, rle == 0 else { throw DFF.Failure.unsupported("skin split-mesh remapping") }
        }
        try data.finished("skin plugin")
        return DFF.Skin(boneCount: bones, usedBones: usedBones, maximumWeights: maxWeights,
                        indices: indices, weights: weights, inverseBindMatrices: inverse)
    }

    func validateSkinHierarchies(frames: [DFF.Frame], geometries: [DFF.Geometry], atomics: [DFF.Atomic]) throws {
        // A palette must resolve within the atomic's connected frame tree. This
        // also allows distinct skeletons in a multi-atomic clump to reuse IDs.
        // Cache roots and palettes once. An adversarial long ancestry chain with
        // many atomics must not rewalk every frame tree for every atomic.
        var roots = [Int](repeating: -1, count: frames.count)
        for index in frames.indices {
            var at = index, path: [Int] = []
            while roots[at] < 0, frames[at].parent >= 0 {
                path.append(at); at = frames[at].parent
            }
            let root = roots[at] >= 0 ? roots[at] : at
            roots[at] = root
            for frame in path { roots[frame] = root }
        }
        var trees: [Int: [Int]] = [:]
        for index in frames.indices { trees[roots[index], default: []].append(index) }
        var validatedPalettes: [Int: Int] = [:]
        for atomic in atomics {
            guard let skin = geometries[atomic.geometry].skin else { continue }
            let treeRoot = roots[atomic.frame]
            if let count = validatedPalettes[treeRoot] {
                guard count == skin.boneCount else { throw DFF.Failure.malformed("skin/HAnim palette mismatch") }
                continue
            }
            let treeFrames = trees[treeRoot] ?? []
            var frameIDs: [UInt32: Int] = [:]
            for index in treeFrames {
                if let hierarchy = frames[index].hierarchy {
                    guard frameIDs.updateValue(index, forKey: hierarchy.id) == nil else {
                        throw DFF.Failure.malformed("duplicate HAnim frame ID")
                    }
                }
            }
            let candidates = treeFrames.compactMap { frames[$0].hierarchy }.filter { !$0.nodes.isEmpty }
            guard candidates.count == 1, let hierarchy = candidates.first,
                  hierarchy.nodes.count == skin.boneCount,
                  hierarchy.nodes.allSatisfy({ frameIDs[$0.id] != nil }) else {
                throw DFF.Failure.malformed("skin/HAnim palette mismatch")
            }
            validatedPalettes[treeRoot] = hierarchy.nodes.count
        }
    }
}
