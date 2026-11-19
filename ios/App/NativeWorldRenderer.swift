import Foundation
import MetalKit
import simd
import CryptoKit

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
    private struct TransparentVehicleDraw {
        let mesh:Mesh,part:NativeVehicleRig.Draw,uniforms:Uniforms
        let pipeline:MTLRenderPipelineState
        let painted:Bool,depth:Float
        var bindTextures:((MTLRenderCommandEncoder)->Bool)?=nil
    }
    private struct TransparentWorldDraw {
        let mesh:Mesh,range:NativeWorldDrawPlan.Range,uniforms:Uniforms
        let native:NativeWorldSharpTextures?,depth:Float
    }
    private var deferredWorldSurfaces:[TransparentWorldDraw]=[]
    // Nil keeps the standalone actor encoder's existing behavior. A scene
    // frame captures packets so world glass can participate in the same order.
    private var deferredVehicleSurfaces:[TransparentVehicleDraw]?
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
    private let worldPipeline: MTLRenderPipelineState
    private let worldSharpPipeline: MTLRenderPipelineState?
    private let worldSurfacePipelines:[String:MTLRenderPipelineState]
    private let vehiclePipeline: MTLRenderPipelineState?
    private let vehiclePaintPipeline: MTLRenderPipelineState?
    private let vehicleNativePipeline: MTLRenderPipelineState?
    private let vehicleMaskPipeline:MTLRenderPipelineState?
    private let animatedPipeline: MTLRenderPipelineState
    private let skeletalPipeline: MTLRenderPipelineState?
    // Same ordinary vertex/appearance states; only the explicit atlas layout differs.
    private let pedAtlasPipeline:MTLRenderPipelineState?
    private let pedAtlasAnimatedPipeline:MTLRenderPipelineState?
    private let pedAtlasSkeletalPipeline:MTLRenderPipelineState?
    private let pedNativePipeline:MTLRenderPipelineState?
    private let pedNativeAnimatedPipeline:MTLRenderPipelineState?
    private let pedNativeSkeletalPipeline:MTLRenderPipelineState?
    private struct PedAtlasGPU {
        let family:String,source:String,layout:MTLBuffer,textureBytes:Int
        let native:NativePedTextureArrays?
        init(family:String,source:String,layout:MTLBuffer,textureBytes:Int,native:NativePedTextureArrays?=nil) {
            self.family=family;self.source=source;self.layout=layout;self.textureBytes=textureBytes;self.native=native
        }
    }
    private var pedAtlasFamilies:[String:String]=[:]
    private var pedAtlasV2Names=Set<String>()
    private var pedAtlasGPU:[String:PedAtlasGPU]=[:]
    private struct PedAtlasLoad {let token:UUID;var request:NativePedAtlasLoader.Request?}
    private var pedAtlasLoads:[String:PedAtlasLoad]=[:]
    private var pedAtlasAdmission:[String:UUID]=[:]
    private var pedAtlasDemand=Set<String>(),pedAtlasErrors=Set<String>()
    private let pedAtlasLoader=NativePedAtlasLoader()
    private var pedAtlasSource:String?

    private let skyPipeline: MTLRenderPipelineState?
    private let atmospherePipelines: [String: MTLRenderPipelineState]
    private let waterPipeline: MTLRenderPipelineState?
    private let skyDepth: MTLDepthStencilState
    private let depth: MTLDepthStencilState
    private let markerDepth: MTLDepthStencilState
    private let textureLoader: MTKTextureLoader
    private var meshes: [String: Mesh] = [:]
    private struct WorldSharpBase {let layers:Int,mapping:[UInt16],source:String;let indices:Int,center:SIMD3<Float>}
    private var worldSharpBase:[String:WorldSharpBase]=[:]
    private var worldSharpManifest:NativeWorldSharpManifest?,worldSharpSource:String?
    private var worldSharpIndexTask:NativeResourceTask?,worldSharpTicket:NativeWorldSharpTicket?
    private var worldSharpName:String?,worldSharpGPU:NativeWorldSharpTextures?
    private var worldSharpRetry:[String:Date]=[:]
    private var worldSharpIndexReady=false,worldSharpIndexRetry=Date.distantPast
    private let worldSharpLoader=NativeWorldSharpLoader()
    let legacyObjects=NativeSAMPObjects.Store()
    var legacyVirtualWorld:Int32=0
    var legacyLocalPlayerID:UInt16?
    private var legacyModelPipelines:NativeRenderWareModel.Pipelines?
    private var legacyPedPipelines:NativeRenderWarePedModel.Pipelines?
    private var legacyModels:[Int32:NativeRenderWareModel.Uploaded]=[:]
    private var legacyPedModels:[String:NativeRenderWarePedModel.Uploaded]=[:]
    private var fixedCJ:NativeCJRuntimeModel?
    private var fixedCJObserver:UUID?
    private var legacyPedStyles:[String:String]=[:]
    private var legacyModelDefinitions:[Int32:NativeSAMPArtwork.Model]=[:]
    private var legacyModelCosts:[Int32:Int]=[:]
    private var legacyModelBytes=0
    private var legacyAssetEpoch:UInt64=0
    private var legacyStockCatalog:NativeSAMPStockModels?
    private var legacyStockCollisionCatalog:NativeSAMPStockCollisionCatalog?
    private var legacyStockManifestSHA256:String?
    private var legacyStockLoader:NativeSAMPStockAssetLoader?
    private var legacyStockModels=Set<Int32>()
    private enum LegacyStockCollisionKind:String {case authored,authoredEmpty,inventoryAbsent}
    private var legacyStockCollisionKinds:[Int32:LegacyStockCollisionKind]=[:]
    private var legacyStockReferences=Set<Int32>()
    private var legacyStockLoads:[Int32:(token:UUID,request:UUID?)]=[:]
    private var legacyStockRetries:[Int32:Double]=[:]
    private var legacyStockUse:[Int32:Double]=[:]
    private var legacyStockPumping=false
    private var legacyStockMetadataEpoch:UInt64=0
    private var legacyStockMetadataPending=0
    private var legacyStockMetadataRetryAfter=0.0
    private var legacyStockMetadataTasks:[UUID:LegacyStockMetadataTransfer]=[:]
    private let legacyImportQueue=DispatchQueue(label:"ZGTA.RenderWare.import",qos:.userInitiated)
    private var legacyMissingObjects=Set<Int32>()
    private var legacyMaterialOwner:NativeSAMPObjectMaterials.Owner?
    private var legacyExactTextures:[NativeSAMPObjectMaterials.TextureRequest:NativeSAMPObjectMaterials.Texture]=[:]
    private var legacyTextureSources:[NativeSAMPObjectMaterials.TextureRequest:UInt32]=[:]
    private var legacyTextureConflicts=Set<NativeSAMPObjectMaterials.TextureRequest>()
    private var legacyTextureLoads=Set<NativeSAMPObjectMaterials.TextureRequest>()
    private var legacyTextureRetries:[NativeSAMPObjectMaterials.TextureRequest:Double]=[:]
    private var legacyExternalTextureBytes:[NativeSAMPObjectMaterials.TextureRequest:Int]=[:]
    private var legacyTextureUse:[NativeSAMPObjectMaterials.TextureRequest:Double]=[:]
    private var legacyMaterialErrors=Set<String>()
    private var legacyCollisionModels:[Int32:[NativeRenderWareCollision.Model]]=[:]
    private lazy var legacyCollisionWorld=groundVehicle.flatMap{try?NativeRenderWareCollisionWorld(world:$0.world)}
    private var legacyCollisionHandles:[UInt16:[NativeRenderWareCollisionWorld.Handle]]=[:]
    private var legacyCollisionKinds:[UInt16:Int32]=[:]
    private var legacyCollisionSerial:UInt64=1
    private var legacySpectatorAccumulator=0.0
    private var legacyObjectClock=NativeSAMPObjectSimulationClock()
    private enum LegacyImportPlan {
        case object(NativeRenderWareModel.Plan),pedestrian(NativeRenderWarePedModel.Plan)
        var resources:NativeRenderWareModel.Plan{switch self{case .object(let plan):return plan;case .pedestrian(let plan):return plan.model}}
    }
    private struct LegacyPreparedImport {
        let drawing:LegacyImportPlan
        let collision:[NativeRenderWareCollision.Model]
    }
    private var actorMeshes: [String: Mesh] = [:]
    private var actorParts: [String: [ActorPart]] = [:]
    private var vehicleRigs:[String:NativeVehicleRig] = [:]
    private var vehicleRigMeshes:[String:Mesh] = [:]
    private var vehicleTextures:[String:NativeVehicleTextures] = [:]
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
    private var selfhostBreathConnection: String?
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
    private var pendingExitPlacement:(()->Void)?
    private var vehicleExitSerial:UInt64=0
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
        var ownFoot:Bool
        var canopySamples:[NativeFlightAnimation.Canopy?] = []
    }
    /// A draw occurrence owns its source, even when another body has the same
    /// model and position. None of these render identities grants body control.
    private struct OwnVehicleDrawSnapshot {
        let input:NativeVehicleRig.Input
        let doors:[NativeVehicleDamage.Door]?
        let wheelOffsets:[Int:Double],wheelAngles:[Float]
        let speed:Float,steering:Double,rearSteering:Double,fallbackSteering:Float
        var wheelPhaseOwned=false
    }
    private struct ParkedVehicleDrawSnapshot {
        let work:Double,rotor:Double,gearUp:Bool,dynamic:Bool
        let frontSpin:Double,rearSpin:Double,offsets:[Double]
    }
    private struct VehicleDrawContext {
        enum Source {
            case own(OwnVehicleDrawSnapshot)
            case remote(RemotePlayer)
            case parked(RemoteVehicle,ParkedVehicleDrawSnapshot?)
            case carriage(speed:Float)
        }
        let source:Source,token:String,appearanceCode:String
        let roll:Float,origin:Float,exactTransform:simd_float4x4?,heldDoorID:String?
        var own:OwnVehicleDrawSnapshot? {if case .own(let value)=source{return value};return nil}
        var player:RemotePlayer? {if case .remote(let value)=source{return value};return nil}
        var parked:RemoteVehicle? {if case .parked(let value,_)=source{return value};return nil}
        var parkedPhysical:ParkedVehicleDrawSnapshot? {if case .parked(_,let value)=source{return value};return nil}
        var isCarriage:Bool {if case .carriage=source{return true};return false}
        var carriageSpeed:Float {if case .carriage(let value)=source{return value};return 0}
    }
    private var lastRiderDraw: Double = 0
    private var riderPoseClock=NativeRiderPoseClock()
    private var riderMonotonicNow:()->Double={ProcessInfo.processInfo.systemUptime}
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
    private var actorRetryAfter:[String:Date]=[:]
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
    private let legacyFollowCamera = NativeGameCamera(persistViews:false)
    private var legacyGameCamera = NativeSAMPGameCamera()
    private var legacyCameraSample:NativeSAMPGameCamera.Sample?
    private var legacyCameraSubject:NativeSAMPGameCamera.Subject?
    private var legacyCameraDiagnostics=Set<NativeSAMPGameCamera.Diagnostic>()
    var legacySpectating:Bool{legacyGameCamera.spectating}
    var legacySpectatorPosition:SIMD3<Float>?{legacyCameraSample?.spectating == true ? legacyCameraSample?.pose.eye:nil}
    private var scenePosition:SIMD3<Float>{legacyCameraSample?.active == true ? legacyCameraSample!.pose.eye:camera}
    private var appPreferences = NativeAppSettings.defaults
    private var ownCameraVisibility=NativeCameraVisibility()
    private var gameCameraFrame: NativeGameCamera.Frame?
    private var passiveCameraTrace:NativePassiveCameraTrace?
    private var passiveCameraTraceClosing=false
    private var passiveCameraRay:NativePassiveCameraTrace.Ray?
    /// Explicit diagnostic seam; no launch flag, settings migration, upload or
    /// gameplay input is attached to it. Files stay in this app's own cache.
    @discardableResult func beginPassiveCameraTrace(maximumRecords:Int=1800,maximumBytes:Int=2*1024*1024)->Bool {
        guard Thread.isMainThread,passiveCameraTrace==nil,!passiveCameraTraceClosing,
              let cache=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask).first else{return false}
        passiveCameraTrace=NativePassiveCameraTrace(directory:cache.appendingPathComponent("CameraAudit",isDirectory:true),
            limits:.init(records:maximumRecords,bytes:maximumBytes,pending:32))
        passiveCameraRay=nil
        gameCamera.onVehicleObservation = {[weak self] observation in
            guard let self else{return}
            self.passiveCameraTrace?.submit(.init(camera:observation,ray:self.passiveCameraRay,draw:nil))
            self.passiveCameraRay=nil
        }
        return true
    }
    func endPassiveCameraTrace(completion:@escaping(NativePassiveCameraTrace.Summary?)->Void) {
        guard Thread.isMainThread else{
            DispatchQueue.main.async{[weak self] in
                guard let self else{completion(nil);return}
                self.endPassiveCameraTrace(completion:completion)
            }
            return
        }
        guard let recorder=passiveCameraTrace else{completion(nil);return}
        passiveCameraTrace=nil;passiveCameraTraceClosing=true;passiveCameraRay=nil
        gameCamera.onVehicleObservation=nil
        recorder.stop{[weak self] summary in self?.passiveCameraTraceClosing=false;completion(summary)}
    }
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
    private(set) var localSkin = 7
    private(set) var localLegacySkin: Int?
    private let actorSelection = NativeActorSelection()
    var actorSelectionState: NativeActorSelection.State? {
        guard let state=actorSelection.state,state.request.sourceIdentity==fixedCJSourceIdentity() else{return nil}
        return state
    }
    var onActorSelectionChanged: ((NativeActorSelection.State)->Void)? {
        didSet { actorSelection.onChange = onActorSelectionChanged }
    }
    private var pendingActorSelection: NativeActorSelection.Request? {
        guard let state = actorSelection.state, state.phase == .pending else { return nil }
        return state.request
    }
    private var pendingLocalSkin: Int? {
        guard let request = pendingActorSelection, request.domain == .native else { return nil }
        return request.skin
    }
    private var pendingLegacySkin: Int? {
        guard let request = pendingActorSelection, request.domain == .legacy else { return nil }
        return request.skin
    }
    func cancelActorSelection() { actorSelection.cancel() }
    private var sampSkinCatalog: NativeSAMPSkinCatalog?
    @discardableResult func loadLegacySkinCatalog(_ data: Data) -> Bool {
        guard let catalog = try? NativeSAMPSkinCatalog(data: data) else { return false }
        sampSkinCatalog = catalog
        resumeActorSelection()
        return true
    }
    /// SA-MP IDs refer to retail peds.ide, not the browser's compact array.
    @discardableResult func setLegacySkin(_ skin: Int) -> Bool {
        let request=actorSelection.begin(domain: .legacy, skin: skin, sourceIdentity: fixedCJSourceIdentity())
        return resolveActorSelection(request,forceCJ:skin==0)
    }
    /// Requests received before the model catalogue are applied once it arrives.
    /// Unsupported/custom IDs remain explicit gaps rather than another skin
    /// being advertised as the requested model.
    @discardableResult func setLocalSkin(_ skin: Int) -> Bool {
        let request=actorSelection.begin(domain: .native, skin: skin, sourceIdentity: fixedCJSourceIdentity())
        return resolveActorSelection(request,forceCJ:skin==0)
    }
    /// Async resource arrivals resume one current intent, never a new request.
    /// Resource admission does not change the server's canonical wire identity.
    private func resumeActorSelection() {
        guard let request = pendingActorSelection else { return }
        _ = resolveActorSelection(request)
    }
    @discardableResult private func resolveActorSelection(_ request: NativeActorSelection.Request,forceCJ:Bool=false) -> Bool {
        let source = fixedCJSourceIdentity()
        _ = actorSelection.invalidateSource(source)
        guard actorSelection.owns(request, sourceIdentity: source) else { return false }
        func unavailable(_ message: String) -> Bool {
            if actorSelection.unavailable(request, sourceIdentity: fixedCJSourceIdentity(), message: message) { onStatus?(message) }
            return false
        }
        let skin: Int
        if request.skin == 0 {
            if let existing=pedModels["0"],existing != "null" {
                return unavailable("FIXED NORMAL CJ CONFLICTS WITH THE EXISTING SKIN0 CATALOGUE")
            }
            // Only a new explicit selection bypasses the failed-owner retry
            // delay. Resource arrivals and remote demand retain normal backoff.
            guard fixedCJ?.isReady == true, pedModels["0"] == "null" else { ensureFixedCJ(force:forceCJ); return false }
            skin = 0
        } else if request.domain == .legacy {
            if (20001...30000).contains(request.skin) {
                guard legacyPedModels["samp-dl-\(request.skin)"] != nil else { return false }
                skin = request.skin
            } else {
                guard let catalog = sampSkinCatalog, !pedModels.isEmpty else { return false }
                guard let native = catalog.nativeSkin(forLegacy: request.skin),
                      pedModels[String(native)] == catalog.model(forLegacy: request.skin) else {
                    return unavailable("NO CONVERTED NATIVE MODEL FOR SA-MP SKIN \(request.skin)")
                }
                skin = native
            }
        } else { skin = request.skin }
        guard !pedModels.isEmpty else { return false }
        guard let model = pedModels[String(skin)] else { return unavailable("NO CONVERTED NATIVE MODEL FOR SKIN \(skin)") }
        // A ready-resource callback may have been superseded or invalidated.
        guard actorSelection.owns(request, sourceIdentity: fixedCJSourceIdentity()) else { return false }
        let changed = skin != localSkin
        localSkin = skin; localLegacySkin = request.domain == .legacy ? request.skin : nil
        loadActor(model)
        if changed {
            prepareFootAnimation()
            // Pose captures belong to the previous skeleton.
            ownRiderCapture = nil; ownRiderPrevious = nil; ownRiderFeet = nil
            ownCameraVisibility.reset()
        }
        return actorSelection.applied(request, nativeSkin: skin, sourceIdentity: fixedCJSourceIdentity())
    }
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
    /// Legacy servers own interior identity independently of altitude. Nil
    /// retains the original browser/self-hosted scene convention.
    var networkInterior: Int? = nil {
        didSet { if oldValue != networkInterior { loadNearby() } }
    }
    private var isInterior: Bool { networkInterior.map { $0 != 0 } ?? (camera.z > 700) }
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
    private var remoteSuspensionConfigurations = [Int: NativeRemoteSuspension.Configuration]()
    private var remoteSuspensionRayBudget = 0
    private var vehicleInfo: [String: [String: String]] = [:]
    private var activeVehicleModel = ""
    private var ownedVehicleAppearance:(id:String,code:String)?
    private var ownVehicleAppearanceCode:String {
        if let id=currentVehicleID,let row=remoteVehicles.first(where:{$0.id==id}){return row.code}
        if let value=ownedVehicleAppearance,value.id==currentVehicleID{return value.code}
        return activeVehicleModel.isEmpty ? "420":activeVehicleModel
    }
    private var activeHandling: VehicleHandling?
    private var activeModelOrigin: Float = 0
    private var pendingVehicleSnapshot:NativeOtherVehicles.Snapshot?
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
    var nativeVehicleTransform: simd_float4x4? { isPassenger ? passengerFrame?.transform:groundVehicle?.active == true ? groundVehicle?.modelTransform : nil }
    var nativeVehicleOrientation: simd_quatf? { groundVehicle?.active == true ? groundVehicle?.orientation : nil }
    /// Read the live owned Rapier body, including pitch/roll and immediate
    /// server changes. Convert the rotation axis once from Y-up to GTA Z-up;
    /// SA-MP orders quaternion components w,x,y,z. Never reconstruct from yaw.
    var legacyVehicleQuaternion: SIMD4<Float>? {
        guard driving, let ground = groundVehicle, ground.active,
              let collider = ground.chassisColliders.first,
              let body = ground.world.colliderInfo(collider)?.body,
              let state = ground.world.bodyState(body) else { return nil }
        let q = state.rotation
        let value = SIMD4(q.real, q.imag.x, -q.imag.z, q.imag.y)
        let length = simd_length_squared(value)
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite, value.w.isFinite,
              length.isFinite, length > 0.000001 else { return nil }
        return value
    }
    /// Original messages target the currently occupied vehicle. Actor health
    /// remains with the pedestrian owner; model immunity precedes both health
    /// damage and the optional geometry-eligible tyre burst.
    @discardableResult func receiveOriginalVehicleHit(_ message: [String: Any],
        random: () -> Double = { Double.random(in: 0..<1) }) -> Bool {
        guard let ground = groundVehicle, ground.active, let damage = ground.damageController,
              let model = Int(activeVehicleModel),
              let hit = NativeOriginalWorldCommands.vehicleDamage(message, driving: driving, model: model) else { return false }
        damage.state.inflict(hit.damage)
        if let wheel = hit.wheel { _ = burstOriginalVehicleWheel(wheel, random: random) }
        vehicleHealth = Int(min(1000, max(0, damage.state.health.rounded())))
        activeVehicleDamage = damage.state.text()
        return true
    }
    private func burstOriginalVehicleWheel(_ wheel: Int, random: () -> Double) -> Bool {
        guard let ground = groundVehicle, ground.active, let damage = ground.damageController,
              let model = vehicleModels[activeVehicleModel], let rig = vehicleRigs[model] else { return false }
        let document = rig.document
        let eligible: Bool
        if document.kind == "bike", let bike = document.joints.bike {
            eligible = !bike.pedalled && (wheel == 0 ? bike.hubs["front"] != nil : wheel == 1 && bike.hubs["rear"] != nil)
        } else {
            eligible = document.kind == "car" && document.id != 432 && document.joints.wheels.contains {
                2 * ($0.left ? 0 : 1) + ($0.front ? 0 : 1) == wheel
            }
        }
        guard eligible, damage.state.burst(wheel) else { return false }
        guard let collider = ground.chassisColliders.first, let body = ground.world.colliderInfo(collider)?.body,
              let state = ground.world.bodyState(body) else { return true }
        let amount = document.kind == "bike" ? 0.02 : 0.03
        let right = state.rotation.act(SIMD3<Float>(1,0,0)), forward = state.rotation.act(SIMD3<Float>(0,0,-1))
        let move = right * Float(50 * ((2 * random() - 1) * amount))
        let turn = simd_cross(forward, right) * Float(50 * ((2 * random() - 1) * amount))
        _ = ground.world.setVelocities(body, linear: state.linearVelocity + move, angular: state.angularVelocity + turn)
        return true
    }
    var vehicleWirePosition: SIMD3<Float> { isPassenger ? passengerFrame?.vehicle.position ?? camera:groundVehicle?.active == true ? groundVehicle!.bodyPosition : camera }
    private(set) var passengerSeat:Int?
    var isPassenger:Bool{passengerSeat != nil}
    private struct SharedVehicleFrame {let vehicle:RemoteVehicle;let transform:simd_float4x4;let speed:Float;let velocity:SIMD3<Float>;var angularVelocity=SIMD3<Float>.zero}
    private var passengerFrame:SharedVehicleFrame?
    private var passengerAccumulator=0.0
    var passengerWirePosition:SIMD3<Float>{
        if let feet=ownRiderFeet{return feet.position}
        guard let frame=passengerFrame,let seat=passengerSeat,
              let definition=riderDefinitions?.models[activeVehicleModel],definition.seats.indices.contains(seat),let point=definition.seats[seat].position else{return camera}
        let at=frame.transform*SIMD4(point,1);return SIMD3(at.x,at.y,at.z)
    }
    var passengerVelocity:SIMD3<Float>{passengerFrame?.velocity ?? .zero}
    var vehicleRoll: Float { groundVehicle?.active == true ? groundVehicle!.roll : vehicleFallbackRoll }
    func vehicleModelOrigin(_ code: String) -> Float { groundVehicle?.modelOrigin(String(code.split(separator: ".").first ?? "")) ?? 0 }
    var nativeVehicleWheels: [NativeVehicleDynamics.WheelSnapshot] { groundVehicle?.output?.wheels ?? [] }
    private var ownVehicleWheelClocks:[Double] {
        if groundVehicle?.active == true{return groundVehicle?.wheelAnglesDouble ?? []}
        if let snapshot=pendingVehicleSnapshot{return [snapshot.frontSpin,snapshot.rearSpin,snapshot.frontSpin,snapshot.rearSpin]}
        return groundVehicle?.wheelAnglesDouble ?? []
    }
    var nativeVehicleWheelAngles: [Float] {ownVehicleWheelClocks.map(Float.init)}
    var nativeBikeLean: Float { groundVehicle?.bikeLean ?? 0 }
    var nativeBikeDrop: [Float] { groundVehicle?.bikeDrop ?? [] }
    var nativeBicyclePedal: Int { groundVehicle?.bicyclePedal ?? 0 }
    var nativeBicycleCrank: Float { groundVehicle?.bicycleCrank ?? 0 }
    var nativeBicycleHop: Float { groundVehicle?.bicycleHop ?? 0 }
    var nativeBikeFullLean: Float { groundVehicle?.bikeFullLean ?? 0 }
    var nativeRotorTurning: Float { groundVehicle?.rotorTurning ?? 0 }
    var nativeVehicleAudioSnapshot:NativeGroundVehicle.AudioSnapshot? {groundVehicle?.audioSnapshot()}
    func takeVehicleHullAudio()->NativeGroundVehicle.HullAudio? {groundVehicle?.takeHullAudio()}
    var audioEar:SIMD3<Float> {legacyCameraSample?.active == true ? legacyCameraSample!.pose.eye:gameCameraFrame?.source ?? camera}
    var audioForward:SIMD3<Float> {legacyCameraSample?.active == true ? simd_normalize(legacyCameraSample!.pose.target-legacyCameraSample!.pose.eye):gameCameraFrame.map{simd_normalize($0.target-$0.source)} ?? aimDirection}
    func remoteVehicleAudioTop(_ model:String)->Double? {groundVehicle?.remoteAudioTop(model:model)}
    var nativeAircraftNozzle: Float? { groundVehicle?.aircraftNozzle }
    var nativeLandingGearUp: Bool { groundVehicle?.landingGearUp ?? false }
    var hasLandingGear: Bool { [476,519,577,520,553,592].contains(Int(activeVehicleModel) ?? 0) }
    var hasJetNozzle: Bool { activeVehicleModel == "520" }
    var hasVehicleHorn: Bool { driving && !isPassenger && !["plane","helicopter","bicycle"].contains(vehicleKind) }
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
    var onVehicleLostInWater:(()->Void)?
    var onVehicleWrecked:(()->Void)?
    var onBikeEjection:((NativeBikeEjection.Event)->Void)?
    var onVehicleExplosion: ((SIMD3<Float>) -> Void)?
    var onVehicleMove: ((String,[String:Any]) -> Void)?
    var onContactAudio: (([NativeVehicleDamageController.Collision],NativeVehicleDamage.Body) -> Void)?
    var onLocalImpact:((Int)->Void)?
    var onLocalHealth: ((Int) -> Void)?
    /// Explicit native fatal cause; an untyped zero-health update cannot
    /// distinguish a wreck explosion from a fall or another scripted death.
    var onLocalFatal:((Int)->Void)?
    /// Original-world fractional damage bypasses the integral self-host ACK
    /// adapter. Weapon53 is drowning and54 is falling; both bypass armour.
    var onLocalDamage: ((Double,Int) -> Void)?
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
    /// A successfully admitted task replaced an active reload animation.
    var onReloadTaskCancelled: (() -> Void)?
    /// A movement task took ownership of an active aim latch. The input/HUD
    /// owner must retire it before another internal fixed step can return foot.
    var onFootAimCancelled: (() -> Void)?
    private var acceptedStreamShot=false
    private var acceptedStreamRay:(weapon:Int,origin:SIMD3<Float>,direction:SIMD3<Float>)?
    var aiming = false
    var driving = false
    var remoteServerTimeOffsetMilliseconds: Double?
    var remotePlayers: [RemotePlayer] = [] { didSet {
        recordRemoteAnimationPackets()
        if remotePlayers.contains(where:{$0.skin==0}){ensureFixedCJ()}
    } }
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
              let fragment = library.makeFunction(name: "ordinaryModelFragment"),
              let worldFragment = library.makeFunction(name: "worldFragment") else { return nil }
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
        descriptor.fragmentFunction = worldFragment
        guard let worldPipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        descriptor.fragmentFunction = library.makeFunction(name:"worldSharpFragment")
        let worldSharpPipeline=descriptor.fragmentFunction.flatMap{_ in try? device.makeRenderPipelineState(descriptor:descriptor)}
        var worldSurfacePipelines:[String:MTLRenderPipelineState]=[:]
        for (kind,function) in [("base","worldSurfaceFragment"),("sharp","worldSharpSurfaceFragment")] {
            descriptor.fragmentFunction=library.makeFunction(name:function)
            for (phase,blended) in [("solid",false),("clear",true)] {
                descriptor.colorAttachments[0].isBlendingEnabled=blended
                if descriptor.fragmentFunction != nil,let state=try? device.makeRenderPipelineState(descriptor:descriptor) {
                    worldSurfacePipelines[kind+"."+phase]=state
                }
            }
        }
        descriptor.colorAttachments[0].isBlendingEnabled=true
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].writeMask = []
        let vehicleMaskPipeline=try? device.makeRenderPipelineState(descriptor:descriptor)
        descriptor.colorAttachments[0].writeMask = .all
        descriptor.fragmentFunction = library.makeFunction(name:"vehicleFragment")
        let vehiclePipeline = descriptor.fragmentFunction.flatMap {_ in try? device.makeRenderPipelineState(descriptor:descriptor)}
        descriptor.fragmentFunction = library.makeFunction(name:"vehiclePaintFragment")
        let vehiclePaintPipeline = descriptor.fragmentFunction.flatMap {_ in try? device.makeRenderPipelineState(descriptor:descriptor)}
        descriptor.fragmentFunction = library.makeFunction(name:"vehicleNativeFragment")
        let vehicleNativePipeline = descriptor.fragmentFunction.flatMap {_ in try? device.makeRenderPipelineState(descriptor:descriptor)}
        descriptor.fragmentFunction = fragment
        descriptor.vertexFunction = animatedVertex
        guard let animatedPipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        descriptor.vertexFunction = library.makeFunction(name: "skeletalActorVertex")
        let skeletalPipeline = descriptor.vertexFunction.flatMap { _ in try? device.makeRenderPipelineState(descriptor: descriptor) }
        descriptor.fragmentFunction=library.makeFunction(name:"ordinaryPedAtlasFragment")
        descriptor.vertexFunction=vertex
        let pedAtlasPipeline=descriptor.fragmentFunction.flatMap{_ in try? device.makeRenderPipelineState(descriptor:descriptor)}
        descriptor.vertexFunction=animatedVertex
        let pedAtlasAnimatedPipeline=descriptor.fragmentFunction.flatMap{_ in try? device.makeRenderPipelineState(descriptor:descriptor)}
        descriptor.vertexFunction=library.makeFunction(name:"skeletalActorVertex")
        let pedAtlasSkeletalPipeline=descriptor.vertexFunction.flatMap{_ in
            descriptor.fragmentFunction.flatMap{_ in try? device.makeRenderPipelineState(descriptor:descriptor)}
        }
        descriptor.fragmentFunction=library.makeFunction(name:"ordinaryPedNativeFragment")
        descriptor.vertexFunction=vertex
        let pedNativePipeline=descriptor.fragmentFunction.flatMap{_ in try? device.makeRenderPipelineState(descriptor:descriptor)}
        descriptor.vertexFunction=animatedVertex
        let pedNativeAnimatedPipeline=descriptor.fragmentFunction.flatMap{_ in try? device.makeRenderPipelineState(descriptor:descriptor)}
        descriptor.vertexFunction=library.makeFunction(name:"skeletalActorVertex")
        let pedNativeSkeletalPipeline=descriptor.vertexFunction.flatMap{_ in
            descriptor.fragmentFunction.flatMap{_ in try? device.makeRenderPipelineState(descriptor:descriptor)}
        }

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
        self.worldPipeline = worldPipeline
        self.worldSharpPipeline = worldSharpPipeline
        self.worldSurfacePipelines=worldSurfacePipelines
        self.vehiclePipeline = vehiclePipeline
        self.vehiclePaintPipeline = vehiclePaintPipeline
        self.vehicleNativePipeline = vehicleNativePipeline
        self.vehicleMaskPipeline = vehicleMaskPipeline
        self.animatedPipeline = animatedPipeline
        self.skeletalPipeline = skeletalPipeline
        self.pedAtlasPipeline=pedAtlasPipeline;self.pedAtlasAnimatedPipeline=pedAtlasAnimatedPipeline;self.pedAtlasSkeletalPipeline=pedAtlasSkeletalPipeline
        self.pedNativePipeline=pedNativePipeline;self.pedNativeAnimatedPipeline=pedNativeAnimatedPipeline;self.pedNativeSkeletalPipeline=pedNativeSkeletalPipeline
        self.skyPipeline = skyPipeline
        self.atmospherePipelines = atmospherePipelines
        self.waterPipeline = waterPipeline
        self.skyDepth = skyDepth
        self.depth = depth
        self.markerDepth = markerDepth
        textureLoader = MTKTextureLoader(device: device)
        super.init()
        fixedCJObserver=NativeResourceStore.shared.observe {[weak self] _ in
            guard let self else{return}
            self.invalidatePedAtlasSourceIfChanged()
            self.loadNearby()
            _ = self.actorSelection.invalidateSource(self.fixedCJSourceIdentity())
            if self.fixedCJ?.invalidateIfSourceChanged()==true,self.needsFixedCJ{self.ensureFixedCJ()}
        }
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
        groundVehicle?.onKinematicStep = {[weak self] delta in
            guard let self,let at=self.legacyObjectClock.advance(delta:delta,now:ProcessInfo.processInfo.systemUptime)else{return}
            self.synchronizeLegacyObjectPhysics(at:at)
        }
        gameCamera.trace = { [weak self] origin,direction,distance in
            guard let self else{return nil}
            return self.cameraRay(from:origin,direction:direction,distance:distance,originalVehiclePolicy:self.driving)
        }
        gameCamera.unavailableDistance = { [weak self] origin,direction,distance in
            guard let self,let vehicle=self.groundVehicle else {return 0}
            return NativeWorldRay.coverage(from:origin,to:origin+direction*distance,interior:self.isInterior,
                loaded:vehicle.isCellLoaded)?.firstUnavailable
        }
        // SA-MP camera ownership is a native adapter, not the archived driven
        // vehicle callback. Preserve its previous solid-body collision policy.
        legacyFollowCamera.trace = {[weak self] origin,direction,distance in
            self?.cameraRay(from:origin,direction:direction,distance:distance,originalVehiclePolicy:false)
        }
        legacyFollowCamera.unavailableDistance=gameCamera.unavailableDistance
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
        return collisions["\(isInterior ? "i" : "c")\(y*16+x)"]
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
        if let name=pedModels[String(localSkin)],let actor=skeletalActors[name],let library=skeletalLibrary,let frame=footAnimationFrame {
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
    var hasNearbyFire: Bool { originalActorBurning || weaponEffects.fires.contains { simd_distance($0.position,camera)<40 } }
    private var originalActorBurning=false
    private(set) var originalCoughing=false
    var hasOriginalWorldFire:Bool{weaponEffects.burning(atFeet:camera)}
    var hasOriginalWorldGas:Bool{weaponEffects.gassed(atFeet:camera)}
    func setOriginalActorEffects(burning:Bool,coughing:Bool){
        originalActorBurning=burning
        let active=coughing && health>0 && !driving && !swimming && climb==nil
        guard originalCoughing != active else{return};originalCoughing=active
        prepareFootAnimation()
        if active{cancelWeaponInput();_=footAnimator?.act("ped/gas_cwr",loop:true)}else{footAnimator?.rest()}
    }
    func canParryOriginalHit(_ hit:NativeOriginalWorldVitals.Hit)->Bool{
        guard canNativeFootMeleeGuard,meleeGuardHeld,meleeBlockHeld,!weaponTriggerHeld,
              footAnimator?.firing != true,footAnimator?.busy != true,footAnimator?.stunned != true,
              footAnimator?.rolling != true,let point=hit.point else{return false}
        let target=SIMD3<Double>(SwiftRapierWorld.gtaToRapier(camera)),source=SIMD3(point.x,point.z,-point.y)
        return NativeFootLocomotion.supportKnockSide(velocity:target-source,heading:Double(actorHeading))==0
    }
    @discardableResult func repairOriginalVehicle()->Bool{
        guard driving,let damage=groundVehicle?.damageController else{return false}
        damage.state.fix();vehicleHealth=1000;activeVehicleDamage=damage.state.text();return true
    }
    @discardableResult func flipOriginalVehicle()->Bool{
        guard driving,let ground=groundVehicle,ground.active,ground.damageController?.state.wrecked != true,
              let collider=ground.chassisColliders.first,let body=ground.world.colliderInfo(collider)?.body,
              let state=ground.world.bodyState(body)else{return false}
        let forward=state.rotation.act(SIMD3<Float>(0,0,-1))
        let facing=hypot(forward.x,forward.z)>0.1 ? atan2(forward.x,-forward.z):heading
        let transform=NativeGroundVehicle.transform(position:SIMD3<Double>(state.position),rotation:simd_quatd(vector:SIMD4<Double>(state.rotation.vector)),origin:Double(activeModelOrigin))
        camera=SIMD3(transform.columns.3.x,transform.columns.3.y,transform.columns.3.z+1)
        ground.teleport(modelPosition:camera,heading:facing);heading=facing;actorHeading=facing
        vehiclePitch=0;vehicleFallbackRoll=0;drivingSpeed=0;verticalSpeed=0;gameCamera.beginVehicle();return true
    }
    func liftOriginalPlayer(_ amount:Double){
        guard amount.isFinite,amount>0,health>0 else{return}
        if driving{
            guard let ground=groundVehicle,ground.active,let collider=ground.chassisColliders.first,
                  let body=ground.world.colliderInfo(collider)?.body,let state=ground.world.bodyState(body)else{return}
            let position=state.position+SIMD3(0,Float(min(100,amount)),0),q=state.rotation
            let transform=NativeGroundVehicle.transform(position:SIMD3<Double>(position),rotation:simd_quatd(vector:SIMD4<Double>(q.vector)),origin:Double(activeModelOrigin))
            camera=SIMD3(transform.columns.3.x,transform.columns.3.y,transform.columns.3.z)
            ground.teleport(modelPosition:camera,heading:heading,bodyPose:.init(position:SIMD3<Double>(position),rotation:simd_quatd(vector:SIMD4<Double>(q.vector))))
            drivingSpeed=0;verticalSpeed=0
        }else{teleport(x:camera.x,y:camera.y,z:camera.z+Float(min(100,amount)),direction:actorHeading)}
    }
    func leaveVehicleForOriginalTeleport(){if driving{discardOwnedVehicle()}}
    /// Authoritative placement revokes ownership without a parked exit or offset.
    func revokeVehicleForServerPlacement(){discardOwnedVehicle()}
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
    var footWireAction:Int {(health>0 ? originalCoughing ? 31:climb?.part.rawValue ?? (personalFlight.state>0 ? 50+personalFlight.state-1:footAnimator?.reportedAction ?? 0):0) | (originalActorBurning ? 64:0)}
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
    /// A fresh independent-server Peer starts a fresh oxygen pool. Keep that
    /// lifecycle separate from health, locomotion and external server profiles.
    func setSelfhostBreathConnection(_ nonce: String?) {
        guard let nonce else { selfhostBreathConnection = nil; return }
        guard selfhostBreathConnection != nonce else { return }
        selfhostBreathConnection = nonce
        swimController.revive()
    }
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
        if hit.parried {
            if !driving,health>0 {footAnimator?.parry()}
            return
        }
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
    func resetDisplayClock() {
        renderClock.reset();riderPoseClock.reset(at:riderMonotonicNow())
        for (_,cached) in remoteFootAnimations { cached.1.resetDisplayClock() }
    }
    var hasNativeFootWeaponTiming:Bool {
        guard footAnimator != nil,let definition=footWeaponDefinitions[equippedWeapon],
              ["gun","stream","launch","throw"].contains(definition.use ?? ""),climb==nil,!driving,!swimming,!personalFlight.chuting else{return false}
        return !personalFlight.flying || definition.arm
    }
    private func combatEligibility(grounded:Bool?=nil)->NativeCombatEligibility.Context {
        let definition=footWeaponDefinitions[equippedWeapon]
        var context=NativeCombatEligibility.Context()
        context.alive=health>0
        context.blocked=driving || swimming || climb != nil || personalFlight.chuting || originalCoughing
        context.airborne = !(grounded ?? character?.state.grounded ?? (verticalSpeed==0))
        context.busy=footAnimator?.busy ?? false;context.stunned=footAnimator?.stunned ?? false
        context.rolling=footAnimator?.rolling ?? false;context.flying=personalFlight.flying
        context.arm=definition?.arm ?? false;context.requiresAim=definition?.requiresAim ?? false
        context.aimHeld=aiming;context.ready=weaponReady;context.reloading=weaponReloading
        return context
    }
    var canRequestFootWeaponFire:Bool {combatEligibility().canRequestFire}
    var supportsFootWeaponAim:Bool {footWeaponDefinitions[equippedWeapon]?.aims == true}
    var canMaintainFootAim:Bool {
        health>0 && supportsFootWeaponAim && !driving && !swimming && climb==nil && !personalFlight.chuting &&
            (!personalFlight.flying || footWeaponDefinitions[equippedWeapon]?.arm == true)
    }
    private func cancelFootAimForTask() {
        let wasAiming=aiming
        aiming=false
        if wasAiming {onFootAimCancelled?()}
    }
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
        if legacySpectating {
            // The server owns the observer's camera. Do not keep falling,
            // drowning or advancing a hidden local pedestrian in this mode.
            legacySpectatorAccumulator += Double(delta)
            while legacySpectatorAccumulator+1e-10>=1.0/60 {
                groundVehicle?.world.step();legacySpectatorAccumulator=max(0,legacySpectatorAccumulator-1.0/60)
            }
            return
        }
        if isPassenger {
            passengerAccumulator+=min(0.25,max(0,Double(delta)))
            while passengerAccumulator+1e-10>=1.0/60{groundVehicle?.world.step();passengerAccumulator=max(0,passengerAccumulator-1.0/60)}
            if let id=currentVehicleID,let frame=sharedVehicleFrame(id:id){
                passengerFrame=frame;camera=SIMD3(frame.transform.columns.3.x,frame.transform.columns.3.y,frame.transform.columns.3.z)
                heading=frame.vehicle.heading;actorHeading=heading;vehiclePitch=frame.vehicle.pitch;vehicleFallbackRoll=frame.vehicle.roll
                drivingSpeed=frame.speed;vehicleHealth=frame.vehicle.health;activeVehicleDamage=frame.vehicle.damage
            }
            dispatchOwnedVehicleExit();loadNearby();return
        }
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
                if let pose=pendingVehicleSnapshot?.physicalPose {
                    let transform=NativeGroundVehicle.transform(position:pose.position,rotation:pose.rotation,origin:Double(origin))
                    camera=SIMD3(transform.columns.3.x,transform.columns.3.y,transform.columns.3.z)
                }else{camera += NativeGroundVehicle.modelOffset(origin:origin-activeModelOrigin,heading:heading,pitch:vehiclePitch,roll:vehicleFallbackRoll)}
                activeModelOrigin = origin
                if groundVehicle.enter(model:activeVehicleModel,modelPosition:camera,heading:heading,pitch:vehiclePitch,roll:vehicleFallbackRoll,bodyPose:pendingVehicleSnapshot?.physicalPose){
                    if let snapshot=pendingVehicleSnapshot{groundVehicle.restoreWheelSpin(front:snapshot.frontSpin,rear:snapshot.rearSpin)}
                    pendingVehicleSnapshot=nil
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
        dispatchOwnedVehicleExit()
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
        } else if !driving && (verticalSpeed != 0 || (legacyGravity ?? 0)<0) {
            verticalSpeed -= (legacyGravity.map{$0*2500} ?? 9.8) * delta
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
        groundVehicle.synchronizeOtherVehicles(order.compactMap{poses[$0]},excluding:isPassenger ? nil:currentVehicleID,near:camera,
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
        let objects=legacyCollisionHandles.sorted(by:{$0.key<$1.key}).compactMap { id,handles -> NativeVehicleSupportScene.ObjectFrame? in
            guard let handle=handles.first,let motion=legacyCollisionWorld?.motion(entityID:handle.entityID)else{return nil}
            let q=motion.transform.rotation
            return .init(id:"object:\(id)",body:motion.bodyID,position:SIMD3<Double>(SwiftRapierWorld.gtaToRapier(motion.transform.position)),
                rotation:simd_quatd(ix:Double(q.imag.x),iy:Double(q.imag.z),iz:Double(-q.imag.y),r:Double(q.real)),
                velocity:SIMD3<Double>(SwiftRapierWorld.gtaToRapier(motion.linearVelocity)),spin:SIMD3<Double>(SwiftRapierWorld.gtaToRapier(motion.angularVelocity)))
        }
        supportScene.synchronize(groundVehicle.supportFrames(),drivers:drivers,objects:objects)
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
            cancelFootAimForTask()
            crouching = false;clearAction()
            footAirTime = 0;footAirFall = 0;footAirFell = false;footJumped = false;footLaunchRemaining = nil
        }
        guard swimController.on else { swimController.ashore(delta);return intended }
        if swimController.completeIfWaterMissing(delta:delta,depth:depth) {
            // Water-only pulses expire here. The succeeding foot task still
            // receives the current stick and its unspent sprint tap this tick.
            pendingDive = false;pendingSwimJump = false
            return intended
        }
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
        if result.hurt>0{onLocalDamage?(result.hurt,53)}
        // The outgoing swim task advances animation only when it owns this
        // tick. A nil result hands the same tick to foot/flight animation.
        if let animator = footAnimator {
            let cancelledReload=animator.reloading
            animator.arm(nil)
            if cancelledReload && !animator.reloading {onReloadTaskCancelled?()}
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
            cancelFootAimForTask()
            crouching=false;clearAction();footLaunchRemaining=nil
        }
        if personalFlight.lifts,footAnimator?.busy != true {personalFlight.takeOff(heading:-Double(actorHeading));crouching=false}
        if personalFlight.flying && footWeaponDefinitions[equippedWeapon]?.arm != true {
            cancelFootAimForTask()
        }
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
            let cancelledReload=personalFlight.flying && animator.reloading
            animator.arm(canAim ? definition:nil)
            if cancelledReload && !animator.reloading {onReloadTaskCancelled?()}
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
        let model = pedModels[String(localSkin)] ?? "bmori"
        guard footAnimator == nil || footAnimationModel != model else { return }
        let style = definitions.style(model:legacyPedStyles[model] ?? model,library:library)
        if let animator = footAnimator {
            animator.setModelStyle(style); footAnimationModel = model
            return
        }
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
                if damage>0,let onLocalDamage{onLocalDamage(damage,54);if health<=0{animator.die()}}
                else{
                    let nextHealth=NativeFallDamage.health(after:damage,current:health)
                    if nextHealth<health {
                        health=nextHealth;onLocalHealth?(health)
                        if health<=0 {animator.die()}
                    }
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
        cancelFootAimForTask()
        climbPhase=nil;pendingClimbPull=false;pendingClimbDrop=false;airGrabTicks=0
        let cancelledReload=animator.reloading
        cancelWeaponInput();crouching=false;manualAnimation=false;animator.resetMovementTask()
        if cancelledReload {onReloadTaskCancelled?()}
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

    private func cameraRay(from origin:SIMD3<Float>,direction:SIMD3<Float>,distance:Float,originalVehiclePolicy:Bool)->Float? {
        let groups: UInt32 = self.driving ? 0xffff0083 : 0xffff0001
        var excluded = self.driving ? self.groundVehicle?.chassisColliders ?? [] : Set<UInt64>()
        if self.isPassenger,let id=self.currentVehicleID{excluded.formUnion(self.groundVehicle?.otherVehicleColliders(id:id) ?? [])}
        let ownExcludedCount=excluded.count
        let dynamicOthers=originalVehiclePolicy ? self.groundVehicle?.cameraExcludedOtherColliders ?? []:[]
        excluded.formUnion(dynamicOthers)
        if let queries=self.character?.queries {excluded.formUnion([queries.walker,queries.probe])}
        let legacyExcluded=self.legacyCollisionWorld?.cameraExcludedColliderIDs ?? []
        excluded.formUnion(legacyExcluded)
        var exactHit:SwiftRapierWorld.Hit?
        let observing=self.passiveCameraTrace != nil
        let observer:((SwiftRapierWorld.Hit)->Void)?=observing ? {exactHit=$0}:nil
        let result=self.worldRay(from:origin,direction:direction,distance:distance,groups:groups,excluding:excluded,onHit:observer)
        if observing {
            func array(_ v:SIMD3<Float>)->[Float]{[v.x,v.y,v.z]}
            var record=NativePassiveCameraTrace.Ray(origin:array(origin),direction:array(direction),requestedDistance:distance,
                groups:groups,vehiclePolicyApplied:originalVehiclePolicy,result:"clear",excludedDynamicOtherCount:dynamicOthers.count,excludedLegacyCount:legacyExcluded.count,
                excludedOwnCount:ownExcludedCount,excludedDynamicOtherSample:Array(dynamicOthers.sorted().prefix(32)))
            switch result {
            case .hit(let hit):record.result="hit";record.resultDistance=hit.distance
            case .unavailable(let distance):record.result="unavailable";record.resultDistance=distance
            case .clear:break
            }
            if let hit=exactHit {
                record.collider=hit.collider;record.body=hit.body;record.nativeMaterial=hit.material
                record.point=array(SwiftRapierWorld.rapierToGTA(hit.point));record.normal=array(SwiftRapierWorld.rapierToGTA(hit.normal))
                let other=self.groundVehicle?.otherColliders.contains(hit.collider) ?? false
                record.originalOtherMember=other
                // The proven native-other owner is vehicles only. Its
                // material63 assignment is not original S-map membership.
                record.originalMaterialMember=other ? false:nil
                record.legacyObject=self.legacyCollisionWorld?.metadata(collider:hit.collider) != nil
                if let body=hit.body {
                    switch self.groundVehicle?.world.bodyKind(body) {
                    case .fixed?:record.bodyKind="fixed"
                    case .dynamic?:record.bodyKind="dynamic"
                    case .kinematicPosition?:record.bodyKind="kinematic-position"
                    case .kinematicVelocity?:record.bodyKind="kinematic-velocity"
                    case nil:record.bodyKind="unknown"
                    }
                }else{record.bodyKind="unparented"}
            }
            self.passiveCameraRay=record
        }
        switch result {
        case .hit(let hit):return hit.distance
        case .unavailable(let at):return at
        case .clear:return nil
        }
    }

    private func worldRay(from origin:SIMD3<Float>,direction:SIMD3<Float>,distance:Float,
                          groups:UInt32,excluding:Set<UInt64>=[],onHit:((SwiftRapierWorld.Hit)->Void)?=nil) -> NativeWorldRay.Result {
        guard let vehicle=groundVehicle else{return .unavailable(0)}
        let magnitude=simd_length(direction)
        guard magnitude.isFinite,magnitude>0.0001,distance.isFinite,distance>0 else{return .unavailable(0)}
        let unit=direction/magnitude
        if let coverage=NativeWorldRay.coverage(from:origin,to:origin+unit*distance,interior:isInterior,loaded:{_ in true}) {
            collisionRequests.request(coverage.cells,now:ProcessInfo.processInfo.systemUptime,visible:activeDetails)
            desiredPhysicsCells=collisionRequests.retained(now:ProcessInfo.processInfo.systemUptime,visible:activeDetails)
            for name in desiredPhysicsCells {loadCollision(name:name)}
        loadWorldSharpIfNeeded()
        }
        var excluded=excluding
        if let queries=character?.queries {excluded.formUnion([queries.walker,queries.probe])}
        return NativeWorldRay.query(from:origin,direction:unit,distance:distance,interior:isInterior,loaded:vehicle.isCellLoaded) { start,way,limit in
            vehicle.world.raycast(origin:SwiftRapierWorld.gtaToRapier(start),direction:SwiftRapierWorld.gtaToRapier(way),
                distance:limit,excludingColliders:excluded,groups:groups).map {
                    onHit?($0)
                    return .init(distance:$0.distance,normal:SwiftRapierWorld.rapierToGTA($0.normal))
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
    private func ownVehicleDrawContext(name:String,code:String)->VehicleDrawContext {
        var input=NativeVehicleRig.Input()
        input.work=groundVehicle?.workingRenderValue ?? 0
        input.steering = -(groundVehicle?.output?.steering ?? 0)
        input.rearSteering = -(groundVehicle?.output?.rearSteering ?? 0)
        let angles=ownVehicleWheelClocks
        input.frontSpin=angles.first ?? 0
        input.rearSpin=angles.count>1 ? angles[1]:0
        input.offsets=[Double](repeating:0,count:4)
        var wheelOffsets:[Int:Double]=[:]
        for wheel in nativeVehicleWheels {
            if input.offsets.indices.contains(wheel.index){input.offsets[wheel.index]=wheel.offset}
            if wheelOffsets[wheel.index]==nil{wheelOffsets[wheel.index]=wheel.offset}
        }
        input.drop=nativeBikeDrop.map(Double.init);input.lean=Double(nativeBikeLean);input.crank=Double(nativeBicycleCrank)
        input.rotor=Double(nativeRotorTurning);input.gearUp=nativeLandingGearUp;input.nozzle=Double(nativeAircraftNozzle ?? 5000)
        let damage=groundVehicle?.damageController?.state
        if let damage {
            input.looks=damage.looks;input.tyres=damage.wheels;input.brokenLights=damage.lights
            input.doorAngles=damage.doors.map(\.angle);input.doorAxes=damage.doors.map(\.axis)
            input.scorched=damage.wrecked;input.lights=vehicleLights && !damage.wrecked
        }else{input.lights=vehicleLights}
        input.braking=(groundVehicle?.output?.brake ?? 0)>0
        let own=OwnVehicleDrawSnapshot(input:input,doors:damage?.doors,wheelOffsets:wheelOffsets,wheelAngles:nativeVehicleWheelAngles,
            speed:drivingSpeed,steering:groundVehicle?.output?.steering ?? 0,rearSteering:groundVehicle?.output?.rearSteering ?? 0,
            fallbackSteering:steeringInput,wheelPhaseOwned:groundVehicle?.active == true || pendingVehicleSnapshot != nil)
        // The existing own fallback uses the base model matrix; the physical
        // transform, when available, already includes its roll and origin.
        let identity=Self.remoteDriverRenderKey(playerID:name,vehicleID:currentVehicleID)
        return .init(source:.own(own),token:"own:\(identity):\(name)",appearanceCode:code,
            roll:0,origin:0,exactTransform:nativeVehicleTransform,heldDoorID:currentVehicleID ?? "own")
    }
    private func remoteVehicleDrawContext(name:String,player:RemotePlayer)->VehicleDrawContext {
        .init(source:.remote(player),token:"remote:\(Self.remoteDriverRenderKey(playerID:player.id,vehicleID:player.vehicleID)):\(name)",
            appearanceCode:player.code,roll:player.roll,origin:vehicleModelOrigin(player.code),exactTransform:nil,heldDoorID:player.vehicleID)
    }
    private func parkedVehicleDrawContext(name:String,vehicle:RemoteVehicle)->VehicleDrawContext {
        let frame=groundVehicle?.otherVehicle(vehicle.id)
        let physical=frame.map{ParkedVehicleDrawSnapshot(work:Double($0.work),rotor:$0.rotor,gearUp:$0.gearUp,dynamic:$0.dynamic,
            frontSpin:$0.frontSpin,rearSpin:$0.rearSpin,offsets:$0.offsets)}
        let identity=Self.remoteDriverRenderKey(playerID:name,vehicleID:vehicle.id)
        return .init(source:.parked(vehicle,physical),token:"remote:\(identity):\(name)",appearanceCode:vehicle.code,
            roll:vehicle.roll,origin:vehicleModelOrigin(vehicle.code),exactTransform:frame?.transform,heldDoorID:vehicle.id)
    }
    private func carriageVehicleDrawContext(name:String,model:String,transform:simd_float4x4,identity:String?,own:Bool,index:Int)->VehicleDrawContext {
        let parent=Self.remoteDriverRenderKey(playerID:name,vehicleID:identity)
        let token="carriage:\(own ? "own":"remote"):\(parent):\(index):\(name)"
        // Preserve the existing carriage spin timing while isolating each
        // layout's identity and exact transform. This is not a train retune.
        return .init(source:.carriage(speed:drivingSpeed),token:token,appearanceCode:model,
            roll:0,origin:0,exactTransform:transform,heldDoorID:nil)
    }
    private static func vehicleDrawTransform(_ base:simd_float4x4,context:VehicleDrawContext?)->simd_float4x4 {
        guard let context else{return base}
        if let exact=context.exactTransform{return exact}
        if context.roll==0 && context.origin==0{return base}
        return base*Self.rotationY(context.roll)*Self.translation(SIMD3(0,0,context.origin))
    }
    private static func legacyVehicleWheel(index:Int,front:Bool,context:VehicleDrawContext?,time:Float)->(offset:Float,spin:Float,turn:Float) {
        guard let context,let own=context.own else{return (0,0,0)}
        if context.exactTransform != nil {
            let spin=own.wheelAngles.indices.contains(index) ? own.wheelAngles[index]:0
            return (Float(own.wheelOffsets[index] ?? 0),spin,Float(front ? own.steering:own.rearSteering))
        }
        let spin=own.wheelPhaseOwned && own.wheelAngles.indices.contains(index) ? own.wheelAngles[index]:time*own.speed/0.35
        return (0,spin,front && own.speed != 0 ? own.fallbackSteering*0.45:0)
    }
    /// The same frame is used by the shared vehicle and every attached rider.
    /// Passenger walking reports never become a second vehicle transform.
    private func sharedVehicleFrame(id:String)->SharedVehicleFrame? {
        if driving,!isPassenger,currentVehicleID==id,let vehicle=remoteVehicles.first(where:{$0.id==id}) {
            var value=vehicle;value.position=vehicleWirePosition;value.heading=heading;value.pitch=vehiclePitch;value.roll=vehicleRoll
            let matrix=nativeVehicleTransform ?? (Self.translation(camera)*Self.rotationZ(-heading)*Self.rotationX(vehiclePitch)*Self.rotationY(vehicleRoll))
            return .init(vehicle:value,transform:matrix,speed:drivingSpeed,velocity:currentWireVelocity,angularVelocity:currentWireAngularVelocity)
        }
        if let driver=remotePlayers.first(where:{$0.vehicleID==id}),
           let vehicle=RemoteVehicle(row:[id,driver.name,driver.code,driver.position.x,driver.position.y,driver.position.z,-driver.heading,driver.pitch,-driver.roll,driver.vehicleHealth,driver.vehicleDamage]) {
            let matrix=Self.translation(driver.position)*Self.rotationZ(-driver.heading)*Self.rotationX(driver.pitch)*Self.rotationY(driver.roll)*Self.translation(SIMD3(0,0,vehicleModelOrigin(driver.code)))
            return .init(vehicle:vehicle,transform:matrix,speed:driver.speed,velocity:driver.velocity,angularVelocity:driver.angularVelocity)
        }
        guard let source=remoteVehicles.first(where:{$0.id==id})else{return nil}
        let vehicle=predictedVehicle(source),matrix=groundVehicle?.otherVehicle(id)?.transform ??
            (Self.translation(vehicle.position)*Self.rotationZ(-vehicle.heading)*Self.rotationX(vehicle.pitch)*Self.rotationY(vehicle.roll)*Self.translation(SIMD3(0,0,vehicleModelOrigin(vehicle.code))))
        var velocity=SIMD3<Float>.zero,spin=SIMD3<Float>.zero
        if let ground=groundVehicle,let collider=ground.otherVehicleColliders(id:id).sorted().first,
           let body=ground.world.colliderInfo(collider)?.body,let state=ground.world.bodyState(body) {
            velocity=SwiftRapierWorld.rapierToGTA(state.linearVelocity)
            spin=SwiftRapierWorld.rapierToGTA(state.angularVelocity)
        }
        let forward=SIMD3(matrix.columns.1.x,matrix.columns.1.y,matrix.columns.1.z)
        return .init(vehicle:vehicle,transform:matrix,speed:simd_dot(velocity,forward),velocity:velocity,angularVelocity:spin)
    }
    func availablePassengerSeat(vehicle:RemoteVehicle)->Int? {
        let model=String(vehicle.code.split(separator:".").first ?? "")
        guard let definition=riderDefinitions?.models[model],definition.seats.count>1 else{return nil}
        let taken=Set(remotePlayers.filter{$0.ridingVehicleID==vehicle.id}.map(\.ridingSeat))
        return (1..<min(16,definition.seats.count)).first{!taken.contains($0)}
    }
    private static func sharedDoorOpen(_ part:Int?,damage:String)->Bool {
        guard let part,let state=NativeVehicleDamage.decode(damage),state.open.indices.contains(part)else{return false}
        return state.open[part]
    }
    @discardableResult func enterPassenger(_ source:RemoteVehicle,seat:Int,kind:String)->Bool {
        let model=String(source.code.split(separator:".").first ?? "")
        guard seat>0,let definition=riderDefinitions?.models[model],definition.seats.indices.contains(seat),definition.seats[seat].position != nil else{return false}
        guard !driving else{return false}
        pendingVehicleSnapshot=nil
        ownCameraVisibility.reset();personalFlight.stop();swimController.stop();swimming=false;underwater=false
        climb=nil;climbPhase=nil;pendingClimbPull=false;pendingClimbDrop=false;airGrabTicks=0
        footAnimator?.rest(cut:true);footAnimationFrame=nil;footLaunchRemaining=nil
        character?.setActive(false);characterActive=false;pendingNativeJump=0
        entryOrigin=camera;entryStarted=ProcessInfo.processInfo.systemUptime
        passengerSeat=seat;passengerFrame=nil;passengerAccumulator=0;currentVehicleID=source.id
        activeVehicleModel=model;activeModelOrigin=Float(definition.origin);vehicleKind=kind;driving=true
        ownRiderPlayback=nil;ownRiderCapture=nil;ownRiderPrevious=nil;ownRiderFeet=nil;pendingVehicleExit=nil;pendingExitPlacement=nil;vehicleExitSerial &+= 1
        ownRiderAnimation=nil;vehicleHorn=false;vehicleSiren=false;steeringInput=0
        if let frame=sharedVehicleFrame(id:source.id){passengerFrame=frame;camera=SIMD3(frame.transform.columns.3.x,frame.transform.columns.3.y,frame.transform.columns.3.z);heading=frame.vehicle.heading}
        loadNearby();return true
    }
    /// A server revocation/despawn is not a driver's park operation. Retain
    /// the last attached feet until the server's following foot correction.
    func revokePassenger(at point:SIMD3<Float>?=nil) {
        guard isPassenger else{return}
        let feet=point ?? passengerWirePosition
        discardOwnedVehicle();teleport(x:feet.x,y:feet.y,z:feet.z)
    }
    func enter(_ source: RemoteVehicle, kind: String) {
        passengerSeat=nil;passengerFrame=nil;passengerAccumulator=0
        let snapshot=groundVehicle?.takeOtherVehicle(source.id)
        pendingVehicleSnapshot=snapshot
        let vehicle=applying(snapshot,to:source)
        ownCameraVisibility.reset()
        climb=nil;climbPhase=nil;pendingClimbPull=false;pendingClimbDrop=false;airGrabTicks=0
        personalFlight.stop()
        swimController.stop();swimming = false;underwater = false
        footAnimator?.rest(cut:true);footAnimationFrame = nil;footLaunchRemaining = nil
        ownRiderAnimation = nil;ownRiderPlayback=nil;ownRiderCapture=nil;ownRiderPrevious=nil;ownRiderFeet=nil;pendingVehicleExit=nil;pendingExitPlacement=nil;vehicleExitSerial &+= 1
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
        ownedVehicleAppearance=(vehicle.id,vehicle.code)
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
        guard driving,pendingVehicleExit==nil,pendingExitPlacement==nil,let playback=ownRiderPlayback,playback.inside else{return pendingVehicleExit != nil || pendingExitPlacement != nil}
        let serial=vehicleExitSerial
        pendingVehicleExit = { [weak self,weak playback] in
            guard let self,let playback,self.vehicleExitSerial==serial,self.driving,self.ownRiderPlayback === playback else{return}
            onReady()
        }
        ownRiderFeet=nil
        let seats=riderDefinitions?.models[activeVehicleModel]?.seats
        let part=seats.flatMap{$0.indices.contains(passengerSeat ?? 0) ? $0[passengerSeat ?? 0].door:nil}
        let leaveOpen=isPassenger ? Self.sharedDoorOpen(part,damage:passengerFrame?.vehicle.damage ?? "") : part.map{groundVehicle?.damageController?.state.isOpen($0) ?? false} ?? false
        playback.leave(at:riderMonotonicNow(),side:ownRiderSide,leaveOpen:leaveOpen)
        return true
    }

    /// Preserve identity across an asynchronous geometry load. An old exit
    /// cannot release a replacement/re-entered vehicle, even with the same ID.
    func deferVehicleExit(_ retry:@escaping()->Void) {
        let serial=vehicleExitSerial
        pendingExitPlacement = { [weak self] in
            guard let self,self.driving,self.vehicleExitSerial==serial else{return}
            retry()
        }
    }
    private func resolveVehicleExit(wanted:SIMD3<Float>?)->NativeVehicleExitPlanner.Placement {
        guard let groundVehicle,(groundVehicle.active || isPassenger),let character else{return .ready(wanted)}
        let seats=riderDefinitions?.models[activeVehicleModel]?.seats
        let seat=seats.flatMap{$0.indices.contains(passengerSeat ?? 0) ? $0[passengerSeat ?? 0].position:nil}.map{SIMD3<Double>($0)}
        func ray(_ p:SIMD3<Double>,_ way:SIMD3<Double>,_ distance:Double)throws->Double? {
            switch worldRay(from:SwiftRapierWorld.rapierToGTA(SIMD3<Float>(p)),
                            direction:SwiftRapierWorld.rapierToGTA(SIMD3<Float>(way)),distance:Float(distance),groups:0xffff0001) {
            case .clear:return nil
            case .hit(let hit):return Double(hit.distance)
            case .unavailable:throw NativeVehicleExitPlanner.QueryError.unavailable
            }
        }
        do {
            func fits(_ p:SIMD3<Double>,_ widening:Double,_ body:UInt64)throws->Bool {
                let radius=0.35+widening
                for x in [-radius,radius]{for z in [-radius,radius]{_=try ray(p+SIMD3(x,0,z),SIMD3(0,1,0),0.001)}}
                return character.motor.fits(p,widening:widening,excludingBody:body)
            }
            let feet:SIMD3<Float>?
            if isPassenger,let id=currentVehicleID {
                feet=try groundVehicle.passengerExitPosition(id:id,model:activeVehicleModel,wanted:wanted,seat:seat,side:ownRiderSide,below:{try ray($0,SIMD3(0,-1,0),$1)},along:ray,fits:fits)
            }else{feet=try groundVehicle.exitPosition(wanted:wanted,seat:seat,side:ownRiderSide,
                below:{try ray($0,SIMD3(0,-1,0),$1)},along:ray,
                fits:{p,widening,body in
                    // A capsule can cross a cell boundary even when its centre
                    // remains in a loaded cell. Request all four corners.
                    let radius=0.35+widening
                    for x in [-radius,radius] {for z in [-radius,radius] {
                        _ = try ray(p+SIMD3(x,0,z),SIMD3(0,1,0),0.001)
                    }}
                    return character.motor.fits(p,widening:widening,excludingBody:body)
                })}
            guard let feet else{return .unavailable}
            return .ready(feet)
        }catch{return .unavailable}
    }

    private func dispatchOwnedVehicleExit() {
        guard driving else{return}
        if groundVehicle?.damageController?.state.wrecked == true {
            onVehicleWrecked?();return
        }
        if groundVehicle?.lostInWater == true {
            onVehicleLostInWater?();return
        }
        if let retry=pendingExitPlacement {
            pendingExitPlacement=nil;DispatchQueue.main.async(execute:retry);return
        }
        if health>0,ownRiderPlayback?.inside != false,(vehicleKind=="bike" || vehicleKind=="bicycle"),
           let event=groundVehicle?.takeBikeEjection(),let onBikeEjection {onBikeEjection(event)}
    }

    @discardableResult
    func exitVehicle(ejection:NativeBikeEjection.Event?=nil,wrecked:Bool=false,water:Bool=false)->Bool {
        guard driving else{return true}
        let wrecked=wrecked || groundVehicle?.damageController?.state.wrecked == true
        let water=water || groundVehicle?.lostInWater == true
        let forced=ejection != nil || wrecked || water
        let exactFeet=ownRiderPlayback?.state == .stood ? ownRiderFeet:nil
        let wanted:SIMD3<Float>? = forced ? { () -> SIMD3<Float> in
            if let transform=groundVehicle?.modelTransform,
               let beside=ownRiderPlayback?.beside(side:ownRiderSide,model:transform){return beside}
            return ownRiderFeet?.position ?? camera
        }():exactFeet?.position
        let placedFeet:SIMD3<Float>?
        switch resolveVehicleExit(wanted:wanted) {
        case .unavailable:return false
        case .ready(let feet):placedFeet=feet
        }
        let forcedFeet=forced ? placedFeet:nil
        pendingVehicleExit=nil;pendingExitPlacement=nil;vehicleExitSerial &+= 1
        vehicleCoupling?.setOwnedVehicle(nil)
        ownCameraVisibility.reset()
        let floor = collision?.height(x: camera.x, y: camera.y,
                                      near: camera.z, maxDrop: 1000)
        let falling = floor.map { camera.z > $0 + 3 } ?? false
        if !isPassenger,let id=currentVehicleID,groundVehicle?.active == true {
            let code=remoteVehicles.first{$0.id==id}?.code ?? "\(activeVehicleModel).6.1.0."
            let work=groundVehicle?.workingValue ?? remoteVehicles.first{$0.id==id}?.work ?? 0
            activeVehicleDamage=vehicleDamage
            groundVehicle?.parkCurrentVehicle(id:id,code:code,health:vehicleHealth,damage:activeVehicleDamage,work:work)
        } else if !isPassenger{groundVehicle?.exit()}
        passengerSeat=nil;passengerFrame=nil;passengerAccumulator=0
        driving = false
        currentVehicleID = nil
        drivingSpeed = 0
        flightVerticalSpeed = 0
        vehiclePitch = 0
        vehicleFallbackRoll = 0
        activeModelOrigin = 0
        pendingVehicleSnapshot=nil
        climb=nil;climbPhase=nil;pendingClimbPull=false;pendingClimbDrop=false;airGrabTicks=0
        activeVehicleModel = ""
        activeHandling = nil
        vehicleKind = "car"
        if let placedFeet {
            camera=placedFeet
            if let exactFeet {heading=exactFeet.heading;actorHeading=exactFeet.heading}
            else {actorHeading=heading}
            verticalSpeed=0
            character?.reset(feet:camera,active:true,grounded:false);characterActive=true
            if !forced {footAnimator?.resetMovementTask()}
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
        if let forcedFeet {
            camera=forcedFeet;verticalSpeed=0
            character?.reset(feet:camera,active:true,grounded:false);characterActive=true
            prepareFootAnimation();cancelGameplayInput();personalFlight.stop()
            crouching=false
            if wrecked {
                if health>0 {
                    footDeathKind="koFront";pendingFootHit=nil;health=0
                    if let onLocalFatal{onLocalFatal(51)}else{onLocalHealth?(0)}
                    footAnimator?.die("koFront")
                } else if footAnimator?.dead != true {footAnimator?.die(footDeathKind ?? "koFront")}
                return true
            }
            if water {footAnimator?.resetMovementTask();return true}
            guard let ejection else{return true}
            footLocomotion.setKnockMomentum(ejection.velocity)
            let damage=Int(min(200,max(0,ceil(ejection.force*0.05))))
            if damage>0 {
                if let onLocalDamage{onLocalDamage(min(200,max(0,ejection.force*0.05)),0)}
                else if let onLocalImpact {onLocalImpact(damage)}
                else {health=max(0,health-damage);onLocalHealth?(health)}
            }
            if health>0 {
                let side=NativeFootLocomotion.supportKnockSide(velocity:ejection.velocity,heading:Double(actorHeading))
                _ = footAnimator?.knock(["koSkidBack","koSpinR","koSkidFront","koSpinL"][side])
            } else {footAnimator?.die("koFront")}
        }
        return true
    }

    /// Despawning/losing ownership must not manufacture a parked body or play
    /// a queued exit after the old vehicle has already ceased to exist.
    private func discardOwnedVehicle() {
        vehicleCoupling?.setOwnedVehicle(nil)
        groundVehicle?.exit()
        passengerSeat=nil;passengerFrame=nil;passengerAccumulator=0
        driving=false;currentVehicleID=nil;drivingSpeed=0;flightVerticalSpeed=0
        vehiclePitch=0;vehicleFallbackRoll=0;activeModelOrigin=0;pendingVehicleSnapshot=nil
        activeVehicleModel="";activeHandling=nil;vehicleKind="car"
        pendingVehicleExit=nil;pendingExitPlacement=nil;vehicleExitSerial &+= 1
        ownRiderPlayback=nil;ownRiderPrevious=nil;ownRiderCapture=nil;ownRiderFeet=nil
        ownRiderAnimation=nil;vehicleHorn=false;vehicleSiren=false;steeringInput=0
        vehicleWorkingControl=0;vehicleHop=false
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
        lastRiderDraw=0;riderPoseClock.reset();remoteServerTimeOffsetMilliseconds=nil
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
        pendingVehicleSnapshot=nil
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
        refreshWorldSharpSource()
        // The far mesh is divided into sixteen 4×4 blocks. Detailed cells are
        // 375 m squares with a 16-column grid and origin (-3000, -3000).
        let anchor=scenePosition
        let gx = max(0, min(15, Int(floor((anchor.x + 3000) / 375))))
        let gy = max(0, min(15, Int(floor((anchor.y + 3000) / 375))))
        let detail = gy * 16 + gx
        let indoors = isInterior
        let prefix = indoors ? "i" : "c"
        activeDetail = "\(prefix)\(detail)"
        var detailNames: Set<String> = []
        // Preload and draw the adjacent cells before crossing their edges.
        // A late collision response must not leave the player without a floor.
        for dx in [Float(-90), 0, 90] { for dy in [Float(-90), 0, 90] {
            let x = max(0, min(15, Int(floor((anchor.x + 3000 + dx) / 375))))
            let y = max(0, min(15, Int(floor((anchor.y + 3000 + dy) / 375))))
            let number = y * 16 + x
            if !indoors || insideCells.contains(number) { detailNames.insert("\(prefix)\(number)") }
        } }
        activeDetails = detailNames
        if collisionScene != indoors {collisionScene=indoors;collisionRequests.reset()}
        var physicalNames=detailNames
        if legacyCameraSample?.active == true && !legacySpectating {
            // A remote scripted camera must not unload the floor beneath a
            // still-live local actor or vehicle.
            for dx in [Float(-90),0,90]{for dy in [Float(-90),0,90]{
                let x=max(0,min(15,Int(floor((camera.x+3000+dx)/375))))
                let y=max(0,min(15,Int(floor((camera.y+3000+dy)/375))))
                let number=y*16+x
                if !indoors || insideCells.contains(number){physicalNames.insert("\(prefix)\(number)")}
            }}
        }
        desiredPhysicsCells=collisionRequests.retained(now:ProcessInfo.processInfo.systemUptime,visible:physicalNames)
        // The camera sits behind the player; draw the adjacent 1.5 km blocks
        // as well so a block edge never cuts across the horizon.
        var far: Set<String> = []
        for dx in [Float(-750), 0, 750] {
            for dy in [Float(-750), 0, 750] {
                let tx = max(0, min(3, Int(floor((anchor.x + 3000 + dx) / 1500))))
                let ty = max(0, min(3, Int(floor((anchor.y + 3000 + dy) / 1500))))
                far.insert("t\(ty * 4 + tx)")
            }
        }
        if indoors { far = [] }
        activeFar = far
        meshes = meshes.filter { detailNames.contains($0.key) || far.contains($0.key) }
        worldSharpBase=worldSharpBase.filter{detailNames.contains($0.key)}
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
        NativeResourceTransport.dataTask(with:server.path("game/world/\(name).col.bin")) { [weak self] data,response,_ in
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
        let source=fixedCJSourceIdentity()
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
        NativeResourceTransport.dataTask(with: binURL) { data, response, error in
            lock.lock()
            if let response = response as? HTTPURLResponse, response.statusCode == 200 { bin = data }
            else { fetchError = error ?? NSError(domain: "World", code: (response as? HTTPURLResponse)?.statusCode ?? -1) }
            lock.unlock()
            group.leave()
        }.resume()
        group.enter()
        NativeResourceTransport.dataTask(with: imageURL) { data, response, error in
            lock.lock()
            if let response = response as? HTTPURLResponse, response.statusCode == 200 { png = data }
            else { fetchError = error ?? NSError(domain: "World", code: (response as? HTTPURLResponse)?.statusCode ?? -1) }
            lock.unlock()
            group.leave()
        }.resume()
        group.notify(queue: .main) { [weak self] in
            guard let self,self.fixedCJSourceIdentity()==source else { return }
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
                if !name.hasPrefix("t") {
                    var low=SIMD3<Float>(repeating:.greatestFiniteMagnitude),high = -low
                    for vertex in world.vertices {
                        let p=SIMD3(vertex.position.x,vertex.position.y,vertex.position.z)
                        low=simd_min(low,p);high=simd_max(high,p)
                    }
                    self.worldSharpBase[name]=WorldSharpBase(layers:world.layers,mapping:world.sharpLayers,source:source,
                        indices:world.indices.count,center:low*0.5+high*0.5)
                    self.loadWorldSharpIfNeeded()
                }
                self.onStatus?("CITY READY: \(name.uppercased())")
            } catch {
                self.retryAfter[name] = Date().addingTimeInterval(5)
                self.onStatus?("CITY DATA ERROR: \(error.localizedDescription)")
            }
        }
    }

    /// All state here belongs to the renderer's main-thread scene. Only the
    /// bounded decoder and GPU upload run off-main; no stale result may publish.
    private func refreshWorldSharpSource() {
        let source=fixedCJSourceIdentity()
        if worldSharpSource != source {
            worldSharpIndexTask?.cancel();worldSharpIndexTask=nil
            worldSharpTicket?.cancel();worldSharpTicket=nil;worldSharpGPU=nil;worldSharpName=nil
            worldSharpManifest=nil;worldSharpBase.removeAll();worldSharpRetry.removeAll()
            worldSharpIndexReady=false;worldSharpIndexRetry = .distantPast
            if worldSharpSource != nil{meshes.removeAll();loading.removeAll();retryAfter.removeAll()}
            worldSharpSource=source
        }
        guard !worldSharpIndexReady,worldSharpIndexTask==nil,Date()>=worldSharpIndexRetry,let server else{return}
        let task=NativeResourceTransport.boundedDataTask(with:server.path("game/world/index.json"),maximumBytes:2*1024*1024){[weak self] data,response,_ in
            guard let data,(response as?HTTPURLResponse)?.statusCode==200,
                  let document=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let rows=document["water"] as? [[NSNumber]] else {
                DispatchQueue.main.async {
                    guard let self,self.worldSharpSource==source,self.fixedCJSourceIdentity()==source else{return}
                    self.worldSharpIndexTask=nil;self.worldSharpIndexRetry=Date().addingTimeInterval(5)
                };return
            }
            let water=NativeWorldWater(rows:rows.map{$0.map(\.floatValue)})
            let cells=(document["inside"] as? [String:Any])?["cells"] as? [[String:Any]] ?? []
            let inside=Set(cells.compactMap{$0["cell"] as? Int})
            let sharp=try? NativeWorldSharpManifest(data:data)
            DispatchQueue.main.async {
                guard let self,self.worldSharpSource==source,self.fixedCJSourceIdentity()==source else{return}
                self.worldSharpIndexTask=nil;self.worldSharpIndexReady=true;self.worldSharpManifest=sharp
                self.worldWater=water;self.waterMesh=self.makeWater(water);self.insideCells=inside
                self.loadNearby()
            }
        }
        worldSharpIndexTask=task;task.resume()
    }
    private func loadWorldSharpIfNeeded() {
        let name=activeDetail,source=fixedCJSourceIdentity()
        if worldSharpName != name {
            worldSharpTicket?.cancel();worldSharpTicket=nil;worldSharpGPU=nil;worldSharpName=name
        }
        guard worldSharpPipeline != nil,worldSharpSource==source,worldSharpGPU==nil,worldSharpTicket==nil,
              Date()>=(worldSharpRetry[name] ?? .distantPast),let server,
              let entry=worldSharpManifest?.entries[name],entry.sharpLayers>0,
              let base=worldSharpBase[name],base.source==source,base.layers==entry.layers,
              let layout=try? NativeWorldSharpLayout(baseLayers:base.layers,mapping:base.mapping,
                sharpLayers:entry.sharpLayers,width:2048,height:((entry.sharpLayers+7)/8)*256) else{return}
        let ticket=NativeWorldSharpTicket();worldSharpTicket=ticket
        worldSharpLoader.load(url:server.path("game/world/\(name).hd.png"),layout:layout,device:device,queue:queue,ticket:ticket){[weak self] result in
            guard let self,!ticket.isCancelled,self.worldSharpTicket === ticket,self.worldSharpName==name,
                  self.activeDetail==name,self.worldSharpSource==source,self.fixedCJSourceIdentity()==source else{return}
            self.worldSharpTicket=nil
            switch result {
            case .success(let textures):self.worldSharpGPU=textures
            case .failure:self.worldSharpRetry[name]=Date().addingTimeInterval(30)
            }
        }
    }

    var server: ServerAddress? {didSet{
        if oldValue != server {invalidatePedAtlasSourceIfChanged();actorSelection.cancel();fixedCJ?.reset();fixedCJ=nil;if needsFixedCJ{ensureFixedCJ()}}
    }}

    deinit {worldSharpIndexTask?.cancel();worldSharpTicket?.cancel();pedAtlasLoader.cancelAll();if let fixedCJObserver{NativeResourceStore.shared.removeObserver(fixedCJObserver)}}
    private var needsFixedCJ:Bool {
        localSkin==0 || pendingLocalSkin==0 || pendingLegacySkin==0 || remotePlayers.contains(where:{$0.skin==0})
    }
    private func fixedCJSourceIdentity()->String {
        let binding=NativeResourceStore.shared.runtimeBinding
        return [server?.display ?? "",binding.generation.uuidString,binding.mode.rawValue,
            binding.contentID ?? "",binding.developmentOrigin ?? "",binding.playable ? "ready":"unverified"].joined(separator:"|")
    }
    private func ensureFixedCJ(force:Bool=false) {
        guard let server else{return}
        if fixedCJ==nil {
            do {
                let owner=try NativeCJRuntimeModel(assetBaseURL:server.url,
                    sourceIdentity:{[weak self]in self?.fixedCJSourceIdentity() ?? ""},
                    accessProvider:{[weak self]in self?.legacyStockAccess()},upload:{[weak self] plan in
                        guard let self,let library=self.device.makeDefaultLibrary() else{throw NativeRenderWarePedModel.Failure.gpu("player shader library missing")}
                        let pipelines=try NativeRenderWarePedModel.Pipelines(device:self.device,library:library,
                            color:self.view.colorPixelFormat,depth:self.view.depthStencilPixelFormat)
                        return .init(uploaded:try NativeRenderWarePedModel.Uploaded(plan:plan,device:self.device),pipelines:pipelines)
                    })
                owner.onInvalidated={[weak self]in
                    guard let self else{return}
                    if self.pedModels["0"]=="null"{self.pedModels.removeValue(forKey:"0")}
                    self.skeletalActors.removeValue(forKey:"null")
                    self.ownRiderCapture=nil;self.ownRiderPrevious=nil
                    self.remoteRiderCapture.removeAll();self.remoteRiderPrevious.removeAll()
                }
                owner.onReady={[weak self,weak owner] ready in
                    guard let self,let owner,self.fixedCJ === owner,owner.isReady,
                          ready.sourceIdentity==self.fixedCJSourceIdentity() else{return}
                    guard self.pedModels["0"]==nil || self.pedModels["0"]=="null" else {
                        if let request=self.pendingActorSelection,request.skin==0 {
                            _=self.actorSelection.unavailable(request,sourceIdentity:self.fixedCJSourceIdentity(),message:"FIXED NORMAL CJ CONFLICTS WITH THE EXISTING SKIN0 CATALOGUE")
                        }
                        self.onStatus?("FIXED NORMAL CJ CONFLICTS WITH THE EXISTING SKIN0 CATALOGUE");return
                    }
                    // All maps become visible together, after the final GPU/
                    // source fence. `null` preserves the real PLAYER1 gait.
                    self.pedModels["0"]="null";self.skeletalActors["null"]=ready.gpu.uploaded.actor
                    self.ownRiderCapture=nil;self.ownRiderPrevious=nil;self.remoteRiderCapture.removeAll();self.remoteRiderPrevious.removeAll()
                    self.resumeActorSelection()
                    if self.localSkin==0{self.footAnimationModel="";self.prepareFootAnimation()}
                    self.onStatus?("FIXED NORMAL CJ READY — VEST / DENIM PROFILE")
                }
                owner.onUnavailable={[weak self]error in
                    guard let self else{return}
                    let message="FIXED NORMAL CJ PROFILE UNAVAILABLE: \(error)"
                    if let request=self.pendingActorSelection,request.skin==0 {
                        _=self.actorSelection.unavailable(request,sourceIdentity:self.fixedCJSourceIdentity(),message:message)
                    }
                    self.onStatus?(message)
                }
                fixedCJ=owner
            }catch{
                let message="FIXED NORMAL CJ PROFILE UNAVAILABLE: \(error)"
                if let request=pendingActorSelection,request.skin==0 {
                    _=actorSelection.unavailable(request,sourceIdentity:fixedCJSourceIdentity(),message:message)
                }
                onStatus?(message);return
            }
        }
        _=fixedCJ?.ensure(force:force)
    }

    func loadModelIndex() {
        loadFlightAssets();loadParticleEffects()
        guard let server else { return }
        let modelSource=fixedCJSourceIdentity()
        loadLegacyStockCatalogs()
        NativeResourceTransport.dataTask(with:server.path("game/native/weapons.json")) { [weak self] data,response,_ in
            guard (response as? HTTPURLResponse)?.statusCode==200,let data,
                  let catalog=try? NativeWeaponMuzzle.Catalog(data:data) else{return}
            DispatchQueue.main.async {self?.weaponMuzzleCatalog=catalog}
        }.resume()
        NativeResourceTransport.dataTask(with:server.path("game/native/riders.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode == 200,
                  let definitions = try? JSONDecoder().decode(NativeRiderDefinitions.self,from:data) else { return }
            DispatchQueue.main.async { self?.riderDefinitions = definitions }
        }.resume()
        NativeResourceTransport.dataTask(with:server.path("game/world/peds.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode == 200,
                  let definitions = try? NativeFootAnimationDefinitions(data:data) else { return }
            DispatchQueue.main.async { self?.footDefinitions = definitions;self?.prepareFootAnimation() }
        }.resume()
        NativeResourceTransport.dataTask(with:server.path("game/native/foot-animation.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode == 200,
                  let definitions = try? NativeFootWeaponAnimation.load(data:data) else { return }
            DispatchQueue.main.async { self?.footWeaponDefinitions = definitions }
        }.resume()
        NativeResourceTransport.dataTask(with:server.path("game/native/melee.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode==200,
                  let definitions=try? NativeMeleeDefinitions(data:data) else{return}
            DispatchQueue.main.async {self?.meleeDefinitions=definitions}
        }.resume()
        NativeResourceTransport.dataTask(with: server.path("game/native/seating.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode == 200,
                  let seating = try? JSONDecoder().decode(NativeVehicleSeating.self,from:data) else { return }
            DispatchQueue.main.async { self?.seating = seating }
        }.resume()
        environment = NativeWorldEnvironment()
        environment?.load(server: server)
        gameCamera.load(server: server) { [weak self] in
            guard let self else { return };self.gameCamera.setDirection(heading: self.heading,pitch: self.cameraPitch)
        }
        legacyFollowCamera.load(server:server)
        atmosphere.load(server: server)
        regionalWeather.load(server: server)
        weatherParticles.load(server: server)
        waterWaves.load(server: server) { [weak self] in
            guard let self,let water = self.worldWater else { return }
            self.waterMesh = self.makeWater(water); self.nearWaterOrigin = nil
        }
        NativeResourceTransport.dataTask(with: server.path("game/native/effects/waterclear256.png")) { [weak self] data,response,_ in
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
            NativeResourceTransport.dataTask(with: server.path("game/native/effects/\(name)")) { data,response,_ in
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
        NativeResourceTransport.dataTask(with: server.path("game/native/models/animations.clips.bin")) { [weak self] data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let library = NativeSkeletalAnimationLibrary(data: data)
            DispatchQueue.main.async { self?.skeletalLibrary = library;self?.prepareFootAnimation() }
        }.resume()
        NativeResourceTransport.dataTask(with: server.path("game/native/models/pedestrians.json")) { [weak self] data, _, _ in
            guard let data, let document = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return }
            let anchors = document.mapValues { $0.compactMapValues { ($0 as? [NSNumber])?.map(\.floatValue) } }
            DispatchQueue.main.async { self?.pedestrianAnchors = anchors }
        }.resume()
        refreshWorldSharpSource()
        NativeResourceTransport.dataTask(with: server.path("game/native/models/index.json")) { [weak self] data, _, _ in
            guard let self, let data,
                  let index = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else { return }
            DispatchQueue.main.async {
                guard self.fixedCJSourceIdentity()==modelSource else{return}
                self.vehicleModels = index["vehicles"] ?? [:]
                self.pedModels = index["peds"] ?? [:]
                self.weaponModels = index["weapons"] ?? [:]
                self.bindPedAtlasFamilies(index["pedAtlasV1"] ?? [:],v2:index["pedAtlasV2"] ?? [:],source:modelSource)
                if self.fixedCJ?.isReady==true,self.pedModels["0"]==nil{self.pedModels["0"]="null"}
                for key in self.legacyModelDefinitions.keys where (20001...30000).contains(key){self.pedModels[String(key)]="samp-dl-\(key)"}
                self.resumeActorSelection()
                self.loadActor(self.pedModels[String(self.localSkin)] ?? "bmori")
                self.loadActor("colt45")
            }
        }.resume()
        NativeResourceTransport.dataTask(with: server.path("game/native/samp-skins.json")) { [weak self] data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data else { return }
            DispatchQueue.main.async {
                guard let self,self.fixedCJSourceIdentity()==modelSource else{return}
                _=self.loadLegacySkinCatalog(data)
            }
        }.resume()
        NativeResourceTransport.dataTask(with: server.path("game/native/handling.json")) { [weak self] data, _, _ in
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
        NativeResourceTransport.dataTask(with: server.path("game/native/vehicles.physics.json")) { [weak self] data,response,_ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let cameraDefinitions = (try? JSONDecoder().decode(CameraVehicleDocument.self,from: data))?.models ?? [:]
            let suspensionRows = ((try? JSONSerialization.jsonObject(with:data)) as? [String:Any])?["models"] as? [String:[String:Any]] ?? [:]
            var suspension = [Int:NativeRemoteSuspension.Configuration]()
            if suspensionRows.count<=1024 {for(key,row)in suspensionRows {
                if let value=NativeRemoteSuspension.Configuration(row),String(value.model)==key{suspension[value.model]=value}
            }}
            DispatchQueue.main.async {
                guard let self else{return}
                self.vehicleCoupling?.reset(connection:self.couplingConnection)
                self.groundVehicle?.loadDefinitions(data);self.cameraVehicleDefinitions = cameraDefinitions
                self.remoteSuspensionConfigurations = suspension
                self.supportScene?.clear()
                if let snapshot=self.couplingSnapshot {self.applyVehicleCouplings(snapshot.links,revision:snapshot.revision,connection:snapshot.connection)}
                self.loadVehicleCouplingDefinitions()
                self.loadVehicleTreads()
            }
        }.resume()
        NativeResourceTransport.dataTask(with:server.path("game/native/trains.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode==200 else{return}
            DispatchQueue.main.async {self?.groundVehicle?.loadTracks(data)}
        }.resume()
    }

    private func loadVehicleCouplingDefinitions() {
        guard let server else{return}
        NativeResourceTransport.dataTask(with:server.path("game/native/vehicle-coupling.json")) { [weak self] data,response,_ in
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
        NativeResourceTransport.dataTask(with:server.path("game/native/vehicle-treads.json")) { [weak self] data,response,_ in
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
        invalidatePedAtlasSourceIfChanged()
        if name == "null" {
            if let ready=fixedCJ?.ready{skeletalActors[name]=ready.gpu.uploaded.actor}else{ensureFixedCJ()}
            return
        }
        if let custom=legacyPedModels[name]{skeletalActors[name]=custom.actor;return}
        let isPed=pedModels.values.contains(name),isVehicle=vehicleModels.values.contains(name)
        if isPed,let family=pedAtlasFamilies[name] {pedAtlasDemand.insert(name);loadPedAtlasActor(name,family:family);return}
        let complete=actorMeshes[name] != nil && (!isPed || skeletalActors[name] != nil) &&
            (!isVehicle || (vehicleRigs[name] != nil && vehicleRigMeshes[name] != nil))
        guard !name.isEmpty,!complete,!actorLoading.contains(name),
              Date()>=(actorRetryAfter[name] ?? .distantPast),
              let server else { return }
        actorLoading.insert(name)
        let actorSource=fixedCJSourceIdentity()
        let group = DispatchGroup()
        let lock = NSLock()
        var binary: Data?
        var image: Data?
        var animation: Data?
        var skeleton: Data?
        var attachment: Data?
        var parts: Data?
        var rigBinary:Data?,rigImage:Data?,rigMetadata:Data?
        if isVehicle {
            for suffix in ["bin","png","json"] {
                group.enter()
                // Rig hierarchy export can change draw traversal, indices and
                // texture layers together. Never combine a fresh hierarchy
                // with an older cached binary/atlas from the same URL.
                let request=URLRequest(url:server.path("game/native/models/\(name).rig.\(suffix)"),cachePolicy:.reloadIgnoringLocalCacheData)
                NativeResourceTransport.dataTask(with:request) { data,response,_ in
                    lock.lock()
                    if (response as? HTTPURLResponse)?.statusCode==200 {
                        if suffix=="bin" {rigBinary=data} else if suffix=="png" {rigImage=data} else {rigMetadata=data}
                    }
                    lock.unlock();group.leave()
                }.resume()
            }
        }
        group.enter()
        NativeResourceTransport.dataTask(with: server.path("game/native/models/\(name).parts.json")) { data, response, _ in
            lock.lock()
            if (response as? HTTPURLResponse)?.statusCode == 200 { parts = data }
            lock.unlock()
            group.leave()
        }.resume()
        group.enter()
        NativeResourceTransport.dataTask(with: server.path("game/native/models/\(name).bin")) { data, response, _ in
            lock.lock()
            if (response as? HTTPURLResponse)?.statusCode == 200 { binary = data }
            lock.unlock()
            group.leave()
        }.resume()
        group.enter()
        NativeResourceTransport.dataTask(with: server.path("game/native/models/\(name).png")) { data, response, _ in
            lock.lock()
            if (response as? HTTPURLResponse)?.statusCode == 200 { image = data }
            lock.unlock()
            group.leave()
        }.resume()
        if isPed {
            group.enter()
            NativeResourceTransport.dataTask(with: server.path("game/native/models/\(name).skel.bin")) { data, response, _ in
                lock.lock()
                let usable = (response as? HTTPURLResponse)?.statusCode == 200
                if usable { skeleton = data }
                lock.unlock()
                if usable { group.leave() }
                else {
                    NativeResourceTransport.dataTask(with: server.path("game/native/models/\(name).anim.bin")) { data, response, _ in
                        lock.lock()
                        if (response as? HTTPURLResponse)?.statusCode == 200 { animation = data }
                        lock.unlock(); group.leave()
                    }.resume()
                }
            }.resume()
            group.enter()
            NativeResourceTransport.dataTask(with: server.path("game/native/models/\(name).hand.bin")) { data, response, _ in
                lock.lock()
                if (response as? HTTPURLResponse)?.statusCode == 200 { attachment = data }
                lock.unlock()
                group.leave()
            }.resume()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.actorLoading.remove(name)
            // A newly advertised family may not be replaced by an older generic request.
            guard self.fixedCJSourceIdentity()==actorSource,self.pedAtlasFamilies[name]==nil else{return}
            // A partial mesh must not permanently suppress skeleton/rig retry.
            // Publish the required family together only after all stages pass.
            self.actorRetryAfter[name]=Date().addingTimeInterval(2)
            guard let binary, let image,
                  let world = try? WorldBinary(data: binary),
                  let atlas = try? self.textureLoader.newTexture(data: image, options: [.SRGB: false]),
                  let vertices = self.device.makeBuffer(bytes: world.vertices,
                                                       length: world.vertices.count * MemoryLayout<NativeVertex>.stride),
                  let indices = self.device.makeBuffer(bytes: world.indices,
                                                      length: world.indices.count * MemoryLayout<UInt32>.stride) else { return }
            let stagedMesh=Mesh(vertices:vertices,indices:indices,indexCount:world.indices.count,atlas:atlas)
            let stagedActor=skeleton.flatMap{NativeSkeletalActor(data:$0,vertexCount:world.vertices.count,device:self.device)}
            guard !isPed || stagedActor != nil else{return}
            var stagedRig:NativeVehicleRig?,stagedRigMesh:Mesh?,stagedMasks:[(Int,Mesh)]=[]
            var stagedVehicleTextures:NativeVehicleTextures?
            if let rigBinary,let rigImage,let rigMetadata,let rig=NativeVehicleRig(data:rigMetadata),
               rig.validatesAssetFamily(binary:rigBinary,atlas:rigImage),
               let meshData=rig.meshData(rigBinary),let geometry=try? WorldBinary(data:meshData),rig.document.draws.allSatisfy({$0.start<=geometry.indices.count && $0.count<=geometry.indices.count-$0.start}),
               let atlas=try? self.textureLoader.newTexture(data:rigImage,options:[.SRGB:false]),
               let vertices=self.device.makeBuffer(bytes:geometry.vertices,length:geometry.vertices.count*MemoryLayout<NativeVertex>.stride),
               let indices=self.device.makeBuffer(bytes:geometry.indices,length:geometry.indices.count*4) {
                if rig.document.version==3 {
                    guard self.vehicleNativePipeline != nil,
                          let textures=try? NativeVehicleTextures(device:self.device,queue:self.queue,atlas:atlas,rig:rig,world:geometry) else{return}
                    stagedVehicleTextures=textures
                }
                rig.installSortCenters(positions:geometry.vertices.map{SIMD3($0.position.x,$0.position.y,$0.position.z)},indices:geometry.indices)
                stagedRig=rig
                stagedRigMesh=Mesh(vertices:vertices,indices:indices,indexCount:geometry.indices.count,atlas:atlas)
                stagedMasks=(rig.document.waterMasks ?? []).compactMap { mask -> (Int,Mesh)? in
                    let vertices=stride(from:0,to:mask.positions.count,by:3).map { index in
                        NativeVertex(position:SIMD4(mask.positions[index],mask.positions[index+1],mask.positions[index+2],1),uvLayer:.zero,tint:SIMD4(repeating:1),dusk:SIMD4(repeating:1))
                    }
                    guard !vertices.isEmpty,!mask.indices.isEmpty,
                          let vertexBuffer=self.device.makeBuffer(bytes:vertices,length:vertices.count*MemoryLayout<NativeVertex>.stride),
                          let indexBuffer=self.device.makeBuffer(bytes:mask.indices,length:mask.indices.count*4) else{return nil}
                    return (mask.node,Mesh(vertices:vertexBuffer,indices:indexBuffer,indexCount:mask.indices.count,atlas:atlas))
                }
            }
            guard !isVehicle || (stagedRig != nil && stagedRigMesh != nil) else{return}
            self.actorMeshes[name]=stagedMesh
            if let stagedActor{self.skeletalActors[name]=stagedActor}
            if let rig=stagedRig,let mesh=stagedRigMesh{
                self.vehicleRigs[name]=rig;self.vehicleRigMeshes[name]=mesh;self.vehicleWaterMasks[name]=stagedMasks
                self.vehicleTextures[name]=stagedVehicleTextures
                if self.activeVehicleModel==String(rig.document.id){self.groundVehicle?.setDamageHinges(rig.damageHinges)}
            }
            self.actorRetryAfter.removeValue(forKey:name)
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

    private func pedAtlasError(_ name:String,_ message:String) {
        if pedAtlasErrors.insert(name).inserted{onStatus?(message)}
    }
    private func clearPedAtlas(_ name:String) {
        pedAtlasLoads.removeValue(forKey:name)?.request?.cancel()
        pedAtlasAdmission.removeValue(forKey:name)
        actorMeshes.removeValue(forKey:name);skeletalActors.removeValue(forKey:name)
        actorAnimations.removeValue(forKey:name);actorParts.removeValue(forKey:name);actorAttachments.removeValue(forKey:name)
        pedAtlasGPU.removeValue(forKey:name);actorRetryAfter.removeValue(forKey:name);pedAtlasErrors.remove(name)
    }
    private func invalidatePedAtlasSourceIfChanged() {
        guard let source=pedAtlasSource,source != fixedCJSourceIdentity() else{return}
        for name in Set(pedAtlasGPU.keys).union(pedAtlasLoads.keys).union(pedAtlasAdmission.keys){clearPedAtlas(name)}
        pedAtlasLoader.cancelAll()
        // Keep the old advertised catalogue fenced. A source change cannot
        // silently downgrade these names to legacy PNGs before a real rebind.
    }
    private func bindPedAtlasFamilies(_ v1:[String:String],v2:[String:String]=[:],source:String) {
        let families=v1.merging(v2){_,new in new}
        let allowed=Set(pedModels.values).subtracting(["null"]).subtracting(vehicleModels.values).subtracting(weaponModels.values)
        let admitted=families.filter{allowed.contains($0.key) && !$0.key.hasPrefix("samp-dl-")}
        let changed=Set(pedAtlasFamilies.keys).union(admitted.keys).filter{
            pedAtlasSource != source || pedAtlasFamilies[$0] != admitted[$0] || pedAtlasV2Names.contains($0) != (v2[$0] != nil)
        }
        for name in changed{clearPedAtlas(name)}
        pedAtlasFamilies=admitted;pedAtlasV2Names=Set(v2.keys).intersection(admitted.keys);pedAtlasSource=source
        if admitted.count != families.count{onStatus?("PED ATLAS CATALOGUE HAS UNKNOWN MODEL ENTRIES")}
    }
    private func loadPedAtlasActor(_ name:String,family:String) {
        let source=fixedCJSourceIdentity()
        if let bound=pedAtlasGPU[name],bound.family==family,bound.source==source,
           actorMeshes[name] != nil,skeletalActors[name] != nil{return}
        let native=pedAtlasV2Names.contains(name)
        let shadersReady=native ? (pedNativePipeline != nil && pedNativeAnimatedPipeline != nil && pedNativeSkeletalPipeline != nil):
            (pedAtlasPipeline != nil && pedAtlasAnimatedPipeline != nil && pedAtlasSkeletalPipeline != nil)
        guard pedAtlasSource==source,NativePedAtlasFamily.version(in:family,model:name)==(native ? 2:1),shadersReady,
              let server else{
            pedAtlasError(name,"PED ATLAS FAMILY/SHADER IS UNAVAILABLE: \(name)");return
        }
        guard pedAtlasLoads[name]==nil,Date()>=(actorRetryAfter[name] ?? .distantPast) else{return}
        let token=UUID()
        // Own the admission before calling the asynchronous factory.
        pedAtlasAdmission[name]=token;pedAtlasLoads[name]=PedAtlasLoad(token:token,request:nil)
        let request=pedAtlasLoader.load(model:name,path:family,source:source,server:server,
            priority:name==pedModels[String(localSkin)] ? 1:0){[weak self] result in
            guard let self,self.pedAtlasAdmission[name]==token,self.pedAtlasLoads[name]?.token==token else{
                if case .success(let payload)=result{payload.close()};return
            }
            let owned=self.pedAtlasLoads.removeValue(forKey:name)?.request
            guard self.fixedCJSourceIdentity()==source,self.pedAtlasSource==source,self.pedAtlasFamilies[name]==family,
                  owned?.isCancelled != true else{if case .success(let payload)=result{payload.close()};return}
            self.actorRetryAfter[name]=Date().addingTimeInterval(2)
            switch result {
            case .failure(let error):
                if (error as? NativePedAtlasLoader.Failure) != .cancelled {
                    self.pedAtlasError(name,"PED ATLAS LOAD FAILED: \(name): \(error.localizedDescription)")
                }
            case .success(let payload):
                let installed=payload.consume{_,files -> Bool in
                    let world=payload.world,validated=payload.layout
                    guard let image=files["atlas"],let skin=files["skeleton"],
                          let atlas=try? self.textureLoader.newTexture(data:image,options:[.SRGB:false,.generateMipmaps:false]),
                          atlas.width==validated.width,atlas.height==validated.height,
                          let vertices=self.device.makeBuffer(bytes:world.vertices,length:world.vertices.count*MemoryLayout<NativeVertex>.stride),
                          let indices=self.device.makeBuffer(bytes:world.indices,length:world.indices.count*4),
                          let rectangles=self.device.makeBuffer(bytes:validated.vectors,length:validated.vectors.count*MemoryLayout<SIMD4<Float>>.stride),
                          let actor=NativeSkeletalActor(data:skin,vertexCount:world.vertices.count,device:self.device) else{return false}
                    let hand=files["hand"].flatMap(NativeActorAttachment.init(data:))
                    let parts=files["parts"].flatMap{try? JSONDecoder().decode(ActorParts.self,from:$0)}
                    guard files["hand"]==nil || hand != nil,files["parts"]==nil || parts != nil,
                          owned?.isCancelled != true,self.fixedCJSourceIdentity()==source,
                          self.pedAtlasSource==source,self.pedAtlasFamilies[name]==family,self.pedAtlasAdmission[name]==token else{return false}
                    guard (validated.hardware != nil)==native else{return false}
                    if native,let parts {
                        guard parts.parts.allSatisfy({$0.start>=0 && $0.count>0 && $0.count<=world.indices.count &&
                            $0.start<=world.indices.count-$0.count && $0.start%3==0 && $0.count%3==0 &&
                            $0.pivot.count==3 && $0.pivot.allSatisfy(\.isFinite)}) else{return false}
                    }
                    let images:NativePedTextureArrays?
                    if let plan=validated.hardware {
                        guard let uploaded=try? NativePedTextureArrays(device:self.device,queue:self.queue,atlas:atlas,plan:plan) else{return false}
                        images=uploaded
                    }else{images=nil}
                    guard owned?.isCancelled != true,self.fixedCJSourceIdentity()==source,self.pedAtlasSource==source,
                          self.pedAtlasFamilies[name]==family,self.pedAtlasAdmission[name]==token else{return false}
                    self.actorMeshes[name]=Mesh(vertices:vertices,indices:indices,indexCount:world.indices.count,atlas:atlas)
                    self.skeletalActors[name]=actor
                    self.pedAtlasGPU[name]=PedAtlasGPU(family:family,source:source,layout:rectangles,
                        textureBytes:validated.textureBytes+(images?.allocatedBytes ?? 0),native:images)
                    self.actorAnimations.removeValue(forKey:name)
                    if let hand{self.actorAttachments[name]=hand}else{self.actorAttachments.removeValue(forKey:name)}
                    if let parts {
                        self.actorParts[name]=parts.parts.filter{$0.start>=0 && $0.count>0 && $0.count<=world.indices.count && $0.start<=world.indices.count-$0.count && $0.pivot.count==3}
                    }else{self.actorParts.removeValue(forKey:name)}
                    self.actorRetryAfter.removeValue(forKey:name);self.pedAtlasErrors.remove(name)
                    return true
                } ?? false
                if !installed,self.pedAtlasAdmission[name]==token {
                    self.pedAtlasError(name,"PED ATLAS GPU ADMISSION FAILED: \(name)")
                }
            }
        }
        if pedAtlasLoads[name]?.token==token{pedAtlasLoads[name]?.request=request}else{request.cancel()}
    }

    private func nativeCameraVehicle() -> NativeGameCamera.Vehicle? {
        if isPassenger {
            guard let id=currentVehicleID,let frame=passengerFrame,frame.vehicle.id==id,
                  let definition=cameraVehicleDefinitions[activeVehicleModel] else{return nil}
            // Shared transform is already the GTA model-root frame. Its
            // translation includes the rotated origin exactly once.
            let matrix=frame.transform
            func column(_ index:Int)->SIMD3<Float>{let c=matrix[index];return SIMD3(c.x,c.y,c.z)}
            func vector(_ row:[Float]?)->SIMD3<Float>?{guard let row,row.count==3 else{return nil};return SIMD3(row[0],row[1],row[2])}
            let seats=riderDefinitions?.models[activeVehicleModel]?.seats
            let eye=passengerSeat.flatMap{index in seats.flatMap{$0.indices.contains(index) ? $0[index].position:nil}}
            let bounds=definition.bounds
            return .init(kind:definition.kind,position:column(3),forward:column(1),right:column(0),up:column(2),
                moveSpeed:frame.velocity/50,turnSpeed:frame.angularVelocity/50,wheels:4,
                bounds:.init(maxX:bounds.maxX,minY:bounds.minY,maxZ:bounds.maxZ,min:vector(bounds.box?.min),max:vector(bounds.box?.max)),
                heightAboveRoad:definition.origin,eye:eye)
        }
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

    private var legacyGravity:Float?
    func receiveLegacyGameplay(_ event:NativeSAMPGameplayCommands.Event) {
        let now=ProcessInfo.processInfo.systemUptime
        let seed=legacyCameraSample?.pose ?? gameCameraFrame.map{NativeSAMPGameCamera.Pose(eye:$0.source,target:$0.target)}
        let revision=legacyGameCamera.followRevision
        do {
            guard try legacyGameCamera.apply(event,at:now,seed:seed) else{return}
            switch event.command {
            case .reset:legacyGravity=nil;_ = groundVehicle?.world.setLegacyGravity(nil)
            case .gravity(let value):
                if groundVehicle?.world.setLegacyGravity(value) != false{legacyGravity=value}
                else{onStatus?("SERVER GRAVITY COULD NOT BE APPLIED")}
            default:break
            }
            if revision != legacyGameCamera.followRevision {
                gameCamera.resetFoot(heading:actorHeading,pitch:cameraPitch)
                gameCamera.beginVehicle();legacyCameraSubject=nil
            }
            if !legacyGameCamera.spectating{legacySpectatorAccumulator=0}
        }catch{onStatus?("SERVER CAMERA COMMAND REJECTED: \(error)")}
    }
    func legacySpawned(generation:UInt64?) {
        _=try?legacyGameCamera.spawned(at:ProcessInfo.processInfo.systemUptime,generation:generation)
        legacyCameraSample=nil;legacyCameraSubject=nil;legacyCameraDiagnostics.removeAll();legacySpectatorAccumulator=0
    }
    func rebaseLegacyObjectClock(){legacyObjectClock.reset()}
    private func legacySubjectFrame(_ subject:NativeSAMPGameCamera.Subject,mode:NativeSAMPGameplayCommands.SpectateMode,delta:Float,now:Double)->NativeSAMPGameCamera.SubjectFrame? {
        if legacyCameraSubject != subject {
            legacyCameraSubject=subject;legacyFollowCamera.resetFoot(heading:heading,pitch:cameraPitch);legacyFollowCamera.beginVehicle()
            legacyFollowCamera.setFootZoom(gameCamera.footZoom);legacyFollowCamera.setVehicleView(gameCamera.vehicleView)
        }
        var focus:SIMD3<Float>,frame:NativeGameCamera.Frame?
        switch subject {
        case .player(let id):
            guard let player=remotePlayers.first(where:{$0.id==String(id)})else{return nil}
            focus=player.position+SIMD3(0,0,1)
            if mode == .normal {
                frame=legacyFollowCamera.followFoot(.init(position:player.position,actorHeading:player.heading,weapon:player.weapon,
                    aiming:player.aim != nil,crouching:player.crouching,planarSpeed:hypot(player.velocity.x,player.velocity.y)),delta:delta)
            }
        case .vehicle(let id):
            let driver=remotePlayers.first(where:{$0.vehicleID==String(id)})
            let vehicle=remoteVehicles.first(where:{$0.id==String(id)}).map{predictedVehicle($0)}
            guard let bodyPosition=driver?.position ?? vehicle?.position else{return nil}
            let code=driver?.code ?? vehicle?.code ?? "",model=String(code.split(separator:".").first ?? "")
            guard let definition=cameraVehicleDefinitions[model]else{return nil}
            let yaw=driver?.heading ?? vehicle?.heading ?? 0,pitch=driver?.pitch ?? vehicle?.pitch ?? 0,roll=driver?.roll ?? vehicle?.roll ?? 0
            let position=bodyPosition+NativeGroundVehicle.modelOffset(origin:definition.origin,heading:yaw,pitch:pitch,roll:roll)
            focus=position
            if mode == .normal {
                let transform=Self.rotationZ(-yaw)*Self.rotationX(pitch)*Self.rotationY(roll)
                let forward=SIMD3(transform.columns.1.x,transform.columns.1.y,transform.columns.1.z)
                let right=SIMD3(transform.columns.0.x,transform.columns.0.y,transform.columns.0.z)
                let up=SIMD3(transform.columns.2.x,transform.columns.2.y,transform.columns.2.z)
                func vector(_ row:[Float]?)->SIMD3<Float>?{guard let row,row.count==3 else{return nil};return SIMD3(row[0],row[1],row[2])}
                let bounds=definition.bounds
                let input=NativeGameCamera.Vehicle(kind:definition.kind,position:position,forward:forward,right:right,up:up,
                    moveSpeed:(driver?.velocity ?? .zero)/50,turnSpeed:(driver?.angularVelocity ?? .zero)/50,wheels:4,
                    bounds:.init(maxX:bounds.maxX,minY:bounds.minY,maxZ:bounds.maxZ,min:vector(bounds.box?.min),max:vector(bounds.box?.max)),
                    heightAboveRoad:definition.origin,eye:vector(definition.driverEye))
                frame=legacyFollowCamera.followVehicle(input,delta:delta,nowMilliseconds:now*1000)
            }
        }
        // Normal mode uses the existing native game-camera algorithms. Side
        // mode has no verified adapter yet; the owner holds its last safe view.
        return .init(focus:focus,normal:frame.map{.init(eye:$0.source,target:$0.target)},normalProvenance:.nativeGameCameraAdapter)
    }
    func receiveLegacyObject(_ event:NativeSAMPObjects.Event) throws {
        switch event{case .create(let value):removeLegacyObjectCollision(value.id);case .destroy(let id):removeLegacyObjectCollision(id);default:break}
        try legacyObjects.apply(event,at:ProcessInfo.processInfo.systemUptime)
        refreshLegacyStockReferences()
    }
    private enum LegacyStockMetadata {
        case models(NativeSAMPStockModels,String),collision(NativeSAMPStockCollisionCatalog)
    }
    /// Only our configured asset origin's LAN access token is eligible. The
    /// policy discards local identity, original-site and Discord cookies.
    private func legacyStockAccess()->NativeStockAssetAccess? {
        guard let server else{return nil}
        return NativeStockAssetAccess(assetOrigin:server.url,sessionCookies:HTTPCookieStorage.shared.cookies(for:server.url) ?? [])
    }
    /// Metadata has no pre-advertised digest. Its dedicated HTTP sink bounds
    /// received bytes before append, rejects redirects, and never uses cookies.
    private func loadLegacyStockCatalogs() {
        guard let server,legacyStockMetadataTasks.isEmpty,legacyStockMetadataPending==0,
              ProcessInfo.processInfo.systemUptime>=legacyStockMetadataRetryAfter,
              legacyStockCatalog == nil || legacyStockCollisionCatalog == nil else{return}
        legacyStockMetadataEpoch &+= 1;let epoch=legacyStockMetadataEpoch
        legacyStockMetadataPending=2
        for (path,collision) in [("game/native/stock-models.json",false),("game/native/stock-collision/catalog.json",true)] {
            let id=UUID()
            let request=LegacyStockMetadataTransfer(url:server.path(path),maximumBytes:16*1024*1024,access:legacyStockAccess()) {[weak self] result in
                guard let self,self.legacyStockMetadataEpoch==epoch else{return}
                self.legacyStockMetadataTasks.removeValue(forKey:id)
                self.legacyImportQueue.async {[weak self] in
                    let parsed:Result<LegacyStockMetadata,Error>=Result {
                        let data=try result.get()
                        return collision ? .collision(try NativeSAMPStockCollisionCatalog.decode(data)):
                            .models(try NativeSAMPStockModels.decode(data),SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined())
                    }
                    DispatchQueue.main.async {
                        guard let self,self.legacyStockMetadataEpoch==epoch,self.server==server else{return}
                        self.legacyStockMetadataPending-=1
                        do {
                            switch try parsed.get(){case .models(let value,let digest):self.legacyStockCatalog=value;self.legacyStockManifestSHA256=digest;case .collision(let value):self.legacyStockCollisionCatalog=value}
                            if self.legacyStockLoader==nil,self.legacyStockCatalog != nil,self.legacyStockCollisionCatalog != nil {
                                var limits=NativeSAMPStockAssetLoader.Limits();limits.concurrentLoads=2;limits.pendingLoads=8
                                self.legacyStockLoader=try .init(assetBaseURL:server.url,limits:limits,accessProvider:{[weak self]in self?.legacyStockAccess()})
                            }
                            self.refreshLegacyStockReferences()
                        }catch{self.legacyStockMetadataRetryAfter=ProcessInfo.processInfo.systemUptime+30;self.onStatus?("STOCK ASSET CATALOG UNAVAILABLE: \(error)")}
                    }
                }
            }
            legacyStockMetadataTasks[id]=request;request.start()
        }
    }
    private func refreshLegacyStockReferences() {
        guard let objects=try?legacyObjects.sampledInstances(at:ProcessInfo.processInfo.systemUptime)else{return}
        var references=Set(objects.map(\.model).filter{(1...19999).contains($0)})
        for object in objects {for material in object.materials.values {
            if case .texture(let model,_,_,_)=material,(1...19999).contains(model){references.insert(Int32(model))}
        }}
        legacyStockReferences=references
        if !references.isEmpty{loadLegacyStockCatalogs()}
        for id in legacyStockLoads.keys.filter({!references.contains($0)}) {
            if let request=legacyStockLoads.removeValue(forKey:id)?.request{legacyStockLoader?.cancel(request)}
        }
        let now=ProcessInfo.processInfo.systemUptime
        for id in references where legacyStockModels.contains(id){legacyStockUse[id]=now}
        pumpLegacyStockObjects()
    }
    private func pumpLegacyStockObjects() {
        guard !legacyStockPumping,let catalog=legacyStockCatalog,let collisionCatalog=legacyStockCollisionCatalog,
              let loader=legacyStockLoader,let server else{return}
        legacyStockPumping=true;defer{legacyStockPumping=false}
        let now=ProcessInfo.processInfo.systemUptime
        for id in legacyStockReferences.sorted() {
            guard legacyStockLoads.count<2 else{break}
            guard !legacyStockModels.contains(id),legacyStockLoads[id]==nil,(legacyStockRetries[id] ?? 0)<=now else{continue}
            let token=UUID(),epoch=legacyAssetEpoch
            legacyStockLoads[id]=(token,nil)
            do {
                let resolution=try catalog.resolve(id:id,assetBaseURL:server.url)
                guard resolution.model.kind == .object || resolution.model.kind == .weapon else {
                    throw NativeRenderWareModel.Failure.unsupported("stock \(resolution.model.kind.rawValue) requires its verified activity/time adapter")
                }
                let request=loader.load(resolution){[weak self] result in
                    guard let self,self.legacyAssetEpoch==epoch,self.legacyStockLoads[id]?.token==token else{return}
                    do {
                        let prepared=try result.get()
                        let collision=try collisionCatalog.resolve(modelID:id,modelName:prepared.model.model,
                            source:prepared.model.source,line:prepared.model.line,stockManifestSHA256:self.legacyStockManifestSHA256,assetBaseURL:server.url)
                        switch collision {
                        case .missing:
                            throw NativeRenderWareModel.Failure.unsupported("authored collision inventory incomplete for \(prepared.model.model)")
                        case .noAuthoredCollision:
                            guard prepared.embeddedCollision.allSatisfy({$0.name == nil || $0.name?.lowercased()==prepared.model.model})else {
                                throw NativeRenderWareModel.Failure.malformed("embedded collision name differs from exact DFF")
                            }
                            self.installLegacyStockObject(prepared,collision:prepared.embeddedCollision,id:id,token:token,epoch:epoch,inventoryAbsent:prepared.embeddedCollision.isEmpty)
                        case .ambiguous:
                            throw NativeRenderWareModel.Failure.unsupported("ambiguous authored collision for \(prepared.model.model)")
                        case .unique(let file):
                            let metadata=file.metadata
                            let asset=NativeSAMPStockModels.Asset(path:metadata.path,bytes:metadata.bytes,crc32:metadata.crc32,sha256:metadata.sha256)
                            let request=loader.loadFile(.init(metadata:asset,url:file.url)){[weak self] result in
                                guard let self,self.legacyAssetEpoch==epoch,self.legacyStockLoads[id]?.token==token else{return}
                                self.legacyImportQueue.async {
                                    let decoded:Result<NativeRenderWareCollision.Model,Error>=Result {try collisionCatalog.prepare(try result.get().data,for:file)}
                                    DispatchQueue.main.async {
                                        guard self.legacyAssetEpoch==epoch,self.legacyStockLoads[id]?.token==token else{return}
                                        do {self.installLegacyStockObject(prepared,collision:[try decoded.get()],id:id,token:token,epoch:epoch)}
                                        catch{self.failLegacyStockObject(id,token:token,error:error)}
                                    }
                                }
                            }
                            self.legacyStockLoads[id]?.request=request
                        }
                    }catch{self.failLegacyStockObject(id,token:token,error:error)}
                }
                legacyStockLoads[id]?.request=request
            }catch{failLegacyStockObject(id,token:token,error:error)}
        }
    }
    private func failLegacyStockObject(_ id:Int32,token:UUID,error:Error) {
        guard legacyStockLoads[id]?.token==token else{return}
        legacyStockLoads.removeValue(forKey:id);legacyStockRetries[id]=ProcessInfo.processInfo.systemUptime+30
        if legacyMissingObjects.insert(id).inserted{onStatus?("STOCK OBJECT \(id) UNAVAILABLE: \(error)")}
        pumpLegacyStockObjects()
    }
    private func legacyCollisionResourceBytes(_ models:[NativeRenderWareCollision.Model])throws->Int {
        var total=0
        func add(_ count:Int,_ stride:Int)throws {
            let product=count.multipliedReportingOverflow(by:stride),sum=total.addingReportingOverflow(product.partialValue)
            guard !product.overflow,!sum.overflow,sum.partialValue<=192*1024*1024 else{throw NativeRenderWareModel.Failure.limit("authored collision resources")}
            total=sum.partialValue
        }
        try add(models.count,MemoryLayout<NativeRenderWareCollision.Model>.stride)
        for model in models {
            try add(model.spheres.count,MemoryLayout<NativeRenderWareCollision.Sphere>.stride)
            try add(model.boxes.count,MemoryLayout<NativeRenderWareCollision.Box>.stride)
            try add(model.mesh.vertices.count,MemoryLayout<SIMD3<Float>>.stride)
            try add(model.mesh.faces.count,MemoryLayout<NativeRenderWareCollision.Face>.stride)
            try add(model.faceGroups.count,MemoryLayout<NativeRenderWareCollision.FaceGroup>.stride)
            if let shadow=model.shadowMesh {
                try add(shadow.vertices.count,MemoryLayout<SIMD3<Float>>.stride)
                try add(shadow.faces.count,MemoryLayout<NativeRenderWareCollision.Face>.stride)
            }
        }
        return total
    }
    /// Only unreferenced stock entries may be evicted. Custom DL resources keep
    /// their existing download/registration barrier and share the same total.
    private func reserveLegacyModelBytes(_ bytes:Int,replacing id:Int32)throws {
        let maximum=192*1024*1024,old=legacyModelCosts[id] ?? 0
        guard bytes>=0,bytes<=maximum else{throw NativeRenderWareModel.Failure.limit("192MiB shared model resources")}
        while bytes>maximum-legacyModelBytes+old || ((1...19999).contains(id) && !legacyStockModels.contains(id) &&
              legacyStockModels.count>=128 && !legacyStockModels.isSubset(of:legacyStockReferences)) {
            guard let unused=legacyStockModels.filter({$0 != id && !legacyStockReferences.contains($0)}).min(by:{(legacyStockUse[$0] ?? 0)<(legacyStockUse[$1] ?? 0)})else {
                throw NativeRenderWareModel.Failure.limit("192MiB shared model resources; active references retained")
            }
            legacyModels.removeValue(forKey:unused);legacyStockModels.remove(unused);legacyStockUse.removeValue(forKey:unused)
            legacyStockCollisionKinds.removeValue(forKey:unused)
            legacyModelBytes-=legacyModelCosts.removeValue(forKey:unused) ?? 0;legacyCollisionModels.removeValue(forKey:unused)
            for key in legacyExactTextures.keys.filter({$0.model==unused}) {
                legacyExactTextures.removeValue(forKey:key);legacyTextureSources.removeValue(forKey:key);legacyTextureConflicts.remove(key)
            }
            legacyMaterialOwner?.reset()
        }
    }
    private func installLegacyStockObject(_ prepared:NativeSAMPStockAssetLoader.Prepared,collision:[NativeRenderWareCollision.Model],
                                          id:Int32,token:UUID,epoch:UInt64,inventoryAbsent:Bool=false) {
        guard legacyAssetEpoch==epoch,legacyStockLoads[id]?.token==token else{return}
        do {
            guard legacyStockReferences.contains(id)else{legacyStockLoads.removeValue(forKey:id);pumpLegacyStockObjects();return}
            guard let catalog=legacyStockCatalog,let server,
                  let dictionary=try catalog.dictionary(named:prepared.model.txd,assetBaseURL:server.url).file else {
                throw NativeRenderWareModel.Failure.malformed("stock dictionary provenance unavailable")
            }
            let dictionaryCRC=dictionary.metadata.crc32
            let bytes=prepared.plan.meshByteCount+prepared.plan.textureByteCount+(try legacyCollisionResourceBytes(collision))
            try reserveLegacyModelBytes(bytes,replacing:id)
            if legacyModelPipelines==nil {
                guard let library=device.makeDefaultLibrary()else{throw NativeRenderWareModel.Failure.gpu("native shader library missing")}
                legacyModelPipelines=try .init(device:device,library:library,color:view.colorPixelFormat,depth:view.depthStencilPixelFormat)
            }
            let uploaded=try NativeRenderWareModel.Uploaded(plan:prepared.plan,device:device)
            let old=legacyModelCosts[id] ?? 0
            legacyModels[id]=uploaded;legacyCollisionModels[id]=collision.filter(\.hasCollisionVolumes)
            legacyStockCollisionKinds[id]=inventoryAbsent ? .inventoryAbsent:(collision.contains(where: \.hasCollisionVolumes) ? .authored:.authoredEmpty)
            legacyStockModels.insert(id);legacyStockUse[id]=ProcessInfo.processInfo.systemUptime
            legacyModelCosts[id]=bytes;legacyModelBytes=legacyModelBytes-old+bytes
            for (index,texture) in uploaded.plan.textures.enumerated() {
                let key=NativeSAMPObjectMaterials.TextureRequest(model:id,dictionary:prepared.model.txd,texture:texture.lookupName)
                if let previous=legacyTextureSources[key],previous != dictionaryCRC {
                    legacyTextureConflicts.insert(key);legacyExactTextures.removeValue(forKey:key)
                }else if !legacyTextureConflicts.contains(key) {
                    legacyExactTextures[key] = .init(image:uploaded.textures[index],sampler:nil,containsTransparency:texture.containsTransparentPixels)
                    legacyTextureSources[key]=dictionaryCRC
                }
            }
            legacyMaterialOwner?.reset();legacyMissingObjects.remove(id);legacyStockRetries.removeValue(forKey:id)
            legacyStockLoads.removeValue(forKey:id);pumpLegacyStockObjects()
            // Physical publication belongs to the existing fixed-step callback.
            // drawLegacyObjects waits for that callback's actual native handles.
        }catch{failLegacyStockObject(id,token:token,error:error)}
    }
    private func legacyModelApplies(_ id:Int32)->Bool {
        legacyStockModels.contains(id) || legacyModelDefinitions[id]?.applies(to:legacyVirtualWorld)==true
    }
    private func legacyStockObjectReady(_ object:NativeSAMPObjects.Instance)->Bool {
        guard legacyStockModels.contains(object.model),legacyStockCollisionKinds[object.model] != nil,
              let models=legacyCollisionModels[object.model]else{return false}
        if models.isEmpty{return true} // Explicit empty COL or verified complete-inventory absence.
        guard legacyCollisionKinds[object.id]==object.model,let handles=legacyCollisionHandles[object.id],
              handles.count==models.count,let world=legacyCollisionWorld else{return false}
        return handles.allSatisfy{world.colliderIDs(for:$0)?.isEmpty==false}
    }
    func legacyStockCollisionProvenance(for model:Int32)->String?{legacyStockCollisionKinds[model]?.rawValue}
    private func legacyObjectSnapshot(at now:Double)->NativeSAMPObjectScene.Snapshot? {
        guard let values=try?legacyObjects.sampledInstances(at:now)else{return nil}
        return NativeSAMPObjectScene.resolve(values) { [self] parent in
            switch parent {
            case .vehicle(let id):
                if driving,currentVehicleID==String(id),let exact=nativeVehicleTransform{return exact}
                guard let vehicle=remoteVehicles.first(where:{$0.id==String(id)})else{return nil}
                let value=predictedVehicle(vehicle)
                return Self.translation(value.position)*Self.rotationZ(-value.heading)*Self.rotationX(value.pitch)*Self.rotationY(value.roll)*Self.translation(SIMD3(0,0,vehicleModelOrigin(value.code)))
            case .player(let id):
                if id==legacyLocalPlayerID{return Self.translation(camera)*Self.rotationZ(-actorHeading)}
                guard let player=remotePlayers.first(where:{$0.id==String(id)})else{return nil}
                return Self.translation(player.position)*Self.rotationZ(-player.heading)
            case .object:return nil
            }
        }
    }
    private func removeLegacyObjectCollision(_ id:UInt16) {
        for handle in legacyCollisionHandles.removeValue(forKey:id) ?? []{_=legacyCollisionWorld?.remove(handle)}
        legacyCollisionKinds.removeValue(forKey:id)
    }
    private func synchronizeLegacyObjectPhysics(at timestamp:Double) {
        guard let world=legacyCollisionWorld,let snapshot=legacyObjectSnapshot(at:timestamp)else{return}
        var live=Set<UInt16>()
        for draw in snapshot.draws {
            guard let models=legacyCollisionModels[draw.object.model],!models.isEmpty,
                  legacyModelApplies(draw.object.model) else{continue}
            let id=draw.object.id;live.insert(id)
            let matrix=draw.transform,rotation=simd_float3x3(SIMD3(matrix.columns.0.x,matrix.columns.0.y,matrix.columns.0.z),SIMD3(matrix.columns.1.x,matrix.columns.1.y,matrix.columns.1.z),SIMD3(matrix.columns.2.x,matrix.columns.2.y,matrix.columns.2.z))
            let pose=NativeRenderWareCollisionWorld.Transform(position:SIMD3(matrix.columns.3.x,matrix.columns.3.y,matrix.columns.3.z),rotation:simd_quatf(rotation))
            do {
                if legacyCollisionKinds[id] != draw.object.model{removeLegacyObjectCollision(id)}
                if let handles=legacyCollisionHandles[id]{for handle in handles{try world.move(handle,to:pose);try world.setCameraCollision(handle,enabled:draw.object.cameraCollision)}}
                else {
                    var made:[NativeRenderWareCollisionWorld.Handle]=[]
                    do {for model in models {
                        guard legacyCollisionSerial<UInt64.max else{throw NativeRenderWareCollisionWorld.Failure.limit("entity generation")}
                        let serial=legacyCollisionSerial;legacyCollisionSerial+=1
                        made.append(try world.insert(.init(id:serial,model:model,transform:pose,cameraCollision:draw.object.cameraCollision)))
                    }}catch{for handle in made{_=world.remove(handle)};throw error}
                    legacyCollisionHandles[id]=made;legacyCollisionKinds[id]=draw.object.model
                }
            }catch{removeLegacyObjectCollision(id);if legacyMissingObjects.insert(draw.object.model).inserted{onStatus?("OBJECT COLLISION UNAVAILABLE: \(error)")}}
        }
        for id in legacyCollisionHandles.keys.filter({!live.contains($0)}){removeLegacyObjectCollision(id)}
    }
    func invalidateLegacyImports(){
        legacyAssetEpoch &+= 1
        _=legacyStockLoader?.reset();legacyStockLoads.removeAll();legacyStockRetries.removeAll()
    }
    func clearLegacyModels() {
        legacyAssetEpoch &+= 1
        _=legacyStockLoader?.reset();legacyStockLoads.removeAll();legacyStockRetries.removeAll();legacyStockUse.removeAll()
        legacyStockReferences.removeAll();legacyStockModels.removeAll()
        legacyStockCollisionKinds.removeAll()
        for name in legacyPedModels.keys{skeletalActors.removeValue(forKey:name)}
        for key in legacyModelDefinitions.keys where (20001...30000).contains(key){pedModels.removeValue(forKey:String(key))}
        let refreshSkin: Int? = {
            guard let current=localLegacySkin,(20001...30000).contains(current),
                  let selection=actorSelection.state,selection.phase == .applied,
                  selection.request.domain == .legacy,selection.request.skin == current else{return nil}
            return current
        }()
        legacyModels.removeAll();legacyPedModels.removeAll();legacyPedStyles.removeAll();legacyModelDefinitions.removeAll();legacyModelCosts.removeAll()
        legacyMaterialOwner?.reset();legacyExactTextures.removeAll();legacyTextureSources.removeAll();legacyTextureConflicts.removeAll();legacyTextureLoads.removeAll();legacyTextureRetries.removeAll();legacyMaterialErrors.removeAll();legacyExternalTextureBytes.removeAll();legacyTextureUse.removeAll()
        legacyModelBytes=0;legacyMissingObjects.removeAll()
        legacyCollisionWorld?.removeAll();legacyCollisionHandles.removeAll();legacyCollisionKinds.removeAll();legacyCollisionModels.removeAll()
        if let refreshSkin{_=setLegacySkin(refreshSkin)}
    }
    func clearLegacyWorld() {
        clearLegacyModels();legacyObjects.reset();legacyVirtualWorld=0;legacyLocalPlayerID=nil
    }
    /// Called only with protocol-verified cache receipts. Parsing remains off
    /// the input/render thread; a stale reconnect cannot publish an old model.
    func importLegacyModel(_ model:NativeSAMPArtwork.Model,dff:URL,txd:URL,dictionary:String?=nil,completion:@escaping(Result<Void,Error>)->Void) {
        let epoch=legacyAssetEpoch
        legacyImportQueue.async { [weak self] in
            let result:Result<LegacyPreparedImport,Error>=Result {
                let data=try Data(contentsOf:dff,options:.mappedIfSafe)
                let geometry=try NativeRenderWareDFF.decode(data)
                let textures=try NativeRenderWareTXD.decode(Data(contentsOf:txd,options:.mappedIfSafe))
                let plan:LegacyImportPlan=model.type==1 ? .pedestrian(try NativeRenderWarePedModel.prepare(dff:geometry,txd:textures)):.object(try NativeRenderWareModel.prepare(dff:geometry,txd:textures))
                for diagnostic in plan.resources.diagnostics {
                    switch diagnostic {
                    case .omittedMipTail:break // Preserve the actual available levels.
                    default:throw NativeRenderWareModel.Failure.unsupported("incomplete model resources: \(diagnostic)")
                    }
                }
                let collision=model.type==1 ? []:try NativeRenderWareCollision.embedded(inDFF:data).flatMap(\.models).filter(\.hasCollisionVolumes)
                return LegacyPreparedImport(drawing:plan,collision:collision)
            }
            DispatchQueue.main.async {
                guard let self,self.legacyAssetEpoch==epoch else{completion(.failure(NativeSAMPArtwork.Failure.cancelled));return}
                do {
                    let prepared=try result.get(),plan=prepared.drawing,bytes=plan.resources.meshByteCount+plan.resources.textureByteCount+(try self.legacyCollisionResourceBytes(prepared.collision))
                    let old=self.legacyModelCosts[model.customID] ?? 0
                    try self.reserveLegacyModelBytes(bytes,replacing:model.customID)
                    if self.legacyModelPipelines==nil {
                        guard let library=self.device.makeDefaultLibrary()else{throw NativeRenderWareModel.Failure.gpu("native shader library missing")}
                        self.legacyModelPipelines=try .init(device:self.device,library:library,color:self.view.colorPixelFormat,depth:self.view.depthStencilPixelFormat)
                    }
                    let resources:NativeRenderWareModel.Uploaded
                    switch plan {
                    case .object(let plan):
                        let uploaded=try NativeRenderWareModel.Uploaded(plan:plan,device:self.device)
                        self.legacyModels[model.customID]=uploaded;resources=uploaded
                    case .pedestrian(let plan):
                        if self.legacyPedPipelines==nil {
                            guard let library=self.device.makeDefaultLibrary()else{throw NativeRenderWareModel.Failure.gpu("native shader library missing")}
                            self.legacyPedPipelines=try .init(device:self.device,library:library,color:self.view.colorPixelFormat,depth:self.view.depthStencilPixelFormat)
                        }
                        let uploaded=try NativeRenderWarePedModel.Uploaded(plan:plan,device:self.device),name="samp-dl-\(model.customID)"
                        resources=uploaded.resources
                        self.legacyPedModels[name]=uploaded;self.pedModels[String(model.customID)]=name;self.skeletalActors[name]=uploaded.actor
                        if let style=self.sampSkinCatalog?.model(forLegacy:Int(model.baseID)){self.legacyPedStyles[name]=style}
                        self.ownRiderCapture=nil;self.ownRiderPrevious=nil;self.remoteRiderCapture.removeAll();self.remoteRiderPrevious.removeAll()
                        if self.pendingLegacySkin==Int(model.customID){self.resumeActorSelection()}
                    }
                    self.legacyModelDefinitions[model.customID]=model;self.legacyModelCosts[model.customID]=bytes
                    self.legacyCollisionModels[model.customID]=prepared.collision
                    for id in self.legacyCollisionKinds.keys.filter({self.legacyCollisionKinds[$0]==model.customID}){self.removeLegacyObjectCollision(id)}
                    if let dictionary,!dictionary.isEmpty {
                        for (index,texture) in resources.plan.textures.enumerated() {
                            for id in Set([model.customID,model.baseID]) {
                                let key=NativeSAMPObjectMaterials.TextureRequest(model:id,dictionary:dictionary.lowercased(),texture:texture.name.lowercased())
                                if let previous=self.legacyTextureSources[key],previous != model.txd.checksum {
                                    self.legacyTextureConflicts.insert(key);self.legacyExactTextures.removeValue(forKey:key)
                                }else if !self.legacyTextureConflicts.contains(key) {
                                    self.legacyTextureSources[key]=model.txd.checksum
                                    self.legacyExactTextures[key] = .init(image:resources.textures[index],sampler:nil,containsTransparency:texture.containsTransparentPixels)
                                }
                            }
                        }
                        self.legacyMaterialOwner?.reset()
                    }
                    self.legacyModelBytes=self.legacyModelBytes-old+bytes
                    completion(.success(()))
                }catch{completion(.failure(error))}
            }
        }
    }
    private func resolvedLegacyMaterial(_ material:NativeSAMPObjects.Material)throws->NativeSAMPObjectMaterials.Resolved {
        if legacyMaterialOwner==nil {
            var limits=NativeSAMPObjectMaterials.Limits();limits.cacheBytes=32*1024*1024
            legacyMaterialOwner=try .init(device:device,limits:limits,textureResolver:{[weak self] request in
                guard let self else{return nil}
                let key=NativeSAMPObjectMaterials.TextureRequest(model:request.model,dictionary:request.dictionary.lowercased(),texture:request.texture.lowercased())
                if self.legacyTextureConflicts.contains(key){throw NativeSAMPObjectMaterials.Failure.unresolvedTexture(request.dictionary,request.texture)}
                if let texture=self.legacyExactTextures[key]{self.legacyTextureUse[key]=ProcessInfo.processInfo.systemUptime;return texture}
                self.loadLegacyDictionary(key);return nil
            })
        }
        return try legacyMaterialOwner!.resolve(material)
    }
    private func loadLegacyDictionary(_ request:NativeSAMPObjectMaterials.TextureRequest) {
        let now=ProcessInfo.processInfo.systemUptime
        guard legacyTextureLoads.count<2,!legacyTextureLoads.contains(request),(legacyTextureRetries[request] ?? 0)<=now,
              request.dictionary.utf8.count<=128,!request.dictionary.isEmpty,
              request.dictionary.utf8.allSatisfy({(48...57).contains($0)||(65...90).contains($0)||(97...122).contains($0)||$0==45||$0==95}),
              let server else{return}
        legacyTextureLoads.insert(request);let epoch=legacyAssetEpoch
        // Only the owner's exact raw dictionary path is considered. Server
        // strings cannot supply paths, hosts or a similarly named dictionary.
        NativeResourceTransport.dataTask(with:server.path("game/\(request.dictionary).txd")){[weak self]data,response,_ in
            let result:Result<NativeRenderWareTXD.Texture,Error>=Result {
                guard (response as?HTTPURLResponse)?.statusCode==200,let data,data.count<=64*1024*1024 else{throw NativeSAMPObjectMaterials.Failure.unresolvedTexture(request.dictionary,request.texture)}
                let dictionary=try NativeRenderWareTXD.decode(data)
                guard let texture=dictionary.textures.first(where:{$0.lookupName==request.texture.lowercased()})else{throw NativeSAMPObjectMaterials.Failure.unresolvedTexture(request.dictionary,request.texture)}
                return texture
            }
            DispatchQueue.main.async {
                guard let self,self.legacyAssetEpoch==epoch else{return}
                self.legacyTextureLoads.remove(request)
                do {
                    let source=try result.get()
                    let bytes=source.mipLevels.compactMap(\.rgba8).reduce(0){$0+$1.count}
                    guard bytes<=32*1024*1024 else{throw NativeSAMPObjectMaterials.Failure.limit}
                    while self.legacyExternalTextureBytes.count>=128 || self.legacyExternalTextureBytes.values.reduce(0,+)+bytes>32*1024*1024 {
                        guard let oldest=self.legacyExternalTextureBytes.keys.min(by:{(self.legacyTextureUse[$0] ?? 0)<(self.legacyTextureUse[$1] ?? 0)})else{throw NativeSAMPObjectMaterials.Failure.limit}
                        self.legacyExternalTextureBytes.removeValue(forKey:oldest);self.legacyExactTextures.removeValue(forKey:oldest);self.legacyTextureUse.removeValue(forKey:oldest)
                    }
                    let plan=NativeRenderWareModel.Plan(geometries:[],textures:[source],instances:[],draws:[],diagnostics:[],meshByteCount:0,textureByteCount:bytes)
                    let resource=try NativeRenderWareModel.Uploaded(plan:plan,device:self.device)
                    self.legacyExactTextures[request] = .init(image:resource.textures[0],sampler:nil,containsTransparency:source.containsTransparentPixels)
                    self.legacyExternalTextureBytes[request]=bytes;self.legacyTextureUse[request]=now
                    self.legacyMaterialOwner?.reset()
                }catch{self.legacyTextureRetries[request]=now+30}
            }
        }.resume()
    }
    private func drawLegacyObjects(encoder:MTLRenderCommandEncoder,matrix:simd_float4x4,eye:SIMD3<Float>) {
        refreshLegacyStockReferences()
        guard let snapshot=legacyObjectSnapshot(at:ProcessInfo.processInfo.systemUptime)else{return}
        for draw in snapshot.draws {
            guard let model=legacyModels[draw.object.model],legacyModelApplies(draw.object.model) else {
                if (1...19999).contains(draw.object.model){continue}
                if legacyMissingObjects.insert(draw.object.model).inserted{onStatus?("OBJECT MODEL \(draw.object.model) NEEDS ITS ORIGINAL RENDERWARE ASSETS")};continue
            }
            if (1...19999).contains(draw.object.model),!legacyStockObjectReady(draw.object){continue}
            guard let pipelines=legacyModelPipelines else{continue}
            if let definition=legacyModelDefinitions[draw.object.model] {
                let hour=Int(gameHour)%24,on=Int(definition.timeOn),off=Int(definition.timeOff)
                if on != off && !(on<off ? hour>=on && hour<off:hour>=on || hour<off){continue}
            }
            let position=SIMD3(draw.transform.columns.3.x,draw.transform.columns.3.y,draw.transform.columns.3.z)
            if draw.object.drawDistance>0,simd_distance(eye,position)>draw.object.drawDistance{continue}
            do {for index in model.plan.draws.indices {
                let packet=model.plan.draws[index],instance=model.plan.instances[packet.instance]
                let geometry=model.plan.geometries[instance.geometry],slot=geometry.parts[packet.part].material
                var overrides=NativeRenderWareModel.DrawOverrides()
                if let slot=UInt8(exactly:slot),let material=draw.object.materials[slot] {
                    do{try resolvedLegacyMaterial(material).apply(to:&overrides)}catch{
                        let key="\(draw.object.id):\(slot):\(material.hashValue)"
                        if legacyMaterialErrors.insert(key).inserted{onStatus?("SERVER OBJECT MATERIAL UNAVAILABLE: \(error)")}
                    }
                }
                try model.encode(drawIndex:index,encoder:encoder,pipelines:pipelines,viewProjection:matrix,modelTransform:draw.transform,overrides:overrides)
            }}catch{if legacyMissingObjects.insert(draw.object.model).inserted{onStatus?("OBJECT RENDER FAILED: \(error)")}}
        }
        encoder.setRenderPipelineState(pipeline);encoder.setDepthStencilState(depth)
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
                if passiveCameraTrace != nil{passiveCameraRay=nil}
                gameCameraFrame = gameCamera.followVehicle(input,delta:Float(step),look:cameraLookDirection,nowMilliseconds:now*1000)
            } else if !driving {
                gameCamera.setDirection(heading:heading,pitch:cameraPitch)
                let cameraAiming=aiming && canMaintainFootAim
                gameCameraFrame=gameCamera.followFoot(.init(position:camera,actorHeading:actorHeading,weapon:equippedWeapon,
                    aiming:cameraAiming,crouching:crouching,holdingLedge:climb != nil || swimController.hauled != nil,parachuting:personalFlight.chuting,
                    sight:cameraAiming ? gameCamera.sightForWeapon(equippedWeapon):nil,
                    planarSpeed:Float(hypot(currentFootVelocity.x,currentFootVelocity.z))),delta:Float(step),look:cameraLookDirection)
            } else {gameCameraFrame=nil}
        }
        let defaultDistance: Float = driving ? 11 : 4.5
        let fallbackEye = camera+SIMD3<Float>(-sin(heading)*defaultDistance,-cos(heading)*defaultDistance,driving ? 4.5 : 2.4)
        let normal=NativeSAMPGameCamera.Pose(eye:gameCameraFrame?.source ?? fallbackEye,
            target:gameCameraFrame?.target ?? (camera+SIMD3(sin(heading)*2,cos(heading)*2,1.2)))
        var owner=legacyGameCamera
        do {
            let sampled=try owner.sample(at:now,normal:normal,subjectProvider:{[weak self] subject,mode in
                self?.legacySubjectFrame(subject,mode:mode,delta:delta,now:now)
            })
            legacyGameCamera=owner;legacyCameraSample=sampled
            if sampled.diagnostics != legacyCameraDiagnostics {
                legacyCameraDiagnostics=sampled.diagnostics
                if !sampled.diagnostics.isEmpty{onStatus?("SERVER CAMERA: \(sampled.diagnostics)")}
            }
        }catch{legacyCameraSample=nil;onStatus?("SERVER CAMERA UNAVAILABLE: \(error)")}
        let pose=legacyCameraSample?.pose ?? normal,eye=pose.eye,target=pose.target
        if legacyCameraSample?.active == true{loadNearby()}
        let viewMatrix = Self.lookAt(eye:eye,target:target,up:pose.up)
        let forward = -SIMD3(viewMatrix.columns.0.z,viewMatrix.columns.1.z,viewMatrix.columns.2.z)
        let right = SIMD3(viewMatrix.columns.0.x,viewMatrix.columns.1.x,viewMatrix.columns.2.x)
        let up = SIMD3(viewMatrix.columns.0.y,viewMatrix.columns.1.y,viewMatrix.columns.2.y)
        let weather = regionalWeather.pick(automatic: automaticWeather && !returningToRegionalWeather,
            epochMilliseconds: Date().timeIntervalSince1970*1000+weatherClockShiftMilliseconds,position: SIMD2(eye.x,eye.y),
            manualFrom: weatherFrom,manualTo: weatherTo,manualBlend: manualBlend,delta: delta)
        let sampledWeatherFrom = weather.from,sampledWeatherTo = weather.to,blend = weather.blend
        roadWetness = ([8,16].contains(sampledWeatherFrom) ? 1-blend : 0)+([8,16].contains(sampledWeatherTo) ? blend : 0)
        let indoors = isInterior
        atmosphereAir = indoors ? 0 : eye.z < 900 ? min(1,atmosphereAir+delta) : max(0,atmosphereAir-delta)
        conditions = environment?.sample(weatherFrom: sampledWeatherFrom,to: sampledWeatherTo,blend: blend,hour: hour,altitude: eye.z)
        let planes = gameCamera.projection(air: atmosphereAir,farClip: conditions?.farClip ?? 25000)
        if let recorder=passiveCameraTrace {
            func array(_ v:SIMD3<Float>)->[Float]{[v.x,v.y,v.z]}
            let subject=nativeVehicleTransform.map{matrix in (0..<4).flatMap{column in (0..<4).map{matrix[column][$0]}}}
            recorder.submit(.init(camera:nil,ray:nil,draw:.init(monotonicMilliseconds:now*1000,eye:array(eye),target:array(target),
                nearPlane:planes.near,farPlane:planes.far,verticalFov:gameCameraFrame?.verticalFov ?? 55.41293,aspect:aspect,
                legacyCameraOverride:legacyCameraSample?.active == true,subjectTransform:subject)))
        }
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
        encoder.setDepthStencilState(depth)
        drawWorldMeshes(matrix: matrix,encoder: encoder)
        particleDrawDelta=Double(delta)
        deferredVehicleSurfaces=[]
        drawActors(encoder: encoder,matrix: matrix)
        let transparentVehicles=deferredVehicleSurfaces ?? [];deferredVehicleSurfaces=nil
        drawLegacyObjects(encoder:encoder,matrix:matrix,eye:eye)
        encodeWorldAndVehicleSurfaces(vehicles:transparentVehicles,encoder:encoder)
        deferredWorldSurfaces.removeAll(keepingCapacity:true)
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

    private func drawWorldMeshes(matrix: simd_float4x4, encoder: MTLRenderCommandEncoder) {
        deferredWorldSurfaces.removeAll(keepingCapacity:true)
        encoder.setRenderPipelineState(worldPipeline)
        defer {
            encoder.setDepthBias(0,slopeScale: 0,clamp: 0)
            encoder.setRenderPipelineState(pipeline)
        }
        for (name,mesh) in meshes where name.hasPrefix("t") {
            encoder.setDepthBias(0.0005,slopeScale: 0,clamp: 0)
            draw(mesh: mesh,cellSize: 64,matrix: matrix,encoder: encoder)
        }
        encoder.setDepthBias(0,slopeScale: 0,clamp: 0)
        for name in activeDetails {if let mesh=meshes[name] {
            if stageWorldSurface(name:name,mesh:mesh,matrix:matrix,encoder:encoder){continue}
            if name==worldSharpName,worldSharpSource==fixedCJSourceIdentity(),let images=worldSharpGPU,
               let worldSharpPipeline,(try? images.bind(encoder:encoder,queue:queue)) != nil {
                encoder.setRenderPipelineState(worldSharpPipeline)
            }else{encoder.setRenderPipelineState(worldPipeline)}
            draw(mesh:mesh,cellSize:128,matrix:matrix,encoder:encoder)
        }}
    }

    /// Admit the split only against the exact current source and geometry.
    private func stageWorldSurface(name:String,mesh:Mesh,matrix:simd_float4x4,encoder:MTLRenderCommandEncoder)->Bool {
        let source=fixedCJSourceIdentity()
        guard worldSharpSource==source,let base=worldSharpBase[name],base.source==source,
              let entry=worldSharpManifest?.entries[name],entry.layers==base.layers,
              let plan=NativeWorldDrawPlan(indexCount:mesh.indexCount,triangles:entry.triangles,blend:entry.blend),
              base.indices==mesh.indexCount,worldSurfacePipelines["base.solid"] != nil,
              worldSurfacePipelines["base.clear"] != nil else{return false}
        var native:NativeWorldSharpTextures?
        if name==worldSharpName,let images=worldSharpGPU,
           worldSurfacePipelines["sharp.solid"] != nil,worldSurfacePipelines["sharp.clear"] != nil {native=images}
        var uniforms=Uniforms(viewProjection:matrix,settings:SIMD4(Float(mesh.atlas.width),Float(mesh.atlas.height),night,128))
        configureEnvironment(&uniforms)
        if plan.solid.count>0 {
            guard encodeWorldSurface(mesh:mesh,range:plan.solid,uniforms:uniforms,native:native,clear:false,encoder:encoder)else{return false}
        }
        if plan.clear.count>0 {
            deferredWorldSurfaces.append(.init(mesh:mesh,range:plan.clear,uniforms:uniforms,native:native,
                depth:NativeVehicleRig.projectedDepth(base.center,matrix:matrix)))
        }
        return true
    }
    @discardableResult private func encodeWorldSurface(mesh:Mesh,range:NativeWorldDrawPlan.Range,uniforms:Uniforms,
        native:NativeWorldSharpTextures?,clear:Bool,encoder:MTLRenderCommandEncoder)->Bool {
        guard range.start>=0,range.count>0,range.count<=mesh.indexCount,range.start<=mesh.indexCount-range.count,
              range.start%3==0,range.count%3==0 else{return false}
        var images=native
        if let candidate=images,(try? candidate.bind(encoder:encoder,queue:queue))==nil{images=nil}
        let key=(images==nil ? "base.":"sharp.")+(clear ? "clear":"solid")
        guard let state=worldSurfacePipelines[key]else{return false}
        var current=uniforms,phase:UInt32=clear ? 1:0
        encoder.setRenderPipelineState(state);encoder.setDepthStencilState(clear ? markerDepth:depth)
        encoder.setDepthBias(0,slopeScale:0,clamp:0)
        encoder.setVertexBuffer(mesh.vertices,offset:0,index:0)
        encoder.setVertexBytes(&current,length:MemoryLayout<Uniforms>.stride,index:1)
        encoder.setFragmentBytes(&current,length:MemoryLayout<Uniforms>.stride,index:1)
        encoder.setFragmentBytes(&phase,length:MemoryLayout<UInt32>.stride,index:3)
        encoder.setFragmentTexture(mesh.atlas,index:0)
        encoder.drawIndexedPrimitives(type:.triangle,indexCount:range.count,indexType:.uint32,indexBuffer:mesh.indices,indexBufferOffset:range.start*4)
        return true
    }
    private func encodeWorldAndVehicleSurfaces(vehicles:[TransparentVehicleDraw],encoder:MTLRenderCommandEncoder) {
        let world=deferredWorldSurfaces
        // Stable ties retain creation order: world cells precede actor parts.
        let depths=world.map(\.depth)+vehicles.map(\.depth)
        for index in NativeVehicleRig.farToNear(depths) {
            if index<world.count {
                let packet=world[index]
                encodeWorldSurface(mesh:packet.mesh,range:packet.range,uniforms:packet.uniforms,native:packet.native,clear:true,encoder:encoder)
            }else{encodeTransparentVehicles([vehicles[index-world.count]],encoder:encoder)}
        }
        encoder.setDepthBias(0,slopeScale:0,clamp:0)
        encoder.setRenderPipelineState(pipeline);encoder.setDepthStencilState(depth)
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

    /// Wire appearance determines rendering role. Optional registry IDs remain
    /// optional: local/free-play driver rows have a vehicle code without one.
    private static func remoteAppearanceIsDriver(code:String,ridingVehicleID:String?)->Bool {
        ridingVehicleID==nil && !code.hasPrefix("s")
    }
    private static func remoteAppearanceIsFoot(code:String,ridingVehicleID:String?)->Bool {
        ridingVehicleID==nil && code.hasPrefix("s")
    }
    private static func remoteDriverRenderKey(playerID:String,vehicleID:String?)->String {
        // Length-tagging keeps arbitrary registry IDs distinct from the
        // ID-less player fallback. These are private cache keys, not wire IDs.
        if let vehicleID{return "vehicle:\(vehicleID.utf8.count):\(vehicleID)"}
        return "player:\(playerID.utf8.count):\(playerID)"
    }
    private func recordRemoteAnimationPackets() {
        let now = ProcessInfo.processInfo.systemUptime
        let wallOffset = Date().timeIntervalSince1970-now
        let live = Set(remotePlayers.filter{Self.remoteAppearanceIsDriver(code:$0.code,ridingVehicleID:$0.ridingVehicleID)}.map(\.id))
        remoteBikeSamples = remoteBikeSamples.filter { live.contains($0.key) }
        for player in remotePlayers where Self.remoteAppearanceIsDriver(code:player.code,ridingVehicleID:player.ridingVehicleID) {
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

    private func bindVehicleTextures(_ textures:NativeVehicleTextures,name:String,slot:Int,encoder:MTLRenderCommandEncoder)->Bool {
        guard vehicleTextures[name] === textures else{return false}
        do{try textures.bind(slot:slot,encoder:encoder,queue:queue);return true}
        catch{
            // A failed family retries as one unit. Never sample its staging
            // image with an old atlas shader or keep a permanently blank rig.
            if vehicleTextures[name] === textures {
                vehicleTextures.removeValue(forKey:name);vehicleRigs.removeValue(forKey:name)
                vehicleRigMeshes.removeValue(forKey:name);vehicleWaterMasks.removeValue(forKey:name)
                actorMeshes.removeValue(forKey:name);actorRetryAfter[name]=Date().addingTimeInterval(2)
                onStatus?("VEHICLE TEXTURES WILL RETRY")
            }
            return false
        }
    }
    private func encodeNativeVehicle(frame:NativeVehicleRig.Frame,textures:NativeVehicleTextures,name:String,mesh:Mesh,
                                     uniforms:Uniforms,matrix:simd_float4x4,encoder:MTLRenderCommandEncoder) {
        for part in frame.draws {
            guard bindVehicleTextures(textures,name:name,slot:part.texture,encoder:encoder)else{break}
            var current=uniforms;current.viewProjection=matrix*part.transform
            var material=SIMD4<Float>(part.layerOverride,part.emissive ? 1:0,part.scorched ? 0.14:1,part.alphaTest)
            var paint=part.paint
            encoder.setVertexBytes(&current,length:MemoryLayout<Uniforms>.stride,index:1)
            encoder.setFragmentBytes(&current,length:MemoryLayout<Uniforms>.stride,index:1)
            encoder.setFragmentBytes(&material,length:MemoryLayout<SIMD4<Float>>.stride,index:2)
            encoder.setFragmentBytes(&paint,length:MemoryLayout<SIMD4<Float>>.stride,index:3)
            encoder.drawIndexedPrimitives(type:.triangle,indexCount:part.count,indexType:.uint32,indexBuffer:mesh.indices,indexBufferOffset:part.start*4)
        }
    }
    private func encodeTransparentVehicles(_ packets:[TransparentVehicleDraw],encoder:MTLRenderCommandEncoder) {
        // Archived transparent vehicle materials retain depthWrite=true. Phase
        // ordering and stable back-to-front compositing are the missing policy.
        encoder.setDepthStencilState(depth)
        for index in NativeVehicleRig.farToNear(packets.map(\.depth)) {
            let packet=packets[index],part=packet.part,mesh=packet.mesh
            var uniforms=packet.uniforms
            var material=SIMD4<Float>(part.layerOverride,part.emissive ? 1:0,part.scorched ? 0.14:1,part.alphaTest)
            encoder.setRenderPipelineState(packet.pipeline)
            encoder.setVertexBuffer(mesh.vertices,offset:0,index:0)
            encoder.setVertexBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1)
            encoder.setFragmentBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1)
            if let bind=packet.bindTextures {guard bind(encoder)else{continue}}
            else{encoder.setFragmentTexture(mesh.atlas,index:0)}
            encoder.setFragmentBytes(&material,length:MemoryLayout<SIMD4<Float>>.stride,index:2)
            // Every vehicle packet owns this ABI even after a world clear
            // draw has bound a four-byte phase at fragment slot3.
            if packet.painted || packet.bindTextures != nil {
                var paint=part.paint
                encoder.setFragmentBytes(&paint,length:MemoryLayout<SIMD4<Float>>.stride,index:3)
            }
            encoder.drawIndexedPrimitives(type:.triangle,indexCount:part.count,indexType:.uint32,indexBuffer:mesh.indices,indexBufferOffset:part.start*4)
        }
        encoder.setRenderPipelineState(pipeline);encoder.setDepthStencilState(depth)
    }
    private func drawActors(encoder: MTLRenderCommandEncoder, matrix: simd_float4x4) {
        pedAtlasDemand.removeAll(keepingCapacity:true)
        remoteSuspensionRayBudget = 64
        let riderTime = riderMonotonicNow()
        let riderDelta = lastRiderDraw > 0 ? min(0.1,max(0,riderTime-lastRiderDraw)) : 0
        lastRiderDraw = riderTime
        let riderPoseInterval=riderPoseClock.interval(at:riderTime,
            active:UIApplication.shared.applicationState == .active && view.window != nil)
        let riderIDs = Set(remotePlayers.filter { Self.remoteAppearanceIsDriver(code:$0.code,ridingVehicleID:$0.ridingVehicleID) || $0.ridingVehicleID != nil }.map(\.id))
        remoteRiderAnimations = remoteRiderAnimations.filter { riderIDs.contains($0.key) }
        remoteRiderPlayback=remoteRiderPlayback.filter{riderIDs.contains($0.key)}
        remoteRiderActions=remoteRiderActions.filter{riderIDs.contains($0.key)}
        remoteRiderCapture=remoteRiderCapture.filter{riderIDs.contains($0.key)}
        remoteRiderPrevious=remoteRiderPrevious.filter{riderIDs.contains($0.key)}
        riderDoorHolds.removeAll(keepingCapacity:true)
        flightAudioVoices.removeAll(keepingCapacity:true)
        remoteBikeAnimations = remoteBikeAnimations.filter { riderIDs.contains($0.key) }
        let footIDs = Set(remotePlayers.filter { Self.remoteAppearanceIsFoot(code:$0.code,ridingVehicleID:$0.ridingVehicleID) }.map(\.id))
        remoteFootAnimations = remoteFootAnimations.filter { footIDs.contains($0.key) }
        var sampledRemoteFootIDs=Set<String>()
        remoteBikeFrames.removeAll(keepingCapacity:true)
        let flightIDs=Set(remotePlayers.map(\.id)).union(["own"])
        flightCanopyPoses=flightCanopyPoses.filter{flightIDs.contains($0.key)}
        flightCanopyLanded=flightCanopyLanded.filter{flightIDs.contains($0.key)}
        var modelInstances: [(String, SIMD3<Float>, Float, Float, String, Double, Int, VehicleDrawContext?, Int?)] = []
        var transparentVehicleDraws:[TransparentVehicleDraw]=[]
        // Vehicle source, appearance and physical transform stay with each
        // occurrence; coordinates are never used as an ownership key.
        var driverPose: NativeSkeletalActor.Pose?
        // Each occurrence refers to its own draw-local override, including
        // co-located players with the same skin. No position key is needed.
        var actorOverrides: [ActorPoseOverride] = []
        func appendPed(_ name:String,_ at:SIMD3<Float>,_ heading:Float,_ pitch:Float,_ clip:String,_ elapsed:Double,_ weapon:Int,
                       pose:NativeSkeletalActor.Pose? = nil,transform:simd_float4x4? = nil,original:Bool = false,flight:NativeFlightAnimation.Frame? = nil,identity:String? = nil,ownFoot:Bool = false,canopySamples:[NativeFlightAnimation.Canopy?] = []) {
            let occurrence = actorOverrides.count
            actorOverrides.append(.init(pose:pose,transform:transform,original:original,flight:flight,identity:identity,ownFoot:ownFoot,canopySamples:canopySamples))
            modelInstances.append((name,at,heading,pitch,clip,elapsed,weapon,nil,occurrence))
        }
        if driving,isPassenger,!legacySpectating,let seat=passengerSeat,let frame=passengerFrame,
           let ped=pedModels[String(localSkin)] {
            loadActor(ped)
            if let actor=skeletalActors[ped],let library=skeletalLibrary,let definition=riderDefinitions?.models[activeVehicleModel],definition.seats.indices.contains(seat) {
                let sourceSeat=definition.seats[seat]
                if ownRiderPlayback==nil,let playback=NativeRiderPlayback(definition:definition,seat:seat,library:library) {
                    ownRiderSide=sourceSeat.side==0 ? 1:sourceSeat.side
                    playback.enter(at:riderTime,side:ownRiderSide,doorOpen:Self.sharedDoorOpen(sourceSeat.door,damage:frame.vehicle.damage) ? 1:0);ownRiderPlayback=playback
                }
                if let sample=ownRiderPlayback?.update(interval:riderPoseInterval,input:.init(dead:health<=0)) {
                    if let capture=sample.capture {
                        switch capture {
                        case .current:ownRiderCapture=ownRiderPrevious
                        case .sample(let value):ownRiderCapture=actor.riderPose(frame:value.pose,library:library,figurePosition:SIMD3<Float>(value.anchor))
                        }
                    }
                    let pose=actor.riderPose(frame:sample.sample.pose,library:library,figurePosition:SIMD3<Float>(sample.sample.anchor),figureTurn:Float(sample.turn),previous:sample.transitioning ? ownRiderCapture:nil,transition:sample.transition)
                    ownRiderPrevious=pose;ownRiderFeet=actor.riderFeet(pose:pose,model:frame.transform,origin:Float(definition.origin))
                    if let id=currentVehicleID,let part=sample.doorPart{riderDoorHolds[id,default:[:]][part]=sample.doorOpen}
                    appendPed(ped,frame.vehicle.position,frame.vehicle.heading,0,"",0,0,pose:pose,transform:frame.transform,original:true)
                    if sample.state == .stood,let ready=pendingVehicleExit{pendingVehicleExit=nil;DispatchQueue.main.async(execute:ready)}
                }
            }
        }else if driving && !legacySpectating {
            let code = ownVehicleAppearanceCode
            if let name = actorName(code: code) {
                let context=ownVehicleDrawContext(name:name,code:code)
                modelInstances.append((name,camera,heading,vehiclePitch,"",0,0,context,nil))
                if let seat = riderDefinitions?.models[activeVehicleModel]?.seats.first?.position ?? vehicleSeats[name], let ped = pedModels[String(localSkin)] {
                    // A pose cannot be the prerequisite for loading its actor:
                    // eviction or fast boarding would otherwise hide it forever.
                    loadActor(ped)
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
                            if time>3{playback.sit(at:riderTime)}else{playback.enter(at:riderTime,side:ownRiderSide,doorOpen:door ? 1:0)}
                            ownRiderPlayback=playback
                        }
                        if let frame=ownRiderPlayback?.update(interval:riderPoseInterval,input:input) {
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
        } else if !driving && !legacySpectating && !scopedCameraHidesPlayer,let name = pedModels[String(localSkin)] {
            let original = footAnimationFrame != nil && skeletalActors[name] != nil
            let pose = skeletalActors[name].flatMap { actor in skeletalLibrary.flatMap { library in
                footAnimationFrame.flatMap { actor.originalPose(blends:$0.blends,library:library,aim:$0.aim,hiddenBones:$0.hiddenBones,figurePitch:$0.figurePitch,figureRoll:$0.figureRoll,legBend:$0.legBend) }
            } }
            let handWeapon = climb != nil || footAnimationFrame?.handWeaponVisible == false ? 0:effectiveWireWeapon
            appendPed(name,camera,actorHeading,swimmingPitch,ownClip,ownClipTime,handWeapon,pose:pose,original:original,flight:footAnimationFrame?.flight,identity:"own",ownFoot:true)
        }
        for player in remotePlayers {
            // A passenger's public carText is still a pedestrian; draw its
            // source seat inside the referenced car instead of a second walker.
            if let vehicleID = player.ridingVehicleID {
                guard let shared=sharedVehicleFrame(id:vehicleID),simd_distance(shared.vehicle.position,scenePosition)<130,
                      let ped=pedModels[String(player.skin)]else{continue}
                let code=shared.vehicle.code
                guard let actor=skeletalActors[ped],let library=skeletalLibrary else {loadActor(ped);continue}
                let model=String(code.split(separator:".").first ?? "")
                guard let definition=riderDefinitions?.models[model],definition.seats.indices.contains(player.ridingSeat),
                      let seat=definition.seats[player.ridingSeat].position else {continue}
                let animator=remoteRiderAnimations[player.id] ?? NativeRiderAnimation(duration:{ [weak self] in self?.skeletalLibrary?.duration(of:$0) })
                remoteRiderAnimations[player.id]=animator
                let input=NativeRiderAnimation.Input(dead:player.life<=0),playbackKey="\(vehicleID):\(model):\(player.ridingSeat):\(ObjectIdentifier(actor))"
                let playback:NativeRiderPlayback?
                if let cached=remoteRiderPlayback[player.id],cached.0==playbackKey{playback=cached.1}
                else {
                    playback=NativeRiderPlayback(definition:definition,seat:player.ridingSeat,library:library)
                    if let playback{remoteRiderPlayback[player.id]=(playbackKey,playback);remoteRiderActions[player.id]=nil;remoteRiderCapture[player.id]=nil;remoteRiderPrevious[player.id]=nil}
                }
                let pose:NativeSkeletalActor.Pose
                if let playback {
                    let action=player.action&63,sourceSeat=definition.seats[player.ridingSeat]
                    if remoteRiderActions[player.id] != action {
                        remoteRiderActions[player.id]=action
                        switch action {
                        case 1,3:playback.enter(at:riderTime,side:action==1 ? -1:1)
                        case 2,4:playback.leave(at:riderTime,side:action==2 ? -1:1,leaveOpen:sourceSeat.door.map{NativeVehicleDamage.decode(shared.vehicle.damage)?.open[$0] ?? false} ?? false)
                        default:if playback.state != .entering{playback.sit(at:riderTime)}
                        }
                    }
                    if let frame=playback.update(interval:riderPoseInterval,input:input) {
                        if let capture=frame.capture {
                            switch capture {
                            case .current:remoteRiderCapture[player.id]=remoteRiderPrevious[player.id]
                            case .sample(let value):remoteRiderCapture[player.id]=actor.riderPose(frame:value.pose,library:library,figurePosition:SIMD3<Float>(value.anchor))
                            }
                        }
                        pose=actor.riderPose(frame:frame.sample.pose,library:library,figurePosition:SIMD3<Float>(frame.sample.anchor),figureTurn:Float(frame.turn),previous:frame.transitioning ? remoteRiderCapture[player.id]:nil,transition:frame.transition)
                        remoteRiderPrevious[player.id]=pose
                        if let part=frame.doorPart{riderDoorHolds[vehicleID,default:[:]][part]=frame.doorOpen}
                    }else{pose=actor.riderPose(frame:animator.update(delta:riderDelta,configuration:definition.configuration(seat:player.ridingSeat),input:input),library:library,figurePosition:seat)}
                }else{pose=actor.riderPose(frame:animator.update(delta:riderDelta,configuration:definition.configuration(seat:player.ridingSeat),input:input),library:library,figurePosition:seat,figureTurn:Float(definition.seats[player.ridingSeat].turn ?? 0))}
                appendPed(ped,shared.vehicle.position,shared.vehicle.heading,0,"",0,0,pose:pose,transform:shared.transform,original:true)
                continue
            }
            guard simd_distance(player.position,scenePosition)<130 else{continue}
            guard let name=actorName(code:player.code) else {continue}
            if Self.remoteAppearanceIsFoot(code:player.code,ridingVehicleID:player.ridingVehicleID) {
                let footPosition=remoteSupportPosition(player) ?? player.position
                var pose:NativeSkeletalActor.Pose?
                var original=false
                var flight:NativeFlightAnimation.Frame?
                var canopySamples:[NativeFlightAnimation.Canopy?] = []
                var handWeapon=player.weapon
                if let actor=skeletalActors[name],let library=skeletalLibrary,let definitions=footDefinitions {
                    let animator:NativeRemoteFootAnimation
                    if let cached=remoteFootAnimations[player.id],cached.0==name {animator=cached.1}
                    else {
                        animator=NativeRemoteFootAnimation(library:library,style:definitions.style(model:legacyPedStyles[name] ?? name,library:library),weapons:footWeaponDefinitions)
                        remoteFootAnimations[player.id]=(name,animator)
                    }
                    let groundContext=NativeRemoteMeleeContext.nearFlooredTarget(attackerID:player.id,
                        position:SIMD3<Double>(player.position),heading:Double(player.heading),
                        own:.init(id:"own",position:SIMD3<Double>(camera),walking:!driving,
                            down:footAnimator?.floored == true,life:Double(health)),
                        people:remotePlayers.map{.init(id:$0.id,position:SIMD3<Double>($0.position),
                            walking:Self.remoteAppearanceIsFoot(code:$0.code,ridingVehicleID:$0.ridingVehicleID),
                            down:$0.down != 0,life:Double($0.life))})
                    let state=NativeRemoteFootAnimation.Snapshot(position:SIMD3<Double>(footPosition),heading:Double(player.heading),
                        velocity:SIMD3<Double>(player.velocity),movement:Double(player.movementRatio),airborne:player.airborne,crouching:player.crouching,
                        weapon:player.weapon,aim:player.aim.map(Double.init),action:player.action,shots:player.shotCount,life:Double(player.life),
                        armour:Double(player.armour),down:player.down,paused:player.paused,pitch:Double(player.pitch),roll:Double(player.roll),script:player.scriptAnimation,
                        nearFlooredTarget:groundContext)
                    sampledRemoteFootIDs.insert(player.id)
                    if let frame=animator.update(at:riderTime,
                        active:UIApplication.shared.applicationState == .active && view.window != nil,snapshot:state) {
                    if !frame.handWeaponVisible { handWeapon=0 }
                    flight=frame.flight
                    canopySamples=frame.canopySamples
                    if !animator.hasUnsupportedFlight {
                        pose=actor.originalPose(blends:frame.blends,library:library,aim:frame.aim,hiddenBones:frame.hiddenBones,figurePitch:frame.figurePitch,figureRoll:frame.figureRoll,legBend:frame.legBend)
                        original=true
                    }
                    }
                }
                if (10...16).contains(player.action & 63) || (20...25).contains(player.action & 63) { handWeapon=0 }
                appendPed(name,footPosition,player.heading,player.pitch,player.animation,riderTime-player.animationStarted,handWeapon,pose:pose,original:original,flight:flight,identity:player.id,canopySamples:canopySamples)
                continue
            }
            let context=remoteVehicleDrawContext(name:name,player:player)
            modelInstances.append((name,player.position,player.heading,player.pitch,"",0,0,context,nil))
            guard let ped=pedModels[String(player.skin)] else {continue}
            guard let actor=skeletalActors[ped],let library=skeletalLibrary else {loadActor(ped);continue}
            let model=String(player.code.split(separator:".").first ?? "")
            guard let source=riderDefinitions?.models[model],let sourceSeat=source.seats.first,let place=sourceSeat.position else {continue}
            let animator=remoteRiderAnimations[player.id] ?? NativeRiderAnimation(duration:{ [weak self] in self?.skeletalLibrary?.duration(of:$0) })
            remoteRiderAnimations[player.id]=animator
            var input=NativeRiderAnimation.Input(speed:Double(player.speed),steer:Double(player.steer),dead:player.life<=0)
            if source.astride,let samples=remoteBikeSamples[player.id] {
                let bike=remoteBikeAnimations[player.id] ?? NativeRemoteBikeAnimation();remoteBikeAnimations[player.id]=bike
                let frame=bike.update(model:model,maxLean:source.bike?["maxLean"],now:riderTime,delta:riderDelta,sample:samples.0,previous:samples.1,
                    owner:.init(appearance:player.code,vehicleID:player.vehicleID,asset:actorMeshes[name].map{ObjectIdentifier($0.vertices)}))
                remoteBikeFrames[player.id]=frame
                input.lean=frame.lean;input.tuck=frame.tuck;input.pedal=frame.pedal;input.crank=frame.crank;input.hop=frame.hop
            }
            var pose:NativeSkeletalActor.Pose
            let playbackKey="\(player.vehicleID ?? ""):\(model):0:\(ObjectIdentifier(actor))"
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
                    case 1,3,5,6:playback.enter(at:riderTime,side:action==1 || action==5 ? -1:1,jack:action==5 || action==6)
                    case 2,4:playback.leave(at:riderTime,side:action==2 ? -1:1,leaveOpen:sourceSeat.door.map{NativeVehicleDamage.decode(player.vehicleDamage)?.open[$0] ?? false} ?? false)
                    default:if playback.state != .entering{playback.sit(at:riderTime)}
                    }
                }
                if let frame=playback.update(interval:riderPoseInterval,input:input) {
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
            let car = player.vehicleID.flatMap{sharedVehicleFrame(id:$0)?.transform} ?? Self.translation(player.position) * Self.rotationZ(-player.heading) *
                Self.rotationX(player.pitch) * Self.rotationY(player.roll) *
                Self.translation(SIMD3(0,0,vehicleModelOrigin(player.code)))
            appendPed(ped,player.position,player.heading,0,"",0,0,pose:pose,transform:car,original:true)
        }
        for (id,cached) in remoteFootAnimations where !sampledRemoteFootIDs.contains(id) {
            cached.1.resetDisplayClock()
        }
        let drivenVehicleIDs = Set(remotePlayers.compactMap(\.vehicleID))
        for projectile in weaponEffects.projectiles {
            let direction = atan2(projectile.velocity.x,projectile.velocity.y)
            let pitch = atan2(projectile.velocity.z,hypot(projectile.velocity.x,projectile.velocity.y))
            modelInstances.append((projectile.model,projectile.position,direction,pitch,"",0,0,nil,nil))
        }
        var parkedTrainCandidates:[RemoteVehicle] = []
        for source in remoteVehicles where (isPassenger || source.id != currentVehicleID) && !drivenVehicleIDs.contains(source.id) {
            let vehicle=predictedVehicle(source)
            guard simd_distance(vehicle.position,camera)<130,let name=actorName(code:vehicle.code) else{continue}
            let context=parkedVehicleDrawContext(name:name,vehicle:vehicle)
            modelInstances.append((name,vehicle.position,vehicle.heading,vehicle.pitch,"",0,0,context,nil))
            parkedTrainCandidates.append(vehicle)
        }
        var trainLayoutIDs:Set<String> = []
        func appendCarriages(_ carriages:[NativeGroundVehicle.Carriage],identity:String?,own:Bool=false) {
            for (index,carriage) in carriages.enumerated() {
                guard let name=actorName(code:carriage.model) else{continue}
                let context=carriageVehicleDrawContext(name:name,model:carriage.model,transform:carriage.transform,identity:identity,own:own,index:index)
                modelInstances.append((name,carriage.position,0,0,"",0,0,context,nil))
            }
        }
        if driving,let carriages=groundVehicle?.carriages {
            appendCarriages(carriages,identity:currentVehicleID,own:true)
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
        let pedAtlasDrawSource=pedAtlasFamilies.isEmpty ? nil:fixedCJSourceIdentity()
        for (name, position, angle, pitch, clip, elapsed, weapon, vehicleContext, occurrence) in modelInstances {
            let queued = occurrence.map { actorOverrides[$0] }
            let mesh = (vehicleContext != nil ? vehicleRigMeshes[name]:nil) ?? actorMeshes[name]
            let fixedPlayer=name=="null" ? fixedCJ?.ready:nil
            let customPed=fixedPlayer?.gpu.uploaded ?? legacyPedModels[name]
            guard mesh != nil || customPed != nil else { loadActor(name); continue }
            if pedAtlasFamilies[name] != nil {
                guard let bound=pedAtlasGPU[name],bound.source==pedAtlasDrawSource,bound.family==pedAtlasFamilies[name] else{loadActor(name);continue}
            }
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
            transform=Self.vehicleDrawTransform(transform,context:vehicleContext)
            if let exact=queued?.transform {transform=exact}
            var uniforms = Uniforms(viewProjection: matrix * transform,
                                    settings: SIMD4(Float(mesh?.atlas.width ?? 1), Float(mesh?.atlas.height ?? 1), night, 128))
            configureEnvironment(&uniforms)
            let opacity:Float = queued?.identity == "own" ? ownCameraVisibility.opacity:1
            uniforms.tintColor.w *= opacity
            encoder.setDepthStencilState(opacity<1 ? markerDepth:depth)
            let locomotion = queued?.ownFoot == true && name == pedModels[String(localSkin)] && position == camera && !driving && actionTimeRemaining > 0 &&
                !swimming && health > 0 ? locomotionClip : nil
            let wire = clip.split(separator: "/")
            let loops: Bool? = wire.count >= 2 ? (wire.count < 3 || wire[2] == "l") : nil
            let sampledPose = skeletalActors[name].flatMap { actor in skeletalLibrary.flatMap {
                return actor.pose(clip: clip, elapsed: elapsed, library: $0,
                           locomotion: locomotion, locomotionElapsed: locomotionTime, looping: loops)
            } }
            let pose = queued?.pose ?? sampledPose
            if let customPed {
                guard let pose,let pipelines=fixedPlayer?.gpu.pipelines ?? legacyPedPipelines else{continue}
                var overrides=NativeRenderWareModel.DrawOverrides();overrides.tint.w=opacity
                do {for index in customPed.plan.model.draws.indices {
                    try customPed.encode(drawIndex:index,pose:pose,encoder:encoder,pipelines:pipelines,viewProjection:matrix,worldTransform:transform,overrides:overrides)
                }}catch{onStatus?("CUSTOM CHARACTER DRAW FAILED: \(error)");continue}
            } else if let mesh {
            if let pose, let actor = skeletalActors[name], let skeletalPipeline {
                if let bound=pedAtlasGPU[name] {guard let selected=bound.native == nil ? pedAtlasSkeletalPipeline:pedNativeSkeletalPipeline else{continue};encoder.setRenderPipelineState(selected)}
                else{encoder.setRenderPipelineState(skeletalPipeline)}
                actor.bind(pose: pose, encoder: encoder)
            } else if let frames = actorAnimations[name]?.sample(clip: clip, elapsed: elapsed) {
                if let bound=pedAtlasGPU[name] {guard let selected=bound.native == nil ? pedAtlasAnimatedPipeline:pedNativeAnimatedPipeline else{continue};encoder.setRenderPipelineState(selected)}
                else{encoder.setRenderPipelineState(animatedPipeline)}
                encoder.setVertexBuffer(frames.0, offset: 0, index: 2)
                encoder.setVertexBuffer(frames.1, offset: 0, index: 3)
                var blend = frames.2
                encoder.setVertexBytes(&blend, length: MemoryLayout<Float>.stride, index: 4)
            } else {
                if let bound=pedAtlasGPU[name] {guard let selected=bound.native == nil ? pedAtlasPipeline:pedNativePipeline else{continue};encoder.setRenderPipelineState(selected)}
                else{encoder.setRenderPipelineState(pipeline)}
            }
            if let layout=pedAtlasGPU[name] {encoder.setFragmentBuffer(layout.layout,offset:0,index:2)}
            encoder.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            let native=pedAtlasGPU[name]?.native
            func drawActorRange(count:Int,offset:Int)throws {
                guard count>=0,offset>=0,count<=mesh.indexCount,offset<=mesh.indexCount-count else{throw NativePedTextureArrays.Failure.indexBuffer}
                if let native {try native.encode(indices:mesh.indices,encoder:encoder,queue:queue,range:offset..<offset+count)}
                else{encoder.drawIndexedPrimitives(type:.triangle,indexCount:count,indexType:.uint32,indexBuffer:mesh.indices,indexBufferOffset:offset*4)}
            }
            do {
                if native==nil{encoder.setFragmentTexture(mesh.atlas,index:0)}
                if clip.isEmpty,let context=vehicleContext,let rig=vehicleRigs[name],vehicleRigMeshes[name] != nil {
                    let completeFrame=vehicleRigFrame(position:position,modelTransform:transform,rig:rig,context:context)
                    // Keep opaque hulls in the normal actor phase. Transparent
                    // materials must wait until every opaque rider has drawn.
                    let frame=completeFrame.opaque
                    let nativeTextures=vehicleTextures[name]
                    if rig.document.version==3 {
                        guard nativeTextures != nil,let vehicleNativePipeline else{continue}
                        encoder.setRenderPipelineState(vehicleNativePipeline)
                    }else if rig.hasDynamicPaint {
                        guard let vehiclePaintPipeline else{onStatus?("VEHICLE PAINT SHADER IS UNAVAILABLE");continue}
                        encoder.setRenderPipelineState(vehiclePaintPipeline)
                    }else{encoder.setRenderPipelineState(vehiclePipeline ?? pipeline)}
                    let alphaPipeline=rig.document.version==3 ? vehicleNativePipeline:rig.hasDynamicPaint ? vehiclePaintPipeline:(vehiclePipeline ?? pipeline)
                    if let alphaPipeline {
                        for part in completeFrame.transparent {
                            var partUniforms=uniforms
                            partUniforms.viewProjection=matrix*transform*part.transform
                            transparentVehicleDraws.append(.init(mesh:mesh,part:part,uniforms:partUniforms,pipeline:alphaPipeline,
                                painted:rig.hasDynamicPaint,depth:NativeVehicleRig.projectedDepth(part.sortCenter,matrix:partUniforms.viewProjection),
                                bindTextures:nativeTextures.map{textures in { [weak self] encoder in
                                    guard let self else{return false}
                                    return self.bindVehicleTextures(textures,name:name,slot:part.texture,encoder:encoder)
                                }}))
                        }
                    }
                    if let nativeTextures {
                        encodeNativeVehicle(frame:frame,textures:nativeTextures,name:name,mesh:mesh,uniforms:uniforms,matrix:matrix*transform,encoder:encoder)
                    }else{for part in frame.draws {
                        uniforms.viewProjection=matrix*transform*part.transform
                        var material=SIMD4<Float>(part.layerOverride,part.emissive ? 1:0,part.scorched ? 0.14:1,part.alphaTest)
                        encoder.setVertexBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1)
                        encoder.setFragmentBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1)
                        encoder.setFragmentBytes(&material,length:MemoryLayout<SIMD4<Float>>.stride,index:2)
                        if rig.hasDynamicPaint {
                            var paint=part.paint
                            encoder.setFragmentBytes(&paint,length:MemoryLayout<SIMD4<Float>>.stride,index:3)
                        }
                        encoder.drawIndexedPrimitives(type:.triangle,indexCount:part.count,indexType:.uint32,indexBuffer:mesh.indices,indexBufferOffset:part.start*4)
                    }}
                    if let vehicleMaskPipeline {
                        encoder.setRenderPipelineState(vehicleMaskPipeline)
                        for (node,mask) in vehicleWaterMasks[name] ?? [] {
                            let m=frame.matrices[node],local=simd_float4x4(columns:(SIMD4<Float>(m[0]),SIMD4<Float>(m[1]),SIMD4<Float>(m[2]),SIMD4<Float>(m[3])))
                            draw(mesh:mask,cellSize:128,matrix:matrix*transform*local,encoder:encoder)
                        }
                    }
                } else if clip.isEmpty, let parts = actorParts[name], !parts.isEmpty {
                    let speed=vehicleContext?.own?.speed ?? 0
                    for part in parts {
                        let pivot = SIMD3<Float>(part.pivot[0], part.pivot[1], part.pivot[2])
                        var local = matrix_identity_float4x4
                        if let wheel = part.wheel {
                            let index = wheel.contains("lf_") ? 0 : wheel.contains("lb_") || wheel.contains("lr_") ? 1 : wheel.contains("rf_") ? 2 : 3
                            let state=Self.legacyVehicleWheel(index:index,front:wheel.contains("f_dummy"),context:vehicleContext,time:Float(ProcessInfo.processInfo.systemUptime))
                            local = Self.translation(SIMD3(0,0,state.offset)) * Self.translation(pivot) *
                                Self.rotationZ(state.turn) * Self.rotationX(state.spin) * Self.translation(-pivot)
                        } else if part.name.hasPrefix("static_prop") && speed != 0 {
                            local = Self.translation(pivot) * Self.rotationY(Float(ProcessInfo.processInfo.systemUptime) * 35) * Self.translation(-pivot)
                        } else if part.name.hasPrefix("static_rotor") && speed != 0 {
                            local = Self.translation(pivot) * Self.rotationZ(Float(ProcessInfo.processInfo.systemUptime) * 35) * Self.translation(-pivot)
                        }
                        uniforms.viewProjection = matrix * transform * local
                        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                        try drawActorRange(count:part.count,offset:part.start)
                    }
                } else {
                    try drawActorRange(count:mesh.indexCount,offset:0)
                }
            }catch{
                clearPedAtlas(name);actorRetryAfter[name]=Date().addingTimeInterval(2)
                pedAtlasError(name,"NATIVE PED TEXTURE DRAW FAILED: \(name)");continue
            }
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
            if let queued,queued.flight != nil || !queued.canopySamples.isEmpty,
               let identity=queued.identity,let pose,let actor=skeletalActors[name] {
                drawFlightAttachments(queued.flight ?? .init(),identity:identity,actor:actor,pose:pose,transform:transform,matrix:matrix,encoder:encoder,opacity:opacity,canopySamples:queued.canopySamples)
            }
            encoder.setDepthStencilState(depth)
        }
        if deferredVehicleSurfaces != nil {deferredVehicleSurfaces=transparentVehicleDraws}
        else{encodeTransparentVehicles(transparentVehicleDraws,encoder:encoder)}
        let visible = Set(modelInstances.map { $0.0 } + modelInstances.compactMap { weaponModels[String($0.6)] })
        for name in Array(pedAtlasLoads.keys) where !visible.contains(name) && !pedAtlasDemand.contains(name) {
            pedAtlasLoads.removeValue(forKey:name)?.request?.cancel();pedAtlasAdmission.removeValue(forKey:name)
        }
        if actorMeshes.count > 32 {
            actorMeshes = actorMeshes.filter { visible.contains($0.key) }
            actorAnimations = actorAnimations.filter { visible.contains($0.key) }
            skeletalActors = skeletalActors.filter { visible.contains($0.key) || legacyPedModels[$0.key] != nil || ($0.key=="null" && fixedCJ?.ready != nil) }
            actorAttachments = actorAttachments.filter { visible.contains($0.key) }
            actorParts = actorParts.filter { visible.contains($0.key) }
            pedAtlasGPU=pedAtlasGPU.filter{visible.contains($0.key)}
            vehicleRigs=vehicleRigs.filter{visible.contains($0.key)}
            vehicleRigMeshes=vehicleRigMeshes.filter{visible.contains($0.key)}
            vehicleTextures=vehicleTextures.filter{visible.contains($0.key)}
            vehicleWaterMasks=vehicleWaterMasks.filter{visible.contains($0.key)}
        }
    }

    private func loadParticleEffects() {
        guard !particleLoading,particleRenderer==nil,let server else{return}
        particleLoading=true
        let group=DispatchGroup(),lock=NSLock();var metadata:Data?,definitions:Data?
        for (name,url) in [("metadata",server.path("game/native/effects/fx-textures.json")),("definitions",server.path("game/world/fx.json"))] {
            group.enter();NativeResourceTransport.dataTask(with:url){data,response,_ in
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
                loaded.enter();NativeResourceTransport.dataTask(with:server.path("game/native/effects/"+sheet.file)){data,response,_ in
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
            NativeResourceTransport.dataTask(with:server.path("game/native/models/"+name)){data,response,_ in
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
                                       transform:simd_float4x4,matrix:simd_float4x4,encoder:MTLRenderCommandEncoder,opacity:Float=1,canopySamples:[NativeFlightAnimation.Canopy?] = []) {
        if flightCanopyMesh==nil || flightJetMesh==nil {loadFlightAssets()}
        let targets=canopySamples.isEmpty ? [flight.canopy]:canopySamples
        for target in targets {
            if let canopy=target,flightCanopyMesh != nil,let accessory=flightCanopyActor,let library=skeletalLibrary {
                flightCanopyPoses[identity]=accessory.canopyPose(clip:canopy.clip,time:canopy.time,easing:canopy.easing,pitch:canopy.pitch,roll:canopy.roll,library:library,previous:flightCanopyPoses[identity])
                if canopy.landed && flightCanopyLanded[identity]==nil {flightCanopyLanded[identity]=transform}
                if !canopy.landed {flightCanopyLanded[identity]=nil}
            } else {flightCanopyLanded[identity]=nil}
        }
        if let canopy=flight.canopy,let posed=flightCanopyPoses[identity],let mesh=flightCanopyMesh,let accessory=flightCanopyActor,let skeletalPipeline {
            let parent=canopy.landed ? flightCanopyLanded[identity] ?? transform:transform
            var scale=matrix_identity_float4x4;scale.columns.0.x=Float(canopy.scale);scale.columns.1.y=Float(canopy.scale);scale.columns.2.z=Float(canopy.scale)
            if canopy.visible {
                encoder.setRenderPipelineState(skeletalPipeline);accessory.bind(pose:posed,encoder:encoder)
                draw(mesh:mesh,cellSize:128,matrix:matrix*parent*scale,encoder:encoder,tint:SIMD4(1,1,1,canopy.landed ? 1:opacity))
            }
        }
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

    private func vehicleRigFrame(position:SIMD3<Float>,modelTransform:simd_float4x4,rig:NativeVehicleRig,context:VehicleDrawContext)->NativeVehicleRig.Frame {
        let now=ProcessInfo.processInfo.systemUptime
        let player=context.player,parked=context.parked,own=context.own,token=context.token
        let delta=min(0.1,max(0,now-(vehicleRigTimes[token] ?? now)));vehicleRigTimes[token]=now
        var input=own?.input ?? NativeVehicleRig.Input()
        input.appearanceCode=context.appearanceCode
        if own==nil {
            let speed=Double(context.isCarriage ? context.carriageSpeed:player?.speed ?? 0)
            input.steering=Double(player?.steer ?? 0)
            var spins=vehicleRigSpins[token] ?? .zero
            let front=rig.document.joints.bike?.hubs["front"]?.radius ?? 0.36
            let rear=rig.document.joints.bike?.hubs["rear"]?.radius ?? 0.36
            spins -= SIMD2(speed*delta/front,speed*delta/rear);vehicleRigSpins[token]=spins
            input.frontSpin=spins.x;input.rearSpin=spins.y
            if player != nil {
                if rig.document.kind=="heli" {input.rotor=0.22}
                else if rig.document.kind=="plane" {input.rotor=0.18}
            }
            if let player,let bike=remoteBikeFrames[player.id] {input.lean=bike.lean;input.crank=bike.crank}
            if let kit=player?.kit {
                if kit.indices.contains(5),rig.document.joints.working != nil {input.work=Double(kit[5])*1000}
                if kit.indices.contains(5),rig.document.id==520 {input.nozzle=Double(kit[5])*5000}
                if kit.indices.contains(5),rig.document.joints.working == nil,rig.document.id != 520,((groundVehicle?.handlingFlags(String(rig.document.id)) ?? 0)&64) != 0 {input.rearSteering=Double(kit[5])}
                input.gearUp=kit.indices.contains(6) && kit[6] != 0
            }
            if let frame=context.parkedPhysical {
                input.work=frame.work
                input.rotor=frame.rotor;input.gearUp=frame.gearUp
                input.frontSpin=frame.frontSpin;input.rearSpin=frame.rearSpin
                vehicleRigSpins[token]=SIMD2(frame.frontSpin,frame.rearSpin)
                if frame.dynamic {
                    input.offsets=frame.offsets
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
            // Existing physical suspension, including working/hydraulic owners,
            // takes priority. Remote projection changes wheel locals only.
            if input.offsets.isEmpty, !context.isCarriage, simd_distance(position,camera)<120,
               let configuration=remoteSuspensionConfigurations[rig.document.id],
               let projected=NativeRemoteSuspension.sample(configuration,model:modelTransform,tyres:input.tyres,query:remoteSuspensionContact) {
                input.offsets=projected.offsets
            }
        }
        if let heldID=context.heldDoorID,let held=riderDoorHolds[heldID] {
            let doors=own != nil ? own?.doors:NativeVehicleDamage(mass:1000,flags:groundVehicle?.modelFlags(String(rig.document.id)) ?? 0,model:rig.document.id).doors
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

    private func remoteSuspensionContact(_ ray:NativeRemoteSuspension.Ray)->NativeRemoteSuspension.Contact {
        guard remoteSuspensionRayBudget>0,let vehicle=groundVehicle else{return .unavailable}
        remoteSuspensionRayBudget-=1
        let origin=SIMD3<Float>(ray.origin),direction=SIMD3<Float>(ray.direction),distance=Float(ray.distance)
        guard let coverage=NativeWorldRay.coverage(from:origin,to:origin+direction*distance,interior:isInterior,loaded:{_ in true})else{return .unavailable}
        collisionRequests.request(coverage.cells,now:ProcessInfo.processInfo.systemUptime,visible:activeDetails)
        desiredPhysicsCells=collisionRequests.retained(now:ProcessInfo.processInfo.systemUptime,visible:activeDetails)
        for name in desiredPhysicsCells {loadCollision(name:name)}
        var excluded=vehicle.otherColliders.union(vehicle.chassisColliders)
        if let queries=character?.queries{excluded.formUnion([queries.walker,queries.probe])}
        var exhausted=false
        let result=NativeWorldRay.query(from:origin,direction:direction,distance:distance,interior:isInterior,loaded:vehicle.isCellLoaded) {start,way,limit in
            // Query only authored static supports. A parked/kinematic/remote
            // chassis or a pedestrian must never become its own tire contact.
            for _ in 0..<16 {
                guard let hit=vehicle.world.queryRay(origin:SwiftRapierWorld.gtaToRapier(start),direction:SwiftRapierWorld.gtaToRapier(way),
                    distance:limit,groups:0xffff0001,excludingColliders:excluded)else{return nil}
                if let body=hit.collider.body,vehicle.world.bodyKind(body) != .fixed {excluded.insert(hit.collider.id);continue}
                return .init(distance:hit.distance,normal:SwiftRapierWorld.rapierToGTA(hit.normal))
            }
            exhausted=true;return nil
        }
        if exhausted{return .unavailable}
        switch result {
        case .unavailable:return .unavailable
        case .clear:return .clear
        case .hit(let hit):return .hit(distance:Double(hit.distance),normal:SIMD3<Double>(hit.normal))
        }
    }

    private func configureEnvironment(_ uniforms: inout Uniforms) {
        guard let conditions, !isInterior else { return }
        uniforms.fogColor = weatherSnapshot?.flash == true ? SIMD4(1,1,1,1) : conditions.skyBottom
        uniforms.fogSettings = SIMD4(conditions.fogStart,conditions.farClip,atmosphereAir,0)
    }

    private func drawEffects(encoder:MTLRenderCommandEncoder,matrix:simd_float4x4,eye:SIMD3<Float>,viewMatrix:simd_float4x4,projection:simd_float4x4,delta:Double) {
        if let effects=particleEffects,let renderer=particleRenderer {
            if originalActorBurning,!driving{effects.burst("fire",at:SIMD3<Double>(camera)+SIMD3(0,0,health>0 ? 1:0.1),delta:delta)}
            effects.update(delta:delta,brightness:1-0.6*Double(night))
            let fog=weatherSnapshot?.flash==true ? SIMD4<Float>(1,1,1,1):conditions?.skyBottom ?? SIMD4<Float>(0,0,0,1)
            renderer.draw(effects.particles,eye:eye,view:viewMatrix,projection:projection,fogColor:SIMD3(fog.x,fog.y,fog.z),fogNear:conditions?.fogStart ?? 0,fogFar:conditions?.farClip ?? 25000,fogAmount:conditions==nil || isInterior ? 0:atmosphereAir,encoder:encoder)
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

    private static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>,up referenceUp:SIMD3<Float> = SIMD3(0,0,1)) -> simd_float4x4 {
        var forward = target-eye
        if simd_length_squared(forward) == 0 { forward = SIMD3(0,1,0) }
        forward = simd_normalize(forward)
        var right = simd_cross(forward,referenceUp)
        // Three.Matrix4.lookAt perturbs its local z by 0.0001 when view and
        // up are parallel. Its local z maps to negative GTA y.
        if simd_length_squared(right) == 0 {
            forward.y += 0.0001;forward = simd_normalize(forward)
            right = simd_cross(forward,referenceUp)
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

/// Bounded bootstrap metadata only. Model/COL bytes use the shared verified
/// NativeSAMPStockAssetLoader instead of a second asset transfer engine.
private final class LegacyStockMetadataTransfer:NSObject,URLSessionDataDelegate {
    private let url:URL,maximumBytes:Int,completion:(Result<Data,Error>)->Void
    private let access:NativeStockAssetAccess?
    private let queue:OperationQueue={let value=OperationQueue();value.maxConcurrentOperationCount=1;return value}()
    private var session:URLSession?,task:URLSessionDataTask?,bytes=Data(),finished=false
    init(url:URL,maximumBytes:Int,access:NativeStockAssetAccess?=nil,completion:@escaping(Result<Data,Error>)->Void) {
        self.url=url;self.maximumBytes=maximumBytes;self.completion=completion;self.access=access
    }
    func start(){queue.addOperation {
        guard !self.finished else{return}
        guard (1...16*1024*1024).contains(self.maximumBytes),["http","https"].contains(self.url.scheme?.lowercased() ?? ""),
              self.url.user==nil,self.url.password==nil,self.url.query==nil,self.url.fragment==nil else {
            self.finish(.failure(NativeSAMPStockAssetLoader.Failure.invalidURL));return
        }
        do {
            if let prepared=try NativeStockAssetAccess.preparedData(for:self.url,maximumBytes:self.maximumBytes) {
                self.finish(.success(prepared));return
            }
        } catch {
            // Installed misses/corruption must stay local failures. Only an
            // explicit development cache miss may reach the bounded HTTP sink.
            self.finish(.failure(error));return
        }
        let configuration=URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage=nil;configuration.httpShouldSetCookies=false;configuration.urlCredentialStorage=nil;configuration.urlCache=nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest=15;configuration.timeoutIntervalForResource=30
        self.session=URLSession(configuration:configuration,delegate:self,delegateQueue:self.queue)
        var request=URLRequest(url:self.url);request.httpShouldHandleCookies=false
        request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
        if let cookie=self.access?.cookieHeader(for:self.url){request.setValue(cookie,forHTTPHeaderField:"Cookie")}
        self.task=self.session!.dataTask(with:request);self.task?.resume()
    }}
    func cancel(){queue.addOperation{self.finish(.failure(NativeSAMPStockAssetLoader.Failure.cancelled))}}
    private func finish(_ result:Result<Data,Error>) {
        guard !finished else{return};finished=true
        task?.cancel();task=nil;session?.invalidateAndCancel();session=nil;bytes=Data()
        DispatchQueue.main.async{self.completion(result)}
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,
                    completionHandler:@escaping(URLSession.ResponseDisposition)->Void) {
        guard !finished else{completionHandler(.cancel);return}
        guard let http=response as?HTTPURLResponse,http.statusCode==200,http.url==url else {
            completionHandler(.cancel);finish(.failure(NativeSAMPStockAssetLoader.Failure.http((response as?HTTPURLResponse)?.statusCode ?? 0)));return
        }
        let encoding=http.value(forHTTPHeaderField:"Content-Encoding")?.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() ?? "identity"
        guard encoding=="identity" || encoding.isEmpty else{completionHandler(.cancel);finish(.failure(NativeSAMPStockAssetLoader.Failure.encoding));return}
        guard response.expectedContentLength<0 || response.expectedContentLength<=maximumBytes else {
            completionHandler(.cancel);finish(.failure(NativeSAMPStockAssetLoader.Failure.limit("stock metadata bytes")));return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data) {
        guard !finished else{return}
        guard data.count<=maximumBytes-bytes.count else{finish(.failure(NativeSAMPStockAssetLoader.Failure.limit("stock metadata stream")));return}
        bytes.append(data)
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
        guard !finished else{return}
        if let error{finish(.failure(error))}else{finish(.success(bytes))}
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,
                    newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) {
        completionHandler(nil);finish(.failure(NativeSAMPStockAssetLoader.Failure.redirect))
    }
}
