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
    private let vehiclePipeline: MTLRenderPipelineState?
    private let vehicleMaskPipeline:MTLRenderPipelineState?
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
    private var vehicleRigs:[String:NativeVehicleRig] = [:]
    private var vehicleRigMeshes:[String:Mesh] = [:]
    private var vehicleWaterMasks:[String:[(Int,Mesh)]] = [:]
    private var vehicleRigStates:[String:NativeVehicleRig.State] = [:]
    private var vehicleRigTimes:[String:Double] = [:]
    private var vehicleRigSpins:[String:SIMD2<Double>] = [:]
    private var vehicleSeats: [String: SIMD3<Float>] = [:]
    private var pedestrianAnchors: [String: [String: [Float]]] = [:]
    private var seating: NativeVehicleSeating?
    private lazy var character = groundVehicle.flatMap { NativeCharacterController(world: $0.world) }
    private lazy var supportScene=groundVehicle.map{NativeVehicleSupportScene(world:$0.world)}
    private lazy var movingSupport=supportScene.map{NativeMovingSupport(scene:$0)}
    private var characterActive = false
    private var pendingNativeJump: Double = 0
    private let swimController = NativeSwimController()
    private let personalFlight=NativePersonalFlightController()
    private(set) var hasParachute=false
    var personalFlightDown=false
    var personalFlightBrake=false
    private var pendingParachuteOpen=false
    var wearingJetpack:Bool {personalFlight.worn}
    var canDropJetpack:Bool {
        personalFlight.worn && !personalFlight.on && !driving && climb==nil && health>0 &&
            (character?.state.grounded ?? (verticalSpeed==0))
    }
    var isChuting:Bool {personalFlight.chuting}
    var personalFlightPitch:Float {Float(personalFlight.pitch)}
    var personalFlightRoll:Float {Float(personalFlight.roll)}
    private var personalFlightAnimationInput:NativeFlightAnimation.Input? {
        personalFlight.state>0 ? .init(state:personalFlight.state,pitch:personalFlight.pitch,roll:personalFlight.roll):nil
    }
    func setFlightGear(parachute:Bool,jetpack:Bool) {
        if jetpack,climb != nil {pendingClimbDrop=true}
        hasParachute=parachute;if personalFlight.worn != jetpack {personalFlight.wear(jetpack)}
    }
    func openParachute() {if personalFlight.chuting {pendingParachuteOpen=true}}
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
    private var meleeDefinitions:NativeMeleeDefinitions?
    private let meleeInput=NativeMeleeInput()
    private var meleeClock:Double=0
    var meleeGuardHeld=false
    var meleeBlockHeld=false
    var onFootMeleeHit:((NativeMeleeEvent)->Bool)?
    var onMeleeSwing:((Int)->Void)?
    var onMeleeGroundTarget:((NativeMeleeProbe)->Bool)?
    private var footAnimator: NativeFootAnimation?
    private let footLocomotion = NativeFootLocomotion()
    private let headingContinuity = NativeHeadingContinuity()
    private var climb:NativeClimbController?
    private var climbPhase:NativeClimbController.Part?
    private var pendingClimbPull=false,pendingClimbDrop=false
    private var airGrabTicks=0
    var jumpHeld=false
    var walkHeld=false
    var isClimbing:Bool {climb != nil}
    private lazy var climbQueries=character.map {NativeRapierClimbQueries(world:$0.world,excluded:[$0.queries.walker,$0.queries.probe])}
    private var footAnimationFrame: NativeFootAnimation.Frame?
    private var footAnimationModel = ""
    private var footAirTime: Double = 0
    private var footAirFall: Double = 0
    private var footAirFell = false
    private var footJumped = false
    private var footJumpMinimum: Double = 0
    private var footAirVelocity = SIMD2<Double>.zero
    private let localHitReaction=NativeLocalHitReaction()
    private var footDeathKind:String?
    private var pendingFootHit:SIMD3<Double>?
    private var footSprintPace: Double = 0
    private var footLaunchRemaining: Double?
    private var footReloadWasActive = false
    private var footReloadRequested = false
    private var riderDefinitions: NativeRiderDefinitions?
    private var ownRiderAnimation: NativeRiderAnimation?
    private var ownRiderPlayback:NativeRiderPlayback?
    private var ownRiderCapture:NativeSkeletalActor.Pose?
    private var ownRiderPrevious:NativeSkeletalActor.Pose?
    private var ownRiderSide = -1
    private var ownRiderFeet:(position:SIMD3<Float>,heading:Float)?
    private var pendingVehicleExit:(()->Void)?
    private var riderDoorHolds:[String:[Int:Double]]=[:]
    private var remoteRiderPlayback:[String:(String,NativeRiderPlayback)]=[:]
    private var remoteRiderActions:[String:Int]=[:]
    private var remoteRiderCapture:[String:NativeSkeletalActor.Pose]=[:]
    private var remoteRiderPrevious:[String:NativeSkeletalActor.Pose]=[:]

    private var remoteRiderAnimations: [String: NativeRiderAnimation] = [:]
    private var remoteFootAnimations: [String:(String,NativeRemoteFootAnimation)] = [:]
    private var remoteBikeAnimations: [String:NativeRemoteBikeAnimation] = [:]
    private var remoteBikeSamples: [String:(NativeRemoteBikeAnimation.Sample,NativeRemoteBikeAnimation.Sample?)] = [:]
    private var remoteBikeFrames: [String:NativeRemoteBikeAnimation.Frame] = [:]
    private struct ActorPoseOverride {
        var pose: NativeSkeletalActor.Pose?
        var transform: simd_float4x4?
        var original: Bool
        var flight:NativeFlightAnimation.Frame?
        var identity:String?
    }
    private var lastRiderDraw: Double = 0
    struct FlightAudioVoice {var id:String;var sound:String;var position:SIMD3<Float>;var thrust:Float}
    private(set) var flightAudioVoices:[FlightAudioVoice]=[]
    private var flightCanopyMesh:Mesh?
    private var flightCanopyActor:NativeSkeletalActor?
    private var flightJetMesh:Mesh?
    private var flightJetAssets:NativeFlightAssets?
    private var flightAssetLoading=false
    private var flightCanopyPoses:[String:NativeSkeletalActor.Pose]=[:]
    private var flightCanopyLanded:[String:simd_float4x4]=[:]
    private var actorAttachments: [String: NativeActorAttachment] = [:]
    private var actorLoading: Set<String> = []
    private var objectiveMarker: Mesh?
    private var waterMesh: Mesh?
    private let weaponEffects = NativeWeaponEffects()
    private var particleEffects:NativeParticleEffects?
    private var particleRenderer:NativeParticleRenderer?
    private var particleLoading=false
    private var particleDrawDelta:Double=0
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
    private var appPreferences = NativeAppSettings.defaults
    private var ownCameraVisibility=NativeCameraVisibility()
    private var gameCameraFrame: NativeGameCamera.Frame?
    private var cameraVehicleDefinitions: [String:CameraVehicleDefinition] = [:]
    private var cameraWasDriving = false
    private var waterTexture: MTLTexture?
    private var nearWaterMesh: Mesh?
    private var nearWaterOrigin: SIMD2<Float>?
    private var renderClock=NativeGameFrameClock()
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
    private var weaponMuzzleCatalog:NativeWeaponMuzzle.Catalog?
    private var loading: Set<String> = []
    private var retryAfter: [String: Date] = [:]
    private var activeDetail = "c59"
    private var activeDetails: Set<String> = ["c59"]
    private var collisionRequests=NativeCollisionRequests()
    private var desiredPhysicsCells=Set<String>()
    private var collisionLoading=Set<String>()
    private var collisionRetryAfter:[String:Date]=[:]
    private var collisionScene:Bool?
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
    var vehicleSiren=false
    private var verticalSpeed: Float = 0
    private var vehicleHandling: [String: VehicleHandling] = [:]
    private var vehicleInfo: [String: [String: String]] = [:]
    private var activeVehicleModel = ""
    private var activeHandling: VehicleHandling?
    private var activeModelOrigin: Float = 0
    private var pendingVehicleBodyPose:NativeUnattendedVehicle.Pose?
    private var vehicleFallbackRoll: Float = 0
    private let groundVehicle = NativeGroundVehicle()
    private var couplingConnection:String?
    private struct CouplingSnapshot {let links:[NativeCouplingLink],revision:Int,connection:String}
    private var couplingSnapshot:CouplingSnapshot?
    private lazy var vehicleCoupling:NativeVehicleCoupling? = {
        guard let ground=groundVehicle else{return nil}
        let coupling=NativeVehicleCoupling(ground:ground)
        coupling.onRequest = {[weak self] request in self?.onCouplingRequest?(request) ?? false}
        return coupling
    }()
    var onCouplingRequest:((NativeVehicleCoupling.Request)->Bool)?
    var vehicleWorkingControl:Float=0
    var hasVehicleWorkingControls:Bool {
        guard driving,groundVehicle?.hasWorkingControls==true,let name=vehicleModels[activeVehicleModel],
              let working=vehicleRigs[name]?.document.joints.working else{return false}
        return !working.parts.isEmpty
    }
    var vehicleWorkingIsTow:Bool {groundVehicle?.workingFrame?.localTowAnchor != nil}
    var vehicleWorkingValue:Int? {driving ? groundVehicle?.workingValue:nil}
    var canUnhitchVehicle:Bool {driving && vehicleCoupling?.towing != nil}
    func setVehicleCouplingConnection(_ value:String?) {
        guard value != couplingConnection else{return}
        couplingConnection=value;couplingSnapshot=nil
        vehicleCoupling?.reset(connection:value);groundVehicle?.workingTowed=false
    }
    func applyVehicleCouplings(_ links:[NativeCouplingLink],revision:Int,connection:String) {
        guard connection==couplingConnection,links.allSatisfy({NativeVehicleCoupling.Kind(rawValue:$0.kind) != nil}) else{return}
        couplingSnapshot = .init(links:links,revision:revision,connection:connection)
        let rows=links.map{NativeVehicleCoupling.Link(parent:$0.parent,trailer:$0.trailer,kind:NativeVehicleCoupling.Kind(rawValue:$0.kind)!)}
        _ = vehicleCoupling?.applyTopology(rows,revision:revision,connection:connection,nowMilliseconds:ProcessInfo.processInfo.systemUptime*1000)
        groundVehicle?.workingTowed=vehicleCoupling?.towedCar != nil
    }
    func rejectVehicleCoupling(_ request:NativeVehicleCoupling.Request) {vehicleCoupling?.rejectRequest(request)}
    func releaseVehicleCoupling(secondOnly:Bool=false) {vehicleCoupling?.requestRelease(nowMilliseconds:ProcessInfo.processInfo.systemUptime*1000,secondOnly:secondOnly)}
    func vehicleCouplingMovePacket(_ id:String)->[String:Any]? {groundVehicle?.otherVehicleMovePacket(id)}
    private func updateVehicleCoupling() {
        guard let ground=groundVehicle else{return}
        vehicleCoupling?.setOwnedVehicle(driving && health>0 && ground.active ? currentVehicleID:nil)
        if ground.consumeWorkingDrop() {releaseVehicleCoupling()}
        let frame=ground.workingFrame
        vehicleCoupling?.update(nowMilliseconds:ProcessInfo.processInfo.systemUptime*1000,
            towAnchor:hasVehicleWorkingControls ? frame?.localTowAnchor:nil,
            canAcquireTow:hasVehicleWorkingControls && (frame?.canAcquireTow ?? false))
        ground.workingTowed=vehicleCoupling?.towedCar != nil
    }
    var vehicleHandbrake = false
    var vehicleHop = false
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
    var nativeBicycleHop: Float { groundVehicle?.bicycleHop ?? 0 }
    var nativeBikeFullLean: Float { groundVehicle?.bikeFullLean ?? 0 }
    var nativeRotorTurning: Float { groundVehicle?.rotorTurning ?? 0 }
    var nativeVehicleAudioSnapshot:NativeGroundVehicle.AudioSnapshot? {groundVehicle?.audioSnapshot()}
    func takeVehicleHullAudio()->NativeGroundVehicle.HullAudio? {groundVehicle?.takeHullAudio()}
    var audioEar:SIMD3<Float> {gameCameraFrame?.source ?? camera}
    var audioForward:SIMD3<Float> {gameCameraFrame.map{simd_normalize($0.target-$0.source)} ?? aimDirection}
    func remoteVehicleAudioTop(_ model:String)->Double? {groundVehicle?.remoteAudioTop(model:model)}
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
    private var vehicleLeanInput: Float = 0
    private var ownClip = "idle_stance"
    private var ownClipTime: Double = 0
    private var locomotionClip = "idle_stance"
    private var locomotionTime: Double = 0
    private var manualAnimation = false
    private var manualAnimationSerial = 0
    private var pedestrian = NativePedestrianMotion()
    var health = 100 {
        didSet {
            if health<=0 {personalFlight.stop();personalFlight.wear(false);hasParachute=false}
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
    var onVehicleMove: ((String,[String:Any]) -> Void)?
    var onContactAudio: (([NativeVehicleDamageController.Collision],NativeVehicleDamage.Body) -> Void)?
    var onLocalHealth: ((Int) -> Void)?
    var onParachuteUsed: (() -> Void)?
    private var actionTimeRemaining: Float = 0
    private var actionClip = ""
    var equippedWeapon = 0
    /// Native utility-gear policy auto-selects the granted bag during a fall.
    /// The visual model and wire must agree. The full browser utility slot and
    /// mid-chute selection are still separate from the server's ammo inventory.
    var effectiveWireWeapon:Int {
        let carried=personalFlight.chuting ? 46:equippedWeapon
        return NativeWeaponAttachment.selectedWeapon(carried,swimming:swimming,
            jetpackFlying:personalFlight.flying,armWeapon:footWeaponDefinitions[carried]?.arm == true)
    }
    var weaponTriggerHeld = false
    var weaponReloading = false
    var weaponReady = true
    var onFootstep: ((String) -> Void)?
    /// Fixed-step animation events own firing time; the inventory/network
    /// consumer can synchronously update weaponReady before the next substep.
    var onFootWeaponShot: ((Int,Bool) -> Bool)?
    private var acceptedStreamShot=false
    private var acceptedStreamRay:(weapon:Int,origin:SIMD3<Float>,direction:SIMD3<Float>)?
    var aiming = false
    var driving = false
    var remoteServerTimeOffsetMilliseconds: Double?
    var remotePlayers: [RemotePlayer] = [] { didSet { recordRemoteAnimationPackets() } }
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
        descriptor.colorAttachments[0].writeMask = []
        let vehicleMaskPipeline=try? device.makeRenderPipelineState(descriptor:descriptor)
        descriptor.colorAttachments[0].writeMask = .all
        descriptor.fragmentFunction = library.makeFunction(name:"vehicleFragment")
        let vehiclePipeline = descriptor.fragmentFunction.flatMap {_ in try? device.makeRenderPipelineState(descriptor:descriptor)}
        descriptor.fragmentFunction = fragment
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
        self.vehiclePipeline = vehiclePipeline
        self.vehicleMaskPipeline = vehicleMaskPipeline
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
        configureMovingSupport()
        groundVehicle?.onOtherMove = {[weak self] id,state in self?.onVehicleMove?(id,state)}
        groundVehicle?.onCouplingStep = {[weak self] _ in self?.updateVehicleCoupling()}
        groundVehicle?.onOtherCollidersChanged = {[weak self] in
            guard let self else{return}
            self.character?.otherColliders=self.groundVehicle?.otherColliders ?? []
        }
        character?.onPress = {[weak self] presses in
            for press in presses {
                self?.groundVehicle?.shoveOtherVehicle(body:press.body,direction:press.direction,point:press.point,speed:press.speed)
            }
        }

        groundVehicle?.onCollisions = { [weak self] collisions,body in self?.onContactAudio?(collisions,body) }
        groundVehicle?.onDamageEvents = { [weak self] events,body in
            guard let self else { return }
            for event in events {
                if event.type == "blow" {
                    let point = SwiftRapierWorld.rapierToGTA(SIMD3<Float>(body.position))
                    self.showBlast(weapon:16,position:point,large:true)
                    self.onVehicleExplosion?(point)
                }
            }
        }
        groundVehicle?.waterLevel = { [weak self] point in
            let gta = SIMD3<Float>(Float(point.x),Float(-point.z),Float(point.y))
            guard let height=self?.worldWater?.height(x:gta.x,y:gta.y,z:gta.z) else { return nil }
            return Double(height)
        }
        groundVehicle?.staminaLeft = { [weak self] in self?.stamina.left ?? 0 }
        groundVehicle?.takeStamina = { [weak self] amount in
            guard let self else{return false};return self.stamina.take(amount)
        }
        groundVehicle?.restStamina = { [weak self] amount in self?.stamina.rest(amount) }
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
            var excluded = self.driving ? self.groundVehicle?.chassisColliders ?? [] : Set<UInt64>()
            if let queries=self.character?.queries {excluded.formUnion([queries.walker,queries.probe])}
            switch self.worldRay(from:origin,direction:direction,distance:distance,groups:groups,excluding:excluded) {
            case .hit(let hit):return hit.distance
            case .unavailable(let at):return at
            case .clear:return nil
            }
        }
        gameCamera.unavailableDistance = { [weak self] origin,direction,distance in
            guard let self,let vehicle=self.groundVehicle else {return 0}
            return NativeWorldRay.coverage(from:origin,to:origin+direction*distance,interior:self.camera.z>700,
                loaded:vehicle.isCellLoaded)?.firstUnavailable
        }
        weaponEffects.trace = { [weak self] origin, direction, distance in
            guard let self else{return nil}
            if case .hit(let hit)=self.worldRay(from:origin,direction:direction,distance:distance,groups:0xffff0083) {
                return NativeWeaponEffects.Contact(distance:hit.distance,normal:hit.normal)
            }
            return nil
        }
        weaponEffects.geometryAvailable = { [weak self] origin,direction,distance in
            guard let self else{return false}
            if case .unavailable=self.worldRay(from:origin,direction:direction,distance:distance,groups:0xffff0083) {return false}
            return true
        }
        weaponEffects.onGas={[weak self] point,delta in self?.particleEffects?.burst("teargas",at:SIMD3<Double>(point),delta:Double(delta))}
        weaponEffects.onFlames={[weak self] point,delta in self?.particleEffects?.burst("fire",at:SIMD3<Double>(point),delta:Double(delta))}
        weaponEffects.onTrail={[weak self] point,delta,flaming in
            guard let effects=self?.particleEffects else{return}
            if flaming{effects.burst("molotov_flame",at:SIMD3<Double>(point),delta:Double(delta))}
            else {effects.spawn("prt_smokeii_3_expand",at:SIMD3<Double>(point),velocity:SIMD3(0,0,0.3),count:Int(floor(40*Double(delta)+Double.random(in:0..<1))),options:.init(jitter:0.4,mult:.init(size:0.35,life:0.5,alpha:0.6)))}
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
    func showBlast(weapon: Int, position: SIMD3<Float>,large:Bool=false) {
        let now = ProcessInfo.processInfo.systemUptime
        guard !blasts.contains(where: { $0.1 == weapon && now-$0.2 < 0.3 && simd_distance($0.0,position)<1.5 }) else { return }
        blasts.append((position,weapon,now))
        weaponEffects.receiveBlast(weapon:weapon,position:position)
        if weapon != 17 {particleEffects?.play(large ? "explosion_large":weapon==18 ? "explosion_molotov":"explosion_small",at:SIMD3<Double>(position))}
        if driving { gameCamera.shake(at: position,strength: 0.6,nowMilliseconds: now*1000) }
    }
    func streamWeapon(_ weapon: Int?, delta: Float) {
        if let weapon {
            guard let ray=acceptedStreamRay,ray.weapon==weapon else{weaponEffects.endStream();return}
            let source=ray.origin,way=ray.direction
            weaponEffects.stream(weapon:weapon,from:source,direction:way,delta:delta)
            let name=weapon==37 ? "flamethrower":weapon==41 ? "spraycan":weapon==42 ? "extinguisher":nil
            if let name {
                particleEffects?.burst(name,at:SIMD3<Double>(source),delta:Double(delta),options:.init(clock:1,turn:simd_quatd(from:SIMD3<Double>(0,1,0),to:SIMD3<Double>(way))))
            }
        } else { weaponEffects.endStream() }
    }

    var position: SIMD3<Float> { camera }
    private var weaponEventFeet:SIMD3<Float>?
    /// Animation markers can run inside several fixed steps before the display
    /// pose is published. A shot must use that event's current physics feet.
    var shotFeet:SIMD3<Float> {weaponEventFeet ?? camera}
    func weaponMuzzle(weapon:Int,left:Bool)->NativeWeaponMuzzle.Sample? {
        guard weapon==equippedWeapon,health>0,!driving else{return nil}
        var source:NativeWeaponMuzzle.Pose?
        if let name=pedModels["7"],let actor=skeletalActors[name],let library=skeletalLibrary,let frame=footAnimationFrame {
            let pose=actor.originalPose(blends:frame.blends,library:library,aim:frame.aim,hiddenBones:frame.hiddenBones,
                figurePitch:frame.figurePitch,figureRoll:frame.figureRoll,legBend:frame.legBend)
            source = .init(weapon:weapon,feet:shotFeet,actorToWorld:Self.translation(shotFeet)*Self.rotationZ(-actorHeading),
                rightHand:actor.transform(bone:24,in:pose),leftHand:actor.transform(bone:34,in:pose),visible:frame.handWeaponVisible)
        }
        return NativeWeaponMuzzle.sample(weapon:weapon,left:left,feet:shotFeet,
            definition:weaponMuzzleCatalog?.definition(weapon:weapon),pose:source)
    }
    var direction: Float { driving ? heading : actorHeading }
    var cameraDirection: Float { gameCameraFrame?.heading ?? heading }
    var hasNearbyFire: Bool { weaponEffects.fires.contains { simd_distance($0.position,camera)<40 } }
    private var groundAudioContact:(material:Int,surface:Int)? {
        if let hit=groundVehicle?.world.raycast(origin:SwiftRapierWorld.gtaToRapier(camera+SIMD3(0,0,0.5)),direction:SIMD3(0,-1,0),distance:1.5,
            excludingColliders:driving ? groundVehicle?.chassisColliders ?? []:[],groups:0xffff0081) {
            return (hit.coarseMaterial,hit.coarseSurface)
        }
        return collision?.ground(x:camera.x,y:camera.y,near:camera.z,maxDrop:1.5).map {($0.material,$0.surface)}
    }
    var groundMaterial: Int? {groundAudioContact?.material}
    var groundSurface: Int? {groundAudioContact?.surface}
    var isWading: Bool {worldWater?.height(x:camera.x,y:camera.y,z:camera.z).map {$0>camera.z} ?? false}
    var hasOriginalFootAnimation: Bool {footAnimator != nil && footAnimationFrame != nil && !driving}
    var footWireMovementRatio:Double {
        guard health>0,!personalFlight.on,climb==nil else{return 0}
        let ratio=footSprintPace>=1 && footLocomotion.requestedMovementRatio>0.5 ? 3:footLocomotion.reportedRatio
        return floor(ratio*100+0.5)/100
    }
    var footWireAction:Int {health>0 ? climb?.part.rawValue ?? (personalFlight.state>0 ? 50+personalFlight.state-1:footAnimator?.reportedAction ?? 0):0}
    var footWireAnimation:String? {health>0 && !swimController.on && footWireAction == 0 && footAnimator?.floored != true ? footAnimator?.tagged:nil}
    var footWireAirborne:Bool {climb==nil && !personalFlight.on && footAirTime>0.05}
    var footWireDown:Int {driving ? 0:footAnimator?.reportedDown ?? 0}
    var footWireAim:Double? {
        guard health>0,climb==nil,!personalFlight.chuting,footWeaponDefinitions[equippedWeapon]?.aims == true,
              aiming || weaponTriggerHeld || footAnimator?.gunUp == true else{return nil}
        return aiming ? Double(cameraPitch):0
    }
    private var currentFootVelocity:SIMD3<Double> {character?.currentVelocity ?? lastFootVelocity}
    var currentWireVelocity:SIMD3<Float> {
        driving ? groundVehicle?.nativeLinearVelocity ?? .zero:SwiftRapierWorld.rapierToGTA(SIMD3<Float>(currentFootVelocity))
    }
    var currentWireAngularVelocity:SIMD3<Float> {driving ? groundVehicle?.nativeAngularVelocity ?? .zero:.zero}
    var footWireSupport:(id:String,offset:SIMD3<Float>)? {
        guard !driving,health>0,!swimController.on,!personalFlight.on,climb==nil,
              let attachment=movingSupport?.attachment,let id=attachment.id else{return nil}
        return (id,SIMD3<Float>(attachment.at))
    }
    func vehicleWireKit(tuck:Double)->[Double]? {driving ? groundVehicle?.wireKit(tuck:tuck):nil}
    var isAirborne: Bool { verticalSpeed != 0 }
    var animationName: String { ownClip }
    var swimmingState: Int { swimController.on ? swimController.state.rawValue : 0 }
    var swimmingPitch: Float { Float(swimController.pitch) }
    var swimmingRatio: Float { Float(swimController.ratio) }
    var swimmingBreath: Int? { swimController.displayBreath }
    var aimDirection: SIMD3<Float> {
        if driving,let frame = gameCameraFrame { return simd_normalize(frame.target-frame.source) }
        return SIMD3(sin(heading)*cos(cameraPitch),cos(heading)*cos(cameraPitch),sin(cameraPitch))
    }
    var cameraLookDirection: String?
    func cancelCameraInput() { gameCamera.cancelLookInput();cameraLookDirection=nil }
    func cancelWeaponInput() {
        weaponTriggerHeld=false;acceptedStreamRay=nil;footAnimator?.cancelInput()
        meleeGuardHeld=false;meleeBlockHeld=false;meleeInput.cancel();footAnimator?.cancelMeleeInput()
    }
    func cancelReloadAnimation() {footAnimator?.cancelReload();footReloadRequested=false;footReloadWasActive=false}
    func receiveHit(_ hit:NativeIncomingHit) {
        guard hit.wasAlive,health>0 || hit.authoritativeHealth==0 else{return}
        prepareFootAnimation()
        let target=SIMD3<Double>(SwiftRapierWorld.gtaToRapier(camera))
        let source=hit.source.map{SIMD3<Double>(SwiftRapierWorld.gtaToRapier($0))}
        let actor=footAnimator != nil
        let side=actor ? source.map{NativeFootLocomotion.supportKnockSide(velocity:target-$0,heading:Double(actorHeading))} ?? 0:0
        var input=NativeLocalHitReaction.Input(weapon:hit.weapon,damage:hit.damage,healthAfter:hit.authoritativeHealth ?? health,
            now:ProcessInfo.processInfo.systemUptime*1000)
        input.side=side;input.piece=hit.piece;input.quiet=hit.quiet;input.wasAlive=hit.wasAlive
        input.still=footLocomotion.requestedMovementRatio==0 && footAirTime==0;input.crouched=crouching
        input.swimming=swimController.on;input.climbing=climb != nil
        input.source=source;input.target=target;input.hasActor=actor
        let response=localHitReaction.receive(input)
        if let kind=response.death {
            let correction=footDeathKind==nil && hit.authoritativeHealth==0
            footDeathKind=kind;pendingFootHit=response.impulse
            crouching=false;personalFlight.stop();cancelWeaponInput()
            footAnimator?.die(kind,correctExisting:correction)
            if response.loseHead {footAnimator?.loseHead()}
        } else if !driving,let kind=response.flinch {
            footAnimator?.flinch(kind,stun:response.stun)
            if response.stun,footAnimator?.stunned==true {cancelWeaponInput()}
        }
    }
    func cancelGameplayInput() {
        cancelWeaponInput();cancelCameraInput()
        acceptedStreamShot=false
        pendingNativeJump=0;pendingSwimJump=false;pendingDive=false;pendingSprintTap=false
        character?.cancelPendingInput()
        pendingClimbPull=false;pendingClimbDrop=false;jumpHeld=false;walkHeld=false
        pendingParachuteOpen=false;sprintWasHeld=false
        vehicleHop=false;groundVehicle?.cancelPendingInput()
        vehicleWorkingControl=0
        personalFlightDown=false;personalFlightBrake=false;personalFlight.cancelInput()
    }
    func recordWeaponShot(weapon:Int,origin:SIMD3<Float>,direction:SIMD3<Float>) {
        guard [37,41,42].contains(weapon),origin.x.isFinite,origin.y.isFinite,origin.z.isFinite,
              direction.x.isFinite,direction.y.isFinite,direction.z.isFinite else{return}
        acceptedStreamRay=(weapon,origin,direction)
    }
    func beginGameplayFrame() {
        acceptedStreamShot=false
        if health<=0 || driving || swimming || climb != nil || personalFlight.on {
            meleeInput.cancel();footAnimator?.cancelMeleeInput()
        }
        if acceptedStreamRay?.weapon != equippedWeapon || !weaponTriggerHeld || !weaponReady || weaponReloading ||
            health<=0 || driving || swimming || climb != nil {acceptedStreamRay=nil}
    }
    func resetDisplayClock() {renderClock.reset()}
    var hasNativeFootWeaponTiming:Bool {
        guard footAnimator != nil,let definition=footWeaponDefinitions[equippedWeapon],
              ["gun","stream","launch","throw"].contains(definition.use ?? ""),climb==nil,!driving,!swimming,!personalFlight.chuting else{return false}
        return !personalFlight.flying || definition.arm
    }
    private func combatEligibility(grounded:Bool?=nil)->NativeCombatEligibility.Context {
        let definition=footWeaponDefinitions[equippedWeapon]
        var context=NativeCombatEligibility.Context()
        context.alive=health>0
        context.blocked=driving || swimming || climb != nil || personalFlight.chuting
        context.airborne = !(grounded ?? character?.state.grounded ?? (verticalSpeed==0))
        context.busy=footAnimator?.busy ?? false;context.stunned=footAnimator?.stunned ?? false
        context.rolling=footAnimator?.rolling ?? false;context.flying=personalFlight.flying
        context.arm=definition?.arm ?? false;context.requiresAim=definition?.requiresAim ?? false
        context.aimHeld=aiming;context.ready=weaponReady;context.reloading=weaponReloading
        return context
    }
    var canRequestFootWeaponFire:Bool {combatEligibility().canRequestFire}
    var supportsFootWeaponAim:Bool {footWeaponDefinitions[equippedWeapon]?.aims == true}
    var canUseFootUtility:Bool {
        // The detonator's source action is an eligibility/stun check, not an
        // ammunition event. Inventory synchronization belongs to the caller.
        let context=combatEligibility()
        return context.canAim && !context.stunned
    }
    var canEmitFootCombatMarker:Bool {combatEligibility().canEmitShot}
    var canEmitFootWeaponShot:Bool {hasNativeFootWeaponTiming && canEmitFootCombatMarker}
    private var activeMeleeDefinition:NativeMeleeDefinitions.Definition? {
        guard let value=meleeDefinitions?[equippedWeapon],let profile=footWeaponDefinitions[equippedWeapon],let library=skeletalLibrary,
              value.compatible(profile,duration:{library.duration(of:$0)}) else{return nil}
        return value
    }
    var hasNativeFootMeleeTiming:Bool {
        footAnimator != nil && activeMeleeDefinition != nil && health>0 && !driving && !swimming && climb==nil && !personalFlight.on
    }
    var canNativeFootMeleeGuard:Bool {
        guard hasNativeFootMeleeTiming,activeMeleeDefinition?.blocks==true,
              let clip=footWeaponDefinitions[equippedWeapon]?.clip("guardIdle") else{return false}
        return skeletalLibrary?.contains(clip)==true
    }
    @discardableResult func requestFootMeleeAttack(alternate:Bool=false)->Bool {
        prepareFootAnimation()
        // The retail special-input tutorial does not establish a clip mapping.
        guard !alternate,hasNativeFootMeleeTiming,weaponReady,!weaponReloading else{return false}
        meleeInput.press(weapon:equippedWeapon);return true
    }
    private func meleeControls(delta:Double,grounded:Bool)->NativeMeleeInput.Frame {
        guard activeMeleeDefinition != nil,let animator=footAnimator else{meleeInput.cancel();return .init()}
        return meleeInput.update(delta:delta,weapon:equippedWeapon,held:weaponTriggerHeld,
            ready:weaponReady && !weaponReloading,canAct:grounded && health>0 && !animator.busy && !animator.stunned && !animator.rolling,
            guardHeld:meleeGuardHeld,blockHeld:meleeBlockHeld,canGuard:canNativeFootMeleeGuard,firing:animator.firing)
    }
    private func advanceMelee(_ frame:NativeMeleeInput.Frame,feet:SIMD3<Float>,ratio:Double,delta:Double) {
        meleeClock += delta
        guard frame.attack,let melee=activeMeleeDefinition,let animator=footAnimator else{return}
        var aside:String?
        if footLocomotion.requestedMovementRatio>1 && ratio>1 {aside="run"}
        else if let ground=melee.ground,footLocomotion.requestedMovementRatio<=1 {
            let probe=NativeMeleeProbe(weapon:equippedWeapon,feet:feet,heading:actorHeading,range:melee.range,radius:ground.radius)
            if onMeleeGroundTarget?(probe)==true {aside="ground"}
        }
        if animator.fire(held:true,aside:aside) {
            meleeInput.accepted();manualAnimation=false;onMeleeSwing?(equippedWeapon)
            // The source starts a strike before checking launch eligibility;
            // a newly accepted melee task owns this same-frame jump request.
            if footLaunchRemaining != nil {animator.cancelQueuedLaunch();footLaunchRemaining=nil}
        }
    }
    var nativeWeaponStreamActive:Bool {
        // An accepted last round still owns this frame's presentation after
        // atomic inventory delivery makes the next round unavailable.
        var context=combatEligibility();context.ready=weaponReady || acceptedStreamShot
        return hasNativeFootWeaponTiming && [37,38,41,42].contains(equippedWeapon) &&
            context.canEmitShot && (acceptedStreamShot ||
                (weaponReady && weaponTriggerHeld && footAnimator?.gunShooting == true && footAnimator?.fired == true))
    }
    @discardableResult func requestFootWeaponFire()->Bool {
        prepareFootAnimation()
        guard hasNativeFootWeaponTiming,canRequestFootWeaponFire,
              let animator=footAnimator else{return false}
        animator.arm(footWeaponDefinitions[equippedWeapon])
        return animator.fire(held:true)
    }
    func zoomCameraSight(_ delta: Float) { gameCamera.zoomSight(delta) }
    var scopedCameraHidesPlayer: Bool { gameCameraFrame?.hidesPlayer ?? false }
    var cameraViewName: String { driving ? gameCamera.vehicleViewName : ["near","middle","far"][gameCamera.footZoom-1] }
    var footCameraView: Int { gameCamera.footZoom }
    var vehicleCameraView: Int { gameCamera.vehicleView }
    func cycleCameraView() { if driving { gameCamera.cycleVehicleView() } else { gameCamera.cycleFootZoom() } }
    /// Presentation preferences only. Physics cell coverage, movement input,
    /// world time and server authority are deliberately outside this boundary.
    func applySettings(_ snapshot: NativeAppSettings.Snapshot, maximumFPS: Int) {
        appPreferences = snapshot.validated()
        gameCamera.setFootZoom(appPreferences.footView)
        gameCamera.setVehicleView(appPreferences.vehicleView)
        if weatherAuto != appPreferences.regionalWeather { weatherAuto = appPreferences.regionalWeather }
        view.preferredFramesPerSecond = appPreferences.effectiveFrameRate(maximum: maximumFPS)
        updateSettingsViewport()
    }
    func updateSettingsViewport() {
        // Always start at the unscaled point bounds. autoResizeDrawable would
        // otherwise overwrite a manually selected resolution on the next layout.
        view.autoResizeDrawable = false
        let scale = view.window?.screen.scale ?? view.contentScaleFactor
        if let size = appPreferences.drawableSize(bounds: view.bounds.size, displayScale: scale),
           view.drawableSize != size { view.drawableSize = size }
    }
    func lookCamera(x: Float,y: Float,delta: Float) {
        gameCamera.lookAnalog(x: x,y: -y,delta: delta,driving: driving,
                              sensitivity: Float(appPreferences.cameraSensitivity), inverted: appPreferences.invertY)
        if !driving { heading = gameCamera.heading;cameraPitch = gameCamera.pitch }
    }
    var vehicleNose: Float { driving ? vehiclePitch : 0 }
    func vehicleName(model: String) -> String? { vehicleInfo[model]?["name"] }
    func vehicleType(model: String) -> String? { vehicleInfo[model]?["type"] }
    var isFiring: Bool { actionTimeRemaining > 0 && actionClip == "colt45_fire" }

    func move(forward: Float, sideways: Float, turn: Float, delta: Float,
              running: Bool = false, lookVertical: Float = 0, lift: Float = 0) {
        vehicleLeanInput = driving ? lookVertical : 0
        synchronizeOtherVehiclePhysics(delta:Double(delta))
        if !driving && gameCamera.isLoaded {
            gameCamera.lookAnalog(x: turn,y: -lookVertical,delta: delta,
                                  sensitivity: Float(appPreferences.cameraSensitivity), inverted: appPreferences.invertY)
            heading = gameCamera.heading;cameraPitch = gameCamera.pitch
        } else if !driving || (vehicleKind != "plane" && vehicleKind != "helicopter") {
            cameraPitch = max(-0.4, min(0.5, cameraPitch + lookVertical * delta * 0.45))
        }
        actionTimeRemaining = max(0, actionTimeRemaining - delta)
        let inputLength = min(1, hypot(forward, sideways))
        // Surface swimming uses the same camera-relative movement intent as
        // walking even when the original skeletal animator is loaded.
        if inputLength>=0.05 {
            swimHeadingTarget=Float(NativeHeadingContinuity.inputFacing(camera:Double(heading),sideways:Double(sideways),forward:Double(forward)))
        }
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
            let controlsEnabled=vehicleHealth>0 && health>0 && (ownRiderPlayback?.inside ?? (ProcessInfo.processInfo.systemUptime-entryStarted>=1))
            let throttle = controlsEnabled ? forward:0
            let table = activeHandling
            let speedLimit = table?.roadTopSpeed ?? 32
            let acceleration = max(1.5, (table?.acceleration ?? 20) * 0.24)
            let braking = max(3, (table?.brakes ?? 7) * 1.2)
            let lock = max(10, min(50, table?.lock ?? 35)) * .pi / 180
            let grip = max(0.35, min(1.8, table?.traction ?? 0.8))
            if let groundVehicle, !groundVehicle.active, groundVehicle.supports(activeVehicleModel),
               groundVehicle.isCellLoaded(activeDetail) {
                let origin = groundVehicle.modelOrigin(activeVehicleModel) ?? 0
                if let pose=pendingVehicleBodyPose {
                    let transform=NativeGroundVehicle.transform(position:pose.position,rotation:pose.rotation,origin:Double(origin))
                    camera=SIMD3(transform.columns.3.x,transform.columns.3.y,transform.columns.3.z)
                }else{camera += NativeGroundVehicle.modelOffset(origin:origin-activeModelOrigin,heading:heading,pitch:vehiclePitch,roll:vehicleFallbackRoll)}
                activeModelOrigin = origin
                if groundVehicle.enter(model:activeVehicleModel,modelPosition:camera,heading:heading,pitch:vehiclePitch,roll:vehicleFallbackRoll,bodyPose:pendingVehicleBodyPose){
                    pendingVehicleBodyPose=nil
                    groundVehicle.setWorkingValue(remoteVehicles.first{$0.id==currentVehicleID}?.work ?? 0)
                }
                groundVehicle.damageController?.state.load(health:Double(vehicleHealth),text:activeVehicleDamage)
                if let name=vehicleModels[activeVehicleModel],let rig=vehicleRigs[name] {groundVehicle.setDamageHinges(rig.damageHinges)}
            }
            if let groundVehicle, groundVehicle.active {
                var input = NativeVehicleDynamics.Input()
                input.throttle = Double(throttle); input.steer = Double(steeringInput)
                input.lean = Double(lookVertical); input.handbrake = vehicleHandbrake
                input.pad = vehicleControllerInput; input.wetness = Double(roadWetness)
                input.hop = vehicleHop && vehicleKind == "bicycle"
                input.pitch = Double(lookVertical); input.roll = Double(turn)
                input.yaw = Double(sideways); input.nobody = health <= 0
                input.jets = Double(vehicleJetControl)
                if vehicleKind == "helicopter" { input.throttle = controlsEnabled ? Double(lift):0 }
                if vehicleKind=="helicopter" {input.drive = .init(throttle:0,steer:0,handbrake:true)}
                else if vehicleKind=="plane" {
                    input.drive = .init(throttle:groundVehicle.forwardSpeed>0.5 ? min(0,input.throttle):0,
                        steer:max(-1,min(1,input.yaw+(groundVehicle.aloft ? 0:input.steer))),handbrake:input.handbrake)
                }
                if !controlsEnabled {groundVehicle.cancelPendingInput()}
                vehicleCoupling?.setOwnedVehicle(health>0 ? currentVehicleID:nil)
                groundVehicle.workingTowed=vehicleCoupling?.towedCar != nil
                groundVehicle.workingControl=controlsEnabled && hasVehicleWorkingControls ? Double(vehicleWorkingControl):0
                let ownedInput=NativeVehicleInputOwnership.gated(input,enabled:controlsEnabled)
                groundVehicle.update(delta: Double(delta), input: ownedInput, currentCell: activeDetail)
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
                jump: pendingNativeJump,geometryReady: groundVehicle?.isCellLoaded(activeDetail) == true && meshes[activeDetail] != nil,
                motion: { [self] step,state,intended in
                    // Water/parachute handoffs inherit the preceding physical
                    // tick, including when this display frame contains none.
                    lastFootVelocity = character.stepVelocity
                    if let held=climbingMotion(delta:step,state:state,intended:intended) {return held}
                    let water = swimmingMotion(delta:step,state:state,intended:intended,push:Double(inputLength),running:running)
                    if swimController.on { return water }
                    if let flight=personalFlightMotion(delta:step,state:state,intended:water,forward:forward,sideways:sideways,running:running) {return flight}
                    return footMotion(delta:step,state:state,intended:water,forward:forward,sideways:sideways,running:running)
                })
            pendingNativeJump = 0; characterOutput = result; next = character.supportFeet ?? result.feet
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
        if !driving, let character {
            lastFootVelocity = character.stepVelocity
        } else if !driving && delta > 0 {
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
        weaponEffects.advance(delta: Double(delta),
            people: remotePlayers.map { NativeWeaponEffects.Target(id:$0.id,position:$0.position) },
            vehicles: remoteVehicles.map { NativeWeaponEffects.Target(id:$0.id,position:$0.position) })
    }

    private func synchronizeOtherVehiclePhysics(delta:Double) {
        guard let groundVehicle else {return}
        var poses:[String:NativeOtherVehicles.Pose] = [:]
        var order:[String] = []
        for vehicle in remoteVehicles {
            order.append(vehicle.id)
            poses[vehicle.id] = .init(id:vehicle.id,code:vehicle.code,position:vehicle.position,
                heading:vehicle.heading,pitch:vehicle.pitch,roll:vehicle.roll,health:vehicle.health,damage:vehicle.damage,work:vehicle.work)
        }
        for player in remotePlayers {
            guard let id=player.vehicleID else {continue}
            if poses[id] == nil{order.append(id)}
            poses[id] = .init(id:id,code:player.code,position:player.position,
                heading:player.heading,pitch:player.pitch,roll:player.roll,health:player.vehicleHealth,damage:player.vehicleDamage,occupied:true)
        }
        groundVehicle.synchronizeOtherVehicles(order.compactMap{poses[$0]},excluding:currentVehicleID,near:camera,
            promoteNear:driving && groundVehicle.active ? vehicleWirePosition:nil,delta:delta,wetness:Double(roadWetness))
        character?.otherColliders = groundVehicle.otherColliders
    }

    private func synchronizeMovingSupport() {
        guard let groundVehicle,let supportScene else{return}
        var drivers:[String:NativeVehicleSupportScene.Driver]=[:]
        for player in remotePlayers {
            guard let id=player.vehicleID else{continue}
            drivers[id] = .init(id:player.id,velocity:SIMD3<Double>(SwiftRapierWorld.gtaToRapier(player.velocity)),
                spin:SIMD3<Double>(SwiftRapierWorld.gtaToRapier(player.angularVelocity)))
        }
        supportScene.otherColliders=groundVehicle.otherColliders
        supportScene.synchronize(groundVehicle.supportFrames(),drivers:drivers)
    }
    private func configureMovingSupport() {
        guard let character else{return}
        func actor(_ motor:NativeCharacterMotor)->NativeMovingSupport.Actor {
            .init(grounded:motor.grounded,rising:motor.rising,
                fits:{motor.fits($0,excludingBody:$1)},stand:{motor.stand()})
        }
        character.resetSupport = {[weak self] in self?.movingSupport?.drop()}
        character.carrySupport = {[weak self] delta,motor,head in
            guard let self,let support=self.movingSupport,self.health>0,!self.driving,self.climb==nil,
                  !self.swimController.on,!self.personalFlight.on else {
                self?.movingSupport?.drop();return .init()
            }
            self.synchronizeMovingSupport()
            let value=support.carry(delta:delta,actor:actor(motor),head:&head)
            self.character?.supportAfloat=support.afloat
            return .init(displacement:value.move,body:support.through,yaw:value.yaw,thrown:value.thrown)
        }
        character.onSupportMotion = {[weak self] yaw,thrown in
            guard let self else{return}
            self.footLocomotion.turn(by:-yaw)
            self.actorHeading=Float(NativeHeadingContinuity.canonical(Double(self.actorHeading)-yaw))
            if let thrown,self.health>0,let animator=self.footAnimator,!animator.floored {
                let side=NativeFootLocomotion.supportKnockSide(velocity:thrown,heading:Double(self.actorHeading))
                self.footLocomotion.setKnockMomentum(thrown);self.crouching=false
                _ = animator.knock(["koSkidBack","koSpinR","koSkidFront","koSpinL"][side])
            }
        }
        character.settleSupport = {[weak self] _,motor,head,input in
            guard let self,let support=self.movingSupport,self.health>0,!self.driving,self.climb==nil,
                  !self.swimController.on,!self.personalFlight.on,input.heldFeet==nil else {
                self?.movingSupport?.drop();return
            }
            support.settle(actor:actor(motor),head:&head,jumping:input.jump>0 || (input.verticalOverride ?? 0)>0,
                moving:simd_length_squared(input.displacement)>0)
        }
        character.afterSupportUpdate = {[weak self] in
            guard let self else{return}
            self.synchronizeMovingSupport()
            self.character?.supportAfloat=self.movingSupport?.afloat ?? false
            self.character?.supportFeet=self.movingSupport?.drawnAt.map{SwiftRapierWorld.rapierToGTA(SIMD3<Float>($0))}
        }
    }

    func jump() {
        guard !driving, health > 0 else { return }
        if climb != nil {pendingClimbPull=true;return}
        if personalFlight.worn || personalFlight.chuting {return}
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
        if climb != nil {return}
        if personalFlight.worn || personalFlight.chuting {return}
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
        let depth = character?.supportAfloat == true ? nil:waterSurface(at:state.feet).map { Double($0.height-state.feet.z) }
        if !swimController.on && swimController.enters(depth) {
            let velocity=personalFlight.on ? personalFlight.linearVelocity:lastFootVelocity
            let rising=personalFlight.on ? velocity.y:state.rising
            if personalFlight.chuting && personalFlight.state>=5 {hasParachute=false;onParachuteUsed?()}
            personalFlight.stop()
            swimController.enter(velocity:velocity,rising:rising,depth:depth!)
            crouching = false;clearAction()
            footAirTime = 0;footAirFall = 0;footAirFell = false;footJumped = false;footLaunchRemaining = nil
        }
        guard swimController.on else { swimController.ashore(delta);return intended }
        headingContinuity.external(.swimming)
        let pace:Double
        if health>0 {
            if swimController.under {stamina.prepareUnderwater()}
            let profile = NativeSprintController.Profile.forMode(swimController.under ? .underwater : .water)
            pace = sprintController.control(profile,ticks:50*delta,tapped:pendingSprintTap,held:running,
                staminaLeft:stamina.left,take:{ [self] in stamina.take($0) })
        } else {pace=0}
        pendingSprintTap = false
        swimController.steer(push:push,sprint:pace >= 1 ? pace : 0,dive:pendingDive,pitch:Double(cameraPitch))
        pendingDive = false
        if swimController.turns && (push > 0 || swimController.under) {
            let target = swimController.under ? heading : swimHeadingTarget
            let difference = atan2(sin(target-actorHeading),cos(target-actorHeading))
            actorHeading += max(-Float(4*delta),min(Float(4*delta),difference))
        }
        // Recovery belongs to the input/steering phase. The following step
        // may switch breast/dive states or hand this tick back to the shore.
        if health>0 && (pace < 1 || swimController.under) {
            stamina.rest(50*delta*(swimController.state == .breast ? 0.25 : 0.5))
        }
        let feet = SIMD3<Double>(SwiftRapierWorld.gtaToRapier(state.feet))
        let jumping = pendingSwimJump;pendingSwimJump = false
        let result = swimController.step(delta:delta,depth:depth,grounded:state.grounded,heading:-Double(actorHeading),
            feet:feet,jump:jumping,ledge:{ [weak self] in self?.swimmingLedge(feet:feet,heading:-Double(self?.actorHeading ?? 0),surface:feet.y+(depth ?? 0)) },dead:health <= 0)
        if swimController.consumeSplash() { onSplash?() }
        guard let result else { return intended }
        // The outgoing swim task advances animation only when it owns this
        // tick. A nil result hands the same tick to foot/flight animation.
        if let animator = footAnimator {
            animator.arm(nil)
            if health <= 0 && !animator.dead { animator.die(footDeathKind ?? "drown") }
            else if health > 0 && animator.dead { animator.revive() }
            var animation = NativeFootAnimation.Input()
            animation.swimming = true
            animation.swim = .init(state:swimController.on ? swimController.state.rawValue : 0,rate:swimController.ratio,pace:swimController.pace,pitch:swimController.pitch)
            footAnimationFrame = animator.update(delta:delta,input:animation)
        }
        if delta>0 {footAirVelocity=SIMD2(result.move.x/delta,-result.move.z/delta)}
        var input = intended
        input.displacement = SwiftRapierWorld.rapierToGTA(SIMD3<Float>(result.move))
        input.verticalOverride = result.rise;input.jump = 0
        if let held = swimController.hauled { input.heldFeet = SwiftRapierWorld.rapierToGTA(SIMD3<Float>(held)) }
        return input
    }

    private func personalFlightMotion(delta:Double,state:NativeCharacterController.Output,intended:NativeCharacterController.Motion,
                                      forward:Float,sideways:Float,running:Bool)->NativeCharacterController.Motion? {
        guard health>0 else {personalFlight.stop();return nil}
        let origin=SwiftRapierWorld.gtaToRapier(state.feet+SIMD3(0,0,0.1))
        let height=character?.world.queryRay(origin:origin,direction:SIMD3(0,-1,0),distance:400,groups:0xffff0001).map{Double($0.distance)}
        personalFlight.steer(x:Double(sideways),y:Double(forward),open:pendingParachuteOpen,up:running,down:personalFlightDown,stop:personalFlightBrake)
        pendingParachuteOpen=false
        if !personalFlight.on,hasParachute,!state.grounded,personalFlight.dives(rising:state.rising,height:height) {
            personalFlight.dive(velocity:lastFootVelocity,rising:state.rising,heading:-Double(actorHeading))
            crouching=false;clearAction();footLaunchRemaining=nil
        }
        if personalFlight.lifts,footAnimator?.busy != true {personalFlight.takeOff(heading:-Double(actorHeading));crouching=false}
        guard personalFlight.on || personalFlight.state==10 else{return nil}
        let ownedFacing=personalFlight.on
        if ownedFacing {headingContinuity.external(personalFlight.chuting ? .parachute:.jetpack)}
        if personalFlight.chuting {stamina.restForLocomotion(ticks:50*delta,ratio:0)}
        let stepped=personalFlight.step(delta:delta,grounded:state.grounded,heading:-Double(heading),height:personalFlight.flying ? height:nil)
        // Touchdown can finish the flight task without returning displacement.
        // Publish its final facing before the foot task resumes in this tick.
        if ownedFacing {actorHeading = -Float(personalFlight.heading)}
        guard let result=stepped else{return nil}
        if delta>0 {footAirVelocity=SIMD2(result.move.x/delta,-result.move.z/delta)}
        var land:String?
        if let landing=result.landed {
            if landing.canopy {hasParachute=false;onParachuteUsed?()}
            if landing.dead {health=0;onLocalHealth?(0)}
            else {land=landing.canopy ? landing.speed>4 ? "fallFront":nil:"collapse"}
        }
        if let animator=footAnimator {
            var animation=NativeFootAnimation.Input()
            animation.land=land;animation.fly=personalFlightAnimationInput
            animation.position=SIMD3<Double>(state.feet);animation.heading=Double(actorHeading)
            let definition=footWeaponDefinitions[equippedWeapon]
            let canAim=personalFlight.flying && definition?.arm == true && definition?.use == "gun"
            animator.arm(canAim ? definition:nil)
            if canAim {
                let context=combatEligibility(grounded:state.grounded)
                animation.gun = .init(pitch:Double(cameraPitch),yaw:min(1.4,max(-1.4,NativeHeadingContinuity.difference(Double(actorHeading),from:Double(heading)))))
                animator.control(.init(fire:weaponTriggerHeld && context.canRequestFire,aim:aiming && context.canAim,
                    held:context.heldTrigger(weaponTriggerHeld),ready:weaponReady && !weaponReloading))
            }
            if health<=0 && !animator.dead {animator.die(footDeathKind ?? "koFront")}
            let frame=animator.update(delta:delta,input:animation)
            footAnimationFrame=frame;emitFootWeaponEvents(frame,feet:state.feet)
        }
        footAirTime=0;footAirFall=0;footAirFell=false;footJumped=false;footLaunchRemaining=nil
        var motion=intended;motion.jump=0
        motion.displacement=SwiftRapierWorld.rapierToGTA(SIMD3<Float>(result.move));motion.verticalOverride=result.rise
        return motion
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
        ownCameraVisibility.reset()
        headingContinuity.reset(facing:Double(actorHeading),locomotion:footLocomotion);footAnimationFrame = nil
        footAirTime = 0;footAirFall = 0;footAirFell = false;footJumped = false;footJumpMinimum = 0
        footLaunchRemaining = nil;footAirVelocity = .zero
    }

    /// Fixed alongside the actual public collision motor. Animation root
    /// distance and collision therefore consume exactly the same time slices.
    private func footMotion(delta: Double,state: NativeCharacterController.Output,
                            intended: NativeCharacterController.Motion,forward: Float,sideways: Float,running: Bool) -> NativeCharacterController.Motion {
        prepareFootAnimation()
        guard let animator = footAnimator else { pendingSprintTap = false;return intended }
        if health>0 {footDeathKind=nil;pendingFootHit=nil}
        headingContinuity.resumeFoot(facing:Double(actorHeading),locomotion:footLocomotion)
        let definition = footWeaponDefinitions[equippedWeapon]
        animator.arm(definition)
        if health <= 0 && !animator.dead { animator.die(footDeathKind ?? "koFront") }
        else if health > 0 && animator.dead { animator.revive() }
        if weaponReloading && !footReloadWasActive && !footReloadRequested { _ = animator.beginReload() }
        footReloadWasActive = weaponReloading;footReloadRequested = false
        let aimContext=combatEligibility(grounded:state.grounded)
        let effectiveAim = definition?.aims == true && (animator.gunUp ||
            (aiming && aimContext.canAim) || (weaponTriggerHeld && aimContext.canRequestFire))
        let meleeFrame=meleeControls(delta:delta,grounded:state.grounded)
        var control = NativeFootLocomotion.Input()
        control.stick = SIMD2(Double(sideways),Double(forward));control.cameraHeading = Double(heading)
        control.walking = walkHeld
        control.guardStance=meleeFrame.guarding
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
        advanceMelee(meleeFrame,feet:state.feet,ratio:locomotion.ratio,delta:delta)
        var motion = intended
        let impact=pendingFootHit;pendingFootHit=nil
        if let impact {
            footLaunchRemaining=nil;footJumped=false
            footAirVelocity=SIMD2(impact.x,-impact.z);motion.jump=0;motion.verticalOverride=impact.y
        }
        var jumping = false
        if let remaining = footLaunchRemaining {
            if remaining-delta < 0 {
                footLaunchRemaining = nil
                if state.grounded {
                    if beginClimb(state:state,extended:true) {
                        return climbingMotion(delta:delta,state:state,intended:motion,advance:false) ?? motion
                    }
                    motion.jump = 6.07;jumping = true
                }
            } else { footLaunchRemaining = remaining-delta;motion.jump = 0 }
        }
        let airborne = !state.grounded || jumping || impact != nil
        if airborne,footAirTime>0,footJumped,!footAirFell,state.rising > -10,simd_length(footAirVelocity)>2.5 {
            airGrabTicks += 1
            if airGrabTicks%2==0,beginClimb(state:state,extended:false) {
                return climbingMotion(delta:delta,state:state,intended:motion,advance:false) ?? motion
            }
        } else {airGrabTicks=0}
        let wholeBodyAim = animator.gunUp && !(definition?.arm ?? false) && !crouching
        if !airborne && health>0 {
            let restricted = wholeBodyAim || crouching || definition?.flags?["heavy"] == true || !animator.sprints
            footSprintPace = restricted ? 0 : sprintController.control(.forMode(.foot),ticks:50*delta,tapped:pendingSprintTap,held:running,
                staminaLeft:stamina.left,take:{ [self] in stamina.take($0) })
        } else if health<=0 {footSprintPace=0}
        if health>0 && footSprintPace < 1 {stamina.restForLocomotion(ticks:50*delta,ratio:locomotion.ratio)}
        pendingSprintTap = false
        var animation = NativeFootAnimation.Input()
        animation.fly=personalFlightAnimationInput;animation.position=SIMD3<Double>(state.feet);animation.heading=Double(actorHeading)
        animation.ratio = locomotion.ratio;animation.sprint = footSprintPace >= 1 && locomotion.pushing && !wholeBodyAim
        animation.pace = animation.sprint ? footSprintPace : 1
        animation.crouch = crouching;animation.strafe = locomotion.strafe
        animation.guarding=meleeFrame.guarding;animation.block=meleeFrame.blocking
        animation.gun = effectiveAim ? .init(pitch:aiming ? Double(cameraPitch) : 0,yaw:min(1.4,max(-1.4,NativeHeadingContinuity.difference(Double(actorHeading),from:Double(heading))))) : nil
        let fireContext=combatEligibility(grounded:!airborne)
        animator.control(.init(fire:weaponTriggerHeld && fireContext.canRequestFire,aim:aiming && fireContext.canAim,
            held:fireContext.heldTrigger(weaponTriggerHeld),pushed:locomotion.pushing,ready:weaponReady && !weaponReloading))
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
                // The prior task's requested horizontal speed matches the
                // archived landing input; committed speed is already stopped
                // by this tick's grounded collision and is not that input.
                let damage=NativeFallDamage.amount(fastest:footAirFall,horizontal:simd_length(footAirVelocity))
                let nextHealth=NativeFallDamage.health(after:damage,current:health)
                if nextHealth<health {
                    health=nextHealth;onLocalHealth?(health)
                    if health<=0 {animator.die()}
                }
            }
            footAirTime = 0;footAirFall = 0;footAirFell = false;footJumped = false;footJumpMinimum = 0
        }
        let frame = animator.update(delta:delta,input:animation);footAnimationFrame = frame
        emitFootWeaponEvents(frame,feet:state.feet)
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
        } else if delta > 0 {
            travel += footLocomotion.groundMomentum(delta:delta)
            footAirVelocity = SIMD2(Double(travel.x)/delta,Double(travel.y)/delta)
        }
        motion.displacement = travel
        if let prominent = frame.blends.last(where: { $0.weight > 0.5 && !$0.clip.isEmpty }) {
            ownClip = prominent.clip + "/l/1";ownClipTime = prominent.time
        }
        return motion
    }

    private func emitFootWeaponEvents(_ frame:NativeFootAnimation.Frame,feet:SIMD3<Float>) {
        let weapon=equippedWeapon
        if hasNativeFootMeleeTiming,let melee=activeMeleeDefinition,let animator=footAnimator {
            guard canEmitFootCombatMarker,
                  let blow=melee.blow(swing:animator.swing,aside:animator.aside) else{return}
            let attack=animator.aside=="ground" ? -1:animator.aside=="run" ? 0:animator.swing+1
            for _ in frame.shots {
                guard equippedWeapon==weapon,canEmitFootCombatMarker else{break}
                let event=NativeMeleeEvent(weapon:weapon,attack:attack,aside:animator.aside,feet:feet,heading:actorHeading,
                    range:melee.range,radius:blow.radius,simulationTime:meleeClock)
                _ = onFootMeleeHit?(event)
            }
            return
        }
        guard canEmitFootWeaponShot else{return}
        weaponEventFeet=feet
        defer {weaponEventFeet=nil}
        for left in frame.shots {
            guard equippedWeapon==weapon,combatEligibility().canEmitShot else{break}
            if onFootWeaponShot?(weapon,left) == true,[37,38,41,42].contains(weapon) {acceptedStreamShot=true}
        }
    }

    func letGoOfLedge() {if climb != nil {pendingClimbDrop=true}}

    private func beginClimb(state:NativeCharacterController.Output,extended:Bool)->Bool {
        guard health>0,climb==nil,!driving,!swimController.on,!personalFlight.on,!personalFlight.worn,
              let library=skeletalLibrary,let animator=footAnimator,let queries=climbQueries,
              let jump=library.duration(of:"ped/climb_jump"),let pull=library.duration(of:"ped/climb_pull"),
              let stand=library.duration(of:"ped/climb_stand"),let vault=library.duration(of:"ped/climb_jump_b"),
              min(jump,pull,stand,vault)>0 else{return false}
        let feet=SIMD3<Double>(SwiftRapierWorld.gtaToRapier(state.feet))
        guard var ledge=queries.find(feet:feet,heading:-Double(actorHeading),extended:extended) else{return false}
        if !extended {ledge.high=ledge.hold.y-feet.y-1>=1.1}
        climb=NativeClimbController(ledge:ledge,feet:feet,durations:.init(jump:jump,pull:pull,stand:stand,vault:vault))
        climbPhase=nil;pendingClimbPull=false;pendingClimbDrop=false;airGrabTicks=0
        cancelWeaponInput();crouching=false;manualAnimation=false;animator.resetMovementTask()
        footAirTime=0;footAirFall=0;footAirFell=false;footJumped=false;footLaunchRemaining=nil;footAirVelocity = .zero
        return true
    }

    /// The held root is published on both the first and completion tick. Root
    /// animation is visual here and must not be added to heldFeet a second time.
    private func climbingMotion(delta:Double,state:NativeCharacterController.Output,intended:NativeCharacterController.Motion,
                                advance:Bool=true)->NativeCharacterController.Motion? {
        guard let task=climb else{return nil}
        let end=advance ? task.step(delta:delta,pull:jumpHeld || pendingClimbPull,drop:pendingClimbDrop || health<=0):nil
        pendingClimbPull=false;pendingClimbDrop=false
        actorHeading = -Float(task.heading);headingContinuity.external(.climbing)
        if let animator=footAnimator {
            animator.arm(nil)
            if task.part != climbPhase {
                climbPhase=task.part
                switch task.part {
                case .jump:_=animator.act("ped/climb_jump",rooted:true,blend:8)
                case .hang:_=animator.act("ped/climb_idle",loop:true,rooted:true,blend:4)
                case .pull:_=animator.act("ped/climb_pull",rooted:true,cut:true)
                case .edge:_=animator.act("ped/climb_stand",rooted:true,paused:true,blend:4)
                case .stand:_=animator.act("ped/climb_stand",rooted:true,cut:true)
                case .vault:_=animator.act("ped/climb_jump_b",rooted:true,cut:true)
                }
            }
            if end != nil {
                if task.part == .stand {_=animator.act("ped/climb_stand_finish",cut:true,once:true)}
                else if task.part == .vault {_=animator.act("ped/climb_jump2fall",rooted:true,cut:true,once:true)}
                else {animator.rest()}
            }
            if health<=0,!animator.dead {animator.die()}
            var animation=NativeFootAnimation.Input()
            animation.position=SIMD3<Double>(state.feet);animation.heading=Double(actorHeading)
            footAnimationFrame=animator.update(delta:delta,input:animation)
        }
        var motion=intended;motion.displacement = .zero;motion.jump=0;motion.verticalOverride=nil
        motion.heldFeet=SwiftRapierWorld.rapierToGTA(SIMD3<Float>(task.feet))
        if let end {
            climb=nil;climbPhase=nil
            footAirTime=end == .over ? 0.35:0;footAirFall=0;footAirFell=false;footJumped=false;footJumpMinimum=0;footLaunchRemaining=nil
            footAirVelocity=end == .over ? SIMD2(-sin(task.heading),cos(task.heading)):.zero
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
        _ = requestFootMeleeAttack()
    }

    func firePistol() {
        fireWeapon(clip: "colt45_fire", duration: 0.73)
    }

    func fireWeapon(clip: String, duration: Float) {
        guard climb==nil else{return}
        manualAnimation = false
        // Native reloads retain the locomotion-owned facing; legacy fallback
        // fire still explicitly adopts its requested facing in both caches.
        if !clip.lowercased().contains("load") {
            actorHeading = heading
            headingContinuity.reset(facing:Double(actorHeading),locomotion:footLocomotion)
        }
        actionClip = clip
        actionTimeRemaining = duration
        pedestrian.perform(clip, duration: Double(duration))
        if let animator = footAnimator {
            animator.arm(footWeaponDefinitions[equippedWeapon])
            if clip.lowercased().contains("load") { _ = animator.beginReload();footReloadRequested = true }
            else { _ = animator.fire(held:false) }
        }
    }

    func clearAction() {
        guard climb==nil else{return}
        actionTimeRemaining = 0; pedestrian.clearAction();footAnimator?.rest();manualAnimation = false
    }
    var animationClips: [String] { skeletalLibrary?.clipNames ?? [] }
    func playAnimation(_ name: String, looping: Bool) {
        guard !driving,climb==nil, health > 0, let library = skeletalLibrary, library.contains(name) else { return }
        manualAnimation = true
        manualAnimationSerial = (manualAnimationSerial+1)%10
        let wire = name + (looping ? "/l/" : "/o/") + String(manualAnimationSerial)
        pedestrian.perform(wire, duration: looping ? 600 : (library.duration(of: name) ?? 1))
        _ = footAnimator?.act(name,loop:looping,once:!looping,tag:wire)
    }

    func hasClearShot(from start: SIMD3<Float>, to finish: SIMD3<Float>) -> Bool {
        guard let vehicle=groundVehicle else { return false }
        var excluded=driving ? vehicle.chassisColliders:Set<UInt64>()
        if let queries=character?.queries { excluded.formUnion([queries.walker,queries.probe]) }
        let offset=finish-start,distance=simd_length(offset)
        guard distance.isFinite,distance>0.0001 else{return false}
        switch worldRay(from:start,direction:offset/distance,distance:distance,groups:0xffff0083,excluding:excluded) {
        case .clear:return true
        case .hit(let hit):return hit.distance>=distance
        case .unavailable:return false
        }
    }

    private func worldRay(from origin:SIMD3<Float>,direction:SIMD3<Float>,distance:Float,
                          groups:UInt32,excluding:Set<UInt64>=[]) -> NativeWorldRay.Result {
        guard let vehicle=groundVehicle else{return .unavailable(0)}
        let magnitude=simd_length(direction)
        guard magnitude.isFinite,magnitude>0.0001,distance.isFinite,distance>0 else{return .unavailable(0)}
        let unit=direction/magnitude
        if let coverage=NativeWorldRay.coverage(from:origin,to:origin+unit*distance,interior:camera.z>700,loaded:{_ in true}) {
            collisionRequests.request(coverage.cells,now:ProcessInfo.processInfo.systemUptime,visible:activeDetails)
            desiredPhysicsCells=collisionRequests.retained(now:ProcessInfo.processInfo.systemUptime,visible:activeDetails)
            for name in desiredPhysicsCells {loadCollision(name:name)}
        }
        var excluded=excluding
        if let queries=character?.queries {excluded.formUnion([queries.walker,queries.probe])}
        return NativeWorldRay.query(from:origin,direction:unit,distance:distance,interior:camera.z>700,loaded:vehicle.isCellLoaded) { start,way,limit in
            vehicle.world.raycast(origin:SwiftRapierWorld.gtaToRapier(start),direction:SwiftRapierWorld.gtaToRapier(way),
                distance:limit,excludingColliders:excluded,groups:groups).map {
                    .init(distance:$0.distance,normal:SwiftRapierWorld.rapierToGTA($0.normal))
                }
        }
    }

    func predictedVehicle(_ vehicle:RemoteVehicle)->RemoteVehicle {
        applying(groundVehicle?.otherVehicle(vehicle.id),to:vehicle)
    }
    private func applying(_ snapshot:NativeOtherVehicles.Snapshot?,to original:RemoteVehicle)->RemoteVehicle {
        guard let snapshot else{return original}
        var vehicle=original
        vehicle.position=snapshot.position;vehicle.heading=snapshot.heading;vehicle.pitch=snapshot.pitch;vehicle.roll=snapshot.roll
        vehicle.health=snapshot.health;vehicle.damage=snapshot.damage;vehicle.work=snapshot.work
        return vehicle
    }
    private func parkedVehicle(name:String,position:SIMD3<Float>)->RemoteVehicle? {
        remoteVehicles.lazy.map{self.predictedVehicle($0)}.first{self.actorName(code:$0.code)==name && $0.position==position}
    }
    func enter(_ source: RemoteVehicle, kind: String) {
        let snapshot=groundVehicle?.takeOtherVehicle(source.id)
        pendingVehicleBodyPose=snapshot?.physicalPose
        let vehicle=applying(snapshot,to:source)
        ownCameraVisibility.reset()
        climb=nil;climbPhase=nil;pendingClimbPull=false;pendingClimbDrop=false;airGrabTicks=0
        personalFlight.stop()
        swimController.stop();swimming = false;underwater = false
        footAnimator?.rest(cut:true);footAnimationFrame = nil;footLaunchRemaining = nil
        ownRiderAnimation = nil;ownRiderPlayback=nil;ownRiderCapture=nil;ownRiderPrevious=nil;ownRiderFeet=nil;pendingVehicleExit=nil
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
        vehicleHorn = false;vehicleSiren=false;vehicleLights = false;vehicleJetControl = 0
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
        if let transform=snapshot?.transform {camera=SIMD3(transform.columns.3.x,transform.columns.3.y,transform.columns.3.z)}
        else{camera += NativeGroundVehicle.modelOffset(origin:activeModelOrigin,heading:heading,pitch:vehiclePitch,roll:vehicleFallbackRoll)}
        activeHandling = vehicleHandling[activeVehicleModel]
        vehicleKind = kind
        waterHeight = vehicle.position.z
        driving = true
        pedestrian.perform("car_getin_lhs", duration: 1.0)
        crouching = false
        currentVehicleID = vehicle.id
        loadNearby()
    }

    var riderWireAction:Int {
        guard driving,let playback=ownRiderPlayback else{return 0}
        if playback.state == .entering{return ownRiderSide<0 ? 1:3}
        if playback.state == .leaving{return ownRiderSide<0 ? 2:4}
        return 0
    }

    /// Keep ownership while the public get-out/door-close queue plays. Forced
    /// exits may still call exitVehicle directly (death/teleport/disconnect).
    @discardableResult func beginVehicleExit(onReady:@escaping()->Void)->Bool {
        guard driving,pendingVehicleExit==nil,let playback=ownRiderPlayback,playback.inside else{return pendingVehicleExit != nil}
        pendingVehicleExit=onReady;ownRiderFeet=nil
        let part=riderDefinitions?.models[activeVehicleModel]?.seats.first?.door
        let leaveOpen=part.map{groundVehicle?.damageController?.state.isOpen($0) ?? false} ?? false
        playback.leave(side:ownRiderSide,leaveOpen:leaveOpen)
        return true
    }

    func exitVehicle() {
        vehicleCoupling?.setOwnedVehicle(nil)
        ownCameraVisibility.reset()
        let exactFeet=ownRiderPlayback?.state == .stood ? ownRiderFeet:nil
        pendingVehicleExit=nil
        let floor = collision?.height(x: camera.x, y: camera.y,
                                      near: camera.z, maxDrop: 1000)
        let falling = floor.map { camera.z > $0 + 3 } ?? false
        if let id=currentVehicleID,groundVehicle?.active == true {
            let code=remoteVehicles.first{$0.id==id}?.code ?? "\(activeVehicleModel).6.1.0."
            let work=groundVehicle?.workingValue ?? remoteVehicles.first{$0.id==id}?.work ?? 0
            activeVehicleDamage=vehicleDamage
            groundVehicle?.parkCurrentVehicle(id:id,code:code,health:vehicleHealth,damage:activeVehicleDamage,work:work)
        } else{groundVehicle?.exit()}
        driving = false
        currentVehicleID = nil
        drivingSpeed = 0
        flightVerticalSpeed = 0
        vehiclePitch = 0
        vehicleFallbackRoll = 0
        activeModelOrigin = 0
        pendingVehicleBodyPose=nil
        climb=nil;climbPhase=nil;pendingClimbPull=false;pendingClimbDrop=false;airGrabTicks=0
        activeVehicleModel = ""
        activeHandling = nil
        vehicleKind = "car"
        if let exactFeet {
            camera=exactFeet.position;heading=exactFeet.heading;actorHeading=exactFeet.heading
            verticalSpeed=falling ? -1:0
        } else {
            camera.x += cos(heading) * 2.5
            camera.y -= sin(heading) * 2.5
            if falling { verticalSpeed = -1 }
            else { camera.z = collision?.height(x: camera.x, y: camera.y,near: camera.z - 1.1) ?? camera.z - 1.1 }
            actorHeading = heading
        }
        ownRiderPlayback=nil;ownRiderPrevious=nil;ownRiderCapture=nil;ownRiderFeet=nil
        pedestrian.perform("car_getout_lhs", duration: 1.0)
        headingContinuity.reset(facing:Double(actorHeading),locomotion:footLocomotion);footAnimationFrame = nil
        footAirTime = 0;footAirFall = 0;footAirFell=false;footJumped = false;footJumpMinimum=0;footLaunchRemaining=nil;footAirVelocity = .zero
        let resumed=gameCamera.resumeFoot(from:gameCameraFrame,fallbackHeading:heading,fallbackPitch:cameraPitch)
        heading=resumed.x;cameraPitch=resumed.y
        cameraWasDriving=false
    }

    /// Despawning/losing ownership must not manufacture a parked body or play
    /// a queued exit after the old vehicle has already ceased to exist.
    private func discardOwnedVehicle() {
        vehicleCoupling?.setOwnedVehicle(nil)
        groundVehicle?.exit()
        driving=false;currentVehicleID=nil;drivingSpeed=0;flightVerticalSpeed=0
        vehiclePitch=0;vehicleFallbackRoll=0;activeModelOrigin=0;pendingVehicleBodyPose=nil
        activeVehicleModel="";activeHandling=nil;vehicleKind="car"
        pendingVehicleExit=nil;ownRiderPlayback=nil;ownRiderPrevious=nil;ownRiderCapture=nil;ownRiderFeet=nil
        riderDoorHolds.removeAll()
    }

    @discardableResult func removeVehicle(id:String)->Bool {
        vehicleCoupling?.removeVehicle(id)
        groundVehicle?.removeOtherVehicle(id:id)
        remoteVehicles.removeAll{$0.id==id}
        guard currentVehicleID==id else{return false}
        discardOwnedVehicle()
        actorHeading=heading
        let resumed=gameCamera.resumeFoot(from:gameCameraFrame,fallbackHeading:heading,fallbackPitch:cameraPitch)
        heading=resumed.x;cameraPitch=resumed.y;cameraWasDriving=false
        teleport(x:camera.x,y:camera.y,z:camera.z)
        return true
    }

    private func clearMultiplayerPresentation() {
        vehicleRigStates.removeAll();vehicleRigTimes.removeAll();vehicleRigSpins.removeAll()
        remoteRiderPlayback.removeAll();remoteRiderActions.removeAll()
        remoteRiderCapture.removeAll();remoteRiderPrevious.removeAll();remoteRiderAnimations.removeAll()
        remoteFootAnimations.removeAll();remoteBikeAnimations.removeAll()
        remoteBikeSamples.removeAll();remoteBikeFrames.removeAll()
        flightCanopyPoses.removeAll();flightCanopyLanded.removeAll();flightAudioVoices.removeAll()
        lastRiderDraw=0;remoteServerTimeOffsetMilliseconds=nil
        weaponEffects.clear();particleEffects?.clear();blasts.removeAll();gameCamera.cancelShake()
    }

    /// A new server peer owns a new world baseline. Discard the previous
    /// owned vehicle without an exit animation, parking packet or side offset.
    /// The subsequent hello applies the self-hosted server's spawn policy.
    func resetMultiplayerSession() {
        localHitReaction.reset();footDeathKind=nil;pendingFootHit=nil
        setVehicleCouplingConnection(nil)
        discardOwnedVehicle()
        groundVehicle?.clearOtherVehicles()
        remotePlayers=[];remoteVehicles=[]
        synchronizeProjectiles([])
        clearMultiplayerPresentation()
        personalFlight.wear(false);hasParachute=false
        cancelReloadAnimation()
        teleport(x:camera.x,y:camera.y,z:camera.z)
    }

    func teleport(x: Float, y: Float, z: Float, direction: Float? = nil) {
        guard x.isFinite,y.isFinite,z.isFinite,direction?.isFinite != false else{return}
        pendingFootHit=nil
        ownCameraVisibility.reset()
        pendingVehicleBodyPose=nil
        climb=nil;climbPhase=nil;pendingClimbPull=false;pendingClimbDrop=false;airGrabTicks=0
        swimController.stop();swimming = false;underwater = false;lastFootVelocity = .zero
        personalFlight.stop();pendingParachuteOpen=false;pendingDive=false;pendingSwimJump=false
        cancelGameplayInput();clearAction();footAnimator?.resetMovementTask()
        characterActive = false; pendingNativeJump = 0
        camera = SIMD3(x, y, z)
        character?.reset(feet:camera,active:false)
        if let direction { heading = direction; actorHeading = direction }
        headingContinuity.reset(facing:Double(actorHeading),locomotion:footLocomotion)
        footAnimationFrame=nil;footAirTime=0;footAirFall=0;footAirFell=false;footJumped=false
        footJumpMinimum=0;footLaunchRemaining=nil;footAirVelocity = .zero;footSprintPace=0
        gameCamera.resetFoot(heading:heading,pitch:cameraPitch);gameCameraFrame=nil
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
        if collisionScene != indoors {collisionScene=indoors;collisionRequests.reset()}
        desiredPhysicsCells=collisionRequests.retained(now:ProcessInfo.processInfo.systemUptime,visible:detailNames)
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
        collisions = collisions.filter { desiredPhysicsCells.contains($0.key) }
        groundVehicle?.retainCells(desiredPhysicsCells)
        for name in far { load(name: name) }
        for name in detailNames { load(name: name) }
        for name in desiredPhysicsCells {loadCollision(name:name)}
    }

    private func loadCollision(name:String) {
        guard collisions[name]==nil,!collisionLoading.contains(name),
              Date()>=(collisionRetryAfter[name] ?? .distantPast),let server else{return}
        collisionLoading.insert(name)
        URLSession.shared.dataTask(with:server.path("game/world/\(name).col.bin")) { [weak self] data,response,_ in
            DispatchQueue.main.async {
                guard let self else{return};self.collisionLoading.remove(name)
                guard self.desiredPhysicsCells.contains(name) else{return}
                guard (response as? HTTPURLResponse)?.statusCode==200,let data,
                      let collision=try? WorldCollision(data:data) else {
                    self.collisionRetryAfter[name]=Date().addingTimeInterval(5);return
                }
                self.collisions[name]=collision;self.groundVehicle?.installCell(name,data:data)
            }
        }.resume()
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
                self.onStatus?("CITY READY: \(name.uppercased())")
            } catch {
                self.retryAfter[name] = Date().addingTimeInterval(5)
                self.onStatus?("CITY DATA ERROR: \(error.localizedDescription)")
            }
        }
    }

    var server: ServerAddress?

    func loadModelIndex() {
        loadFlightAssets();loadParticleEffects()
        guard let server else { return }
        URLSession.shared.dataTask(with:server.path("game/native/weapons.json")) { [weak self] data,response,_ in
            guard (response as? HTTPURLResponse)?.statusCode==200,let data,
                  let catalog=try? NativeWeaponMuzzle.Catalog(data:data) else{return}
            DispatchQueue.main.async {self?.weaponMuzzleCatalog=catalog}
        }.resume()
        URLSession.shared.dataTask(with:server.path("game/native/riders.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode == 200,
                  let definitions = try? JSONDecoder().decode(NativeRiderDefinitions.self,from:data) else { return }
            DispatchQueue.main.async { self?.riderDefinitions = definitions }
        }.resume()
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
        URLSession.shared.dataTask(with:server.path("game/native/melee.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode==200,
                  let definitions=try? NativeMeleeDefinitions(data:data) else{return}
            DispatchQueue.main.async {self?.meleeDefinitions=definitions}
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
            DispatchQueue.main.async {
                guard let self else{return}
                self.vehicleCoupling?.reset(connection:self.couplingConnection)
                self.groundVehicle?.loadDefinitions(data);self.cameraVehicleDefinitions = cameraDefinitions
                self.supportScene?.clear()
                if let snapshot=self.couplingSnapshot {self.applyVehicleCouplings(snapshot.links,revision:snapshot.revision,connection:snapshot.connection)}
                self.loadVehicleCouplingDefinitions()
                self.loadVehicleTreads()
            }
        }.resume()
        URLSession.shared.dataTask(with:server.path("game/native/trains.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode==200 else{return}
            DispatchQueue.main.async {self?.groundVehicle?.loadTracks(data)}
        }.resume()
    }

    private func loadVehicleCouplingDefinitions() {
        guard let server else{return}
        URLSession.shared.dataTask(with:server.path("game/native/vehicle-coupling.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode==200 else{return}
            DispatchQueue.main.async {
                guard let self else{return}
                self.groundVehicle?.loadCouplingDefinitions(data)
                self.supportScene?.invalidatePoses()
                if self.driving {self.groundVehicle?.setWorkingValue(self.remoteVehicles.first{$0.id==self.currentVehicleID}?.work ?? 0)}
            }
        }.resume()
    }

    private func loadVehicleTreads() {
        guard let server else{return}
        URLSession.shared.dataTask(with:server.path("game/native/vehicle-treads.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode==200 else{return}
            DispatchQueue.main.async { _ = self?.supportScene?.load(data) }
        }.resume()
    }

    private func remoteSupportPosition(_ player:RemotePlayer)->SIMD3<Float>? {
        guard player.vehicleID==nil,player.ridingVehicleID==nil,let id=player.supportVehicleID else{return nil}
        let transform:simd_float4x4?
        if driving,currentVehicleID==id,groundVehicle?.active==true {transform=groundVehicle?.modelTransform}
        else{transform=groundVehicle?.otherVehicle(id)?.transform}
        guard let transform else{return nil}
        let at=transform*SIMD4(player.supportOffset,1)
        return SIMD3(at.x,at.y,at.z)
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
        var rigBinary:Data?,rigImage:Data?,rigMetadata:Data?
        if vehicleModels.values.contains(name) {
            for suffix in ["bin","png","json"] {
                group.enter()
                // Rig hierarchy export can change draw traversal, indices and
                // texture layers together. Never combine a fresh hierarchy
                // with an older cached binary/atlas from the same URL.
                let request=URLRequest(url:server.path("game/native/models/\(name).rig.\(suffix)"),cachePolicy:.reloadIgnoringLocalCacheData)
                URLSession.shared.dataTask(with:request) { data,response,_ in
                    lock.lock()
                    if (response as? HTTPURLResponse)?.statusCode==200 {
                        if suffix=="bin" {rigBinary=data} else if suffix=="png" {rigImage=data} else {rigMetadata=data}
                    }
                    lock.unlock();group.leave()
                }.resume()
            }
        }
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
            if let rigBinary,let rigImage,let rigMetadata,let rig=NativeVehicleRig(data:rigMetadata),
               let geometry=try? WorldBinary(data:rigBinary),rig.document.draws.allSatisfy({$0.start+$0.count<=geometry.indices.count}),
               let atlas=try? self.textureLoader.newTexture(data:rigImage,options:[.SRGB:false]),
               let vertices=self.device.makeBuffer(bytes:geometry.vertices,length:geometry.vertices.count*MemoryLayout<NativeVertex>.stride),
               let indices=self.device.makeBuffer(bytes:geometry.indices,length:geometry.indices.count*4) {
                self.vehicleRigs[name]=rig
                self.vehicleRigMeshes[name]=Mesh(vertices:vertices,indices:indices,indexCount:geometry.indices.count,atlas:atlas)
                self.vehicleWaterMasks[name]=(rig.document.waterMasks ?? []).compactMap { mask -> (Int,Mesh)? in
                    let vertices=stride(from:0,to:mask.positions.count,by:3).map { index in
                        NativeVertex(position:SIMD4(mask.positions[index],mask.positions[index+1],mask.positions[index+2],1),uvLayer:.zero,tint:SIMD4(repeating:1),dusk:SIMD4(repeating:1))
                    }
                    guard !vertices.isEmpty,!mask.indices.isEmpty,
                          let vertexBuffer=self.device.makeBuffer(bytes:vertices,length:vertices.count*MemoryLayout<NativeVertex>.stride),
                          let indexBuffer=self.device.makeBuffer(bytes:mask.indices,length:mask.indices.count*4) else{return nil}
                    return (mask.node,Mesh(vertices:vertexBuffer,indices:indexBuffer,indexCount:mask.indices.count,atlas:atlas))
                }
                if self.activeVehicleModel==String(rig.document.id) {self.groundVehicle?.setDamageHinges(rig.damageHinges)}
            }
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
        let timing=renderClock.advance(timestamp:now,active:true)
        let delta=Float(timing.delta)
        if timing.discontinuity {
            cancelCameraInput()
            if driving {gameCamera.beginVehicle()}
            else {gameCamera.resetFoot(heading:heading,pitch:cameraPitch)}
        }
        atmosphereMilliseconds += Double(delta)*1000
        let hour = gameHour
        let manualBlend = Float(min(1,max(0,(now-weatherChanged)/4)))
        if returningToRegionalWeather && manualBlend >= 1 { returningToRegionalWeather = false }
        let aspect = max(0.1,Float(view.drawableSize.width/max(1,view.drawableSize.height)))
        if cameraWasDriving != driving {
            cameraWasDriving = driving
            if driving {gameCamera.beginVehicle()}
            else {
                let resumed=gameCamera.resumeFoot(from:gameCameraFrame,fallbackHeading:heading,fallbackPitch:cameraPitch)
                heading=resumed.x;cameraPitch=resumed.y
            }
        }
        // Advance camera lag in bounded slices, consuming queued analog look
        // only once. Render positions are current poses, not retroactive input.
        for step in timing.steps.isEmpty ? [0]:timing.steps {
            if driving,let input = nativeCameraVehicle() {
                gameCameraFrame = gameCamera.followVehicle(input,delta:Float(step),look:cameraLookDirection,nowMilliseconds:now*1000)
            } else if !driving {
                gameCamera.setDirection(heading:heading,pitch:cameraPitch)
                gameCameraFrame=gameCamera.followFoot(.init(position:camera,actorHeading:actorHeading,weapon:equippedWeapon,
                    aiming:aiming,crouching:crouching,holdingLedge:climb != nil || swimController.hauled != nil,parachuting:personalFlight.chuting,
                    sight:aiming ? gameCamera.sightForWeapon(equippedWeapon):nil,
                    planarSpeed:Float(hypot(currentFootVelocity.x,currentFootVelocity.z))),delta:Float(step),look:cameraLookDirection)
            } else {gameCameraFrame=nil}
        }
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
        ownCameraVisibility.update(eye:eye,feet:camera,nearPlane:planes.near,
            attachmentRadius:personalFlight.worn ? 0.2:0,presentationClearance:1)
        let projection=Self.perspective(aspect:aspect,verticalFov:gameCameraFrame?.verticalFov ?? 55.41293,near:planes.near,far:planes.far)
        let matrix=projection*viewMatrix
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
        particleDrawDelta=Double(delta)
        drawActors(encoder: encoder,matrix: matrix)
        if !indoors { drawWater(eye: eye,matrix: matrix,encoder: encoder) }
        if let atmosphereSnapshot { drawAtmosphereQuads(atmosphereSnapshot.quads.filter { !$0.paintedOnSky },matrix: matrix,encoder: encoder) }
        drawEffects(encoder:encoder,matrix:matrix,eye:eye,viewMatrix:viewMatrix,projection:projection,delta:Double(delta))
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

    private func recordRemoteAnimationPackets() {
        let now = ProcessInfo.processInfo.systemUptime
        let wallOffset = Date().timeIntervalSince1970-now
        let live = Set(remotePlayers.map(\.id))
        remoteBikeSamples = remoteBikeSamples.filter { live.contains($0.key) }
        for player in remotePlayers where player.vehicleID != nil {
            let serial = player.packetClockMilliseconds > 0 ? player.packetClockMilliseconds : player.packetReceivedAt
            if remoteBikeSamples[player.id]?.0.serial == serial { continue }
            let received = player.packetReceivedAt > 0 ? player.packetReceivedAt : now
            var at = received
            if player.packetClockMilliseconds > 0,let offset = remoteServerTimeOffsetMilliseconds {
                at = min(received,(player.packetClockMilliseconds-offset)/1000-wallOffset)
            }
            if let previous = remoteBikeSamples[player.id]?.0,at <= previous.time { continue }
            let sample = NativeRemoteBikeAnimation.Sample(serial:serial,time:at,speed:Double(player.speed),
                yawRate:Double(player.angularVelocity.z),health:Double(player.vehicleHealth),kit:player.kit?.map(Double.init))
            remoteBikeSamples[player.id] = (sample,remoteBikeSamples[player.id]?.0)
        }
    }

    private func drawActors(encoder: MTLRenderCommandEncoder, matrix: simd_float4x4) {
        let riderTime = ProcessInfo.processInfo.systemUptime
        let riderDelta = lastRiderDraw > 0 ? min(0.1,max(0,riderTime-lastRiderDraw)) : 0
        lastRiderDraw = riderTime
        let riderIDs = Set(remotePlayers.filter { $0.vehicleID != nil || $0.ridingVehicleID != nil }.map(\.id))
        remoteRiderAnimations = remoteRiderAnimations.filter { riderIDs.contains($0.key) }
        remoteRiderPlayback=remoteRiderPlayback.filter{riderIDs.contains($0.key)}
        remoteRiderActions=remoteRiderActions.filter{riderIDs.contains($0.key)}
        remoteRiderCapture=remoteRiderCapture.filter{riderIDs.contains($0.key)}
        remoteRiderPrevious=remoteRiderPrevious.filter{riderIDs.contains($0.key)}
        riderDoorHolds.removeAll(keepingCapacity:true)
        flightAudioVoices.removeAll(keepingCapacity:true)
        remoteBikeAnimations = remoteBikeAnimations.filter { riderIDs.contains($0.key) }
        let footIDs = Set(remotePlayers.filter { $0.vehicleID == nil && $0.ridingVehicleID == nil }.map(\.id))
        remoteFootAnimations = remoteFootAnimations.filter { footIDs.contains($0.key) }
        remoteBikeFrames.removeAll(keepingCapacity:true)
        let flightIDs=Set(remotePlayers.map(\.id)).union(["own"])
        flightCanopyPoses=flightCanopyPoses.filter{flightIDs.contains($0.key)}
        flightCanopyLanded=flightCanopyLanded.filter{flightIDs.contains($0.key)}
        var modelInstances: [(String, SIMD3<Float>, Float, Float, String, Double, Int)] = []
        var driverPose: NativeSkeletalActor.Pose?
        // An ordered queue preserves independent instances even when two players
        // have the same skin and exact position (including passengers).
        var actorOverrides: [String:[ActorPoseOverride]] = [:]
        var actorOverrideOffsets: [String:Int] = [:]
        func key(_ name: String,_ position: SIMD3<Float>) -> String { "\(name):\(position)" }
        func appendPed(_ name:String,_ at:SIMD3<Float>,_ heading:Float,_ pitch:Float,_ clip:String,_ elapsed:Double,_ weapon:Int,
                       pose:NativeSkeletalActor.Pose? = nil,transform:simd_float4x4? = nil,original:Bool = false,flight:NativeFlightAnimation.Frame? = nil,identity:String? = nil) {
            actorOverrides[key(name,at),default:[]].append(.init(pose:pose,transform:transform,original:original,flight:flight,identity:identity))
            modelInstances.append((name,at,heading,pitch,clip,elapsed,weapon))
        }
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
                    var originalDriver = false
                    if let definition = riderDefinitions?.models[activeVehicleModel],
                       let sourceSeat = definition.seats.first,let place = sourceSeat.position,
                       let actor = skeletalActors[ped],let library = skeletalLibrary {
                        if ownRiderAnimation == nil { ownRiderAnimation = NativeRiderAnimation(duration:{ [weak self] in self?.skeletalLibrary?.duration(of:$0) }) }
                        let input = NativeRiderAnimation.Input(speed:Double(drivingSpeed),
                            steer:-(groundVehicle?.output?.steering ?? Double(steeringInput)*0.61),
                            lean:Double(groundVehicle?.bikeLean ?? 0),tuck:Double(vehicleLeanInput),
                            pedal:groundVehicle?.bicyclePedal,crank:groundVehicle.map { Double($0.bicycleCrank) },
                            hop:Double(groundVehicle?.bicycleHop ?? 0),dead:health <= 0)
                        let car=nativeVehicleTransform ?? (Self.translation(camera)*Self.rotationZ(-heading)*Self.rotationX(vehiclePitch))
                        if ownRiderPlayback==nil,let playback=NativeRiderPlayback(definition:definition,library:library) {
                            let near=car.inverse*SIMD4(entryOrigin,1);ownRiderSide=near.x<0 ? -1:1
                            let door=sourceSeat.door.map{groundVehicle?.damageController?.state.isOpen($0) ?? false} ?? false
                            if time>3{playback.sit()}else{playback.enter(side:ownRiderSide,doorOpen:door ? 1:0)}
                            ownRiderPlayback=playback
                        }
                        if let frame=ownRiderPlayback?.update(delta:riderDelta,input:input) {
                            if let capture=frame.capture {
                                switch capture {
                                case .current:ownRiderCapture=ownRiderPrevious
                                case .sample(let value):ownRiderCapture=actor.riderPose(frame:value.pose,library:library,figurePosition:SIMD3<Float>(value.anchor))
                                }
                            }
                            driverPose=actor.riderPose(frame:frame.sample.pose,library:library,figurePosition:SIMD3<Float>(frame.sample.anchor),figureTurn:Float(frame.turn),previous:frame.transitioning ? ownRiderCapture:nil,transition:frame.transition)
                            ownRiderPrevious=driverPose
                            if let part=frame.doorPart{riderDoorHolds[currentVehicleID ?? "own",default:[:]][part]=frame.doorOpen}
                            if let release=frame.releasedDoor,let damage=groundVehicle?.damageController?.state,damage.doors.indices.contains(release.0){damage.letGo(release.0,angle:damage.doors[release.0].open*release.1)}
                            if let driverPose{ownRiderFeet=actor.riderFeet(pose:driverPose,model:car,origin:Float(definition.origin))}
                            if frame.state == .stood,let ready=pendingVehicleExit {
                                pendingVehicleExit=nil;DispatchQueue.main.async(execute:ready)
                            }
                            originalDriver=true
                        } else if let frame=ownRiderAnimation?.update(delta:riderDelta,configuration:definition.configuration(),input:input) {
                            driverPose=actor.riderPose(frame:frame,library:library,figurePosition:place,figureTurn:Float(sourceSeat.turn ?? 0));originalDriver=true
                        }
                    }
                    let alias = entering ? "entryEnd" : "car_sit"
                    let fallback = pedestrianAnchors[ped]?[alias]
                    if driverPose != nil || fallback?.count == 3 {
                        let pelvis = driverPose.map { SIMD3($0.pelvis.columns.3.x,$0.pelvis.columns.3.y,$0.pelvis.columns.3.z) } ??
                            SIMD3(fallback![0],fallback![1],fallback![2])
                        let car = nativeVehicleTransform ?? (Self.translation(camera) * Self.rotationZ(-heading) * Self.rotationX(vehiclePitch))
                        var transform = originalDriver ? car : car * Self.translation(seat) * Self.rotationZ(.pi) * Self.translation(-pelvis)
                        let sitting = SIMD3(transform.columns.3.x,transform.columns.3.y,transform.columns.3.z)
                        let amount = Float(min(1,max(0,time/max(0.001,duration))))
                        let at = entering && !originalDriver ? entryOrigin+(sitting-entryOrigin)*amount : sitting
                        transform.columns.3 = SIMD4(at,1)
                        var riderVisible=true
                        if originalDriver,let pose=driverPose,let actor=skeletalActors[ped],let head=actor.transform(bone:5,in:pose),let eye=gameCameraFrame?.source {
                            let world=transform*head.columns.3;riderVisible=simd_distance(SIMD3(world.x,world.y,world.z),eye)>0.45
                        }
                        if riderVisible{appendPed(ped,at,heading,0,clip,elapsed,0,pose:driverPose,transform:transform,original:originalDriver)}
                    }
                }
            }
        } else if !scopedCameraHidesPlayer,let name = pedModels["7"] {
            let original = footAnimationFrame != nil && skeletalActors[name] != nil
            let pose = skeletalActors[name].flatMap { actor in skeletalLibrary.flatMap { library in
                footAnimationFrame.flatMap { actor.originalPose(blends:$0.blends,library:library,aim:$0.aim,hiddenBones:$0.hiddenBones,figurePitch:$0.figurePitch,figureRoll:$0.figureRoll,legBend:$0.legBend) }
            } }
            let handWeapon = climb != nil || footAnimationFrame?.handWeaponVisible == false ? 0:effectiveWireWeapon
            appendPed(name,camera,actorHeading,swimmingPitch,ownClip,ownClipTime,handWeapon,pose:pose,original:original,flight:footAnimationFrame?.flight,identity:"own")
        }
        for player in remotePlayers where simd_distance(player.position, camera) < 130 {
            // A passenger's public carText is still a pedestrian; draw its
            // source seat inside the referenced car instead of a second walker.
            if let vehicleID = player.ridingVehicleID {
                let driver = remotePlayers.first { $0.vehicleID == vehicleID }
                let parked = remoteVehicles.first { $0.id == vehicleID }.map{predictedVehicle($0)}
                let own = driving && currentVehicleID == vehicleID
                let code = own ? (parked?.code ?? "\(activeVehicleModel).6.1.0.") : driver?.code ?? parked?.code
                guard let code,let name=actorName(code:code),let ped=pedModels[String(player.skin)] else {continue}
                guard let actor=skeletalActors[ped],let library=skeletalLibrary else {loadActor(ped);continue}
                let model=String(code.split(separator:".").first ?? "")
                guard let definition=riderDefinitions?.models[model],definition.seats.indices.contains(player.ridingSeat),
                      let seat=definition.seats[player.ridingSeat].position else {continue}
                let animator=remoteRiderAnimations[player.id] ?? NativeRiderAnimation(duration:{ [weak self] in self?.skeletalLibrary?.duration(of:$0) })
                remoteRiderAnimations[player.id]=animator
                let frame=animator.update(delta:riderDelta,configuration:definition.configuration(seat:player.ridingSeat),input:.init(dead:player.life<=0))
                let pose=actor.riderPose(frame:frame,library:library,figurePosition:seat,figureTurn:Float(definition.seats[player.ridingSeat].turn ?? 0))
                let position=own ? camera:driver?.position ?? parked?.position ?? player.position
                let angle=own ? heading:driver?.heading ?? parked?.heading ?? 0
                let pitch=own ? vehiclePitch:driver?.pitch ?? parked?.pitch ?? 0
                let roll=own ? vehicleRoll:driver?.roll ?? parked?.roll ?? 0
                let transform=own && nativeVehicleTransform != nil ? nativeVehicleTransform! :
                    Self.translation(position)*Self.rotationZ(-angle)*Self.rotationX(pitch)*Self.rotationY(roll)*Self.translation(SIMD3(0,0,vehicleModelOrigin(code)))
                _ = name
                appendPed(ped,position,angle,0,"",0,0,pose:pose,transform:transform,original:true)
                continue
            }
            guard let name=actorName(code:player.code) else {continue}
            if player.vehicleID == nil {
                let footPosition=remoteSupportPosition(player) ?? player.position
                var pose:NativeSkeletalActor.Pose?
                var original=false
                var flight:NativeFlightAnimation.Frame?
                var handWeapon=player.weapon
                if let actor=skeletalActors[name],let library=skeletalLibrary,let definitions=footDefinitions {
                    let animator:NativeRemoteFootAnimation
                    if let cached=remoteFootAnimations[player.id],cached.0==name {animator=cached.1}
                    else {
                        animator=NativeRemoteFootAnimation(library:library,style:definitions.style(model:name,library:library),weapons:footWeaponDefinitions)
                        remoteFootAnimations[player.id]=(name,animator)
                    }
                    let groundContext=NativeRemoteMeleeContext.nearFlooredTarget(attackerID:player.id,
                        position:SIMD3<Double>(player.position),heading:Double(player.heading),
                        own:.init(id:"own",position:SIMD3<Double>(camera),walking:!driving,
                            down:footAnimator?.floored == true,life:Double(health)),
                        people:remotePlayers.map{.init(id:$0.id,position:SIMD3<Double>($0.position),
                            walking:$0.vehicleID == nil && $0.ridingVehicleID == nil && $0.code.hasPrefix("s"),
                            down:$0.down != 0,life:Double($0.life))})
                    let state=NativeRemoteFootAnimation.Snapshot(position:SIMD3<Double>(footPosition),heading:Double(player.heading),
                        velocity:SIMD3<Double>(player.velocity),movement:Double(player.movementRatio),airborne:player.airborne,crouching:player.crouching,
                        weapon:player.weapon,aim:player.aim.map(Double.init),action:player.action,shots:player.shotCount,life:Double(player.life),
                        armour:Double(player.armour),down:player.down,paused:player.paused,pitch:Double(player.pitch),roll:Double(player.roll),script:player.scriptAnimation,
                        nearFlooredTarget:groundContext)
                    let frame=animator.update(delta:riderDelta,nowMilliseconds:riderTime*1000,snapshot:state)
                    if !frame.handWeaponVisible { handWeapon=0 }
                    flight=frame.flight
                    if !animator.hasUnsupportedFlight {
                        pose=actor.originalPose(blends:frame.blends,library:library,aim:frame.aim,hiddenBones:frame.hiddenBones,figurePitch:frame.figurePitch,figureRoll:frame.figureRoll,legBend:frame.legBend)
                        original=true
                    }
                }
                if (10...16).contains(player.action & 63) || (20...25).contains(player.action & 63) { handWeapon=0 }
                appendPed(name,footPosition,player.heading,player.pitch,player.animation,riderTime-player.animationStarted,handWeapon,pose:pose,original:original,flight:flight,identity:player.id)
                continue
            }
            modelInstances.append((name,player.position,player.heading,player.pitch,"",0,0))
            guard let ped=pedModels[String(player.skin)] else {continue}
            guard let actor=skeletalActors[ped],let library=skeletalLibrary else {loadActor(ped);continue}
            let model=String(player.code.split(separator:".").first ?? "")
            guard let source=riderDefinitions?.models[model],let sourceSeat=source.seats.first,let place=sourceSeat.position else {continue}
            let animator=remoteRiderAnimations[player.id] ?? NativeRiderAnimation(duration:{ [weak self] in self?.skeletalLibrary?.duration(of:$0) })
            remoteRiderAnimations[player.id]=animator
            var input=NativeRiderAnimation.Input(speed:Double(player.speed),steer:Double(player.steer),dead:player.life<=0)
            if source.astride,let samples=remoteBikeSamples[player.id] {
                let bike=remoteBikeAnimations[player.id] ?? NativeRemoteBikeAnimation();remoteBikeAnimations[player.id]=bike
                let frame=bike.update(model:model,maxLean:source.bike?["maxLean"],now:riderTime,delta:riderDelta,sample:samples.0,previous:samples.1)
                remoteBikeFrames[player.id]=frame
                input.lean=frame.lean;input.tuck=frame.tuck;input.pedal=frame.pedal;input.crank=frame.crank;input.hop=frame.hop
            }
            var pose:NativeSkeletalActor.Pose
            let playbackKey="\(player.vehicleID ?? ""):\(model):0"
            let playback:NativeRiderPlayback?
            if let cached=remoteRiderPlayback[player.id],cached.0==playbackKey{playback=cached.1}
            else {
                playback=NativeRiderPlayback(definition:source,library:library)
                if let playback{remoteRiderPlayback[player.id]=(playbackKey,playback);remoteRiderActions[player.id]=nil;remoteRiderCapture[player.id]=nil;remoteRiderPrevious[player.id]=nil}
            }
            if let playback {
                let action=player.action&63
                if remoteRiderActions[player.id] != action {
                    remoteRiderActions[player.id]=action
                    switch action {
                    case 1,3,5,6:playback.enter(side:action==1 || action==5 ? -1:1,jack:action==5 || action==6)
                    case 2,4:playback.leave(side:action==2 ? -1:1,leaveOpen:sourceSeat.door.map{NativeVehicleDamage.decode(player.vehicleDamage)?.open[$0] ?? false} ?? false)
                    default:if playback.state != .entering{playback.sit()}
                    }
                }
                if let frame=playback.update(delta:riderDelta,input:input) {
                    if let capture=frame.capture {
                        switch capture {
                        case .current:remoteRiderCapture[player.id]=remoteRiderPrevious[player.id]
                        case .sample(let value):remoteRiderCapture[player.id]=actor.riderPose(frame:value.pose,library:library,figurePosition:SIMD3<Float>(value.anchor))
                        }
                    }
                    pose=actor.riderPose(frame:frame.sample.pose,library:library,figurePosition:SIMD3<Float>(frame.sample.anchor),figureTurn:Float(frame.turn),previous:frame.transitioning ? remoteRiderCapture[player.id]:nil,transition:frame.transition)
                    remoteRiderPrevious[player.id]=pose
                    if let part=frame.doorPart,let vehicle=player.vehicleID {riderDoorHolds[vehicle,default:[:]][part]=frame.doorOpen}
                } else {pose=actor.riderPose(frame:animator.update(delta:riderDelta,configuration:source.configuration(),input:input),library:library,figurePosition:place)}
            } else {pose=actor.riderPose(frame:animator.update(delta:riderDelta,configuration:source.configuration(),input:input),library:library,figurePosition:place)}
            let car = Self.translation(player.position) * Self.rotationZ(-player.heading) *
                Self.rotationX(player.pitch) * Self.rotationY(player.roll) *
                Self.translation(SIMD3(0,0,vehicleModelOrigin(player.code)))
            appendPed(ped,player.position,player.heading,0,"",0,0,pose:pose,transform:car,original:true)
        }
        let drivenVehicleIDs = Set(remotePlayers.compactMap(\.vehicleID))
        for projectile in weaponEffects.projectiles {
            let direction = atan2(projectile.velocity.x,projectile.velocity.y)
            let pitch = atan2(projectile.velocity.z,hypot(projectile.velocity.x,projectile.velocity.y))
            modelInstances.append((projectile.model,projectile.position,direction,pitch,"",0,0))
        }
        var parkedTransforms:[String:simd_float4x4] = [:]
        var parkedTrainCandidates:[RemoteVehicle] = []
        for source in remoteVehicles where source.id != currentVehicleID && !drivenVehicleIDs.contains(source.id) {
            let vehicle=predictedVehicle(source)
            guard simd_distance(vehicle.position,camera)<130,let name=actorName(code:vehicle.code) else{continue}
            modelInstances.append((name,vehicle.position,vehicle.heading,vehicle.pitch,"",0,0))
            parkedTrainCandidates.append(vehicle)
            if let exact=groundVehicle?.otherVehicle(vehicle.id)?.transform{parkedTransforms[key(name,vehicle.position)]=exact}
        }
        var carriageTransforms:[String:simd_float4x4] = [:]
        var carriageIdentifiers:[String:String] = [:]
        var trainLayoutIDs:Set<String> = []
        func appendCarriages(_ carriages:[NativeGroundVehicle.Carriage],identity:String) {
            for (index,carriage) in carriages.enumerated() {
                guard let name=actorName(code:carriage.model) else{continue}
                modelInstances.append((name,carriage.position,0,0,"",0,0))
                let token=key(name,carriage.position)
                carriageTransforms[token]=carriage.transform
                carriageIdentifiers[token]=identity=="own" ? "carriage:\(index):\(name)":"carriage:\(identity):\(index):\(name)"
            }
        }
        if driving,let carriages=groundVehicle?.carriages {
            appendCarriages(carriages,identity:"own")
            if let currentVehicleID {trainLayoutIDs.insert(currentVehicleID)}
        }
        for vehicle in parkedTrainCandidates {
            let model=String(vehicle.code.split(separator:".").first ?? "")
            trainLayoutIDs.insert(vehicle.id)
            let carriages=groundVehicle?.trainCarriages(id:vehicle.id,model:model,bodyPosition:vehicle.position,
                heading:vehicle.heading,pitch:vehicle.pitch,roll:vehicle.roll,bodyPose:groundVehicle?.otherVehicle(vehicle.id)?.physicalPose) ?? []
            appendCarriages(carriages,identity:vehicle.id)
        }
        for player in remotePlayers {
            guard let id=player.vehicleID,id != currentVehicleID,!trainLayoutIDs.contains(id) else{continue}
            trainLayoutIDs.insert(id)
            let model=String(player.code.split(separator:".").first ?? "")
            let carriages=groundVehicle?.trainCarriages(id:id,model:model,bodyPosition:player.position,
                heading:player.heading,pitch:player.pitch,roll:player.roll) ?? []
            appendCarriages(carriages,identity:id)
        }
        groundVehicle?.retainTrainCarriageLayouts(trainLayoutIDs)
        for (name, position, angle, pitch, clip, elapsed, weapon) in modelInstances {
            let token=key(name,position),offset=actorOverrideOffsets[key(name,position),default:0]
            let queued=actorOverrides[token].flatMap { $0.indices.contains(offset) ? $0[offset]:nil }
            if queued != nil {actorOverrideOffsets[token]=offset+1}
            guard let mesh = (clip.isEmpty ? vehicleRigMeshes[name]:nil) ?? actorMeshes[name] else { loadActor(name); continue }
            let originalFoot = queued?.original ?? false
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
            } else if clip.isEmpty,let vehicle = parkedVehicle(name:name,position:position) {
                transform *= Self.rotationY(vehicle.roll)
                transform *= Self.translation(SIMD3(0,0,vehicleModelOrigin(vehicle.code)))
            }
            if driving && position == camera && clip.isEmpty, let exact = nativeVehicleTransform { transform = exact }
            if let exact=queued?.transform {transform=exact}
            if let parked=parkedTransforms[key(name,position)] {transform=parked}
            if let carriage=carriageTransforms[key(name,position)] {transform=carriage}
            var uniforms = Uniforms(viewProjection: matrix * transform,
                                    settings: SIMD4(Float(mesh.atlas.width), Float(mesh.atlas.height), night, 128))
            configureEnvironment(&uniforms)
            let opacity:Float = queued?.identity == "own" ? ownCameraVisibility.opacity:1
            uniforms.tintColor.w *= opacity
            encoder.setDepthStencilState(opacity<1 ? markerDepth:depth)
            let locomotion = name == pedModels["7"] && position == camera && !driving && actionTimeRemaining > 0 &&
                !swimming && health > 0 ? locomotionClip : nil
            let wire = clip.split(separator: "/")
            let loops: Bool? = wire.count >= 2 ? (wire.count < 3 || wire[2] == "l") : nil
            let sampledPose = skeletalActors[name].flatMap { actor in skeletalLibrary.flatMap {
                return actor.pose(clip: clip, elapsed: elapsed, library: $0,
                           locomotion: locomotion, locomotionElapsed: locomotionTime, looping: loops)
            } }
            let pose = queued?.pose ?? sampledPose
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
            if clip.isEmpty,let rig=vehicleRigs[name],vehicleRigMeshes[name] != nil {
                let frame=vehicleRigFrame(name:name,position:position,rig:rig,carriage:carriageIdentifiers[key(name,position)])
                encoder.setRenderPipelineState(vehiclePipeline ?? pipeline)
                for part in frame.draws {
                    uniforms.viewProjection=matrix*transform*part.transform
                    var material=SIMD4<Float>(part.layerOverride,part.emissive ? 1:0,part.scorched ? 0.14:1,part.alphaTest)
                    encoder.setVertexBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1)
                    encoder.setFragmentBytes(&material,length:MemoryLayout<SIMD4<Float>>.stride,index:2)
                    encoder.drawIndexedPrimitives(type:.triangle,indexCount:part.count,indexType:.uint32,indexBuffer:mesh.indices,indexBufferOffset:part.start*4)
                }
                if let vehicleMaskPipeline {
                    encoder.setRenderPipelineState(vehicleMaskPipeline)
                    for (node,mask) in vehicleWaterMasks[name] ?? [] {
                        let m=frame.matrices[node],local=simd_float4x4(columns:(SIMD4<Float>(m[0]),SIMD4<Float>(m[1]),SIMD4<Float>(m[2]),SIMD4<Float>(m[3])))
                        draw(mesh:mask,cellSize:128,matrix:matrix*transform*local,encoder:encoder)
                    }
                }
            } else if clip.isEmpty, let parts = actorParts[name], !parts.isEmpty {
                let speed = position == camera && driving ? drivingSpeed : 0
                for part in parts {
                    let pivot = SIMD3<Float>(part.pivot[0], part.pivot[1], part.pivot[2])
                    var local = matrix_identity_float4x4
                    if let wheel = part.wheel {
                        let index = wheel.contains("lf_") ? 0 : wheel.contains("lb_") || wheel.contains("lr_") ? 1 : wheel.contains("rf_") ? 2 : 3
                        let exact = position == camera && nativeVehicleTransform != nil
                        let state = exact ? nativeVehicleWheels.first(where: { $0.index == index }) : nil
                        let spin = exact ? nativeVehicleWheelAngles[index] : Float(ProcessInfo.processInfo.systemUptime)*speed/0.35
                        let turn = exact ? (wheel.contains("f_dummy") ? (groundVehicle?.output?.steering ?? 0) : (groundVehicle?.output?.rearSteering ?? 0)) :
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
            let heldWeapon = NativeWeaponAttachment.selectedWeapon(weapon,swimming:false,
                jetpackFlying:queued?.identity == "own" && personalFlight.flying,
                armWeapon:footWeaponDefinitions[weapon]?.flags?["arm"] == true)
            let rightHand:simd_float4x4?
            if let pose,let actor=skeletalActors[name] {
                rightHand=actor.transform(bone:NativeWeaponAttachment.rightHandBone,in:pose)
            } else {rightHand=actorAttachments[name]?.frame(clip:clip,elapsed:elapsed)}
            let spine = pose.flatMap { p in skeletalActors[name]?.transform(bone:NativeWeaponAttachment.parachuteBone,in:p) }
            if let weaponName = weaponModels[String(heldWeapon)], heldWeapon > 0,
               let pistol = actorMeshes[weaponName],
               let attachment = NativeWeaponAttachment.transform(weapon:heldWeapon,rightHand:rightHand,spine:spine) {
                encoder.setRenderPipelineState(pipeline)
                draw(mesh: pistol, cellSize: 128, matrix: matrix * transform * attachment,
                     encoder: encoder,tint:SIMD4(1,1,1,opacity))
                if weaponMuzzleCatalog?.definition(weapon:heldWeapon)?.twin == true,let pose,
                   let actor=skeletalActors[name],let left=actor.transform(bone:34,in:pose) {
                    draw(mesh:pistol,cellSize:128,matrix:matrix*transform*left*NativeWeaponMuzzle.attachment(left:true),
                        encoder:encoder,tint:SIMD4(1,1,1,opacity))
                }
            } else if let weaponName = weaponModels[String(heldWeapon)], heldWeapon > 0 {
                loadActor(weaponName)
            }
            if let flight=queued?.flight,let identity=queued?.identity,let pose,let actor=skeletalActors[name] {
                drawFlightAttachments(flight,identity:identity,actor:actor,pose:pose,transform:transform,matrix:matrix,encoder:encoder,opacity:opacity)
            }
            encoder.setDepthStencilState(depth)
        }
        let visible = Set(modelInstances.map { $0.0 } + modelInstances.compactMap { weaponModels[String($0.6)] })
        if actorMeshes.count > 32 {
            actorMeshes = actorMeshes.filter { visible.contains($0.key) }
            actorAnimations = actorAnimations.filter { visible.contains($0.key) }
            skeletalActors = skeletalActors.filter { visible.contains($0.key) }
            actorAttachments = actorAttachments.filter { visible.contains($0.key) }
            actorParts = actorParts.filter { visible.contains($0.key) }
            vehicleRigs=vehicleRigs.filter{visible.contains($0.key)}
            vehicleRigMeshes=vehicleRigMeshes.filter{visible.contains($0.key)}
            vehicleWaterMasks=vehicleWaterMasks.filter{visible.contains($0.key)}
        }
    }

    private func loadParticleEffects() {
        guard !particleLoading,particleRenderer==nil,let server else{return}
        particleLoading=true
        let group=DispatchGroup(),lock=NSLock();var metadata:Data?,definitions:Data?
        for (name,url) in [("metadata",server.path("game/native/effects/fx-textures.json")),("definitions",server.path("game/world/fx.json"))] {
            group.enter();URLSession.shared.dataTask(with:url){data,response,_ in
                lock.lock();if (response as? HTTPURLResponse)?.statusCode==200{if name=="metadata"{metadata=data}else{definitions=data}};lock.unlock();group.leave()
            }.resume()
        }
        group.notify(queue:.main){[weak self] in
            guard let self else{return}
            guard let metadata,let definitions,let library=self.device.makeDefaultLibrary(),
                  let renderer=NativeParticleRenderer(device:self.device,queue:self.queue,library:library,metadata:metadata),
                  let effects=try? NativeParticleEffects(data:definitions,textures:Set(renderer.document.sprites.keys)) else{self.particleLoading=false;return}
            effects.water={[weak self] point in self?.worldWater?.height(x:Float(point.x),y:Float(point.y),z:Float(point.z)).map(Double.init)}
            let loaded=DispatchGroup()
            for(index,sheet)in renderer.document.sheets.enumerated() {
                guard !sheet.file.isEmpty,sheet.file.count<64,sheet.file.utf8.allSatisfy({(48...57).contains($0)||(65...90).contains($0)||(97...122).contains($0)||[45,46,95].contains($0)}) else{continue}
                loaded.enter();URLSession.shared.dataTask(with:server.path("game/native/effects/"+sheet.file)){data,response,_ in
                    DispatchQueue.main.async {
                        if (response as? HTTPURLResponse)?.statusCode==200,let data{_ = renderer.install(sheet:index,data:data)}
                        loaded.leave()
                    }
                }.resume()
            }
            loaded.notify(queue:.main){[weak self] in
                guard let self else{return};self.particleLoading=false
                if renderer.ready{self.particleRenderer=renderer;self.particleEffects=effects}
            }
        }
    }

    private func loadFlightAssets() {
        guard !flightAssetLoading,let server else{return}
        flightAssetLoading=true
        let group=DispatchGroup(),lock=NSLock()
        var files:[String:Data]=[:]
        for name in ["parachute.bin","parachute.png","parachute.skel.bin","jetpack.bin","jetpack.png","jetpack.flight.json"] {
            group.enter()
            URLSession.shared.dataTask(with:server.path("game/native/models/"+name)){data,response,_ in
                lock.lock();if (response as? HTTPURLResponse)?.statusCode==200,let data{files[name]=data};lock.unlock();group.leave()
            }.resume()
        }
        group.notify(queue:.main){[weak self] in
            guard let self else{return};self.flightAssetLoading=false
            func mesh(_ name:String)->Mesh? {
                guard let bytes=files[name+".bin"],let pixels=files[name+".png"],let world=try? WorldBinary(data:bytes),
                      let atlas=try? self.textureLoader.newTexture(data:pixels,options:[.SRGB:false]),
                      let vertices=self.device.makeBuffer(bytes:world.vertices,length:world.vertices.count*MemoryLayout<NativeVertex>.stride),
                      let indices=self.device.makeBuffer(bytes:world.indices,length:world.indices.count*4) else{return nil}
                return Mesh(vertices:vertices,indices:indices,indexCount:world.indices.count,atlas:atlas)
            }
            if let model=mesh("parachute"),let bytes=files["parachute.skel.bin"] {
                self.flightCanopyActor=NativeSkeletalActor(data:bytes,vertexCount:model.vertices.length/MemoryLayout<NativeVertex>.stride,device:self.device,allowAccessory:true)
                if self.flightCanopyActor != nil {self.flightCanopyMesh=model}
            }
            if let model=mesh("jetpack"),let bytes=files["jetpack.flight.json"],let document=try? JSONDecoder().decode(NativeFlightAssets.self,from:bytes),document.draws.allSatisfy({$0.node>=0 && $0.node<document.nodes.count && $0.start>=0 && $0.count>=0 && $0.start+$0.count<=model.indexCount}) {
                self.flightJetMesh=model;self.flightJetAssets=document
            }
        }
    }

    private func drawFlightAttachments(_ flight:NativeFlightAnimation.Frame,identity:String,actor:NativeSkeletalActor,pose:NativeSkeletalActor.Pose,
                                       transform:simd_float4x4,matrix:simd_float4x4,encoder:MTLRenderCommandEncoder,opacity:Float=1) {
        if flightCanopyMesh==nil || flightJetMesh==nil {loadFlightAssets()}
        if let canopy=flight.canopy,let mesh=flightCanopyMesh,let accessory=flightCanopyActor,let library=skeletalLibrary,let skeletalPipeline {
            let posed=accessory.canopyPose(clip:canopy.clip,time:canopy.time,easing:canopy.easing,pitch:canopy.pitch,roll:canopy.roll,library:library,previous:flightCanopyPoses[identity])
            flightCanopyPoses[identity]=posed
            if canopy.landed && flightCanopyLanded[identity]==nil {flightCanopyLanded[identity]=transform}
            if !canopy.landed {flightCanopyLanded[identity]=nil}
            let parent=canopy.landed ? flightCanopyLanded[identity] ?? transform:transform
            var scale=matrix_identity_float4x4;scale.columns.0.x=Float(canopy.scale);scale.columns.1.y=Float(canopy.scale);scale.columns.2.z=Float(canopy.scale)
            if canopy.visible {
                encoder.setRenderPipelineState(skeletalPipeline);accessory.bind(pose:posed,encoder:encoder)
                draw(mesh:mesh,cellSize:128,matrix:matrix*parent*scale,encoder:encoder,tint:SIMD4(1,1,1,canopy.landed ? 1:opacity))
            }
        } else {flightCanopyLanded[identity]=nil}
        if let jet=flight.jet,let mesh=flightJetMesh,let document=flightJetAssets,let spine=actor.transform(bone:3,in:pose) {
            flightAudioVoices.append(.init(id:identity,sound:jet.sound,position:SIMD3(transform.columns.3.x,transform.columns.3.y,transform.columns.3.z),thrust:Float(jet.thrust)))
            let matrices=document.jetPose(jet)
            guard matrices.count==document.nodes.count else{return}
            if let effects=particleEffects {
                for(index,node)in document.nodes.enumerated() where node.name=="jetball1" || node.name=="jetball2" {
                    let world=transform*spine*matrices[index],vector=world*SIMD4<Float>(0,0,-1,0)
                    let direction=simd_normalize(SIMD3<Double>(SIMD3(vector.x,vector.y,vector.z)))
                    let origin=SIMD3<Double>(SIMD3(world.columns.3.x,world.columns.3.y,world.columns.3.z))+direction*0.15
                    effects.burst("jetpack",at:origin,delta:particleDrawDelta,options:.init(time:jet.thrust,velocity:flight.velocity,scale:0.6,turn:simd_quatd(from:SIMD3(0,0,-1),to:direction)))
                }
            }
            encoder.setRenderPipelineState(pipeline)
            var uniforms=Uniforms(viewProjection:matrix*transform*spine,settings:SIMD4(Float(mesh.atlas.width),Float(mesh.atlas.height),night,128));configureEnvironment(&uniforms)
            uniforms.tintColor.w *= opacity
            encoder.setVertexBuffer(mesh.vertices,offset:0,index:0);encoder.setFragmentTexture(mesh.atlas,index:0)
            for part in document.draws where part.visible && part.count>0 {
                uniforms.viewProjection=matrix*transform*spine*matrices[part.node]
                encoder.setVertexBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1);encoder.setFragmentBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1)
                encoder.drawIndexedPrimitives(type:.triangle,indexCount:part.count,indexType:.uint32,indexBuffer:mesh.indices,indexBufferOffset:part.start*4)
            }
        }
    }

    private func vehicleRigFrame(name:String,position:SIMD3<Float>,rig:NativeVehicleRig,carriage:String?)->NativeVehicleRig.Frame {
        let now=ProcessInfo.processInfo.systemUptime
        let player=remotePlayers.first{$0.vehicleID != nil && $0.position==position && actorName(code:$0.code)==name}
        let parked=parkedVehicle(name:name,position:position)
        let own=driving && position==camera && name==vehicleModels[activeVehicleModel]
        let token=carriage ?? (own ? "own:\(currentVehicleID ?? name):\(name)":"remote:\(player?.vehicleID ?? parked?.id ?? name):\(name)")
        let delta=min(0.1,max(0,now-(vehicleRigTimes[token] ?? now)));vehicleRigTimes[token]=now
        var input=NativeVehicleRig.Input()
        if own {
            input.work=groundVehicle?.workingRenderValue ?? 0
            input.steering = -(groundVehicle?.output?.steering ?? 0)
            input.rearSteering = -(groundVehicle?.output?.rearSteering ?? 0)
            let angles=groundVehicle?.wheelAnglesDouble ?? []
            input.frontSpin=angles.first ?? 0
            input.rearSpin=angles.count>1 ? angles[1]:0
            input.offsets=[Double](repeating:0,count:4)
            for wheel in nativeVehicleWheels where input.offsets.indices.contains(wheel.index) {input.offsets[wheel.index]=wheel.offset}
            input.drop=nativeBikeDrop.map(Double.init);input.lean=Double(nativeBikeLean);input.crank=Double(nativeBicycleCrank)
            input.rotor=Double(nativeRotorTurning);input.gearUp=nativeLandingGearUp;input.nozzle=Double(nativeAircraftNozzle ?? 5000)
            if let damage=groundVehicle?.damageController?.state {
                input.looks=damage.looks;input.tyres=damage.wheels;input.brokenLights=damage.lights
                input.doorAngles=damage.doors.map(\.angle);input.doorAxes=damage.doors.map(\.axis)
                input.scorched=damage.wrecked;input.lights=vehicleLights && !damage.wrecked
            } else {input.lights=vehicleLights}
            input.braking=(groundVehicle?.output?.brake ?? 0)>0
        } else {
            let speed=Double(carriage != nil ? drivingSpeed:player?.speed ?? 0)
            input.steering=Double(player?.steer ?? 0)
            var spins=vehicleRigSpins[token] ?? .zero
            let front=rig.document.joints.bike?.hubs["front"]?.radius ?? 0.36
            let rear=rig.document.joints.bike?.hubs["rear"]?.radius ?? 0.36
            spins -= SIMD2(speed*delta/front,speed*delta/rear);vehicleRigSpins[token]=spins
            input.frontSpin=spins.x;input.rearSpin=spins.y
            if let player,let bike=remoteBikeFrames[player.id] {input.lean=bike.lean;input.crank=bike.crank}
            if let kit=player?.kit {
                if kit.indices.contains(5),rig.document.joints.working != nil {input.work=Double(kit[5])*1000}
                if kit.indices.contains(5),rig.document.id==520 {input.nozzle=Double(kit[5])*5000}
                if kit.indices.contains(5),rig.document.joints.working == nil,rig.document.id != 520,((groundVehicle?.handlingFlags(String(rig.document.id)) ?? 0)&64) != 0 {input.rearSteering=Double(kit[5])}
                input.gearUp=kit.indices.contains(6) && kit[6] != 0
            }
            if player==nil,let parked,let frame=groundVehicle?.otherVehicle(parked.id) {
                input.work=Double(frame.work)
                input.rotor=frame.rotor;input.gearUp=frame.gearUp
                if frame.dynamic {
                    input.frontSpin=frame.frontSpin;input.rearSpin=frame.rearSpin;input.offsets=frame.offsets
                }
            }
            let text=player?.vehicleDamage ?? parked?.damage ?? ""
            if let decoded=NativeVehicleDamage.decode(text) {
                input.looks=decoded.looks;input.tyres=decoded.wheels;input.brokenLights=decoded.lights
                let model=String(rig.document.id)
                let damage=NativeVehicleDamage(mass:1000,flags:groundVehicle?.modelFlags(model) ?? 0,model:rig.document.id)
                input.doorAngles=damage.doors.indices.map{decoded.open[$0] ? damage.doors[$0].open:damage.doors[$0].closed}
                input.doorAxes=damage.doors.map(\.axis)
            }
            input.scorched=(player?.vehicleHealth ?? parked?.health ?? 1000)<=0
            input.lights=(player?.lights ?? false) && !input.scorched
        }
        let heldID=own ? currentVehicleID ?? "own":player?.vehicleID ?? parked?.id
        if let heldID,let held=riderDoorHolds[heldID] {
            let doors=own ? groundVehicle?.damageController?.state.doors:NativeVehicleDamage(mass:1000,flags:groundVehicle?.modelFlags(String(rig.document.id)) ?? 0,model:rig.document.id).doors
            if let doors {
                for(part,fraction)in held where doors.indices.contains(part) && input.doorAngles.indices.contains(part){input.doorAngles[part]=doors[part].open*fraction}
            }
        }
        var state=vehicleRigStates[token] ?? .init()
        let frame=rig.pose(input,state:&state,delta:delta);vehicleRigStates[token]=state
        if vehicleRigTimes.count>128 {
            vehicleRigTimes=vehicleRigTimes.filter{now-$0.value<30}
            vehicleRigStates=vehicleRigStates.filter{vehicleRigTimes[$0.key] != nil}
            vehicleRigSpins=vehicleRigSpins.filter{vehicleRigTimes[$0.key] != nil}
        }
        return frame
    }

    private func configureEnvironment(_ uniforms: inout Uniforms) {
        guard let conditions, camera.z < 700 else { return }
        uniforms.fogColor = weatherSnapshot?.flash == true ? SIMD4(1,1,1,1) : conditions.skyBottom
        uniforms.fogSettings = SIMD4(conditions.fogStart,conditions.farClip,atmosphereAir,0)
    }

    private func drawEffects(encoder:MTLRenderCommandEncoder,matrix:simd_float4x4,eye:SIMD3<Float>,viewMatrix:simd_float4x4,projection:simd_float4x4,delta:Double) {
        if let effects=particleEffects,let renderer=particleRenderer {
            effects.update(delta:delta,brightness:1-0.6*Double(night))
            let fog=weatherSnapshot?.flash==true ? SIMD4<Float>(1,1,1,1):conditions?.skyBottom ?? SIMD4<Float>(0,0,0,1)
            renderer.draw(effects.particles,eye:eye,view:viewMatrix,projection:projection,fogColor:SIMD3(fog.x,fog.y,fog.z),fogNear:conditions?.fogStart ?? 0,fogFar:conditions?.farClip ?? 25000,fogAmount:conditions==nil || camera.z>=700 ? 0:atmosphereAir,encoder:encoder)
            encoder.setDepthStencilState(depth)
        }
        guard let atlas=effectAtlas else{return}
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
        for (position,_,started) in blasts where particleEffects==nil {
            let age = Float(now-started), size = 1+age*7
            sprite("fireball6",at:position+SIMD3(0,0,size*0.25),width:size,height:size,color:SIMD4(1,0.65,0.22,max(0,1-age)))
            if age > 0.15 { sprite("smoke5",at:position+SIMD3(0,0,age*4),width:size*1.3,height:size,color:SIMD4(0.3,0.3,0.3,0.45*(1-age))) }
        }
        for fire in weaponEffects.fires where particleEffects==nil { for flame in fire.flames where flame.strength > 0 {
            sprite("fireball6",at:flame.position+SIMD3(0,0,0.8),width:1,height:1.8,color:SIMD4(1,0.55,0.1,min(1,flame.strength)))
        } }
        for stream in weaponEffects.streams where particleEffects==nil {
            let texture = stream.weapon == 37 ? "fireball6" : stream.weapon == 42 ? "smoke" : "sphere"
            let color = stream.weapon == 37 ? SIMD4<Float>(1,0.55,0.1,0.6) : SIMD4<Float>(0.9,0.95,1,0.35)
            for n in 1...12 {
                let share = Float(n)/12, spread = 0.15+share*0.7
                sprite(texture,at:stream.position+stream.direction*(share*stream.range),width:spread,height:spread,color:color)
            }
        }
        for projectile in weaponEffects.projectiles where particleEffects==nil && projectile.weapon==17 && projectile.lying {
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
