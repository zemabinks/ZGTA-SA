// SPDX-License-Identifier: AGPL-3.0-only
// Independently implemented bounded COL reader. Format reference: Parik's
// DragonFF gtaLib/col.py (GPL-3.0-or-later); no implementation is copied/linked.
// Reference identity, license and coverage are documented by the collision test.
import Foundation
import simd

/// Authored GTA Z-up collision only. Shadow triangles never become physical
/// triangles, and a missing COL plugin never falls back to the visual mesh.
enum NativeRenderWareCollision {
    struct Limits {
        var fileBytes = 32 * 1024 * 1024
        var dffBytes = 64 * 1024 * 1024
        var models = 1_024
        var chunks = 65_536
        var spheres = 65_535
        var boxes = 65_535
        var faces = 65_535
        var vertices = 100_000
        var faceGroups = 65_535
        var totalPrimitives = 1_000_000
        var totalVertices = 1_000_000
    }
    enum Failure: Error, CustomStringConvertible {
        case malformed(String), limit(String), unsupported(String)
        var description: String {
            switch self {
            case .malformed(let s): return "Malformed COL: \(s)"
            case .limit(let s): return "COL limit: \(s)"
            case .unsupported(let s): return "Unsupported COL: \(s)"
            }
        }
    }
    enum Version: Int { case coll = 1, col2 = 2, col3 = 3 }
    struct Bounds {
        let minimum: SIMD3<Float>
        let maximum: SIMD3<Float>
        let center: SIMD3<Float>
        let radius: Float
    }
    struct Surface {
        let material: UInt8
        /// COL2/3 mesh faces have no stored primitive flag/brightness fields.
        let flags: UInt8?
        let brightness: UInt8?
        let lighting: UInt8
        var dayLight: UInt8 { lighting & 15 }
        var nightLight: UInt8 { lighting >> 4 }
    }
    struct Sphere { let center: SIMD3<Float>; let radius: Float; let surface: Surface }
    struct Box { let minimum: SIMD3<Float>; let maximum: SIMD3<Float>; let surface: Surface }
    struct Face { let a: UInt32; let b: UInt32; let c: UInt32; let surface: Surface }
    struct Mesh { let vertices: [SIMD3<Float>]; let faces: [Face] }
    struct FaceGroup { let minimum: SIMD3<Float>; let maximum: SIMD3<Float>; let firstFace: Int; let lastFace: Int }
    struct Model {
        let version: Version
        let name: String? // nil for explicitly decoded headerless legacy data.
        let modelID: UInt16?
        let bounds: Bounds
        let flags: UInt32? // COLL has no model flags word.
        let spheres: [Sphere]
        let boxes: [Box]
        let mesh: Mesh
        let faceGroups: [FaceGroup]
        let shadowMesh: Mesh?
        var hasCollisionVolumes: Bool { !spheres.isEmpty || !boxes.isEmpty || !mesh.faces.isEmpty }
    }
    struct Embedded {
        let pluginOffset: Int
        let payloadBytes: Int
        let headerlessLegacy: Bool
        let models: [Model]
    }
    static func decode(_ data: Data, limits: Limits = .init()) throws -> [Model] {
        try COLDecoder(data, limits: limits, maximumBytes: limits.fileBytes).collection(start: 0, end: data.count)
    }
    /// Explicit entry point; arbitrary unknown COL file signatures are not
    /// silently interpreted as headerless data by decode().
    static func decodeHeaderlessCOL1(_ data: Data, limits: Limits = .init()) throws -> Model {
        try COLDecoder(data, limits: limits, maximumBytes: limits.fileBytes).legacy(start: 0, end: data.count, name: nil, id: nil)
    }
    static func embedded(inDFF data: Data, limits: Limits = .init()) throws -> [Embedded] {
        try COLDecoder(data, limits: limits, maximumBytes: limits.dffBytes).embedded()
    }
}

private struct COLReader {
    let bytes: [UInt8]
    var at: Int
    let end: Int
    var remaining: Int { end - at }
    mutating func require(_ n: Int) throws {
        guard n >= 0, n <= remaining else { throw NativeRenderWareCollision.Failure.malformed("truncated field at \(at)") }
    }
    mutating func u8() throws -> UInt8 { try require(1); defer { at += 1 }; return bytes[at] }
    mutating func u16() throws -> UInt16 {
        try require(2); defer { at += 2 }; return UInt16(bytes[at]) | UInt16(bytes[at+1]) << 8
    }
    mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }
    mutating func u32() throws -> UInt32 {
        try require(4); defer { at += 4 }
        return UInt32(bytes[at]) | UInt32(bytes[at+1]) << 8 | UInt32(bytes[at+2]) << 16 | UInt32(bytes[at+3]) << 24
    }
    mutating func f32() throws -> Float {
        let v = Float(bitPattern: try u32())
        guard v.isFinite else { throw NativeRenderWareCollision.Failure.malformed("non-finite float at \(at-4)") }
        return v
    }
    mutating func v3() throws -> SIMD3<Float> { try SIMD3(f32(),f32(),f32()) }
    mutating func skip(_ n: Int) throws { try require(n); at += n }
}

private final class COLDecoder {
    typealias COL = NativeRenderWareCollision
    struct Span { let start: Int; let end: Int; let label: String }
    struct Chunk { let kind: UInt32; let start: Int; let end: Int }
    let bytes: [UInt8]
    let limits: COL.Limits
    var modelCount = 0, chunks = 0, primitiveCount = 0, vertexCount = 0
    init(_ data: Data, limits: COL.Limits, maximumBytes: Int) throws {
        guard maximumBytes > 0, data.count <= maximumBytes else { throw COL.Failure.limit("file bytes") }
        bytes = Array(data); self.limits = limits
    }
    func count(_ raw: UInt32, _ max: Int, _ label: String) throws -> Int {
        guard max >= 0, UInt64(raw) <= UInt64(max) else { throw COL.Failure.limit(label) }
        return Int(raw)
    }
    func budget(primitives: Int, vertices: Int) throws {
        primitiveCount += primitives; vertexCount += vertices
        guard primitiveCount <= limits.totalPrimitives, vertexCount <= limits.totalVertices else { throw COL.Failure.limit("aggregate primitives/vertices") }
    }
    func newModel() throws {
        modelCount += 1
        guard modelCount <= limits.models else { throw COL.Failure.limit("model count") }
    }
    func ordered(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>) throws {
        guard (0..<3).allSatisfy({ lo[$0] <= hi[$0] }) else { throw COL.Failure.malformed("inverted bounding box") }
    }
    func surface(_ r: inout COLReader) throws -> COL.Surface {
        try COL.Surface(material: r.u8(),flags: r.u8(),brightness: r.u8(),lighting: r.u8())
    }
    func bounds(_ r: inout COLReader, legacy: Bool) throws -> COL.Bounds {
        let lo: SIMD3<Float>, hi: SIMD3<Float>, center: SIMD3<Float>, radius: Float
        if legacy { radius = try r.f32(); center = try r.v3(); lo = try r.v3(); hi = try r.v3() }
        else { lo = try r.v3(); hi = try r.v3(); center = try r.v3(); radius = try r.f32() }
        try ordered(lo,hi)
        guard radius >= 0 else { throw COL.Failure.malformed("negative bounds radius") }
        return COL.Bounds(minimum: lo,maximum: hi,center: center,radius: radius)
    }
    func collection(start: Int, end: Int) throws -> [COL.Model] {
        var at = start, models: [COL.Model] = []
        while at < end {
            if bytes[at..<end].allSatisfy({ $0 == 0 }) {
                guard (end-start) % 2048 == 0, end-at < 2048 else { throw COL.Failure.malformed("invalid final sector padding") }
                break
            }
            var r = COLReader(bytes: bytes,at: at,end: end)
            try r.require(32)
            let signature = try r.u32(), size = try r.u32()
            let version: COL.Version
            switch signature {
            case 0x4c4c4f43: version = .coll
            case 0x324c4f43: version = .col2
            case 0x334c4f43: version = .col3
            default: throw COL.Failure.unsupported("signature 0x\(String(signature,radix:16))")
            }
            guard size >= 24, UInt64(size) <= UInt64(end-at-8) else { throw COL.Failure.malformed("model length") }
            let modelEnd = at + 8 + Int(size)
            let raw = bytes[r.at..<(r.at+22)].prefix { $0 != 0 }
            guard !raw.contains(where: { $0 < 32 || $0 == 127 }) else { throw COL.Failure.malformed("model name control byte") }
            let name = String(data: Data(raw),encoding: .utf8) ?? String(data: Data(raw),encoding: .isoLatin1) ?? ""
            try r.skip(22); let id = try r.u16()
            let model = version == .coll ? try legacy(start: at+32,end: modelEnd,name: name,id: id) :
                try modern(start: at,end: modelEnd,version: version,name: name,id: id)
            models.append(model); at = modelEnd
        }
        guard !models.isEmpty else { throw COL.Failure.malformed("empty collection") }
        return models
    }
    func legacy(start: Int, end: Int, name: String?, id: UInt16?) throws -> COL.Model {
        try newModel()
        var r = COLReader(bytes: bytes,at: start,end: end)
        let b = try bounds(&r,legacy: true)
        let sphereCount = try count(r.u32(),limits.spheres,"spheres"); try r.require(sphereCount*20)
        var spheres: [COL.Sphere] = []
        for _ in 0..<sphereCount {
            let radius = try r.f32(), center = try r.v3(), s = try surface(&r)
            guard radius >= 0 else { throw COL.Failure.malformed("negative sphere radius") }
            spheres.append(COL.Sphere(center: center,radius: radius,surface: s))
        }
        guard try r.u32() == 0 else { throw COL.Failure.unsupported("legacy suspension lines") }
        let boxCount = try count(r.u32(),limits.boxes,"boxes"); try r.require(boxCount*28)
        var boxes: [COL.Box] = []
        for _ in 0..<boxCount {
            let lo = try r.v3(), hi = try r.v3(), s = try surface(&r); try ordered(lo,hi)
            boxes.append(COL.Box(minimum: lo,maximum: hi,surface: s))
        }
        let vertices = try count(r.u32(),limits.vertices,"vertices"); try r.require(vertices*12)
        var points: [SIMD3<Float>] = []
        for _ in 0..<vertices { points.append(try r.v3()) }
        let faces = try count(r.u32(),limits.faces,"faces"); try r.require(faces*16)
        var triangles: [COL.Face] = []
        for _ in 0..<faces {
            let a = try r.u32(), b = try r.u32(), c = try r.u32(), s = try surface(&r)
            guard Int(a) < vertices, Int(b) < vertices, Int(c) < vertices else { throw COL.Failure.malformed("legacy face vertex index") }
            triangles.append(COL.Face(a: a,b: b,c: c,surface: s))
        }
        guard r.at == end else { throw COL.Failure.malformed("legacy trailing data") }
        try budget(primitives: sphereCount+boxCount+faces,vertices: vertices)
        return COL.Model(version: .coll,name: name,modelID: id,bounds: b,flags: nil,spheres: spheres,boxes: boxes,
            mesh: COL.Mesh(vertices: points,faces: triangles),faceGroups: [],shadowMesh: nil)
    }

    func modern(start: Int, end: Int, version: COL.Version, name: String, id: UInt16) throws -> COL.Model {
        try newModel()
        var r = COLReader(bytes: bytes,at: start+32,end: end)
        let b = try bounds(&r,legacy: false)
        let sphereCount = try count(UInt32(r.u16()),limits.spheres,"spheres")
        let boxCount = try count(UInt32(r.u16()),limits.boxes,"boxes")
        let faceCount = try count(UInt32(r.u16()),limits.faces,"faces")
        let lines = try r.u8(); try r.skip(1)
        let flags = try r.u32(), sphereOffset = try r.u32(), boxOffset = try r.u32(), lineOffset = try r.u32()
        let vertexOffset = try r.u32(), faceOffset = try r.u32(), planeOffset = try r.u32()
        var shadowFaces = 0, shadowVerticesOffset: UInt32 = 0, shadowFacesOffset: UInt32 = 0
        if version == .col3 {
            shadowFaces = try count(r.u32(),limits.faces,"shadow faces")
            shadowVerticesOffset = try r.u32(); shadowFacesOffset = try r.u32()
        }
        guard lines == 0 else { throw COL.Failure.unsupported("suspension/cone primitives") }
        guard planeOffset == 0 else { throw COL.Failure.unsupported("stored triangle planes") }
        guard (flags & 2 != 0) == (sphereCount+boxCount+faceCount > 0),
              (flags & 16 != 0) == (shadowFaces > 0) else { throw COL.Failure.malformed("collision/shadow flags disagree with counts") }
        let headerEnd = r.at
        var spans: [Span] = []
        func offset(_ value: UInt32, _ label: String) throws -> Int {
            guard value > 0, UInt64(value) + 4 <= UInt64(end-start) else { throw COL.Failure.malformed("\(label) offset") }
            let absolute = start + 4 + Int(value)
            guard absolute >= headerEnd else { throw COL.Failure.malformed("\(label) points into header") }
            return absolute
        }
        func section(_ value: UInt32, count: Int, stride: Int, label: String) throws -> COLReader {
            if count == 0 {
                if value != 0 { _ = try offset(value,label) }
                return COLReader(bytes: bytes,at: headerEnd,end: headerEnd)
            }
            let first = try offset(value,label), length = count*stride
            guard length <= end-first else { throw COL.Failure.malformed("\(label) exceeds model") }
            let span = Span(start: first,end: first+length,label: label)
            guard spans.allSatisfy({ span.end <= $0.start || span.start >= $0.end }) else {
                throw COL.Failure.malformed("overlapping \(label) section")
            }
            spans.append(span); return COLReader(bytes: bytes,at: first,end: first+length)
        }
        if lineOffset != 0 { _ = try offset(lineOffset,"empty lines") }
        var sr = try section(sphereOffset,count: sphereCount,stride: 20,label: "spheres")
        var spheres: [COL.Sphere] = []
        for _ in 0..<sphereCount {
            let center = try sr.v3(), radius = try sr.f32(), s = try surface(&sr)
            guard radius >= 0 else { throw COL.Failure.malformed("negative sphere radius") }
            spheres.append(COL.Sphere(center: center,radius: radius,surface: s))
        }
        var br = try section(boxOffset,count: boxCount,stride: 28,label: "boxes")
        var boxes: [COL.Box] = []
        for _ in 0..<boxCount {
            let lo = try br.v3(), hi = try br.v3(), s = try surface(&br); try ordered(lo,hi)
            boxes.append(COL.Box(minimum: lo,maximum: hi,surface: s))
        }
        var fr = try section(faceOffset,count: faceCount,stride: 8,label: "faces")
        let triangles = try faces(&fr,count: faceCount)
        let vertices = try count(triangles.map { max($0.a,max($0.b,$0.c)) }.max().map { $0+1 } ?? 0,limits.vertices,"vertices")
        var vr = try section(vertexOffset,count: vertices,stride: 6,label: "vertices")
        let points = try compressed(&vr,count: vertices)
        var groups: [COL.FaceGroup] = []
        if flags & 8 != 0 {
            guard faceCount > 0 else { throw COL.Failure.malformed("face groups without faces") }
            let faceStart = try offset(faceOffset,"faces")
            guard faceStart >= headerEnd+4 else { throw COL.Failure.malformed("face group count") }
            var grCount = COLReader(bytes: bytes,at: faceStart-4,end: faceStart)
            let n = try count(grCount.u32(),limits.faceGroups,"face groups")
            guard n > 0, n*28 <= faceStart-4-headerEnd else { throw COL.Failure.malformed("face group span") }
            let first = faceStart-4-n*28
            var gr = try section(UInt32(first-start-4),count: n*28+4,stride: 1,label: "face groups")
            for _ in 0..<n {
                let lo = try gr.v3(), hi = try gr.v3(), first = Int(try gr.u16()), last = Int(try gr.u16())
                try ordered(lo,hi)
                guard first <= last, last < faceCount else { throw COL.Failure.malformed("face group face index") }
                groups.append(COL.FaceGroup(minimum: lo,maximum: hi,firstFace: first,lastFace: last))
            }
        }
        var shadow: COL.Mesh?
        var shadowVertices = 0
        if shadowFaces > 0 {
            let first = try offset(shadowVerticesOffset,"shadow vertices"), last = try offset(shadowFacesOffset,"shadow faces")
            guard last >= first else { throw COL.Failure.malformed("shadow vertex span") }
            shadowVertices = try count(UInt32((last-first)/6),limits.vertices,"shadow vertices")
            var sv = try section(shadowVerticesOffset,count: shadowVertices,stride: 6,label: "shadow vertices")
            var sf = try section(shadowFacesOffset,count: shadowFaces,stride: 8,label: "shadow faces")
            let shadowPoints = try compressed(&sv,count: shadowVertices), shadowTriangles = try faces(&sf,count: shadowFaces)
            guard shadowTriangles.allSatisfy({ Int($0.a) < shadowVertices && Int($0.b) < shadowVertices && Int($0.c) < shadowVertices }) else {
                throw COL.Failure.malformed("shadow face vertex index")
            }
            shadow = COL.Mesh(vertices: shadowPoints,faces: shadowTriangles)
        } else {
            if shadowVerticesOffset != 0 { _ = try offset(shadowVerticesOffset,"empty shadow vertices") }
            if shadowFacesOffset != 0 { _ = try offset(shadowFacesOffset,"empty shadow faces") }
        }
        try budget(primitives: sphereCount+boxCount+faceCount+shadowFaces,vertices: vertices+shadowVertices)
        return COL.Model(version: version,name: name,modelID: id,bounds: b,flags: flags,spheres: spheres,boxes: boxes,
            mesh: COL.Mesh(vertices: points,faces: triangles),faceGroups: groups,shadowMesh: shadow)
    }
    func faces(_ r: inout COLReader, count: Int) throws -> [COL.Face] {
        var values: [COL.Face] = []
        for _ in 0..<count {
            let a = try r.u16(), b = try r.u16(), c = try r.u16(), material = try r.u8(), light = try r.u8()
            values.append(COL.Face(a: UInt32(a),b: UInt32(b),c: UInt32(c),
                surface: COL.Surface(material: material,flags: nil,brightness: nil,lighting: light)))
        }
        return values
    }
    func compressed(_ r: inout COLReader, count: Int) throws -> [SIMD3<Float>] {
        var values: [SIMD3<Float>] = []
        for _ in 0..<count { values.append(try SIMD3(Float(r.i16())/128,Float(r.i16())/128,Float(r.i16())/128)) }
        return values
    }

    func rwChunks(start: Int, end: Int, padding: Bool = false) throws -> [Chunk] {
        var r = COLReader(bytes: bytes,at: start,end: end), result: [Chunk] = []
        while r.remaining > 0 {
            if padding, bytes[r.at..<end].allSatisfy({ $0 == 0 }) {
                guard bytes.count % 2048 == 0, r.remaining < 2048 else { throw COL.Failure.malformed("DFF sector padding") }
                break
            }
            let kind = try r.u32(), length = try r.u32(); _ = try r.u32()
            guard UInt64(length) <= UInt64(r.remaining) else { throw COL.Failure.malformed("DFF chunk length") }
            chunks += 1; guard chunks <= limits.chunks else { throw COL.Failure.limit("DFF chunks") }
            result.append(Chunk(kind: kind,start: r.at,end: r.at+Int(length))); try r.skip(Int(length))
        }
        return result
    }
    func embedded() throws -> [COL.Embedded] {
        let top = try rwChunks(start: 0,end: bytes.count,padding: true)
        guard top.count == 1 || top.count == 2, top.first?.kind == 16,
              top.count == 1 || top[1].kind == 3 else { throw COL.Failure.malformed("DFF clump header") }
        if top.count == 2 { _ = try rwChunks(start: top[1].start,end: top[1].end) }
        let clump = try rwChunks(start: top[0].start,end: top[0].end)
        var found: [COL.Embedded] = []
        for ext in clump where ext.kind == 3 {
            for plugin in try rwChunks(start: ext.start,end: ext.end) where plugin.kind == 0x253f2fa {
                guard plugin.end-plugin.start <= limits.fileBytes else { throw COL.Failure.limit("embedded payload") }
                let headered = plugin.end-plugin.start >= 3 && bytes[plugin.start..<(plugin.start+3)].elementsEqual([67,79,76])
                let models = headered ? try collection(start: plugin.start,end: plugin.end) :
                    [try legacy(start: plugin.start,end: plugin.end,name: nil,id: nil)]
                found.append(COL.Embedded(pluginOffset: plugin.start,payloadBytes: plugin.end-plugin.start,
                    headerlessLegacy: !headered,models: models))
            }
        }
        return found
    }
}
