import Foundation
import CoreGraphics

/// Native input boundaries. These are platform correctness rules, not a claim
/// that the retail game's undocumented stick response has been measured.
enum NativeInputMath {
    static func stick(x: Float, y: Float, deadzone: Float = 0.05) -> SIMD2<Float> {
        guard x.isFinite, y.isFinite else { return .zero }
        let value = SIMD2(x, y), length = hypot(x, y)
        guard length > deadzone else { return .zero }
        return length > 1 ? value / length : value
    }
}

struct NativeControllerInputGate {
    private(set) var needsNeutral = true
    mutating func reset() { needsNeutral = true }
    /// Use the radial movement boundary when deciding whether a stick is neutral.
    mutating func accepts(active: Bool, left: SIMD2<Float>, right: SIMD2<Float>,
                         triggers: SIMD2<Float>, pressed: Bool) -> Bool {
        accepts(active: active, axes: [hypot(left.x, left.y), hypot(right.x, right.y),
                                      triggers.x, triggers.y], pressed: pressed)
    }
    mutating func accepts(active: Bool, axes: [Float], pressed: Bool) -> Bool {
        guard active else { reset(); return false }
        guard axes.allSatisfy(\.isFinite) else { reset(); return false }
        if needsNeutral {
            guard !pressed, axes.allSatisfy({ abs($0) <= 0.05 }) else { return false }
            needsNeutral = false
        }
        return true
    }
}

/// Preserve ordinary low-frame-rate elapsed time. A suspension/clock jump is
/// a discontinuity, rather than a gigantic movement command on resumption.
struct NativeGameFrameClock {
    struct Frame { let delta: Double; let steps: [Double]; let discontinuity: Bool }
    private var previous: Double?
    mutating func reset() { previous = nil }
    mutating func advance(timestamp: Double, active: Bool) -> Frame {
        guard active, timestamp.isFinite else { reset(); return Frame(delta: 0, steps: [], discontinuity: false) }
        guard let previous else { self.previous = timestamp; return Frame(delta: 1.0 / 60.0, steps: [1.0 / 60.0], discontinuity: false) }
        self.previous = timestamp
        let elapsed = timestamp - previous
        guard elapsed > 0, elapsed <= 0.5 else {
            return Frame(delta: 0, steps: [], discontinuity: elapsed < 0 || elapsed > 0.5)
        }
        let count = max(1, Int(ceil(elapsed / (1.0 / 60.0) - 1e-8)))
        return Frame(delta: elapsed, steps: Array(repeating: elapsed / Double(count), count: count), discontinuity: false)
    }
}

struct NativeVirtualStickState {
    static let ringRadius: CGFloat = 55, knobRadius: CGFloat = 21, travel: CGFloat = 44
    private(set) var value = CGPoint.zero
    private(set) var origin = CGPoint.zero
    private(set) var active = false
    private var touchOrigin = CGPoint.zero
    mutating func begin(at point: CGPoint, bounds: CGRect) {
        guard point.x.isFinite, point.y.isFinite, bounds.contains(point) else { return }
        touchOrigin = point; origin = Self.displayOrigin(point, bounds: bounds); value = .zero; active = true
    }
    mutating func move(to point: CGPoint) {
        guard active, point.x.isFinite, point.y.isFinite else { return }
        let dx = point.x - touchOrigin.x, dy = point.y - touchOrigin.y
        let scale = max(Self.travel, hypot(dx, dy))
        value = CGPoint(x: dx / scale, y: dy / scale)
    }
    mutating func reset() { active = false; value = .zero }
    static func displayOrigin(_ point: CGPoint, bounds: CGRect) -> CGPoint {
        let inset = max(ringRadius, travel + knobRadius)
        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
            high >= low ? min(high, max(low, value)) : (low + high) / 2
        }
        return CGPoint(x: clamp(point.x, bounds.minX + inset, bounds.maxX - inset),
                       y: clamp(point.y, bounds.minY + inset, bounds.maxY - inset))
    }
}
