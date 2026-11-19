// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal
import simd

/// Static, indexed DFF/TXD resources. RW coordinates, UVs, material slots and
/// frame transforms are preserved; the caller supplies its coordinate transform.
/// No skinning, collision, vehicle visibility heuristics, environment mapping,
/// or animation is implied by a successful static upload.
enum NativeRenderWareModel {
    struct Limits {
        var vertices = 1_000_000
        var indices = 6_000_000
        var instances = 4_096
        var draws = 32_768
        var materials = 16_384
        var meshBytes = 128 * 1024 * 1024
        var textureBytes = 128 * 1024 * 1024
    }
    enum Failure: Error, CustomStringConvertible {
        case malformed(String), unsupported(String), limit(String), gpu(String)
        var description: String {
            switch self {
            case .malformed(let s): return "Malformed static RW model: \(s)"
            case .unsupported(let s): return "Unsupported static RW model: \(s)"
            case .limit(let s): return "Static RW model limit: \(s)"
            case .gpu(let s): return "Static RW GPU failure: \(s)"
            }
        }
    }
    enum Diagnostic: Equatable {
        case missingTexture(geometry: Int, material: Int, name: String)
        case omittedMipTail(texture: String, firstMissingLevel: Int)
        case additionalMorphTargets(geometry: Int)
        case noRenderableTriangles
    }
    struct Vertex {
        var position: SIMD3<Float>
        var normal: SIMD3<Float>
        var uv: SIMD2<Float>
        var color: SIMD4<Float>
    }
    struct Sampler: Hashable {
        /// RW: filter 1 nearest, 2 linear, 3/4 nearest/linear with nearest mip,
        /// 5/6 nearest/linear with interpolated mips. Address: wrap/mirror/clamp/border.
        let filter: UInt8
        let addressU: UInt8
        let addressV: UInt8
    }
    struct Material {
        let source: NativeRenderWareDFF.Material
        let textureIndex: Int?
        let sampler: Sampler
        let usesBlending: Bool
        /// Geometry MODULATE controls the source color. Explicit server draw
        /// overrides remain independently meaningful even without that flag.
        var modulatesMaterial: Bool = true
    }
    struct Part {
        let material: Int
        let indexStart: Int
        let indexCount: Int
    }
    struct Geometry {
        let sourceIndex: Int
        let vertices: [Vertex]
        /// All original sets remain available; the static base-texture shader uses set 0.
        let textureCoordinates: [[SIMD2<Float>]]
        let indices: [UInt32]
        let parts: [Part]
        let materials: [Material]
    }
    struct Instance {
        let sourceAtomic: Int
        let geometry: Int
        let frameName: String?
        let frameTransform: simd_float4x4
    }
    struct Draw {
        let instance: Int
        let part: Int
    }
    struct Plan {
        let geometries: [Geometry]
        let textures: [NativeRenderWareTXD.Texture]
        let instances: [Instance]
        let draws: [Draw]
        let diagnostics: [Diagnostic]
        let meshByteCount: Int
        let textureByteCount: Int
        /// Resource completeness only, not original-engine visual parity.
        var isComplete: Bool { diagnostics.isEmpty && !draws.isEmpty }
    }

    static func prepare(dff: NativeRenderWareDFF, txd: NativeRenderWareTXD.TextureDictionary?, limits: Limits = Limits()) throws -> Plan {
        guard limits.vertices > 0, limits.indices > 0, limits.instances > 0,
              limits.draws > 0, limits.materials > 0, limits.meshBytes > 0, limits.textureBytes > 0 else { throw Failure.limit("invalid budgets") }
        var available: [String: NativeRenderWareTXD.Texture] = [:]
        for texture in txd?.textures ?? [] {
            guard available.updateValue(texture, forKey: texture.lookupName) == nil else { throw Failure.malformed("duplicate texture lookup name") }
        }
        var geometries: [Geometry] = [], instances: [Instance] = [], draws: [Draw] = []
        var textures: [NativeRenderWareTXD.Texture] = [], textureIndices: [String: Int] = [:]
        var geometryIndices: [Int: Int] = [:], diagnostics: [Diagnostic] = []
        var vertexCount = 0, indexCount = 0, materialCount = 0, meshBytes = 0, textureBytes = 0
        for (atomicIndex, atomic) in dff.atomics.enumerated() {
            // rpATOMICRENDER == 4; collision-only/dummy atomics are not visible.
            guard atomic.flags & 4 != 0 else { continue }
            guard instances.count < limits.instances else { throw Failure.limit("render instances") }
            guard dff.frames.indices.contains(atomic.frame), dff.geometries.indices.contains(atomic.geometry) else { throw Failure.malformed("atomic reference") }
            let frame = dff.frames[atomic.frame]
            guard finite(frame.worldTransform) else { throw Failure.malformed("non-finite frame transform") }
            let geometryIndex: Int
            if let existing = geometryIndices[atomic.geometry] { geometryIndex = existing }
            else {
                let source = dff.geometries[atomic.geometry]
                guard source.skin == nil else { throw Failure.unsupported("skinned geometry \(atomic.geometry) requires skeletal importer") }
                guard source.positions.count == source.vertexCount, source.vertexCount > 0 else { throw Failure.malformed("missing static positions") }
                guard source.normals.isEmpty || source.normals.count == source.vertexCount,
                      source.prelitColors.isEmpty || source.prelitColors.count == source.vertexCount,
                      source.textureCoordinates.first == nil || source.textureCoordinates[0].count == source.vertexCount else { throw Failure.malformed("vertex attribute count") }
                guard source.vertexCount <= limits.vertices - vertexCount,
                      source.triangles.count <= (limits.indices - indexCount) / 3 else { throw Failure.limit("vertices or triangle indices") }
                guard source.materials.count <= limits.materials - materialCount else { throw Failure.limit("material slots") }
                materialCount += source.materials.count
                let newIndices = source.triangles.count * 3
                let vertexBytes = try checkedProduct(source.vertexCount, MemoryLayout<Vertex>.stride)
                let indexBytes = try checkedProduct(newIndices, MemoryLayout<UInt32>.stride)
                guard vertexBytes <= limits.meshBytes - meshBytes, indexBytes <= limits.meshBytes - meshBytes - vertexBytes else { throw Failure.limit("mesh buffer bytes") }
                vertexCount += source.vertexCount; indexCount += newIndices; meshBytes += vertexBytes + indexBytes
                var vertices: [Vertex] = []; vertices.reserveCapacity(source.vertexCount)
                for index in 0..<source.vertexCount {
                    let p = source.positions[index]
                    let normal = source.normals.isEmpty ? SIMD3<Float>(repeating: 0) : source.normals[index]
                    let uv = source.textureCoordinates.first?[index] ?? SIMD2<Float>(repeating: 0)
                    guard finite(p), finite(normal), uv.x.isFinite, uv.y.isFinite else { throw Failure.malformed("non-finite vertex attribute") }
                    let c = source.prelitColors.isEmpty ? SIMD4<UInt8>(repeating: 255) : source.prelitColors[index]
                    vertices.append(Vertex(position: p, normal: normal, uv: uv, color: SIMD4(Float(c.x), Float(c.y), Float(c.z), Float(c.w)) / 255))
                }
                var buckets = [[UInt32]](repeating: [], count: source.materials.count)
                for triangle in source.triangles {
                    guard buckets.indices.contains(Int(triangle.material)), Int(triangle.a) < source.vertexCount,
                          Int(triangle.b) < source.vertexCount, Int(triangle.c) < source.vertexCount else { throw Failure.malformed("triangle index or material reference") }
                    buckets[Int(triangle.material)].append(contentsOf: [UInt32(triangle.a), UInt32(triangle.b), UInt32(triangle.c)])
                }
                var parts: [Part] = [], indices: [UInt32] = [], materials: [Material] = []
                indices.reserveCapacity(newIndices)
                for (materialIndex, material) in source.materials.enumerated() {
                    if buckets[materialIndex].isEmpty {
                        materials.append(Material(source: material, textureIndex: nil, sampler: try sampler(0x1102), usesBlending: false,
                                                  modulatesMaterial: source.flags & 0x40 != 0))
                        continue
                    }
                    var selected: Int?
                    if let name = material.textureName, !name.isEmpty {
                        let lookup = name.lowercased()
                        if let existing = textureIndices[lookup] { selected = existing }
                        else if let texture = available[lookup] {
                            var size = 0
                            var missing = false
                            for (level, mip) in texture.mipLevels.enumerated() {
                                if let pixels = mip.rgba8 {
                                    guard !missing, mip.width > 0, mip.height > 0,
                                          pixels.count == (try checkedProduct(try checkedProduct(mip.width, mip.height), 4)) else { throw Failure.malformed("texture mip layout") }
                                    guard pixels.count <= limits.textureBytes - textureBytes - size else { throw Failure.limit("texture upload bytes") }
                                    size += pixels.count
                                } else if !missing {
                                    diagnostics.append(.omittedMipTail(texture: texture.name, firstMissingLevel: level)); missing = true
                                }
                            }
                            guard texture.mipLevels.first?.rgba8 != nil else { throw Failure.malformed("texture lacks base mip") }
                            selected = textures.count; textures.append(texture); textureIndices[lookup] = selected
                            textureBytes += size
                        } else { diagnostics.append(.missingTexture(geometry: atomic.geometry, material: materialIndex, name: name)) }
                    }
                    let texture = selected.map { textures[$0] }
                    // A selected native dictionary texture is already loaded.
                    // librw Texture::read adds a reference on a dictionary hit;
                    // streamRead applies the DFF request only at refCount == 1.
                    // Preserve both raw fields; use the found texture's state.
                    let sampler = try sampler(texture?.filterAddressing ?? material.textureFilterAndAddressing ?? 0x1102)
                    let prelitAlpha = buckets[materialIndex].contains { source.prelitColors.isEmpty ? false : source.prelitColors[Int($0)].w != 255 }
                    let modulatesMaterial = source.flags & 0x40 != 0
                    materials.append(Material(source: material, textureIndex: selected, sampler: sampler,
                                              usesBlending: material.color.w != 255 || prelitAlpha || (texture?.containsTransparentPixels ?? false),
                                              modulatesMaterial: modulatesMaterial))
                    if !buckets[materialIndex].isEmpty {
                        parts.append(Part(material: materialIndex, indexStart: indices.count, indexCount: buckets[materialIndex].count))
                        indices.append(contentsOf: buckets[materialIndex])
                    }
                }
                if source.morphTargets.count > 1 { diagnostics.append(.additionalMorphTargets(geometry: atomic.geometry)) }
                geometryIndex = geometries.count; geometryIndices[atomic.geometry] = geometryIndex
                geometries.append(Geometry(sourceIndex: atomic.geometry, vertices: vertices, textureCoordinates: source.textureCoordinates, indices: indices, parts: parts, materials: materials))
            }
            let parts = geometries[geometryIndex].parts
            guard parts.count <= limits.draws - draws.count else { throw Failure.limit("draw count across repeated atomics") }
            let instance = instances.count
            instances.append(Instance(sourceAtomic: atomicIndex, geometry: geometryIndex, frameName: frame.name, frameTransform: frame.worldTransform))
            for part in parts.indices { draws.append(Draw(instance: instance, part: part)) }
        }
        if draws.isEmpty { diagnostics.append(.noRenderableTriangles) }
        return Plan(geometries: geometries, textures: textures, instances: instances, draws: draws,
                    diagnostics: diagnostics, meshByteCount: meshBytes, textureByteCount: textureBytes)
    }

    static func sampler(_ packed: UInt32) throws -> Sampler {
        let filter = UInt8(packed & 255), u = UInt8((packed >> 8) & 15)
        let storedV = UInt8((packed >> 12) & 15)
        // RW texture streams use V == 0 to inherit U. Observed in 19 original
        // materials; confirmed by librw texture.cpp streamRead (blob SHA
        // 961649e0bc0568c663b730746a8be9fd28222aea), not an arbitrary fallback.
        let v = storedV == 0 ? u : storedV
        guard (1...6).contains(filter), (1...4).contains(u), (1...4).contains(v) else { throw Failure.unsupported("filter/addressing 0x\(String(packed, radix: 16))") }
        return Sampler(filter: filter, addressU: u, addressV: v)
    }
    private static func checkedProduct(_ a: Int, _ b: Int) throws -> Int {
        let (value, overflow) = a.multipliedReportingOverflow(by: b)
        guard !overflow, value >= 0 else { throw Failure.limit("allocation overflow") }; return value
    }
    private static func finite(_ p: SIMD3<Float>) -> Bool { p.x.isFinite && p.y.isFinite && p.z.isFinite }
    private static func finite(_ m: simd_float4x4) -> Bool {
        [m.columns.0, m.columns.1, m.columns.2, m.columns.3].allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite }
    }

    struct DrawOverrides {
        var visible = true
        /// Applied after the atomic frame, before the caller's model transform.
        var transform = matrix_identity_float4x4
        var tint = SIMD4<Float>(repeating: 1)
        var alphaCutoff: Float = 1 / 255
        var ambient: Float = 1
        var diffuse: Float = 0
        var lightDirection = SIMD3<Float>(0, 0, 1)
        var textureOverride: MTLTexture?
        var samplerOverride: MTLSamplerState?
        /// Replaces the source material color; tint remains a separate multiplier.
        var materialColorOverride: SIMD4<Float>?
        var blendOverride: Bool?
        var ignoreVertexColor = false
    }
    struct Uniforms {
        var viewProjection: simd_float4x4
        var model: simd_float4x4
        var normalMatrix: simd_float4x4
        var color: SIMD4<Float>
        var lightDirectionAmbient: SIMD4<Float>
        var settings: SIMD4<Float>
    }
    struct Pipelines {
        let opaque: MTLRenderPipelineState
        let blended: MTLRenderPipelineState
        let opaqueDepth: MTLDepthStencilState
        let blendedDepth: MTLDepthStencilState
        init(device: MTLDevice, library: MTLLibrary, color: MTLPixelFormat, depth: MTLPixelFormat = .depth32Float) throws {
            guard let vertex = library.makeFunction(name: "native_rw_model_vertex"), let fragment = library.makeFunction(name: "native_rw_model_fragment") else { throw Failure.gpu("NativeRenderWareModel.metal functions not in library") }
            func pipeline(_ blend: Bool) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor(); d.vertexFunction = vertex; d.fragmentFunction = fragment
                d.colorAttachments[0].pixelFormat = color; d.depthAttachmentPixelFormat = depth
                d.colorAttachments[0].isBlendingEnabled = blend
                d.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha; d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                d.colorAttachments[0].sourceAlphaBlendFactor = .one; d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
                return try device.makeRenderPipelineState(descriptor: d)
            }
            opaque = try pipeline(false); blended = try pipeline(true)
            let d = MTLDepthStencilDescriptor(); d.depthCompareFunction = .lessEqual; d.isDepthWriteEnabled = true
            guard let a = device.makeDepthStencilState(descriptor: d) else { throw Failure.gpu("opaque depth state") }
            d.isDepthWriteEnabled = false
            guard let b = device.makeDepthStencilState(descriptor: d) else { throw Failure.gpu("blended depth state") }
            opaqueDepth = a; blendedDepth = b
        }
    }
    final class Uploaded {
        struct Buffers { let vertices: MTLBuffer; let indices: MTLBuffer }
        let plan: Plan
        let geometries: [Buffers]
        let textures: [MTLTexture]
        let whiteTexture: MTLTexture
        let samplers: [Sampler: MTLSamplerState]

        init(plan: Plan, device: MTLDevice) throws {
            self.plan = plan
            var buffers: [Buffers] = []
            for geometry in plan.geometries {
                // Empty index buffers have no draw; a minimal allocation is legal.
                let vertices = geometry.vertices.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
                let indices = geometry.indices.isEmpty ? device.makeBuffer(length: 4, options: .storageModeShared) : geometry.indices.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
                guard let vertices, let indices else { throw Failure.gpu("mesh buffers") }
                buffers.append(Buffers(vertices: vertices, indices: indices))
            }
            geometries = buffers
            var images: [MTLTexture] = []
            for source in plan.textures {
                let resident = source.mipLevels.prefix { $0.rgba8 != nil }
                guard let base = resident.first else { throw Failure.gpu("texture base mip missing") }
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: base.width, height: base.height, mipmapped: resident.count > 1)
                d.mipmapLevelCount = resident.count; d.storageMode = .shared; d.usage = .shaderRead
                guard let texture = device.makeTexture(descriptor: d) else { throw Failure.gpu("texture \(source.name)") }
                texture.label = "RW \(source.name)"
                for (level, mip) in resident.enumerated() {
                    mip.rgba8!.withUnsafeBytes { texture.replace(region: MTLRegionMake2D(0, 0, mip.width, mip.height), mipmapLevel: level, withBytes: $0.baseAddress!, bytesPerRow: mip.rowBytes) }
                }
                images.append(texture)
            }
            textures = images
            let whiteDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
            whiteDescriptor.storageMode = .shared; whiteDescriptor.usage = .shaderRead
            guard let white = device.makeTexture(descriptor: whiteDescriptor) else { throw Failure.gpu("white material texture") }
            var whitePixel: UInt32 = 0xFFFFFFFF
            withUnsafeBytes(of: &whitePixel) { white.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 4) }
            whiteTexture = white
            var states: [Sampler: MTLSamplerState] = [:]
            for material in plan.geometries.flatMap({ $0.materials }) where states[material.sampler] == nil {
                let s = material.sampler, d = MTLSamplerDescriptor()
                d.minFilter = [2, 4, 6].contains(s.filter) ? .linear : .nearest; d.magFilter = d.minFilter
                d.mipFilter = s.filter < 3 ? .notMipmapped : s.filter < 5 ? .nearest : .linear
                func address(_ mode: UInt8) -> MTLSamplerAddressMode {
                    switch mode { case 1: return .repeat; case 2: return .mirrorRepeat; case 3: return .clampToEdge; default: return .clampToZero }
                }
                d.sAddressMode = address(s.addressU); d.tAddressMode = address(s.addressV)
                guard let state = device.makeSamplerState(descriptor: d) else { throw Failure.gpu("sampler") }
                states[s] = state
            }
            samplers = states
        }

        /// One draw at a time allows the owner to cull instances, sort alpha draws,
        /// and override attached-object transforms/material tint independently.
        func encode(drawIndex: Int, encoder: MTLRenderCommandEncoder, pipelines: Pipelines,
                    viewProjection: simd_float4x4, modelTransform: simd_float4x4,
                    overrides: DrawOverrides = DrawOverrides()) throws {
            guard overrides.visible else { return }
            guard plan.draws.indices.contains(drawIndex) else { throw Failure.malformed("draw index") }
            let draw = plan.draws[drawIndex], instance = plan.instances[draw.instance]
            let geometry = plan.geometries[instance.geometry], part = geometry.parts[draw.part]
            let material = geometry.materials[part.material], color = material.source.color
            let model = modelTransform * overrides.transform * instance.frameTransform
            let determinant = simd_determinant(model)
            guard finite(viewProjection), finite(model), determinant.isFinite, abs(determinant) > 1e-12,
                  overrides.tint.x.isFinite, overrides.tint.y.isFinite, overrides.tint.z.isFinite, overrides.tint.w.isFinite,
                  overrides.alphaCutoff.isFinite, overrides.ambient.isFinite, overrides.diffuse.isFinite, finite(overrides.lightDirection) else { throw Failure.malformed("draw transform/lighting") }
            let normalMatrix = simd_transpose(simd_inverse(model))
            guard finite(normalMatrix) else { throw Failure.malformed("normal transform overflow") }
            let sourceColor = material.modulatesMaterial
                ? SIMD4(Float(color.x), Float(color.y), Float(color.z), Float(color.w)) / 255
                : SIMD4<Float>(repeating: 1)
            let materialColor = overrides.materialColorOverride ?? sourceColor
            guard materialColor.x.isFinite, materialColor.y.isFinite, materialColor.z.isFinite, materialColor.w.isFinite else { throw Failure.malformed("material color override") }
            let boundTexture = overrides.textureOverride ?? material.textureIndex.map { textures[$0] }
            var uniforms = Uniforms(viewProjection: viewProjection, model: model, normalMatrix: normalMatrix,
                                    color: materialColor * overrides.tint,
                                    lightDirectionAmbient: SIMD4(overrides.lightDirection, overrides.ambient),
                                    settings: SIMD4(overrides.diffuse, max(0, min(1, overrides.alphaCutoff)), overrides.ignoreVertexColor ? 1:0, boundTexture == nil ? 0:1))
            let blend = overrides.blendOverride ?? (material.usesBlending || materialColor.w < 1 || overrides.tint.w < 1)
            encoder.setRenderPipelineState(blend ? pipelines.blended : pipelines.opaque)
            encoder.setDepthStencilState(blend ? pipelines.blendedDepth : pipelines.opaqueDepth)
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(geometries[instance.geometry].vertices, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentTexture(boundTexture ?? whiteTexture, index: 0)
            encoder.setFragmentSamplerState(overrides.samplerOverride ?? samplers[material.sampler], index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: part.indexCount, indexType: .uint32,
                                          indexBuffer: geometries[instance.geometry].indices, indexBufferOffset: part.indexStart * 4)
        }
    }
}
