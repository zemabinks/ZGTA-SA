import UIKit
import GameController
import MetalKit

final class NativeGameViewController: UIViewController {
    private let server: ServerAddress
    private let network: NativeMultiplayerClient
    private let gameplay: NativeGameplayClient
    private let renderer: NativeWorldRenderer?
    private let status = UILabel()
    private let players = UILabel()
    private let objective = UILabel()
    private let vehicleButton = UIButton(type: .system)
    private let attackButton = UIButton(type: .system)
    private let vitals = UILabel()
    private let stick = VirtualStick()
    private weak var gameplayPanel: NativeGameplayPanel?
    private var currentVehicle: RemoteVehicle?
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var lastNetwork: CFTimeInterval = 0
    private var lastGameplay: CFTimeInterval = 0
    private var lastVehicleButton = false
    private var lastJobsButton = false
    private var lastAutomaticCheckpoint: [String: Date] = [:]
    private var turn: Float = 0
    private var run = false
    private var lastJumpButton = false
    private var lastAttackButton = false
    private var lastAttackTime: CFTimeInterval = 0

    init(server: ServerAddress) {
        self.server = server
        self.network = NativeMultiplayerClient(server: server)
        self.gameplay = NativeGameplayClient(server: server)
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
            renderer.loadModelIndex()
        } else {
            status.text = "METAL IS UNAVAILABLE ON THIS DEVICE"
        }
        installHUD()
        network.onStatus = { [weak self] text in self?.status.text = text }
        network.onPresence = { [weak self] count, names in
            self?.players.text = "\(count) PLAYER\(count == 1 ? "" : "S") ONLINE" +
                (names.count > 1 ? "  ·  " + names.joined(separator: ", ") : "")
        }
        network.onPlayers = { [weak self] players in self?.renderer?.remotePlayers = players }
        network.onVehicles = { [weak self] vehicles in self?.renderer?.remoteVehicles = vehicles }
        network.onEnter = { [weak self] id, okay in
            guard let self else { return }
            guard okay, let vehicle = self.network.vehicles[id] else {
                self.status.text = "VEHICLE ACCESS DENIED"
                return
            }
            self.currentVehicle = vehicle
            self.renderer?.enter(vehicle)
            self.vehicleButton.setTitle("EXIT CAR", for: .normal)
            self.status.text = "DRIVING \(vehicle.name.uppercased())"
        }
        network.onTeleport = { [weak self] point in self?.renderer?.teleport(x: point.x, y: point.y, z: point.z) }
        network.onVitals = { [weak self] health, armour in
            self?.vitals.text = "HEALTH \(health)  ·  ARMOUR \(armour)"
            self?.attackButton.setTitle(health == 0 ? "RESPAWN" : "HIT", for: .normal)
        }
        gameplay.onState = { [weak self] state in
            guard let self else { return }
            self.network.syncVitals(from: state)
            self.gameplayPanel?.update(state)
            self.showObjective(state)
            self.maybeAdvanceCheckpoint(state)
        }
        gameplay.onResult = { [weak self] result in self?.status.text = result.uppercased() }
        network.connect()
        gameplay.refresh()
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
        let missions = button("JOBS / GARAGE", action: #selector(openGameplay))
        top.addSubview(missions)
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
        vitals.text = "HEALTH 100  ·  ARMOUR 0"
        vitals.textColor = .white
        vitals.font = .systemFont(ofSize: 12, weight: .semibold)
        vitals.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        vitals.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(vitals)
        objective.textColor = .white
        objective.font = .systemFont(ofSize: 13, weight: .bold, width: .condensed)
        objective.numberOfLines = 2
        objective.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        objective.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(objective)
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
        attackButton.setTitle("HIT", for: .normal)
        attackButton.setTitleColor(.white, for: .normal)
        attackButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .black, width: .condensed)
        attackButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        attackButton.translatesAutoresizingMaskIntoConstraints = false
        attackButton.addTarget(self, action: #selector(attack), for: .touchUpInside)
        view.addSubview(attackButton)
        vehicleButton.setTitle("ENTER CAR", for: .normal)
        vehicleButton.setTitleColor(.white, for: .normal)
        vehicleButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .black, width: .condensed)
        vehicleButton.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        vehicleButton.translatesAutoresizingMaskIntoConstraints = false
        vehicleButton.addTarget(self, action: #selector(toggleVehicle), for: .touchUpInside)
        view.addSubview(vehicleButton)
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            top.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            top.topAnchor.constraint(equalTo: view.topAnchor),
            top.heightAnchor.constraint(equalToConstant: 47),
            brand.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            brand.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            menu.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            menu.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            missions.trailingAnchor.constraint(equalTo: menu.leadingAnchor, constant: -24),
            missions.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            divider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            divider.topAnchor.constraint(equalTo: top.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 4),
            status.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            status.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),
            players.leadingAnchor.constraint(equalTo: status.leadingAnchor),
            players.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 4),
            vitals.leadingAnchor.constraint(equalTo: players.leadingAnchor),
            vitals.topAnchor.constraint(equalTo: players.bottomAnchor, constant: 4),
            objective.leadingAnchor.constraint(equalTo: status.leadingAnchor),
            objective.topAnchor.constraint(equalTo: vitals.bottomAnchor, constant: 5),
            objective.widthAnchor.constraint(lessThanOrEqualToConstant: 390),
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
            ,attackButton.trailingAnchor.constraint(equalTo: runButton.leadingAnchor, constant: -12),
            attackButton.centerYAnchor.constraint(equalTo: runButton.centerYAnchor),
            attackButton.widthAnchor.constraint(equalToConstant: 72),
            attackButton.heightAnchor.constraint(equalToConstant: 42)
            ,vehicleButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -30),
            vehicleButton.bottomAnchor.constraint(equalTo: look.topAnchor, constant: -12),
            vehicleButton.heightAnchor.constraint(equalToConstant: 35),
            vehicleButton.widthAnchor.constraint(equalToConstant: 108)
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
    @objc private func jump() { renderer?.jump() }

    @objc private func attack() {
        guard let renderer else { return }
        if network.health == 0 {
            network.respawn()
            if currentVehicle != nil {
                currentVehicle = nil
                renderer.exitVehicle()
                vehicleButton.setTitle("ENTER CAR", for: .normal)
            }
            renderer.teleport(x: 1480, y: -1738, z: 13)
            status.text = "RESPAWNED AT THE CITY CENTRE"
            return
        }
        guard currentVehicle == nil else { status.text = "EXIT THE VEHICLE TO FIGHT"; return }
        guard !network.passive else { status.text = "TURN OFF PASSIVE MODE TO FIGHT"; return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastAttackTime >= 0.35 else { return }
        lastAttackTime = now
        let origin = renderer.position
        let facing = SIMD2<Float>(sin(renderer.direction), cos(renderer.direction))
        let target = network.players.values.compactMap { player -> (RemotePlayer, Float)? in
            let offset = player.position - origin
            let distance = hypot(offset.x, offset.y)
            guard distance > 0.1, distance <= 3.5, abs(offset.z) <= 2.5,
                  simd_dot(SIMD2(offset.x, offset.y) / distance, facing) >= 0.25 else { return nil }
            return (player, distance)
        }.min { $0.1 < $1.1 }
        guard let target else { status.text = "NO PLAYER IN MELEE REACH"; return }
        network.sendMeleeHit(to: target.0.id)
        status.text = "FIST ATTACK ON \(target.0.name.uppercased())"
    }

    @objc private func openGameplay() {
        let panel = NativeGameplayPanel()
        panel.modalPresentationStyle = .overFullScreen
        panel.onAction = { [weak self] action, payload in self?.gameplay.perform(action, payload: payload) }
        panel.update(gameplay.state)
        gameplayPanel = panel
        present(panel, animated: true)
    }

    @objc private func toggleVehicle() {
        guard let renderer else { return }
        if currentVehicle != nil {
            if let currentVehicle { network.sendExit(renderer.position, heading: renderer.direction, vehicle: currentVehicle) }
            currentVehicle = nil
            renderer.exitVehicle()
            vehicleButton.setTitle("ENTER CAR", for: .normal)
            return
        }
        guard let nearest = network.vehicles.values.min(by: {
            simd_distance($0.position, renderer.position) < simd_distance($1.position, renderer.position)
        }), simd_distance(nearest.position, renderer.position) <= 8 else {
            status.text = "MOVE WITHIN 8 M OF A VEHICLE"
            return
        }
        network.requestEnter(nearest)
    }

    private func showObjective(_ state: [String: Any]) {
        let race = state["race"] as? [String: Any]
        let activeRace = race?["stage"] as? String == "running" && race?["joined"] as? Bool == true
        let job = state["job"] as? [String: Any]
        let exploration = state["exploration"] as? [String: Any]
        let target = activeRace ? race?["target"] as? [String: Any] :
            job?["target"] as? [String: Any] ?? exploration?["tracked"] as? [String: Any]
        let name = activeRace ? "MULTIPLAYER RACE" :
            (job?["name"] as? String ?? (target == nil ? "" : "EXPLORATION")).uppercased()
        let stage = activeRace ? "CHECKPOINT" : (job?["stage"] as? String ?? "").uppercased()
        if let target {
            let x = (target["x"] as? NSNumber)?.floatValue ?? 0
            let y = (target["y"] as? NSNumber)?.floatValue ?? 0
            let position = renderer?.position ?? SIMD3<Float>(1480, -1738, 13)
            let angle = atan2(x - position.x, y - position.y)
            var turn = angle - (renderer?.direction ?? 0)
            while turn > .pi { turn -= 2 * .pi }
            while turn < -.pi { turn += 2 * .pi }
            let arrow = turn < -.pi / 5 ? "◀" : turn > .pi / 5 ? "▶" : "▲"
            let distance = Int(hypot(x - position.x, y - position.y))
            objective.text = "\(name)  ·  \(stage)\n\(arrow) \(target["name"] as? String ?? "OBJECTIVE")  ·  \(distance) M"
        } else if job != nil {
            objective.text = "\(name)  ·  \(stage)\nOPEN JOBS FOR OBJECTIVE"
        } else { objective.text = "" }
    }

    private func maybeAdvanceCheckpoint(_ state: [String: Any]) {
        guard state["driving"] as? Bool == true else { return }
        if let race = state["race"] as? [String: Any],
           race["stage"] as? String == "running", race["joined"] as? Bool == true,
           let index = (race["index"] as? NSNumber)?.intValue,
           let total = (race["total"] as? NSNumber)?.intValue,
           let remaining = (race["remaining"] as? NSNumber)?.doubleValue,
           let radius = (race["radius"] as? NSNumber)?.doubleValue,
           remaining <= radius {
            let action = index == total ? "race.finish" : "race.checkpoint"
            let key = "race:\(race["started"] ?? ""): \(index):\(action)"
            let now = Date()
            if now.timeIntervalSince(lastAutomaticCheckpoint[key] ?? .distantPast) >= 5 {
                lastAutomaticCheckpoint[key] = now
                gameplay.perform(action)
            }
            return
        }
        guard
              let job = state["job"] as? [String: Any],
              job["mode"] as? String == "checkpoints",
              let index = (job["index"] as? NSNumber)?.intValue,
              let total = (job["total"] as? NSNumber)?.intValue,
              let remaining = (job["remaining"] as? NSNumber)?.doubleValue,
              let radius = (job["radius"] as? NSNumber)?.doubleValue,
              remaining <= radius else { return }
        let id = job["id"] as? String ?? "route"
        if ["patrol", "pizza"].contains(id),
           (job["vehicleId"] as? String) != (state["drivingVehicle"] as? String) { return }
        let action = index == total ? "job.complete" : "job.checkpoint"
        let key = "\(id):\(job["started"] ?? ""): \(index):\(action)"
        let now = Date()
        if now.timeIntervalSince(lastAutomaticCheckpoint[key] ?? .distantPast) < 5 { return }
        lastAutomaticCheckpoint[key] = now
        gameplay.perform(action)
    }

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
        var gamepadAttacking = false
        if let pad = GCController.controllers().compactMap(\.extendedGamepad).first {
            let lx = pad.leftThumbstick.xAxis.value, ly = pad.leftThumbstick.yAxis.value
            if abs(lx) + abs(ly) > 0.05 { forward = ly; sideways = lx }
            let rx = pad.rightThumbstick.xAxis.value
            if abs(rx) > 0.05 { steering = rx }
            gamepadRunning = pad.buttonA.isPressed
            gamepadJumping = pad.buttonB.isPressed
            gamepadAttacking = pad.rightTrigger.isPressed
            if pad.buttonX.isPressed && !lastVehicleButton { toggleVehicle() }
            if pad.buttonY.isPressed && !lastJobsButton && presentedViewController == nil { openGameplay() }
            lastVehicleButton = pad.buttonX.isPressed
            lastJobsButton = pad.buttonY.isPressed
        }
        if gamepadJumping && !lastJumpButton { renderer?.jump() }
        lastJumpButton = gamepadJumping
        if gamepadAttacking && !lastAttackButton { attack() }
        lastAttackButton = gamepadAttacking
        let walking = abs(forward) + abs(sideways) > 0.05
        let speed: Float = (run || gamepadRunning) ? 2 : 1
        if currentVehicle != nil { steering = max(-1, min(1, steering + sideways)) }
        renderer?.move(forward: forward * speed, sideways: currentVehicle == nil ? sideways * speed : 0,
                       turn: steering, delta: delta)
        if link.timestamp - lastNetwork > 0.2, let renderer {
            lastNetwork = link.timestamp
            network.sendPosition(renderer.position, heading: renderer.direction, moving: walking,
                                 running: speed > 1,
                                 vehicle: currentVehicle, speed: renderer.drivingSpeed,
                                 airborne: renderer.isAirborne)
        }
        if link.timestamp - lastGameplay > 1.5 {
            lastGameplay = link.timestamp
            gameplay.refresh()
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
