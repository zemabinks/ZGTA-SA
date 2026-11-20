// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal
import simd

/// Native custom-ped mesh/material upload, backed by the actual skeletal actor.
/// This is a render resource, not a replacement animation controller. Callers
/// supply a real actor pose; failed rig/texture imports never become a T-pose.
enum NativeRenderWarePedModel {
    enum Failure: Error, CustomStringConvertible {
        case incompatible(String), gpu(String), malformed(String)
        var description: String {
            switch self {
            case .incompatible(let value): return "Incompatible RW pedestrian: \(value)"
            case .gpu(let value): return "RW pedestrian GPU failure: \(value)"
            case .malformed(let value): return "Malformed RW pedestrian draw: \(value)"
            }
        }
    }
    struct Plan {
        let skeleton: NativeRenderWareSkeleton.Plan
        /// Uses exactly skeleton.vertices order, with indices grouped by material.
        let model: NativeRenderWareModel.Plan
    }

    /// Uses the same clip-W distance and linear fog interval as ordinary
    /// actors. Kept separate from material tint, alpha and directional light.
    /// The default preserves isolated resource previews and verifier draws.
    struct Environment {
        var fogColor = SIMD4<Float>(0, 0, 0, 1)
        var fogSettings = SIMD4<Float>(0, 1, 0, 0)
    }

    static func prepare(dff: NativeRenderWareDFF, txd: NativeRenderWareTXD.TextureDictionary?,
                        rigLimits: NativeRenderWareSkeleton.Limits = .init(),
                        modelLimits: NativeRenderWareModel.Limits = .init()) throws -> Plan {
        let skeleton = try NativeRenderWareSkeleton.prepare(dff, limits: rigLimits)
        guard dff.atomics[0].flags & 4 != 0 else { throw Failure.incompatible("non-render atomic") }
        let source = dff.geometries[skeleton.geometryIndex]
        guard source.textureCoordinates.allSatisfy({ $0.count == source.vertexCount }) else {
            throw Failure.incompatible("texture coordinate count")
        }
        // Reuse the static loader's validated material/texture/sampler resolution.
        // The temporary CPU clump has identity coordinates and no skin; it never
        // enters the renderer. Rebuild its mesh in SKN1 order before upload.
        let geometry = NativeRenderWareDFF.Geometry(flags: source.flags, vertexCount: source.vertexCount,
            textureCoordinates: source.textureCoordinates, prelitColors: source.prelitColors,
            triangles: source.triangles, materials: source.materials, morphTargets: source.morphTargets, skin: nil)
        let identity = matrix_identity_float4x4
        let frame = NativeRenderWareDFF.Frame(name: nil, parent: -1, flags: 0,
            localTransform: identity, worldTransform: identity, hierarchy: nil)
        let atomic = NativeRenderWareDFF.Atomic(frame: 0, geometry: 0, flags: 4, unused: 0)
        let staticDFF = NativeRenderWareDFF(version: dff.version, frames: [frame], geometries: [geometry], atomics: [atomic])
        let base = try NativeRenderWareModel.prepare(dff: staticDFF, txd: txd, limits: modelLimits)
        for diagnostic in base.diagnostics {
            if case .missingTexture(_, _, let name) = diagnostic { throw Failure.incompatible("missing texture \(name)") }
        }
        guard let prepared = base.geometries.first, base.geometries.count == 1, !base.draws.isEmpty else {
            throw Failure.incompatible("empty material mesh")
        }
        if source.textureCoordinates.isEmpty,
           prepared.parts.contains(where: { prepared.materials[$0.material].textureIndex != nil }) {
            throw Failure.incompatible("textured material has no UV coordinates")
        }
        guard skeleton.vertices.count <= modelLimits.vertices else { throw Failure.incompatible("material-split vertex budget") }
        let bytes = skeleton.vertices.count * MemoryLayout<NativeRenderWareModel.Vertex>.stride +
            skeleton.indices.count * MemoryLayout<UInt32>.stride
        guard bytes <= modelLimits.meshBytes else { throw Failure.incompatible("material-split mesh byte budget") }
        let vertices = skeleton.vertices.map { prepared.vertices[$0.sourceIndex] }
        let uvSets = source.textureCoordinates.map { layer in skeleton.vertices.map { layer[$0.sourceIndex] } }
        var buckets = [[UInt32]](repeating: [], count: prepared.materials.count)
        for (index, triangle) in source.triangles.enumerated() {
            buckets[Int(triangle.material)].append(contentsOf: skeleton.indices[(index * 3)..<(index * 3 + 3)])
        }
        let mesh = NativeRenderWareModel.Geometry(sourceIndex: skeleton.geometryIndex, vertices: vertices,
            textureCoordinates: uvSets, indices: buckets.flatMap { $0 }, parts: prepared.parts, materials: prepared.materials)
        let instance = NativeRenderWareModel.Instance(sourceAtomic: skeleton.atomicIndex, geometry: 0,
            frameName: dff.frames[dff.atomics[0].frame].name, frameTransform: identity)
        let model = NativeRenderWareModel.Plan(geometries: [mesh], textures: base.textures, instances: [instance],
            draws: base.draws, diagnostics: base.diagnostics, meshByteCount: bytes, textureByteCount: base.textureByteCount)
        return Plan(skeleton: skeleton, model: model)
    }

    struct Pipelines {
        let opaque: MTLRenderPipelineState
        let blended: MTLRenderPipelineState
        let opaqueDepth: MTLDepthStencilState
        let blendedDepth: MTLDepthStencilState
        init(device: MTLDevice, library: MTLLibrary, color: MTLPixelFormat, depth: MTLPixelFormat = .depth32Float) throws {
            guard let vertex = library.makeFunction(name: "native_rw_ped_vertex"),
                  let fragment = library.makeFunction(name: "native_rw_ped_fragment") else {
                throw Failure.gpu("ped vertex/scene fragment missing from library")
            }
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
            guard let a = device.makeDepthStencilState(descriptor: d) else { throw Failure.gpu("opaque depth") }
            d.isDepthWriteEnabled = false
            guard let b = device.makeDepthStencilState(descriptor: d) else { throw Failure.gpu("blended depth") }
            opaqueDepth = a; blendedDepth = b
        }
    }

    final class Uploaded {
        let plan: Plan
        let actor: NativeSkeletalActor
        let resources: NativeRenderWareModel.Uploaded
        init(plan: Plan, device: MTLDevice,validateActor:((NativeSkeletalActor)throws->Void)?=nil) throws {
            guard let actor = NativeSkeletalActor(data: plan.skeleton.encodedSKN1(),
                vertexCount: plan.skeleton.vertices.count, device: device) else {
                throw Failure.incompatible("NativeSkeletalActor rejected SKN1")
            }
            // Reject a foreign rig before allocating the material mesh/images.
            try validateActor?(actor)
            self.plan = plan; self.actor = actor
            resources = try NativeRenderWareModel.Uploaded(plan: plan.model, device: device)
        }

        /// The pose palette ALREADY supplies skin correction and coordinate basis.
        /// worldTransform only places that posed actor in the scene; applying the
        /// DFF atomic transform or skeleton.axis again would double-transform it.
        func encode(drawIndex: Int, pose: NativeSkeletalActor.Pose, encoder: MTLRenderCommandEncoder,
                    pipelines: Pipelines, viewProjection: simd_float4x4, worldTransform: simd_float4x4,
                    overrides: NativeRenderWareModel.DrawOverrides = .init(),
                    environment: Environment = .init()) throws {
            guard overrides.visible else { return }
            guard plan.model.draws.indices.contains(drawIndex), pose.palette.count == plan.skeleton.bones.count,
                  pose.palette.allSatisfy({ NativeRenderWarePedModel.finite($0) }) else {
                throw Failure.malformed("draw index or pose palette")
            }
            let draw = plan.model.draws[drawIndex], geometry = plan.model.geometries[0]
            let part = geometry.parts[draw.part], material = geometry.materials[part.material]
            let model = worldTransform * overrides.transform, determinant = simd_determinant(model)
            guard NativeRenderWarePedModel.finite(viewProjection), NativeRenderWarePedModel.finite(model),
                  determinant.isFinite, abs(determinant) > 1e-12,
                  (0..<4).allSatisfy({ overrides.tint[$0].isFinite }), overrides.alphaCutoff.isFinite,
                  (0..<4).allSatisfy({environment.fogColor[$0].isFinite && environment.fogSettings[$0].isFinite}),
                  overrides.ambient.isFinite, overrides.diffuse.isFinite,
                  (0..<3).allSatisfy({ overrides.lightDirection[$0].isFinite }) else {
                throw Failure.malformed("non-finite/singular transform or lighting")
            }
            let normal = simd_transpose(simd_inverse(model))
            guard NativeRenderWarePedModel.finite(normal) else { throw Failure.malformed("normal transform overflow") }
            let color = material.source.color
            // Keep the common material ABI in sync with the static encoder.
            // Binding a texture is insufficient: settings.w admits sampling.
            let sourceColor = material.modulatesMaterial
                ? SIMD4(Float(color.x), Float(color.y), Float(color.z), Float(color.w)) / 255
                : SIMD4<Float>(repeating: 1)
            let materialColor = overrides.materialColorOverride ?? sourceColor
            guard (0..<4).allSatisfy({materialColor[$0].isFinite})else{throw Failure.malformed("material color")}
            let boundTexture = overrides.textureOverride ?? material.textureIndex.map{resources.textures[$0]}
            var uniforms = NativeRenderWareModel.Uniforms(viewProjection: viewProjection, model: model, normalMatrix: normal,
                color: materialColor * overrides.tint,
                lightDirectionAmbient: SIMD4(overrides.lightDirection, overrides.ambient),
                settings: SIMD4(overrides.diffuse, max(0, min(1, overrides.alphaCutoff)), overrides.ignoreVertexColor ? 1:0, boundTexture == nil ? 0:1))
            let blend = overrides.blendOverride ?? (material.usesBlending || materialColor.w < 1 || overrides.tint.w < 1)
            encoder.setRenderPipelineState(blend ? pipelines.blended : pipelines.opaque)
            encoder.setDepthStencilState(blend ? pipelines.blendedDepth : pipelines.opaqueDepth)
            encoder.setCullMode(.none)
            encoder.setVertexBuffer(resources.geometries[0].vertices, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<NativeRenderWareModel.Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<NativeRenderWareModel.Uniforms>.stride, index: 1)
            // Every draw binds its scene, including the disabled default. A
            // prior character's fog may never leak into another render owner.
            var scene = environment
            encoder.setFragmentBytes(&scene, length: MemoryLayout<Environment>.stride, index: 4)
            actor.bind(pose: pose, encoder: encoder)
            encoder.setFragmentTexture(boundTexture ?? resources.whiteTexture, index: 0)
            encoder.setFragmentSamplerState(overrides.samplerOverride ?? resources.samplers[material.sampler], index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: part.indexCount, indexType: .uint32,
                indexBuffer: resources.geometries[0].indices, indexBufferOffset: part.indexStart * 4)
        }
    }
    private static func finite(_ matrix: simd_float4x4) -> Bool {
        (0..<4).allSatisfy { column in (0..<4).allSatisfy { matrix[column][$0].isFinite } }
    }
}
