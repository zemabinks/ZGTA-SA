// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// A bounded, fixed-Normal player body assembler. This is not a skin0 alias,
/// wardrobe engine or authentication of the initial SA-MP clothes descriptor.
/// Source positions remain in their common RW basis; only the completed body
/// is passed through the existing skeleton's single axis/floor correction.
enum NativeCJAssembly {
    enum Failure: Error, CustomStringConvertible {
        case invalid(String), unsupported(String), limit(String)
        var description: String {
            switch self {
            case .invalid(let s): return "Invalid player assembly: \(s)"
            case .unsupported(let s): return "Unsupported player assembly: \(s)"
            case .limit(let s): return "Player assembly limit: \(s)"
            }
        }
    }
    struct Limits {
        var componentFileBytes = 4 * 1024 * 1024
        var vertices = 32_768
        var triangles = 65_536
        var materials = 128
    }
    enum Component: String, CaseIterable {
        case torso, head, hands, legs, feet
        var texture: String { self == .hands ? "torso" : rawValue }
    }
    struct Part {
        let component: Component
        let normal: NativeRenderWareDFF
    }
    struct PartReport {
        let component: Component
        let sourceVertexRange: Range<Int>
        let sourcePaletteIDs: [UInt32]
        let unusedExtraBoneIDs: [UInt32]
        /// Source garment binds are deliberately NOT substituted for template
        /// binds. The common player palette owns the assembled deformation.
        let maximumSharedInverseBindDifference: Float
    }
    struct Plan {
        let dff: NativeRenderWareDFF
        let skeleton: NativeRenderWareSkeleton.Plan
        let parts: [PartReport]
        /// The original animation/style table calls PLAYER1's model "null".
        /// A future resource registration must preserve that style explicitly.
        let animationStyleModel = "null"
    }

    /// Clothes DFFs are three complete clumps, not one clump with three morph
    /// targets. Require and decode all three named variants; Normal is third.
    /// Ordinary DFF parsing is unchanged and still rejects trailing clumps.
    static func normalClump(from data: Data, limits: Limits = .init()) throws -> NativeRenderWareDFF {
        guard limits.componentFileBytes > 0, data.count <= limits.componentFileBytes else { throw Failure.limit("component bytes") }
        let bytes = [UInt8](data)
        func u32(_ at: Int) -> UInt32 {
            UInt32(bytes[at]) | UInt32(bytes[at+1]) << 8 | UInt32(bytes[at+2]) << 16 | UInt32(bytes[at+3]) << 24
        }
        var at = 0, models: [NativeRenderWareDFF] = []
        var parser = NativeRenderWareDFF.Limits()
        parser.fileBytes = limits.componentFileBytes; parser.frames = 128; parser.bones = 64
        parser.geometries = 1; parser.atomics = 1; parser.verticesPerGeometry = limits.vertices
        parser.totalVertices = limits.vertices; parser.trianglesPerGeometry = limits.triangles
        parser.totalTriangles = limits.triangles; parser.materialsPerGeometry = limits.materials
        for expected in ["ripped", "fat", "normal"] {
            guard bytes.count - at >= 12, u32(at) == 16 else { throw Failure.invalid("three clump sequence") }
            let size = Int(u32(at+4))
            guard size <= bytes.count - at - 12 else { throw Failure.invalid("clump bounds") }
            let end = at + 12 + size
            let model = try NativeRenderWareDFF.decode(Data(bytes[at..<end]), limits: parser)
            guard model.atomics.count == 1, let atomic = model.atomics.first,
                  model.frames.indices.contains(atomic.frame),
                  model.frames[atomic.frame].name?.lowercased() == expected,
                  atomic.flags & 4 != 0, model.geometries.count == 1,
                  model.geometries[0].skin != nil else { throw Failure.invalid("variant identity \(expected)") }
            models.append(model); at = end
        }
        if at != bytes.count {
            guard bytes.count % 2048 == 0, bytes.count - at < 2048,
                  bytes[at...].allSatisfy({ $0 == 0 }) else { throw Failure.invalid("trailing component data") }
        }
        guard models.allSatisfy({ $0.version == models[0].version }) else { throw Failure.invalid("variant versions") }
        return models[2]
    }

    static func prepare(template: NativeRenderWareDFF, parts: [Part], limits: Limits = .init()) throws -> Plan {
        guard limits.vertices > 0, limits.vertices <= 65_535, limits.triangles > 0,
              limits.materials > 0, limits.materials <= 65_535 else { throw Failure.limit("invalid budgets") }
        guard parts.count == Component.allCases.count,
              Set(parts.map(\.component)).count == Component.allCases.count else { throw Failure.invalid("requires all five unique components") }
        guard template.atomics.count == 1, template.geometries.count == 1,
              let sourceSkin = template.geometries[0].skin,
              template.frames.indices.contains(template.atomics[0].frame),
              template.geometries[0].vertexCount <= 64,
              template.frames[template.atomics[0].frame].name?.lowercased() == "normal" else {
            throw Failure.invalid("explicit player rig template required")
        }
        let templateRig = try NativeRenderWareSkeleton.prepare(template)
        try validateBindBasis(template,rig: templateRig)
        let templateIDs = templateRig.bones.map(\.id)
        var targetIndex: [UInt32: UInt8] = [:]
        for (i, id) in templateIDs.enumerated() {
            guard i < 64, targetIndex.updateValue(UInt8(i), forKey: id) == nil else { throw Failure.invalid("template bone palette") }
        }
        let atomic = template.atomics[0], root = template.frames[atomic.frame].worldTransform
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = []
        var coordinates: [[SIMD2<Float>]] = [], colors: [SIMD4<UInt8>] = []
        var triangles: [NativeRenderWareDFF.Triangle] = [], materials: [NativeRenderWareDFF.Material] = []
        var ids: [SIMD4<UInt8>] = [], weights: [SIMD4<Float>] = [], reports: [PartReport] = []
        var normalMode: Bool?, uvCount: Int?, flags: UInt16 = 0, used: Set<UInt8> = []
        for component in Component.allCases {
            let model = parts.first { $0.component == component }!.normal
            let rig = try NativeRenderWareSkeleton.prepare(model)
            try validateBindBasis(model,rig: rig)
            let sourceAtomic = model.atomics[0], geometry = model.geometries[0], skin = geometry.skin!
            guard model.frames[sourceAtomic.frame].name?.lowercased() == "normal", sourceAtomic.flags & 4 != 0,
                  difference(root, model.frames[sourceAtomic.frame].worldTransform) <= 0.00001 else {
                throw Failure.unsupported("component root basis differs: \(component)")
            }
            guard geometry.vertexCount <= limits.vertices - positions.count,
                  geometry.triangles.count <= limits.triangles - triangles.count,
                  geometry.materials.count <= limits.materials - materials.count else { throw Failure.limit("assembled mesh") }
            let hasNormals = !geometry.normals.isEmpty
            guard normalMode == nil || normalMode == hasNormals,
                  geometry.normals.isEmpty || geometry.normals.count == geometry.vertexCount,
                  geometry.positions.allSatisfy({ p in (0..<3).allSatisfy { p[$0].isFinite && abs(p[$0]) < 1000 } }),
                  geometry.normals.allSatisfy({ p in (0..<3).allSatisfy { p[$0].isFinite } }),
                  geometry.prelitColors.isEmpty || geometry.prelitColors.count == geometry.vertexCount,
                  !geometry.textureCoordinates.isEmpty,
                  uvCount == nil || uvCount == geometry.textureCoordinates.count,
                  geometry.textureCoordinates.allSatisfy({ layer in layer.count == geometry.vertexCount && layer.allSatisfy { $0.x.isFinite && $0.y.isFinite } }) else {
                throw Failure.invalid("normal/UV arrays")
            }
            normalMode = hasNormals; uvCount = geometry.textureCoordinates.count
            if coordinates.isEmpty { coordinates = Array(repeating: [], count: geometry.textureCoordinates.count) }
            let vertexStart = positions.count, materialStart = materials.count
            positions += geometry.positions; normals += geometry.normals
            colors += geometry.prelitColors.isEmpty ? Array(repeating: SIMD4(255,255,255,255), count: geometry.vertexCount) : geometry.prelitColors
            for layer in coordinates.indices { coordinates[layer] += geometry.textureCoordinates[layer] }
            for material in geometry.materials {
                materials.append(.init(flags: material.flags, color: SIMD4(255,255,255,255), textureName: component.texture,
                    maskName: nil, textureFilterAndAddressing: nil, surface: material.surface))
            }
            var extras = Set(rig.bones.map(\.id).filter { targetIndex[$0] == nil }), maximum: Float = 0
            for (i, bone) in rig.bones.enumerated() {
                if let target = targetIndex[bone.id] { maximum = max(maximum, difference(skin.inverseBindMatrices[i], sourceSkin.inverseBindMatrices[Int(target)])) }
            }
            for vertex in 0..<geometry.vertexCount {
                let source = skin.indices[vertex], value = skin.weights[vertex]
                guard abs(value.sum() - 1) <= 0.00001 else { throw Failure.invalid("weight normalization") }
                var mapped = SIMD4<UInt8>(repeating: 0)
                for influence in 0..<4 {
                    guard Int(source[influence]) < rig.bones.count else { throw Failure.invalid("source influence") }
                    let id = rig.bones[Int(source[influence])].id
                    if value[influence] > 0 {
                        guard let target = targetIndex[id] else { throw Failure.unsupported("positive influence on absent player bone \(id)") }
                        mapped[influence] = target; used.insert(target)
                    } else if targetIndex[id] == nil { extras.insert(id) }
                }
                ids.append(mapped); weights.append(value)
            }
            for triangle in geometry.triangles {
                triangles.append(.init(a: UInt16(vertexStart + Int(triangle.a)), b: UInt16(vertexStart + Int(triangle.b)),
                    c: UInt16(vertexStart + Int(triangle.c)), material: UInt16(materialStart + Int(triangle.material))))
            }
            flags |= geometry.flags
            reports.append(.init(component: component, sourceVertexRange: vertexStart..<positions.count,
                sourcePaletteIDs: rig.bones.map(\.id), unusedExtraBoneIDs: extras.sorted(), maximumSharedInverseBindDifference: maximum))
        }
        guard !positions.isEmpty, colors.count == positions.count else { throw Failure.invalid("empty/prelit body") }
        var low = positions[0], high = positions[0]
        for p in positions { low = simd_min(low,p); high = simd_max(high,p) }
        let center = (low + high) / 2, radius = positions.reduce(Float(0)) { max($0,simd_length($1-center)) }
        let morph = NativeRenderWareDFF.MorphTarget(boundingSphere: SIMD4(center,radius), positions: positions, normals: normals)
        let skin = NativeRenderWareDFF.Skin(boneCount: sourceSkin.boneCount, usedBones: used.sorted(), maximumWeights: 4,
            indices: ids, weights: weights, inverseBindMatrices: sourceSkin.inverseBindMatrices)
        flags = (flags & ~1) | 8
        let geometry = NativeRenderWareDFF.Geometry(flags: flags, vertexCount: positions.count, textureCoordinates: coordinates,
            prelitColors: colors, triangles: triangles, materials: materials, morphTargets: [morph], skin: skin)
        let combined = NativeRenderWareDFF(version: template.version, frames: template.frames,
            geometries: [geometry], atomics: [.init(frame: atomic.frame,geometry: 0,flags: atomic.flags,unused: 0)])
        let skeleton = try NativeRenderWareSkeleton.prepare(combined)
        return Plan(dff: combined, skeleton: skeleton, parts: reports)
    }
    private static func difference(_ a: simd_float4x4, _ b: simd_float4x4) -> Float {
        var result: Float = 0
        for column in 0..<4 { for row in 0..<4 { result = max(result,abs(a[column][row]-b[column][row])) } }
        return result
    }
    private static func validateBindBasis(_ model: NativeRenderWareDFF, rig: NativeRenderWareSkeleton.Plan) throws {
        let bases = rig.bones.map { bone in
            model.frames[rig.frames[bone.frame].sourceIndex].worldTransform * bone.inverseBind
        }
        guard let first = bases.first, bases.allSatisfy({ difference(first,$0) <= 0.0001 }) else {
            throw Failure.invalid("inconsistent source bind bases")
        }
    }
}
