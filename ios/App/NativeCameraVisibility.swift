import Foundation
import simd

/// Native rendering safety envelope, not a reconstruction of retail camera
/// fading. Keep the existing camera collision/follow equations unchanged.
/// A near plane inside the player's capsule must not draw the camera through
/// the body or attached pack. Spatial hysteresis avoids threshold flicker.
struct NativeCameraVisibility {
    private(set) var hidden = false
    mutating func reset() { hidden = false }
    @discardableResult mutating func update(eye: SIMD3<Float>, feet: SIMD3<Float>, nearPlane: Float,
        bodyBottom: Float = 0.35, bodyTop: Float = 1.65, radius: Float = 0.35,
        attachmentRadius: Float = 0, exitClearance: Float = 0.08) -> Bool {
        let values = [eye.x,eye.y,eye.z,feet.x,feet.y,feet.z,nearPlane,bodyBottom,bodyTop,radius,attachmentRadius,exitClearance]
        guard values.allSatisfy(\.isFinite), bodyTop >= bodyBottom, radius >= 0,
              attachmentRadius >= 0, nearPlane >= 0, exitClearance >= 0 else { hidden = true; return true }
        let low = feet + SIMD3(0,0,bodyBottom), high = feet + SIMD3(0,0,bodyTop)
        let axis = high-low, length = simd_length_squared(axis)
        let t = length > 0 ? min(1,max(0,simd_dot(eye-low,axis)/length)) : 0
        let threshold = radius + attachmentRadius + nearPlane + (hidden ? exitClearance : 0)
        hidden = simd_length_squared(eye-(low+axis*t)) <= threshold*threshold
        return hidden
    }
}
