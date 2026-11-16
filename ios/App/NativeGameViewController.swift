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
    private let appSettings: NativeAppSettings
    private var settingsObserver: NSObjectProtocol?
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
    private var previousPad = NativeGameBindings.Pad()
    private let weaponCycle = NativeWeaponCycleQueue()
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
    private var bunnyHopPressed=false
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
    private var usingMelee:Bool {weapons.current.isMelee}
    private var magazine: Int { weapons.rounds }
    private var reserve: Int { weapons.reserve }
    private var aiming = false
    private var touchMeleeGuard=false
    private var guardWeapon:Int?
    private var pauseEscapeHandoff:NativeModalKeyHandoff?
    private var firePressed = false
    private var lastCrouchButton = false
    private var lastGamepadAim = false
    private var lastCameraButton = false
    private var previousAudioPosition: SIMD3<Float>?
    private var contextActionShown:String?
    private var autoReloadWeapon:Int?
    private var auxiliaryMode:String?
    private var vehicleTuck:Double=0
    private var heldKeys: Set<UIKeyboardHIDUsage> = []
    private var canNavigateMenus:Bool { applicationActive && viewIfLoaded?.window != nil && presentedViewController == nil }
    private var acceptsHeldInput: Bool { canNavigateMenus && network.isReady }
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applicationActive = UIApplication.shared.applicationState == .active
        applyAppSettings()
        network.setApplicationActive(applicationActive)
        becomeFirstResponder()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        renderer?.updateSettingsViewport()
    }
    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
        displayLink?.invalidate();network.disconnect();gameplay.setConnectionReady(false)
    }
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        resetControls()
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange(); stick.reset(); lookStick.reset()
    }
    @objc private func applicationResigned() {
        pauseEscapeHandoff?.release()
        applicationActive = false;network.setApplicationActive(false); frameClock.reset();renderer?.resetDisplayClock(); resetControls()
    }
    @objc private func applicationReturned() {
        applicationActive = true;network.setApplicationActive(true); frameClock.reset();renderer?.resetDisplayClock(); resetControls()
    }
    private func resetControls() {
        heldKeys.removeAll(); stick.reset(); lookStick.reset(); controllerGate.reset()
        previousPad = .init(); weaponCycle.cancel()
        touchMeleeGuard=false
        renderer?.meleeGuardHeld=false;renderer?.meleeBlockHeld=false
        run = false; gasPressed = false; brakePressed = false; handbrakePressed = false
        autoReloadWeapon=nil
        flightBrakePressed = false; hornPressed = false; bunnyHopPressed=false; nozzleUpPressed = false; nozzleDownPressed = false; firePressed = false
        lastVehicleButton = false; lastJobsButton = false; lastGearButton = false; lastLightsButton = false
        lastJumpButton = false; lastAttackButton = false; lastWeaponButton = false; lastReloadButton = false
        lastCrouchButton = false; lastGamepadAim = false; lastCameraButton = false
        setAiming(false)
        runButton.layer.borderWidth = 1; runButton.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        renderer?.walkHeld = false
        renderer?.vehicleHop=false
        renderer?.weaponTriggerHeld = false; renderer?.vehicleHandbrake = false; renderer?.vehicleHorn = false
        renderer?.vehicleJetControl = 0; renderer?.personalFlightDown = false; renderer?.personalFlightBrake = false
        renderer?.vehicleWorkingControl=0;vehicleTuck=0
        renderer?.cancelCameraInput(); renderer?.cancelGameplayInput(); renderer?.streamWeapon(nil, delta: 0)
        audio.cancelHornInput()
        audio.stream(weapon: 0, active: false)
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled=Set(presses.filter{$0.key == nil})
        defer {if !unhandled.isEmpty {super.pressesBegan(unhandled,with:event)}}
        guard applicationActive, presentedViewController == nil else { return }
        if presses.contains(where:{$0.key?.keyCode == .keyboardEscape}) {
            guard !NativeMenuKeyLatch.isHeld(Int(UIKeyboardHIDUsage.keyboardEscape.rawValue)) else { return }
            if heldKeys.insert(.keyboardEscape).inserted {performBinding(.pause)}
            return
        }
        guard network.isReady else{return}
        var firstKeys:[UIKeyboardHIDUsage]=[]
        for press in presses {
            guard let code=press.key?.keyCode else {continue}
            guard !NativeMenuKeyLatch.isHeld(Int(code.rawValue)) else { continue }
            if heldKeys.insert(code).inserted {firstKeys.append(code)}
        }
        // All simultaneous modifiers must be visible before jump/enter edges.
        // Otherwise an unordered Shift+aim batch can jump instead of blocking.
        let context=bindingContext
        for code in firstKeys {
            if let action=NativeGameBindings.keyAction(Int(code.rawValue),context:context) {performBinding(action)}
            if presentedViewController != nil {break}
        }
        // Keyboard input belongs to the game. Forwarding a handled key can
        // invoke the presenting connection/menu controller behind this screen.
    }
    private var bindingContext:NativeGameBindings.Context {
        var mode:NativeGameBindings.Mode = .foot
        if currentVehicle != nil {mode = .vehicle(renderer?.vehicleKind ?? "car")}
        else if renderer?.isClimbing == true {mode = .climb}
        else if renderer?.swimming == true {mode = .swim}
        else if renderer?.isChuting == true {mode = .parachute}
        else if renderer?.wearingJetpack == true {mode = .jetpack}
        let canGuard=usingMelee && renderer?.canNativeFootMeleeGuard == true && network.health>0 && !network.passive
        let keyboardAim=heldKeys.contains { [NativeGameBindings.Key.delete.rawValue,NativeGameBindings.Key.caps.rawValue].contains(Int($0.rawValue)) }
        return .init(mode:mode,landingGear:renderer?.hasLandingGear == true,nozzle:renderer?.hasJetNozzle == true,
                     melee:canGuard,guarding:canGuard && (touchMeleeGuard || keyboardAim || lastGamepadAim),
                     working:currentVehicle != nil && renderer?.hasVehicleWorkingControls == true,
                     workingIsTow:renderer?.vehicleWorkingIsTow == true,hasCoupling:currentVehicle != nil && renderer?.canUnhitchVehicle == true)
    }
    private func performBinding(_ action:NativeGameBindings.Action) {
        if action == .pause {if canNavigateMenus {openPause()};return}
        guard acceptsHeldInput else{return}
        switch action {
        case .jump:jump()
        case .crouch,.dive:toggleCrouch()
        case .enter:toggleVehicle()
        case .meleeAlternate:
            if renderer?.requestFootMeleeAttack(alternate:true) != true {status.text="SPECIAL MELEE ATTACK IS NOT AVAILABLE FOR THIS PROFILE"}
        case .weaponPrevious:cycleWeapon(-1)
        case .weaponNext:cycleWeapon(1)
        case .reload:reload()
        case .action:performNearbyMissionAction()
        case .jobs:openGameplay()
        case .chat:openChat()
        case .map:openMap()
        case .animations:openAnimations()
        case .camera:cycleCameraPreference()
        case .lights:renderer?.vehicleLights.toggle()
        case .gear:toggleGear()
        case .unhitch:renderer?.releaseVehicleCoupling()
        case .radioPrevious:radio.previous();radioButton.setTitle(radio.stationName,for:.normal)
        case .radioNext:nextRadioStation()
        case .pause:openPause()
        case .attack:attack()
        }
    }
    private func cycleWeapon(_ direction:Int) {
        guard currentVehicle==nil,renderer?.isClimbing != true,renderer?.swimming != true,renderer?.isChuting != true,
              weapons.synchronized else{return}
        let rows=(gameplay.state["weaponInventory"] as? [String:Any])?["weapons"] as? [[String:Any]] ?? []
        let order=NativeGameBindings.weaponOrder(rows,owned:weapons.weapons.map(\.id))
        if let request=weaponCycle.request(direction:direction,owned:order,selected:weapons.selected) {
            sendWeaponSelection(request)
        }
    }
    private func sendWeaponSelection(_ request:NativeWeaponCycleQueue.Request) {
        renderer?.cancelWeaponInput()
        let connection=network.inventoryConnection
        gameplay.perform("weapon.select",payload:["weapon":request.weapon]) { [weak self] result in
            guard let self,self.network.inventoryConnection==connection else{return}
            let next=self.weaponCycle.complete(request.id,succeeded:result)
            if result==nil {self.network.requestInventoryResync()}
            if let next {self.sendWeaponSelection(next)}
        }
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let code=press.key?.keyCode {
                heldKeys.remove(code)
                NativeMenuKeyLatch.release(Int(code.rawValue))
                if code == .keyboardEscape {pauseEscapeHandoff?.release()}
            }
        }
        super.pressesEnded(presses, with: event)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        NativeMenuKeyLatch.reset()
        pauseEscapeHandoff?.release();resetControls(); super.pressesCancelled(presses, with: event)
    }

    init(server: ServerAddress, settings: NativeAppSettings = .shared) {
        self.server = server
        self.appSettings = settings
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
        settingsObserver = NotificationCenter.default.addObserver(forName: NativeAppSettings.didChange,
            object: nil, queue: .main) { [weak self] notification in
                guard let self, notification.object as? NativeAppSettings === self.appSettings else { return }
                self.applyAppSettings()
            }
        applyAppSettings()
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
        renderer?.onLocalImpact = { [weak self] value in self?.network.reportImpactDamage(value) }
        renderer?.onLocalHealth = { [weak self] value in self?.network.reportLocalHealth(value) }
        renderer?.onParachuteUsed = { [weak self] in self?.network.usedParachute() }
        network.onFlightGear = { [weak self] parachute,jetpack in self?.renderer?.setFlightGear(parachute:parachute,jetpack:jetpack) }
        weapons.onChange = { [weak self] in
            guard let self else { return }
            if self.guardWeapon != self.weapons.selected {self.guardWeapon=self.weapons.selected;self.touchMeleeGuard=false}
            self.renderer?.equippedWeapon = self.weapons.selected
            self.updateWeaponHUD()
        }
        weapons.onNeedsRefresh = { [weak self] in self?.gameplay.refresh() }
        weapons.onNeedsResync = { [weak self] in self?.network.requestInventoryResync() }
        network.onInventoryConnection = { [weak self] nonce in
            guard let self else{return}
            self.renderer?.setVehicleCouplingConnection(nonce)
            self.weaponCycle.disconnected()
            self.gameplay.inventoryConnection=nonce
            self.weapons.setConnection(nonce)
            self.renderer?.cancelWeaponInput();self.renderer?.cancelReloadAnimation()
        }
        network.onCouplings = { [weak self] links,revision,connection in
            guard let self,self.network.inventoryConnection==connection else{return}
            self.renderer?.applyVehicleCouplings(links,revision:revision,connection:connection)
            self.updateAuxiliaryControls()
        }
        renderer?.onCouplingRequest = { [weak self] request in self?.requestVehicleCoupling(request) ?? false }
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
        renderer?.onVehicleLostInWater = { [weak self] in self?.completeVehicleExit(water:true) }
        renderer?.onVehicleWrecked = { [weak self] in self?.completeVehicleExit(wrecked:true) }
        renderer?.onBikeEjection = { [weak self] event in self?.completeVehicleExit(ejection:event) }
        renderer?.onMeleeSwing = { [weak self] _ in self?.audio.swing() }
        renderer?.onFootMeleeHit = { [weak self] event in self?.consumeFootMeleeHit(event) ?? false }
        renderer?.onMeleeGroundTarget = { [weak self] probe in
            guard let self,let renderer=self.renderer else{return false}
            return NativeMeleeTargeting.groundTarget(probe:probe,candidates:self.meleeCandidates,
                visible:renderer.hasClearShot) != nil
        }
        network.onConnectionState = { [weak self] state in self?.connectionChanged(state) }
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
        network.onVehicleRemoved = { [weak self] id in self?.vehicleRemoved(id) }
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
            self?.updateAuxiliaryControls()
        }
        network.onRespawn = { [weak self] in self?.finishRespawn() }
        network.onIncomingHit = { [weak self] hit in self?.renderer?.receiveHit(hit) }
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
        applyAppSettings()
    }

    /// One complete snapshot applies to both display clocks and every live
    /// presentation owner. Options changes never issue gameplay/server actions.
    private func applyAppSettings() {
        guard isViewLoaded else { return }
        let snapshot = appSettings.snapshot
        let maximumFPS = (view.window?.screen ?? UIScreen.main).maximumFramesPerSecond
        let fps = snapshot.effectiveFrameRate(maximum: maximumFPS)
        renderer?.applySettings(snapshot, maximumFPS: maximumFPS)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: Float(min(30, fps)),
            maximum: Float(fps), preferred: Float(fps))
        gameHUD.radar.isHidden = !snapshot.radarVisible
        mapButton.isHidden = !snapshot.radarVisible
        gameHUD.radar.circular = snapshot.radarCircular
        gameHUD.radar.span = CGFloat(snapshot.radarSpan)
        gameHUD.radar.showWorldMarkers = snapshot.radarWorldMarkers
        audio.applySettings(snapshot)
        radio.applySettings(snapshot)
    }

    private func cycleCameraPreference() {
        guard let renderer else { return }
        renderer.cycleCameraView()
        appSettings.update {
            $0.footView = renderer.footCameraView
            $0.vehicleView = renderer.vehicleCameraView
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed || isMovingFromParent || presentingViewController?.isBeingDismissed == true {stopGame()}
    }
    private func connectionChanged(_ state:NativeMultiplayerClient.ConnectionState) {
        if state == .ready {
            resetControls();gameplay.setConnectionReady(true)
            lastNetwork=0;lastGameplay=0;gameplay.refresh()
            return
        }
        gameplay.setConnectionReady(false)
        for key in heldKeys {_ = NativeMenuKeyLatch.press(Int(key.rawValue))}
        resetControls();previousAudioPosition=nil;lastAutomaticCheckpoint.removeAll()
        renderer?.resetMultiplayerSession()
        currentVehicle=nil;setDrivingControls(false)
        vehicleButton.setTitle("ENTER CAR",for:.normal);gameHUD.updateVehicle(name:nil,speed:0)
        gameHUD.radar.target=nil;renderer?.objective=nil
        radio.stop()
        players.text=state == .stopped ? "MULTIPLAYER DISCONNECTED":"RECONNECTING TO MULTIPLAYER"
    }

    private func vehicleRemoved(_ id:String) {
        guard renderer?.removeVehicle(id:id) == true else{return}
        currentVehicle=nil
        resetControls();previousAudioPosition=nil
        setDrivingControls(false)
        vehicleButton.setTitle("ENTER CAR",for:.normal)
        gameHUD.updateVehicle(name:nil,speed:0)
        radio.stop()
    }

    private func stopGame() {
        gameplay.setConnectionReady(false)
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
            control.addTarget(self, action: control === weaponButton ? #selector(releaseNozzleUp) : #selector(releaseNozzleDown), for: [.touchUpInside,.touchUpOutside,.touchCancel])
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

    @objc private func close() {stopGame();dismiss(animated:true)}
    @objc private func openPause() {
        guard presentedViewController == nil else { return }
        let escapeState=NativeModalKeyHandoff(pressed:heldKeys.contains(.keyboardEscape))
        pauseEscapeHandoff=escapeState
        heldKeys.removeAll();firePressed = false;handbrakePressed = false
        let panel = NativePausePanel();panel.driving = currentVehicle != nil
        panel.escapeHandoff=escapeState
        panel.controlsHint=NativeGameBindings.legend(bindingContext)
        panel.cameraName = { [weak self] in self?.renderer?.cameraViewName ?? "middle" }
        panel.onJobs = { [weak self] in self?.openGameplay() }
        panel.onCamera = { [weak self] in self?.cycleCameraPreference() }
        panel.onMap = { [weak self] in self?.openMap() }
        panel.onOptions = { [weak self] in self?.openOptions() }
        panel.onAnimations = { [weak self] in self?.openAnimations() }
        panel.onRadio = { [weak self] in self?.nextRadioStation() }
        panel.onFlightGear = { [weak self] in self?.openFlightEquipment() }
        panel.weatherName = { [weak self] in self?.renderer?.weatherAuto == true ? "REGIONAL AUTO" : "SERVER" }
        panel.onWeather = { [weak self] in
            self?.appSettings.update { $0.regionalWeather.toggle() }
        }
        panel.onLeave = { [weak self] in self?.close() }
        panel.modalPresentationStyle = .overFullScreen;present(panel,animated:true)
    }
    @objc private func openOptions() {
        guard presentedViewController == nil else { return }
        let options = NativeOptionsViewController(settings: appSettings)
        options.modalPresentationStyle = .overFullScreen
        present(options, animated: true)
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
    @objc private func jump() {
        guard !(bindingContext.melee && bindingContext.guarding) else{return}
        renderer?.jump()
    }
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
        aimButton.isHidden = currentVehicle != nil || ((!usingPistol || usingMelee) && renderer?.canNativeFootMeleeGuard != true)
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
        updateAuxiliaryControls()
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
        if driving {updateAuxiliaryControls()}else{updateWeaponHUD()}
        if driving { setAiming(false); firePressed = false }
        if !driving { gasPressed = false; brakePressed = false; handbrakePressed = false }
        hornPressed = false;nozzleUpPressed = false;nozzleDownPressed = false
    }

    /// Metadata and confirmed links can arrive after entry. Refresh only the
    /// contextual controls; setDrivingControls owns the one-time input reset.
    private func updateAuxiliaryControls() {
        let driving=currentVehicle != nil,working=driving && renderer?.hasVehicleWorkingControls == true
        let nozzle=driving && !working && renderer?.hasJetNozzle == true
        let tow=working && renderer?.vehicleWorkingIsTow == true
        let mode="\(currentVehicle?.id ?? "foot"):\(working ? (tow ? "tow":"working") : nozzle ? "nozzle":"normal")"
        if mode != auxiliaryMode {
            auxiliaryMode=mode;nozzleUpPressed=false;nozzleDownPressed=false
            renderer?.vehicleWorkingControl=0;renderer?.vehicleJetControl=0
        }
        let dead=network.health<=0
        if driving {
            let bicycle=renderer?.vehicleKind == "bicycle",unhitch=renderer?.canUnhitchVehicle == true
            weaponButton.isHidden = !working && !nozzle
            reloadButton.isHidden = !working && !nozzle
            aimButton.isHidden = bicycle
            crouchButton.isHidden = !unhitch && renderer?.hasLandingGear != true
            attackButton.isHidden = !dead && !bicycle && renderer?.hasVehicleHorn != true
            styleControl(crouchButton,icon:nil,fallback:unhitch ? "link":"airplane.circle",
                         accessibility:unhitch ? "Unhitch vehicle":"Toggle landing gear")
            styleControl(aimButton,icon:nil,fallback:"light.max",accessibility:"Toggle vehicle lights")
            styleControl(attackButton,icon:nil,fallback:dead ? "arrow.clockwise":bicycle ? "arrow.up.circle.fill":"speaker.wave.2.fill",
                         accessibility:dead ? "Respawn":bicycle ? "Hold and release bunny hop":"Hold horn")
            if working {
                styleControl(weaponButton,icon:nil,fallback:"arrow.up",accessibility:tow ? "Hold to raise tow bar":"Hold to raise working part")
                styleControl(reloadButton,icon:nil,fallback:"arrow.down",accessibility:tow ? "Hold to lower tow bar":"Hold to lower working part")
            } else if nozzle {
                styleControl(weaponButton,icon:nil,fallback:"arrow.up.right",accessibility:"Hold to rotate jets forward")
                styleControl(reloadButton,icon:nil,fallback:"arrow.down",accessibility:"Hold to rotate jets downward")
            }
            return
        }
        let deploy=renderer?.isChuting == true,detonator=weapons.selected==40
        let canGuard=renderer?.canNativeFootMeleeGuard == true
        weaponButton.isHidden=false
        reloadButton.isHidden = dead || deploy || !usingPistol || (weapons.selected != 39 && (magazine>=weapons.current.capacity || reserve==0))
        aimButton.isHidden = dead || deploy || (!canGuard && (!usingPistol || renderer?.supportsFootWeaponAim != true))
        crouchButton.isHidden=false
        attackButton.isHidden = !dead && !deploy && !detonator && !weapons.current.supportsAttack
        styleControl(crouchButton,icon:nil,fallback:"arrow.down.to.line",accessibility:"Toggle crouch")
        styleControl(aimButton,icon:nil,fallback:"viewfinder",accessibility:canGuard ? "Toggle melee guard":"Toggle aim")
        styleControl(attackButton,icon:usingPistol && !dead && !deploy ? "Touch_fire":nil,
                     fallback:dead ? "arrow.clockwise":deploy ? "arrow.up.forward.circle":detonator ? "bolt.circle":usingPistol ? "scope":"hand.raised.fingers.spread.fill",
                     accessibility:dead ? "Respawn":deploy ? "Open parachute":detonator ? "Detonate planted satchels":usingPistol ? "Fire":"Hit")
        attackButton.setTitle(dead ? "RESPAWN":deploy ? "DEPLOY":detonator ? "DETONATE":usingPistol ? "FIRE":"HIT",for:.normal)
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
        if currentVehicle != nil && (renderer?.hasJetNozzle == true || renderer?.hasVehicleWorkingControls == true) { return }
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
        if renderer?.canNativeFootMeleeGuard == true {
            touchMeleeGuard.toggle();setAiming(false)
            aimButton.backgroundColor=UIColor.black.withAlphaComponent(touchMeleeGuard ? 0.7:0.3)
        } else {setAiming(usingMelee ? false:!aiming)}
    }
    @objc private func toggleGear() { if renderer?.hasLandingGear == true { renderer?.toggleLandingGear() } }
    @objc private func pressNozzleUp() { if acceptsHeldInput && currentVehicle != nil && (renderer?.hasJetNozzle == true || renderer?.hasVehicleWorkingControls == true) { nozzleUpPressed = true } }
    @objc private func pressNozzleDown() { if acceptsHeldInput && currentVehicle != nil && (renderer?.hasJetNozzle == true || renderer?.hasVehicleWorkingControls == true) { nozzleDownPressed = true } }
    @objc private func releaseNozzleUp() { nozzleUpPressed = false }
    @objc private func releaseNozzleDown() { nozzleDownPressed = false }
    @objc private func toggleCrouch() {
        if currentVehicle != nil {if renderer?.canUnhitchVehicle == true {renderer?.releaseVehicleCoupling()}else{toggleGear()};return}
        guard currentVehicle == nil, let renderer, network.health > 0 else { return }
        renderer.toggleCrouch()
        crouchButton.backgroundColor = UIColor.black.withAlphaComponent(renderer.crouching ? 0.7 : 0.3)
    }
    private func setAiming(_ value: Bool) {
        aiming = value && usingPistol && !usingMelee && renderer?.supportsFootWeaponAim == true && currentVehicle == nil && renderer?.isClimbing != true && renderer?.swimming != true && renderer?.isChuting != true
        renderer?.aiming = aiming
        gameHUD.setAiming(aiming, scoped: weapons.selected == 34)
        aimButton.backgroundColor = UIColor.black.withAlphaComponent(aiming ? 0.7 : 0.3)
    }
    @objc private func pressFire() {
        guard acceptsHeldInput else { return }
        if currentVehicle != nil && network.health>0 {
            if renderer?.vehicleKind == "bicycle" {bunnyHopPressed=true}else{hornPressed = true}
            return
        }
        firePressed = true;attack()
    }
    @objc private func releaseFire() { firePressed = false;hornPressed = false;bunnyHopPressed=false }

    @objc private func reload() {
        guard acceptsHeldInput else{return}
        guard currentVehicle == nil,renderer?.isClimbing != true,renderer?.swimming != true,renderer?.isChuting != true else { return }
        if weapons.selected == 39 { network.detonateSatchels(); return }
        guard usingPistol else { return }
        guard !weapons.reloading, magazine < weapons.current.capacity, reserve > 0 else { return }
        let requestID=weapons.beginReloadRequest()
        let connection=network.inventoryConnection
        var dispatchReturned=false,synchronouslyRejected=false
        gameplay.perform("weapon.reload") { [weak self] result in
            guard let self else{return}
            guard self.network.inventoryConnection==connection else{return}
            self.weapons.finishReloadRequest(id:requestID,succeeded:result)
            if result == false {
                if !dispatchReturned {synchronouslyRejected=true}
                self.renderer?.cancelReloadAnimation()
            }
        }
        dispatchReturned=true
        guard !synchronouslyRejected,acceptsHeldInput,network.inventoryConnection==connection else{return}
        let clips = NativeWeaponAnimation.forWeapon(weapons.selected)
        renderer?.fireWeapon(clip: renderer?.crouching == true ? clips.crouchReload : clips.reload, duration: 1.8)
        audio.reload(weapon: weapons.selected)
        updateWeaponHUD()
        status.text = "RELOADING \(weapons.current.name.uppercased())"
    }

    @objc private func attack() {
        guard acceptsHeldInput, !weaponCycle.busy else { return }
        guard let renderer else { return }
        if currentVehicle != nil && network.health > 0 { return }
        if network.health == 0 {
            status.text = "RESPAWN REQUESTED"
            network.respawn()
            return
        }
        if renderer.isChuting {renderer.openParachute();return}
        guard currentVehicle == nil else { status.text = "EXIT THE VEHICLE TO FIGHT"; return }
        guard !network.passive else { status.text = "TURN OFF PASSIVE MODE TO FIGHT"; return }
        guard !renderer.swimming,!renderer.isClimbing else { return }
        if weapons.selected==40 {
            guard weapons.synchronized,renderer.canUseFootUtility else{return}
            network.detonateSatchels();return
        }
        if usingPistol && renderer.hasNativeFootWeaponTiming {
            _ = renderer.requestFootWeaponFire()
            return
        }
        if weapons.current.isMelee {
            // Damage belongs to the accepted animation's hit marker. A rejected
            // request, missing definition or a buffered press cannot hit early.
            guard weapons.canFire,renderer.hasNativeFootMeleeTiming else{return}
            _ = renderer.requestFootMeleeAttack()
            return
        }
        // Unsupported jetpack weapon types must not fall back to wall-clock
        // firing through the flight animation. Armed flight is capability-gated.
        guard !renderer.wearingJetpack else { return }
        guard renderer.canRequestFootWeaponFire,weapons.current.supportsAttack else{return}
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastAttackTime >= weapons.current.interval,let ray=currentShotRay(weapon:weapons.selected,left:false),let ticket=network.reserveShot(),weapons.fire(ticket:ticket) else { return }
        lastAttackTime = now
        if usingPistol {
            updateWeaponHUD()
            let clips = NativeWeaponAnimation.forWeapon(weapons.selected)
            renderer.fireWeapon(clip: weapons.current.fireKind == "PROJECTILE" ? "grenade/weapon_throw/n/1" : renderer.crouching ? clips.crouchFire : clips.fire,
                                duration: weapons.current.fireKind == "PROJECTILE" ? 0.8 : Float(weapons.current.interval))
            emitWeaponShot(weapon: weapons.selected, left: false,ticket:ticket,ray:ray)
            return
        }
    }

    private var meleeCandidates:[NativeMeleeTargeting.Candidate] {
        network.orderedPlayers.filter {$0.code.hasPrefix("s") && $0.ridingVehicleID == nil}.map {
            .init(id:$0.id,feet:$0.position,heading:$0.heading,crouching:$0.crouching,
                down:$0.down != 0,dead:$0.life <= 0)
        }
    }

    private func finishRespawn() {
        resetControls()
        if currentVehicle != nil {
            currentVehicle=nil
            renderer?.exitVehicle()
            vehicleButton.setTitle("ENTER CAR",for:.normal)
            setDrivingControls(false);radio.stop()
        }
        renderer?.teleport(x:1480,y:-1738,z:13)
        status.text="RESPAWNED AT THE CITY CENTRE"
    }

    private func consumeFootMeleeHit(_ event:NativeMeleeEvent)->Bool {
        guard let renderer,applicationActive,presentedViewController == nil,currentVehicle == nil,!weaponCycle.busy,
              network.health>0,!network.passive,!renderer.swimming,!renderer.isChuting,
              renderer.hasNativeFootMeleeTiming,weapons.selected==event.weapon,weapons.current.isMelee,weapons.canFire,
              renderer.canEmitFootCombatMarker,
              network.recordMeleeStrike(weapon:event.weapon) else{return false}
        // A valid miss still advances the remote animation counter. Damage
        // remains conditional on a selected visible victim and live transport.
        guard let target=NativeMeleeTargeting.select(event:event,candidates:meleeCandidates,visible:renderer.hasClearShot),
              network.sendMeleeHit(to:target.id,weapon:event.weapon) else{return true}
        audio.meleeHit()
        status.text="MELEE ATTACK ON \(network.players[target.id]?.name.uppercased() ?? "PLAYER")"
        return true
    }

    private func consumeFootWeaponShot(weapon: Int, left: Bool)->Bool {
        guard let renderer, applicationActive, presentedViewController == nil, currentVehicle == nil, !weaponCycle.busy,
              network.health > 0, !network.passive, !renderer.swimming, !renderer.isChuting,
              renderer.hasNativeFootWeaponTiming, weapons.selected == weapon, usingPistol,
              renderer.canEmitFootWeaponShot,
              let ray=currentShotRay(weapon:weapon,left:left),let ticket=network.reserveShot() else { return false }
        return NativeWeaponShotDelivery.deliver(weapon: weapon, left: left,ticket:ticket, inventory: weapons,
            readiness: { renderer.weaponReady = $0 }, emission: { [self] weapon, left,ticket in
                updateWeaponHUD()
                emitWeaponShot(weapon: weapon, left: left,ticket:ticket,ray:ray)
            })
    }

    /// Freeze valid geometry before reserving/spending a ticket. Emission is
    /// synchronous, so both hands retain their own event-time ray snapshot.
    private func currentShotRay(weapon:Int,left:Bool)->NativeShotTargeting.Ray? {
        guard let renderer,let muzzle=renderer.weaponMuzzle(weapon:weapon,left:left) else{return nil}
        // Do not spawn a shot past a wall merely because an extended barrel
        // crossed it. Retain the existing safe body origin in that case.
        let clear=simd_distance(muzzle.safetyOrigin,muzzle.origin)<0.0001 ||
            renderer.hasClearShot(from:muzzle.safetyOrigin,to:muzzle.origin)
        return .init(origin:clear ? muzzle.origin:muzzle.safetyOrigin,
                     direction:renderer.aimDirection,range:weapons.current.range)
    }

    /// Shared effects/network emission uses the captured event-time hand muzzle.
    /// Unavailable or wall-obstructed poses retain the safe body-origin fallback.
    /// Animation-event firing never restarts a clip here.
    private func emitWeaponShot(weapon: Int, left: Bool,ticket:NativeShotTicket,ray:NativeShotTargeting.Ray) {
        guard let renderer, weapons.selected == weapon else { return }
        renderer.recordWeaponShot(weapon:weapon,origin:ray.origin,direction:ray.direction)
        if weapons.current.fireKind == "PROJECTILE" {
            network.sendWeaponShot(weapon: weapon, from: ray.origin,
                to: ray.point(at:max(5,min(100,ray.range))), player: nil,ticket:ticket)
            return
        }
        audio.shot(weapon: weapon)
        if NativeStreamShotTargets.weapons.contains(weapon) {
            let candidates=network.orderedPlayers.map {
                NativeShotTargeting.Candidate(id:$0.id,point:$0.position+SIMD3(0,0,0.9))
            }
            let targets=NativeStreamShotTargets.players(ray:ray,candidates:candidates,
                visible:{renderer.hasClearShot(from:$0,to:$1)})
            network.sendWeaponShot(weapon:weapon,from:ray.origin,to:ray.end,player:nil,ticket:ticket,streamPlayers:targets)
            return
        }
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
        guard acceptsHeldInput else{return}
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

    private func sendCurrentPosition(moving:Bool,running:Bool,tuck:Double,paused:Bool) {
        guard network.isReady,let renderer else{return}
            network.sendPosition(currentVehicle == nil ? renderer.position : renderer.vehicleWirePosition, heading: renderer.direction, moving: moving,
                                 running: running,
                                 vehicle: currentVehicle, speed: renderer.drivingSpeed,
                                 steer: renderer.steeringInput,
                                 pitch:currentVehicle == nil ? renderer.personalFlightPitch:renderer.vehicleNose,
                                 roll:currentVehicle == nil ? renderer.personalFlightRoll:renderer.vehicleRoll,
                                 vehicleHealth: renderer.vehicleHealth,
                                 vehicleDamage:renderer.vehicleDamage,lights:renderer.vehicleLights,horn:renderer.vehicleHorn,siren:renderer.vehicleSiren,
                                 airborne: renderer.footWireAirborne, weapon:renderer.effectiveWireWeapon,
                                 firing: renderer.isFiring, animation: renderer.footWireAnimation,
                                 crouching: renderer.crouching,swimState: renderer.swimmingState,
                                 swimPitch: renderer.swimmingPitch,swimRatio: renderer.swimmingRatio,
                                 movement:renderer.footWireMovementRatio,aim:renderer.footWireAim,
                                 action:currentVehicle != nil ? renderer.riderWireAction:renderer.footWireAction,
                                 velocity:renderer.currentWireVelocity,angularVelocity:renderer.currentWireAngularVelocity,
                                 kit:renderer.vehicleWireKit(tuck:tuck),vehicleWork:renderer.vehicleWorkingValue,paused:paused,support:renderer.footWireSupport,down:renderer.footWireDown)
    }

    private func requestVehicleCoupling(_ request:NativeVehicleCoupling.Request)->Bool {
        // A broken physical constraint must still be released while a menu
        // covers player input. Attaching a new target remains an input action.
        let detaching=request.trailer==nil
        guard (detaching || acceptsHeldInput),network.isReady,network.health>0,
              network.couplingAcknowledgements,network.couplingRevision != nil,
              let vehicle=currentVehicle,let renderer,let connection=network.inventoryConnection else{return false}
        var moves:[(String,[String:Any])]=[]
        for id in [Optional(request.parent),request.trailer].compactMap({$0}) where id != vehicle.id {
            guard let packet=renderer.vehicleCouplingMovePacket(id) else{return false}
            moves.append((id,packet))
        }
        // Snapshot the current physics frame before any callback can observe
        // a hitch. Ordinary200ms position publication is not acquisition data.
        sendCurrentPosition(moving:renderer.drivingSpeed>0.05,running:false,tuck:vehicleTuck,paused:!acceptsHeldInput)
        for (id,packet) in moves {
            guard (detaching || acceptsHeldInput),network.isReady,network.health>0,
                  network.inventoryConnection==connection,currentVehicle?.id==vehicle.id else{return false}
            network.sendVehicleMove(id,state:packet)
        }
        guard (detaching || acceptsHeldInput),network.isReady,network.health>0,
              network.inventoryConnection==connection,currentVehicle?.id==vehicle.id else{return false}
        return network.requestCoupling(parent:request.parent,trailer:request.trailer,kind:request.kind.rawValue) { [weak self] accepted in
            guard let self,self.network.inventoryConnection==connection else{return}
            if !accepted {self.renderer?.rejectVehicleCoupling(request)}
        }
    }

    private func completeVehicleExit(ejection:NativeBikeEjection.Event?=nil,wrecked:Bool=false,water:Bool=false) {
        guard let renderer,currentVehicle != nil else{return}
        let parked = renderer.vehicleWirePosition, heading = renderer.direction
        let pitch = renderer.vehicleNose, roll = renderer.vehicleRoll
        let damage = renderer.vehicleDamage,work=renderer.vehicleWorkingValue,health=renderer.vehicleHealth
        guard renderer.exitVehicle(ejection:ejection,wrecked:wrecked,water:water) else {
            let vehicleID=currentVehicle?.id
            renderer.deferVehicleExit { [weak self,weak renderer] in
                guard let self,let renderer,self.renderer === renderer,self.currentVehicle?.id==vehicleID else{return}
                self.completeVehicleExit(ejection:ejection,wrecked:wrecked,water:water)
            }
            return
        }
        if let currentVehicle {
            network.sendExit(renderer.position, parked: parked, heading: heading, pitch: pitch, roll: roll,
                             vehicle: currentVehicle, vehicleHealth:health,vehicleDamage:damage,vehicleWork:work,
                             footHeading:renderer.direction)
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
        network.tickConnection(now:ProcessInfo.processInfo.systemUptime)
        let active = applicationActive && view.window != nil
        let timing = frameClock.advance(timestamp: link.timestamp, active: active)
        if timing.discontinuity { resetControls() }
        let delta = Float(timing.delta)
        weapons.tick()
        var acceptsInput = active && presentedViewController == nil && network.isReady
        if !acceptsInput && inputWasAvailable { resetControls() }
        inputWasAvailable = acceptsInput
        // Over-full-screen panels leave the game visible, so UIKit does not
        // always repeat viewDidAppear when keyboard input should resume.
        if acceptsInput,view.window != nil,!isFirstResponder { becomeFirstResponder() }
        if acceptsInput && firePressed && weapons.selected != 40 && renderer?.hasNativeFootWeaponTiming != true && renderer?.hasNativeFootMeleeTiming != true { attack() }
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
        let context=bindingContext
        let keyboard=NativeGameBindings.keyboard(Set(heldKeys.map {Int($0.rawValue)}),context:context)
        var horn = currentVehicle != nil && (hornPressed || keyboard.horn)
        var jets: Float = context.nozzle && !context.working ? (nozzleUpPressed ? 1:0)-(nozzleDownPressed ? 1:0):0
        var working=NativeGameBindings.workingControl(context:context,keyboard:keyboard.working,
            touchRaise:nozzleUpPressed,touchLower:nozzleDownPressed)
        if keyboard.moving {forward=keyboard.forward;if currentVehicle==nil {sideways=keyboard.sideways}}
        if context.aircraft {sideways=keyboard.sideways}
        if keyboard.steeringKeys {steering=keyboard.steering}
        if keyboard.pitchKeys {lookVertical=keyboard.pitch}
        if context.nozzle,!context.working,keyboard.nozzle != 0 {jets=keyboard.nozzle}
        renderer?.cameraLookDirection=keyboard.look
        let helicopter = currentVehicle != nil && renderer?.vehicleKind == "helicopter"
        if helicopter && keyboard.moving {lift=keyboard.forward;forward=0}
        var gamepadRunning = false
        var gamepadHop=false
        var gamepadJumping = false
        var gamepadAttacking = keyboard.attack
        let controller = GCController.controllers().compactMap(\.extendedGamepad).first
        var controllerAllowed = false
        if let pad = controller {
            let pressed = [pad.buttonA,pad.buttonB,pad.buttonX,pad.buttonY,pad.leftShoulder,pad.rightShoulder,
                           pad.dpad.up,pad.dpad.down,pad.dpad.left,pad.dpad.right,pad.buttonMenu].contains { $0.isPressed } ||
                pad.leftThumbstickButton?.isPressed == true || pad.rightThumbstickButton?.isPressed == true || pad.buttonOptions?.isPressed == true
            controllerAllowed = controllerGate.accepts(active: active && presentedViewController == nil,
                axes: [pad.leftThumbstick.xAxis.value,pad.leftThumbstick.yAxis.value,pad.rightThumbstick.xAxis.value,
                       pad.rightThumbstick.yAxis.value,pad.leftTrigger.value,pad.rightTrigger.value], pressed: pressed)
        } else { controllerGate.reset() }
        if controllerAllowed, let pad = controller {
            let buttons=NativeGameBindings.Pad(a:pad.buttonA.isPressed,b:pad.buttonB.isPressed,x:pad.buttonX.isPressed,y:pad.buttonY.isPressed,
                lb:pad.leftShoulder.isPressed,rb:pad.rightShoulder.isPressed,leftClick:pad.leftThumbstickButton?.isPressed == true,
                rightClick:pad.rightThumbstickButton?.isPressed == true,menu:pad.buttonMenu.isPressed,options:pad.buttonOptions?.isPressed == true,
                up:pad.dpad.up.isPressed,down:pad.dpad.down.isPressed,left:pad.dpad.left.isPressed,right:pad.dpad.right.isPressed)
            var padContext=context
            padContext.guarding=context.melee && (touchMeleeGuard || keyboard.aim || pad.leftTrigger.isPressed)
            let actions=NativeGameBindings.padActions(buttons,previous:previousPad,context:padContext)
            previousPad=buttons
            for action in actions {performBinding(action);if presentedViewController != nil {break}}
            if let direction=NativeGameBindings.padLook(buttons,context:context) {renderer?.cameraLookDirection=direction}
            working=NativeGameBindings.workingControl(context:context,keyboard:keyboard.working,
                touchRaise:nozzleUpPressed,touchLower:nozzleDownPressed,pad:buttons)
            let left = NativeInputMath.stick(x: pad.leftThumbstick.xAxis.value, y: pad.leftThumbstick.yAxis.value)
            let lx = left.x, ly = left.y
            if abs(lx) + abs(ly) > 0.05 { forward = ly; sideways = lx }
            let right = NativeInputMath.stick(x: pad.rightThumbstick.xAxis.value, y: pad.rightThumbstick.yAxis.value)
            let rx = right.x
            if abs(rx) > 0.05 { if currentVehicle != nil { cameraLookX = rx } else { steering = rx } }
            let ry = right.y
            if abs(ry) > 0.05 { if currentVehicle != nil { cameraLookY = ry } else { lookVertical = ry } }
            gamepadRunning = pad.buttonA.isPressed && context.mode != .vehicle("bicycle")
            gamepadHop = pad.buttonA.isPressed && context.mode == .vehicle("bicycle")
            gamepadJumping = pad.buttonX.isPressed
            if currentVehicle != nil {
                if abs(ly)>0.05 || !keyboard.pitchKeys {lookVertical=ly}
                if abs(lx)>0.05 || !keyboard.steeringKeys {steering=lx}
                let rudder:Float=(pad.rightShoulder.isPressed ? 1:0)-(pad.leftShoulder.isPressed ? 1:0)
                if rudder != 0 || keyboard.sideways==0 {sideways=rudder}
                horn = horn || (buttons.leftClick && !context.landingGear)
                if context.nozzle && !context.working { jets = (pad.dpad.left.isPressed ? 1:0)-(pad.dpad.down.isPressed ? 1:0) }
                let throttle = pad.rightTrigger.value
                let braking = pad.leftTrigger.value
                if helicopter {
                    if throttle > 0.05 || braking > 0.05 { lift = throttle - braking }
                } else {
                    if throttle > 0.05 || braking > 0.05 { forward = throttle - braking }
                    else if !keyboard.moving { forward = 0 }
                }
            } else {
                gamepadAttacking = gamepadAttacking || pad.rightTrigger.isPressed || (pad.buttonB.isPressed && context.mode != .swim && context.mode != .climb)
            }
        }
        acceptsInput = acceptsInput && presentedViewController == nil
        let heldAim=acceptsInput && (keyboard.aim || (controllerAllowed && controller?.leftTrigger.isPressed == true))
        let guardHeld=acceptsInput && context.melee && (touchMeleeGuard || heldAim)
        renderer?.meleeGuardHeld=guardHeld
        renderer?.meleeBlockHeld=guardHeld && (handbrakePressed || gamepadJumping || keyboard.jump) && !(firePressed || gamepadAttacking)
        if let cameraAim=NativeGameBindings.cameraAimUpdate(held:heldAim,previousHeld:lastGamepadAim,melee:usingMelee,current:aiming) {setAiming(cameraAim)}
        if guardHeld {aimButton.backgroundColor=UIColor.black.withAlphaComponent(0.7)}
        lastGamepadAim=heldAim

        // Opening a panel from a controller during this frame must suppress the
        // same frame's remaining jump/fire/movement commands too.
        acceptsInput = acceptsInput && presentedViewController == nil
        if !acceptsInput {
            gamepadJumping = false; gamepadAttacking = false;gamepadHop=false
            renderer?.cameraLookDirection=nil
        }
        // Pad jump edges are dispatched by padActions; keyboard edges by pressesBegan.
        lastJumpButton = gamepadJumping
        let hornState=audio.vehicleHornInput(model:currentVehicle.flatMap{Int($0.code.split(separator:".").first ?? "")},
            identity:currentVehicle?.id,pressed:acceptsInput && horn && renderer?.hasVehicleHorn == true,milliseconds:link.timestamp*1000)
        renderer?.vehicleHorn=hornState.horn;renderer?.vehicleSiren=hornState.siren
        renderer?.vehicleJetControl = acceptsInput ? jets:0
        renderer?.vehicleWorkingControl = acceptsInput && network.health>0 ? working:0
        renderer?.vehicleHop = acceptsInput && context.mode == .vehicle("bicycle") && (bunnyHopPressed || gamepadHop || keyboard.hop)
        if NativeGameBindings.shouldRequestAttack(held:gamepadAttacking,wasHeld:lastAttackButton,
            nativeGun:renderer?.hasNativeFootWeaponTiming == true,nativeMelee:renderer?.hasNativeFootMeleeTiming == true,
            edgeOnlyUtility:weapons.selected==40) {attack()}
        lastAttackButton = gamepadAttacking
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
        let running = acceptsInput && (run || gamepadRunning || keyboard.sprint)
        renderer?.walkHeld = acceptsInput && currentVehicle == nil && keyboard.walk
        if currentVehicle != nil { renderer?.lookCamera(x:cameraLookX,y:cameraLookY,delta:delta) }
        renderer?.vehicleHandbrake = acceptsInput && currentVehicle != nil &&
            (handbrakePressed || gamepadJumping || keyboard.handbrake)
        renderer?.vehicleControllerInput = GCController.controllers().contains { $0.extendedGamepad != nil }
        renderer?.personalFlightDown=acceptsInput && (handbrakePressed || gamepadJumping || keyboard.jump)
        renderer?.jumpHeld=acceptsInput && (handbrakePressed || gamepadJumping || keyboard.jump)
        renderer?.personalFlightBrake=acceptsInput && (flightBrakePressed || keyboard.flightBrake)
        vehicleTuck=acceptsInput ? Double(lookVertical):0
        if renderer?.isClimbing == true && aiming {setAiming(false)}
        let canFight = acceptsInput && !weaponCycle.busy && currentVehicle == nil && renderer?.isClimbing != true && network.health > 0 && !network.passive &&
            renderer?.swimming != true && renderer?.isChuting != true &&
            (renderer?.wearingJetpack != true || renderer?.hasNativeFootWeaponTiming == true || renderer?.hasNativeFootMeleeTiming == true)
        if !canFight { renderer?.cancelWeaponInput() }
        renderer?.weaponTriggerHeld = canFight && (firePressed || gamepadAttacking)
        renderer?.weaponReloading = weapons.reloading
        renderer?.weaponReady = weapons.canFire && !weaponCycle.busy
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
            updateAuxiliaryControls()
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
        if network.isReady, link.timestamp - lastNetwork > 0.2 {
            lastNetwork = link.timestamp
            sendCurrentPosition(moving:walking,running:running,tuck:Double(lookVertical),paused:!acceptsInput)
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

