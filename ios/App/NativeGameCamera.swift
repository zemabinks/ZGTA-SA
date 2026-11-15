import Foundation
import simd

/// Public client camera algorithms: main9737 on-foot follow, module98726 vehicle
/// cameras, and module62540 camera collision/FOV wrapper. Native GTA axes.
final class NativeGameCamera {
    struct Planes { let near: Float;let far: Float }
    struct Frame {
        let source: SIMD3<Float>
        let target: SIMD3<Float>
        let verticalFov: Float
        let heading: Float
        let pitch: Float
        let hidesPlayer: Bool
        let aimSource: SIMD3<Float>?
    }
    struct Foot {
        var position: SIMD3<Float>
        var actorHeading: Float = 0
        var weapon: Int = 0
        var aiming = false
        var crouching = false
        var holdingLedge = false
        var parachuting = false
        var sight: String?
    }
    struct Bounds {
        var maxX: Float
        var minY: Float
        var maxZ: Float
        var min: SIMD3<Float>?
        var max: SIMD3<Float>?
    }
    struct Vehicle {
        var kind = "car"
        var position: SIMD3<Float>
        var forward: SIMD3<Float>
        var right: SIMD3<Float>
        var up: SIMD3<Float>?
        /// The original camera consumes velocity/50 and angularVelocity/50.
        var moveSpeed = SIMD3<Float>.zero
        var turnSpeed = SIMD3<Float>.zero
        var wheels = 4
        var bounds: Bounds
        var heightAboveRoad: Float = 0
        /// Original model ped_frontseat frame in local GTA axes.
        var eye: SIMD3<Float>?
    }
    struct Sight: Decodable { let first: Double; let least: Double; let most: Double }
    private struct Document: Decodable {
        let vehicleProfiles: [String:[Double]]
        let vehicleDistances: [String:[Double]]
        let vehicleAngles: [String:[Double]]
        let cinematic: [String:[Double]]
        let footDistances: [Double]
        let footSights: [String:Sight]
        let footWeaponFov: [[Double]]
        let weaponSights: [String:String]
    }
    enum Error: Swift.Error { case invalidTable }
    private let persistViews: Bool
    private var table: Document?
    private var request: URLSessionDataTask?
    var trace: ((SIMD3<Float>,SIMD3<Float>,Float) -> Float?)?
    /// Streaming boundaries are not solid surfaces. They may be closer than
    /// the original solid-wall minimum and must never be crossed by that clamp.
    var unavailableDistance: ((SIMD3<Float>,SIMD3<Float>,Float) -> Float?)?
    private(set) var heading: Float = 0
    private(set) var pitch: Float = -0.15
    private(set) var footZoom = 2
    private(set) var vehicleView = 2
    private var nearPlane: Float = 2,farPlane: Float = 60000
    private var currentVerticalFov: Double = 45
    private var lastSource = SIMD3<Double>.zero
    private var shakeGain: Double = 0,shakeSince: Double = 0
    private var footDistance: Double = 1.5
    private var footAim = false,oldFootAim = false
    private var footNeedsReset = false
    private var aimShare: Double = 0,aimStart: Double = 0,aimClock: Double = 0,targetFov: Double = 70
    private var crouchDrop: Double = 0,aimDrop: Double = 0
    private var ledgeClock: Double = 0
    private var feetAnchor = SIMD3<Double>.zero,previousFeet = SIMD3<Double>.zero
    private var chaseSource = SIMD3<Double>.zero,chaseBack = SIMD3<Double>.zero
    private var chase = false,previousDistance: Double = 0
    private var footAimSource: SIMD3<Double>?
    private var sight: String?
    private var sightTarget: [String:Double] = [:],sightFov: [String:Double] = [:]
    private var sightVelocity: Double = 0,sightClock: Double = 0
    private var carKind = "car",carZoom = 2
    private var carDistance: Double = 1
    private var carElevation: Double = 0,carAzimuth: Double = 0
    private var carPitchVelocity: Double = 0,carYawVelocity: Double = 0,carFov: Double = 70
    private var oldElevation: Double = -9999,oldAzimuth: Double = -9999,manualHold: Double = 0
    private var carReset = true,carLookReset = false
    private var carFarSource = SIMD3<Double>.zero,carOldSource = SIMD3<Double>.zero
    private var carLook = SIMD2<Double>.zero
    private var cockpitYaw: Double = 0,cockpitPitch: Double = 0,cockpitHold: Double = 0
    private var cinematicSource: SIMD3<Double>?
    private var cinematicSide = 0
    var isLoaded: Bool { table != nil }
    var footTurning: Float { Float(sight.flatMap { sightFov[$0] }.map { $0/80 } ?? ((70+(targetFov-70)*aimShare)/70)) }
    var vehicleViewName: String { ["near","middle","far","eye","bumper","cinematic"][vehicleView-1] }
    init(persistViews: Bool = true) {
        self.persistViews = persistViews
        if persistViews {
            let foot = UserDefaults.standard.integer(forKey: "world.view.foot"),car = UserDefaults.standard.integer(forKey: "world.view.car")
            footZoom = (1...3).contains(foot) ? foot : 2
            vehicleView = (1...6).contains(car) ? car : 2;carZoom = min(vehicleView,3)
        }
    }
    convenience init(data: Data) throws { self.init(persistViews: false);try install(data) }
    deinit { request?.cancel() }
    func load(server: ServerAddress,completion: (() -> Void)? = nil) {
        request?.cancel()
        request = URLSession.shared.dataTask(with: server.path("game/native/camera.json")) { [weak self] data,response,_ in
            guard let data,(response as? HTTPURLResponse)?.statusCode == 200 else { return }
            DispatchQueue.main.async { guard let self,(try? self.install(data)) != nil else { return };completion?() }
        };request?.resume()
    }
    private func install(_ data: Data) throws {
        let value = try JSONDecoder().decode(Document.self,from: data)
        guard ["car","bike","heli","plane"].allSatisfy({ key in
            value.vehicleProfiles[key]?.count == 15 && value.vehicleDistances[key]?.count == 3 && value.vehicleAngles[key]?.count == 3
        }),value.footDistances.count == 3,["scope","camera","rocket"].allSatisfy({ value.footSights[$0] != nil }),
              value.cinematic["ground"]?.count == 4,value.cinematic["air"]?.count == 4,
              value.footWeaponFov.allSatisfy({ $0.count == 2 }),
              (Array(value.vehicleProfiles.values).flatMap{$0}+Array(value.vehicleDistances.values).flatMap{$0}+Array(value.vehicleAngles.values).flatMap{$0}+value.footDistances).allSatisfy(\.isFinite) else { throw Error.invalidTable }
        table = value;footDistance = value.footDistances[footZoom-1];carDistance = value.vehicleDistances[carKind]![carZoom-1]
        sightTarget = value.footSights.mapValues(\.first);sightFov = sightTarget
    }
    /// Main-loop projection for active on-foot/driving gameplay. The original
    /// camera also retains a one-metre far-plane update deadband.
    func projection(air: Float,farClip: Float) -> Planes {
        let near: Float = 0.15,far: Float = air >= 1 ? farClip : 25000
        if abs(near-nearPlane) > 0.15*nearPlane || abs(far-farPlane) > 1 { nearPlane = near;farPlane = far }
        return Planes(near: nearPlane,far: farPlane)
    }
    func sightForWeapon(_ weapon: Int) -> String? { table?.weaponSights[String(weapon)] }
    func setDirection(heading: Float,pitch: Float) {
        guard heading.isFinite, pitch.isFinite else { return }
        self.heading = heading;self.pitch = pitch
    }
    /// Clear queued deltas when an input source disappears. This deliberately
    /// preserves the current view and the player's chosen zoom.
    func cancelLookInput() { carLook = .zero }
    /// A mode/teleport boundary must not reuse an old foot chase/aim anchor.
    func resetFoot(heading: Float, pitch: Float) {
        setDirection(heading: heading, pitch: max(-1.4835299, min(.pi / 4, pitch)))
        footNeedsReset = true; chase = false; previousDistance = 0; ledgeClock = 0
        footAim = false; oldFootAim = false; aimShare = 0; aimStart = 0; aimClock = 0
        crouchDrop = 0; aimDrop = 0; footAimSource = nil; sight = nil; sightVelocity = 0; sightClock = 0
        if let table { footDistance = table.footDistances[footZoom - 1] }
        cancelLookInput()
    }
    /// Keep the direction currently on screen on vehicle exit. Angles differing
    /// by a whole turn represent the same view; choose the nearest equivalent.
    @discardableResult func resumeFoot(from frame: Frame?, fallbackHeading: Float, fallbackPitch: Float) -> SIMD2<Float> {
        let reference = fallbackHeading.isFinite ? fallbackHeading : 0
        let wanted = frame?.heading ?? reference
        let target = wanted.isFinite ? reference + Self.shortestAngle(wanted - reference) : reference
        resetFoot(heading: target, pitch: frame?.pitch ?? fallbackPitch)
        return SIMD2(heading, pitch)
    }
    static func shortestAngle(_ angle: Float) -> Float {
        guard angle.isFinite else { return 0 }
        return Float(atan2(sin(Double(angle)), cos(Double(angle))))
    }
    func cycleFootZoom() { setFootZoom(footZoom%3+1) }
    func setFootZoom(_ value: Int) { footZoom = max(1,min(3,value));if persistViews { UserDefaults.standard.set(footZoom,forKey: "world.view.foot") } }
    func cycleVehicleView() { setVehicleView(vehicleView%6+1) }
    func setVehicleView(_ value: Int) { let view = max(1,min(6,value));guard view != vehicleView else { return };vehicleView = view;if vehicleView <= 3 {carZoom = vehicleView};resetCockpit();if persistViews { UserDefaults.standard.set(vehicleView,forKey: "world.view.car") } }
    func setVehicleKind(_ value: String) {
        guard let table else { return };let kind = table.vehicleProfiles[value] != nil ? value : "car"
        if kind != carKind {carKind = kind;carDistance = table.vehicleDistances[kind]![carZoom-1]}
    }
    func resetVehicle() { carReset = true; resetCockpit() }
    /// Entering a different vehicle is a lifecycle boundary, beyond the public
    /// camera helper's reset flag. Old manual deltas must not affect the new car.
    func beginVehicle() {
        carReset = true; carLookReset = false; manualHold = 0; carLook = .zero
        carYawVelocity = 0; carPitchVelocity = 0; oldElevation = -9999; oldAzimuth = -9999
        resetCockpit()
    }
    private func resetCockpit() { cockpitYaw = 0;cockpitPitch = 0;cockpitHold = 0;cinematicSource = nil }
    /// Browser pointer deltas are CSS pixels; positive y moves the view down.
    func lookPixels(x: Float,y: Float,driving: Bool = false) {
        guard x.isFinite, y.isFinite else { return }
        if driving { carLook += SIMD2(Double(x),Double(y));return }
        heading += x*0.0022
        let lower: Float = sight != nil ? -1.55 : footAim ? -1.5533431 : -1.4835299
        let upper: Float = sight != nil ? 1.55 : .pi/4
        pitch = max(lower,min(upper,pitch-y*0.0022))
    }
    func lookTouch(x: Float,y: Float,driving: Bool = false,sensitivity: Float = 1,aimSensitivity: Float = 1,inverted: Bool = false) {
        guard sensitivity.isFinite, aimSensitivity.isFinite, sensitivity >= 0, aimSensitivity >= 0 else { return }
        let scale = sensitivity*(driving ? 1.5 : 2.3)*(driving ? 1 : footTurning*(footAim || sight != nil ? aimSensitivity : 1))
        lookPixels(x: x*scale,y: y*scale*(inverted ? -1 : 1),driving: driving)
    }
    func lookAnalog(x: Float,y: Float,delta: Float,driving: Bool = false,sensitivity: Float = 1,inverted: Bool = false) {
        guard x.isFinite, y.isFinite, delta.isFinite, delta > 0, sensitivity.isFinite, sensitivity >= 0 else { return }
        let scale = 3.2*sensitivity*(0.3+0.7*hypot(x,y))*(driving ? 1 : footTurning*(footAim || sight != nil ? 0.5 : 1))*delta/0.0022
        lookPixels(x: x*scale,y: y*scale*0.6*(inverted ? -1 : 1),driving: driving)
    }
    func zoomSight(_ delta: Float) {
        guard let sight,let config = table?.footSights[sight] else { return }
        let factor = abs(delta) > 1 ? 1.084 : pow(1.0255,0.07*50)
        sightTarget[sight] = Self.clamp((sightTarget[sight] ?? config.first)*(delta < 0 ? 1/factor : factor),config.least,config.most)
    }

    /// Main9737's held look-behind is a render-time override after normal
    /// follow, restored before the next update. Keep chase/aim and input yaw
    /// advancing normally; never feed the returned reverse heading into them.
    func followFoot(_ input: Foot,delta: Float,look: String? = nil) -> Frame? {
        guard let normal=processFoot(input,delta:delta) else{return nil}
        guard look == "behind",!input.aiming else{return normal}
        let focus=Self.double(input.position)+SIMD3(0,0,1.4)
        var direction=focus-lastSource;direction.z=0
        let distance=simd_length(direction)
        guard distance>0.05 else{return normal}
        direction /= distance
        let hit=collision(focus,direction,distance)
        let contact=hit.flatMap{$0.isFinite && $0>=0 && $0<=distance ? $0:nil}
        // The archived solid-wall minimum is .6m. Missing streamed geometry
        // remains a boundary and may shorten that minimum, as in normal follow.
        let reach=availableReach(focus,direction,max(0.6,(contact ?? distance)-0.3),padding:0.3)
        var source=focus+direction*reach;source.z=lastSource.z
        let displaySource=Self.float(source),displayTarget=Self.float(focus)
        // An unavailable boundary can reduce reach below the archived .6m
        // minimum. At equal view/focus heights Float conversion may then make
        // eye==target; retain the ordinary view rather than return a frame
        // that needs the renderer's generic direction fallback.
        guard Self.finite(displaySource),Self.finite(displayTarget),
              simd_length_squared(displayTarget-displaySource)>0 else{return normal}
        let facing=Self.normalized(focus-source)
        // Do not call frame(): lastSource belongs to normal follow, just as the
        // original wrapper restores its saved camera after drawing this view.
        return Frame(source:displaySource,target:displayTarget,verticalFov:normal.verticalFov,
            heading:Float(atan2(facing.x,facing.y)),pitch:Float(asin(Self.clamp(facing.z,-1,1))),
            hidesPlayer:normal.hidesPlayer,aimSource:normal.aimSource)
    }

    private func processFoot(_ input: Foot,delta: Float) -> Frame? {
        guard let table, delta.isFinite, delta >= 0, Self.finite(input.position), input.actorHeading.isFinite else { return nil }
        let dt = footNeedsReset ? 0 : Double(delta), feet = Self.double(input.position), speed = 50 * dt
        footNeedsReset = false
        footAim = input.aiming && input.sight == nil
        if input.sight != sight {
            sight = table.footSights[input.sight ?? ""] != nil ? input.sight : nil
            if let sight,let config = table.footSights[sight] { sightTarget[sight] = config.first;sightFov[sight] = config.first;sightVelocity = 0;sightClock = 0 }
        }
        ledgeClock = input.holdingLedge ? 0.6 : max(0,ledgeClock-dt)
        feetAnchor = ledgeClock > 0 && dt > 0 ? feetAnchor+(feet-feetAnchor)*min(1,9*dt) : feet
        let moving = dt > 0 && simd_length_squared(previousFeet-feet) > pow(0.05*dt,2)
        previousFeet = feet
        let drop: Double = input.crouching ? (moving ? 0.2 : 0.7) : 0,aimCrouch: Double = input.crouching ? 0.35 : 0
        if footAim != oldFootAim || dt <= 0 {
            oldFootAim = footAim;if !footAim { footAimSource = nil };aimStart = aimShare;aimClock = 0;crouchDrop = drop;aimDrop = aimCrouch
            if footAim { targetFov = input.weapon == 33 ? 70 : table.footWeaponFov.first(where: { Int($0[0]) == input.weapon })?[1] ?? 70 }
        }
        aimClock += dt
        aimShare = footAim ? aimStart+(1-aimStart)*(0.5-0.5*cos(Double.pi*min(1,aimClock/0.4))) : aimStart*(0.5+0.5*cos(Double.pi*Self.clamp((aimClock/0.35-0.1)/0.9,0,1)))
        if footAim {
            let desired = table.footWeaponFov.first(where: { Int($0[0]) == input.weapon })?[1] ?? 70
            targetFov = targetFov > desired ? max(desired,targetFov-speed) : min(desired,targetFov+speed)
            aimDrop += (aimCrouch-aimDrop)*min(1,0.13*speed)
        } else { crouchDrop += (drop-crouchDrop)*min(1,0.1*speed) }
        if let sight {
            sightClock = min(sightClock+50*dt,10)
            while sightClock >= 1 {
                sightClock -= 1
                let difference = (sightTarget[sight] ?? 70)-(sightFov[sight] ?? 70),target = 0.5*difference
                if abs(difference) <= 0.5 { sightVelocity = 0;continue }
                sightVelocity += (target-sightVelocity)*0.25
                if target < 0 && target > sightVelocity || target > 0 && target < sightVelocity { sightVelocity = target }
                sightFov[sight,default: 70] += sightVelocity
            }
        }
        let fov = Self.verticalFov(sight.flatMap{sightFov[$0]} ?? (aimShare > 0 ? 70+(targetFov-70)*aimShare : 70))
        let forward = SIMD3<Double>(sin(Double(heading))*cos(Double(pitch)),cos(Double(heading))*cos(Double(pitch)),sin(Double(pitch)))
        if sight != nil {
            let source = feetAnchor+SIMD3(0,0,1.62-crouchDrop)
            return frame(source: source,target: source+forward*10,fov: fov,hidesPlayer: true)
        }
        var focus = feetAnchor+SIMD3(0,0,1.6)
        let back = -forward,wanted = table.footDistances[footZoom-1],rate = 6*dt
        footDistance = footDistance < wanted ? min(wanted,footDistance+rate) : max(wanted,footDistance-rate)
        let distance = footDistance+(footZoom == 3 && input.parachuting ? 4 : 2)
        var follow = distance
        if aimShare > 0 || dt <= 0 || chase && simd_length_squared(focus-chaseSource) > 100 { chase = false }
        var flat = SIMD3(forward.x,forward.y,0)
        if simd_length_squared(flat) < 1e-6 { chase = false } else { flat = simd_normalize(flat) }
        var elevation: Double = 0
        if chase {
            let separation = simd_distance(focus,chaseSource)
            if separation < distance && distance > 2 { follow = max(distance > previousDistance ? distance : 2,separation) }
            let direction = Self.normalized(focus-chaseBack)
            elevation = Self.clamp(asin(Self.clamp(direction.z,-1,1)),-1.4835299,Double.pi/4)
        }
        previousDistance = distance
        let chasing = flat*cos(elevation)+SIMD3(0,0,sin(elevation))
        chaseSource = focus-chasing*follow;chaseBack = focus-chasing*max(follow,4)
        chase = aimShare <= 0 && dt > 0 && simd_length_squared(flat) > 0.5
        focus.z -= crouchDrop
        var reach = follow
        if aimShare > 0 || footAim {
            let zoom = Self.clamp((70-targetFov)/20,0,1),narrow = Self.clamp((70-targetFov)/35,0,1)
            let right = Self.normalized(SIMD3(forward.y,-forward.x,0))
            let facing = Self.clamp(cos(Double(heading-input.actorHeading)),0,1)
            let shoulder = (0.2+0.1*narrow)*(1-acos(facing)/(Double.pi/2))
            var aimPoint = feetAnchor+SIMD3(0,0,1.5+0.1*zoom-aimDrop)
            let hit = collision(aimPoint,right,shoulder+0.25)
            aimPoint += right*min(shoulder,hit.map{max(0,$0-0.25)} ?? shoulder)
            let aimedDistance = 1+1.6*cos(asin(Self.clamp(back.z,-1,1)))
            if footAim {
                let aimHit = collision(aimPoint,back,aimedDistance+0.25)
                let actual = aimHit.map{max(0.4,$0-0.25)} ?? aimedDistance
                footAimSource = aimPoint+back*availableReach(aimPoint,back,actual,padding:0.25)
            }
            focus += (aimPoint-focus)*aimShare
            reach = follow+(aimedDistance-follow)*aimShare
        }
        let hit = collision(focus,back,reach+0.25)
        let actual = availableReach(focus,back,hit.map {max(0.4,$0-0.25)} ?? reach,padding:0.25)
        let source = focus+back*actual
        return frame(source: source,target: source+forward*10,fov: fov,hidesPlayer: false,aimSource: footAimSource)
    }

    /// Exact blast/collision camera shake envelope from the vehicle wrapper.
    func shake(at point: SIMD3<Float>,strength: Float,nowMilliseconds: Double = ProcessInfo.processInfo.systemUptime*1000) {
        let remaining = shakeGain*exp(-2.5*(nowMilliseconds-shakeSince)/1000)
        shakeGain = max(remaining,Double(strength)*max(0,1-simd_distance(lastSource,Self.double(point))/100))
        shakeSince = nowMilliseconds
    }
    func followVehicle(_ input: Vehicle,delta: Float,look: String? = nil,
                       nowMilliseconds: Double = ProcessInfo.processInfo.systemUptime*1000,
                       random: () -> Double = { Double.random(in: 0..<1) }) -> Frame? {
        guard let frame = processVehicle(input,delta: delta,look: look) else { return nil }
        let amplitude = shakeGain > 0 ? shakeGain*exp(-2.5*(nowMilliseconds-shakeSince)/1000) : 0
        if amplitude > 0.002 {
            let x = random()-0.5,z = random()-0.5,y = -(random()-0.5)
            let source = Self.double(frame.source)+SIMD3(x,y,z)*amplitude
            lastSource = source
            let direction = Self.normalized(Self.double(frame.target)-source)
            return Frame(source: Self.float(source),target: frame.target,verticalFov: frame.verticalFov,
                heading: Float(atan2(direction.x,direction.y)),pitch: Float(asin(Self.clamp(direction.z,-1,1))),
                hidesPlayer: frame.hidesPlayer,aimSource: frame.aimSource)
        }
        shakeGain = 0;return frame
    }
    private func processVehicle(_ input: Vehicle,delta: Float,look: String? = nil) -> Frame? {
        guard let table, delta.isFinite, delta >= 0, Self.finite(input.position), Self.finite(input.forward), Self.finite(input.right),
              Self.finite(input.moveSpeed), Self.finite(input.turnSpeed), input.up.map(Self.finite) ?? true else { return nil }
        let kind = table.vehicleProfiles[input.kind] != nil ? input.kind : "car"
        setVehicleKind(kind)
        let p = table.vehicleProfiles[kind]!,desiredDistance = table.vehicleDistances[kind]![carZoom-1]
        let step = Double(delta)*50,position = Self.double(input.position),forward = Self.double(input.forward),right = Self.double(input.right)
        let move = Self.double(input.moveSpeed),turn = Self.double(input.turnSpeed),up = input.up.map(Self.double)
        let maxX = Double(input.bounds.maxX),minY = Double(input.bounds.minY),maxZ = Double(input.bounds.maxZ)
        let ground = kind == "car" || kind == "bike",manual = carLook
        defer { carLook = .zero }
        carDistance = carDistance < desiredDistance ? min(desiredDistance,carDistance+0.12*step) : max(desiredDistance,carDistance-0.12*step)
        var center = position
        var slope = table.vehicleAngles[kind]![carZoom-1]
        let length = 2*abs(minY)
        var distance = carDistance+p[1]+length
        let minimumDistance = length*p[3]
        var extendedDistance = distance
        let lift = maxZ*p[0]-p[2]
        if kind == "heli" { if let up { center += up*(0.6*maxZ) } }
        else if lift > 0 { center.z += lift;distance += lift;extendedDistance = distance;slope += 0.3/distance*lift }
        let farDistance = max(distance,carZoom == 1 && ground ? 0.65*p[4] : p[4])
        if carReset { carFov = 70 }
        else {
            let speed = simd_dot(forward,move)
            if ground && speed > 0.4 { carFov += (speed-0.4)*step }
            if carFov > 70 { carFov = pow(0.98,step)*(carFov-70)+70 }
            carFov = Self.clamp(carFov,70,100)
        }
        if carReset || carLookReset {
            carReset = false;carLookReset = false;carElevation = 0;carAzimuth = Self.azimuth(forward)-Double.pi/2
            carYawVelocity = 0;carPitchVelocity = 0
            let way = Self.carWay(carElevation,carAzimuth)
            carFarSource = center-way*farDistance;carOldSource = center-way*distance;carElevation = -slope
        }
        let previousWay = Self.normalized(center-carFarSource)
        var oldDirection = Self.azimuth(previousWay)-Double.pi/2
        if oldDirection < -Double.pi { oldDirection += 2*Double.pi }
        var movementDirection = Self.horizontal(move) <= 0.02 ? oldDirection : Self.azimuth(move)-Double.pi/2
        if movementDirection < oldDirection-Double.pi { movementDirection += 2*Double.pi }
        else if movementDirection > oldDirection+Double.pi { movementDirection -= 2*Double.pi }
        let turnRate = step*p[10],turnLimit = step*p[11]
        let sideways = simd_length(move-previousWay*simd_dot(move,previousWay))
        let turnStep = Self.clamp(min(1,turnRate*sideways)*(movementDirection-oldDirection),-turnLimit,turnLimit)
        var targetDirection = oldDirection+turnStep
        if targetDirection < carAzimuth-Double.pi/2 { targetDirection += 2*Double.pi }
        else if targetDirection > carAzimuth+Double.pi { targetDirection -= 2*Double.pi }
        let oldDistance = simd_distance(center,carOldSource)
        if oldDistance < distance && distance > minimumDistance { distance = max(minimumDistance,oldDistance) }
        var maxElevation = p[13]
        if simd_length_squared(move) < 0.04 && kind != "heli" && (kind != "plane" || input.wheels > 0) && (kind != "bike" || input.wheels > 3) {
            let across = Self.normalized(simd_cross(forward,SIMD3(0,0,1)))
            let over = Self.normalized(simd_cross(across,forward))
            if simd_dot(over,previousWay) > 0 {
                let difference = carAzimuth-(Self.azimuth(forward)-Double.pi/2)
                let folded = asin(abs(sin(difference)))
                let clearance = folded <= atan2(maxX,-minY) ? (1.5-minY)/cos(folded) : (1.2+maxX)/cos(max(0,Double.pi/2-folded))
                maxElevation = cos(difference)*atan2(forward.z,Self.horizontal(forward))+atan2(center.z-position.z+Double(input.heightAboveRoad),1.2*clearance)
                if kind == "car" && input.wheels > 1 && abs(simd_dot(turn,forward)) < 0.05 {
                    maxElevation += cos(difference+Double.pi/2)*atan2(right.z,Self.horizontal(right))
                }
            }
        }
        var desiredElevation = Self.clamp(asin(Self.clamp(previousWay.z,-1,1))-slope,-p[14],maxElevation)
        let elevationLimit = step*p[6]
        let elevationStep = Self.clamp((1-pow(p[5],step))*(desiredElevation-carElevation),-elevationLimit,elevationLimit)
        var yawInput: Double = 0,pitchInput: Double = 0,manuallyTurning = false
        if manual.x != 0 || manual.y != 0 {
            let rate = 0.0125*carFov*0.0025
            yawInput = -2*manual.x*rate;pitchInput = -2*manual.y*rate
            carYawVelocity = 0;carPitchVelocity = 0;desiredElevation = carElevation;manualHold = 50;manuallyTurning = true
        } else if manualHold > 0 {
            carYawVelocity = 0;carPitchVelocity = 0;desiredElevation = carElevation;manualHold = max(0,manualHold-step);manuallyTurning = true
        }
        var vertical = pitchInput*p[12]
        let horizontal = yawInput*p[12],decay = pow(p[8],step),share = 1-decay
        carYawVelocity = Self.clamp(horizontal+(targetDirection-carAzimuth)/max(step,1),-p[9],p[9])*share+decay*carYawVelocity
        if abs(carYawVelocity) < 0.0001 { carYawVelocity = 0 }
        carAzimuth += manuallyTurning ? horizontal : step*carYawVelocity
        if carAzimuth < -Double.pi { carAzimuth += 2*Double.pi } else if carAzimuth > Double.pi { carAzimuth -= 2*Double.pi }
        if ground && desiredElevation < carElevation && oldDistance >= distance && input.wheels > 1 { vertical += (desiredElevation-carElevation)*0.075 }
        carPitchVelocity = share*vertical+decay*carPitchVelocity
        let pitchLimit = vertical > 0 ? 0.5*p[9] : p[9]
        carPitchVelocity = Self.clamp(carPitchVelocity,-pitchLimit,pitchLimit)
        if abs(carPitchVelocity) < 0.0001 { carPitchVelocity = 0 }
        let adjustedElevation: Double
        if manuallyTurning { adjustedElevation = vertical+desiredElevation;carElevation += vertical }
        else { adjustedElevation = step*carPitchVelocity+desiredElevation;carElevation += elevationStep }
        if carElevation > maxElevation { carElevation = maxElevation;carPitchVelocity = 0 }
        else if carElevation < -p[14] { carElevation = -p[14];carPitchVelocity = 0 }
        if abs(oldElevation-carElevation) < 0.0001 { carElevation = oldElevation };oldElevation = carElevation
        if abs(oldAzimuth-carAzimuth) < 0.0001 { carAzimuth = oldAzimuth };oldAzimuth = carAzimuth
        let source = center-Self.carWay(carElevation,carAzimuth)*distance
        let lagWay = Self.carWay(adjustedElevation+slope,carAzimuth)
        carFarSource = center-lagWay*farDistance;carOldSource = center-lagWay*distance
        if vehicleView > 3 { return cockpit(input,kind: kind,step: step,manual: manual,look: look,fov: carFov) }
        var around = center,target = center,finalSource = source
        let side = look == "right" ? 1.0 : look == "left" ? -1.0 : 0
        if side != 0 && kind != "heli" && kind != "plane" {
            carLookReset = true
            let direction = atan2(forward.y,forward.x)+side*Double.pi/2
            let edge = side > 0 ? input.bounds.min.map { Double($0.x) } ?? -maxX : input.bounds.max.map { Double($0.x) } ?? maxX
            let roof = position.z+edge*right.z+maxZ*(up?.z ?? 1)
            finalSource = SIMD3(position.x+extendedDistance*cos(direction),position.y+extendedDistance*sin(direction),min(source.z,max(roof,center.z)+0.1))
            target = position+SIMD3(0,0,1.1);around = position
        } else if look == "behind" {
            finalSource = center+forward*extendedDistance;finalSource.z = center.z+extendedDistance*(forward.z+0.2);target = position
        }
        return vehicleFrame(source: finalSource,target: target,around: around,fov: carFov)
    }
    private func cockpit(_ input: Vehicle,kind: String,step: Double,manual: SIMD2<Double>,look: String?,fov: Double) -> Frame? {
        guard let table else { return nil }
        let position = Self.double(input.position),forward = Self.double(input.forward),right = Self.double(input.right)
        let up = input.up.map(Self.double) ?? Self.normalized(simd_cross(right,forward))
        if vehicleView == 6 {
            let profile = table.cinematic[kind == "heli" || kind == "plane" ? "air" : "ground"]!
            if cinematicSource == nil || simd_distance(cinematicSource!,position) > profile[3] {
                var direction = Self.double(input.moveSpeed);direction.z = 0
                if simd_length_squared(direction) < 0.0004 { direction = forward;direction.z = 0 }
                direction = Self.normalized(direction)
                let side = SIMD3(direction.y,-direction.x,0)*(cinematicSide%2 != 0 ? profile[1] : -profile[1]);cinematicSide += 1
                cinematicSource = position+direction*profile[0]+side;cinematicSource!.z += profile[2]
            }
            return vehicleFrame(source: cinematicSource!,target: position,around: position,fov: 50)
        }
        if manual.x != 0 || manual.y != 0 {
            let rate = 0.0125*fov*0.005
            cockpitYaw = Self.clamp(cockpitYaw-manual.x*rate,-2.4,2.4)
            cockpitPitch = Self.clamp(cockpitPitch-manual.y*rate,-1.1,1.1);cockpitHold = 50
        } else if cockpitHold > 0 { cockpitHold = max(0,cockpitHold-step) }
        else { cockpitYaw *= pow(0.92,step);cockpitPitch *= pow(0.92,step) }
        let yaw = look == "behind" ? Double.pi : look == "left" ? Double.pi/2 : look == "right" ? -Double.pi/2 : cockpitYaw
        let bounds = input.bounds
        let local: SIMD3<Double>
        if vehicleView == 5 && kind != "bike" {
            local = SIMD3(0,(bounds.max.map{Double($0.y)} ?? -Double(bounds.minY))-0.15,0.45*Double(bounds.maxZ))
        } else if let eye = input.eye { local = Self.double(eye)+SIMD3(0,0.12,0.62) }
        else { local = SIMD3(-0.4*Double(bounds.maxX),-0.05*Double(bounds.minY),0.7*Double(bounds.maxZ)) }
        let source = position+right*local.x+forward*local.y+up*local.z
        let across = forward*cos(yaw)-right*sin(yaw)
        let direction = across*cos(cockpitPitch)+up*sin(cockpitPitch)
        return vehicleFrame(source: source,target: source+direction*10,around: source,fov: fov)
    }
    private func vehicleFrame(source: SIMD3<Double>,target: SIMD3<Double>,around: SIMD3<Double>,fov: Double) -> Frame {
        var source = source
        let offset = source-around,distance = simd_length(offset)
        if distance > 0.0001 {
            let direction = offset/distance
            if let hit = collision(around,direction,distance+0.3),hit < distance+0.3 { source = around+direction*max(0,hit-0.3) }
        }
        return frame(source: source,target: target,fov: Self.verticalFov(fov))
    }
    private static func finite(_ value: SIMD3<Float>) -> Bool { value.x.isFinite && value.y.isFinite && value.z.isFinite }
    private static func horizontal(_ value: SIMD3<Double>) -> Double { hypot(value.x,value.y) }
    private static func azimuth(_ value: SIMD3<Double>) -> Double { atan2(-value.x,value.y) }
    private static func carWay(_ elevation: Double,_ azimuth: Double) -> SIMD3<Double> { SIMD3(-cos(azimuth)*cos(elevation),-sin(azimuth)*cos(elevation),sin(elevation)) }

    private func collision(_ origin: SIMD3<Double>,_ direction: SIMD3<Double>,_ distance: Double) -> Double? {
        trace?(Self.float(origin),Self.float(direction),Float(distance)).map(Double.init)
    }
    private func availableReach(_ origin: SIMD3<Double>,_ direction: SIMD3<Double>,_ distance: Double,padding: Double) -> Double {
        guard let missing=unavailableDistance?(Self.float(origin),Self.float(direction),Float(distance+padding)),
              missing.isFinite,missing>=0 else {return distance}
        return min(distance,max(0,Double(missing)-padding))
    }
    private func frame(source: SIMD3<Double>,target: SIMD3<Double>,fov: Double,hidesPlayer: Bool = false,aimSource: SIMD3<Double>? = nil) -> Frame {
        let direction = Self.normalized(target-source)
        lastSource = source
        if abs(fov-currentVerticalFov) > 0.01 { currentVerticalFov = fov }
        return Frame(source: Self.float(source),target: Self.float(target),verticalFov: Float(currentVerticalFov),heading: Float(atan2(direction.x,direction.y)),pitch: Float(asin(Self.clamp(direction.z,-1,1))),hidesPlayer: hidesPlayer,aimSource: aimSource.map(Self.float))
    }
    private static func verticalFov(_ horizontal: Double) -> Double { 2*atan(0.75*tan(horizontal*Double.pi/360))*180/Double.pi }
    private static func double(_ value: SIMD3<Float>) -> SIMD3<Double> { SIMD3(Double(value.x),Double(value.y),Double(value.z)) }
    private static func float(_ value: SIMD3<Double>) -> SIMD3<Float> { SIMD3(Float(value.x),Float(value.y),Float(value.z)) }
    private static func normalized(_ value: SIMD3<Double>) -> SIMD3<Double> { let size = simd_length(value);return size > 0 ? value/size : .zero }
    private static func clamp(_ value: Double,_ lower: Double,_ upper: Double) -> Double { min(upper,max(lower,value)) }
}
