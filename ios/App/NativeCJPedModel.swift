// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

extension NativeRenderWarePedModel {
    /// Reuses the existing actual skin/material/Metal upload contract. The
    /// caller still supplies an authenticated wardrobe profile and animation
    /// owner. This function does not advertise this candidate as legacy skin0.
    static func prepareCJ(_ candidate: NativeCJResources.Prepared) throws -> Plan {
        let plan = try prepare(dff: candidate.assembly.dff,txd: candidate.textures)
        guard plan.model.isComplete,
              plan.skeleton.encodedSKN1() == candidate.assembly.skeleton.encodedSKN1() else {
            throw Failure.incompatible("incomplete or mismatched player assembly")
        }
        return plan
    }
}
