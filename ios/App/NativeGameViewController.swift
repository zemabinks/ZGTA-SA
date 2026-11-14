import UIKit
import GameController
import MetalKit

final class NativeGameViewController: UIViewController {
    private let server: ServerAddress
    private let network: NativeMultiplayerClient
    private let gameplay: NativeGameplayClient
    private let radio: NativeVehicleRadio
    private let renderer: NativeWorldRenderer?
    private let status = NativeTransientStatusLabel()
    private let players = UILabel()
    private let objective = UILabel()
    private let chatFeed = UILabel()
    private let gameHUD = NativeGameHUD()
    private let mapButton = UIButton(type: .custom)
    private let vehicleButton = NativeIconButton()
    private let radioButton = NativeIconButton()
    private let missionButton = NativeIconButton()
    private let attackButton = NativeIconButton()
    private let weaponButton = NativeIconButton()
    private let reloadButton = NativeIconButton()
    private let runButton = NativeIconButton()
    private let jumpButton = NativeIconButton()
    private let gasButton = NativeIconButton()
    private let brakeButton = NativeIconButton()
    private let ammoLabel = UILabel()
    private let vitals = UILabel()
    private let stick = VirtualStick()
    private let lookStick = VirtualStick()
    private weak var gameplayPanel: NativeGameplayPanel?
    private weak var chatPanel: NativeChatPanel?
    private var currentVehicle: RemoteVehicle?
    private var nearbyMissionAction: String?
    private var displayLink: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var lastNetwork: CFTimeInterval = 0
    private var lastGameplay: CFTimeInterval = 0
    private var lastHUD: CFTimeInterval = 0
    private var lastVehicleButton = false
    private var lastJobsButton = false
    private var lastAutomaticCheckpoint: [String: Date] = [:]
    private var run = false
    private var gasPressed = false
    private var brakePressed = false
    private var lastJumpButton = false
    private var lastAttackButton = false
    private var lastWeaponButton = false
    private var lastReloadButton = false
    private var lastAttackTime: CFTimeInterval = 0
    private var usingPistol = false
    private var magazine = 17
    private var reserve = 68

    init(server: ServerAddress) {
        self.server = server
        self.network = NativeMultiplayerClient(server: server)
        self.gameplay = NativeGameplayClient(server: server)
        self.radio = NativeVehicleRadio(server: server)
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
        network.onChat = { [weak self] lines in
            self?.chatFeed.text = lines.suffix(3).joined(separator: "\n")
            self?.chatFeed.isHidden = lines.isEmpty
            self?.chatPanel?.update(lines)
        }
        network.onVehicles = { [weak self] vehicles in self?.renderer?.remoteVehicles = vehicles }
        network.onEnter = { [weak self] id, okay in
            guard let self else { return }
            guard okay, let vehicle = self.network.vehicles[id] else {
                self.status.text = "VEHICLE ACCESS DENIED"
                return
            }
            self.currentVehicle = vehicle
            let kind = self.vehicleModelType(vehicle)
            self.renderer?.enter(vehicle, kind: kind)
            self.vehicleButton.setTitle("EXIT CAR", for: .normal)
            let modelName = self.vehicleModelName(vehicle)
            self.status.text = kind == "plane" ? "PILOTING \(modelName.uppercased()) · RIGHT STICK UP TO CLIMB" :
                kind == "helicopter" ? "PILOTING \(modelName.uppercased()) · GAS TO RISE" :
                "DRIVING \(modelName.uppercased())"
            self.gameHUD.updateVehicle(name: modelName, speed: 0)
            self.setDrivingControls(true)
            self.radio.resume()
        }
        network.onTeleport = { [weak self] point in self?.renderer?.teleport(x: point.x, y: point.y, z: point.z) }
        network.onVitals = { [weak self] health, armour in
            self?.vitals.text = "HEALTH \(health)  ·  ARMOUR \(armour)"
            self?.gameHUD.updateVitals(health: health, armour: armour)
            self?.attackButton.setTitle(health == 0 ? "RESPAWN" :
                                          (self?.usingPistol == true ? "FIRE" : "HIT"), for: .normal)
        }
        gameplay.onState = { [weak self] state in
            guard let self else { return }
            self.network.syncVitals(from: state)
            if let amount = state["cash"] as? NSNumber { self.gameHUD.updateCash(amount.intValue) }
            if let wanted = state["wanted"] as? NSNumber { self.gameHUD.updateWanted(wanted.intValue) }
            self.gameplayPanel?.update(state)
            self.showObjective(state)
            self.updateRadarTarget(state)
            self.updateNearbyMissionAction(state)
            self.maybeAdvanceCheckpoint(state)
        }
        gameplay.onResult = { [weak self] result in self?.status.text = result.uppercased() }
        radio.onStatus = { [weak self] message in self?.status.text = message }
        network.connect()
        gameplay.refresh()
        gameHUD.radar.loadMap(server: server)
        gameHUD.loadFont(server: server)
        gameHUD.loadWeaponIcon(server: server, weapon: 0)
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
        radio.stop()
    }

    private func installHUD() {
        let menu = button("MENU", action: #selector(close))
        styleControl(menu, icon: "Touch_pause", fallback: "pause.fill", accessibility: "Pause and return to menu")
        view.addSubview(menu)
        let missions = button("JOBS / GARAGE", action: #selector(openGameplay))
        styleControl(missions, icon: nil, fallback: "briefcase.fill", accessibility: "Jobs and garage")
        view.addSubview(missions)
        let chat = button("CHAT", action: #selector(openChat))
        styleControl(chat, icon: nil, fallback: "bubble.left.and.bubble.right.fill", accessibility: "Open multiplayer chat")
        view.addSubview(chat)
        status.text = "LOADING LOCAL CITY"
        status.textColor = .white
        status.font = .systemFont(ofSize: 12, weight: .bold, width: .condensed)
        status.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)
        players.text = "CONNECTING TO MULTIPLAYER"
        players.textColor = .white
        players.font = .systemFont(ofSize: 10, weight: .semibold, width: .condensed)
        players.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        players.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(players)
        objective.textColor = .white
        objective.font = .systemFont(ofSize: 11, weight: .bold, width: .condensed)
        objective.numberOfLines = 2
        objective.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        objective.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(objective)
        chatFeed.textColor = .white
        chatFeed.font = .systemFont(ofSize: 11, weight: .semibold, width: .condensed)
        chatFeed.numberOfLines = 3
        chatFeed.lineBreakMode = .byTruncatingTail
        chatFeed.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        chatFeed.translatesAutoresizingMaskIntoConstraints = false
        chatFeed.isHidden = true
        view.addSubview(chatFeed)
        gameHUD.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(gameHUD)
        mapButton.translatesAutoresizingMaskIntoConstraints = false
        mapButton.accessibilityLabel = "Open city map"
        mapButton.addTarget(self, action: #selector(openMap), for: .touchUpInside)
        view.addSubview(mapButton)
        stick.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stick)
        let look = lookStick
        look.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(look)
        runButton.setTitle("RUN", for: .normal)
        runButton.addTarget(self, action: #selector(toggleRun), for: .touchUpInside)
        styleControl(runButton, icon: nil, fallback: "figure.run", accessibility: "Toggle sprint")
        runButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(runButton)
        jumpButton.setTitle("JUMP", for: .normal)
        jumpButton.translatesAutoresizingMaskIntoConstraints = false
        jumpButton.addTarget(self, action: #selector(jump), for: .touchUpInside)
        styleControl(jumpButton, icon: "Touch_jump", fallback: "figure.run", accessibility: "Jump")
        view.addSubview(jumpButton)
        gasButton.setTitle("GAS", for: .normal)
        gasButton.translatesAutoresizingMaskIntoConstraints = false
        styleControl(gasButton, icon: "Touch_gas", fallback: "pedal.accelerator.fill",
                     accessibility: "Hold to accelerate")
        gasButton.addTarget(self, action: #selector(pressGas), for: .touchDown)
        gasButton.addTarget(self, action: #selector(releaseGas),
                            for: [.touchUpInside, .touchUpOutside, .touchCancel])
        gasButton.isHidden = true
        view.addSubview(gasButton)
        brakeButton.setTitle("BRAKE", for: .normal)
        brakeButton.translatesAutoresizingMaskIntoConstraints = false
        styleControl(brakeButton, icon: nil, fallback: "minus.circle.fill",
                     accessibility: "Hold to brake or reverse")
        brakeButton.addTarget(self, action: #selector(pressBrake), for: .touchDown)
        brakeButton.addTarget(self, action: #selector(releaseBrake),
                              for: [.touchUpInside, .touchUpOutside, .touchCancel])
        brakeButton.isHidden = true
        view.addSubview(brakeButton)
        attackButton.setTitle("HIT", for: .normal)
        attackButton.setTitleColor(.white, for: .normal)
        attackButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .black, width: .condensed)
        styleControl(attackButton, icon: nil, fallback: "hand.raised.fingers.spread.fill", accessibility: "Hit")
        attackButton.translatesAutoresizingMaskIntoConstraints = false
        attackButton.addTarget(self, action: #selector(attack), for: .touchUpInside)
        view.addSubview(attackButton)
        for (control, title, action) in [(weaponButton, "PISTOL", #selector(toggleWeapon)),
                                         (reloadButton, "RELOAD", #selector(reload))] {
            control.setTitle(title, for: .normal)
            control.setTitleColor(.white, for: .normal)
            control.titleLabel?.font = .systemFont(ofSize: 15, weight: .black, width: .condensed)
            styleControl(control, icon: control === weaponButton ? "Touch_weapons" : "Touch_reload",
                         fallback: control === weaponButton ? "circle.grid.2x2.fill" : "arrow.clockwise",
                         accessibility: title)
            control.translatesAutoresizingMaskIntoConstraints = false
            control.addTarget(self, action: action, for: .touchUpInside)
            view.addSubview(control)
        }
        updateWeaponHUD()
        vehicleButton.setTitle("ENTER CAR", for: .normal)
        vehicleButton.setTitleColor(.white, for: .normal)
        vehicleButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .black, width: .condensed)
        styleControl(vehicleButton, icon: "Touch_enter_exit", fallback: "car.side.fill", accessibility: "Enter vehicle")
        vehicleButton.translatesAutoresizingMaskIntoConstraints = false
        vehicleButton.addTarget(self, action: #selector(toggleVehicle), for: .touchUpInside)
        vehicleButton.isHidden = true
        view.addSubview(vehicleButton)
        radioButton.setTitle("RADIO OFF", for: .normal)
        radioButton.setTitleColor(.white, for: .normal)
        radioButton.titleLabel?.font = .systemFont(ofSize: 12, weight: .black, width: .condensed)
        radioButton.titleLabel?.adjustsFontSizeToFitWidth = true
        styleControl(radioButton, icon: nil, fallback: "radio.fill", accessibility: "Change radio station")
        radioButton.translatesAutoresizingMaskIntoConstraints = false
        radioButton.isHidden = true
        radioButton.addTarget(self, action: #selector(nextRadioStation), for: .touchUpInside)
        view.addSubview(radioButton)
        missionButton.setTitle("OBJECTIVE", for: .normal)
        missionButton.translatesAutoresizingMaskIntoConstraints = false
        styleControl(missionButton, icon: nil, fallback: "hand.point.up.left.fill",
                     accessibility: "Use nearby mission objective")
        missionButton.addTarget(self, action: #selector(performNearbyMissionAction), for: .touchUpInside)
        missionButton.isHidden = true
        view.addSubview(missionButton)
        NSLayoutConstraint.activate([
            menu.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            menu.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            menu.widthAnchor.constraint(equalToConstant: 42),
            menu.heightAnchor.constraint(equalTo: menu.widthAnchor),
            missions.trailingAnchor.constraint(equalTo: menu.leadingAnchor, constant: -8),
            missions.centerYAnchor.constraint(equalTo: menu.centerYAnchor),
            missions.widthAnchor.constraint(equalToConstant: 42),
            missions.heightAnchor.constraint(equalTo: missions.widthAnchor),
            chat.trailingAnchor.constraint(equalTo: missions.leadingAnchor, constant: -8),
            chat.centerYAnchor.constraint(equalTo: menu.centerYAnchor),
            chat.widthAnchor.constraint(equalToConstant: 42),
            chat.heightAnchor.constraint(equalTo: chat.widthAnchor),
            status.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            status.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 9),
            players.leadingAnchor.constraint(equalTo: status.leadingAnchor),
            players.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 4),
            objective.leadingAnchor.constraint(equalTo: status.leadingAnchor),
            objective.topAnchor.constraint(equalTo: players.bottomAnchor, constant: 5),
            objective.widthAnchor.constraint(lessThanOrEqualToConstant: 390),
            chatFeed.leadingAnchor.constraint(equalTo: status.leadingAnchor),
            chatFeed.topAnchor.constraint(equalTo: objective.bottomAnchor, constant: 5),
            chatFeed.widthAnchor.constraint(lessThanOrEqualToConstant: 390),
            gameHUD.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            gameHUD.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            gameHUD.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            gameHUD.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mapButton.leadingAnchor.constraint(equalTo: gameHUD.radar.leadingAnchor),
            mapButton.topAnchor.constraint(equalTo: gameHUD.radar.topAnchor),
            mapButton.widthAnchor.constraint(equalTo: gameHUD.radar.widthAnchor),
            mapButton.heightAnchor.constraint(equalTo: gameHUD.radar.heightAnchor),
            stick.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            stick.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
            stick.widthAnchor.constraint(equalToConstant: 190),
            stick.heightAnchor.constraint(equalToConstant: 155),
            look.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            look.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
            look.widthAnchor.constraint(equalToConstant: 150),
            look.heightAnchor.constraint(equalToConstant: 155),
            runButton.trailingAnchor.constraint(equalTo: look.leadingAnchor, constant: -14),
            runButton.bottomAnchor.constraint(equalTo: look.centerYAnchor, constant: -5),
            runButton.widthAnchor.constraint(equalToConstant: 48),
            runButton.heightAnchor.constraint(equalTo: runButton.widthAnchor),
            jumpButton.trailingAnchor.constraint(equalTo: look.leadingAnchor, constant: -14),
            jumpButton.topAnchor.constraint(equalTo: look.centerYAnchor, constant: 5),
            jumpButton.widthAnchor.constraint(equalToConstant: 48),
            jumpButton.heightAnchor.constraint(equalTo: jumpButton.widthAnchor)
            ,gasButton.trailingAnchor.constraint(equalTo: runButton.trailingAnchor),
            gasButton.centerYAnchor.constraint(equalTo: runButton.centerYAnchor),
            gasButton.widthAnchor.constraint(equalToConstant: 48),
            gasButton.heightAnchor.constraint(equalTo: gasButton.widthAnchor),
            brakeButton.trailingAnchor.constraint(equalTo: jumpButton.trailingAnchor),
            brakeButton.centerYAnchor.constraint(equalTo: jumpButton.centerYAnchor),
            brakeButton.widthAnchor.constraint(equalToConstant: 48),
            brakeButton.heightAnchor.constraint(equalTo: brakeButton.widthAnchor)
            ,attackButton.trailingAnchor.constraint(equalTo: runButton.leadingAnchor, constant: -12),
            attackButton.centerYAnchor.constraint(equalTo: runButton.centerYAnchor),
            attackButton.widthAnchor.constraint(equalToConstant: 48),
            attackButton.heightAnchor.constraint(equalTo: attackButton.widthAnchor)
            ,weaponButton.trailingAnchor.constraint(equalTo: attackButton.trailingAnchor),
            weaponButton.bottomAnchor.constraint(equalTo: attackButton.topAnchor, constant: -7),
            weaponButton.widthAnchor.constraint(equalToConstant: 48),
            weaponButton.heightAnchor.constraint(equalTo: weaponButton.widthAnchor),
            reloadButton.trailingAnchor.constraint(equalTo: weaponButton.leadingAnchor, constant: -7),
            reloadButton.centerYAnchor.constraint(equalTo: weaponButton.centerYAnchor),
            reloadButton.widthAnchor.constraint(equalToConstant: 48),
            reloadButton.heightAnchor.constraint(equalTo: reloadButton.widthAnchor)
            ,vehicleButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            vehicleButton.bottomAnchor.constraint(equalTo: look.topAnchor, constant: 46),
            vehicleButton.heightAnchor.constraint(equalToConstant: 48),
            vehicleButton.widthAnchor.constraint(equalTo: vehicleButton.heightAnchor),
            radioButton.trailingAnchor.constraint(equalTo: vehicleButton.leadingAnchor, constant: -8),
            radioButton.centerYAnchor.constraint(equalTo: vehicleButton.centerYAnchor),
            radioButton.heightAnchor.constraint(equalToConstant: 48),
            radioButton.widthAnchor.constraint(equalTo: radioButton.heightAnchor),
            missionButton.trailingAnchor.constraint(equalTo: vehicleButton.leadingAnchor, constant: -8),
            missionButton.bottomAnchor.constraint(equalTo: vehicleButton.topAnchor, constant: -8),
            missionButton.widthAnchor.constraint(equalToConstant: 48),
            missionButton.heightAnchor.constraint(equalTo: missionButton.widthAnchor)
        ])
    }

    private func styleControl(_ button: UIButton, icon name: String?, fallback: String,
                              accessibility: String) {
        let icon = name.flatMap { UIImage(named: $0) }
        if let icon {
            let scaled = UIGraphicsImageRenderer(size: CGSize(width: 26, height: 26)).image { _ in
                icon.draw(in: CGRect(x: 0, y: 0, width: 26, height: 26))
            }
            button.setImage(scaled.withRenderingMode(.alwaysTemplate), for: .normal)
        } else {
            button.setImage(UIImage(systemName: fallback,
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 23, weight: .bold)),
                            for: .normal)
        }
        button.accessibilityLabel = accessibility
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        button.layer.cornerRadius = 24
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.25
        button.layer.shadowRadius = 5
        button.imageView?.contentMode = .scaleAspectFit
    }

    private func label(_ text: String, size: CGFloat, bold: Bool) -> UILabel {
        let result = UILabel()
        result.text = text
        result.textColor = .white
        result.font = .systemFont(ofSize: size, weight: bold ? .black : .regular, width: .condensed)
        result.translatesAutoresizingMaskIntoConstraints = false
        return result
    }

    private func button(_ text: String, action: Selector) -> NativeIconButton {
        let result = NativeIconButton()
        result.setTitle(text, for: .normal)
        result.setTitleColor(.white, for: .normal)
        result.titleLabel?.font = .systemFont(ofSize: 18, weight: .black, width: .condensed)
        result.translatesAutoresizingMaskIntoConstraints = false
        result.addTarget(self, action: action, for: .touchUpInside)
        return result
    }

    @objc private func close() { dismiss(animated: true) }
    @objc private func openChat() {
        guard presentedViewController == nil else { return }
        let panel = NativeChatPanel()
        panel.modalPresentationStyle = .overFullScreen
        panel.onSend = { [weak self] line in self?.network.sendChat(line) }
        panel.update(network.chatMessages)
        chatPanel = panel
        present(panel, animated: true)
    }
    @objc private func openMap() {
        guard presentedViewController == nil else { return }
        let map = NativeCityMapViewController(image: gameHUD.radar.mapImage,
                                              position: gameHUD.radar.position,
                                              players: gameHUD.radar.players,
                                              vehicles: gameHUD.radar.vehicles,
                                              target: gameHUD.radar.target)
        map.modalPresentationStyle = .overFullScreen
        present(map, animated: true)
    }
    @objc private func controllerChanged() { status.text = GCController.controllers().isEmpty ? "TOUCH CONTROLS ACTIVE" : "CONTROLLER CONNECTED" }
    @objc private func toggleRun() {
        run.toggle()
        runButton.layer.borderColor = (run ? UIColor(red: 0.365, green: 0.714, blue: 0.898, alpha: 1) :
                                       UIColor.white.withAlphaComponent(0.3)).cgColor
        runButton.layer.borderWidth = run ? 2.5 : 1
    }
    @objc private func jump() { renderer?.jump() }
    @objc private func pressGas() { gasPressed = true }
    @objc private func releaseGas() { gasPressed = false }
    @objc private func pressBrake() { brakePressed = true }
    @objc private func releaseBrake() { brakePressed = false }
    @objc private func nextRadioStation() {
        guard currentVehicle != nil else { return }
        radio.next()
        radioButton.setTitle(radio.stationName, for: .normal)
    }
    @objc private func performNearbyMissionAction() {
        guard let nearbyMissionAction else { return }
        missionButton.isHidden = true
        gameplay.perform(nearbyMissionAction)
    }

    private func updateNearbyMissionAction(_ state: [String: Any]) {
        nearbyMissionAction = nil
        guard let job = state["job"] as? [String: Any],
              let remaining = (job["remaining"] as? NSNumber)?.doubleValue,
              remaining <= ((job["radius"] as? NSNumber)?.doubleValue ?? 0) else {
            missionButton.isHidden = true
            return
        }
        let mode = job["mode"] as? String ?? "distance"
        let onFoot = state["onFoot"] as? Bool == true
        let driving = state["driving"] as? Bool == true
        let marked = (job["vehicleId"] as? String) == (state["drivingVehicle"] as? String)
        let stage = job["stage"] as? String ?? ""
        let id = job["id"] as? String ?? ""
        var label: String?
        switch mode {
        case "route":
            let ready = id == "courier" ? onFoot || stage == "delivery" : driving && marked
            if ready {
                nearbyMissionAction = stage == "pickup" ? "job.pickup" : "job.complete"
                label = stage == "pickup" ? "Collect or load mission item" : "Deliver mission item"
            }
        case "fire":
            if stage == "respond", driving && marked {
                nearbyMissionAction = "job.respond"
                label = "Arrive at fire call"
            } else if stage == "extinguish" {
                nearbyMissionAction = "job.extinguish"
                label = "Extinguish fire"
            } else if stage == "rescue", onFoot {
                nearbyMissionAction = "job.complete"
                label = "Rescue person"
            }
        case "heist":
            if stage == "plan", onFoot {
                nearbyMissionAction = "heist.rob"
                label = "Collect heist bag"
            } else if stage == "escape", driving && marked,
                      (state["wanted"] as? NSNumber)?.intValue == 0 {
                nearbyMissionAction = "job.complete"
                label = "Deliver heist bag"
            }
        case "flight":
            if stage == "landing", driving && marked, job["landingReady"] as? Bool == true {
                nearbyMissionAction = "job.complete"
                label = "Finish flight"
            }
        case "distance":
            nearbyMissionAction = "job.complete"
            label = "Complete mission"
        default: break
        }
        missionButton.accessibilityLabel = label
        missionButton.isHidden = nearbyMissionAction == nil
    }

    private func updateWeaponHUD() {
        weaponButton.setTitle(usingPistol ? "FISTS" : "PISTOL", for: .normal)
        reloadButton.isHidden = currentVehicle != nil || !usingPistol || magazine >= 17 || reserve == 0
        ammoLabel.text = usingPistol ? "COLT .45  ·  \(magazine) / \(reserve)" : "FISTS EQUIPPED"
        gameHUD.updateWeapon(pistol: usingPistol, magazine: magazine, reserve: reserve)
        gameHUD.loadWeaponIcon(server: server, weapon: usingPistol ? 22 : 0)
        attackButton.setTitle(network.health == 0 ? "RESPAWN" :
                              (usingPistol ? "FIRE" : "HIT"), for: .normal)
        styleControl(attackButton, icon: usingPistol ? "Touch_fire" : nil,
                     fallback: usingPistol ? "scope" : "hand.raised.fingers.spread.fill",
                     accessibility: network.health == 0 ? "Respawn" : usingPistol ? "Fire" : "Hit")
    }

    private func setDrivingControls(_ driving: Bool) {
        vehicleButton.isHidden = false
        radioButton.isHidden = !driving
        runButton.isHidden = driving
        jumpButton.isHidden = driving
        gasButton.isHidden = !driving
        brakeButton.isHidden = !driving
        let helicopter = driving && renderer?.vehicleKind == "helicopter"
        styleControl(gasButton, icon: helicopter ? nil : "Touch_gas",
                     fallback: helicopter ? "arrow.up" : "pedal.accelerator.fill",
                     accessibility: helicopter ? "Climb" : "Accelerate")
        styleControl(brakeButton, icon: nil,
                     fallback: helicopter ? "arrow.down" : "minus.circle.fill",
                     accessibility: helicopter ? "Descend" : "Brake or reverse")
        weaponButton.isHidden = driving
        attackButton.isHidden = driving
        reloadButton.isHidden = driving || !usingPistol || magazine >= 17 || reserve == 0
        if !driving { gasPressed = false; brakePressed = false }
    }

    private func vehicleModelName(_ vehicle: RemoteVehicle) -> String {
        let key = String(vehicle.code.split(separator: ".").first ?? "")
        if let name = renderer?.vehicleName(model: key) { return name }
        guard let model = Int(key),
              let catalog = gameplay.state["catalog"] as? [String: Any],
              let cars = catalog["cars"] as? [[String: Any]],
              let entry = cars.first(where: { ($0["model"] as? NSNumber)?.intValue == model }) else {
            return "VEHICLE \(key)"
        }
        return entry["name"] as? String ?? "VEHICLE \(key)"
    }

    private func vehicleModelType(_ vehicle: RemoteVehicle) -> String {
        let key = String(vehicle.code.split(separator: ".").first ?? "")
        if let kind = renderer?.vehicleType(model: key) { return kind }
        guard let model = Int(key),
              let catalog = gameplay.state["catalog"] as? [String: Any],
              let cars = catalog["cars"] as? [[String: Any]],
              let entry = cars.first(where: { ($0["model"] as? NSNumber)?.intValue == model }),
              let type = entry["type"] as? String else { return "car" }
        return type
    }

    @objc private func toggleWeapon() {
        guard currentVehicle == nil else { status.text = "EXIT THE VEHICLE TO EQUIP"; return }
        usingPistol.toggle()
        renderer?.equippedWeapon = usingPistol ? 22 : 0
        renderer?.clearAction()
        updateWeaponHUD()
        status.text = usingPistol ? "COLT .45 EQUIPPED" : "FISTS EQUIPPED"
    }

    @objc private func reload() {
        guard usingPistol, magazine < 17, reserve > 0 else { return }
        let count = min(17 - magazine, reserve)
        magazine += count
        reserve -= count
        updateWeaponHUD()
        status.text = "COLT .45 RELOADED"
    }

    @objc private func attack() {
        guard let renderer else { return }
        if network.health == 0 {
            network.respawn()
            if currentVehicle != nil {
                currentVehicle = nil
                renderer.exitVehicle()
                vehicleButton.setTitle("ENTER CAR", for: .normal)
                setDrivingControls(false)
                radio.stop()
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
        if usingPistol {
            guard magazine > 0 else { status.text = "EMPTY MAGAZINE — RELOAD"; return }
            magazine -= 1
            updateWeaponHUD()
            renderer.firePistol()
            let origin = renderer.position + SIMD3<Float>(0, 0, 1.35)
            let facing = SIMD2<Float>(sin(renderer.direction), cos(renderer.direction))
            let target = network.players.values.compactMap { player -> (RemotePlayer, Float)? in
                let offset = player.position - renderer.position
                let distance = hypot(offset.x, offset.y)
                guard distance > 0.5, distance <= 60, abs(offset.z) <= 6,
                      simd_dot(SIMD2(offset.x, offset.y) / distance, facing) >= 0.86,
                      renderer.hasClearShot(to: player.position) else { return nil }
                return (player, distance)
            }.min { $0.1 < $1.1 }
            let hit = target.map { $0.0.position + SIMD3<Float>(0, 0, 1.15) } ??
                origin + SIMD3<Float>(facing.x * 60, facing.y * 60, 0)
            network.sendPistolShot(from: origin, to: hit, player: target?.0.id)
            status.text = target.map { "COLT .45 FIRED AT \($0.0.name.uppercased())" } ??
                "COLT .45 FIRED"
            return
        }
        renderer.performFistAttack()
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
            if let currentVehicle {
                network.sendExit(renderer.position, heading: renderer.direction,
                                 vehicle: currentVehicle, vehicleHealth: renderer.vehicleHealth)
            }
            currentVehicle = nil
            renderer.exitVehicle()
            vehicleButton.setTitle("ENTER CAR", for: .normal)
            gameHUD.updateVehicle(name: nil, speed: 0)
            setDrivingControls(false)
            radio.stop()
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
            var turn = angle - (renderer?.cameraDirection ?? 0)
            while turn > .pi { turn -= 2 * .pi }
            while turn < -.pi { turn += 2 * .pi }
            let arrow = turn < -.pi / 5 ? "◀" : turn > .pi / 5 ? "▶" : "▲"
            let distance = Int(hypot(x - position.x, y - position.y))
            objective.text = "\(name)  ·  \(stage)\n\(arrow) \(target["name"] as? String ?? "OBJECTIVE")  ·  \(distance) M"
        } else if job != nil {
            objective.text = "\(name)  ·  \(stage)\nOPEN JOBS FOR OBJECTIVE"
        } else { objective.text = "" }
    }

    private func updateRadarTarget(_ state: [String: Any]) {
        let race = state["race"] as? [String: Any]
        let activeRace = race?["stage"] as? String == "running" && race?["joined"] as? Bool == true
        let job = state["job"] as? [String: Any]
        let exploration = state["exploration"] as? [String: Any]
        let target = activeRace ? race?["target"] as? [String: Any] :
            job?["target"] as? [String: Any] ?? exploration?["tracked"] as? [String: Any]
        if let x = (target?["x"] as? NSNumber)?.floatValue,
           let y = (target?["y"] as? NSNumber)?.floatValue {
            gameHUD.radar.target = SIMD2(x, y)
            renderer?.objective = SIMD2(x, y)
        } else {
            gameHUD.radar.target = nil
            renderer?.objective = nil
        }
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

    @objc private func tick(_ link: CADisplayLink) {
        let delta = lastTime == 0 ? Float(1.0 / 60) : Float(min(0.05, link.timestamp - lastTime))
        lastTime = link.timestamp
        var forward = Float(-stick.value.y)
        var sideways = Float(stick.value.x)
        var steering = Float(lookStick.value.x)
        var lookVertical = Float(-lookStick.value.y)
        var lift: Float = 0
        let helicopter = currentVehicle != nil && renderer?.vehicleKind == "helicopter"
        var gamepadRunning = false
        var gamepadJumping = false
        var gamepadAttacking = false
        var gamepadWeapon = false
        var gamepadReload = false
        if let pad = GCController.controllers().compactMap(\.extendedGamepad).first {
            let lx = pad.leftThumbstick.xAxis.value, ly = pad.leftThumbstick.yAxis.value
            if abs(lx) + abs(ly) > 0.05 { forward = ly; sideways = lx }
            let rx = pad.rightThumbstick.xAxis.value
            if abs(rx) > 0.05 { steering = rx }
            let ry = pad.rightThumbstick.yAxis.value
            if abs(ry) > 0.05 { lookVertical = ry }
            gamepadRunning = pad.buttonA.isPressed
            gamepadJumping = pad.buttonB.isPressed
            if currentVehicle != nil {
                let throttle = pad.rightTrigger.value
                let braking = pad.leftTrigger.value
                if helicopter {
                    if throttle > 0.05 || braking > 0.05 { lift = throttle - braking }
                } else {
                    steering = abs(lx) > 0.05 ? lx : steering
                    sideways = 0
                    if throttle > 0.05 || braking > 0.05 { forward = throttle - braking }
                }
            } else {
                gamepadAttacking = pad.rightTrigger.isPressed
            }
            gamepadWeapon = pad.leftShoulder.isPressed
            gamepadReload = pad.rightShoulder.isPressed
            if pad.buttonX.isPressed && !lastVehicleButton { toggleVehicle() }
            if pad.buttonY.isPressed && !lastJobsButton && presentedViewController == nil { openGameplay() }
            lastVehicleButton = pad.buttonX.isPressed
            lastJobsButton = pad.buttonY.isPressed
        }
        if gamepadJumping && !lastJumpButton { renderer?.jump() }
        lastJumpButton = gamepadJumping
        if gamepadAttacking && !lastAttackButton { attack() }
        lastAttackButton = gamepadAttacking
        if gamepadWeapon && !lastWeaponButton { toggleWeapon() }
        lastWeaponButton = gamepadWeapon
        if gamepadReload && !lastReloadButton { reload() }
        lastReloadButton = gamepadReload
        if currentVehicle != nil {
            if helicopter {
                if gasPressed { lift = 1 }
                if brakePressed { lift = -1 }
            } else {
                if gasPressed { forward = 1 }
                if brakePressed { forward = -1 }
            }
        }
        let walking = abs(forward) + abs(sideways) > 0.05
        let running = run || gamepadRunning
        if currentVehicle != nil && !helicopter { steering = max(-1, min(1, steering + sideways)) }
        renderer?.move(forward: forward, sideways: currentVehicle == nil || helicopter ? sideways : 0,
                       turn: steering, delta: delta, running: running,
                       lookVertical: lookVertical, lift: lift)
        if link.timestamp - lastHUD > 0.1, let renderer {
            lastHUD = link.timestamp
            status.expireIfNeeded()
            gameHUD.radar.position = SIMD2(renderer.position.x, renderer.position.y)
            gameHUD.radar.heading = renderer.direction
            gameHUD.radar.players = network.players.values.map { SIMD2($0.position.x, $0.position.y) }
            gameHUD.radar.vehicles = network.vehicles.values.map { SIMD2($0.position.x, $0.position.y) }
            gameHUD.updateVehicle(name: currentVehicle.map(vehicleModelName), speed: renderer.drivingSpeed)
            gameHUD.updateClock()
            if currentVehicle == nil {
                vehicleButton.isHidden = !network.vehicles.values.contains {
                    simd_distance($0.position, renderer.position) <= 8
                }
            }
        }
        if link.timestamp - lastNetwork > 0.2, let renderer {
            lastNetwork = link.timestamp
            network.sendPosition(renderer.position, heading: renderer.direction, moving: walking,
                                 running: running,
                                 vehicle: currentVehicle, speed: renderer.drivingSpeed,
                                 steer: renderer.steeringInput, pitch: renderer.vehicleNose,
                                 vehicleHealth: renderer.vehicleHealth,
                                 airborne: renderer.isAirborne, weapon: usingPistol ? 22 : 0,
                                 firing: renderer.isFiring)
        }
        if link.timestamp - lastGameplay > 1.5 {
            lastGameplay = link.timestamp
            gameplay.refresh()
        }
    }
}

private final class NativeTransientStatusLabel: UILabel {
    private var expiresAt: CFTimeInterval = 0

    override var text: String? {
        didSet {
            guard text != oldValue else { return }
            alpha = 1
            expiresAt = ProcessInfo.processInfo.systemUptime + 6
        }
    }

    func expireIfNeeded() {
        if ProcessInfo.processInfo.systemUptime >= expiresAt { alpha = 0 }
    }
}

private final class NativeIconButton: UIButton {
    override func setTitle(_ title: String?, for state: UIControl.State) {
        if state == .normal { accessibilityLabel = title }
        super.setTitle(nil, for: state)
    }
}

private final class VirtualStick: UIView {
    private let ring = UIView()
    private let knob = UIView()
    private(set) var value = CGPoint.zero
    private var origin = CGPoint.zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        ring.bounds.size = CGSize(width: 110, height: 110)
        ring.layer.cornerRadius = 55
        ring.layer.borderWidth = 2
        ring.layer.borderColor = UIColor.white.withAlphaComponent(0.35).cgColor
        ring.backgroundColor = UIColor.black.withAlphaComponent(0.12)
        ring.isUserInteractionEnabled = false
        ring.isHidden = true
        addSubview(ring)
        knob.bounds.size = CGSize(width: 42, height: 42)
        knob.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        knob.layer.cornerRadius = 21
        knob.isUserInteractionEnabled = false
        knob.isHidden = true
        addSubview(knob)
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        ring.center = origin
        knob.center = CGPoint(x: origin.x + value.x * 44,
                              y: origin.y + value.y * 44)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let point = touches.first?.location(in: self) else { return }
        origin = point
        value = .zero
        ring.isHidden = false
        knob.isHidden = false
        setNeedsLayout()
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(touches.first?.location(in: self)) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { update(nil) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { update(nil) }

    private func update(_ point: CGPoint?) {
        if let point {
            let dx = point.x - origin.x, dy = point.y - origin.y
            let length = max(1, hypot(dx, dy))
            let radius: CGFloat = 44
            let scale = min(1, radius / length)
            value = CGPoint(x: dx * scale / radius, y: dy * scale / radius)
        } else {
            value = .zero
            ring.isHidden = true
            knob.isHidden = true
        }
        setNeedsLayout()
    }
}
