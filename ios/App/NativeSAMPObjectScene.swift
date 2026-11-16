// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// RenderWare/GTA Z-up object transforms. Pedestrian animation axes and native
/// physics Y-up conversions must not be applied to these static DFF frames.
enum NativeSAMPObjectScene {
    struct Draw {
        let object: NativeSAMPObjects.Instance
        let transform: simd_float4x4
    }
    struct Snapshot {
        let draws: [Draw]
        let unresolved: Set<UInt16>
    }
    /// GTAQuat uses Y*X*Z and negative degree angles, unlike a generic XYZ
    /// helper. Reference: open.mp-sdk/include/gtaquat.hpp d06f793c2aebcc9f065dd27f9f3e2a56270dc2e8.
    static func transform(position: SIMD3<Float>, degrees: SIMD3<Float>) -> simd_float4x4 {
        let angle = degrees * (-Float.pi / 180)
        let x = simd_quatf(angle: angle.x, axis: SIMD3(1,0,0))
        let y = simd_quatf(angle: angle.y, axis: SIMD3(0,1,0))
        let z = simd_quatf(angle: angle.z, axis: SIMD3(0,0,1))
        var matrix = simd_float4x4(y * x * z)
        matrix.columns.3 = SIMD4(position,1)
        return matrix
    }
    static func resolve(_ objects: [NativeSAMPObjects.Instance], maximumDepth: Int = 64,
                        externalParent: (NativeSAMPObjects.Parent) -> simd_float4x4?) -> Snapshot {
        // Duplicate identifiers never resolve through an arbitrary first/last row.
        var byID: [UInt16: NativeSAMPObjects.Instance] = [:], invalid = Set<UInt16>()
        for object in objects {
            if byID.updateValue(object, forKey: object.id) != nil { invalid.insert(object.id) }
        }
        var made: [UInt16: simd_float4x4] = [:], visiting = Set<UInt16>(), failed = invalid
        func finite(_ matrix: simd_float4x4) -> Bool {
            (0..<4).allSatisfy { column in (0..<4).allSatisfy { row in matrix[column][row].isFinite } }
        }
        func make(_ id: UInt16, depth: Int) -> simd_float4x4? {
            if let value = made[id] { return value }
            guard depth < max(1,min(128,maximumDepth)), !visiting.contains(id), !failed.contains(id), let object = byID[id] else {
                failed.insert(id); return nil
            }
            visiting.insert(id); defer { visiting.remove(id) }
            let value: simd_float4x4
            if let attachment = object.attachment {
                let parent: simd_float4x4?
                switch attachment.parent {
                case .object(let other): parent = make(other, depth: depth + 1)
                default: parent = externalParent(attachment.parent)
                }
                guard let parent, finite(parent) else { failed.insert(id); return nil }
                if attachment.syncRotation {
                    value = parent * transform(position: attachment.offset, degrees: attachment.rotation)
                } else {
                    let point = parent * SIMD4(attachment.offset,1)
                    value = transform(position: SIMD3(point.x,point.y,point.z), degrees: attachment.rotation)
                }
            } else { value = transform(position: object.position, degrees: object.rotation) }
            guard finite(value) else { failed.insert(id); return nil }
            made[id] = value; return value
        }
        let draws = byID.keys.sorted().compactMap { id -> Draw? in
            guard let object=byID[id],let matrix=make(id,depth:0) else{return nil}
            return Draw(object:object,transform:matrix)
        }
        return Snapshot(draws:draws,unresolved:Set(byID.keys).subtracting(made.keys))
    }
}
