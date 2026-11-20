// SPDX-License-Identifier: AGPL-3.0-only
// CPU bridge for independently decoded owner/server-provided DFF pedestrian rigs.
import Foundation
import simd

/// Builds the same SKN1 contract as our own tools/assets/prepare_native_skeletons.py exporter.
/// A static object, unsupported rig or incompatible morph model fails explicitly;
/// this bridge never substitutes an unanimated actor or a generic pedestrian.
enum NativeRenderWareSkeleton {
    struct Limits {
        var vertices = 99_999 // NativeSkeletalActor requires count < 100,000.
        var frames = 512
        var bones = 64
        var indices = 600_000
    }
    enum Failure: Error, CustomStringConvertible {
        case incompatible(String)
        case limit(String)
        var description: String {
            switch self {
            case .incompatible(let reason): return "Incompatible pedestrian rig: \(reason)"
            case .limit(let reason): return "Pedestrian rig limit: \(reason)"
            }
        }
    }
    struct Frame {
        let sourceIndex: Int
        let parent: Int
        let boneID: Int
        let rest: simd_float4x4
    }
    struct Bone {
        let id: UInt32
        let frame: Int
        let inverseBind: simd_float4x4
    }
    struct Vertex {
        let sourceIndex: Int
        let materialIndex: Int
        let position: SIMD3<Float>
        let bones: SIMD4<UInt8>
        let weights: SIMD4<Float>
    }
    struct Plan {
        let atomicIndex: Int
        let geometryIndex: Int
        let frames: [Frame]
        /// Indexed by the DFF skin palette index, independently of HAnim order.
        let bones: [Bone]
        /// First triangle-use order, split by (source vertex, material slot).
        /// The mesh vertex buffer MUST use this same ordering as the SKN1 data.
        let vertices: [Vertex]
        let indices: [UInt32]
        let correction: simd_float4x4
        let axis: simd_float4x4
        let floor: Float

        /// SKN1's fixed-width fields permit admission without allocating a
        /// second encoded rig on the render thread merely to count its bytes.
        var encodedByteCount:Int {144 + frames.count * 72 + bones.count * 68 + vertices.count * 32}

        func encodedSKN1() -> Data {
            var output = Data()
            output.reserveCapacity(encodedByteCount)
            func u32(_ value: UInt32) {
                output.append(contentsOf: [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8),
                    UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 24)])
            }
            func f32(_ value: Float) { u32(value.bitPattern) }
            func matrix(_ value: simd_float4x4) {
                for column in 0..<4 { for row in 0..<4 { f32(value[column][row]) } }
            }
            u32(0x314e4b53); u32(UInt32(vertices.count)); u32(UInt32(frames.count)); u32(UInt32(bones.count))
            matrix(correction); matrix(axis)
            for frame in frames {
                u32(UInt32(bitPattern: Int32(frame.parent))); u32(UInt32(bitPattern: Int32(frame.boneID)))
                matrix(frame.rest)
            }
            for bone in bones { u32(UInt32(bone.frame)); matrix(bone.inverseBind) }
            for vertex in vertices {
                f32(vertex.position.x); f32(vertex.position.y); f32(vertex.position.z)
                output.append(contentsOf: [vertex.bones.x, vertex.bones.y, vertex.bones.z, vertex.bones.w])
                for component in 0..<4 { f32(vertex.weights[component]) }
            }
            return output
        }

        /// Rest-pose validation/reference helper, using exactly the SKN1 basis.
        /// Animation still belongs to NativeSkeletalActor and its loaded library.
        func restPalette() -> [simd_float4x4] {
            var world: [simd_float4x4] = []
            for frame in frames {
                world.append(frame.parent >= 0 ? world[frame.parent] * frame.rest : frame.rest)
            }
            return bones.map { axis * correction * world[$0.frame] * $0.inverseBind }
        }
    }

    static func prepare(_ model: NativeRenderWareDFF, limits: Limits = Limits()) throws -> Plan {
        guard model.atomics.count == 1, model.geometries.count == 1, let atomic = model.atomics.first,
              atomic.geometry == 0, model.frames.indices.contains(atomic.frame),
              let geometry = model.geometries.first, let skin = geometry.skin else {
            throw Failure.incompatible("requires one atomic and one skinned geometry")
        }
        guard !model.frames.isEmpty, model.frames.count <= min(512, limits.frames),
              skin.boneCount > 0, skin.boneCount <= min(64, limits.bones) else { throw Failure.limit("frames/bones") }
        guard geometry.morphTargets.count == 1, geometry.positions.count == geometry.vertexCount,
              geometry.vertexCount > 0, skin.indices.count == geometry.vertexCount,
              skin.weights.count == geometry.vertexCount, skin.inverseBindMatrices.count == skin.boneCount else {
            throw Failure.incompatible("unsupported morph targets or incomplete skin arrays")
        }
        guard geometry.triangles.count <= limits.indices / 3 else { throw Failure.limit("triangle indices") }

        // Existing actor builds globals in array order. Preserve the source order
        // when already topological; remap otherwise without changing bone IDs.
        var order: [Int] = [], state = [UInt8](repeating: 0, count: model.frames.count)
        for start in model.frames.indices {
            var path: [Int] = [], at = start
            while at >= 0, state[at] != 2 {
                guard state[at] == 0 else { throw Failure.incompatible("frame cycle") }
                state[at] = 1; path.append(at)
                let parent = model.frames[at].parent
                guard parent >= -1, parent < model.frames.count else { throw Failure.incompatible("frame parent") }
                at = parent
            }
            for frame in path.reversed() { state[frame] = 2; order.append(frame) }
        }
        var remap = [Int](repeating: 0, count: model.frames.count)
        for (index, source) in order.enumerated() { remap[source] = index }
        var frameByID: [UInt32: Int] = [:]
        var hierarchy: NativeRenderWareDFF.HAnim?
        for index in model.frames.indices {
            let frame = model.frames[index]
            guard rigid(double(frame.localTransform)) else { throw Failure.incompatible("scaled/sheared/reflected frame") }
            if let h = frame.hierarchy {
                guard h.id <= UInt32(Int32.max), frameByID.updateValue(index, forKey: h.id) == nil else {
                    throw Failure.incompatible("duplicate/out-of-range HAnim ID")
                }
                if !h.nodes.isEmpty {
                    guard hierarchy == nil else { throw Failure.incompatible("multiple HAnim palettes") }
                    hierarchy = h
                }
            }
        }
        guard frameByID[0] != nil, frameByID[1] != nil, let hierarchy,
              hierarchy.nodes.count == skin.boneCount else { throw Failure.incompatible("root/pelvis/palette missing") }
        let nodes = hierarchy.nodes.sorted { $0.index < $1.index }
        var bones: [Bone] = []
        for (index, node) in nodes.enumerated() {
            guard node.index == index, let frame = frameByID[node.id],
                  rigid(double(skin.inverseBindMatrices[index])) else { throw Failure.incompatible("bone mapping/inverse bind") }
            bones.append(Bone(id: node.id, frame: remap[frame], inverseBind: skin.inverseBindMatrices[index]))
        }
        let frames = order.map { source -> Frame in
            let frame = model.frames[source]
            return Frame(sourceIndex: source, parent: frame.parent >= 0 ? remap[frame.parent] : -1,
                         boneID: frame.hierarchy.map { Int($0.id) } ?? -1, rest: frame.localTransform)
        }
        // Use Double for the bind/floor derivation, matching our exporter, and
        // quantize only the completed SKN1 matrices to Float32.
        var globals: [simd_double4x4] = []
        for frame in frames {
            let local = double(frame.rest)
            globals.append(frame.parent >= 0 ? globals[frame.parent] * local : local)
        }
        let basis = globals[bones[0].frame] * double(bones[0].inverseBind)
        guard rigid(basis) else { throw Failure.incompatible("non-rigid skin basis") }
        let correction = globals[remap[atomic.frame]] * inverseRigid(basis)
        guard finite(correction) else { throw Failure.incompatible("non-finite bind correction") }

        var vertices: [Vertex] = [], indices: [UInt32] = [], lookup: [UInt64: UInt32] = [:]
        for triangle in geometry.triangles {
            guard Int(triangle.material) < geometry.materials.count else { throw Failure.incompatible("material index") }
            for original in [triangle.a, triangle.b, triangle.c] {
                let index = Int(original), material = Int(triangle.material)
                guard index < geometry.vertexCount else { throw Failure.incompatible("vertex index") }
                let key = UInt64(original) << 32 | UInt64(triangle.material)
                if let mapped = lookup[key] { indices.append(mapped); continue }
                guard vertices.count < min(99_999, limits.vertices) else { throw Failure.limit("material-split vertices") }
                let point = geometry.positions[index], ids = skin.indices[index], weights = skin.weights[index]
                guard (0..<3).allSatisfy({ point[$0].isFinite }),
                      (0..<4).allSatisfy({ Int(ids[$0]) < skin.boneCount && weights[$0].isFinite && weights[$0] >= 0 }),
                      abs(weights.x + weights.y + weights.z + weights.w - 1) < 0.01 else {
                    throw Failure.incompatible("non-finite vertex or invalid influences")
                }
                let mapped = UInt32(vertices.count); lookup[key] = mapped; indices.append(mapped)
                vertices.append(Vertex(sourceIndex: index, materialIndex: material, position: point, bones: ids, weights: weights))
            }
        }
        guard !vertices.isEmpty else { throw Failure.incompatible("empty triangle mesh") }
        var floor = Double.infinity
        for vertex in vertices {
            var point = SIMD4<Double>(Double(vertex.position.x), Double(vertex.position.y), Double(vertex.position.z), 1)
            var at = atomic.frame
            while at >= 0 { point = double(model.frames[at].localTransform) * point; at = model.frames[at].parent }
            guard (0..<4).allSatisfy({ point[$0].isFinite }), (0..<3).allSatisfy({ abs(point[$0]) < 1000 }) else {
                throw Failure.incompatible("model coordinates exceed existing actor contract")
            }
            floor = min(floor, point.y)
        }
        let axis = simd_double4x4(SIMD4(1, 0, 0, 0), SIMD4(0, 0, 1, 0),
                                 SIMD4(0, -1, 0, 0), SIMD4(0, 0, -floor, 1))
        let correction32 = float(correction), axis32 = float(axis)
        guard finite(double(correction32)), finite(double(axis32)), Float(floor).isFinite else {
            throw Failure.incompatible("Float32 bind basis overflow")
        }
        return Plan(atomicIndex: 0, geometryIndex: 0, frames: frames, bones: bones, vertices: vertices,
                    indices: indices, correction: correction32, axis: axis32, floor: Float(floor))
    }

    private static func double(_ m: simd_float4x4) -> simd_double4x4 {
        simd_double4x4(SIMD4<Double>(m.columns.0), SIMD4<Double>(m.columns.1),
                       SIMD4<Double>(m.columns.2), SIMD4<Double>(m.columns.3))
    }
    private static func float(_ m: simd_double4x4) -> simd_float4x4 {
        simd_float4x4(SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1),
                      SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3))
    }
    private static func finite(_ m: simd_double4x4) -> Bool {
        (0..<4).allSatisfy { column in (0..<4).allSatisfy { m[column][$0].isFinite } }
    }
    private static func rigid(_ m: simd_double4x4) -> Bool {
        guard finite(m), abs(m.columns.0.w) < 0.00001, abs(m.columns.1.w) < 0.00001,
              abs(m.columns.2.w) < 0.00001, abs(m.columns.3.w - 1) < 0.00001 else { return false }
        let axes = [SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                    SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                    SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)]
        return axes.allSatisfy { abs(simd_length_squared($0) - 1) <= 0.002 } &&
            abs(simd_dot(axes[0], axes[1])) <= 0.002 && abs(simd_dot(axes[0], axes[2])) <= 0.002 &&
            abs(simd_dot(axes[1], axes[2])) <= 0.002 && simd_dot(simd_cross(axes[0], axes[1]), axes[2]) > 0.998
    }
    private static func inverseRigid(_ m: simd_double4x4) -> simd_double4x4 {
        let x = SIMD3(m.columns.0.x, m.columns.1.x, m.columns.2.x)
        let y = SIMD3(m.columns.0.y, m.columns.1.y, m.columns.2.y)
        let z = SIMD3(m.columns.0.z, m.columns.1.z, m.columns.2.z)
        let t = SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z)
        return simd_double4x4(SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0),
                              SIMD4(-(x * t.x + y * t.y + z * t.z), 1))
    }
}
