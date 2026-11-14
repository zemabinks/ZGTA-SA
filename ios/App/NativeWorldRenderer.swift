import Foundation
import MetalKit
import simd

/// Renders the locally hosted WRL2 world directly with Metal. Game meshes and
/// texture atlases stay on the Mac; the app fetches only visible cells.
final class NativeWorldRenderer: NSObject, MTKViewDelegate {
    private struct Uniforms {
        var viewProjection: simd_float4x4
        var settings: SIMD4<Float>
    }

    private struct Mesh {
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let indexCount: Int
        let atlas: MTLTexture
    }

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
    private let depth: MTLDepthStencilState
    private let markerDepth: MTLDepthStencilState
    private let textureLoader: MTKTextureLoader
    private var meshes: [String: Mesh] = [:]
    private var actorMeshes: [String: Mesh] = [:]
    private var actorAnimations: [String: NativeActorAnimation] = [:]
    private var actorAttachments: [String: NativeActorAttachment] = [:]
    private var actorLoading: Set<String> = []
    private var objectiveMarker: Mesh?
    private var vehicleModels: [String: String] = [:]
    private var pedModels: [String: String] = [:]
    private var loading: Set<String> = []
    private var retryAfter: [String: Date] = [:]
    private var activeDetail = "c59"
    private var activeFar: Set<String> = []
    private var camera = SIMD3<Float>(1480, -1738, 13)
    private var heading: Float = 0
    private var actorHeading: Float = 0
    private var cameraPitch: Float = 0
    private var collision: WorldCollision?
    private(set) var drivingSpeed: Float = 0
    private var verticalSpeed: Float = 0
    private var vehicleHandling: [String: VehicleHandling] = [:]
    private var vehicleInfo: [String: [String: String]] = [:]
    private var activeVehicleModel = ""
    private var activeHandling: VehicleHandling?
    private(set) var vehicleKind = "car"
    private var vehiclePitch: Float = 0
    private var flightVerticalSpeed: Float = 0
    private var flightStartHeight: Float = 0
    private var waterHeight: Float = 0
    private(set) var steeringInput: Float = 0
    private var ownClip = "idle_stance"
    private var ownClipTime: Double = 0
    private var actionTimeRemaining: Float = 0
    private var actionClip = ""
    var equippedWeapon = 0
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
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depth = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        depthDescriptor.isDepthWriteEnabled = false
        guard let markerDepth = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        self.view = view
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.animatedPipeline = animatedPipeline
        self.depth = depth
        self.markerDepth = markerDepth
        textureLoader = MTKTextureLoader(device: device)
        super.init()
        objectiveMarker = makeObjectiveMarker()
        view.delegate = self
    }

    var position: SIMD3<Float> { camera }
    var direction: Float { driving ? heading : actorHeading }
    var cameraDirection: Float { heading }
    var isAirborne: Bool { verticalSpeed != 0 }
    var vehicleNose: Float { driving ? vehiclePitch : 0 }
    func vehicleName(model: String) -> String? { vehicleInfo[model]?["name"] }
    func vehicleType(model: String) -> String? { vehicleInfo[model]?["type"] }
    var isFiring: Bool { actionTimeRemaining > 0 && actionClip == "colt45_fire" }

    func move(forward: Float, sideways: Float, turn: Float, delta: Float,
              running: Bool = false, lookVertical: Float = 0, lift: Float = 0) {
        if !driving || (vehicleKind != "plane" && vehicleKind != "helicopter") {
            cameraPitch = max(-0.4, min(0.5, cameraPitch + lookVertical * delta * 0.45))
        }
        actionTimeRemaining = max(0, actionTimeRemaining - delta)
        let inputLength = min(1, hypot(forward, sideways))
        let clip = !driving && actionTimeRemaining > 0 ? actionClip :
            !driving && verticalSpeed != 0 ? "jump_launch" :
            inputLength < 0.05 ? (equippedWeapon == 22 ? "gun_stand" : "idle_stance") :
            running ? "run_player" : "walk_player"
        if clip != ownClip { ownClip = clip; ownClipTime = 0 }
        else { ownClipTime += Double(delta * (inputLength < 0.05 ? 1 : inputLength)) }
        let start = camera
        var next = camera
        if driving {
            steeringInput = max(-1, min(1, turn))
            let table = activeHandling
            let speedLimit = table?.roadTopSpeed ?? 32
            let acceleration = max(1.5, (table?.acceleration ?? 20) * 0.24)
            let braking = max(3, (table?.brakes ?? 7) * 1.2)
            let lock = max(10, min(50, table?.lock ?? 35)) * .pi / 180
            let grip = max(0.35, min(1.8, table?.traction ?? 0.8))
            if vehicleKind == "helicopter" {
                heading += steeringInput * delta * 0.95
                drivingSpeed += (forward * 24 - drivingSpeed) * min(1, delta * 1.6)
                next.x += (sin(heading) * drivingSpeed + cos(heading) * sideways * 15) * delta
                next.y += (cos(heading) * drivingSpeed - sin(heading) * sideways * 15) * delta
                flightVerticalSpeed += (lift * 8 - flightVerticalSpeed) * min(1, delta * 1.8)
                next.z += flightVerticalSpeed * delta
                vehiclePitch += (forward * 0.16 - vehiclePitch) * min(1, delta * 2)
            } else if vehicleKind == "plane" && activeVehicleModel != "539" {
                let top = max(35, min(95, (table?.maxVelocity ?? 200) / 3.6))
                let target = max(0, min(top, forward > 0 ? top * forward : 0))
                let rate = forward < 0 ? max(3, braking) : forward > 0 ? max(3, acceleration) : 1.2
                drivingSpeed += max(-rate * delta, min(rate * delta, target - drivingSpeed))
                // Keep a touch-only takeoff climbing above the airport's
                // terminal and container roofs. A right-stick input overrides
                // the assist, so a pilot can level or descend at any time.
                let autoRotate = drivingSpeed > 15 && forward > 0.05 &&
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
                let input = max(-1, min(1, forward))
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
            heading += turn * delta * 1.8
            if inputLength >= 0.05 {
                let worldX = sin(heading) * forward + cos(heading) * sideways
                let worldY = cos(heading) * forward - sin(heading) * sideways
                let desired = atan2(worldX, worldY)
                if actionTimeRemaining == 0 {
                    let difference = atan2(sin(desired - actorHeading),
                                           cos(desired - actorHeading))
                    actorHeading += max(-delta * 8, min(delta * 8, difference))
                }
                // The archived clips sweep a foot roughly 1.1 m in 1.2 s
                // walking and 1.5 m in 0.73 s running. Match world travel to
                // those cycles so the feet do not slide across the pavement.
                let distance = delta * (running ? 4.1 : 1.6) * inputLength
                let length = max(0.0001, hypot(worldX, worldY))
                next.x += worldX / length * distance
                next.y += worldY / length * distance
            }
        }
        let radius: Float = driving ? (vehicleKind == "bike" || vehicleKind == "bicycle" ? 0.48 : 0.9) : 0.32
        let height: Float = driving ? (vehicleKind == "plane" ? 2.5 : 1.4) : 1.8
        if collision?.canMove(from: start, to: next, radius: radius, bodyHeight: height) == false {
            if driving { drivingSpeed = 0; flightVerticalSpeed = 0 }
            next = start
        }
        camera = next
        if driving && (vehicleKind == "plane" || vehicleKind == "helicopter") &&
            activeVehicleModel != "539" {
            if let floor = collision?.height(x: camera.x, y: camera.y,
                                             near: camera.z - 1.1, maxDrop: 20),
               camera.z < floor + 1.1 {
                camera.z = floor + 1.1
                flightVerticalSpeed = max(0, flightVerticalSpeed)
            }
        } else if driving && (vehicleKind == "boat" || activeVehicleModel == "539") {
            camera.z = waterHeight
        } else if !driving && verticalSpeed != 0 {
            verticalSpeed -= 9.8 * delta
            camera.z += verticalSpeed * delta
            if let floor = collision?.height(x: camera.x, y: camera.y,
                                             near: camera.z, maxDrop: 8),
               camera.z <= floor {
                camera.z = floor
                verticalSpeed = 0
            }
        } else if let z = collision?.height(x: camera.x, y: camera.y,
                                            near: camera.z - (driving ? 1.1 : 0)) {
            camera.z = z + (driving ? 1.1 : 0)
        }
        loadNearby()
    }

    func jump() {
        guard !driving, verticalSpeed == 0 else { return }
        verticalSpeed = 5.5
    }

    func performFistAttack() {
        actorHeading = heading
        actionClip = "fighta_1"
        actionTimeRemaining = 0.43
    }

    func firePistol() {
        actorHeading = heading
        actionClip = "colt45_fire"
        actionTimeRemaining = 0.73
    }

    func clearAction() { actionTimeRemaining = 0 }

    func hasClearShot(to target: SIMD3<Float>) -> Bool {
        let start = camera + SIMD3<Float>(0, 0, 1.35)
        let finish = target + SIMD3<Float>(0, 0, 1.15)
        return collision?.lineOfSight(from: start, to: finish) ?? true
    }

    func enter(_ vehicle: RemoteVehicle, kind: String) {
        camera = vehicle.position
        heading = vehicle.heading
        actorHeading = heading
        drivingSpeed = 0
        verticalSpeed = 0
        flightVerticalSpeed = 0
        flightStartHeight = vehicle.position.z
        vehiclePitch = 0
        steeringInput = 0
        activeVehicleModel = String(vehicle.code.split(separator: ".").first ?? "")
        activeHandling = vehicleHandling[activeVehicleModel]
        vehicleKind = kind
        waterHeight = vehicle.position.z
        driving = true
        currentVehicleID = vehicle.id
        loadNearby()
    }

    func exitVehicle() {
        let floor = collision?.height(x: camera.x, y: camera.y,
                                      near: camera.z, maxDrop: 1000)
        let falling = floor.map { camera.z > $0 + 3 } ?? false
        driving = false
        currentVehicleID = nil
        drivingSpeed = 0
        flightVerticalSpeed = 0
        vehiclePitch = 0
        activeVehicleModel = ""
        activeHandling = nil
        vehicleKind = "car"
        camera.x += cos(heading) * 2.5
        camera.y -= sin(heading) * 2.5
        if falling { verticalSpeed = -1 }
        else { camera.z = collision?.height(x: camera.x, y: camera.y,
                                           near: camera.z - 1.1) ?? camera.z - 1.1 }
        actorHeading = heading
    }

    func teleport(x: Float, y: Float, z: Float) {
        camera = SIMD3(x, y, z)
        verticalSpeed = 0
        loadNearby()
    }

    func loadNearby() {
        // The far mesh is divided into sixteen 4×4 blocks. Detailed cells are
        // 375 m squares with a 16-column grid and origin (-3000, -3000).
        let gx = max(0, min(15, Int(floor((camera.x + 3000) / 375))))
        let gy = max(0, min(15, Int(floor((camera.y + 3000) / 375))))
        let detail = gy * 16 + gx
        activeDetail = "c\(detail)"
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
        activeFar = far
        meshes = meshes.filter { $0.key == activeDetail || far.contains($0.key) }
        for name in far { load(name: name) }
        load(name: activeDetail)
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
        if name.hasPrefix("c") {
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
            if name.hasPrefix("c"), name != self.activeDetail { return }
            if name.hasPrefix("t"), !self.activeFar.contains(name) { return }
            guard let bin, let png else {
                self.retryAfter[name] = Date().addingTimeInterval(5)
                self.onStatus?("CITY FILE UNAVAILABLE: \(name.uppercased()) \(fetchError?.localizedDescription ?? "")")
                return
            }
            do {
                let world = try WorldBinary(data: bin)
                let atlas = try self.textureLoader.newTexture(data: png, options: [.SRGB: false])
                let cellSize = name.hasPrefix("c") ? 128 : 64
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
                if name == self.activeDetail, let col {
                    self.collision = try? WorldCollision(data: col)
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
        URLSession.shared.dataTask(with: server.path("game/native/models/index.json")) { [weak self] data, _, _ in
            guard let self, let data,
                  let index = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else { return }
            DispatchQueue.main.async {
                self.vehicleModels = index["vehicles"] ?? [:]
                self.pedModels = index["peds"] ?? [:]
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
        var attachment: Data?
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
            URLSession.shared.dataTask(with: server.path("game/native/models/\(name).anim.bin")) { data, response, _ in
                lock.lock()
                if (response as? HTTPURLResponse)?.statusCode == 200 { animation = data }
                lock.unlock()
                group.leave()
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

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let aspect = max(0.1, Float(view.drawableSize.width / max(1, view.drawableSize.height)))
        let distance: Float = driving ? 11 : 4.5
        // Raise or lower the camera around a nearby focus point. Changing only
        // the look-at height used to push the player off screen at pitch limits.
        let eyeHeight: Float = driving ?
            max(1.2, min(7, 4.5 - cameraPitch * 6)) :
            max(0.65, min(4.5, 2.4 - cameraPitch * 3.5))
        let eye = camera + SIMD3<Float>(-sin(heading) * distance, -cos(heading) * distance,
                                        eyeHeight)
        let focusAhead: Float = driving ? 4 : 2
        let target = camera + SIMD3<Float>(sin(heading) * focusAhead,
                                           cos(heading) * focusAhead,
                                           (driving ? 1.1 : 1.2) + cameraPitch)
        let matrix = Self.perspective(aspect: aspect) * Self.lookAt(eye: eye, target: target)
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depth)
        encoder.setCullMode(.none)
        // Keep the full far block under the 375 m detailed cell. Omitting the
        // entire 1.5 km block leaves a large empty square around the player.
        // A slight depth bias lets detailed geometry win where both overlap.
        for (name, mesh) in meshes where name.hasPrefix("t") {
            encoder.setDepthBias(0.0005, slopeScale: 0, clamp: 0)
            draw(mesh: mesh, cellSize: 64, matrix: matrix, encoder: encoder)
        }
        encoder.setDepthBias(0, slopeScale: 0, clamp: 0)
        if let mesh = meshes[activeDetail] {
            draw(mesh: mesh, cellSize: 128, matrix: matrix, encoder: encoder)
        }
        drawActors(encoder: encoder, matrix: matrix)
        drawObjective(encoder: encoder, matrix: matrix)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
        onFrame?()
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
                      encoder: MTLRenderCommandEncoder) {
        var uniforms = Uniforms(viewProjection: matrix,
                                settings: SIMD4(Float(mesh.atlas.width), Float(mesh.atlas.height),
                                                0, cellSize))
        encoder.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentTexture(mesh.atlas, index: 0)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount,
                                      indexType: .uint32, indexBuffer: mesh.indices, indexBufferOffset: 0)
    }

    private func drawActors(encoder: MTLRenderCommandEncoder, matrix: simd_float4x4) {
        var modelInstances: [(String, SIMD3<Float>, Float, Float, String, Double, Int)] = []
        if driving {
            let code = remoteVehicles.first(where: { $0.id == currentVehicleID })?.code ?? "420.6.1.0."
            if let name = actorName(code: code) {
                modelInstances.append((name, camera, heading, vehiclePitch, "", 0, 0))
            }
        } else if let name = pedModels["7"] {
            modelInstances.append((name, camera, actorHeading, 0, ownClip, ownClipTime, equippedWeapon))
        }
        for player in remotePlayers where simd_distance(player.position, camera) < 130 {
            if let name = actorName(code: player.code) {
                modelInstances.append((name, player.position, player.heading, player.pitch,
                                       player.animation, ProcessInfo.processInfo.systemUptime,
                                       player.weapon))
            }
        }
        let drivenVehicleIDs = Set(remotePlayers.compactMap(\.vehicleID))
        for vehicle in remoteVehicles where vehicle.id != currentVehicleID &&
            !drivenVehicleIDs.contains(vehicle.id) &&
            simd_distance(vehicle.position, camera) < 130 {
            if let name = actorName(code: vehicle.code) {
                modelInstances.append((name, vehicle.position, vehicle.heading, 0, "", 0, 0))
            }
        }
        for (name, position, angle, pitch, clip, elapsed, weapon) in modelInstances {
            guard let mesh = actorMeshes[name] else { loadActor(name); continue }
            // Archived pedestrian DFFs face local -Y after the RenderWare axis
            // conversion, while the world protocol defines heading zero as +Y.
            let modelAngle = angle + (pedModels.values.contains(name) ? Float.pi : 0)
            let c = cos(modelAngle), s = sin(modelAngle)
            let cp = cos(pitch), sp = sin(pitch)
            let transform = simd_float4x4(columns: (
                SIMD4(c, -s, 0, 0), SIMD4(s * cp, c * cp, sp, 0),
                SIMD4(-s * sp, -c * sp, cp, 0),
                SIMD4(position.x, position.y, position.z, 1)))
            var uniforms = Uniforms(viewProjection: matrix * transform,
                                    settings: SIMD4(Float(mesh.atlas.width), Float(mesh.atlas.height), 0, 128))
            if let frames = actorAnimations[name]?.sample(clip: clip, elapsed: elapsed) {
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
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount,
                                          indexType: .uint32, indexBuffer: mesh.indices,
                                          indexBufferOffset: 0)
            if weapon == 22,
               let pistol = actorMeshes["colt45"],
               let hand = actorAttachments[name]?.frame(clip: clip, elapsed: elapsed) {
                encoder.setRenderPipelineState(pipeline)
                draw(mesh: pistol, cellSize: 128, matrix: matrix * transform * hand,
                     encoder: encoder)
            }
        }
    }

    private static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 0, 1)))
        let up = simd_cross(right, forward)
        return simd_float4x4(columns: (
            SIMD4(right.x, up.x, -forward.x, 0),
            SIMD4(right.y, up.y, -forward.y, 0),
            SIMD4(right.z, up.z, -forward.z, 0),
            SIMD4(-simd_dot(right, eye), -simd_dot(up, eye), simd_dot(forward, eye), 1)))
    }

    private static func perspective(aspect: Float) -> simd_float4x4 {
        let near: Float = 0.1, far: Float = 3000
        let scale: Float = 1 / tan(.pi / 6)
        return simd_float4x4(columns: (
            SIMD4(scale / aspect, 0, 0, 0),
            SIMD4(0, scale, 0, 0),
            SIMD4(0, 0, far / (near - far), -1),
            SIMD4(0, 0, far * near / (near - far), 0)))
    }
}
