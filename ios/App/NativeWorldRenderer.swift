import Foundation
import MetalKit
import simd

/// Renders the locally hosted WRL2 world directly with Metal. Game meshes and
/// texture atlases stay on the Mac; the app fetches only visible cells.
final class NativeWorldRenderer: NSObject, MTKViewDelegate {
    private struct Uniforms {
        var viewProjection: simd_float4x4
        var settings: SIMD4<Float>
        var fogColor = SIMD4<Float>(0.54, 0.70, 0.81, 1)
        var fogSettings = SIMD4<Float>(1000, 2500, 0, 0)
        var tintColor = SIMD4<Float>(1,1,1,1)
    }
    private struct AtmosphereUniforms {
        var matrix: simd_float4x4
        var atlas: SIMD4<Float>
    }
    private struct DomeUniforms {
        var inverseMatrix: simd_float4x4
        var eye: SIMD4<Float>
        var forward: SIMD4<Float>
        var high: SIMD4<Float>
        var low: SIMD4<Float>
        var below: SIMD4<Float>
        var settings: SIMD4<Float>
    }
    private struct WaterUniforms {
        var matrix: simd_float4x4
        var eye: SIMD4<Float>
        var tint: SIMD4<Float>
        var alphas: SIMD4<Float>
        var shifts: SIMD4<Float>
        var waves: SIMD4<Float>
        var fogColor: SIMD4<Float>
        var fog: SIMD4<Float>
        var net: SIMD4<Float>
        var alongX0: SIMD4<Float>
        var alongX1: SIMD4<Float>
        var alongY0: SIMD4<Float>
        var alongY1: SIMD4<Float>
    }

    private struct Mesh {
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let indexCount: Int
        let atlas: MTLTexture
    }
    private struct ActorPart: Decodable {
        let name: String
        let start: Int
        let count: Int
        let wheel: String?
        let pivot: [Float]
    }
    private struct ActorParts: Decodable {
        let parts: [ActorPart]
        let driverSeat: [Float]?
        let driverDoor: [Float]?
    }
    private struct CameraVehicleDefinition: Decodable {
        struct Bounds: Decodable {
            struct Box: Decodable { let min: [Float];let max: [Float] }
            let maxX: Float;let minY: Float;let maxZ: Float;let box: Box?
        }
        let kind: String;let origin: Float;let bounds: Bounds;let driverEye: [Float]?
    }
    private struct CameraVehicleDocument: Decodable { let models: [String:CameraVehicleDefinition] }

    private struct VehicleHandling {
        let maxVelocity: Float
        let acceleration: Float
        let brakes: Float
        let lock: Float
        let traction: Float
        let drag: Float
        let flags: Int

        init?(row: [Any]) {
            guard row.count > 23,
                  let maxVelocity = (row[0] as? NSNumber)?.floatValue,
                  let acceleration = (row[1] as? NSNumber)?.floatValue,
                  let brakes = (row[2] as? NSNumber)?.floatValue,
                  let lock = (row[3] as? NSNumber)?.floatValue,
                  let traction = (row[4] as? NSNumber)?.floatValue,
                  let drag = (row[8] as? NSNumber)?.floatValue,
                  let flags = (row[23] as? NSNumber)?.intValue else { return nil }
            self.maxVelocity = maxVelocity
            self.acceleration = acceleration
            self.brakes = brakes
            self.lock = lock
            self.traction = traction
            self.drag = drag
            self.flags = flags
        }

        // The archived client's 23895 module derives its wheel-speed limit
        // from these handling rows. Convert its normalized limit to m/s.
        var roadTopSpeed: Float {
            let drive = 0.00016 * acceleration
            let threshold = drive / 6
            var speed = maxVelocity * 0.00555556
            while speed > 0 {
                speed -= 0.01
                if drag >= 0.01 {
                    if speed * speed * (drag / 2) / 1000 <= threshold { break }
                } else if -(1 / (speed * speed * drag + 1) - 1) * speed <= threshold {
                    break
                }
            }
            let limit = max(0, speed)
            let normalized = flags & 0x1000000 != 0 ? limit : limit * 1.2
            return max(5, normalized * 50)
        }
    }

    let view: MTKView
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let animatedPipeline: MTLRenderPipelineState
    private let skeletalPipeline: MTLRenderPipelineState?
    private let skyPipeline: MTLRenderPipelineState?
    private let atmospherePipelines: [String: MTLRenderPipelineState]
    private let waterPipeline: MTLRenderPipelineState?
    private let skyDepth: MTLDepthStencilState
    private let depth: MTLDepthStencilState
    private let markerDepth: MTLDepthStencilState
    private let textureLoader: MTKTextureLoader
    private var meshes: [String: Mesh] = [:]
    private var actorMeshes: [String: Mesh] = [:]
    private var actorParts: [String: [ActorPart]] = [:]
    private var vehicleSeats: [String: SIMD3<Float>] = [:]
    private var pedestrianAnchors: [String: [String: [Float]]] = [:]
    private var seating: NativeVehicleSeating?
    private lazy var character = groundVehicle.flatMap { NativeCharacterController(world: $0.world) }
    private var characterActive = false
    private var pendingNativeJump: Double = 0
    private let swimController = NativeSwimController()
    private let sprintController = NativeSprintController()
    private var stamina = NativeStamina()
    private var sprintWasHeld = false
    private var pendingSprintTap = false
    private var pendingDive = false
    private var pendingSwimJump = false
    private var lastFootVelocity = SIMD3<Double>.zero
    private var swimAnimation = ""
    private var swimAnimationElapsed: Double = 0
    private var swimHeadingTarget: Float = 0
    private var entryStarted: Double = 0
    private var entryOrigin = SIMD3<Float>.zero
    private var actorAnimations: [String: NativeActorAnimation] = [:]
    private var skeletalActors: [String: NativeSkeletalActor] = [:]
    private var skeletalLibrary: NativeSkeletalAnimationLibrary?
    private var footDefinitions: NativeFootAnimationDefinitions?
    private var footWeaponDefinitions: [Int: NativeFootWeaponAnimation] = [:]
    private var footAnimator: NativeFootAnimation?
    private let footLocomotion = NativeFootLocomotion()
    private var footAnimationFrame: NativeFootAnimation.Frame?
    private var footAnimationModel = ""
    private var footAirTime: Double = 0
    private var footAirFall: Double = 0
    private var footAirFell = false
    private var footJumped = false
    private var footJumpMinimum: Double = 0
    private var footAirVelocity = SIMD2<Double>.zero
    private var footSprintPace: Double = 0
    private var footLaunchRemaining: Double?
    private var footReloadWasActive = false
    private var footReloadRequested = false
    private var actorAttachments: [String: NativeActorAttachment] = [:]
    private var actorLoading: Set<String> = []
    private var objectiveMarker: Mesh?
    private var waterMesh: Mesh?
    private let weaponEffects = NativeWeaponEffects()
    private var effectAtlas: MTLTexture?
    private var effectSprites: [String: Int] = [:]
    private var blasts: [(SIMD3<Float>, Int, Double)] = []
    private var worldWater: NativeWorldWater?
    private var environment: NativeWorldEnvironment?
    private let atmosphere = NativeAtmosphere()
    private let regionalWeather = NativeRegionalWeather()
    private let weatherParticles = NativeWeatherParticles()
    var weatherAudio: NativeWeatherAudio? {
        get { weatherParticles.audio }
        set { weatherParticles.audio = newValue }
    }
    private let waterWaves = NativeWaterWaves()
    private let gameCamera = NativeGameCamera()
    private var gameCameraFrame: NativeGameCamera.Frame?
    private var cameraVehicleDefinitions: [String:CameraVehicleDefinition] = [:]
    private var cameraWasDriving = false
    private var waterTexture: MTLTexture?
    private var nearWaterMesh: Mesh?
    private var nearWaterOrigin: SIMD2<Float>?
    private var lastAtmosphereFrame: Double = 0
    private var atmosphereMilliseconds: Double = 0
    private var atmosphereAir: Float = 0
    private var roadWetness: Float = 0
    private var atmosphereSnapshot: NativeAtmosphere.Snapshot?
    private var weatherSnapshot: NativeWeatherParticles.Snapshot?
    private var conditions: NativeWorldEnvironment.Conditions?
    private var night: Float = 0
    private var weatherFrom = 10
    private var weatherTo = 10
    private var weatherChanged: Double = 0
    private var manualWeatherSelection = 10
    private var returningToRegionalWeather = false
    private var automaticWeather = UserDefaults.standard.bool(forKey: "world.weather.auto") {
        didSet { UserDefaults.standard.set(automaticWeather,forKey: "world.weather.auto") }
    }
    /// A synchronized site clock can supply its offset; game dayShift is separate.
    var weatherClockShiftMilliseconds: Double = 0
    var weatherAuto: Bool {
        get { automaticWeather }
        set { setWeatherOverride(newValue ? nil : manualWeatherSelection) }
    }
    func setWeatherOverride(_ id: Int?) {
        if let id {
            guard (0..<23).contains(id) else { return }
            manualWeatherSelection = id
            if automaticWeather && !returningToRegionalWeather {
                weatherFrom = id;weatherTo = id;weatherChanged = 0
            } else if returningToRegionalWeather {
                weatherFrom = weatherTo;weatherTo = id;weatherChanged = ProcessInfo.processInfo.systemUptime
            } else { setWeather(id) }
            returningToRegionalWeather = false;automaticWeather = false
        } else {
            guard !automaticWeather else { return }
            if let target = regionalWeather.at(epochMilliseconds: Date().timeIntervalSince1970*1000+weatherClockShiftMilliseconds,
                                               position: SIMD2(camera.x,camera.y)) {
                weatherFrom = weatherTo;weatherTo = target.to
                weatherChanged = ProcessInfo.processInfo.systemUptime;returningToRegionalWeather = true
            }
            automaticWeather = true
        }
    }
    var dayShift: Double = 0
    var dayHold: Double?
    var gameHour: Float { NativeWorldEnvironment.gameHour(shiftMilliseconds: dayShift, holdMilliseconds: dayHold) }
    func setWeather(_ id: Int) {
        guard (0..<23).contains(id) else { return }
        manualWeatherSelection = id
        guard !automaticWeather,id != weatherTo else { return }
        weatherFrom = weatherTo; weatherTo = id; weatherChanged = ProcessInfo.processInfo.systemUptime
    }
    private var vehicleModels: [String: String] = [:]
    private var pedModels: [String: String] = [:]
    private var weaponModels: [String: String] = [:]
    private var loading: Set<String> = []
    private var retryAfter: [String: Date] = [:]
    private var activeDetail = "c59"
    private var activeDetails: Set<String> = ["c59"]
    private var insideCells: Set<Int> = []
    private var activeFar: Set<String> = []
    private var camera = SIMD3<Float>(1480, -1738, 13)
    private var heading: Float = 0
    private var actorHeading: Float = 0
    private var cameraPitch: Float = -0.15
    private var collisions: [String: WorldCollision] = [:]
    private var collision: WorldCollision? { collisions[activeDetail] }
    private(set) var drivingSpeed: Float = 0
    private(set) var vehicleHealth = 1000
    private var activeVehicleDamage = ""
    var vehicleDamage: String { groundVehicle?.damageController?.state.text() ?? activeVehicleDamage }
    var vehicleLights = false
    var vehicleHorn = false
    private var verticalSpeed: Float = 0
    private var vehicleHandling: [String: VehicleHandling] = [:]
    private var vehicleInfo: [String: [String: String]] = [:]
    private var activeVehicleModel = ""
    private var activeHandling: VehicleHandling?
    private var activeModelOrigin: Float = 0
    private var vehicleFallbackRoll: Float = 0
    private let groundVehicle = NativeGroundVehicle()
    var vehicleHandbrake = false
    var vehicleControllerInput = false
    var vehicleJetControl: Float = 0
    var nativeVehicleTransform: simd_float4x4? { groundVehicle?.active == true ? groundVehicle?.modelTransform : nil }
    var nativeVehicleOrientation: simd_quatf? { groundVehicle?.active == true ? groundVehicle?.orientation : nil }
    var vehicleWirePosition: SIMD3<Float> { groundVehicle?.active == true ? groundVehicle!.bodyPosition : camera }
    var vehicleRoll: Float { groundVehicle?.active == true ? groundVehicle!.roll : vehicleFallbackRoll }
    func vehicleModelOrigin(_ code: String) -> Float { groundVehicle?.modelOrigin(String(code.split(separator: ".").first ?? "")) ?? 0 }
    var nativeVehicleWheels: [NativeVehicleDynamics.WheelSnapshot] { groundVehicle?.output?.wheels ?? [] }
    var nativeVehicleWheelAngles: [Float] { groundVehicle?.wheelAngles ?? [] }
    var nativeBikeLean: Float { groundVehicle?.bikeLean ?? 0 }
    var nativeBikeDrop: [Float] { groundVehicle?.bikeDrop ?? [] }
    var nativeBicyclePedal: Int { groundVehicle?.bicyclePedal ?? 0 }
    var nativeBicycleCrank: Float { groundVehicle?.bicycleCrank ?? 0 }
    var nativeRotorTurning: Float { groundVehicle?.rotorTurning ?? 0 }
    var nativeAircraftNozzle: Float? { groundVehicle?.aircraftNozzle }
    var nativeLandingGearUp: Bool { groundVehicle?.landingGearUp ?? false }
    var hasLandingGear: Bool { [476,519,577,520,553,592].contains(Int(activeVehicleModel) ?? 0) }
    var hasJetNozzle: Bool { activeVehicleModel == "520" }
    var hasVehicleHorn: Bool { driving && !["plane","helicopter","bicycle"].contains(vehicleKind) }
    func toggleLandingGear() { groundVehicle?.setLandingGear(!(groundVehicle?.landingGearUp ?? false)) }
    private(set) var vehicleKind = "car"
    private var vehiclePitch: Float = 0
    private var flightVerticalSpeed: Float = 0
    private var flightStartHeight: Float = 0
    private var waterHeight: Float = 0
    private(set) var steeringInput: Float = 0
    private var ownClip = "idle_stance"
    private var ownClipTime: Double = 0
    private var locomotionClip = "idle_stance"
    private var locomotionTime: Double = 0
    private var manualAnimation = false
    private var pedestrian = NativePedestrianMotion()
    var health = 100 {
        didSet {
            if health > 0 && oldValue <= 0 {
                swimController.revive();stamina.reset();sprintController.reset()
            }
        }
    }
    var crouching = false
    private(set) var swimming = false
    private(set) var underwater = false
    var onCollision: ((Float) -> Void)?
    var onLand: (() -> Void)?
    var onSplash: (() -> Void)?
    var onVehicleExplosion: ((SIMD3<Float>) -> Void)?
    private var actionTimeRemaining: Float = 0
    private var actionClip = ""
    var equippedWeapon = 0
    var weaponTriggerHeld = false
    var weaponReloading = false
    var weaponReady = true
    var onFootstep: ((String) -> Void)?
    var aiming = false
    var driving = false
    var remotePlayers: [RemotePlayer] = []
    var remoteVehicles: [RemoteVehicle] = []
    var currentVehicleID: String?
    var objective: SIMD2<Float>?
    var onStatus: ((String) -> Void)?
    var onFrame: (() -> Void)?

    init?(preferredDevice: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device = preferredDevice,
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "worldVertex"),
              let animatedVertex = library.makeFunction(name: "animatedActorVertex"),
              let fragment = library.makeFunction(name: "worldFragment") else { return nil }
        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.depthStencilPixelFormat = .depth32Float
        view.clearColor = MTLClearColor(red: 0.54, green: 0.70, blue: 0.81, alpha: 1)
        view.preferredFramesPerSecond = 60
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].rgbBlendOperation = .add
        descriptor.colorAttachments[0].alphaBlendOperation = .add
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        descriptor.vertexFunction = animatedVertex
        guard let animatedPipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        descriptor.vertexFunction = library.makeFunction(name: "skeletalActorVertex")
        let skeletalPipeline = descriptor.vertexFunction.flatMap { _ in try? device.makeRenderPipelineState(descriptor: descriptor) }
        descriptor.vertexFunction = library.makeFunction(name: "nativeDomeVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "nativeDomeFragment")
        let skyPipeline = descriptor.vertexFunction.flatMap { _ in try? device.makeRenderPipelineState(descriptor: descriptor) }
        var atmospherePipelines: [String: MTLRenderPipelineState] = [:]
        for (key,fragment,source,destination) in [
            ("sky","nativeSkySpriteFragment",MTLBlendFactor.one,MTLBlendFactor.one),
            ("cloud","nativeCloudSpriteFragment",.sourceAlpha,.oneMinusSourceAlpha),
            ("particle","nativeWeatherSpriteFragment",.sourceAlpha,.oneMinusSourceAlpha),
            ("splash","nativeWeatherSpriteFragment",.sourceAlpha,.one),
            ("color","nativeAtmosphereColorFragment",.sourceAlpha,.oneMinusSourceAlpha),
            ("rainbow","nativeRainbowFragment",.one,.one)] {
            descriptor.vertexFunction = library.makeFunction(name: "nativeAtmosphereVertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].sourceRGBBlendFactor = source
            descriptor.colorAttachments[0].destinationRGBBlendFactor = destination
            if descriptor.vertexFunction != nil,descriptor.fragmentFunction != nil {
                atmospherePipelines[key] = try? device.makeRenderPipelineState(descriptor: descriptor)
            }
        }
        descriptor.vertexFunction = library.makeFunction(name: "nativeWaterVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "nativeWaterFragment")
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        let waterPipeline = descriptor.vertexFunction.flatMap { _ in try? device.makeRenderPipelineState(descriptor: descriptor) }
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depth = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        depthDescriptor.isDepthWriteEnabled = false
        guard let markerDepth = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        depthDescriptor.depthCompareFunction = .always
        guard let skyDepth = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        self.view = view
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.animatedPipeline = animatedPipeline
        self.skeletalPipeline = skeletalPipeline
        self.skyPipeline = skyPipeline
        self.atmospherePipelines = atmospherePipelines
        self.waterPipeline = waterPipeline
        self.skyDepth = skyDepth
        self.depth = depth
        self.markerDepth = markerDepth
        textureLoader = MTKTextureLoader(device: device)
        super.init()
        groundVehicle?.onDamageEvents = { [weak self] events,body in
            guard let self else { return }
            for event in events {
                if event.type == "sparks" { self.onCollision?(Float(event.force ?? 0)) }
                if event.type == "blow" {
                    let point = SwiftRapierWorld.rapierToGTA(SIMD3<Float>(body.position))
                    self.showBlast(weapon:16,position:point)
                    self.onVehicleExplosion?(point)
                }
            }
        }
        groundVehicle?.waterLevel = { [weak self] point in
            let gta = SIMD3<Float>(Float(point.x),Float(-point.z),Float(point.y))
            guard let height=self?.worldWater?.height(x:gta.x,y:gta.y,z:gta.z) else { return nil }
            return Double(height)
        }
        groundVehicle?.waterWave = { [weak self] point in
            let gta = SIMD3<Float>(Float(point.x),Float(-point.z),Float(point.y))
            guard let self, let base = self.worldWater?.height(x:gta.x,y:gta.y,z:gta.z),
                  let surface = self.waterSurface(at:gta) else { return .init(height:0,normal:SIMD3(0,1,0)) }
            return .init(height:Double(surface.height-base),normal:SIMD3(Double(surface.normal.x),Double(surface.normal.z),Double(-surface.normal.y)))
        }
        objectiveMarker = makeObjectiveMarker()
        gameCamera.trace = { [weak self] origin,direction,distance in
            guard let self else { return nil }
            let groups: UInt32 = self.driving ? 0xffff0083 : 0xffff0001
            let excluded = self.driving ? self.groundVehicle?.chassisColliders ?? [] : []
            let physics = self.groundVehicle?.world.raycast(origin: SwiftRapierWorld.gtaToRapier(origin),
                direction: SwiftRapierWorld.gtaToRapier(direction),distance: distance,excludingColliders: excluded,groups: groups)?.distance
            let geometry = self.collisionFor(SIMD3(origin.x,origin.y,self.camera.z))?.raycast(from: origin,direction: direction,distance: distance)?.distance
            if let physics,let geometry { return min(physics,geometry) }
            return physics ?? geometry
        }
        weaponEffects.trace = { [weak self] origin, direction, distance in
            guard let self, let hit = self.collisionFor(origin)?.raycast(from: origin, direction: direction, distance: distance) else { return nil }
            return NativeWeaponEffects.Contact(distance: hit.distance, normal: hit.normal)
        }
        weaponEffects.groundHeight = { [weak self] x,y,z in
            self?.collisionFor(SIMD3(x,y,z))?.height(x:x,y:y,near:z,maxDrop:4)
        }
        weaponEffects.onDetonation = { [weak self] event in self?.showBlast(weapon: event.weapon, position: event.position) }
        view.delegate = self
    }

    private func collisionFor(_ point: SIMD3<Float>) -> WorldCollision? {
        let x = max(0,min(15,Int(floor((point.x+3000)/375))))
        let y = max(0,min(15,Int(floor((point.y+3000)/375))))
        return collisions["\(point.z > 700 ? "i" : "c")\(y*16+x)"]
    }
    func synchronizeProjectiles(_ rows: [[String: Any]]) { weaponEffects.synchronizeServer(rows) }
    func showBlast(weapon: Int, position: SIMD3<Float>) {
        let now = ProcessInfo.processInfo.systemUptime
        guard !blasts.contains(where: { $0.1 == weapon && now-$0.2 < 0.3 && simd_distance($0.0,position)<1.5 }) else { return }
        blasts.append((position,weapon,now))
        if driving { gameCamera.shake(at: position,strength: 0.6,nowMilliseconds: now*1000) }
    }
    func streamWeapon(_ weapon: Int?, delta: Float) {
        if let weapon {
            weaponEffects.stream(weapon: weapon, from: camera + SIMD3(0,0,1.3), direction: aimDirection, delta: delta)
        } else { weaponEffects.endStream() }
    }

    var position: SIMD3<Float> { camera }
    var direction: Float { driving ? heading : actorHeading }
    var cameraDirection: Float { gameCameraFrame?.heading ?? heading }
    var hasNearbyFire: Bool { weaponEffects.fires.contains { simd_distance($0.position,camera)<40 } }
    var groundMaterial: Int? { collision?.ground(x:camera.x,y:camera.y,near:camera.z,maxDrop:1.5)?.material }
    var isAirborne: Bool { verticalSpeed != 0 }
    var animationName: String { ownClip }
    var swimmingState: Int { swimController.on ? swimController.state.rawValue : 0 }
    var swimmingPitch: Float { Float(swimController.pitch) }
    var swimmingRatio: Float { Float(swimController.ratio) }
    var swimmingBreath: Int? { swimController.on && swimController.under ? Int(ceil(swimController.breath*100)) : nil }
    var aimDirection: SIMD3<Float> {
        if driving,let frame = gameCameraFrame { return simd_normalize(frame.target-frame.source) }
        return SIMD3(sin(heading)*cos(cameraPitch),cos(heading)*cos(cameraPitch),sin(cameraPitch))
    }
    var cameraLookDirection: String?
    func zoomCameraSight(_ delta: Float) { gameCamera.zoomSight(delta) }
    var scopedCameraHidesPlayer: Bool { gameCameraFrame?.hidesPlayer ?? false }
    var cameraViewName: String { driving ? gameCamera.vehicleViewName : ["near","middle","far"][gameCamera.footZoom-1] }
    func cycleCameraView() { if driving { gameCamera.cycleVehicleView() } else { gameCamera.cycleFootZoom() } }
    func lookCamera(x: Float,y: Float,delta: Float) {
        gameCamera.lookAnalog(x: x,y: -y,delta: delta,driving: driving)
        if !driving { heading = gameCamera.heading;cameraPitch = gameCamera.pitch }
    }
    var vehicleNose: Float { driving ? vehiclePitch : 0 }
    func vehicleName(model: String) -> String? { vehicleInfo[model]?["name"] }
    func vehicleType(model: String) -> String? { vehicleInfo[model]?["type"] }
    var isFiring: Bool { actionTimeRemaining > 0 && actionClip == "colt45_fire" }

    func move(forward: Float, sideways: Float, turn: Float, delta: Float,
              running: Bool = false, lookVertical: Float = 0, lift: Float = 0) {
        synchronizeOtherVehiclePhysics()
        if !driving && gameCamera.isLoaded {
            gameCamera.lookAnalog(x: turn,y: -lookVertical,delta: delta)
            heading = gameCamera.heading;cameraPitch = gameCamera.pitch
        } else if !driving || (vehicleKind != "plane" && vehicleKind != "helicopter") {
            cameraPitch = max(-0.4, min(0.5, cameraPitch + lookVertical * delta * 0.45))
        }
        actionTimeRemaining = max(0, actionTimeRemaining - delta)
        let inputLength = min(1, hypot(forward, sideways))
        if running && !sprintWasHeld { pendingSprintTap = true }
        sprintWasHeld = running
        if manualAnimation && inputLength > 0.05 { clearAction() }
        pedestrian.health = health
        pedestrian.crouching = crouching
        pedestrian.swimming = swimming
        pedestrian.underwater = underwater
        pedestrian.update(delta: Double(delta), moving: inputLength >= 0.05,
                          running: running, airborne: verticalSpeed != 0,
                          verticalSpeed: verticalSpeed, weapon: equippedWeapon,
                          driving: driving, backwards: forward < -0.05)
        ownClip = pedestrian.clip
        ownClipTime = pedestrian.elapsed
        let nextLocomotion = inputLength < 0.05 ? (equippedWeapon > 0 ? "gun_stand" : "idle_stance") :
            crouching ? (forward < 0 ? "guncrouchbwd" : "guncrouchfwd") : running ? "run_player" : "walk_player"
        if nextLocomotion != locomotionClip { locomotionClip = nextLocomotion; locomotionTime = 0 }
        else { locomotionTime += Double(delta) }
        let start = camera
        let startHeading = heading
        var next = camera
        if driving {
            steeringInput = max(-1, min(1, turn))
            let throttle = vehicleHealth > 0 && health > 0 && ProcessInfo.processInfo.systemUptime-entryStarted >= 1 ? forward : 0
            let table = activeHandling
            let speedLimit = table?.roadTopSpeed ?? 32
            let acceleration = max(1.5, (table?.acceleration ?? 20) * 0.24)
            let braking = max(3, (table?.brakes ?? 7) * 1.2)
            let lock = max(10, min(50, table?.lock ?? 35)) * .pi / 180
            let grip = max(0.35, min(1.8, table?.traction ?? 0.8))
            if let groundVehicle, !groundVehicle.active, groundVehicle.supports(activeVehicleModel),
               groundVehicle.isCellLoaded(activeDetail) {
                let origin = groundVehicle.modelOrigin(activeVehicleModel) ?? 0
                camera += NativeGroundVehicle.modelOffset(origin:origin-activeModelOrigin,heading:heading,pitch:vehiclePitch,roll:vehicleFallbackRoll)
                activeModelOrigin = origin
                groundVehicle.enter(model:activeVehicleModel,modelPosition:camera,heading:heading,pitch:vehiclePitch,roll:vehicleFallbackRoll)
                groundVehicle.damageController?.state.load(health:Double(vehicleHealth),text:activeVehicleDamage)
            }
            if let groundVehicle, groundVehicle.active {
                var input = NativeVehicleDynamics.Input()
                input.throttle = Double(throttle); input.steer = Double(steeringInput)
                input.lean = Double(lookVertical); input.handbrake = vehicleHandbrake
                input.pad = vehicleControllerInput; input.wetness = Double(roadWetness)
                input.hop = vehicleHandbrake && vehicleKind == "bicycle"
                input.pitch = Double(lookVertical); input.roll = Double(turn)
                input.yaw = Double(sideways); input.nobody = vehicleHealth <= 0 || health <= 0
                input.jets = Double(vehicleJetControl)
                if vehicleKind == "helicopter" { input.throttle = Double(lift) }
                groundVehicle.update(delta: Double(delta), input: input, currentCell: activeDetail)
                if let damage = groundVehicle.damageController?.state {
                    vehicleHealth = max(0,min(1000,Int(damage.health.rounded())))
                    activeVehicleDamage = damage.text()
                }
                next = groundVehicle.modelPosition; heading = groundVehicle.heading
                drivingSpeed = groundVehicle.speed; vehiclePitch = groundVehicle.pitch
                if let angle = groundVehicle.output?.steering { steeringInput = Float(angle) }
            } else if vehicleKind == "helicopter" {
                heading += steeringInput * delta * 0.95
                drivingSpeed += (throttle * 24 - drivingSpeed) * min(1, delta * 1.6)
                next.x += (sin(heading) * drivingSpeed + cos(heading) * sideways * 15) * delta
                next.y += (cos(heading) * drivingSpeed - sin(heading) * sideways * 15) * delta
                flightVerticalSpeed += ((vehicleHealth > 0 ? lift : 0) * 8 -
                    flightVerticalSpeed) * min(1, delta * 1.8)
                next.z += flightVerticalSpeed * delta
                vehiclePitch += (throttle * 0.16 - vehiclePitch) * min(1, delta * 2)
            } else if vehicleKind == "plane" && activeVehicleModel != "539" {
                let top = max(35, min(95, (table?.maxVelocity ?? 200) / 3.6))
                let target = max(0, min(top, throttle > 0 ? top * throttle : 0))
                let rate = throttle < 0 ? max(3, braking) : throttle > 0 ? max(3, acceleration) : 1.2
                drivingSpeed += max(-rate * delta, min(rate * delta, target - drivingSpeed))
                // Keep a touch-only takeoff climbing above the airport's
                // terminal and container roofs. A right-stick input overrides
                // the assist, so a pilot can level or descend at any time.
                let autoRotate = drivingSpeed > 15 && throttle > 0.05 &&
                    camera.z < flightStartHeight + 120
                let requestedPitch = abs(lookVertical) > 0.05 ? lookVertical * 0.35 :
                    autoRotate ? 0.22 : 0
                let desiredPitch = max(-0.35, min(0.35, requestedPitch))
                vehiclePitch += (desiredPitch - vehiclePitch) * min(1, delta * 1.5)
                heading += steeringInput * delta * (0.2 + min(0.6, drivingSpeed / 90))
                next.x += sin(heading) * drivingSpeed * delta
                next.y += cos(heading) * drivingSpeed * delta
                let liftSpeed = drivingSpeed > 18 ? drivingSpeed * sin(vehiclePitch) : -3.5
                flightVerticalSpeed += (liftSpeed - flightVerticalSpeed) * min(1, delta * 2.5)
                next.z += flightVerticalSpeed * delta
            } else {
                let reverseLimit: Float = vehicleKind == "bicycle" ? 0 :
                    vehicleKind == "bike" ? 3 : vehicleKind == "train" ? 8 : 9
                let top = vehicleKind == "boat" ? min(speedLimit, 35) :
                    vehicleKind == "bicycle" ? min(speedLimit, 15) : speedLimit
                let input = max(-1, min(1, throttle))
                if input > 0.05 {
                    drivingSpeed = min(top, drivingSpeed +
                        (drivingSpeed < 0 ? braking : acceleration) * input * delta)
                } else if input < -0.05 {
                    drivingSpeed = max(-reverseLimit, drivingSpeed -
                        (drivingSpeed > 0 ? braking : acceleration * 0.6) * -input * delta)
                } else {
                    let coast = max(0.8, min(3, (table?.drag ?? 2) * 0.7)) * delta
                    drivingSpeed = abs(drivingSpeed) <= coast ? 0 :
                        drivingSpeed - (drivingSpeed > 0 ? coast : -coast)
                }
                let wheelbase: Float = vehicleKind == "bike" || vehicleKind == "bicycle" ? 1.5 : 2.6
                let steeringAngle = steeringInput * lock / (1 + abs(drivingSpeed) * 0.08)
                let yawRate = drivingSpeed * tan(steeringAngle) / wheelbase
                let yawLimit: Float = vehicleKind == "train" || vehicleKind == "trailer" ? 0 :
                    vehicleKind == "bike" || vehicleKind == "bicycle" ? 2.2 : 1.5
                heading += max(-yawLimit, min(yawLimit, yawRate * grip)) * delta
                next.x += sin(heading) * drivingSpeed * delta
                next.y += cos(heading) * drivingSpeed * delta
                if vehicleKind == "boat" || activeVehicleModel == "539" { next.z = waterHeight }
            }
        } else {
            if !gameCamera.isLoaded { heading += turn * delta * 1.8 }
            if footAnimator == nil { prepareFootAnimation() }
            if footAnimator == nil && aiming { actorHeading = heading }
            if footAnimator == nil && inputLength >= 0.05 && health > 0 {
                let worldX = sin(heading) * forward + cos(heading) * sideways
                let worldY = cos(heading) * forward - sin(heading) * sideways
                let desired = atan2(worldX, worldY)
                swimHeadingTarget = desired
                if actionTimeRemaining == 0 && !aiming {
                    let difference = atan2(sin(desired - actorHeading),
                                           cos(desired - actorHeading))
                    actorHeading += max(-delta * 8, min(delta * 8, difference))
                }
                // The archived clips sweep a foot roughly 1.1 m in 1.2 s
                // walking and 1.5 m in 0.73 s running. Match world travel to
                // those cycles so the feet do not slide across the pavement.
                let distance = delta * (swimming ? (running ? 2.8 : 1.3) : crouching ? 0.9 : running ? 4.1 : aiming ? 1.1 : 1.6) * inputLength
                let length = max(0.0001, hypot(worldX, worldY))
                next.x += worldX / length * distance
                next.y += worldY / length * distance
            }
        }
        var characterOutput: NativeCharacterController.Output?
        if !driving, let character {
            if !characterActive { character.reset(feet: start); characterActive = true }
            let result = character.update(delta: Double(delta),displacement: next-start,
                jump: pendingNativeJump,geometryReady: groundVehicle?.isCellLoaded(activeDetail) == true,
                motion: { [self] step,state,intended in
                    let water = swimmingMotion(delta:step,state:state,intended:intended,push:Double(inputLength),running:running)
                    if swimController.on { return water }
                    return footMotion(delta:step,state:state,intended:water,forward:forward,sideways:sideways,running:running)
                })
            pendingNativeJump = 0; characterOutput = result; next = result.feet
        } else if characterActive {
            character?.setActive(false); characterActive = false; pendingNativeJump = 0
        }
        if !driving && character == nil,footAnimator != nil {
            let grounded = verticalSpeed == 0
            let state = NativeCharacterController.Output(feet:start,grounded:grounded,rising:Double(verticalSpeed),eased:0,propped:false,pressed:[])
            let motion = footMotion(delta:Double(delta),state:state,intended:.init(displacement:.zero),forward:forward,sideways:sideways,running:running)
            next = start + motion.displacement
            if motion.jump > 0 { verticalSpeed = Float(motion.jump) }
        }
        let radius: Float = driving ? (vehicleKind == "bike" || vehicleKind == "bicycle" ? 0.48 : 0.9) : 0.32
        let height: Float = driving ? (vehicleKind == "plane" ? 2.5 : 1.4) : crouching ? 1.0 : 1.8
        let bodyBlocked = characterOutput == nil && groundVehicle?.active != true && collision?.canMove(from: start, to: next,
                                             radius: radius, bodyHeight: height) == false
        let length: Float = vehicleKind == "plane" || vehicleKind == "helicopter" ? 4.5 :
            vehicleKind == "bike" || vehicleKind == "bicycle" ? 0.9 :
            vehicleKind == "boat" ? 2.8 : 2.1
        let lead = drivingSpeed >= 0 ? length : -length
        let oldBumper = start + SIMD3<Float>(sin(startHeading) * lead,
                                             cos(startHeading) * lead, 0)
        let newBumper = next + SIMD3<Float>(sin(heading) * lead,
                                            cos(heading) * lead, 0)
        let bumperBlocked = characterOutput == nil && groundVehicle?.active != true && driving && abs(drivingSpeed) > 0.05 &&
            collision?.canMove(from: oldBumper, to: newBumper,
                               radius: radius, bodyHeight: height) == false
        if bodyBlocked || bumperBlocked {
            if driving {
                if abs(drivingSpeed) > 8 {
                    onCollision?(abs(drivingSpeed))
                    let damage = Int(min(300, max(12, (abs(drivingSpeed) - 7) * 3)))
                    vehicleHealth = max(0, vehicleHealth - damage)
                    onStatus?(vehicleHealth == 0 ? "VEHICLE DISABLED · REPAIR IT AT A WORKSHOP" :
                        "COLLISION · VEHICLE HEALTH \(vehicleHealth) / 1000")
                }
                drivingSpeed = 0
                flightVerticalSpeed = 0
            }
            next = start
        }
        camera = next
        let surface = waterSurface(at: camera)?.height
        swimming = !driving && swimController.on
        underwater = swimming && swimController.under
        if !driving && delta > 0 {
            lastFootVelocity = SIMD3<Double>(SwiftRapierWorld.gtaToRapier((camera-start)/delta))
        }
        if let characterOutput {
            if characterOutput.grounded && verticalSpeed < 0 && !swimController.on { onLand?() }
            verticalSpeed = characterOutput.grounded ? 0 : Float(characterOutput.rising)
        } else if groundVehicle?.active == true {
            // Rapier owns chassis position and suspension. A pedestrian floor
            // correction here would discard jumps, banking and rollovers.
            verticalSpeed = 0
        } else if swimming, let surface {
            camera.z += ((surface - (underwater ? 2.2 : 0.65)) - camera.z) * min(1, delta * 3)
            verticalSpeed = 0
        } else if driving && (vehicleKind == "plane" || vehicleKind == "helicopter") &&
            activeVehicleModel != "539" {
            if let floor = collision?.height(x: camera.x, y: camera.y,
                                             near: camera.z - 1.1, maxDrop: 20),
               camera.z < floor + 1.1 {
                camera.z = floor + 1.1
                flightVerticalSpeed = max(0, flightVerticalSpeed)
            }
        } else if driving && (vehicleKind == "boat" || activeVehicleModel == "539") {
            camera.z = surface.map { $0 + 0.4 } ?? waterHeight
        } else if !driving && verticalSpeed != 0 {
            verticalSpeed -= 9.8 * delta
            camera.z += verticalSpeed * delta
            if let floor = collision?.height(x: camera.x, y: camera.y,
                                             near: camera.z, maxDrop: 8),
               camera.z <= floor {
                camera.z = floor
                verticalSpeed = 0
                onLand?()
            }
        } else if let z = collision?.height(x: camera.x, y: camera.y,
                                            near: camera.z - (driving ? 1.1 : 0)) {
            camera.z = z + (driving ? 1.1 : 0)
        } else if !driving, collision != nil, health > 0 {
            verticalSpeed = -0.01
        }
        if swimController.on {
            let names = ["swim_tread","swim_breast","swim_crawl","swim_dive_under","swim_under","swim_glide","swim_jumpout"]
            let once = swimController.state == .dive || swimController.state == .out
            let clip = "swim/"+names[swimController.state.rawValue-1]+(once ? "/n/1" : "/l/1")
            if clip != swimAnimation { swimAnimation = clip;swimAnimationElapsed = 0 }
            let speed = swimController.state == .breast ? max(0.3,min(1,swimController.ratio)) :
                swimController.state == .crawl || swimController.state == .under ? swimController.pace : 1
            swimAnimationElapsed += Double(delta)*speed;ownClip = clip;ownClipTime = swimAnimationElapsed
        } else { swimAnimation = "";swimAnimationElapsed = 0 }
        loadNearby()
        weaponEffects.update(delta: delta,
            people: remotePlayers.map { NativeWeaponEffects.Target(id:$0.id,position:$0.position) },
            vehicles: remoteVehicles.map { NativeWeaponEffects.Target(id:$0.id,position:$0.position) })
    }

    private func synchronizeOtherVehiclePhysics() {
        guard let groundVehicle else {return}
        var poses:[String:NativeOtherVehicles.Pose] = [:]
        for vehicle in remoteVehicles {
            poses[vehicle.id] = .init(id:vehicle.id,code:vehicle.code,position:vehicle.position,
                heading:vehicle.heading,pitch:vehicle.pitch,roll:vehicle.roll)
        }
        for player in remotePlayers {
            guard let id=player.vehicleID else {continue}
            poses[id] = .init(id:id,code:player.code,position:player.position,
                heading:player.heading,pitch:player.pitch,roll:player.roll)
        }
        groundVehicle.synchronizeOtherVehicles(Array(poses.values),excluding:currentVehicleID,near:camera)
        character?.otherColliders = groundVehicle.otherColliders
    }

    func jump() {
        guard !driving, health > 0 else { return }
        if swimming { pendingSwimJump = true; return }
        guard verticalSpeed == 0 else { return }
        if let footAnimator {
            guard !footAnimator.busy,!footAnimator.stunned,!footAnimator.swinging,footLaunchRemaining == nil else { return }
            if crouching { crouching = false; return }
            footLaunchRemaining = footAnimator.launch()
            return
        }
        crouching = false
        if characterActive { pendingNativeJump = 6.07; verticalSpeed = 6.07 }
        else { verticalSpeed = 5.5 }
    }

    func toggleCrouch() {
        if swimController.on { pendingDive = true }
        else { crouching.toggle() }
    }

    func waterSurface(at point: SIMD3<Float>) -> (height: Float,normal: SIMD3<Float>)? {
        guard let base = worldWater?.height(x:point.x,y:point.y,z:point.z) else { return nil }
        let wave = waterWaves.rise(x:point.x,y:point.y)
        return (base+wave.height,wave.normal)
    }

    private func swimmingMotion(delta: Double,state: NativeCharacterController.Output,
                                intended: NativeCharacterController.Motion,push: Double,running: Bool) -> NativeCharacterController.Motion {
        let depth = waterSurface(at:state.feet).map { Double($0.height-state.feet.z) }
        if !swimController.on && swimController.enters(depth) {
            swimController.enter(velocity:lastFootVelocity,rising:state.rising,depth:depth!)
            crouching = false;clearAction()
            footAirTime = 0;footAirFall = 0;footAirFell = false;footJumped = false;footLaunchRemaining = nil
        }
        guard swimController.on else { swimController.ashore(delta);return intended }
        let profile = NativeSprintController.Profile.forMode(swimController.under ? .underwater : .water)
        let pace = sprintController.control(profile,ticks:50*delta,tapped:pendingSprintTap,held:running,
            staminaLeft:stamina.left,take:{ [self] in stamina.take($0) })
        pendingSprintTap = false
        swimController.steer(push:push,sprint:pace >= 1 ? pace : 0,dive:pendingDive,pitch:Double(cameraPitch))
        pendingDive = false
        if swimController.turns && (push > 0 || swimController.under) {
            let target = swimController.under ? heading : swimHeadingTarget
            let difference = atan2(sin(target-actorHeading),cos(target-actorHeading))
            actorHeading += max(-Float(4*delta),min(Float(4*delta),difference))
        }
        let feet = SIMD3<Double>(SwiftRapierWorld.gtaToRapier(state.feet))
        let jumping = pendingSwimJump;pendingSwimJump = false
        let result = swimController.step(delta:delta,depth:depth,grounded:state.grounded,heading:-Double(actorHeading),
            feet:feet,jump:jumping,ledge:{ [weak self] in self?.swimmingLedge(feet:feet,heading:-Double(self?.actorHeading ?? 0),surface:feet.y+(depth ?? 0)) },dead:health <= 0)
        if let animator = footAnimator {
            animator.arm(nil)
            if health <= 0 && !animator.dead { animator.die("drown") }
            else if health > 0 && animator.dead { animator.revive() }
            var animation = NativeFootAnimation.Input()
            animation.swimming = true
            animation.swim = .init(state:swimController.on ? swimController.state.rawValue : 0,rate:swimController.ratio,pace:swimController.pace,pitch:swimController.pitch)
            footAnimationFrame = animator.update(delta:delta,input:animation)
        }
        if pace < 1 || swimController.under {
            stamina.rest(50*delta*(swimController.state == .breast ? 0.25 : 0.5))
        }
        if swimController.consumeSplash() { onSplash?() }
        guard let result else { return intended }
        var input = intended
        input.displacement = SwiftRapierWorld.rapierToGTA(SIMD3<Float>(result.move))
        input.verticalOverride = result.rise;input.jump = 0
        if let held = swimController.hauled { input.heldFeet = SwiftRapierWorld.rapierToGTA(SIMD3<Float>(held)) }
        return input
    }

    private func prepareFootAnimation() {
        guard let library = skeletalLibrary,let definitions = footDefinitions else { return }
        let model = pedModels["7"] ?? "bmori"
        guard footAnimator == nil || footAnimationModel != model else { return }
        let style = definitions.style(model:model,library:library)
        func swimSpeed(_ name: String) -> Double? {
            let clip = "swim/"+name
            guard let duration = library.duration(of:clip),duration > 0 else { return nil }
            return library.cycleTravel(clip).y/duration
        }
        swimController.setSpeeds(breast:swimSpeed("swim_breast"),crawl:swimSpeed("swim_crawl"),under:swimSpeed("swim_under"))
        let animator = NativeFootAnimation(library:library,style:style)
        animator.onStep = { [weak self] kind in self?.onFootstep?(kind) }
        footAnimator = animator;footAnimationModel = model
        footLocomotion.reset(heading:Double(actorHeading));footAnimationFrame = nil
        footAirTime = 0;footAirFall = 0;footAirFell = false;footJumped = false;footJumpMinimum = 0
        footLaunchRemaining = nil;footAirVelocity = .zero
    }

    /// Fixed alongside the actual public collision motor. Animation root
    /// distance and collision therefore consume exactly the same time slices.
    private func footMotion(delta: Double,state: NativeCharacterController.Output,
                            intended: NativeCharacterController.Motion,forward: Float,sideways: Float,running: Bool) -> NativeCharacterController.Motion {
        prepareFootAnimation()
        guard let animator = footAnimator else { pendingSprintTap = false;return intended }
        let definition = footWeaponDefinitions[equippedWeapon]
        animator.arm(definition)
        if health <= 0 && !animator.dead { animator.die() }
        else if health > 0 && animator.dead { animator.revive() }
        if weaponReloading && !footReloadWasActive && !footReloadRequested { _ = animator.reload() }
        footReloadWasActive = weaponReloading;footReloadRequested = false
        let effectiveAim = definition?.aims == true && (aiming || animator.gunUp || weaponTriggerHeld)
        var control = NativeFootLocomotion.Input()
        control.stick = SIMD2(Double(sideways),Double(forward));control.cameraHeading = Double(heading)
        control.aiming = effectiveAim;control.crouching = crouching;control.gunUp = animator.gunUp
        control.armAim = definition?.arm ?? false;control.hipFire = effectiveAim && !aiming
        control.movingAim = definition?.flags?["moveAim"] ?? true
        control.movingFire = definition?.flags?["moveFire"] ?? true
        control.isGun = definition?.use == "gun";control.gunShooting = animator.gunShooting
        control.attackHeld = weaponTriggerHeld;control.busy = animator.busy || health <= 0
        control.stunned = animator.stunned;control.rolling = animator.rolling;control.swinging = animator.swinging
        control.air = !state.grounded;control.turningRate = animator.style.turn
        control.throwing = definition?.use == "throw" && (weaponTriggerHeld || animator.firing)
        let locomotion = footLocomotion.update(delta:delta,input:control)
        actorHeading = Float(locomotion.heading)
        var motion = intended
        var jumping = false
        if let remaining = footLaunchRemaining {
            if remaining-delta < 0 {
                footLaunchRemaining = nil
                if state.grounded { motion.jump = 6.07;jumping = true }
            } else { footLaunchRemaining = remaining-delta;motion.jump = 0 }
        }
        let airborne = !state.grounded || jumping
        let wholeBodyAim = animator.gunUp && !(definition?.arm ?? false) && !crouching
        if !airborne {
            let restricted = wholeBodyAim || crouching || definition?.flags?["heavy"] == true || !animator.sprints
            footSprintPace = restricted ? 0 : sprintController.control(.forMode(.foot),ticks:50*delta,tapped:pendingSprintTap,held:running,
                staminaLeft:stamina.left,take:{ [self] in stamina.take($0) })
            if footSprintPace < 1 { stamina.rest(50*delta*(locomotion.ratio > 1 ? 0.15 : 0.5)) }
        }
        pendingSprintTap = false
        var animation = NativeFootAnimation.Input()
        animation.ratio = locomotion.ratio;animation.sprint = footSprintPace >= 1 && locomotion.pushing && !wholeBodyAim
        animation.pace = animation.sprint ? footSprintPace : 1
        animation.crouch = crouching;animation.strafe = locomotion.strafe
        animation.gun = effectiveAim ? .init(pitch:aiming ? Double(cameraPitch) : 0,yaw:min(1.4,max(-1.4,Double(actorHeading-heading)))) : nil
        if effectiveAim { animator.control(.init(fire:weaponTriggerHeld && weaponReady,aim:aiming,held:weaponTriggerHeld,pushed:locomotion.pushing,ready:weaponReady)) }
        if airborne {
            footAirTime += delta;footJumped = footJumped || jumping;footAirFall = max(footAirFall,-state.rising)
            if state.rising < -5 {
                let feet = state.feet
                let hit = character?.world.queryRay(origin:SwiftRapierWorld.gtaToRapier(feet+SIMD3(0,0,0.1)),direction:SIMD3(0,-1,0),distance:4,groups:0xffff0001)
                if hit == nil { footAirFell = true }
            }
            animation.air = footAirFell ? "fall" : footJumped ? "jump" : footAirTime > 0.35 ? "glide" : nil
        } else {
            if footAirTime > 0 && (footJumped || footAirTime > 0.35) {
                animation.land = footAirFell ? (footAirFall > 20 ? "koSkidBack" : "collapse") : locomotion.ratio > 1.5 && locomotion.pushing ? "land" : "fallLand"
            }
            footAirTime = 0;footAirFall = 0;footAirFell = false;footJumped = false;footJumpMinimum = 0
        }
        let frame = animator.update(delta:delta,input:animation);footAnimationFrame = frame
        var travel = NativeFootLocomotion.worldTravel(frame.travel,heading:locomotion.heading)
        if airborne {
            if jumping {
                let speed: Double = frame.sprintShare > 0 ? 8.5+2.5*frame.sprintShare : 5+3.5*min(1,max(0,locomotion.ratio-1))
                footAirVelocity = SIMD2(sin(locomotion.heading),cos(locomotion.heading))*speed
            }
            if footJumped && state.rising > 0 && footJumpMinimum < 1 {
                let forward = SIMD2(sin(locomotion.heading),cos(locomotion.heading)),along = simd_dot(footAirVelocity,forward)
                if along < 2.5 { footAirVelocity += forward*(2.5-along) }
                footJumpMinimum += delta
            }
            if state.propped { footAirVelocity = .zero }
            let magnitude = sqrt(simd_length_squared(footAirVelocity)+state.rising*state.rising)
            footAirVelocity *= pow(max(0,1-magnitude/8750),50*delta)
            travel = SIMD3(Float(footAirVelocity.x*delta),Float(footAirVelocity.y*delta),0)
        } else if delta > 0 { footAirVelocity = SIMD2(Double(travel.x)/delta,Double(travel.y)/delta) }
        motion.displacement = travel
        if let prominent = frame.blends.last(where: { $0.weight > 0.5 && !$0.clip.isEmpty }) {
            ownClip = prominent.clip + "/l/1";ownClipTime = prominent.time
        }
        return motion
    }

    private func swimmingLedge(feet: SIMD3<Double>,heading: Double,surface: Double) -> SIMD3<Double>? {
        guard let character else { return nil }
        let forward = SIMD3<Float>(Float(-sin(heading)),0,Float(-cos(heading)))
        var wall: Float?
        for offset in [0.15,0.7,-0.4] {
            wall = character.world.queryRay(origin:SIMD3(Float(feet.x),Float(surface+offset),Float(feet.z)),
                direction:forward,distance:1.3,groups:0xffff0001)?.distance
            if wall != nil { break }
        }
        guard let wall else { return nil }
        var top = SIMD3<Float>(Float(feet.x),Float(surface+2),Float(feet.z))+forward*(wall+0.55)
        guard let down = character.world.queryRay(origin:top,direction:SIMD3(0,-1,0),distance:2.5,groups:0xffff0001),
              down.distance >= 0.05 else { return nil }
        top.y -= down.distance
        let value = SIMD3<Double>(top)
        return character.motor.fits(value) ? value : nil
    }

    func performFistAttack() {
        manualAnimation = false
        actorHeading = heading
        actionClip = "fighta_1"
        actionTimeRemaining = 0.43
        pedestrian.perform("fighta_1", duration: 0.43)
        if let animator = footAnimator { animator.arm(footWeaponDefinitions[0]);_ = animator.fire(held:false) }
    }

    func firePistol() {
        fireWeapon(clip: "colt45_fire", duration: 0.73)
    }

    func fireWeapon(clip: String, duration: Float) {
        manualAnimation = false
        actorHeading = heading
        actionClip = clip
        actionTimeRemaining = duration
        pedestrian.perform(clip, duration: Double(duration))
        if let animator = footAnimator {
            animator.arm(footWeaponDefinitions[equippedWeapon])
            if clip.lowercased().contains("load") { _ = animator.reload();footReloadRequested = true }
            else { _ = animator.fire(held:false) }
        }
    }

    func clearAction() { actionTimeRemaining = 0; pedestrian.clearAction();footAnimator?.rest();manualAnimation = false }
    var animationClips: [String] { skeletalLibrary?.clipNames ?? [] }
    func playAnimation(_ name: String, looping: Bool) {
        guard !driving, health > 0, let library = skeletalLibrary, library.contains(name) else { return }
        manualAnimation = true
        let wire = name + (looping ? "/l/1" : "/n/1")
        pedestrian.perform(wire, duration: looping ? 600 : (library.duration(of: name) ?? 1))
        _ = footAnimator?.act(name,loop:looping)
    }

    func hasClearShot(to target: SIMD3<Float>) -> Bool {
        let start = camera + SIMD3<Float>(0, 0, 1.35)
        let finish = target + SIMD3<Float>(0, 0, 1.15)
        return collision?.lineOfSight(from: start, to: finish) ?? true
    }

    func enter(_ vehicle: RemoteVehicle, kind: String) {
        swimController.stop();swimming = false;underwater = false
        footAnimator?.rest(cut:true);footAnimationFrame = nil;footLaunchRemaining = nil
        character?.setActive(false); characterActive = false; pendingNativeJump = 0
        groundVehicle?.exit()
        entryOrigin = camera
        entryStarted = ProcessInfo.processInfo.systemUptime
        camera = vehicle.position
        heading = vehicle.heading
        actorHeading = heading
        drivingSpeed = 0
        vehicleHealth = vehicle.health
        activeVehicleDamage = vehicle.damage
        vehicleHorn = false;vehicleLights = false;vehicleJetControl = 0
        verticalSpeed = 0
        flightVerticalSpeed = 0
        flightStartHeight = vehicle.position.z
        vehiclePitch = vehicle.pitch
        vehicleFallbackRoll = vehicle.roll
        steeringInput = 0
        activeVehicleModel = String(vehicle.code.split(separator: ".").first ?? "")
        // Browser vehicle packets carry the rigid-body/root position; its
        // visible model is a child translated up by this original DFF offset.
        activeModelOrigin = groundVehicle?.modelOrigin(activeVehicleModel) ?? 0
        camera += NativeGroundVehicle.modelOffset(origin:activeModelOrigin,heading:heading,pitch:vehiclePitch,roll:vehicleFallbackRoll)
        activeHandling = vehicleHandling[activeVehicleModel]
        vehicleKind = kind
        waterHeight = vehicle.position.z
        driving = true
        pedestrian.perform("car_getin_lhs", duration: 1.0)
        crouching = false
        currentVehicleID = vehicle.id
        loadNearby()
    }

    func exitVehicle() {
        let floor = collision?.height(x: camera.x, y: camera.y,
                                      near: camera.z, maxDrop: 1000)
        let falling = floor.map { camera.z > $0 + 3 } ?? false
        groundVehicle?.exit()
        driving = false
        currentVehicleID = nil
        drivingSpeed = 0
        flightVerticalSpeed = 0
        vehiclePitch = 0
        vehicleFallbackRoll = 0
        activeModelOrigin = 0
        activeVehicleModel = ""
        activeHandling = nil
        vehicleKind = "car"
        camera.x += cos(heading) * 2.5
        camera.y -= sin(heading) * 2.5
        if falling { verticalSpeed = -1 }
        else { camera.z = collision?.height(x: camera.x, y: camera.y,
                                           near: camera.z - 1.1) ?? camera.z - 1.1 }
        actorHeading = heading
        pedestrian.perform("car_getout_lhs", duration: 1.0)
        footLocomotion.reset(heading:Double(actorHeading));footAnimationFrame = nil
        footAirTime = 0;footAirFall = 0;footJumped = false;footAirVelocity = .zero
    }

    func teleport(x: Float, y: Float, z: Float, direction: Float? = nil) {
        swimController.stop();swimming = false;underwater = false;lastFootVelocity = .zero
        characterActive = false; pendingNativeJump = 0
        camera = SIMD3(x, y, z)
        if let direction { heading = direction; actorHeading = direction }
        groundVehicle?.teleport(modelPosition: camera, heading: heading)
        verticalSpeed = 0
        loadNearby()
    }

    func loadNearby() {
        // The far mesh is divided into sixteen 4×4 blocks. Detailed cells are
        // 375 m squares with a 16-column grid and origin (-3000, -3000).
        let gx = max(0, min(15, Int(floor((camera.x + 3000) / 375))))
        let gy = max(0, min(15, Int(floor((camera.y + 3000) / 375))))
        let detail = gy * 16 + gx
        let indoors = camera.z > 700
        let prefix = indoors ? "i" : "c"
        activeDetail = "\(prefix)\(detail)"
        var detailNames: Set<String> = []
        // Preload and draw the adjacent cells before crossing their edges.
        // A late collision response must not leave the player without a floor.
        for dx in [Float(-90), 0, 90] { for dy in [Float(-90), 0, 90] {
            let x = max(0, min(15, Int(floor((camera.x + 3000 + dx) / 375))))
            let y = max(0, min(15, Int(floor((camera.y + 3000 + dy) / 375))))
            let number = y * 16 + x
            if !indoors || insideCells.contains(number) { detailNames.insert("\(prefix)\(number)") }
        } }
        activeDetails = detailNames
        // The camera sits behind the player; draw the adjacent 1.5 km blocks
        // as well so a block edge never cuts across the horizon.
        var far: Set<String> = []
        for dx in [Float(-750), 0, 750] {
            for dy in [Float(-750), 0, 750] {
                let tx = max(0, min(3, Int(floor((camera.x + 3000 + dx) / 1500))))
                let ty = max(0, min(3, Int(floor((camera.y + 3000 + dy) / 1500))))
                far.insert("t\(ty * 4 + tx)")
            }
        }
        if indoors { far = [] }
        activeFar = far
        meshes = meshes.filter { detailNames.contains($0.key) || far.contains($0.key) }
        collisions = collisions.filter { detailNames.contains($0.key) }
        groundVehicle?.retainCells(detailNames)
        for name in far { load(name: name) }
        for name in detailNames { load(name: name) }
    }

    private func load(name: String) {
        guard meshes[name] == nil, !loading.contains(name),
              Date() >= (retryAfter[name] ?? .distantPast), let server else { return }
        loading.insert(name)
        onStatus?("LOADING CITY: \(name.uppercased())")
        let binURL = server.path("game/world/\(name).bin")
        let imageURL = server.path("game/world/\(name).png")
        let group = DispatchGroup()
        var bin: Data?
        var png: Data?
        var col: Data?
        var fetchError: Error?
        let lock = NSLock()
        group.enter()
        URLSession.shared.dataTask(with: binURL) { data, response, error in
            lock.lock()
            if let response = response as? HTTPURLResponse, response.statusCode == 200 { bin = data }
            else { fetchError = error ?? NSError(domain: "World", code: (response as? HTTPURLResponse)?.statusCode ?? -1) }
            lock.unlock()
            group.leave()
        }.resume()
        group.enter()
        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            lock.lock()
            if let response = response as? HTTPURLResponse, response.statusCode == 200 { png = data }
            else { fetchError = error ?? NSError(domain: "World", code: (response as? HTTPURLResponse)?.statusCode ?? -1) }
            lock.unlock()
            group.leave()
        }.resume()
        if name.hasPrefix("c") || name.hasPrefix("i") {
            group.enter()
            URLSession.shared.dataTask(with: server.path("game/world/\(name).col.bin")) { data, response, _ in
                lock.lock()
                if (response as? HTTPURLResponse)?.statusCode == 200 { col = data }
                lock.unlock()
                group.leave()
            }.resume()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.loading.remove(name)
            if name.hasPrefix("c") || name.hasPrefix("i"), !self.activeDetails.contains(name) { return }
            if name.hasPrefix("t"), !self.activeFar.contains(name) { return }
            guard let bin, let png else {
                self.retryAfter[name] = Date().addingTimeInterval(5)
                self.onStatus?("CITY FILE UNAVAILABLE: \(name.uppercased()) \(fetchError?.localizedDescription ?? "")")
                return
            }
            do {
                let world = try WorldBinary(data: bin)
                let atlas = try self.textureLoader.newTexture(data: png, options: [.SRGB: false])
                let cellSize = name.hasPrefix("t") ? 64 : 128
                let columns = atlas.width / cellSize
                guard atlas.width == 2048,
                      atlas.height >= ((world.layers + columns - 1) / columns) * cellSize,
                      let vertices = self.device.makeBuffer(bytes: world.vertices,
                                                            length: world.vertices.count * MemoryLayout<NativeVertex>.stride),
                      let indices = self.device.makeBuffer(bytes: world.indices,
                                                           length: world.indices.count * MemoryLayout<UInt32>.stride) else {
                    self.retryAfter[name] = Date().addingTimeInterval(5)
                    self.onStatus?("INVALID CITY TEXTURE: \(name.uppercased())")
                    return
                }
                self.meshes[name] = Mesh(vertices: vertices, indices: indices,
                                         indexCount: world.indices.count, atlas: atlas)
                if !name.hasPrefix("t"), let col {
                    self.collisions[name] = try? WorldCollision(data: col)
                    self.groundVehicle?.installCell(name, data: col)
                }
                self.onStatus?("CITY READY: \(name.uppercased())")
            } catch {
                self.retryAfter[name] = Date().addingTimeInterval(5)
                self.onStatus?("CITY DATA ERROR: \(error.localizedDescription)")
            }
        }
    }

    var server: ServerAddress?

    func loadModelIndex() {
        guard let server else { return }
        URLSession.shared.dataTask(with:server.path("game/world/peds.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode == 200,
                  let definitions = try? NativeFootAnimationDefinitions(data:data) else { return }
            DispatchQueue.main.async { self?.footDefinitions = definitions;self?.prepareFootAnimation() }
        }.resume()
        URLSession.shared.dataTask(with:server.path("game/native/foot-animation.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode == 200,
                  let definitions = try? NativeFootWeaponAnimation.load(data:data) else { return }
            DispatchQueue.main.async { self?.footWeaponDefinitions = definitions }
        }.resume()
        URLSession.shared.dataTask(with: server.path("game/native/seating.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode == 200,
                  let seating = try? JSONDecoder().decode(NativeVehicleSeating.self,from:data) else { return }
            DispatchQueue.main.async { self?.seating = seating }
        }.resume()
        environment = NativeWorldEnvironment()
        environment?.load(server: server)
        gameCamera.load(server: server) { [weak self] in
            guard let self else { return };self.gameCamera.setDirection(heading: self.heading,pitch: self.cameraPitch)
        }
        atmosphere.load(server: server)
        regionalWeather.load(server: server)
        weatherParticles.load(server: server)
        waterWaves.load(server: server) { [weak self] in
            guard let self,let water = self.worldWater else { return }
            self.waterMesh = self.makeWater(water); self.nearWaterOrigin = nil
        }
        URLSession.shared.dataTask(with: server.path("game/native/effects/waterclear256.png")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode == 200 else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.waterTexture = try? self.textureLoader.newTexture(data: data,options: [.SRGB:false,.generateMipmaps:true])
            }
        }.resume()
        let effectsGroup = DispatchGroup(), effectsLock = NSLock()
        var spriteData: Data?, spriteImage: Data?
        for name in ["index.json","atlas.png"] {
            effectsGroup.enter()
            URLSession.shared.dataTask(with: server.path("game/native/effects/\(name)")) { data,response,_ in
                effectsLock.lock()
                if (response as? HTTPURLResponse)?.statusCode == 200 {
                    if name == "index.json" { spriteData=data } else { spriteImage=data }
                }
                effectsLock.unlock();effectsGroup.leave()
            }.resume()
        }
        effectsGroup.notify(queue:.main) { [weak self] in
            guard let self, let spriteImage, let spriteData,
                  let document = try? JSONSerialization.jsonObject(with:spriteData) as? [String:Any] else { return }
            self.effectSprites = document["sprites"] as? [String:Int] ?? [:]
            self.effectAtlas = try? self.textureLoader.newTexture(data:spriteImage,options:[.SRGB:false])
        }
        URLSession.shared.dataTask(with: server.path("game/native/models/animations.clips.bin")) { [weak self] data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let library = NativeSkeletalAnimationLibrary(data: data)
            DispatchQueue.main.async { self?.skeletalLibrary = library;self?.prepareFootAnimation() }
        }.resume()
        URLSession.shared.dataTask(with: server.path("game/native/models/pedestrians.json")) { [weak self] data, _, _ in
            guard let data, let document = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }
            let anchors = document.mapValues { $0.compactMapValues { ($0 as? [NSNumber])?.map(\.floatValue) } }
            DispatchQueue.main.async { self?.pedestrianAnchors = anchors }
        }.resume()
        URLSession.shared.dataTask(with: server.path("game/world/index.json")) { [weak self] data, _, _ in
            guard let self, let data,
                  let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = document["water"] as? [[NSNumber]] else { return }
            let water = NativeWorldWater(rows: rows.map { $0.map(\.floatValue) })
            let cells = (document["inside"] as? [String: Any])?["cells"] as? [[String: Any]] ?? []
            let inside = Set(cells.compactMap { $0["cell"] as? Int })
            DispatchQueue.main.async {
                self.worldWater = water; self.waterMesh = self.makeWater(water); self.insideCells = inside
                self.loadNearby()
            }
        }.resume()
        URLSession.shared.dataTask(with: server.path("game/native/models/index.json")) { [weak self] data, _, _ in
            guard let self, let data,
                  let index = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else { return }
            DispatchQueue.main.async {
                self.vehicleModels = index["vehicles"] ?? [:]
                self.pedModels = index["peds"] ?? [:]
                self.weaponModels = index["weapons"] ?? [:]
                self.loadActor(self.pedModels["7"] ?? "bmori")
                self.loadActor("colt45")
            }
        }.resume()
        URLSession.shared.dataTask(with: server.path("game/native/handling.json")) { [weak self] data, _, _ in
            guard let self, let data,
                  let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = document["rows"] as? [String: [Any]] else { return }
            let handling = rows.compactMapValues { VehicleHandling(row: $0) }
            let info = document["vehicles"] as? [String: [String: String]] ?? [:]
            DispatchQueue.main.async {
                self.vehicleHandling = handling
                self.vehicleInfo = info
                self.activeHandling = handling[self.activeVehicleModel]
            }
        }.resume()
        URLSession.shared.dataTask(with: server.path("game/native/vehicles.physics.json")) { [weak self] data,response,_ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let cameraDefinitions = (try? JSONDecoder().decode(CameraVehicleDocument.self,from: data))?.models ?? [:]
            DispatchQueue.main.async { self?.groundVehicle?.loadDefinitions(data);self?.cameraVehicleDefinitions = cameraDefinitions }
        }.resume()
    }

    private func actorName(code: String) -> String? {
        if code.hasPrefix("s") { return pedModels[String(code.dropFirst())] }
        return vehicleModels[String(code.split(separator: ".").first ?? "")]
    }

    private func loadActor(_ name: String) {
        guard !name.isEmpty, actorMeshes[name] == nil, !actorLoading.contains(name),
              let server else { return }
        actorLoading.insert(name)
        let group = DispatchGroup()
        let lock = NSLock()
        var binary: Data?
        var image: Data?
        var animation: Data?
        var skeleton: Data?
        var attachment: Data?
        var parts: Data?
        group.enter()
        URLSession.shared.dataTask(with: server.path("game/native/models/\(name).parts.json")) { data, response, _ in
            lock.lock()
            if (response as? HTTPURLResponse)?.statusCode == 200 { parts = data }
            lock.unlock()
            group.leave()
        }.resume()
        group.enter()
        URLSession.shared.dataTask(with: server.path("game/native/models/\(name).bin")) { data, response, _ in
            lock.lock()
            if (response as? HTTPURLResponse)?.statusCode == 200 { binary = data }
            lock.unlock()
            group.leave()
        }.resume()
        group.enter()
        URLSession.shared.dataTask(with: server.path("game/native/models/\(name).png")) { data, response, _ in
            lock.lock()
            if (response as? HTTPURLResponse)?.statusCode == 200 { image = data }
            lock.unlock()
            group.leave()
        }.resume()
        if pedModels.values.contains(name) {
            group.enter()
            URLSession.shared.dataTask(with: server.path("game/native/models/\(name).skel.bin")) { data, response, _ in
                lock.lock()
                let usable = (response as? HTTPURLResponse)?.statusCode == 200
                if usable { skeleton = data }
                lock.unlock()
                if usable { group.leave() }
                else {
                    URLSession.shared.dataTask(with: server.path("game/native/models/\(name).anim.bin")) { data, response, _ in
                        lock.lock()
                        if (response as? HTTPURLResponse)?.statusCode == 200 { animation = data }
                        lock.unlock(); group.leave()
                    }.resume()
                }
            }.resume()
            group.enter()
            URLSession.shared.dataTask(with: server.path("game/native/models/\(name).hand.bin")) { data, response, _ in
                lock.lock()
                if (response as? HTTPURLResponse)?.statusCode == 200 { attachment = data }
                lock.unlock()
                group.leave()
            }.resume()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.actorLoading.remove(name)
            guard let binary, let image,
                  let world = try? WorldBinary(data: binary),
                  let atlas = try? self.textureLoader.newTexture(data: image, options: [.SRGB: false]),
                  let vertices = self.device.makeBuffer(bytes: world.vertices,
                                                       length: world.vertices.count * MemoryLayout<NativeVertex>.stride),
                  let indices = self.device.makeBuffer(bytes: world.indices,
                                                      length: world.indices.count * MemoryLayout<UInt32>.stride) else { return }
            self.actorMeshes[name] = Mesh(vertices: vertices, indices: indices,
                                          indexCount: world.indices.count, atlas: atlas)
            if let skeleton, let actor = NativeSkeletalActor(data: skeleton, vertexCount: world.vertices.count, device: self.device) {
                self.skeletalActors[name] = actor
            }
            if let parts, let decoded = try? JSONDecoder().decode(ActorParts.self, from: parts) {
                if let seat = decoded.driverSeat, seat.count == 3 { self.vehicleSeats[name] = SIMD3(seat[0],seat[1],seat[2]) }
                self.actorParts[name] = decoded.parts.filter {
                    $0.start >= 0 && $0.count > 0 && $0.start + $0.count <= world.indices.count && $0.pivot.count == 3
                }
            }
            if let animation,
               let frames = NativeActorAnimation(data: animation, vertexCount: world.vertices.count,
                                                 device: self.device) {
                self.actorAnimations[name] = frames
            }
            if let attachment, let hand = NativeActorAttachment(data: attachment) {
                self.actorAttachments[name] = hand
            }
        }
    }

    private func nativeCameraVehicle() -> NativeGameCamera.Vehicle? {
        if let value = groundVehicle?.cameraFrame {
            return NativeGameCamera.Vehicle(kind: vehicleKind == "helicopter" ? "heli" : vehicleKind == "bicycle" ? "bike" : vehicleKind,
                position: value.position,forward: value.forward,right: value.right,up: value.up,
                moveSpeed: value.moveSpeed,turnSpeed: value.turnSpeed,wheels: value.wheels,
                bounds: .init(maxX: value.maxX,minY: value.minY,maxZ: value.maxZ,min: value.minimum,max: value.maximum),
                heightAboveRoad: value.heightAboveRoad,eye: value.eye)
        }
        guard let definition = cameraVehicleDefinitions[activeVehicleModel] else { return nil }
        let forward = SIMD3<Float>(sin(heading)*cos(vehiclePitch),cos(heading)*cos(vehiclePitch),sin(vehiclePitch))
        let right = SIMD3<Float>(cos(heading),-sin(heading),0),up = simd_normalize(simd_cross(right,forward))
        func vector(_ row: [Float]?) -> SIMD3<Float>? { guard let row,row.count == 3 else { return nil };return SIMD3(row[0],row[1],row[2]) }
        let eye = vector(definition.driverEye)
        let bounds = definition.bounds
        return NativeGameCamera.Vehicle(kind: definition.kind,position: camera,forward: forward,right: right,up: up,
            moveSpeed: forward*(drivingSpeed/50)+SIMD3(0,0,flightVerticalSpeed/50),turnSpeed: .zero,wheels: flightVerticalSpeed == 0 ? 4 : 0,
            bounds: .init(maxX: bounds.maxX,minY: bounds.minY,maxZ: bounds.maxZ,min: vector(bounds.box?.min),max: vector(bounds.box?.max)),
            heightAboveRoad: definition.origin,eye: eye)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = ProcessInfo.processInfo.systemUptime
        let delta = Float(lastAtmosphereFrame == 0 ? 1/60.0 : max(0,now-lastAtmosphereFrame))
        lastAtmosphereFrame = now; atmosphereMilliseconds += Double(delta)*1000
        let hour = gameHour
        let manualBlend = Float(min(1,max(0,(now-weatherChanged)/4)))
        if returningToRegionalWeather && manualBlend >= 1 { returningToRegionalWeather = false }
        let aspect = max(0.1,Float(view.drawableSize.width/max(1,view.drawableSize.height)))
        if cameraWasDriving != driving {
            cameraWasDriving = driving;gameCamera.resetVehicle()
            gameCamera.setDirection(heading: heading,pitch: cameraPitch)
        }
        if driving,let input = nativeCameraVehicle() {
            gameCameraFrame = gameCamera.followVehicle(input,delta: delta,look: cameraLookDirection,nowMilliseconds: now*1000)
        } else if !driving {
            gameCamera.setDirection(heading: heading,pitch: cameraPitch)
            gameCameraFrame = gameCamera.followFoot(.init(position: camera,actorHeading: actorHeading,weapon: equippedWeapon,
                aiming: aiming,crouching: crouching,sight: aiming ? gameCamera.sightForWeapon(equippedWeapon) : nil),delta: delta)
        } else { gameCameraFrame = nil }
        let defaultDistance: Float = driving ? 11 : 4.5
        let fallbackEye = camera+SIMD3<Float>(-sin(heading)*defaultDistance,-cos(heading)*defaultDistance,driving ? 4.5 : 2.4)
        let eye = gameCameraFrame?.source ?? fallbackEye
        let target = gameCameraFrame?.target ?? (camera+SIMD3(sin(heading)*2,cos(heading)*2,1.2))
        let viewMatrix = Self.lookAt(eye: eye,target: target)
        let forward = -SIMD3(viewMatrix.columns.0.z,viewMatrix.columns.1.z,viewMatrix.columns.2.z)
        let right = SIMD3(viewMatrix.columns.0.x,viewMatrix.columns.1.x,viewMatrix.columns.2.x)
        let up = SIMD3(viewMatrix.columns.0.y,viewMatrix.columns.1.y,viewMatrix.columns.2.y)
        let weather = regionalWeather.pick(automatic: automaticWeather && !returningToRegionalWeather,
            epochMilliseconds: Date().timeIntervalSince1970*1000+weatherClockShiftMilliseconds,position: SIMD2(eye.x,eye.y),
            manualFrom: weatherFrom,manualTo: weatherTo,manualBlend: manualBlend,delta: delta)
        let sampledWeatherFrom = weather.from,sampledWeatherTo = weather.to,blend = weather.blend
        roadWetness = ([8,16].contains(sampledWeatherFrom) ? 1-blend : 0)+([8,16].contains(sampledWeatherTo) ? blend : 0)
        let indoors = camera.z >= 700
        atmosphereAir = indoors ? 0 : eye.z < 900 ? min(1,atmosphereAir+delta) : max(0,atmosphereAir-delta)
        conditions = environment?.sample(weatherFrom: sampledWeatherFrom,to: sampledWeatherTo,blend: blend,hour: hour,altitude: eye.z)
        let planes = gameCamera.projection(air: atmosphereAir,farClip: conditions?.farClip ?? 25000)
        let matrix = Self.perspective(aspect: aspect,verticalFov: gameCameraFrame?.verticalFov ?? 55.41293,near: planes.near,far: planes.far)*viewMatrix
        night = NativeWorldEnvironment.nightShare(hour: hour)
        if let conditions {
            atmosphereSnapshot = atmosphere.update(delta: delta,hour: hour,weatherFrom: sampledWeatherFrom,weatherTo: sampledWeatherTo,blend: blend,
                camera: eye,cameraFar: planes.far,cameraRight: right,cameraUp: up,conditions: conditions,air: atmosphereAir,interiorColor: indoors ? 0 : nil)
            weatherSnapshot = weatherParticles.update(delta: delta,camera: eye,forward: forward,cameraRight: right,cameraUp: up,
                weatherFrom: sampledWeatherFrom,weatherTo: sampledWeatherTo,blend: blend,skyTop: SIMD3(conditions.skyTop.x,conditions.skyTop.y,conditions.skyTop.z),
                outdoors: !indoors,textured: effectAtlas != nil,ground: { [weak self] x,y,z,drop in
                    guard let self else { return nil }
                    return self.collisionFor(SIMD3(x,y,self.camera.z))?.height(x: x,y: y,near: z,maxDrop: drop)
                })
            waterWaves.set(timeMilliseconds: atmosphereMilliseconds,roughness: waterWaves.weatherRoughness(from: sampledWeatherFrom,to: sampledWeatherTo,blend: blend))
            waterWaves.look(x: eye.x,y: eye.y)
            view.clearColor = MTLClearColor(red: Double(conditions.skyBottom.x),green: Double(conditions.skyBottom.y),blue: Double(conditions.skyBottom.z),alpha: 1)
        }
        guard let drawable = view.currentDrawable,let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer(),let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setCullMode(.none)
        if let skyPipeline,let conditions {
            let below = atmosphereSnapshot?.belowColor ?? SIMD3(conditions.skyBottom.x,conditions.skyBottom.y,conditions.skyBottom.z)
            var uniforms = DomeUniforms(inverseMatrix: matrix.inverse,eye: SIMD4(eye,1),forward: SIMD4(forward,0),
                high: conditions.skyTop,low: weatherSnapshot?.flash == true ? SIMD4(1,1,1,1) : conditions.skyBottom,
                below: SIMD4(below,1),settings: SIMD4(atmosphereAir,indoors ? 1 : 0,0,0))
            encoder.setRenderPipelineState(skyPipeline); encoder.setDepthStencilState(skyDepth)
            encoder.setFragmentBytes(&uniforms,length: MemoryLayout<DomeUniforms>.stride,index: 1)
            encoder.drawPrimitives(type: .triangle,vertexStart: 0,vertexCount: 3)
        }
        if let atmosphereSnapshot {
            drawAtmosphereQuads(atmosphereSnapshot.quads.filter(\.paintedOnSky),matrix: matrix,encoder: encoder)
            drawSkyDetails(atmosphereSnapshot,eye: eye,matrix: matrix,encoder: encoder)
        }
        encoder.setRenderPipelineState(pipeline); encoder.setDepthStencilState(depth)
        for (name,mesh) in meshes where name.hasPrefix("t") {
            encoder.setDepthBias(0.0005,slopeScale: 0,clamp: 0)
            draw(mesh: mesh,cellSize: 64,matrix: matrix,encoder: encoder)
        }
        encoder.setDepthBias(0,slopeScale: 0,clamp: 0)
        for name in activeDetails { if let mesh = meshes[name] { draw(mesh: mesh,cellSize: 128,matrix: matrix,encoder: encoder) } }
        drawActors(encoder: encoder,matrix: matrix)
        if !indoors { drawWater(eye: eye,matrix: matrix,encoder: encoder) }
        if let atmosphereSnapshot { drawAtmosphereQuads(atmosphereSnapshot.quads.filter { !$0.paintedOnSky },matrix: matrix,encoder: encoder) }
        drawEffects(encoder: encoder,matrix: matrix)
        if let weatherSnapshot {
            drawAtmosphereQuads(weatherSnapshot.quads,matrix: matrix,encoder: encoder)
            drawRainLines(weatherSnapshot.lines,matrix: matrix,encoder: encoder)
        }
        drawObjective(encoder: encoder,matrix: matrix)
        encoder.endEncoding(); command.present(drawable); command.commit(); onFrame?()
    }

    private func makeObjectiveMarker() -> Mesh? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        guard let atlas = device.makeTexture(descriptor: textureDescriptor) else { return nil }
        let white: [UInt8] = [255, 255, 255, 255]
        white.withUnsafeBytes { bytes in
            atlas.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                          withBytes: bytes.baseAddress!, bytesPerRow: 4)
        }
        var vertices: [NativeVertex] = []
        var indices: [UInt32] = []
        func vertex(_ x: Float, _ y: Float, _ z: Float, alpha: Float) {
            let tint = SIMD4<Float>(1, 0.64, 0.06, alpha)
            vertices.append(NativeVertex(position: SIMD4(x, y, z, 1),
                                         uvLayer: SIMD4(0.5, 0.5, 0, 0),
                                         tint: tint, dusk: tint))
        }
        let sections = 40
        for n in 0..<sections {
            let a = Float(n) * 2 * .pi / Float(sections)
            let b = Float(n + 1) * 2 * .pi / Float(sections)
            let base = UInt32(vertices.count)
            vertex(cos(a) * 1.0, sin(a) * 1.0, 0.12, alpha: 0.62)
            vertex(cos(a) * 1.18, sin(a) * 1.18, 0.12, alpha: 0.62)
            vertex(cos(b) * 1.0, sin(b) * 1.0, 0.12, alpha: 0.62)
            vertex(cos(b) * 1.18, sin(b) * 1.18, 0.12, alpha: 0.62)
            indices += [base, base + 1, base + 2, base + 1, base + 3, base + 2]
            let wall = UInt32(vertices.count)
            vertex(cos(a) * 1.0, sin(a) * 1.0, 0.15, alpha: 0.06)
            vertex(cos(b) * 1.0, sin(b) * 1.0, 0.15, alpha: 0.06)
            vertex(cos(a) * 1.0, sin(a) * 1.0, 2.2, alpha: 0.14)
            vertex(cos(b) * 1.0, sin(b) * 1.0, 2.2, alpha: 0.14)
            indices += [wall, wall + 1, wall + 2, wall + 1, wall + 3, wall + 2]
        }
        guard let vertexBuffer = device.makeBuffer(bytes: vertices,
                                                   length: vertices.count * MemoryLayout<NativeVertex>.stride),
              let indexBuffer = device.makeBuffer(bytes: indices,
                                                  length: indices.count * MemoryLayout<UInt32>.stride)
        else { return nil }
        return Mesh(vertices: vertexBuffer, indices: indexBuffer,
                    indexCount: indices.count, atlas: atlas)
    }

    private func makeWater(_ water: NativeWorldWater) -> Mesh? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        guard let atlas = device.makeTexture(descriptor: descriptor) else { return nil }
        let pixel: [UInt8] = [255,255,255,255]
        pixel.withUnsafeBytes { atlas.replace(region: MTLRegionMake2D(0,0,1,1), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 4) }
        var vertices: [NativeVertex] = []; var indices: [UInt32] = []
        let outside: [[SIMD3<Float>]] = [(-40000 as Float,-40000 as Float,40000 as Float,-3000 as Float),(-40000,3000,40000,40000),(-40000,-3000,-3000,3000),(3000,-3000,40000,3000)].map { x0,y0,x1,y1 in [SIMD3(x0,y0,0),SIMD3(x1,y0,0),SIMD3(x0,y1,0),SIMD3(x1,y1,0)] }
        for (index,p) in (water.polygons+outside).enumerated() {
            let wavy = index >= water.polygons.count || waterWaves.isWavy(min: SIMD2(p.map(\.x).min()!,p.map(\.y).min()!),max: SIMD2(p.map(\.x).max()!,p.map(\.y).max()!))
            let base = UInt32(vertices.count)
            for point in p {
                let tint = SIMD4<Float>(1,1,1,1)
                vertices.append(NativeVertex(position: SIMD4(point.x,point.y,point.z,1), uvLayer: SIMD4(0,0,wavy ? 1 : 0,0), tint: tint, dusk: tint))
            }
            indices += [base,base+1,base+2]
            if p.count == 4 { indices += [base+1,base+3,base+2] }
        }
        guard !vertices.isEmpty, let v = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<NativeVertex>.stride),
              let i = device.makeBuffer(bytes: indices, length: indices.count * 4) else { return nil }
        return Mesh(vertices: v, indices: i, indexCount: indices.count, atlas: atlas)
    }

    private func drawAtmosphereGeometry(vertices: [NativeVertex],indices: [UInt32] = [],key: String,
                                        matrix: simd_float4x4,depthTest: Bool,primitive: MTLPrimitiveType = .triangle,
                                        encoder: MTLRenderCommandEncoder) {
        guard !vertices.isEmpty,let pipeline = atmospherePipelines[key],
              let buffer = device.makeBuffer(bytes: vertices,length: vertices.count*MemoryLayout<NativeVertex>.stride) else { return }
        var uniforms = AtmosphereUniforms(matrix: matrix,atlas: SIMD4(Float(effectAtlas?.width ?? 2048),Float(effectAtlas?.height ?? 128),128,0))
        encoder.setRenderPipelineState(pipeline); encoder.setDepthStencilState(depthTest ? markerDepth : skyDepth)
        encoder.setVertexBuffer(buffer,offset: 0,index: 0)
        encoder.setVertexBytes(&uniforms,length: MemoryLayout<AtmosphereUniforms>.stride,index: 1)
        encoder.setFragmentBytes(&uniforms,length: MemoryLayout<AtmosphereUniforms>.stride,index: 1)
        if let effectAtlas { encoder.setFragmentTexture(effectAtlas,index: 0) }
        if indices.isEmpty { encoder.drawPrimitives(type: primitive,vertexStart: 0,vertexCount: vertices.count) }
        else if let index = device.makeBuffer(bytes: indices,length: indices.count*4) {
            encoder.drawIndexedPrimitives(type: primitive,indexCount: indices.count,indexType: .uint32,indexBuffer: index,indexBufferOffset: 0)
        }
    }
    private func drawAtmosphereQuads(_ quads: [NativeAtmosphere.Quad],matrix: simd_float4x4,encoder: MTLRenderCommandEncoder) {
        guard effectAtlas != nil else { return }
        var vertices: [NativeVertex] = [],indices: [UInt32] = [],key = "",testDepth = true
        func flush() {
            drawAtmosphereGeometry(vertices: vertices,indices: indices,key: key,matrix: matrix,depthTest: testDepth,encoder: encoder)
            vertices.removeAll(keepingCapacity: true); indices.removeAll(keepingCapacity: true)
        }
        for quad in quads {
            guard let slot = effectSprites[quad.texture] else { continue }
            let nextKey = quad.shading == .sky ? "sky" : quad.shading == .cloud ? "cloud" : quad.blend == .additive ? "splash" : "particle"
            if nextKey != key || quad.depthTest != testDepth { flush(); key = nextKey; testDepth = quad.depthTest }
            let base = UInt32(vertices.count)
            for (x,y) in [(Float(-1),Float(-1)),(1,-1),(-1,1),(1,1)] {
                let point = quad.center+quad.right*x+quad.up*y
                let tint = x < 0 && y > 0 ? quad.topLeftTint ?? quad.tint : quad.tint
                let u = x*0.5+0.5,v = quad.flipV ? 0.5-y*0.5 : y*0.5+0.5
                vertices.append(NativeVertex(position: SIMD4(point,1),uvLayer: SIMD4(u,v,Float(slot),quad.paintedOnSky ? 1 : 0),tint: tint,dusk: tint))
            }
            indices += [base,base+1,base+2,base+1,base+3,base+2]
        }
        flush()
    }
    private func drawSkyDetails(_ sky: NativeAtmosphere.Snapshot,eye: SIMD3<Float>,matrix: simd_float4x4,encoder: MTLRenderCommandEncoder) {
        if let bow = sky.rainbow {
            var vertices: [NativeVertex] = [],indices: [UInt32] = []
            for turn in 0...96 {
                let angle = Float(turn)/96*6.28319
                for band in [Float(0),1] {
                    let wide = (bow.angle+(band-0.5)*bow.width)*Float.pi/180
                    let way = bow.middle*cos(wide)+(bow.across*cos(angle)+bow.over*sin(angle))*sin(wide)
                    let tint = SIMD4<Float>(bow.strength,1,1,1)
                    vertices.append(NativeVertex(position: SIMD4(eye+way*bow.distance,1),uvLayer: SIMD4(Float(turn)/96,band,way.z,1),tint: tint,dusk: tint))
                }
                if turn < 96 { let n = UInt32(turn*2); indices += [n,n+2,n+1,n+2,n+3,n+1] }
            }
            drawAtmosphereGeometry(vertices: vertices,indices: indices,key: "rainbow",matrix: matrix,depthTest: false,encoder: encoder)
        }
        if let meteor = sky.meteor {
            let vertices = [(meteor.head,meteor.headAlpha),(meteor.tail,Float(0))].map { point,alpha in
                NativeVertex(position: SIMD4(point,1),uvLayer: SIMD4(0,0,0,1),tint: SIMD4(1,1,1,alpha),dusk: .zero)
            }
            drawAtmosphereGeometry(vertices: vertices,key: "color",matrix: matrix,depthTest: false,primitive: .line,encoder: encoder)
        }
    }
    private func drawRainLines(_ lines: [NativeWeatherParticles.Line],matrix: simd_float4x4,encoder: MTLRenderCommandEncoder) {
        var vertices: [NativeVertex] = []
        for line in lines {
            for (point,alpha) in [(line.from,line.fromAlpha),(line.to,line.toAlpha)] {
                vertices.append(NativeVertex(position: SIMD4(point,1),uvLayer: .zero,tint: SIMD4(line.color,alpha),dusk: .zero))
            }
        }
        drawAtmosphereGeometry(vertices: vertices,key: "color",matrix: matrix,depthTest: true,primitive: .line,encoder: encoder)
    }
    private func drawWater(eye: SIMD3<Float>,matrix: simd_float4x4,encoder: MTLRenderCommandEncoder) {
        guard let waterPipeline,let waterTexture,let waterMesh,let worldWater,let conditions,waterWaves.isLoaded else { return }
        if nearWaterOrigin == nil || abs(eye.x-nearWaterOrigin!.x) > 16 || abs(eye.y-nearWaterOrigin!.y) > 16 {
            let origin = SIMD2<Float>(2*floor(eye.x/2+0.5),2*floor(eye.y/2+0.5))
            nearWaterOrigin = origin; nearWaterMesh = nil
            if let sea = waterWaves.nearGrid(origin: origin,ground: { x,y in worldWater.height(x: x,y: y,z: 0) }) {
                var vertices: [NativeVertex] = []; vertices.reserveCapacity(265*265)
                var indices: [UInt32] = []; indices.reserveCapacity(418176)
                for row in 0..<265 { for col in 0..<265 {
                    let value = sea[row*265+col],point = SIMD3(origin.x+Float(col)*0.5-66,origin.y+Float(row)*0.5-66,value.x)
                    vertices.append(NativeVertex(position: SIMD4(point,1),uvLayer: SIMD4(value.y,value.z,value.w,1),tint: .zero,dusk: .zero))
                } }
                for row in 0..<264 { for col in 0..<264 { let n = UInt32(row*265+col); indices += [n,n+1,n+265,n+1,n+266,n+265] } }
                if let v = device.makeBuffer(bytes: vertices,length: vertices.count*MemoryLayout<NativeVertex>.stride),
                   let i = device.makeBuffer(bytes: indices,length: indices.count*4) {
                    nearWaterMesh = Mesh(vertices: v,indices: i,indexCount: indices.count,atlas: waterTexture)
                }
            }
        }
        let render = waterWaves.renderUniforms(timeMilliseconds: atmosphereMilliseconds,color: conditions.waterColor)
        let x = waterWaves.xFactors,y = waterWaves.yFactors
        guard x.count == 8,y.count == 8 else { return }
        let origin = nearWaterOrigin ?? .zero
        let visible = nearWaterMesh != nil && waterWaves.rough > 0
        var uniforms = WaterUniforms(matrix: matrix,eye: SIMD4(eye,1),tint: render.tint,alphas: SIMD4(render.alphas.x,render.alphas.y,0,0),shifts: render.shifts,
            waves: SIMD4(render.waves.x,render.waves.y,render.waves.z,waterWaves.rough),
            fogColor: weatherSnapshot?.flash == true ? SIMD4(1,1,1,1) : conditions.skyBottom,
            fog: SIMD4(conditions.fogStart,conditions.farClip,atmosphereAir,0),net: SIMD4(origin.x,origin.y,visible ? 65 : 0,0),
            alongX0: SIMD4(x[0],x[1],x[2],x[3]),alongX1: SIMD4(x[4],x[5],x[6],x[7]),
            alongY0: SIMD4(y[0],y[1],y[2],y[3]),alongY1: SIMD4(y[4],y[5],y[6],y[7]))
        encoder.setRenderPipelineState(waterPipeline); encoder.setDepthStencilState(depth)
        encoder.setVertexBytes(&uniforms,length: MemoryLayout<WaterUniforms>.stride,index: 1)
        encoder.setFragmentBytes(&uniforms,length: MemoryLayout<WaterUniforms>.stride,index: 1)
        encoder.setFragmentTexture(waterTexture,index: 0)
        for mesh in [waterMesh]+(visible ? [nearWaterMesh!] : []) {
            encoder.setVertexBuffer(mesh.vertices,offset: 0,index: 0)
            encoder.setDepthBias(mesh.vertices === nearWaterMesh?.vertices ? 0.0005 : 0,slopeScale: 0,clamp: 0)
            encoder.drawIndexedPrimitives(type: .triangle,indexCount: mesh.indexCount,indexType: .uint32,indexBuffer: mesh.indices,indexBufferOffset: 0)
        }
        encoder.setDepthBias(0,slopeScale: 0,clamp: 0)
    }

    private func drawObjective(encoder: MTLRenderCommandEncoder, matrix: simd_float4x4) {
        guard let objective, let objectiveMarker,
              simd_distance(objective, SIMD2(camera.x, camera.y)) <= 180 else { return }
        let floor = collision?.height(x: objective.x, y: objective.y,
                                      near: camera.z, maxDrop: 25) ?? camera.z
        let pulse = 1 + 0.08 * sin(Float(ProcessInfo.processInfo.systemUptime) * 3)
        let transform = simd_float4x4(columns: (
            SIMD4(pulse, 0, 0, 0), SIMD4(0, pulse, 0, 0),
            SIMD4(0, 0, 1, 0), SIMD4(objective.x, objective.y, floor, 1)))
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(markerDepth)
        draw(mesh: objectiveMarker, cellSize: 1, matrix: matrix * transform, encoder: encoder)
        encoder.setDepthStencilState(depth)
    }

    private func draw(mesh: Mesh, cellSize: Float, matrix: simd_float4x4,
                      encoder: MTLRenderCommandEncoder, tint: SIMD4<Float> = SIMD4(1,1,1,1)) {
        var uniforms = Uniforms(viewProjection: matrix,
                                settings: SIMD4(Float(mesh.atlas.width), Float(mesh.atlas.height),
                                                night, cellSize))
        configureEnvironment(&uniforms)
        uniforms.tintColor = tint
        encoder.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentTexture(mesh.atlas, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount,
                                      indexType: .uint32, indexBuffer: mesh.indices, indexBufferOffset: 0)
    }

    private func drawActors(encoder: MTLRenderCommandEncoder, matrix: simd_float4x4) {
        var modelInstances: [(String, SIMD3<Float>, Float, Float, String, Double, Int)] = []
        var driverPosition: SIMD3<Float>?
        var driverTransform: simd_float4x4?
        var driverPose: NativeSkeletalActor.Pose?
        var remoteDriverTransforms: [String:simd_float4x4] = [:]
        var remoteDriverPoses: [String:NativeSkeletalActor.Pose] = [:]
        func key(_ name: String,_ position: SIMD3<Float>) -> String { "\(name):\(position)" }
        if driving {
            let code = remoteVehicles.first(where: { $0.id == currentVehicleID })?.code ?? "420.6.1.0."
            if let name = actorName(code: code) {
                modelInstances.append((name, camera, heading, vehiclePitch, "", 0, 0))
                if let seat = vehicleSeats[name], let ped = pedModels["7"] {
                    let time = ProcessInfo.processInfo.systemUptime - entryStarted
                    let definition = seating?.models[activeVehicleModel]
                    let entry = definition?.clip("entry") ?? "ped/car_getin_lhs"
                    let duration = skeletalLibrary?.duration(of: entry) ?? 1
                    let entering = time < duration
                    let seated = definition?.clip(abs(drivingSpeed) < 0.5 ? "still" : "sit") ?? "ped/car_sit"
                    let clip = entering ? entry : seated
                    let elapsed = entering ? time : ownClipTime
                    var layers: [NativeSkeletalLayer] = []
                    if !entering,let definition {
                        let weight = min(1,abs(steeringInput))
                        let steerClip = definition.clip(steeringInput < 0 ? "left" : "right")
                        if skeletalLibrary?.contains(steerClip) == true && weight > 0 {
                            layers.append(.init(clip:steerClip,elapsed:elapsed,weight:weight))
                        }
                    }
                    driverPose = skeletalActors[ped].flatMap { actor in skeletalLibrary.flatMap {
                        actor.pose(clip:clip,elapsed:elapsed,library:$0,layers:layers,looping:!entering)
                    } }
                    let alias = entering ? "entryEnd" : "car_sit"
                    let fallback = pedestrianAnchors[ped]?[alias]
                    if driverPose != nil || fallback?.count == 3 {
                        let pelvis = driverPose.map { SIMD3($0.pelvis.columns.3.x,$0.pelvis.columns.3.y,$0.pelvis.columns.3.z) } ??
                            SIMD3(fallback![0],fallback![1],fallback![2])
                        let car = nativeVehicleTransform ?? (Self.translation(camera) * Self.rotationZ(-heading) * Self.rotationX(vehiclePitch))
                        var transform = car * Self.translation(seat) * Self.rotationZ(.pi) * Self.translation(-pelvis)
                        let sitting = SIMD3(transform.columns.3.x,transform.columns.3.y,transform.columns.3.z)
                        let amount = Float(min(1,max(0,time/max(0.001,duration))))
                        let at = entering ? entryOrigin+(sitting-entryOrigin)*amount : sitting
                        transform.columns.3 = SIMD4(at,1)
                        driverTransform = transform; driverPosition = at
                        modelInstances.append((ped,at,heading,0,clip,elapsed,0))
                    }
                }
            }
        } else if !scopedCameraHidesPlayer,let name = pedModels["7"] {
            modelInstances.append((name, camera, actorHeading, swimmingPitch, ownClip, ownClipTime, swimming ? 0 : equippedWeapon))
        }
        for player in remotePlayers where simd_distance(player.position, camera) < 130 {
            if let name = actorName(code: player.code) {
                let inVehicle = player.vehicleID != nil
                modelInstances.append((name, player.position, player.heading, player.pitch,
                                       inVehicle ? "" : player.animation, ProcessInfo.processInfo.systemUptime-player.animationStarted,
                                       inVehicle ? 0 : player.weapon))
                if inVehicle, let seat = vehicleSeats[name],let ped = pedModels[String(player.skin)],
                   let actor = skeletalActors[ped],let library = skeletalLibrary {
                    let model = String(player.code.split(separator:".").first ?? "")
                    let definition = seating?.models[model]
                    let clip = definition?.clip(abs(player.speed) < 0.5 ? "still" : "sit") ?? "ped/car_sit"
                    let elapsed = ProcessInfo.processInfo.systemUptime-player.animationStarted
                    var layers: [NativeSkeletalLayer] = []
                    if let definition,abs(player.steer) > 0 {
                        let steerClip = definition.clip(player.steer < 0 ? "left" : "right")
                        if library.contains(steerClip) { layers.append(.init(clip:steerClip,elapsed:elapsed,weight:min(1,abs(player.steer)))) }
                    }
                    if let pose = actor.pose(clip:clip,elapsed:elapsed,library:library,layers:layers) {
                        let pelvis = SIMD3(pose.pelvis.columns.3.x,pose.pelvis.columns.3.y,pose.pelvis.columns.3.z)
                        let car = Self.translation(player.position) * Self.rotationZ(-player.heading) *
                            Self.rotationX(player.pitch) * Self.rotationY(player.roll) *
                            Self.translation(SIMD3(0,0,vehicleModelOrigin(player.code)))
                        let transform = car * Self.translation(seat) * Self.rotationZ(.pi) * Self.translation(-pelvis)
                        let position = SIMD3(transform.columns.3.x,transform.columns.3.y,transform.columns.3.z)
                        remoteDriverTransforms[key(ped,position)] = transform;remoteDriverPoses[key(ped,position)] = pose
                        modelInstances.append((ped,position,player.heading,player.pitch,clip,elapsed,0))
                    }
                } else if inVehicle,let ped = pedModels[String(player.skin)] { loadActor(ped) }
            }
        }
        let drivenVehicleIDs = Set(remotePlayers.compactMap(\.vehicleID))
        for projectile in weaponEffects.projectiles {
            let direction = atan2(projectile.velocity.x,projectile.velocity.y)
            let pitch = atan2(projectile.velocity.z,hypot(projectile.velocity.x,projectile.velocity.y))
            modelInstances.append((projectile.model,projectile.position,direction,pitch,"",0,0))
        }
        for vehicle in remoteVehicles where vehicle.id != currentVehicleID &&
            !drivenVehicleIDs.contains(vehicle.id) &&
            simd_distance(vehicle.position, camera) < 130 {
            if let name = actorName(code: vehicle.code) {
                modelInstances.append((name, vehicle.position, vehicle.heading, vehicle.pitch, "", 0, 0))
            }
        }
        for (name, position, angle, pitch, clip, elapsed, weapon) in modelInstances {
            guard let mesh = actorMeshes[name] else { loadActor(name); continue }
            let originalFoot = !driving && name == pedModels["7"] && position == camera &&
                footAnimationFrame != nil && skeletalActors[name] != nil
            // Archived pedestrian DFFs face local -Y after the RenderWare axis
            // conversion, while the world protocol defines heading zero as +Y.
            let modelAngle = angle + (pedModels.values.contains(name) && !originalFoot ? Float.pi : 0)
            let c = cos(modelAngle), s = sin(modelAngle)
            // The pedestrian's fixed model-facing half turn is below its
            // body-pitch pivot in the original hierarchy. Commuting it into
            // this single model matrix reverses the local X rotation.
            let bodyPitch = originalFoot ? 0 : pedModels.values.contains(name) ? -pitch : pitch
            let cp = cos(bodyPitch), sp = sin(bodyPitch)
            var transform = simd_float4x4(columns: (
                SIMD4(c, -s, 0, 0), SIMD4(s * cp, c * cp, sp, 0),
                SIMD4(-s * sp, -c * sp, cp, 0),
                SIMD4(position.x, position.y, position.z, 1)))
            if clip.isEmpty,let vehicle = remotePlayers.first(where: { $0.position == position && $0.vehicleID != nil }) {
                transform *= Self.rotationY(vehicle.roll)
                transform *= Self.translation(SIMD3(0,0,vehicleModelOrigin(vehicle.code)))
            } else if clip.isEmpty,let vehicle = remoteVehicles.first(where: { $0.position == position && actorName(code:$0.code) == name }) {
                transform *= Self.rotationY(vehicle.roll)
                transform *= Self.translation(SIMD3(0,0,vehicleModelOrigin(vehicle.code)))
            }
            if driving && position == camera && clip.isEmpty, let exact = nativeVehicleTransform { transform = exact }
            if name == pedModels["7"] && position == driverPosition, let driverTransform { transform = driverTransform }
            if let remote = remoteDriverTransforms[key(name,position)] { transform = remote }
            var uniforms = Uniforms(viewProjection: matrix * transform,
                                    settings: SIMD4(Float(mesh.atlas.width), Float(mesh.atlas.height), night, 128))
            configureEnvironment(&uniforms)
            let locomotion = name == pedModels["7"] && position == camera && !driving && actionTimeRemaining > 0 &&
                !swimming && health > 0 ? locomotionClip : nil
            let wire = clip.split(separator: "/")
            let loops: Bool? = wire.count >= 2 ? (wire.count < 3 || wire[2] == "l") : nil
            let sampledPose = skeletalActors[name].flatMap { actor in skeletalLibrary.flatMap {
                if originalFoot,let frame = footAnimationFrame {
                    return actor.originalPose(blends:frame.blends,library:$0,aim:frame.aim,hiddenBones:frame.hiddenBones,figurePitch:frame.figurePitch)
                }
                return actor.pose(clip: clip, elapsed: elapsed, library: $0,
                           locomotion: locomotion, locomotionElapsed: locomotionTime, looping: loops)
            } }
            let ownPose = name == pedModels["7"] && position == driverPosition ? (driverPose ?? sampledPose) : sampledPose
            let pose = remoteDriverPoses[key(name,position)] ?? ownPose
            if let pose, let actor = skeletalActors[name], let skeletalPipeline {
                encoder.setRenderPipelineState(skeletalPipeline)
                actor.bind(pose: pose, encoder: encoder)
            } else if let frames = actorAnimations[name]?.sample(clip: clip, elapsed: elapsed) {
                encoder.setRenderPipelineState(animatedPipeline)
                encoder.setVertexBuffer(frames.0, offset: 0, index: 2)
                encoder.setVertexBuffer(frames.1, offset: 0, index: 3)
                var blend = frames.2
                encoder.setVertexBytes(&blend, length: MemoryLayout<Float>.stride, index: 4)
            } else {
                encoder.setRenderPipelineState(pipeline)
            }
            encoder.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentTexture(mesh.atlas, index: 0)
            if clip.isEmpty, let parts = actorParts[name], !parts.isEmpty {
                let speed = position == camera && driving ? drivingSpeed : 0
                for part in parts {
                    let pivot = SIMD3<Float>(part.pivot[0], part.pivot[1], part.pivot[2])
                    var local = matrix_identity_float4x4
                    if let wheel = part.wheel {
                        let index = wheel.contains("lf_") ? 0 : wheel.contains("lb_") || wheel.contains("lr_") ? 1 : wheel.contains("rf_") ? 2 : 3
                        let exact = position == camera && nativeVehicleTransform != nil
                        let state = exact ? nativeVehicleWheels.first(where: { $0.index == index }) : nil
                        let spin = exact ? nativeVehicleWheelAngles[index] : Float(ProcessInfo.processInfo.systemUptime)*speed/0.35
                        let turn = exact ? (wheel.contains("f_dummy") ? -(groundVehicle?.output?.steering ?? 0) : -(groundVehicle?.output?.rearSteering ?? 0)) :
                            Double(wheel.contains("f_dummy") && speed != 0 ? steeringInput*0.45 : 0)
                        local = Self.translation(SIMD3(0,0,Float(state?.offset ?? 0))) * Self.translation(pivot) *
                            Self.rotationZ(Float(turn)) * Self.rotationX(spin) * Self.translation(-pivot)
                    } else if part.name.hasPrefix("static_prop") && speed != 0 {
                        local = Self.translation(pivot) * Self.rotationY(Float(ProcessInfo.processInfo.systemUptime) * 35) * Self.translation(-pivot)
                    } else if part.name.hasPrefix("static_rotor") && speed != 0 {
                        local = Self.translation(pivot) * Self.rotationZ(Float(ProcessInfo.processInfo.systemUptime) * 35) * Self.translation(-pivot)
                    }
                    uniforms.viewProjection = matrix * transform * local
                    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                    encoder.drawIndexedPrimitives(type: .triangle, indexCount: part.count,
                        indexType: .uint32, indexBuffer: mesh.indices, indexBufferOffset: part.start * 4)
                }
            } else {
                encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount,
                                              indexType: .uint32, indexBuffer: mesh.indices, indexBufferOffset: 0)
            }
            if let weaponName = weaponModels[String(weapon)], weapon > 0,
               let pistol = actorMeshes[weaponName],
               let hand = pose?.hand ?? actorAttachments[name]?.frame(clip: clip, elapsed: elapsed) {
                encoder.setRenderPipelineState(pipeline)
                draw(mesh: pistol, cellSize: 128, matrix: matrix * transform * hand,
                     encoder: encoder)
            } else if let weaponName = weaponModels[String(weapon)], weapon > 0 {
                loadActor(weaponName)
            }
        }
        let visible = Set(modelInstances.map { $0.0 } + modelInstances.compactMap { weaponModels[String($0.6)] })
        if actorMeshes.count > 32 {
            actorMeshes = actorMeshes.filter { visible.contains($0.key) }
            actorAnimations = actorAnimations.filter { visible.contains($0.key) }
            skeletalActors = skeletalActors.filter { visible.contains($0.key) }
            actorAttachments = actorAttachments.filter { visible.contains($0.key) }
            actorParts = actorParts.filter { visible.contains($0.key) }
        }
    }

    private func configureEnvironment(_ uniforms: inout Uniforms) {
        guard let conditions, camera.z < 700 else { return }
        uniforms.fogColor = weatherSnapshot?.flash == true ? SIMD4(1,1,1,1) : conditions.skyBottom
        uniforms.fogSettings = SIMD4(conditions.fogStart,conditions.farClip,atmosphereAir,0)
    }

    private func drawEffects(encoder: MTLRenderCommandEncoder, matrix: simd_float4x4) {
        guard let atlas = effectAtlas else { return }
        let now = ProcessInfo.processInfo.systemUptime
        blasts.removeAll { now-$0.2 > 1.1 }
        var vertices: [NativeVertex] = [], indices: [UInt32] = []
        let right = SIMD3<Float>(cos(heading),-sin(heading),0)
        func sprite(_ name: String, at point: SIMD3<Float>, width: Float, height: Float, color: SIMD4<Float>) {
            guard let slot = effectSprites[name] else { return }
            let base = UInt32(vertices.count)
            for (x,y,u,v) in [(-1 as Float,-1 as Float,0 as Float,1 as Float),(1,-1,1,1),(-1,1,0,0),(1,1,1,0)] {
                let p = point + right*(x*width/2) + SIMD3<Float>(0,0,y*height/2)
                vertices.append(NativeVertex(position:SIMD4(p.x,p.y,p.z,1),uvLayer:SIMD4(u,v,Float(slot),0),tint:color,dusk:color))
            }
            indices += [base,base+1,base+2,base+1,base+3,base+2]
        }
        for (position,_,started) in blasts {
            let age = Float(now-started), size = 1+age*7
            sprite("fireball6",at:position+SIMD3(0,0,size*0.25),width:size,height:size,color:SIMD4(1,0.65,0.22,max(0,1-age)))
            if age > 0.15 { sprite("smoke5",at:position+SIMD3(0,0,age*4),width:size*1.3,height:size,color:SIMD4(0.3,0.3,0.3,0.45*(1-age))) }
        }
        for fire in weaponEffects.fires { for flame in fire.flames where flame.strength > 0 {
            sprite("fireball6",at:flame.position+SIMD3(0,0,0.8),width:1,height:1.8,color:SIMD4(1,0.55,0.1,min(1,flame.strength)))
        } }
        for stream in weaponEffects.streams {
            let texture = stream.weapon == 37 ? "fireball6" : stream.weapon == 42 ? "smoke" : "sphere"
            let color = stream.weapon == 37 ? SIMD4<Float>(1,0.55,0.1,0.6) : SIMD4<Float>(0.9,0.95,1,0.35)
            for n in 1...12 {
                let share = Float(n)/12, spread = 0.15+share*0.7
                sprite(texture,at:stream.position+stream.direction*(share*stream.range),width:spread,height:spread,color:color)
            }
        }
        for projectile in weaponEffects.projectiles where projectile.weapon == 17 && projectile.age > 0.5 {
            sprite("smoke5",at:projectile.position+SIMD3(0,0,0.8),width:2,height:2,color:SIMD4(0.7,0.8,0.65,0.35))
        }
        guard !vertices.isEmpty,
              let v = device.makeBuffer(bytes:vertices,length:vertices.count*MemoryLayout<NativeVertex>.stride),
              let i = device.makeBuffer(bytes:indices,length:indices.count*4) else { return }
        encoder.setRenderPipelineState(pipeline);encoder.setDepthStencilState(markerDepth)
        draw(mesh:Mesh(vertices:v,indices:i,indexCount:indices.count,atlas:atlas),cellSize:128,matrix:matrix,encoder:encoder)
        encoder.setDepthStencilState(depth)
    }

    private static func translation(_ p: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4; m.columns.3 = SIMD4(p.x, p.y, p.z, 1); return m
    }
    private static func rotationX(_ a: Float) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(1,0,0,0), SIMD4(0,cos(a),sin(a),0), SIMD4(0,-sin(a),cos(a),0), SIMD4(0,0,0,1)))
    }
    private static func rotationY(_ a: Float) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(cos(a),0,-sin(a),0), SIMD4(0,1,0,0), SIMD4(sin(a),0,cos(a),0), SIMD4(0,0,0,1)))
    }
    private static func rotationZ(_ a: Float) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4(cos(a),sin(a),0,0), SIMD4(-sin(a),cos(a),0,0), SIMD4(0,0,1,0), SIMD4(0,0,0,1)))
    }

    private static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
        var forward = target-eye
        if simd_length_squared(forward) == 0 { forward = SIMD3(0,1,0) }
        forward = simd_normalize(forward)
        var right = simd_cross(forward,SIMD3<Float>(0,0,1))
        // Three.Matrix4.lookAt perturbs its local z by 0.0001 when view and
        // up are parallel. Its local z maps to negative GTA y.
        if simd_length_squared(right) == 0 {
            forward.y += 0.0001;forward = simd_normalize(forward)
            right = simd_cross(forward,SIMD3<Float>(0,0,1))
        }
        right = simd_normalize(right)
        let up = simd_cross(right,forward)
        return simd_float4x4(columns: (
            SIMD4(right.x, up.x, -forward.x, 0),
            SIMD4(right.y, up.y, -forward.y, 0),
            SIMD4(right.z, up.z, -forward.z, 0),
            SIMD4(-simd_dot(right, eye), -simd_dot(up, eye), simd_dot(forward, eye), 1)))
    }

    private static func perspective(aspect: Float, zoom: Float = 1, verticalFov: Float = 60, near: Float = 0.15, far: Float = 3000) -> simd_float4x4 {
        let scale: Float = zoom / tan(verticalFov * .pi / 360)
        return simd_float4x4(columns: (
            SIMD4(scale / aspect, 0, 0, 0),
            SIMD4(0, scale, 0, 0),
            SIMD4(0, 0, far / (near - far), -1),
            SIMD4(0, 0, far * near / (near - far), 0)))
    }
}
