// SPDX-License-Identifier: AGPL-3.0-only
import Metal
import simd

extension NativeRenderWareModel {
    struct Bounds {
        private(set) var low = SIMD3<Float>(repeating: .infinity)
        private(set) var high = SIMD3<Float>(repeating: -.infinity)
        var center: SIMD3<Float> { low + (high - low) * 0.5 }
        var radius: Float { simd_length(high - low) * 0.5 }

        init() {}

        init(plan: Plan) throws {
            self.init()
            let meshes = plan.geometries.map { mesh in
                var box = Bounds()
                for index in mesh.indices { box.extend(to: mesh.vertices[Int(index)].position) }
                return box
            }
            for instance in plan.instances where !plan.geometries[instance.geometry].parts.isEmpty {
                extend(to: meshes[instance.geometry], transformedBy: instance.frameTransform)
            }
            guard radius.isFinite, radius > 0 else { throw Failure.malformed("invalid model bounds") }
        }

        private mutating func extend(to point: SIMD3<Float>) {
            low = simd_min(low, point)
            high = simd_max(high, point)
        }

        mutating func extend(to box: Bounds, transformedBy transform: simd_float4x4) {
            for x in [box.low.x, box.high.x] {
                for y in [box.low.y, box.high.y] {
                    for z in [box.low.z, box.high.z] {
                        let p = transform * SIMD4(x, y, z, 1)
                        extend(to: SIMD3(p.x, p.y, p.z))
                    }
                }
            }
        }
    }
}

/// Local static IPL geometry drawn in GTA coordinates inside the world render pass.
final class NativeInstalledWorldSection {
    private struct Draw {
        let model: NativeRenderWareModel.Uploaded
        let index: Int
        let transform: simd_float4x4
        let center: SIMD3<Float>
    }
    let summary: String
    private let region: NativeISORegionInstallation.Region
    private let pipelines: NativeRenderWareModel.Pipelines
    private let solid: [Draw]
    private let transparent: [Draw]
    private let center: SIMD3<Float>
    private let radius: Float
    private var heading: Float = -1.2
    private var elevation: Float = 0.66
    private var zoom: Float = 1

    init(region: NativeISORegionInstallation.Region, device: MTLDevice) throws {
        self.region = region
        guard let library = device.makeDefaultLibrary() else { throw NativeRenderWareModel.Failure.gpu("missing model shaders") }
        pipelines = try .init(device: device, library: library, color: .bgra8Unorm)
        var resources: [Int: (model: NativeRenderWareModel.Uploaded, bounds: NativeRenderWareModel.Bounds)] = [:]
        var solid: [Draw] = [], transparent: [Draw] = []
        var box = NativeRenderWareModel.Bounds()
        for row in region.instances {
            let transform = try row.worldTransform()
            if resources[row.modelID] == nil {
                guard let plan = region.models[row.modelID], !plan.draws.isEmpty else {
                    throw NativeRenderWareModel.Failure.malformed("missing installed geometry for IPL model \(row.modelID)")
                }
                resources[row.modelID] = (try .init(plan: plan, device: device), try .init(plan: plan))
            }
            guard let resource = resources[row.modelID] else { throw NativeRenderWareModel.Failure.gpu("missing uploaded IPL model") }
            let p = transform * SIMD4(resource.bounds.center, 1)
            let position = SIMD3(p.x, p.y, p.z)
            box.extend(to: resource.bounds, transformedBy: transform)
            let plan = resource.model.plan
            for (index, part) in plan.draws.enumerated() {
                let geometry = plan.geometries[plan.instances[part.instance].geometry]
                let draw = Draw(model: resource.model, index: index, transform: transform, center: position)
                if geometry.materials[geometry.parts[part.part].material].usesBlending { transparent.append(draw) }
                else { solid.append(draw) }
            }
        }
        radius = box.radius
        guard radius.isFinite, radius > 0 else { throw NativeRenderWareModel.Failure.malformed("empty or invalid IPL bounds") }
        center = box.center
        self.solid = solid
        self.transparent = transparent
        let filename = URL(fileURLWithPath: region.placementPath).lastPathComponent
        let collision = region.collisions.isEmpty ? "" : " · \(region.collisions.count) collision models"
        summary = "Rendered \(filename) · \(region.instances.count) placements · \(resources.count) models\(collision)"
    }

    func registerCollision(in world: SwiftRapierWorld?) throws -> NativeInstalledSectionCollision? {
        guard !region.collisions.isEmpty else { return nil } // Earlier visual-only installation.
        guard let world else { throw NativeRenderWareCollisionWorld.Failure.bridge("local physics world") }
        let collision = try NativeInstalledSectionCollision(world: world, instances: region.instances,
                                                           sourceSlots: region.sourceSlots, collisions: region.collisions)
        guard world.step() else { throw NativeRenderWareCollisionWorld.Failure.bridge("section broad phase") }
        return collision
    }

    func orbit(horizontal: Float, vertical: Float) {
        heading -= horizontal
        elevation = max(-1.35, min(1.5, elevation + vertical))
    }

    func magnify(by scale: Float) {
        guard scale.isFinite, scale > 0 else { return }
        zoom = max(0.06, min(3, zoom / scale))
    }

    func camera(aspect: Float, verticalFov: Float) -> NativeSAMPGameCamera.Pose {
        let halfFov = verticalFov * Float.pi / 360
        let narrow = atan(tan(halfFov) * min(1, aspect))
        let distance = 1.05 * radius * zoom / sin(narrow)
        let axis = SIMD3(cos(heading) * cos(elevation), sin(heading) * cos(elevation), sin(elevation))
        return .init(eye: center + distance * axis, target: center)
    }

    func encode(encoder: MTLRenderCommandEncoder, matrix: simd_float4x4, eye: SIMD3<Float>) throws {
        func encode(_ draw: Draw) throws {
            try draw.model.encode(drawIndex: draw.index, encoder: encoder, pipelines: pipelines,
                                  viewProjection: matrix, modelTransform: draw.transform)
        }
        for draw in solid { try encode(draw) }
        for draw in transparent.sorted(by: { simd_distance_squared(eye, $0.center) > simd_distance_squared(eye, $1.center) }) {
            try encode(draw)
        }
    }
}
