import UIKit
import GameController
import MetalKit

final class NativeGameViewController: UIViewController {
    private let server: ServerAddress
    private let network: NativeMultiplayerClient
    private let renderer: NativeWorldRenderer?
    private let status = UILabel()
    private let players = UILabel()
    private let stick = VirtualStick()
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var lastNetwork: CFTimeInterval = 0
    private var turn: Float = 0
    private var run = false
    private var jumping = false

    init(server: ServerAddress) {
        self.server = server
        self.network = NativeMultiplayerClient(server: server)
        self.renderer = NativeWorldRenderer()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        if let renderer {
            renderer.server = server
            renderer.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(renderer.view)
            NSLayoutConstraint.activate([
                renderer.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                renderer.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                renderer.view.topAnchor.constraint(equalTo: view.topAnchor),
                renderer.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            renderer.onStatus = { [weak self] text in self?.status.text = text }
            renderer.loadNearby()
        } else {
            status.text = "METAL IS UNAVAILABLE ON THIS DEVICE"
        }
        installHUD()
        network.onStatus = { [weak self] text in self?.status.text = text }
        network.onPresence = { [weak self] count, names in
            self?.players.text = "\(count) PLAYER\(count == 1 ? "" : "S") ONLINE" +
                (names.count > 1 ? "  ·  " + names.joined(separator: ", ") : "")
        }
        network.connect()
        NotificationCenter.default.addObserver(self, selector: #selector(controllerChanged), name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerChanged), name: .GCControllerDidDisconnect, object: nil)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        displayLink?.invalidate()
        network.disconnect()
    }

    private func installHUD() {
        let top = UIView()
        top.backgroundColor = UIColor.black.withAlphaComponent(0.76)
        top.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(top)
        let brand = label("ZGTA:SA  /  NATIVE", size: 18, bold: true)
        top.addSubview(brand)
        let menu = button("MENU", action: #selector(close))
        top.addSubview(menu)
        let divider = UIView()
        divider.backgroundColor = UIColor(red: 0.18, green: 0.44, blue: 0.83, alpha: 1)
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)
        status.text = "LOADING LOCAL CITY"
        status.textColor = .white
        status.font = .systemFont(ofSize: 13, weight: .semibold)
        status.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)
        players.text = "CONNECTING TO MULTIPLAYER"
        players.textColor = .white
        players.font = .systemFont(ofSize: 12, weight: .semibold)
        players.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        players.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(players)
        stick.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stick)
        let look = UIView()
        look.backgroundColor = UIColor.black.withAlphaComponent(0.22)
        look.layer.cornerRadius = 52
        look.layer.borderWidth = 1
        look.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        look.translatesAutoresizingMaskIntoConstraints = false
        look.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(lookPan(_:))))
        view.addSubview(look)
        let lookText = label("LOOK", size: 14, bold: true)
        lookText.textAlignment = .center
        look.addSubview(lookText)
        let runButton = button("RUN", action: #selector(toggleRun))
        runButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        view.addSubview(runButton)
        let jumpButton = button("JUMP", action: #selector(jump))
        jumpButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        view.addSubview(jumpButton)
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            top.topAnchor.constraint(equalTo: view.topAnchor),
            top.heightAnchor.constraint(equalToConstant: 47),
            brand.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            brand.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            menu.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            menu.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.topAnchor.constraint(equalTo: top.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 4),
            status.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            status.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),
            players.leadingAnchor.constraint(equalTo: status.leadingAnchor),
            players.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 4),
            stick.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 30),
            stick.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            stick.widthAnchor.constraint(equalToConstant: 122),
            stick.heightAnchor.constraint(equalToConstant: 122),
            look.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -30),
            look.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -25),
            look.widthAnchor.constraint(equalToConstant: 104),
            look.heightAnchor.constraint(equalToConstant: 104),
            lookText.centerXAnchor.constraint(equalTo: look.centerXAnchor),
            lookText.centerYAnchor.constraint(equalTo: look.centerYAnchor),
            runButton.trailingAnchor.constraint(equalTo: look.leadingAnchor, constant: -14),
            runButton.bottomAnchor.constraint(equalTo: look.centerYAnchor, constant: -5),
            jumpButton.trailingAnchor.constraint(equalTo: look.leadingAnchor, constant: -14),
            jumpButton.topAnchor.constraint(equalTo: look.centerYAnchor, constant: 5)
        ])
    }

    private func label(_ text: String, size: CGFloat, bold: Bool) -> UILabel {
        let result = UILabel()
        result.text = text
        result.textColor = .white
        result.font = .systemFont(ofSize: size, weight: bold ? .black : .regular, width: .condensed)
        result.translatesAutoresizingMaskIntoConstraints = false
        return result
    }

    private func button(_ text: String, action: Selector) -> UIButton {
        let result = UIButton(type: .system)
        result.setTitle(text, for: .normal)
        result.setTitleColor(.white, for: .normal)
        result.titleLabel?.font = .systemFont(ofSize: 18, weight: .black, width: .condensed)
        result.translatesAutoresizingMaskIntoConstraints = false
        result.addTarget(self, action: action, for: .touchUpInside)
        return result
    }

    @objc private func close() { dismiss(animated: true) }
    @objc private func controllerChanged() { status.text = GCController.controllers().isEmpty ? "TOUCH CONTROLS ACTIVE" : "CONTROLLER CONNECTED" }
    @objc private func toggleRun() { run.toggle() }
    @objc private func jump() { jumping = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.jumping = false } }

    @objc private func lookPan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .ended || gesture.state == .cancelled { turn = 0; return }
        turn = Float(max(-1, min(1, gesture.velocity(in: gesture.view).x / 400)))
    }

    @objc private func tick(_ link: CADisplayLink) {
        let delta = lastTime == 0 ? Float(1.0 / 60) : Float(min(0.05, link.timestamp - lastTime))
        lastTime = link.timestamp
        var forward = Float(-stick.value.y)
        var sideways = Float(stick.value.x)
        var steering = turn
        var gamepadRunning = false
        var gamepadJumping = false
        if let pad = GCController.controllers().compactMap(\.extendedGamepad).first {
            let lx = pad.leftThumbstick.xAxis.value, ly = pad.leftThumbstick.yAxis.value
            if abs(lx) + abs(ly) > 0.05 { forward = ly; sideways = lx }
            let rx = pad.rightThumbstick.xAxis.value
            if abs(rx) > 0.05 { steering = rx }
            gamepadRunning = pad.buttonA.isPressed
            gamepadJumping = pad.buttonB.isPressed
        }
        let walking = abs(forward) + abs(sideways) > 0.05
        let speed: Float = (run || gamepadRunning) ? 2 : 1
        renderer?.move(forward: forward * speed, sideways: sideways * speed, turn: steering, delta: delta)
        if link.timestamp - lastNetwork > 0.2, let renderer {
            lastNetwork = link.timestamp
            var position = renderer.position
            if jumping || gamepadJumping { position.z += 1 }
            network.sendPosition(position, heading: renderer.direction, moving: walking)
        }
    }
}

private final class VirtualStick: UIView {
    private let knob = UIView()
    private(set) var value = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.34)
        layer.cornerRadius = 61
        layer.borderColor = UIColor.white.withAlphaComponent(0.45).cgColor
        layer.borderWidth = 2
        knob.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        knob.frame = CGRect(x: 41, y: 41, width: 40, height: 40)
        knob.layer.cornerRadius = 20
        knob.isUserInteractionEnabled = false
        addSubview(knob)
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches.first?.location(in: self)) }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches.first?.location(in: self)) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { update(nil) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { update(nil) }

    private func update(_ point: CGPoint?) {
        if let point {
            let dx = point.x - bounds.midX, dy = point.y - bounds.midY
            let length = max(1, hypot(dx, dy))
            let scale = min(1, 42 / length)
            value = CGPoint(x: dx * scale / 42, y: dy * scale / 42)
        } else { value = .zero }
        knob.center = CGPoint(x: bounds.midX + value.x * 42, y: bounds.midY + value.y * 42)
    }
}
