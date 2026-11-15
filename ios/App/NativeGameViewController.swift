import UIKit
import GameController
import MetalKit

final class NativeGameViewController: UIViewController {
    private let server: ServerAddress
    private let network: NativeMultiplayerClient
    private let gameplay: NativeGameplayClient
    private let radio: NativeVehicleRadio
    private let weapons: NativeWeaponState
    private let audio: NativeGameAudio
    private let renderer: NativeWorldRenderer?
    private let status = NativeTransientStatusLabel()
    private let players = NativeHUDTextLabel()
    private let objective = NativeHUDTextLabel()
    private let chatFeed = NativeHUDTextLabel()
    private let gameHUD = NativeGameHUD()
    private let mapButton = UIButton(type: .custom)
    private let vehicleButton = NativeIconButton()
    private let radioButton = NativeIconButton()
    private let missionButton = NativeIconButton()
    private let attackButton = NativeIconButton()
    private let weaponButton = NativeIconButton()
    private let reloadButton = NativeIconButton()
    private let aimButton = NativeIconButton()
    private let crouchButton = NativeIconButton()
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
    private weak var weaponPanel: NativeWeaponShopPanel?
    private var currentVehicle: RemoteVehicle?
    private var nearbyMissionAction: String?
    private var nearbyMissionPayload: [String:Any] = [:]
    private var displayLink: CADisplayLink?
    private var frameClock = NativeGameFrameClock()
    private var controllerGate = NativeControllerInputGate()
    private var applicationActive = true
    private var inputWasAvailable = false
    private var lastNetwork: CFTimeInterval = 0
    private var lastGameplay: CFTimeInterval = 0
    private var lastHUD: CFTimeInterval = 0
    private var lastVehicleButton = false
    private var lastJobsButton = false
    private var lastAutomaticCheckpoint: [String: Date] = [:]
    private var run = false
    private var gasPressed = false
    private var brakePressed = false
    private var handbrakePressed = false
    private var flightBrakePressed=false
    private var hornPressed = false
    private var nozzleUpPressed = false
    private var nozzleDownPressed = false
    private var lastGearButton = false
    private var lastLightsButton = false
    private var lastJumpButton = false
    private var lastAttackButton = false
    private var lastWeaponButton = false
    private var lastReloadButton = false
    private var lastAttackTime: CFTimeInterval = 0
    private var usingPistol: Bool { weapons.current.isGun }
    private var magazine: Int { weapons.rounds }
    private var reserve: Int { weapons.reserve }
    private var aiming = false
    private var firePressed = false
    private var lastCrouchButton = false
    private var lastGamepadAim = false
    private var lastCameraButton = false
    private var previousAudioPosition: SIMD3<Float>?
    private var contextActionShown:String?
    private var autoReloadWeapon:Int?
    private var heldKeys: Set<UIKeyboardHIDUsage> = []
    private var acceptsHeldInput: Bool { applicationActive && viewIfLoaded?.window != nil && presentedViewController == nil }
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applicationActive = UIApplication.shared.applicationState == .active
        becomeFirstResponder()
    }
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        resetControls()
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange(); stick.reset(); lookStick.reset()
    }
    @objc private func applicationResigned() {
        applicationActive = false; frameClock.reset();renderer?.resetDisplayClock(); resetControls()
    }
    @objc private func applicationReturned() {
        applicationActive = true; frameClock.reset();renderer?.resetDisplayClock(); resetControls()
    }
    private func resetControls() {
        heldKeys.removeAll(); stick.reset(); lookStick.reset(); controllerGate.reset()
        run = false; gasPressed = false; brakePressed = false; handbrakePressed = false
        autoReloadWeapon=nil
        flightBrakePressed = false; hornPressed = false; nozzleUpPressed = false; nozzleDownPressed = false; firePressed = false
        lastVehicleButton = false; lastJobsButton = false; lastGearButton = false; lastLightsButton = false
        lastJumpButton = false; lastAttackButton = false; lastWeaponButton = false; lastReloadButton = false
        lastCrouchButton = false; lastGamepadAim = false; lastCameraButton = false
        setAiming(false)
        runButton.layer.borderWidth = 1; runButton.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        renderer?.weaponTriggerHeld = false; renderer?.vehicleHandbrake = false; renderer?.vehicleHorn = false
        renderer?.vehicleJetControl = 0; renderer?.personalFlightDown = false; renderer?.personalFlightBrake = false
        renderer?.cancelCameraInput(); renderer?.cancelGameplayInput(); renderer?.streamWeapon(nil, delta: 0)
        audio.cancelHornInput()
        audio.stream(weapon: 0, active: false)
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard applicationActive, presentedViewController == nil else { return }
        for press in presses {
            guard let code = press.key?.keyCode else { continue }
            let first = heldKeys.insert(code).inserted
            guard first else { continue }
            switch code {
            case .keyboardSpacebar: jump()
            case .keyboardC: toggleCrouch()
            case .keyboardE: toggleVehicle()
            case .keyboardR: if currentVehicle != nil { toggleGear() } else { reload() }
            case .keyboardTab: toggleWeapon()
            case .keyboardQ: toggleAim()
            case .keyboardT: openChat()
            case .keyboardM: openMap()
            case .keyboardF: openGameplay()
            case .keyboardG: openAnimations()
            case .keyboardV: renderer?.cycleCameraView()
            case .keyboardL: if currentVehicle != nil { renderer?.vehicleLights.toggle() }
            default: break
            }
        }
        super.pressesBegan(presses, with: event)
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let code = press.key?.keyCode { heldKeys.remove(code) } }
        super.pressesEnded(presses, with: event)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        resetControls(); super.pressesCancelled(presses, with: event)
    }

    init(server: ServerAddress) {
        self.server = server
        self.network = NativeMultiplayerClient(server: server)
        self.gameplay = NativeGameplayClient(server: server)
        self.radio = NativeVehicleRadio(server: server)
        self.weapons = NativeWeaponState(server: server)
        self.audio = NativeGameAudio(server: server)
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
        audio.prepare()
        renderer?.weatherAudio = audio.weather
        renderer?.onCollision = { [weak self] speed in self?.audio.collision(severity: speed) }
        renderer?.onLand = { [weak self] in
            guard let self,self.renderer?.hasOriginalFootAnimation != true else {return}
            self.audio.land()
        }
        renderer?.onFootstep = { [weak self] kind in
            guard let self,let renderer=self.renderer else {return}
            self.audio.footstep(kind,material:renderer.groundMaterial,surface:renderer.groundSurface,wading:renderer.isWading)
        }
        renderer?.onSplash = { [weak self] in self?.audio.land(water:true) }
        renderer?.onVehicleExplosion = { [weak self] _ in self?.audio.explosion(weapon:51) }
        renderer?.onVehicleMove = { [weak self] id,state in self?.network.sendVehicleMove(id,state:state) }
        renderer?.onContactAudio = { [weak self] collisions,body in self?.audio.vehicleContacts(collisions,body:body) }
        renderer?.onLocalHealth = { [weak self] value in self?.network.reportLocalHealth(value) }
        renderer?.onParachuteUsed = { [weak self] in self?.network.usedParachute() }
        network.onFlightGear = { [weak self] parachute,jetpack in self?.renderer?.setFlightGear(parachute:parachute,jetpack:jetpack) }
        weapons.onChange = { [weak self] in
            guard let self else { return }
            self.renderer?.equippedWeapon = self.weapons.selected
            self.updateWeaponHUD()
        }
        weapons.onNeedsRefresh = { [weak self] in self?.gameplay.refresh() }
        weapons.onNeedsResync = { [weak self] in self?.network.requestInventoryResync() }
        network.onInventoryConnection = { [weak self] nonce in
            guard let self else{return}
            self.gameplay.inventoryConnection=nonce
            self.weapons.setConnection(nonce)
            self.renderer?.cancelWeaponInput();self.renderer?.cancelReloadAnimation()
        }
        network.onInventory = { [weak self] state in self?.weapons.apply(state) }
        network.onProjectiles = { [weak self] rows in self?.renderer?.synchronizeProjectiles(rows) }
        network.onBlast = { [weak self] weapon, position in
            self?.renderer?.showBlast(weapon:weapon,position:position)
            let distance = self?.renderer.map { simd_distance($0.position,position) } ?? 0
            self?.audio.explosion(weapon:weapon,distance:distance)
        }
        network.onWeaponSound = { [weak self] weapon in self?.audio.shot(weapon:weapon) }
        renderer?.equippedWeapon = weapons.selected
        renderer?.onFootWeaponShot = { [weak self] weapon, left in
            self?.consumeFootWeaponShot(weapon: weapon, left: left) ?? false
        }
        network.onStatus = { [weak self] text in self?.status.text = text }
        network.onPresence = { [weak self] count, names in
            self?.players.text = "\(count) PLAYER\(count == 1 ? "" : "S") ONLINE" +
                (names.count > 1 ? "  ·  " + names.joined(separator: ", ") : "")
        }
        network.onPlayers = { [weak self] players in
            guard let self else {return}
            self.renderer?.remoteServerTimeOffsetMilliseconds=self.network.serverTimeOffsetMilliseconds
            self.renderer?.remotePlayers=players
        }
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
            self.radio.enter(model:Int(vehicle.code.split(separator:".").first ?? "") ?? 0)
            self.radioButton.setTitle(self.radio.stationName.uppercased(),for:.normal)
        }
        network.onTeleport = { [weak self] point, heading in
            self?.resetControls()
            self?.renderer?.teleport(x: point.x, y: point.y, z: point.z, direction: heading)
        }
        network.onEnvironment = { [weak self] weather, shift, hold in
            if let weather { self?.renderer?.setWeather(weather) }
            if let shift { self?.renderer?.dayShift = shift }
            self?.renderer?.dayHold = hold
        }
        network.onVitals = { [weak self] health, armour in
            if health <= 0 { self?.resetControls() }
            self?.renderer?.health = health
            self?.vitals.text = "HEALTH \(health)  ·  ARMOUR \(armour)"
            self?.gameHUD.updateVitals(health: health, armour: armour)
            self?.attackButton.setTitle(health == 0 ? "RESPAWN" :
                                          (self?.usingPistol == true ? "FIRE" : "HIT"), for: .normal)
        }
        gameplay.onState = { [weak self] state in
            guard let self else { return }
            self.network.syncVitals(from: state)
            if let inventory = state["weaponInventory"] as? [String: Any] {
                self.weapons.apply(inventory)
                self.weaponPanel?.update(inventory, cash: (state["cash"] as? NSNumber)?.intValue ?? 0,
                                         onFoot: self.currentVehicle == nil)
            }
            self.gameHUD.updateWorld(state: state)
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
        NotificationCenter.default.addObserver(self, selector: #selector(applicationResigned), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationReturned), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerChanged), name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerChanged), name: .GCControllerDidDisconnect, object: nil)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        resetControls(); frameClock.reset()
        displayLink?.invalidate()
        network.disconnect()
        radio.stop()
        audio.stop()
        heldKeys.removeAll()
    }

    private func installHUD() {
        let menu = button("MENU", action: #selector(openPause))
        styleControl(menu, icon: "Touch_pause", fallback: "pause.fill", accessibility: "Open game menu")
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
        stick.accessibilityLabel = "Movement stick"; look.accessibilityLabel = "Camera look stick"
        look.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(look)
        runButton.setTitle("RUN", for: .normal)
        runButton.addTarget(self, action: #selector(toggleRun), for: .touchUpInside)
        styleControl(runButton, icon: nil, fallback: "figure.run", accessibility: "Toggle sprint")
        runButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(runButton)
        jumpButton.setTitle("JUMP", for: .normal)
        jumpButton.translatesAutoresizingMaskIntoConstraints = false
        jumpButton.addTarget(self, action: #selector(jump), for: .touchDown)
        jumpButton.addTarget(self, action: #selector(pressHandbrake), for: .touchDown)
        jumpButton.addTarget(self, action: #selector(releaseHandbrake), for: [.touchUpInside,.touchUpOutside,.touchCancel])
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
        attackButton.addTarget(self, action: #selector(pressFire), for: .touchDown)
        attackButton.addTarget(self, action: #selector(releaseFire), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        view.addSubview(attackButton)
        aimButton.translatesAutoresizingMaskIntoConstraints = false
        styleControl(aimButton, icon: nil, fallback: "viewfinder", accessibility: "Toggle aim")
        aimButton.addTarget(self, action: #selector(toggleAim), for: .touchUpInside)
        view.addSubview(aimButton)
        crouchButton.translatesAutoresizingMaskIntoConstraints = false
        styleControl(crouchButton, icon: nil, fallback: "arrow.down.to.line", accessibility: "Toggle crouch")
        crouchButton.addTarget(self, action: #selector(toggleCrouch), for: .touchUpInside)
        crouchButton.addTarget(self,action:#selector(pressFlightBrake),for:.touchDown)
        crouchButton.addTarget(self,action:#selector(releaseFlightBrake),for:[.touchUpInside,.touchUpOutside,.touchCancel])
        view.addSubview(crouchButton)
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
            control.addTarget(self, action: control === weaponButton ? #selector(pressNozzleUp) : #selector(pressNozzleDown), for: .touchDown)
            control.addTarget(self, action: #selector(releaseNozzle), for: [.touchUpInside,.touchUpOutside,.touchCancel])
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
            ,aimButton.trailingAnchor.constraint(equalTo: attackButton.leadingAnchor, constant: -10),
            aimButton.centerYAnchor.constraint(equalTo: attackButton.centerYAnchor),
            aimButton.widthAnchor.constraint(equalToConstant: 44),
            aimButton.heightAnchor.constraint(equalTo: aimButton.widthAnchor)
            ,crouchButton.centerXAnchor.constraint(equalTo: attackButton.centerXAnchor),
            crouchButton.centerYAnchor.constraint(equalTo: jumpButton.centerYAnchor),
            crouchButton.widthAnchor.constraint(equalToConstant: 44),
            crouchButton.heightAnchor.constraint(equalTo: crouchButton.widthAnchor)
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
    @objc private func openPause() {
        guard presentedViewController == nil else { return }
        heldKeys.removeAll();firePressed = false;handbrakePressed = false
        let panel = NativePausePanel();panel.driving = currentVehicle != nil
        panel.cameraName = { [weak self] in self?.renderer?.cameraViewName ?? "middle" }
        panel.onCamera = { [weak self] in self?.renderer?.cycleCameraView() }
        panel.onAnimations = { [weak self] in self?.openAnimations() }
        panel.onRadio = { [weak self] in self?.nextRadioStation() }
        panel.onFlightGear = { [weak self] in self?.openFlightEquipment() }
        panel.weatherName = { [weak self] in self?.renderer?.weatherAuto == true ? "REGIONAL AUTO" : "SERVER" }
        panel.onWeather = { [weak self] in
            guard let renderer = self?.renderer else { return };renderer.weatherAuto.toggle()
        }
        panel.onLeave = { [weak self] in self?.close() }
        panel.modalPresentationStyle = .overFullScreen;present(panel,animated:true)
    }
    @objc private func openChat() {
        guard presentedViewController == nil else { return }
        heldKeys.removeAll();firePressed=false
        let panel = NativeChatPanel()
        panel.modalPresentationStyle = .overFullScreen
        panel.onSend = { [weak self] line in self?.network.sendChat(line) }
        panel.update(network.chatMessages)
        chatPanel = panel
        present(panel, animated: true)
    }

    private func openFlightEquipment() {
        guard presentedViewController==nil,currentVehicle==nil,network.health>0 else{return}
        let sheet=UIAlertController(title:"FLIGHT EQUIPMENT",message:"Parachute: fire opens the canopy. Jetpack: run or move to rise, jump to descend, crouch to brake.",preferredStyle:.actionSheet)
        sheet.addAction(UIAlertAction(title:"Equip parachute",style:.default){[weak self] _ in self?.network.sendChat("/parachute")})
        let worn=renderer?.wearingJetpack == true
        let jetpack=UIAlertAction(title:worn ? "Remove jetpack":"Equip jetpack",style:.default){[weak self] _ in self?.network.sendChat(worn ? "/dropjetpack":"/jetpack")}
        jetpack.isEnabled = !worn || renderer?.canDropJetpack == true
        sheet.addAction(jetpack)
        sheet.addAction(UIAlertAction(title:"Cancel",style:.cancel))
        sheet.popoverPresentationController?.sourceView=view
        sheet.popoverPresentationController?.sourceRect=CGRect(x:view.bounds.midX,y:view.bounds.midY,width:1,height:1)
        present(sheet,animated:true)
    }
    @objc private func openMap() {
        guard presentedViewController == nil else { return }
        heldKeys.removeAll();firePressed=false
        let map = NativeCityMapViewController(image: gameHUD.radar.mapImage,
                                              position: gameHUD.radar.position,
                                              players: gameHUD.radar.players,
                                              vehicles: gameHUD.radar.vehicles,
                                              target: gameHUD.radar.target,
                                              markers: gameHUD.radar.markers,
                                              heading: gameHUD.radar.heading,
                                              waypoint: gameHUD.radar.waypoint,
                                              onWaypoint: { [weak self] point in self?.gameHUD.radar.waypoint = point })
        map.modalPresentationStyle = .overFullScreen
        present(map, animated: true)
    }
    @objc private func controllerChanged() { resetControls(); status.text = GCController.controllers().isEmpty ? "TOUCH CONTROLS ACTIVE" : "CONTROLLER CONNECTED" }
    @objc private func toggleRun() {
        run.toggle()
        runButton.layer.borderColor = (run ? UIColor(red: 0.365, green: 0.714, blue: 0.898, alpha: 1) :
                                       UIColor.white.withAlphaComponent(0.3)).cgColor
        runButton.layer.borderWidth = run ? 2.5 : 1
    }
    @objc private func jump() { renderer?.jump() }
    @objc private func pressGas() { if acceptsHeldInput { gasPressed = true } }
    @objc private func releaseGas() { gasPressed = false }
    @objc private func pressHandbrake() { if acceptsHeldInput { handbrakePressed = true } }
    @objc private func releaseHandbrake() { handbrakePressed = false }
    @objc private func pressFlightBrake() { if acceptsHeldInput { flightBrakePressed = true } }
    @objc private func releaseFlightBrake() {flightBrakePressed=false}
    @objc private func pressBrake() { if acceptsHeldInput { brakePressed = true } }
    @objc private func releaseBrake() { brakePressed = false }
    @objc private func nextRadioStation() {
        guard currentVehicle != nil else { return }
        radio.next()
        radioButton.setTitle(radio.stationName, for: .normal)
    }
    @objc private func performNearbyMissionAction() {
        guard let nearbyMissionAction else { return }
        missionButton.isHidden = true
        if nearbyMissionAction == "native.weapons" { toggleWeapon() }
        else { gameplay.perform(nearbyMissionAction,payload:nearbyMissionPayload) }
    }

    private func updateNearbyMissionAction(_ state: [String: Any]) {
        nearbyMissionAction = nil
        nearbyMissionPayload = [:]
        guard let job = state["job"] as? [String: Any],
              let remaining = (job["remaining"] as? NSNumber)?.doubleValue,
              remaining <= ((job["radius"] as? NSNumber)?.doubleValue ?? 0) else {
            updatePropertyAction(state)
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

    private func updatePropertyAction(_ state: [String:Any]) {
        missionButton.isHidden = true
        guard currentVehicle == nil, network.health > 0 else { return }
        if state["insideHome"] is [String:Any] {
            nearbyMissionAction = "home.exit"; missionButton.accessibilityLabel = "Exit home"
        } else if let renderer, let homes = state["homes"] as? [[String:Any]],
                  let home = homes.first(where: { value in
                      guard let out = value["out"] as? [NSNumber],out.count>=3 else { return false }
                      return simd_distance(renderer.position,SIMD3(out[0].floatValue,out[1].floatValue,out[2].floatValue)) <= 8
                  }), let id = home["id"] as? String {
            nearbyMissionAction = "home.enter";nearbyMissionPayload = ["home":id]
            missionButton.accessibilityLabel = "Enter \(home["name"] as? String ?? "home")"
        } else if let inventory = state["weaponInventory"] as? [String:Any],
                  let shop = inventory["nearestShop"] as? [String:Any],shop["within"] as? Bool == true {
            nearbyMissionAction = "native.weapons";missionButton.accessibilityLabel = "Open Ammu-Nation"
        }
        missionButton.isHidden = nearbyMissionAction == nil
    }

    private func updateWeaponHUD() {
        guard currentVehicle == nil else { return }
        weaponButton.setTitle(weapons.current.name.uppercased(), for: .normal)
        weaponButton.accessibilityLabel = "Choose weapon. \(weapons.current.name) equipped"
        reloadButton.isHidden = currentVehicle != nil || !usingPistol ||
            (weapons.selected != 39 && (magazine >= weapons.current.capacity || reserve == 0))
        reloadButton.accessibilityLabel = weapons.selected == 39 ? "Detonate planted satchels" : "Reload"
        aimButton.isHidden = currentVehicle != nil || !usingPistol
        ammoLabel.text = weapons.reloading ? "RELOADING" : "\(weapons.current.name.uppercased()) · \(magazine) / \(reserve)"
        gameHUD.updateWeapon(id: weapons.selected, name: weapons.current.name, magazine: magazine, reserve: reserve)
        gameHUD.loadWeaponIcon(server: server, weapon: weapons.selected)
        styleControl(weaponButton,icon:"Touch_weapons",fallback:"circle.grid.2x2.fill",accessibility:"Choose weapon")
        styleControl(reloadButton,icon:"Touch_reload",fallback:"arrow.clockwise",accessibility:weapons.selected == 39 ? "Detonate planted satchels" : "Reload")
        attackButton.setTitle(network.health == 0 ? "RESPAWN" :
                              (usingPistol ? "FIRE" : "HIT"), for: .normal)
        styleControl(attackButton, icon: usingPistol ? "Touch_fire" : nil,
                     fallback: usingPistol ? "scope" : "hand.raised.fingers.spread.fill",
                     accessibility: network.health == 0 ? "Respawn" : usingPistol ? "Fire" : "Hit")
    }

    private func setDrivingControls(_ driving: Bool) {
        resetControls()
        vehicleButton.isHidden = false
        radioButton.isHidden = !driving
        runButton.isHidden = driving
        let roadVehicle = driving && !["plane","helicopter","boat","train"].contains(renderer?.vehicleKind ?? "car")
        jumpButton.isHidden = driving && !roadVehicle
        styleControl(jumpButton, icon: driving ? nil : "Touch_jump",
                     fallback: driving ? "p.circle.fill" : "figure.run",
                     accessibility: driving ? "Hold handbrake" : "Jump")
        gasButton.isHidden = !driving
        brakeButton.isHidden = !driving
        let helicopter = driving && renderer?.vehicleKind == "helicopter"
        styleControl(gasButton, icon: helicopter ? nil : "Touch_gas",
                     fallback: helicopter ? "arrow.up" : "pedal.accelerator.fill",
                     accessibility: helicopter ? "Climb" : "Accelerate")
        styleControl(brakeButton, icon: nil,
                     fallback: helicopter ? "arrow.down" : "minus.circle.fill",
                     accessibility: helicopter ? "Descend" : "Brake or reverse")
        let nozzle = driving && renderer?.hasJetNozzle == true
        weaponButton.isHidden = driving && !nozzle
        attackButton.isHidden = driving && renderer?.hasVehicleHorn != true
        reloadButton.isHidden = driving ? !nozzle : !usingPistol ||
            (weapons.selected != 39 && (magazine >= weapons.current.capacity || reserve == 0))
        aimButton.isHidden = driving ? renderer?.vehicleKind == "bicycle" : !usingPistol
        crouchButton.isHidden = driving && renderer?.hasLandingGear != true
        styleControl(crouchButton,icon:nil,fallback:driving ? "airplane.circle" : "arrow.down.to.line",accessibility:driving ? "Toggle landing gear" : "Toggle crouch")
        styleControl(aimButton,icon:nil,fallback:driving ? "light.max" : "viewfinder",accessibility:driving ? "Toggle vehicle lights" : "Toggle aim")
        if driving {
            styleControl(attackButton,icon:nil,fallback:"speaker.wave.2.fill",accessibility:"Hold horn")
            if nozzle {
                styleControl(weaponButton,icon:nil,fallback:"arrow.up.right",accessibility:"Hold to rotate jets forward")
                styleControl(reloadButton,icon:nil,fallback:"arrow.down",accessibility:"Hold to rotate jets downward")
            }
        } else { updateWeaponHUD() }
        if driving { setAiming(false); firePressed = false }
        if !driving { gasPressed = false; brakePressed = false; handbrakePressed = false }
        hornPressed = false;nozzleUpPressed = false;nozzleDownPressed = false
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
        if currentVehicle != nil && renderer?.hasJetNozzle == true { return }
        guard currentVehicle == nil else { status.text = "EXIT THE VEHICLE TO EQUIP"; return }
        guard presentedViewController == nil else { return }
        heldKeys.removeAll(); firePressed = false; setAiming(false)
        let panel = NativeWeaponShopPanel()
        panel.modalPresentationStyle = .overFullScreen
        panel.onAction = { [weak self] action, payload in self?.gameplay.perform(action, payload: payload) }
        panel.onNavigate = { [weak self] point in self?.gameHUD.radar.waypoint = point }
        panel.update(gameplay.state["weaponInventory"] as? [String: Any] ?? [:],
                     cash: (gameplay.state["cash"] as? NSNumber)?.intValue ?? 0, onFoot: true)
        weaponPanel = panel
        present(panel, animated: true)
    }

    @objc private func toggleAim() {
        if currentVehicle != nil { renderer?.vehicleLights.toggle();return }
        setAiming(!aiming)
    }
    @objc private func toggleGear() { if renderer?.hasLandingGear == true { renderer?.toggleLandingGear() } }
    @objc private func pressNozzleUp() { if acceptsHeldInput && currentVehicle != nil && renderer?.hasJetNozzle == true { nozzleUpPressed = true } }
    @objc private func pressNozzleDown() { if acceptsHeldInput && currentVehicle != nil && renderer?.hasJetNozzle == true { nozzleDownPressed = true } }
    @objc private func releaseNozzle() { nozzleUpPressed = false;nozzleDownPressed = false }
    @objc private func toggleCrouch() {
        if currentVehicle != nil { toggleGear();return }
        guard currentVehicle == nil, let renderer, network.health > 0 else { return }
        renderer.toggleCrouch()
        crouchButton.backgroundColor = UIColor.black.withAlphaComponent(renderer.crouching ? 0.7 : 0.3)
    }
    private func setAiming(_ value: Bool) {
        aiming = value && usingPistol && currentVehicle == nil && renderer?.isClimbing != true && renderer?.swimming != true && renderer?.isChuting != true
        renderer?.aiming = aiming
        gameHUD.setAiming(aiming, scoped: weapons.selected == 34)
        aimButton.backgroundColor = UIColor.black.withAlphaComponent(aiming ? 0.7 : 0.3)
    }
    @objc private func pressFire() {
        guard acceptsHeldInput else { return }
        if currentVehicle != nil { hornPressed = true;return }
        firePressed = true;attack()
    }
    @objc private func releaseFire() { firePressed = false;hornPressed = false }

    @objc private func reload() {
        guard currentVehicle == nil,renderer?.isClimbing != true,renderer?.swimming != true,renderer?.isChuting != true else { return }
        if weapons.selected == 39 { network.detonateSatchels(); return }
        guard usingPistol else { return }
        guard !weapons.reloading, magazine < weapons.current.capacity, reserve > 0 else { return }
        let requestID=weapons.beginReloadRequest()
        let connection=network.inventoryConnection
        gameplay.perform("weapon.reload") { [weak self] result in
            guard let self else{return}
            guard self.network.inventoryConnection==connection else{return}
            self.weapons.finishReloadRequest(id:requestID,succeeded:result)
            if result == false {self.renderer?.cancelReloadAnimation()}
        }
        let clips = NativeWeaponAnimation.forWeapon(weapons.selected)
        renderer?.fireWeapon(clip: renderer?.crouching == true ? clips.crouchReload : clips.reload, duration: 1.8)
        audio.reload(weapon: weapons.selected)
        updateWeaponHUD()
        status.text = "RELOADING \(weapons.current.name.uppercased())"
    }

    @objc private func attack() {
        guard acceptsHeldInput else { return }
        guard let renderer else { return }
        if renderer.isChuting {renderer.openParachute();return}
        if currentVehicle != nil && network.health > 0 { return }
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
        guard !renderer.swimming,!renderer.isClimbing else { return }
        if usingPistol && renderer.hasNativeFootWeaponTiming {
            _ = renderer.requestFootWeaponFire()
            return
        }
        // Unsupported jetpack weapon types must not fall back to wall-clock
        // firing through the flight animation. Armed flight is capability-gated.
        guard !renderer.wearingJetpack else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastAttackTime >= weapons.current.interval,let ray=currentShotRay(),let ticket=network.reserveShot(),weapons.fire(ticket:ticket) else { return }
        lastAttackTime = now
        if usingPistol {
            updateWeaponHUD()
            let clips = NativeWeaponAnimation.forWeapon(weapons.selected)
            renderer.fireWeapon(clip: weapons.current.fireKind == "PROJECTILE" ? "grenade/weapon_throw/n/1" : renderer.crouching ? clips.crouchFire : clips.fire,
                                duration: weapons.current.fireKind == "PROJECTILE" ? 0.8 : Float(weapons.current.interval))
            emitWeaponShot(weapon: weapons.selected, left: false,ticket:ticket,ray:ray)
            return
        }
        renderer.performFistAttack()
        audio.swing()
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
        audio.meleeHit()
        status.text = "FIST ATTACK ON \(target.0.name.uppercased())"
    }

    private func consumeFootWeaponShot(weapon: Int, left: Bool)->Bool {
        guard let renderer, applicationActive, presentedViewController == nil, currentVehicle == nil,
              network.health > 0, !network.passive, !renderer.swimming, !renderer.isChuting,
              renderer.hasNativeFootWeaponTiming, weapons.selected == weapon, usingPistol,
              let ray=currentShotRay(),let ticket=network.reserveShot() else { return false }
        return NativeWeaponShotDelivery.deliver(weapon: weapon, left: left,ticket:ticket, inventory: weapons,
            readiness: { renderer.weaponReady = $0 }, emission: { [self] weapon, left,ticket in
                updateWeaponHUD()
                emitWeaponShot(weapon: weapon, left: left,ticket:ticket,ray:ray)
            })
    }

    /// Freeze valid geometry before reserving/spending a ticket. Emission is
    /// synchronous, so both hands retain their own event-time ray snapshot.
    private func currentShotRay()->NativeShotTargeting.Ray? {
        guard let renderer else{return nil}
        return .init(origin:NativeShotTargeting.muzzle(feet:renderer.shotFeet),
                     direction:renderer.aimDirection,range:weapons.current.range)
    }

    /// Shared effects/network emission. Animation-event firing never restarts a
    /// clip here. Muzzle position retains the existing body-offset approximation;
    /// `left` preserves event identity until actual per-hand muzzle data is wired.
    private func emitWeaponShot(weapon: Int, left: Bool,ticket:NativeShotTicket,ray:NativeShotTargeting.Ray) {
        guard let renderer, weapons.selected == weapon else { return }
        if weapons.current.fireKind == "PROJECTILE" {
            network.sendWeaponShot(weapon: weapon, from: ray.origin,
                to: ray.point(at:max(5,min(100,ray.range))), player: nil,ticket:ticket)
            return
        }
        audio.shot(weapon: weapon)
        let candidates=network.orderedPlayers.map {
            NativeShotTargeting.Candidate(id:$0.id,point:NativeShotTargeting.torso(feet:$0.position))
        }
        let target=NativeShotTargeting.select(ray:ray,aiming:aiming,candidates:candidates,
            visible:{renderer.hasClearShot(from:$0,to:$1)})
        network.sendWeaponShot(weapon:weapon,from:ray.origin,to:target?.point ?? ray.end,player:target?.id,ticket:ticket)
    }

    @objc private func openGameplay() {
        guard presentedViewController == nil else { return }
        heldKeys.removeAll();firePressed=false
        let panel = NativeGameplayPanel()
        panel.modalPresentationStyle = .overFullScreen
        panel.onAction = { [weak self] action, payload in self?.gameplay.perform(action, payload: payload) }
        panel.onAnimations = { [weak self, weak panel] in
            panel?.dismiss(animated: true) { self?.openAnimations() }
        }
        panel.update(gameplay.state)
        gameplayPanel = panel
        present(panel, animated: true)
    }

    @objc private func openAnimations() {
        guard presentedViewController == nil, let renderer else { return }
        heldKeys.removeAll(); firePressed = false
        let panel = NativeAnimationPanel(clips: renderer.animationClips)
        panel.onPlay = { [weak renderer] name, loop in renderer?.playAnimation(name, looping: loop) }
        panel.onStop = { [weak renderer] in renderer?.clearAction() }
        panel.modalPresentationStyle = .overFullScreen
        present(panel, animated: true)
    }

    @objc private func toggleVehicle() {
        guard let renderer else { return }
        if renderer.isClimbing {renderer.letGoOfLedge();return}
        if renderer.canDropJetpack {network.sendChat("/dropjetpack");return}
        if currentVehicle != nil {
            if [1,3].contains(renderer.riderWireAction) {status.text="ENTERING VEHICLE";return}
            if renderer.beginVehicleExit(onReady:{[weak self] in self?.completeVehicleExit()}) {return}
            completeVehicleExit();return
        }
        guard let nearest = network.orderedVehicles.map(renderer.predictedVehicle).min(by: {
            simd_distance($0.position, renderer.position) < simd_distance($1.position, renderer.position)
        }), simd_distance(nearest.position, renderer.position) <= 8 else {
            status.text = "MOVE WITHIN 8 M OF A VEHICLE"
            return
        }
        network.requestEnter(nearest)
    }

    private func completeVehicleExit() {
        guard let renderer,currentVehicle != nil else{return}
        let parked = renderer.vehicleWirePosition, heading = renderer.direction
        let pitch = renderer.vehicleNose, roll = renderer.vehicleRoll
        let damage = renderer.vehicleDamage
        renderer.exitVehicle()
        if let currentVehicle {
            network.sendExit(renderer.position, parked: parked, heading: heading, pitch: pitch, roll: roll,
                             vehicle: currentVehicle, vehicleHealth: renderer.vehicleHealth,vehicleDamage:damage)
        }
        currentVehicle = nil
        vehicleButton.setTitle("ENTER CAR", for: .normal)
        gameHUD.updateVehicle(name: nil, speed: 0)
        setDrivingControls(false)
        radio.stop()
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
        let active = applicationActive && view.window != nil
        let timing = frameClock.advance(timestamp: link.timestamp, active: active)
        if timing.discontinuity { resetControls() }
        let delta = Float(timing.delta)
        weapons.tick()
        var acceptsInput = active && presentedViewController == nil
        if !acceptsInput && inputWasAvailable { resetControls() }
        inputWasAvailable = acceptsInput
        // Over-full-screen panels leave the game visible, so UIKit does not
        // always repeat viewDidAppear when keyboard input should resume.
        if acceptsInput,view.window != nil,!isFirstResponder { becomeFirstResponder() }
        if acceptsInput && firePressed && renderer?.hasNativeFootWeaponTiming != true { attack() }
        var forward = Float(-stick.value.y)
        var sideways = Float(stick.value.x)
        var steering = Float(lookStick.value.x)
        var lookVertical = Float(-lookStick.value.y)
        var cameraLookX: Float = currentVehicle != nil ? steering : 0
        var cameraLookY: Float = currentVehicle != nil ? lookVertical : 0
        if currentVehicle != nil {
            steering = sideways;lookVertical = forward;forward = 0
        }
        var lift: Float = 0
        var horn = currentVehicle != nil && (hornPressed || heldKeys.contains(.keyboardH) || heldKeys.contains(.keyboardCapsLock))
        var jets: Float = (nozzleUpPressed ? 1:0)-(nozzleDownPressed ? 1:0)
        if heldKeys.contains(.keyboardW) { forward = 1 }
        if heldKeys.contains(.keyboardS) { forward = -1 }
        if heldKeys.contains(.keyboardA) { sideways = -1 }
        if heldKeys.contains(.keyboardD) { sideways = 1 }
        if currentVehicle != nil && (heldKeys.contains(.keyboardA) || heldKeys.contains(.keyboardD)) { steering = sideways }
        if heldKeys.contains(.keyboardLeftArrow) { if currentVehicle != nil { cameraLookX = -1 } else { steering = -1 } }
        if heldKeys.contains(.keyboardRightArrow) { if currentVehicle != nil { cameraLookX = 1 } else { steering = 1 } }
        if heldKeys.contains(.keyboardUpArrow) { if currentVehicle != nil { cameraLookY = 1 } else { lookVertical = 1 } }
        if heldKeys.contains(.keyboardDownArrow) { if currentVehicle != nil { cameraLookY = -1 } else { lookVertical = -1 } }
        let helicopter = currentVehicle != nil && renderer?.vehicleKind == "helicopter"
        var gamepadRunning = false
        var gamepadJumping = false
        var gamepadAttacking = false
        var gamepadWeapon = false
        var gamepadReload = false
        let controller = GCController.controllers().compactMap(\.extendedGamepad).first
        var controllerAllowed = false
        if let pad = controller {
            let pressed = [pad.buttonA,pad.buttonB,pad.buttonX,pad.buttonY,pad.leftShoulder,pad.rightShoulder,
                           pad.dpad.up,pad.dpad.down,pad.dpad.left,pad.dpad.right,pad.buttonMenu].contains { $0.isPressed } ||
                pad.leftThumbstickButton?.isPressed == true || pad.rightThumbstickButton?.isPressed == true || pad.buttonOptions?.isPressed == true
            controllerAllowed = controllerGate.accepts(active: acceptsInput,
                axes: [pad.leftThumbstick.xAxis.value,pad.leftThumbstick.yAxis.value,pad.rightThumbstick.xAxis.value,
                       pad.rightThumbstick.yAxis.value,pad.leftTrigger.value,pad.rightTrigger.value], pressed: pressed)
        } else { controllerGate.reset() }
        if controllerAllowed, let pad = controller {
            let crouch = pad.leftThumbstickButton?.isPressed == true
            if currentVehicle == nil && crouch && !lastCrouchButton { toggleCrouch() }
            lastCrouchButton = crouch
            let left = NativeInputMath.stick(x: pad.leftThumbstick.xAxis.value, y: pad.leftThumbstick.yAxis.value)
            let lx = left.x, ly = left.y
            if abs(lx) + abs(ly) > 0.05 { forward = ly; sideways = lx }
            let right = NativeInputMath.stick(x: pad.rightThumbstick.xAxis.value, y: pad.rightThumbstick.yAxis.value)
            let rx = right.x
            if abs(rx) > 0.05 { if currentVehicle != nil { cameraLookX = rx } else { steering = rx } }
            let ry = right.y
            if abs(ry) > 0.05 { if currentVehicle != nil { cameraLookY = ry } else { lookVertical = ry } }
            gamepadRunning = pad.buttonA.isPressed
            gamepadJumping = pad.buttonB.isPressed
            if currentVehicle != nil {
                lookVertical = ly;steering = lx
                sideways = (pad.rightShoulder.isPressed ? 1 : 0)-(pad.leftShoulder.isPressed ? 1 : 0)
                renderer?.cameraLookDirection = pad.rightThumbstickButton?.isPressed == true ? "behind" : nil
                let cameraButton = pad.buttonOptions?.isPressed == true
                if cameraButton && !lastCameraButton { renderer?.cycleCameraView() }
                lastCameraButton = cameraButton
                horn = horn || pad.leftThumbstickButton?.isPressed == true
                let gear = pad.dpad.up.isPressed,lights = pad.dpad.right.isPressed
                if gear && !lastGearButton { toggleGear() }
                if lights && !lastLightsButton { renderer?.vehicleLights.toggle() }
                lastGearButton = gear;lastLightsButton = lights
                if renderer?.hasJetNozzle == true { jets = (pad.dpad.left.isPressed ? 1:0)-(pad.dpad.down.isPressed ? 1:0) }
                let throttle = pad.rightTrigger.value
                let braking = pad.leftTrigger.value
                if helicopter {
                    if throttle > 0.05 || braking > 0.05 { lift = throttle - braking }
                } else {
                    if throttle > 0.05 || braking > 0.05 { forward = throttle - braking }
                    else { forward = 0 }
                }
            } else {
                gamepadAttacking = pad.rightTrigger.isPressed
                let aim = pad.leftTrigger.isPressed
                if usingPistol && aim != lastGamepadAim { setAiming(aim) }
                lastGamepadAim = aim
            }
            gamepadWeapon = currentVehicle == nil && pad.leftShoulder.isPressed
            gamepadReload = currentVehicle == nil && pad.rightShoulder.isPressed
            if pad.buttonX.isPressed && !lastVehicleButton { toggleVehicle() }
            if pad.buttonY.isPressed && !lastJobsButton && presentedViewController == nil { openGameplay() }
            lastVehicleButton = pad.buttonX.isPressed
            lastJobsButton = pad.buttonY.isPressed
        }
        // Opening a panel from a controller during this frame must suppress the
        // same frame's remaining jump/fire/movement commands too.
        acceptsInput = acceptsInput && presentedViewController == nil
        if !acceptsInput {
            gamepadJumping = false; gamepadAttacking = false; gamepadWeapon = false; gamepadReload = false
        }
        if gamepadJumping && !lastJumpButton { renderer?.jump() }
        lastJumpButton = gamepadJumping
        let hornState=audio.vehicleHornInput(model:currentVehicle.flatMap{Int($0.code.split(separator:".").first ?? "")},
            identity:currentVehicle?.id,pressed:acceptsInput && horn && renderer?.hasVehicleHorn == true,milliseconds:link.timestamp*1000)
        renderer?.vehicleHorn=hornState.horn;renderer?.vehicleSiren=hornState.siren
        renderer?.vehicleJetControl = acceptsInput ? jets:0
        if gamepadAttacking && (renderer?.hasNativeFootWeaponTiming != true || !lastAttackButton) { attack() }
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
        if !acceptsInput {
            forward = 0;sideways = 0;steering = 0;lookVertical = 0;lift = 0;cameraLookX = 0;cameraLookY = 0
        }
        let walking = abs(forward) + abs(sideways) > 0.05
        let running = acceptsInput && (run || gamepadRunning || heldKeys.contains(.keyboardLeftShift))
        if currentVehicle != nil { renderer?.lookCamera(x:cameraLookX,y:cameraLookY,delta:delta) }
        renderer?.vehicleHandbrake = acceptsInput && currentVehicle != nil &&
            (handbrakePressed || gamepadJumping || heldKeys.contains(.keyboardSpacebar))
        renderer?.vehicleControllerInput = GCController.controllers().contains { $0.extendedGamepad != nil }
        renderer?.personalFlightDown=acceptsInput && (handbrakePressed || gamepadJumping || heldKeys.contains(.keyboardSpacebar))
        renderer?.jumpHeld=acceptsInput && (handbrakePressed || gamepadJumping || heldKeys.contains(.keyboardSpacebar))
        renderer?.personalFlightBrake=acceptsInput && (flightBrakePressed || gamepadReload || heldKeys.contains(.keyboardC))
        if renderer?.isClimbing == true && aiming {setAiming(false)}
        let canFight = acceptsInput && currentVehicle == nil && renderer?.isClimbing != true && network.health > 0 && !network.passive &&
            renderer?.swimming != true && renderer?.isChuting != true &&
            (renderer?.wearingJetpack != true || renderer?.hasNativeFootWeaponTiming == true)
        if !canFight { renderer?.cancelWeaponInput() }
        renderer?.weaponTriggerHeld = canFight && (firePressed || gamepadAttacking)
        renderer?.weaponReloading = weapons.reloading
        renderer?.weaponReady = weapons.canFire
        renderer?.beginGameplayFrame()
        for step in timing.steps {
            renderer?.move(forward: forward, sideways: sideways,
                           turn: steering, delta: Float(step), running: running,
                           lookVertical: lookVertical, lift: lift)
        }
        let triggerHeld=firePressed || gamepadAttacking
        if !triggerHeld || magazine>0 || autoReloadWeapon != weapons.selected {autoReloadWeapon=nil}
        if canFight,triggerHeld,weapons.current.fireKind == "INSTANT_HIT",magazine==0,reserve>0,
           !weapons.reloading,autoReloadWeapon==nil {
            autoReloadWeapon=weapons.selected
            reload()
        }
        if let renderer {
            let streaming = canFight && (renderer.hasNativeFootWeaponTiming ? renderer.nativeWeaponStreamActive :
                (firePressed || gamepadAttacking) && !weapons.reloading && magazine > 0 && [37,38,41,42].contains(weapons.selected))
            renderer.streamWeapon(streaming && [37,41,42].contains(weapons.selected) ? weapons.selected : nil, delta: delta)
            let distance = previousAudioPosition.map { simd_distance($0, renderer.position) } ?? 0
            audio.footsteps(distance: !renderer.hasOriginalFootAnimation && currentVehicle == nil && distance < 3 ? distance : 0,
                           running: running, crouching: renderer.crouching,
                           swimming: renderer.swimming, grounded: !renderer.isAirborne,
                           material:renderer.groundMaterial)
            // There is one stream voice. Calling stop for every other weapon
            // would stop the selected flame/spray/minigun voice in the same frame.
            audio.stream(weapon: weapons.selected, active: streaming)
            audio.fire(active:renderer.hasNearbyFire)
            audio.updateVehicle(model: currentVehicle.flatMap { Int($0.code.split(separator: ".").first ?? "") },
                                kind: renderer.vehicleKind, speed: renderer.drivingSpeed,
                                throttle: forward, health: renderer.vehicleHealth, delta: delta,
                                snapshot:renderer.nativeVehicleAudioSnapshot,hull:renderer.takeVehicleHullAudio(),ear:renderer.audioEar)
            audio.horn(model:currentVehicle.flatMap {Int($0.code.split(separator:".").first ?? "")},active:renderer.vehicleHorn,siren:renderer.vehicleSiren)
            audio.updateRemoteVehicles(network.orderedPlayers,ear:renderer.audioEar,forward:renderer.audioForward,
                                       top:{renderer.remoteVehicleAudioTop($0)})
            audio.updateContacts(delta:Double(delta))
            audio.updateFlightPacks(renderer.flightAudioVoices,delta:Double(delta))
            previousAudioPosition = renderer.position
        }
        if link.timestamp - lastHUD > 0.1, let renderer {
            lastHUD = link.timestamp
            status.expireIfNeeded()
            gameHUD.radar.position = SIMD2(renderer.position.x, renderer.position.y)
            gameHUD.radar.heading = renderer.direction
            gameHUD.radar.players = network.players.values.map { SIMD2($0.position.x, $0.position.y) }
            gameHUD.radar.vehicles = network.vehicles.values.map { SIMD2($0.position.x, $0.position.y) }
            gameHUD.updateVehicle(name: currentVehicle.map(vehicleModelName), speed: renderer.drivingSpeed)
            gameHUD.updateClock(hour: renderer.gameHour)
            gameHUD.updateBreath(renderer.swimmingBreath)
            if currentVehicle == nil {
                let climbing=renderer.isClimbing
                let dropping=renderer.canDropJetpack
                let context=climbing ? "climb":dropping ? "drop":"enter"
                if context != contextActionShown {
                    contextActionShown=context
                    styleControl(vehicleButton,icon:context == "enter" ? "Touch_enter_exit":nil,
                        fallback:climbing ? "hand.raised.slash":dropping ? "arrow.down.to.line":"car.side.fill",
                        accessibility:climbing ? "Let go":dropping ? "Remove jetpack":"Enter vehicle")
                }
                vehicleButton.isHidden = !climbing && !dropping && !network.orderedVehicles.map(renderer.predictedVehicle).contains {
                    simd_distance($0.position, renderer.position) <= 8
                }
            }
        }
        if link.timestamp - lastNetwork > 0.2, let renderer {
            lastNetwork = link.timestamp
            network.sendPosition(currentVehicle == nil ? renderer.position : renderer.vehicleWirePosition, heading: renderer.direction, moving: walking,
                                 running: running,
                                 vehicle: currentVehicle, speed: renderer.drivingSpeed,
                                 steer: renderer.steeringInput,
                                 pitch:currentVehicle == nil ? renderer.personalFlightPitch:renderer.vehicleNose,
                                 roll:currentVehicle == nil ? renderer.personalFlightRoll:renderer.vehicleRoll,
                                 vehicleHealth: renderer.vehicleHealth,
                                 vehicleDamage:renderer.vehicleDamage,lights:renderer.vehicleLights,horn:renderer.vehicleHorn,siren:renderer.vehicleSiren,
                                 airborne: renderer.footWireAirborne, weapon:renderer.isChuting ? 46:weapons.selected,
                                 firing: renderer.isFiring, animation: renderer.footWireAnimation,
                                 crouching: renderer.crouching,swimState: renderer.swimmingState,
                                 swimPitch: renderer.swimmingPitch,swimRatio: renderer.swimmingRatio,
                                 movement:renderer.footWireMovementRatio,aim:renderer.footWireAim,
                                 action:currentVehicle != nil ? renderer.riderWireAction:renderer.footWireAction,
                                 velocity:renderer.currentWireVelocity,angularVelocity:renderer.currentWireAngularVelocity,
                                 kit:renderer.vehicleWireKit(tuck:Double(lookVertical)),paused:!acceptsInput)
        }
        if link.timestamp - lastGameplay > 1.5 {
            lastGameplay = link.timestamp
            radio.synchronize(milliseconds:Date().timeIntervalSince1970*1000+network.serverTimeOffsetMilliseconds)
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

