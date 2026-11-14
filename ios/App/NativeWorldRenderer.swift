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

    let view: MTKView
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let depth: MTLDepthStencilState
    private let textureLoader: MTKTextureLoader
    private var meshes: [String: Mesh] = [:]
    private var actorMeshes: [String: Mesh] = [:]
    private var actorLoading: Set<String> = []
    private var vehicleModels: [String: String] = [:]
    private var pedModels: [String: String] = [:]
    private var loading: Set<String> = []
    private var retryAfter: [String: Date] = [:]
    private var activeDetail = "c59"
    private var camera = SIMD3<Float>(1480, -1738, 13)
    private var heading: Float = 0
    private var collision: WorldCollision?
    private(set) var drivingSpeed: Float = 0
    private var verticalSpeed: Float = 0
    var driving = false
    var remotePlayers: [RemotePlayer] = []
    var remoteVehicles: [RemoteVehicle] = []
    var currentVehicleID: String?
    var onStatus: ((String) -> Void)?
    var onFrame: (() -> Void)?

    init?(preferredDevice: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device = preferredDevice,
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "worldVertex"),
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
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        guard let depth = device.makeDepthStencilState(descriptor: depthDescriptor) else { return nil }
        self.view = view
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.depth = depth
        textureLoader = MTKTextureLoader(device: device)
        super.init()
        view.delegate = self
    }

    var position: SIMD3<Float> { camera }
    var direction: Float { heading }
    var isAirborne: Bool { verticalSpeed != 0 }

    func move(forward: Float, sideways: Float, turn: Float, delta: Float) {
        let start = camera
        var next = camera
        if driving {
            heading += turn * delta * max(0.45, min(1.8, abs(drivingSpeed) / 7))
            let desired = max(-8, min(24, forward * 24))
            drivingSpeed += (desired - drivingSpeed) * min(1, delta * (forward == 0 ? 2.2 : 1.3))
            next.x += sin(heading) * drivingSpeed * delta
            next.y += cos(heading) * drivingSpeed * delta
        } else {
            heading += turn * delta * 1.8
            let scale = delta * 5.0
            next.x += (sin(heading) * forward + cos(heading) * sideways) * scale
            next.y += (cos(heading) * forward - sin(heading) * sideways) * scale
        }
        let radius: Float = driving ? 0.9 : 0.32
        let height: Float = driving ? 1.4 : 1.8
        if collision?.canMove(from: start, to: next, radius: radius, bodyHeight: height) == false {
            if driving { drivingSpeed = 0 }
            next = start
        }
        camera = next
        if !driving && verticalSpeed != 0 {
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

    func enter(_ vehicle: RemoteVehicle) {
        camera = vehicle.position
        heading = vehicle.heading
        drivingSpeed = 0
        verticalSpeed = 0
        driving = true
        currentVehicleID = vehicle.id
        loadNearby()
    }

    func exitVehicle() {
        driving = false
        currentVehicleID = nil
        drivingSpeed = 0
        camera.x += cos(heading) * 2.5
        camera.y -= sin(heading) * 2.5
        camera.z = collision?.height(x: camera.x, y: camera.y, near: camera.z - 1.1) ?? camera.z - 1.1
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
        meshes = meshes.filter { !$0.key.hasPrefix("c") || $0.key == activeDetail }
        // The camera sits behind the player; draw the adjacent 1.5 km blocks
        // as well so a block edge never cuts across the horizon.
        for dx in [Float(-750), 0, 750] {
            for dy in [Float(-750), 0, 750] {
                let tx = max(0, min(3, Int(floor((camera.x + 3000 + dx) / 1500))))
                let ty = max(0, min(3, Int(floor((camera.y + 3000 + dy) / 1500))))
                load(name: "t\(ty * 4 + tx)")
            }
        }
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
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let aspect = max(0.1, Float(view.drawableSize.width / max(1, view.drawableSize.height)))
        let distance: Float = driving ? 11 : 6
        let eye = camera + SIMD3<Float>(-sin(heading) * distance, -cos(heading) * distance,
                                        driving ? 4.5 : 2.8)
        let target = camera + SIMD3<Float>(sin(heading) * 4, cos(heading) * 4,
                                           driving ? 1.1 : 1.2)
        let matrix = Self.perspective(aspect: aspect) * Self.lookAt(eye: eye, target: target)
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depth)
        encoder.setCullMode(.none)
        let farX = max(0, min(3, Int(floor((camera.x + 3000) / 1500))))
        let farY = max(0, min(3, Int(floor((camera.y + 3000) / 1500))))
        let currentFar = "t\(farY * 4 + farX)"
        for (name, mesh) in meshes where name != currentFar || meshes[activeDetail] == nil {
            var uniforms = Uniforms(viewProjection: matrix,
                                    settings: SIMD4(Float(mesh.atlas.width), Float(mesh.atlas.height),
                                                    0, name.hasPrefix("c") ? 128 : 64))
            encoder.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentTexture(mesh.atlas, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount,
                                          indexType: .uint32, indexBuffer: mesh.indices, indexBufferOffset: 0)
        }
        drawActors(encoder: encoder, matrix: matrix)
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
        onFrame?()
    }

    private func drawActors(encoder: MTLRenderCommandEncoder, matrix: simd_float4x4) {
        var modelInstances: [(String, SIMD3<Float>, Float)] = []
        if driving {
            let code = remoteVehicles.first(where: { $0.id == currentVehicleID })?.code ?? "420.6.1.0."
            if let name = actorName(code: code) {
                modelInstances.append((name, camera, heading))
            }
        } else if let name = pedModels["7"] {
            modelInstances.append((name, camera, heading))
        }
        for player in remotePlayers where simd_distance(player.position, camera) < 130 {
            if let name = actorName(code: player.code) {
                modelInstances.append((name, player.position, player.heading))
            }
        }
        for vehicle in remoteVehicles where vehicle.id != currentVehicleID &&
            simd_distance(vehicle.position, camera) < 130 {
            if let name = actorName(code: vehicle.code) {
                modelInstances.append((name, vehicle.position, vehicle.heading))
            }
        }
        for (name, position, angle) in modelInstances {
            guard let mesh = actorMeshes[name] else { loadActor(name); continue }
            let c = cos(angle), s = sin(angle)
            let transform = simd_float4x4(columns: (
                SIMD4(c, -s, 0, 0), SIMD4(s, c, 0, 0),
                SIMD4(0, 0, 1, 0), SIMD4(position.x, position.y, position.z, 1)))
            var uniforms = Uniforms(viewProjection: matrix * transform,
                                    settings: SIMD4(Float(mesh.atlas.width), Float(mesh.atlas.height), 0, 128))
            encoder.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentTexture(mesh.atlas, index: 0)
            encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount,
                                          indexType: .uint32, indexBuffer: mesh.indices,
                                          indexBufferOffset: 0)
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
