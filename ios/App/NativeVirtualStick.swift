import UIKit

/// A floating analog stick. Its visual circle stays inside the existing
/// safe-area hit zone; motion remains relative to the actual initial touch.
final class VirtualStick: UIView {
    private let ring = UIView(), knob = UIView()
    private var state = NativeVirtualStickState()
    private var activeTouch: UITouch?
    var value: CGPoint { state.value }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear; isMultipleTouchEnabled = false
        ring.layer.cornerRadius = NativeVirtualStickState.ringRadius
        ring.layer.borderWidth = 2; ring.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        ring.backgroundColor = UIColor.black.withAlphaComponent(0.12)
        knob.layer.cornerRadius = NativeVirtualStickState.knobRadius
        knob.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        for item in [ring, knob] { item.isUserInteractionEnabled = false; item.isHidden = true; addSubview(item) }
        accessibilityLabel = "Analog stick"; accessibilityTraits = .allowsDirectInteraction
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func reset() { state.reset(); activeTouch = nil; ring.isHidden = true; knob.isHidden = true; setNeedsLayout() }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { reset() } }
    override func layoutSubviews() {
        super.layoutSubviews()
        let center = NativeVirtualStickState.displayOrigin(state.origin, bounds: bounds)
        ring.bounds = CGRect(x: 0, y: 0, width: NativeVirtualStickState.ringRadius * 2, height: NativeVirtualStickState.ringRadius * 2)
        knob.bounds = CGRect(x: 0, y: 0, width: NativeVirtualStickState.knobRadius * 2, height: NativeVirtualStickState.knobRadius * 2)
        ring.center = center
        knob.center = CGPoint(x: center.x + state.value.x * NativeVirtualStickState.travel,
                              y: center.y + state.value.y * NativeVirtualStickState.travel)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch; state.begin(at: touch.location(in: self), bounds: bounds)
        ring.isHidden = !state.active; knob.isHidden = !state.active; setNeedsLayout()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        state.move(to: touch.location(in: self)); setNeedsLayout()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = activeTouch, touches.contains(touch) { reset() }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { reset() }
}
