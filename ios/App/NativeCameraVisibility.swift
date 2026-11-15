import Foundation
import simd

/// Native rendering safety envelope, not a reconstruction of retail camera
/// fading. Keep the existing camera collision/follow equations unchanged.
/// A near plane inside the player's capsule must not draw the camera through
/// the body or attached pack. A separate presentation clearance covers the
/// obstructed close-camera view. Use binary visibility: naive translucent
/// skeletal triangles expose unsorted internal surfaces. This clearance is a
/// native policy pending original-runtime measurement, not a retail constant.
struct NativeCameraVisibility {
    private(set) var hidden = false
    var opacity:Float {hidden ? 0:1}
    mutating func reset() { hidden = false }
    @discardableResult mutating func update(eye: SIMD3<Float>, feet: SIMD3<Float>, nearPlane: Float,
        bodyBottom: Float = 0.35, bodyTop: Float = 1.65, radius: Float = 0.35,
        attachmentRadius: Float = 0, exitClearance: Float = 0.08, presentationClearance:Float = 0) -> Bool {
        let values = [eye.x,eye.y,eye.z,feet.x,feet.y,feet.z,nearPlane,bodyBottom,bodyTop,radius,attachmentRadius,exitClearance,presentationClearance]
        guard values.allSatisfy(\.isFinite), bodyTop >= bodyBottom, radius >= 0,
              attachmentRadius >= 0, nearPlane >= 0, exitClearance >= 0, presentationClearance >= 0 else { hidden = true; return true }
        let low = feet + SIMD3(0,0,bodyBottom), high = feet + SIMD3(0,0,bodyTop)
        let axis = high-low, length = simd_length_squared(axis)
        let t = length > 0 ? min(1,max(0,simd_dot(eye-low,axis)/length)) : 0
        let threshold = max(radius+attachmentRadius+nearPlane,presentationClearance+attachmentRadius) + (hidden ? exitClearance:0)
        hidden = simd_length_squared(eye-(low+axis*t)) <= threshold*threshold
        return hidden
    }
}
