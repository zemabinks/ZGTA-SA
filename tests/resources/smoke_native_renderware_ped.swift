// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal
import simd

private enum PedTestFailure: Error { case failed(String) }
private func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw PedTestFailure.failed(message) }
}
private func reject(_ message: String, _ body: () throws -> Void) throws {
    do { try body() } catch { return }
    throw PedTestFailure.failed("expected rejection: " + message)
}

@main struct RenderWarePedSmoke {
    private struct OwnerCases:Decodable{let models:[String];let skeletons:[String:String]}
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1]), out = URL(fileURLWithPath: CommandLine.arguments[2])
        let game = root.appendingPathComponent("local-only/site/game")
        let ownerCases:OwnerCases
        if CommandLine.arguments.count>3 {
            ownerCases=try JSONDecoder().decode(OwnerCases.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3])))
            try check(!ownerCases.models.isEmpty && ownerCases.models.count<=16 && Set(ownerCases.models).count==ownerCases.models.count,"bounded owner cases")
        }else{ownerCases=OwnerCases(models:["bmori","army","wmopj"],skeletons:[:])}
        let generated = try NativeRenderWareDFF.decode(Data(contentsOf: out.appendingPathComponent("generated.dff")))
        let source = generated.geometries[0]
        let normals = [SIMD3<Float>](repeating: SIMD3(0,0,1), count: source.vertexCount)
        let uv: [SIMD2<Float>] = [SIMD2(0,0),SIMD2(1,0),SIMD2(0,1),SIMD2(1,1)]
        let colors: [SIMD4<UInt8>] = [SIMD4(255,128,64,255),SIMD4(64,255,128,255),SIMD4(128,64,255,255),SIMD4(repeating: 255)]
        func model(textureName: String?, uvSets: [[SIMD2<Float>]] = []) -> NativeRenderWareDFF {
            let material = NativeRenderWareDFF.Material(flags: 0,color: SIMD4(repeating: 255),textureName: textureName,
                maskName: nil,textureFilterAndAddressing: 0x1101,surface: nil)
            let target = NativeRenderWareDFF.MorphTarget(boundingSphere: source.morphTargets[0].boundingSphere,
                positions: source.positions,normals: normals)
            let geometry = NativeRenderWareDFF.Geometry(flags: source.flags,vertexCount: source.vertexCount,
                textureCoordinates: uvSets,prelitColors: colors,
                triangles: source.triangles + [.init(a: 1,b: 2,c: 0,material: 0)],
                materials: [material,material],morphTargets: [target],skin: source.skin)
            return NativeRenderWareDFF(version: generated.version,frames: generated.frames,geometries: [geometry],atomics: generated.atomics)
        }
        let pixels: [UInt8] = [255,0,0,255, 0,255,0,255, 0,0,255,255, 255,255,255,255]
        let texture = NativeRenderWareTXD.Texture(name: "CHECK",maskName: "",filterAddressing: 0x1101,
            rasterFormat: 0x8500,d3dFormat: 21,depth: 32,nativeFlags: 1,
            mipLevels: [.init(width: 2,height: 2,encodedByteCount: 16,rgba8: Data(pixels),containsTransparentPixels: false)])
        let txd = NativeRenderWareTXD.TextureDictionary(version: 0,deviceID: 2,textures: [texture],decodedByteCount: 16)
        let fixture = model(textureName: "check",uvSets: [uv,uv.map { $0 * 0.5 }])
        let plan = try NativeRenderWarePedModel.prepare(dff: fixture,txd: txd)
        try check(plan.model.geometries[0].vertices.count == 6, "material-split vertex count")
        try check(plan.model.geometries[0].indices == [0,1,2,1,2,0,3,4,5], "material buckets preserve SKN1 vertex order")
        try check(plan.model.geometries[0].parts.map(\.indexCount) == [6,3], "material draw ranges")
        for (index, vertex) in plan.skeleton.vertices.enumerated() {
            let mesh = plan.model.geometries[0].vertices[index]
            try check(mesh.position == source.positions[vertex.sourceIndex] && mesh.uv == uv[vertex.sourceIndex], "source positions/UVs")
            try check(mesh.color == SIMD4<Float>(colors[vertex.sourceIndex]) / 255 && mesh.normal == normals[vertex.sourceIndex], "prelit/normal alignment")
            try check(plan.model.geometries[0].textureCoordinates[1][index] == uv[vertex.sourceIndex] * 0.5, "additional UV remapping")
        }
        try check(plan.model.textures.count == 1 && plan.model.meshByteCount == 6*64+9*4, "resource budget/dedup")
        try reject("missing named texture") { _ = try NativeRenderWarePedModel.prepare(dff: model(textureName: "missing",uvSets: [uv]),txd: txd) }
        try reject("missing UVs") { _ = try NativeRenderWarePedModel.prepare(dff: model(textureName: "check"),txd: txd) }
        try reject("additional UV count") { _ = try NativeRenderWarePedModel.prepare(dff: model(textureName: "check",uvSets: [uv,[]]),txd: txd) }
        var limits = NativeRenderWareModel.Limits(); limits.meshBytes = 6*64+9*4-1
        try reject("split mesh bytes") { _ = try NativeRenderWarePedModel.prepare(dff: fixture,txd: txd,modelLimits: limits) }
        limits = .init(); limits.vertices = 5
        try reject("split vertex count") { _ = try NativeRenderWarePedModel.prepare(dff: fixture,txd: txd,modelLimits: limits) }
        let untextured = try NativeRenderWarePedModel.prepare(dff: model(textureName: nil,uvSets: []),txd: nil)
        try check(untextured.model.textures.isEmpty, "legitimate untextured material")
        let oldAtomic = generated.atomics[0]
        let hidden = NativeRenderWareDFF(version: generated.version,frames: generated.frames,geometries: generated.geometries,
            atomics: [.init(frame: oldAtomic.frame,geometry: oldAtomic.geometry,flags: 1,unused: 0)])
        try reject("hidden atomic") { _ = try NativeRenderWarePedModel.prepare(dff: hidden,txd: nil) }
        var report: [String: Any] = ["generatedCPUChecks": true,"gpu": "unavailable","ownerModels": 0]
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            try JSONSerialization.data(withJSONObject: report,options: [.prettyPrinted,.sortedKeys]).write(to: out.appendingPathComponent("report.json"))
            print("CPU PASS; Metal device unavailable in this process"); return
        }
        let shaderSource = try String(contentsOf: root.appendingPathComponent("ios/App/NativeRenderWareModel.metal"),encoding: .utf8) + "\n" +
            String(contentsOf: root.appendingPathComponent("ios/App/NativeRenderWarePedModel.metal"),encoding: .utf8)
        let shader = try device.makeLibrary(source: shaderSource,options: nil)
        let pipelines = try NativeRenderWarePedModel.Pipelines(device: device,library: shader,color: .rgba8Unorm)
        let compute = try device.makeComputePipelineState(function: shader.makeFunction(name: "native_rw_ped_probe")!)
        let animationData = try Data(contentsOf: game.appendingPathComponent("native/models/animations.clips.bin"))
        guard let library = NativeSkeletalAnimationLibrary(data: animationData) else { throw PedTestFailure.failed("real CLP1 library") }
        try check(library.contains("ped/walk_player"), "actual walk clip present")
        var testedModels = 0, poses = 0, sampled = 0, pixelsDrawn = 0
        var positionError: Float = 0, normalError: Float = 0, stockError: Float = 0, walkMotion: Float = 0, aimMotion: Float = 0
        var images = Set<Data>()
        var assets: [(String,NativeRenderWarePedModel.Plan)] = [("generated",plan)]
        for name in ownerCases.models {
            let dff = try NativeRenderWareDFF.decode(Data(contentsOf: game.appendingPathComponent(name + ".dff")))
            let txd = try NativeRenderWareTXD.decode(Data(contentsOf: game.appendingPathComponent(name + ".txd")))
            assets.append((name,try NativeRenderWarePedModel.prepare(dff: dff,txd: txd)))
        }
        var world = simd_float4x4(simd_quatf(angle: 0.35,axis: SIMD3(0,0,1)))
        world.columns.3 = SIMD4(3,-2,0.7,1)
        for (name,asset) in assets {
            let uploaded = try NativeRenderWarePedModel.Uploaded(plan: asset,device: device)
            let actor = uploaded.actor, count = actor.vertexCount
            try check(actor.skinVertices.length == count * MemoryLayout<NativeSkinVertex>.stride, "actual native actor buffer")
            var selected: [(String,NativeSkeletalActor.Pose)] = []
            for time in [0.0,0.17,0.39,0.61] {
                guard let pose = actor.pose(clip: "ped/walk_player",elapsed: time,library: library) else { throw PedTestFailure.failed("actual walk pose") }
                selected.append(("walk-\(time)",pose))
            }
            let blends = [NativeSkeletalBlend(clip: "ped/walk_player",time: 0.39)]
            var aim = NativeSkeletalActor.OriginalAim(); aim.look = 0.2; aim.spinePitch = 0.15; aim.rightArm = 1; aim.pitch = 0.35; aim.yaw = -0.25
            let original = actor.originalPose(blends: blends,library: library)
            let aiming = actor.originalPose(blends: blends,library: library,aim: aim)
            selected.append(("original-walk",original)); selected.append(("original-aim",aiming))
            let first = actor.positions(pose: selected[0].1), moved = actor.positions(pose: selected[2].1)
            walkMotion = max(walkMotion,zip(first,moved).map { simd_distance($0,$1) }.max() ?? 0)
            if name != "generated" {
                aimMotion = max(aimMotion,zip(actor.positions(pose: original),actor.positions(pose: aiming)).map { simd_distance($0,$1) }.max() ?? 0)
                testedModels += 1
            }
            let stock: NativeSkeletalActor? = name == "generated" ? nil : NativeSkeletalActor(data:
                try Data(contentsOf:ownerCases.skeletons[name].map{URL(fileURLWithPath:$0)} ??
                    game.appendingPathComponent("native/models/" + name + ".skel.bin")),vertexCount: count,device: device)
            for (label,pose) in selected {
                let cpu = actor.positions(pose: pose)
                if let stock, label.hasPrefix("walk-"), let time = Double(label.dropFirst(5)),
                   let reference = stock.pose(clip: "ped/walk_player",elapsed: time,library: library) {
                    stockError = max(stockError,zip(cpu,stock.positions(pose: reference)).map { simd_distance($0,$1) }.max() ?? 0)
                }
                let positions = device.makeBuffer(length: count*16,options: .storageModeShared)!
                let normalsOut = device.makeBuffer(length: count*16,options: .storageModeShared)!
                var uniforms = NativeRenderWareModel.Uniforms(viewProjection: matrix_identity_float4x4,model: world,
                    normalMatrix: simd_transpose(simd_inverse(world)),color: SIMD4(repeating: 1),
                    lightDirectionAmbient: SIMD4(0,0,1,1),settings: SIMD4(0,0,0,0))
                var length = UInt32(count)
                let command = queue.makeCommandBuffer()!, encoder = command.makeComputeCommandEncoder()!
                encoder.setComputePipelineState(compute)
                encoder.setBuffer(uploaded.resources.geometries[0].vertices,offset: 0,index: 0)
                encoder.setBuffer(actor.skinVertices,offset: 0,index: 1)
                pose.palette.withUnsafeBytes { encoder.setBytes($0.baseAddress!,length: $0.count,index: 2) }
                encoder.setBytes(&uniforms,length: MemoryLayout<NativeRenderWareModel.Uniforms>.stride,index: 3)
                encoder.setBuffer(positions,offset: 0,index: 4); encoder.setBuffer(normalsOut,offset: 0,index: 5)
                encoder.setBytes(&length,length: 4,index: 6)
                encoder.dispatchThreads(MTLSize(width: count,height: 1,depth: 1),threadsPerThreadgroup: MTLSize(width: min(64,compute.maxTotalThreadsPerThreadgroup),height: 1,depth: 1))
                encoder.endEncoding(); command.commit(); command.waitUntilCompleted()
                try check(command.status == .completed, "ped GPU probe \(name)/\(label): \(String(describing: command.error))")
                let gpu = positions.contents().bindMemory(to: SIMD4<Float>.self,capacity: count)
                let gpuNormals = normalsOut.contents().bindMemory(to: SIMD4<Float>.self,capacity: count)
                var worldPoints: [SIMD3<Float>] = []
                for index in 0..<count {
                    try check((0..<4).allSatisfy({ gpu[index][$0].isFinite && gpuNormals[index][$0].isFinite }),
                              "finite GPU skin outputs \(name)/\(label)")
                    let expected = world * SIMD4(cpu[index],1), vertex = asset.skeleton.vertices[index]
                    let inputNormal = asset.model.geometries[0].vertices[index].normal
                    var normal = SIMD4<Float>.zero
                    for slot in 0..<4 where vertex.weights[slot] > 0 {
                        normal += (pose.palette[Int(vertex.bones[slot])] * SIMD4(inputNormal,0)) * vertex.weights[slot]
                    }
                    normal = uniforms.normalMatrix * normal
                    positionError = max(positionError,simd_distance(SIMD3(gpu[index].x,gpu[index].y,gpu[index].z),SIMD3(expected.x,expected.y,expected.z)))
                    normalError = max(normalError,simd_distance(SIMD3(gpuNormals[index].x,gpuNormals[index].y,gpuNormals[index].z),SIMD3(normal.x,normal.y,normal.z)))
                    worldPoints.append(SIMD3(expected.x,expected.y,expected.z)); sampled += 1
                }
                let minX = worldPoints.map(\.x).min()!, maxX = worldPoints.map(\.x).max()!
                let minZ = worldPoints.map(\.z).min()!, maxZ = worldPoints.map(\.z).max()!
                let sx = 1.8/max(0.001,maxX-minX), sz = 1.8/max(0.001,maxZ-minZ)
                let projection = simd_float4x4(SIMD4(sx,0,0,0),SIMD4(0,0,0,0),SIMD4(0,sz,0,0),
                    SIMD4(-(minX+maxX)*sx/2,-(minZ+maxZ)*sz/2,0.5,1))
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,width: 64,height: 64,mipmapped: false)
                descriptor.storageMode = .shared; descriptor.usage = [.renderTarget,.shaderRead]
                let target = device.makeTexture(descriptor: descriptor)!
                let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,width: 64,height: 64,mipmapped: false)
                depthDescriptor.storageMode = .private; depthDescriptor.usage = .renderTarget
                let depth = device.makeTexture(descriptor: depthDescriptor)!
                let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = target
                pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
                pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0)
                pass.depthAttachment.texture = depth; pass.depthAttachment.loadAction = .clear; pass.depthAttachment.storeAction = .dontCare
                pass.depthAttachment.clearDepth = 1
                let draw = queue.makeCommandBuffer()!, render = draw.makeRenderCommandEncoder(descriptor: pass)!
                for index in asset.model.draws.indices {
                    try uploaded.encode(drawIndex: index,pose: pose,encoder: render,pipelines: pipelines,
                        viewProjection: projection,worldTransform: world)
                }
                render.endEncoding()
                // Read GPU-rendered pixels through an explicit GPU copy, which
                // also works when a discrete GPU's texture CPU mapping is stale.
                let readback=device.makeBuffer(length:64*64*4,options:.storageModeShared)!
                let blit=draw.makeBlitCommandEncoder()!
                blit.copy(from:target,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),
                    sourceSize:MTLSize(width:64,height:64,depth:1),to:readback,destinationOffset:0,
                    destinationBytesPerRow:256,destinationBytesPerImage:64*64*4)
                blit.endEncoding(); draw.commit(); draw.waitUntilCompleted()
                try check(draw.status == .completed, "actual ped vertex/fragment draw \(name)/\(label)")
                let image=Array(UnsafeBufferPointer(start:readback.contents().assumingMemoryBound(to:UInt8.self),count:64*64*4))
                var visible = 0
                for pixel in 0..<(64*64) {
                    let base = pixel * 4
                    let hasColor = image[base] != 0 || image[base+1] != 0 || image[base+2] != 0
                    if image[base+3] > 0 && hasColor { visible += 1 }
                }
                try check(visible > 20, "nonempty textured draw \(name)/\(label)")
                pixelsDrawn += visible; images.insert(Data(image)); poses += 1
                if label == "walk-0.39" { try Data(image).write(to: out.appendingPathComponent(name + "-walk.rgba")) }
            }
        }
        try check(positionError < 0.0001 && normalError < 0.0001 && stockError < 0.0001, "GPU/CPU/stock actor numerical parity")
        try check(walkMotion > 0.01 && aimMotion > 0.01 && images.count >= 8, "walking and aiming visibly animate")
        report.merge(["gpu": "passed","device": device.name,"ownerModels": testedModels,"actualActor": true,
            "ownerModelNames":ownerCases.models,
            "gpuReadback":"explicit texture-to-shared-buffer blit; discrete GPU texture CPU mapping may be stale",
            "posesRendered": poses,"sampledVertices": sampled,"positionMaxError": Double(positionError),
            "normalMaxError": Double(normalError),"stockActorMaxError": Double(stockError),
            "walkMotion": Double(walkMotion),"aimMotion": Double(aimMotion),"visiblePixelSamples": pixelsDrawn,
            "distinctFrames": images.count,"clipCount": library.clipCount]) { _,new in new }
        try JSONSerialization.data(withJSONObject: report,options: [.prettyPrinted,.sortedKeys]).write(to: out.appendingPathComponent("report.json"))
        print("PASS actual actor + ped vertex/fragment + \(poses) animated draws / \(sampled) GPU vertices")
    }
}
