import Foundation
import Metal
import simd

/// Compile with NativeActorAnimation.swift and NativeSkeletalActor.swift, then
/// run on the Mac to compare raw-track CPU and Metal skinning to the local
/// independently baked ANP3 vertex reference. No game data enters the source.
@main struct SkeletalSmoke {
    static func main() throws {
        let root = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) :
            URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let models = root.appendingPathComponent("local-only/site/game/native/models")
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("A Metal device is required")
        }
        let source = try String(contentsOf: root.appendingPathComponent("ios/App/SkeletalShaders.metal"), encoding: .utf8)
        let shader = try device.makeLibrary(source: source, options: nil)
        let pipeline = try device.makeComputePipelineState(function: shader.makeFunction(name: "skeletalPositionProbe")!)
        let worldSource = try String(contentsOf: root.appendingPathComponent("ios/App/WorldShaders.metal"), encoding: .utf8)
        let world = try device.makeLibrary(source: worldSource, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = shader.makeFunction(name: "skeletalActorVertex")
        descriptor.fragmentFunction = world.makeFunction(name: "worldFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        descriptor.depthAttachmentPixelFormat = .depth32Float
        _ = try device.makeRenderPipelineState(descriptor: descriptor)
        let raw = try Data(contentsOf: models.appendingPathComponent("animations.clips.bin"))
        guard let library = NativeSkeletalAnimationLibrary(data: raw) else { fatalError("Invalid CLP1 library") }
        let reference = try Data(contentsOf: models.appendingPathComponent("bmori.anim.bin"))
        let bytes = [UInt8](reference)
        func u32(_ at: Int) -> Int {
            Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
        }
        func f32(_ at: Int) -> Float { Float(bitPattern: UInt32(u32(at))) }
        let count = u32(4), clips = u32(8), fps = u32(12)
        guard let actor = NativeSkeletalActor(data: try Data(contentsOf: models.appendingPathComponent("bmori.skel.bin")),
            vertexCount: count, device: device) else { fatalError("Invalid SKN1 rig") }
        precondition(MemoryLayout<NativeSkinVertex>.stride == 48)
        let output = device.makeBuffer(length: count * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)!
        var offset = 16, largestCPU: Float = 0, largestGPU: Float = 0, samples = 0
        var worst = ""
        for _ in 0..<clips {
            let name = String(bytes: bytes[offset..<(offset + 16)].prefix { $0 != 0 }, encoding: .ascii)!
            let frames = u32(offset + 16)
            offset += 20
            for frame in Set([0, frames / 2, frames - 1]).sorted() {
                guard let pose = actor.pose(clip: name, elapsed: Double(frame) / Double(fps), library: library) else {
                    fatalError("Unavailable raw clip: " + name)
                }
                let cpu = actor.positions(pose: pose)
                let command = queue.makeCommandBuffer()!, encoder = command.makeComputeCommandEncoder()!
                encoder.setComputePipelineState(pipeline)
                encoder.setBuffer(actor.skinVertices, offset: 0, index: 0)
                pose.palette.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 1) }
                encoder.setBuffer(output, offset: 0, index: 2)
                var length = UInt32(count)
                encoder.setBytes(&length, length: 4, index: 3)
                encoder.dispatchThreads(MTLSize(width: count, height: 1, depth: 1),
                    threadsPerThreadgroup: MTLSize(width: min(64, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
                encoder.endEncoding()
                command.commit(); command.waitUntilCompleted()
                precondition(command.status == .completed, "Metal skin probe failed")
                let gpu = output.contents().bindMemory(to: SIMD4<Float>.self, capacity: count)
                let start = offset + frame * count * 12
                for vertex in 0..<count {
                    let at = start + vertex * 12
                    let expected = SIMD3(f32(at), f32(at + 4), f32(at + 8))
                    let difference = simd_distance(cpu[vertex], expected)
                    if difference > largestCPU {
                        largestCPU = difference
                        worst = "\(name) frame \(frame) vertex \(vertex) CPU \(cpu[vertex]) reference \(expected)"
                    }
                    largestGPU = max(largestGPU, simd_distance(SIMD3(gpu[vertex].x, gpu[vertex].y, gpu[vertex].z), expected))
                    samples += 1
                }
            }
            offset += frames * count * 12
        }
        precondition(offset == bytes.count)
        precondition(largestCPU < 0.0001, "CPU rig differs by \(largestCPU) m: \(worst)")
        precondition(largestGPU < 0.0001, "GPU rig differs by \(largestGPU) m")
        let walk = actor.pose(clip: "walk_player", elapsed: 0.3, library: library)!
        let firing = actor.pose(clip: "rifle_fire", elapsed: 0.4, library: library,
            locomotion: "walk_player", locomotionElapsed: 0.3)!
        for bone in [1, 41, 42, 43, 44, 51, 52, 53, 54] {
            let left = actor.transform(bone: bone, in: walk)!, right = actor.transform(bone: bone, in: firing)!
            precondition(simd_distance(left.columns.3, right.columns.3) < 0.00001,
                         "Firing interrupts locomotion leg \(bone)")
        }
        precondition(simd_distance(walk.hand.columns.3, firing.hand.columns.3) > 0.01,
                     "Upper-body firing layer did not move the hand")
        let preserved = actor.pose(clip: "death_front", elapsed: 0.5, library: library,
            previous: walk, transition: 0)!
        precondition(zip(actor.positions(pose: walk), actor.positions(pose: preserved))
            .allSatisfy { simd_distance($0.0, $0.1) < 0.00001 }, "Transition changed its zero-weight source")
        for name in library.clipNames {
            guard let pose = actor.pose(clip: name, elapsed: (library.duration(of: name) ?? 0) / 2,
                                       library: library) else { fatalError("Raw clip unavailable: " + name) }
            precondition(actor.positions(pose: pose).allSatisfy {
                $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && simd_length($0) < 1000
            }, "Non-finite runtime animation: " + name)
            precondition(library.canonicalName(forWire: name + "/l/1") == name)
        }
        let rigs = try JSONSerialization.jsonObject(with: Data(contentsOf: models.appendingPathComponent("skeletons.json"))) as! [String: [String: Any]]
        for (name, spec) in rigs {
            let count = (spec["vertices"] as! NSNumber).intValue
            guard let rig = NativeSkeletalActor(data: try Data(contentsOf: models.appendingPathComponent(name + ".skel.bin")),
                                                vertexCount: count, device: device),
                  let pose = rig.pose(clip: "idle_stance", elapsed: 0.4, library: library) else {
                fatalError("Unable to decode runtime rig: " + name)
            }
            precondition(rig.positions(pose: pose).allSatisfy {
                $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && simd_length($0) < 10
            }, "Invalid pedestrian vertices: " + name)
        }
        print("PASS: \(library.clipCount) raw clips / \(library.aliasCount) aliases / \(rigs.count) runtime rigs; \(clips) baked references / \(samples) sampled vertices; CPU max \(largestCPU) m, GPU max \(largestGPU) m; all raw poses finite; locomotion firing layers and transition preservation")
    }
}
