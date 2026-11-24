// SPDX-License-Identifier: AGPL-3.0-only
import simd

/// Owns a section's IPL bodies in the same Rapier world used for normal gameplay.
/// Destruction or an incomplete registration removes only this section's bodies.
final class NativeInstalledSectionCollision {
    let owner: NativeRenderWareCollisionWorld

    init(world: SwiftRapierWorld, instances: [NativeWorldPlacement.Instance], sourceSlots: [Int],
         collisions: [Int: NativeRenderWareCollision.Model]) throws {
        let failure = NativeRenderWareCollisionWorld.Failure.invalid("IPL slot or original collision model mismatch")
        guard instances.count == sourceSlots.count, Set(sourceSlots).count == sourceSlots.count else { throw failure }
        owner = try .init(world: world)
        do {
            for (instance, slot) in zip(instances, sourceSlots) {
                guard let id = UInt64(exactly: slot), let model = collisions[instance.modelID],
                      let name = instance.modelName, model.name?.lowercased() == name.lowercased() else { throw failure }
                let matrix = try instance.worldTransform()
                let axes = simd_float3x3(SIMD3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
                                         SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
                                         SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
                try owner.insert(.init(id: id, model: model, transform: .init(position: instance.position, rotation: simd_quatf(axes))))
            }
        } catch {
            owner.removeAll()
            throw error
        }
    }
}
