// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CoreGraphics
import Metal
import simd
import Darwin

private enum Failure: Error { case check(String) }
private var checks = 0, rendered = 0
private func check(_ value: Bool, _ text: String) throws {
    checks += 1
    if !value { throw Failure.check(text) }
}

// The actual renderer constructor runs below. The unshown view is the only
// reduced UI boundary; descriptors, functions and pipeline states use Metal.
private final class MTKView {
    var colorPixelFormat: MTLPixelFormat = .invalid
    var depthStencilPixelFormat: MTLPixelFormat = .invalid
    var clearColor = MTLClearColorMake(0, 0, 0, 0)
    var preferredFramesPerSecond = 0
    init(frame: CGRect, device: DeviceSpy) {}
}
private final class DeviceSpy {
    struct Capture {
        let vertex: String, fragment: String
        let writes: MTLColorWriteMask
        let pipeline: MTLRenderPipelineState
    }
    let actual: MTLDevice, library: MTLLibrary
    var captures: [Capture] = []
    init(_ actual: MTLDevice, _ library: MTLLibrary) { self.actual = actual; self.library = library }
    func makeCommandQueue() -> MTLCommandQueue? { actual.makeCommandQueue() }
    func makeDefaultLibrary() -> MTLLibrary? { library }
    func makeRenderPipelineState(descriptor: MTLRenderPipelineDescriptor) throws -> MTLRenderPipelineState {
        let result = try actual.makeRenderPipelineState(descriptor: descriptor)
        captures.append(.init(vertex: descriptor.vertexFunction!.name, fragment: descriptor.fragmentFunction!.name,
                              writes: descriptor.colorAttachments[0].writeMask, pipeline: result))
        return result
    }
}
private func productionPipelines(_ preferredDevice: DeviceSpy?) -> [DeviceSpy.Capture]? {
    // PRODUCTION_CONSTRUCTOR
    return device.captures
}

private struct Vertex {
    var position: SIMD4<Float>, uvLayer: SIMD4<Float>, tint: SIMD4<Float>, dusk: SIMD4<Float>
}
private struct Uniforms {
    var viewProjection = matrix_identity_float4x4
    var settings = SIMD4<Float>(4, 4, 0, 4)
    var fogColor = SIMD4<Float>(0.2, 0.4, 0.6, 1)
    var fogSettings = SIMD4<Float>(0, 2, 0, 0)
    var tintColor = SIMD4<Float>(repeating: 1)
}
private struct Case {
    let name: String
    var day = SIMD4<Float>(0, 0, 0, 1)
    var dusk = SIMD4<Float>(0.1, 0.2, 0.4, 1)
    var texture = SIMD4<UInt8>(255, 255, 255, 255)
    var night: Float = 0
    var weather = SIMD4<Float>(repeating: 1)
    var fog: Float = 0
    var clear = SIMD4<Float>(repeating: 0)
}
private func rgb(_ value: SIMD4<Float>) -> SIMD3<Float> { SIMD3(value.x, value.y, value.z) }
private func clamp(_ value: Float) -> Float { min(1, max(0, value)) }

// Authored vertex/texture/uniform values only. This oracle describes the
// selected base material, while native weather/fog/alpha remain separate.
private func expected(_ value: Case, world: Bool) -> SIMD4<UInt8> {
    let texture = SIMD4<Float>(Float(value.texture.x), Float(value.texture.y), Float(value.texture.z), Float(value.texture.w)) / 255
    if texture.w * value.day.w < 0.1 { return encode(value.clear) }
    var light = SIMD3<Float>(repeating: 0)
    if world {
        let day = simd_min(rgb(value.day) + SIMD3<Float>(repeating: 0.30), SIMD3<Float>(repeating: 1))
        let dusk = simd_min(rgb(value.dusk) + SIMD3<Float>(0.10, 0.10, 0.15), SIMD3<Float>(repeating: 1))
        light = day + (dusk - day) * value.night
    } else {
        light = simd_max((rgb(value.day) + (rgb(value.dusk) - rgb(value.day)) * value.night) * 1.8,
                         SIMD3<Float>(repeating: 0.20))
    }
    var color = rgb(texture) * light
    if !world { color = simd_min(color, SIMD3<Float>(repeating: 1)) }
    color *= rgb(value.weather)
    let fog = value.fog * 0.5 // Authored clip W = 1, fog interval = [0,2].
    color = color + (SIMD3<Float>(0.2, 0.4, 0.6) - color) * fog
    let alpha = texture.w * value.day.w * value.weather.w
    color = color * alpha + rgb(value.clear) * (1 - alpha)
    return encode(SIMD4(color, alpha + value.clear.w * (1 - alpha)))
}
private func encode(_ value: SIMD4<Float>) -> SIMD4<UInt8> {
    SIMD4(UInt8((clamp(value.x) * 255).rounded()), UInt8((clamp(value.y) * 255).rounded()),
          UInt8((clamp(value.z) * 255).rounded()), UInt8((clamp(value.w) * 255).rounded()))
}

private func render(_ value: Case, capture: DeviceSpy.Capture, device: MTLDevice, queue: MTLCommandQueue) throws -> SIMD4<UInt8> {
    let input = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 4, height: 4, mipmapped: false)
    input.storageMode = device.hasUnifiedMemory ? .shared : .managed; input.usage = .shaderRead
    let output = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1, height: 1, mipmapped: false)
    output.storageMode = input.storageMode; output.usage = .renderTarget
    let depth = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 1, height: 1, mipmapped: false)
    depth.storageMode = .private; depth.usage = .renderTarget
    guard let atlas = device.makeTexture(descriptor: input), let target = device.makeTexture(descriptor: output),
          let depthTexture = device.makeTexture(descriptor: depth), let command = queue.makeCommandBuffer() else { throw Failure.check("render allocation") }
    let pixels = Array(repeating: [value.texture.x, value.texture.y, value.texture.z, value.texture.w], count: 16).flatMap { $0 }
    pixels.withUnsafeBytes { atlas.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0, withBytes: $0.baseAddress!, bytesPerRow: 16) }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = target; pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(Double(value.clear.x), Double(value.clear.y), Double(value.clear.z), Double(value.clear.w))
    pass.depthAttachment.texture = depthTexture; pass.depthAttachment.loadAction = .clear
    pass.depthAttachment.storeAction = .dontCare; pass.depthAttachment.clearDepth = 1
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw Failure.check("render encoder") }
    encoder.setRenderPipelineState(capture.pipeline); encoder.setCullMode(.none)
    let positions: [Float] = [-1, -1, 0, 3, -1, 0, -1, 3, 0]
    let vertices = stride(from: 0, to: 9, by: 3).map { index in
        Vertex(position: SIMD4(positions[index], positions[index + 1], positions[index + 2], 1),
               uvLayer: SIMD4(0.5, 0.5, 0, 0), tint: value.day, dusk: value.dusk)
    }
    var uniforms = Uniforms(); uniforms.settings.z = value.night; uniforms.tintColor = value.weather; uniforms.fogSettings.z = value.fog
    vertices.withUnsafeBytes { encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 0) }
    encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
    positions.withUnsafeBytes {
        encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 2)
        encoder.setVertexBytes($0.baseAddress!, length: $0.count, index: 3)
    }
    var mix: Float = 0.5; encoder.setVertexBytes(&mix, length: MemoryLayout<Float>.stride, index: 4)
    encoder.setFragmentTexture(atlas, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); encoder.endEncoding()
    if output.storageMode == .managed {
        guard let blit = command.makeBlitCommandEncoder() else { throw Failure.check("readback encoder") }
        blit.synchronize(resource: target); blit.endEncoding()
    }
    command.commit(); command.waitUntilCompleted()
    try check(command.status == .completed, "GPU command completion: \(String(describing: command.error))")
    var bytes = [UInt8](repeating: 0, count: 4)
    bytes.withUnsafeMutableBytes { target.getBytes($0.baseAddress!, bytesPerRow: 4, from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0) }
    rendered += 1
    return SIMD4(bytes[2], bytes[1], bytes[0], bytes[3])
}

private struct BatchMesh { let id: Int }
private final class BatchEncoder {
    var state = "ordinary", bias: Float = 0
    var draws: [(Int, Float, String, Float)] = []
    func setRenderPipelineState(_ value: String) { state = value }
    func setDepthBias(_ value: Float, slopeScale: Float, clamp: Float) { bias = value }
}
private final class SharpBind {
    var fail=false,binds=0
    func bind(encoder:BatchEncoder,queue:Int)throws{binds+=1;if fail{throw Failure.check("authored unavailable upload")}}
}
private func productionBatch(_ encoder: BatchEncoder, meshes: [String: BatchMesh], activeDetails: Set<String>,
    worldSharpName:String?=nil,worldSharpSource:String?=nil,worldSharpGPU:SharpBind?=nil,worldSharpPipeline:String?="sharp") {
    let queue=0
    var deferredWorldSurfaces:[Int]=[]
    func stageWorldSurface(name:String,mesh:BatchMesh,matrix:simd_float4x4,encoder:BatchEncoder)->Bool{false}
    func fixedCJSourceIdentity()->String{"current"}
    let worldPipeline = "world", pipeline = "ordinary", matrix = matrix_identity_float4x4
    func draw(mesh: BatchMesh, cellSize: Float, matrix: simd_float4x4, encoder: BatchEncoder) {
        encoder.draws.append((mesh.id, cellSize, encoder.state, encoder.bias))
    }
    // PRODUCTION_WORLD_BATCH
}

@main private struct WorldMaterialsSmoke {
    static func main() {
        var report: [String: Any] = [:]
        let path = URL(fileURLWithPath: CommandLine.arguments[2])
        do {
            try check(MemoryLayout<Vertex>.stride == 64 && MemoryLayout<Uniforms>.stride == 128, "native vertex/uniform ABI")
            if let device = MTLCreateSystemDefaultDevice() {
                let shader = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
                let library = try device.makeLibrary(source: shader, options: nil)
                let spy = DeviceSpy(device, library)
                guard let captures = productionPipelines(spy), let queue = device.makeCommandQueue(),
                      let world = captures.first(where: { $0.vertex == "worldVertex" && $0.fragment == "worldFragment" && $0.writes == .all }),
                      let animated = captures.first(where: { $0.vertex == "animatedActorVertex" && $0.writes == .all }),
                      let ordinary = captures.first(where: { $0.vertex == "worldVertex" && $0.fragment == "ordinaryModelFragment" && $0.writes == .all }) ?? captures.first(where: { $0.vertex == "worldVertex" && $0.writes == .all })
                else { throw Failure.check("actual constructor's world/static/animated pipeline availability") }
                var cases = [Case(name: "zero-prelight-day")]
                for night: Float in [0, 0.25, 0.5, 0.75, 1] {
                    var value = Case(name: "authored-day-night-\(night)")
                    value.day = SIMD4(0.25, 0.5, 0.75, 1); value.night = night
                    value.texture = SIMD4(128, 192, 64, 255); cases.append(value)
                    var weather = value; weather = Case(name: "weather-fog-alpha-\(night)", day: value.day, dusk: value.dusk, texture: value.texture, night: night,
                                                       weather: SIMD4(0.8, 0.9, 0.7, 0.6), fog: 0.8, clear: SIMD4(0.125, 0.25, 0.375, 0.5))
                    cases.append(weather)
                }
                var transparent = Case(name: "native-cutout-preserved"); transparent.day.w = 0.01; transparent.clear = SIMD4(0.125, 0.25, 0.375, 0.5); cases.append(transparent)
                var bright = Case(name: "full-prelight-preserves-albedo"); bright.day = SIMD4(repeating: 1); bright.texture = SIMD4(97, 143, 211, 255); cases.append(bright)
                for (role, state, worldRole) in [("world", world, true), ("ordinary", ordinary, false), ("animated", animated, false)] {
                    for value in cases {
                        let got = try render(value, capture: state, device: device, queue: queue), wanted = expected(value, world: worldRole)
                        let differences = (0..<4).map { abs(Int(got[$0]) - Int(wanted[$0])) }
                        try check(differences.allSatisfy { $0 <= 3 }, "\(role)/\(value.name): got \(got), expected \(wanted)")
                    }
                }
                try check(animated.fragment == "ordinaryModelFragment" && ordinary.fragment == "ordinaryModelFragment", "fallback static/animated model ownership")
                report["gpu"] = "PASS"; report["device"] = device.name
            } else {
                try check(CommandLine.arguments[3] != "require-gpu", "a physical Metal device is required for this invocation")
                report["gpu"] = "UNAVAILABLE: no render claim"
            }
            let batch = BatchEncoder()
            productionBatch(batch, meshes: ["t0": .init(id: 10), "c0": .init(id: 20), "unused": .init(id: 30)], activeDetails: ["c0", "missing"])
            try check(batch.draws.map { $0.0 } == [10, 20], "actual world batch selects far then active detail meshes")
            try check(batch.draws.map { $0.1 } == [64, 128] && batch.draws.allSatisfy { $0.2 == "world" }, "actual batch uses world material and native atlas sizes")
            try check(batch.state == "ordinary" && batch.bias == 0, "world pass restores generic material and depth bias")
            let empty = BatchEncoder(); productionBatch(empty, meshes: [:], activeDetails: [])
            try check(empty.draws.isEmpty && empty.state == "ordinary" && empty.bias == 0, "empty world pass preserves later model state")
            let images=SharpBind(),sharp=BatchEncoder()
            productionBatch(sharp,meshes:["t0":.init(id:10),"c0":.init(id:20),"c1":.init(id:21)],activeDetails:["c0","c1"],
                worldSharpName:"c0",worldSharpSource:"current",worldSharpGPU:images)
            try check(images.binds==1 && sharp.draws.first?.2=="world" && sharp.draws.first(where:{$0.0==20})?.2=="sharp" && sharp.draws.first(where:{$0.0==21})?.2=="world","Only the admitted central cell uses the HD pipeline")
            try check(sharp.state=="ordinary" && sharp.bias==0,"HD batch restores ordinary state")
            for failure in ["source","upload","pipeline"] {
                let failed=SharpBind(),fallback=BatchEncoder();failed.fail=failure=="upload"
                productionBatch(fallback,meshes:["c0":.init(id:20)],activeDetails:["c0"],worldSharpName:"c0",
                    worldSharpSource:failure=="source" ? "retired":"current",worldSharpGPU:failed,
                    worldSharpPipeline:failure=="pipeline" ? nil:"sharp")
                try check(fallback.draws.count==1 && fallback.draws[0].2=="world","Unavailable HD family retains actual base material: "+failure)
            }
            report["status"] = "PASS"
        } catch { report["status"] = "FAIL"; report["error"] = String(describing: error) }
        report["checks"] = checks; report["renderedPixels"] = rendered
        report["scope"] = "Authored pixels; actual shader/constructor execution requires gpu=PASS. ABI and literal batch checks run on every host with view/draw boundaries. No original assets or retail scene claim."
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: path)
        print(String(data: try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
        if report["status"] as? String != "PASS" { exit(1) }
    }
}
