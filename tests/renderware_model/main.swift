// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal
import simd

var checks = 0
let cpuOnly = CommandLine.arguments.contains("--cpu-only")
let testArguments = CommandLine.arguments.filter { $0 != "--cpu-only" }
func require(_ condition: @autoclosure () -> Bool, _ label: String) {
    checks += 1
    if !condition() { fatalError("static model regression: \(label)") }
}
func failure(_ label: String, _ body: () throws -> Void) {
    do { try body(); fatalError("expected bounded failure: \(label)") }
    catch is NativeRenderWareModel.Failure { checks += 1 }
    catch { fatalError("unexpected error for \(label): \(error)") }
}
typealias DFF = NativeRenderWareDFF
typealias Model = NativeRenderWareModel
let white = SIMD4<UInt8>(repeating: 255)
func material(_ texture: String? = nil, color: SIMD4<UInt8> = SIMD4(repeating: 255), filtering: UInt32? = 0x1101) -> DFF.Material {
    DFF.Material(flags: 0, color: color, textureName: texture, maskName: nil, textureFilterAndAddressing: filtering, surface: nil)
}
func geometry(_ materials: [DFF.Material] = [material()], skin: DFF.Skin? = nil) -> DFF.Geometry {
    let positions: [SIMD3<Float>] = [SIMD3(-1,-1,0), SIMD3(1,-1,0), SIMD3(-1,1,0), SIMD3(1,1,0)]
    let normals = [SIMD3<Float>](repeating: SIMD3(0,0,1), count: 4)
    let target = DFF.MorphTarget(boundingSphere: SIMD4(0,0,0,2), positions: positions, normals: normals)
    return DFF.Geometry(flags: 0, vertexCount: 4, textureCoordinates: [[SIMD2(0,0), SIMD2(1,0), SIMD2(0,1), SIMD2(1,1)]],
                        prelitColors: [white,white,white,white], triangles: [DFF.Triangle(a: 0,b: 1,c: 2,material: 0), DFF.Triangle(a: 2,b: 1,c: 3,material: 0)],
                        materials: materials, morphTargets: [target], skin: skin)
}
func clump(_ geometry: DFF.Geometry, count: Int = 1, flags: UInt32 = 4) -> DFF {
    let frame = DFF.Frame(name: "static", parent: -1, flags: 0, localTransform: matrix_identity_float4x4, worldTransform: matrix_identity_float4x4, hierarchy: nil)
    return DFF(version: 0, frames: [frame], geometries: [geometry], atomics: (0..<count).map { _ in DFF.Atomic(frame: 0,geometry: 0,flags: flags,unused: 0) })
}
let colors: [UInt8] = [255,0,0,255, 0,255,0,255, 0,0,255,255, 255,255,255,255]
let texture = NativeRenderWareTXD.Texture(name: "CHECK", maskName: "", filterAddressing: 0x1101, rasterFormat: 0x8500,
    d3dFormat: 21, depth: 32, nativeFlags: 1,
    mipLevels: [.init(width: 2,height: 2,encodedByteCount: 16,rgba8: Data(colors),containsTransparentPixels: false),
                .init(width: 1,height: 1,encodedByteCount: 4,rgba8: Data([127,127,127,255]),containsTransparentPixels: false)])
let txd = NativeRenderWareTXD.TextureDictionary(version: 0,deviceID: 2,textures: [texture],decodedByteCount: 20)

require(MemoryLayout<Model.Vertex>.stride == 64, "Metal vertex ABI stride")
require(MemoryLayout<Model.Vertex>.offset(of: \.position) == 0, "position ABI")
require(MemoryLayout<Model.Vertex>.offset(of: \.normal) == 16, "normal ABI")
require(MemoryLayout<Model.Vertex>.offset(of: \.uv) == 32, "UV ABI")
require(MemoryLayout<Model.Vertex>.offset(of: \.color) == 48, "color ABI")
require(MemoryLayout<Model.Uniforms>.stride == 240, "Metal uniform ABI")
require(MemoryLayout<Model.Uniforms>.offset(of: \.settings) == 224, "settings ABI")

let untextured = try Model.prepare(dff: clump(geometry()), txd: nil)
require(untextured.isComplete && untextured.textures.isEmpty, "untextured materials valid")
let plan = try Model.prepare(dff: clump(geometry([material("check")]), count: 20), txd: txd)
require(plan.geometries.count == 1 && plan.instances.count == 20 && plan.draws.count == 20, "repeated atomics share geometry")
require(plan.textures.count == 1 && plan.meshByteCount == 4 * 64 + 6 * 4 && plan.textureByteCount == 20, "bounded unique resource accounting")
require(plan.geometries[0].vertices[2].uv == SIMD2(0,1), "original UVs preserved")
require(plan.geometries[0].vertices[2].normal == SIMD3(0,0,1), "original normals preserved")
require(plan.geometries[0].indices == [0,1,2,2,1,3], "original winding preserved")
require(plan.geometries[0].materials[0].textureIndex == 0 && plan.isComplete, "case insensitive texture resolution")
let missing = try Model.prepare(dff: clump(geometry([material("missing")])), txd: txd)
require(!missing.isComplete && missing.diagnostics == [.missingTexture(geometry: 0,material: 0,name: "missing")], "unresolved diagnostic")
let unused = try Model.prepare(dff: clump(geometry([material(),material("unused_missing", filtering: 0)])), txd: nil)
require(unused.isComplete && unused.textures.isEmpty, "unused material does not require resources")
let hidden = try Model.prepare(dff: clump(geometry(), count: 10,flags: 1), txd: nil)
require(hidden.geometries.isEmpty && hidden.instances.isEmpty && !hidden.isComplete, "non-render atomics skipped")
let skin = DFF.Skin(boneCount: 1, usedBones: [0], maximumWeights: 1, indices: [SIMD4<UInt8>](repeating: SIMD4(repeating: 0), count: 4),
                    weights: [SIMD4<Float>](repeating: SIMD4(1,0,0,0), count: 4), inverseBindMatrices: [matrix_identity_float4x4])
failure("skinned geometry") { _ = try Model.prepare(dff: clump(geometry(skin: skin)), txd: nil) }
let hiddenSkin = try Model.prepare(dff: clump(geometry(skin: skin),flags: 1), txd: nil)
require(hiddenSkin.draws.isEmpty, "non-render skin does not pretend to load")
let alpha = try Model.prepare(dff: clump(geometry([material(color: SIMD4(23,45,67,128))])), txd: nil)
require(alpha.geometries[0].materials[0].usesBlending && alpha.geometries[0].materials[0].source.color == SIMD4(23,45,67,128), "material alpha/color preserved")
let original = geometry()
let colored = DFF.Geometry(flags: original.flags,vertexCount: original.vertexCount,
    textureCoordinates: [[SIMD2(-0.25,2),SIMD2(1,0),SIMD2(0,1),SIMD2(1,1)]],
    prelitColors: [SIMD4(128,64,255,32),white,white,white],triangles: original.triangles,
    materials: original.materials,morphTargets: original.morphTargets,skin: nil)
let attributes = try Model.prepare(dff: clump(colored),txd: nil)
require(attributes.geometries[0].vertices[0].uv == SIMD2(-0.25,2), "unclamped full UV coordinates")
require(attributes.geometries[0].vertices[0].color == SIMD4<Float>(128,64,255,32)/255, "prelit RGBA conversion")
require(attributes.geometries[0].materials[0].usesBlending, "prelit alpha affects draw")
for f in 1...6 { for u in 1...4 { for v in 1...4 {
    let sampler = try Model.sampler(UInt32(f | u << 8 | v << 12))
    require(sampler.filter == f && sampler.addressU == u && sampler.addressV == v, "filter/address bits")
} } }
failure("unknown filter") { _ = try Model.sampler(0x1100) }
failure("unknown address") { _ = try Model.sampler(0x5101) }
let inheritedV = try Model.sampler(0x10106), explicitV = try Model.sampler(0x11106)
require(inheritedV == explicitV, "legacy omitted V inherits U")
for (label, change) in [
    ("vertices", { (l: inout Model.Limits) in l.vertices = 3 }),
    ("indices", { (l: inout Model.Limits) in l.indices = 5 }),
    ("instances", { (l: inout Model.Limits) in l.instances = 19 }),
    ("draws", { (l: inout Model.Limits) in l.draws = 19 }),
    ("meshBytes", { (l: inout Model.Limits) in l.meshBytes = 279 }),
    ("textureBytes", { (l: inout Model.Limits) in l.textureBytes = 19 })
] {
    var limits = Model.Limits(); change(&limits)
    failure(label) { _ = try Model.prepare(dff: clump(geometry([material("CHECK")]),count: 20),txd: txd,limits: limits) }
}
var materialLimits = Model.Limits(); materialLimits.materials = 1
failure("material slots") { _ = try Model.prepare(dff: clump(geometry([material(),material()])),txd: nil,limits: materialLimits) }
let omitted = NativeRenderWareTXD.Texture(name: "tail",maskName: "",filterAddressing: 0x1101,rasterFormat: 0x8200,d3dFormat: 0x31545844,depth: 16,nativeFlags: 8,
                                        mipLevels: [.init(width: 2,height: 2,encodedByteCount: 8,rgba8: Data(colors),containsTransparentPixels: false),
                                                    .init(width: 1,height: 1,encodedByteCount: 0,rgba8: nil,containsTransparentPixels: false)])
let partial = try Model.prepare(dff: clump(geometry([material("tail")])),txd: .init(version: 0,deviceID: 2,textures: [omitted],decodedByteCount: 16))
require(!partial.isComplete && partial.diagnostics == [.omittedMipTail(texture: "tail",firstMissingLevel: 1)], "missing mip never invented")

// Independently authored found-dictionary ownership cases. Both original raw
// fields are retained; cached native state wins over a DFF stream request.
func dictionary(_ filtering: UInt32, name: String = "CHECK") -> NativeRenderWareTXD.TextureDictionary {
    let value = NativeRenderWareTXD.Texture(name: name,maskName: texture.maskName,filterAddressing: filtering,
        rasterFormat: texture.rasterFormat,d3dFormat: texture.d3dFormat,depth: texture.depth,nativeFlags: texture.nativeFlags,mipLevels: texture.mipLevels)
    return .init(version: 0,deviceID: 2,textures: [value],decodedByteCount: 20)
}
let found = try Model.prepare(dff: clump(geometry([material("check",filtering: 0x13306)])),txd: dictionary(0x1201))
let foundMaterial = found.geometries[0].materials[0]
require(foundMaterial.sampler.filter == 1 && foundMaterial.sampler.addressU == 2 && foundMaterial.sampler.addressV == 1,
        "found native dictionary sampler wins over DFF request")
require(foundMaterial.source.textureFilterAndAddressing == 0x13306 && found.textures[0].filterAddressing == 0x1201,
        "sampler selection never rewrites either original field")
require(found.textureByteCount == 20 && found.textures[0].mipLevels.count == 2 && found.textures[0].mipLevels[0].rgba8 == Data(colors),
        "sampler selection preserves resident mips and original pixels")
for nativeFilter in 1...6 {
    let selected = try Model.prepare(dff: clump(geometry([material("CHECK",filtering: 0x3306)])),txd: dictionary(UInt32(0x1200 | nativeFilter)))
    let actual = selected.geometries[0].materials[0].sampler
    require(actual.filter == nativeFilter && actual.addressU == 2 && actual.addressV == 1,"all found native filter modes retain their own address state")
}
let ignoredRequest = try Model.prepare(dff: clump(geometry([material("CHECK",filtering: 0)])),txd: dictionary(0x1101))
require(ignoredRequest.geometries[0].materials[0].sampler.filter == 1 && ignoredRequest.geometries[0].materials[0].source.textureFilterAndAddressing == 0,
        "invalid unused DFF request cannot override valid found-native state")
let absentRequest = try Model.prepare(dff: clump(geometry([material("CHECK",filtering: nil)])),txd: dictionary(0x2302))
require(absentRequest.geometries[0].materials[0].sampler.filter == 2 && absentRequest.geometries[0].materials[0].sampler.addressU == 3,
        "found native state also works without DFF request")
for malformed in [UInt32(0x1100),0x1001,0x1501,0x5101,0x1107] {
    failure("invalid found-native sampler remains unsupported") {
        _ = try Model.prepare(dff: clump(geometry([material("CHECK",filtering: 0x1101)])),txd: dictionary(malformed))
    }
}
let unresolvedRequest = try Model.prepare(dff: clump(geometry([material("absent",filtering: 0x2302)])),txd: dictionary(0x1101))
require(unresolvedRequest.diagnostics == [.missingTexture(geometry: 0,material: 0,name: "absent")] && unresolvedRequest.textures.isEmpty,
        "missing name does not gain a fabricated dictionary match")
let unresolvedSampler = unresolvedRequest.geometries[0].materials[0].sampler
require(unresolvedSampler.filter == 2 && unresolvedSampler.addressU == 3 && unresolvedSampler.addressV == 2,
        "unresolved request metadata retains prior DFF sampler behavior")
failure("invalid unresolved DFF sampler is not silently repaired") {
    _ = try Model.prepare(dff: clump(geometry([material("absent",filtering: 0)])),txd: dictionary(0x1101))
}
let emptyName = try Model.prepare(dff: clump(geometry([material("",filtering: 0x3302)])),txd: dictionary(0x1101))
require(emptyName.isComplete && emptyName.textures.isEmpty && emptyName.geometries[0].materials[0].sampler.filter == 2,
        "empty-name material keeps its prior non-lookup behavior")
let unrelatedBad = dictionary(0,name: "unused")
let unrelated = try Model.prepare(dff: clump(geometry([material("CHECK",filtering: 0x3306)])),txd: .init(version: 0,deviceID: 2,
    textures: unrelatedBad.textures + txd.textures,decodedByteCount: 40))
require(unrelated.isComplete && unrelated.textures.count == 1 && unrelated.geometries[0].materials[0].sampler.filter == 1,
        "unselected invalid native texture is not promoted into this model")

var gpuResult = cpuOnly ? "disabled-by-cpu-only-test-option" : "unavailable"
var gpuDevice: String?
if !cpuOnly, let device = MTLCreateSystemDefaultDevice() {
    gpuDevice = device.name
    guard testArguments.count >= 2 else { fatalError("pass NativeRenderWareModel.metal path") }
    let source = try String(contentsOfFile: testArguments[1], encoding: .utf8)
    let library = try device.makeLibrary(source: source, options: nil)
    let pipelines = try Model.Pipelines(device: device,library: library,color: .rgba8Unorm)
    let gpu = try Model.Uploaded(plan: plan,device: device)
    require(gpu.textures[0].width == 2 && gpu.textures[0].height == 2 && gpu.textures[0].mipmapLevelCount == 2, "original mip dimensions uploaded")
    var basePixels = [UInt8](repeating: 0,count: 16)
    gpu.textures[0].getBytes(&basePixels,bytesPerRow: 8,from: MTLRegionMake2D(0,0,2,2),mipmapLevel: 0)
    require(basePixels == colors, "GPU upload preserves RGBA")
    var lastMip = [UInt8](repeating: 0,count: 4)
    gpu.textures[0].getBytes(&lastMip,bytesPerRow: 4,from: MTLRegionMake2D(0,0,1,1),mipmapLevel: 1)
    require(lastMip == [127,127,127,255], "all resident mips uploaded")
    let partialGPU = try Model.Uploaded(plan: partial,device: device)
    require(partialGPU.textures[0].mipmapLevelCount == 1, "empty tail not fabricated")
    let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,width: 4,height: 4,mipmapped: false)
    colorDescriptor.storageMode = .shared; colorDescriptor.usage = [.renderTarget,.shaderRead]
    let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float,width: 4,height: 4,mipmapped: false)
    depthDescriptor.storageMode = .private; depthDescriptor.usage = .renderTarget
    guard let color = device.makeTexture(descriptor: colorDescriptor), let depth = device.makeTexture(descriptor: depthDescriptor),
          let queue = device.makeCommandQueue(), let command = queue.makeCommandBuffer() else { fatalError("offscreen resources") }
    let pass = MTLRenderPassDescriptor(); pass.colorAttachments[0].texture = color
    pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,1)
    pass.depthAttachment.texture = depth; pass.depthAttachment.loadAction = .clear; pass.depthAttachment.storeAction = .dontCare; pass.depthAttachment.clearDepth = 1
    guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { fatalError("offscreen encoder") }
    encoder.setViewport(MTLViewport(originX: 0,originY: 0,width: 4,height: 4,znear: 0,zfar: 1))
    try gpu.encode(drawIndex: 0,encoder: encoder,pipelines: pipelines,viewProjection: matrix_identity_float4x4,modelTransform: matrix_identity_float4x4)
    var hiddenOverride = Model.DrawOverrides(); hiddenOverride.visible = false
    try gpu.encode(drawIndex: -1,encoder: encoder,pipelines: pipelines,viewProjection: matrix_identity_float4x4,modelTransform: matrix_identity_float4x4,overrides: hiddenOverride)
    encoder.endEncoding()
    // GPU-written texture getBytes can expose a stale CPU mapping on a discrete
    // GPU. Copy the actual target into a shared buffer before CPU assertions.
    let readback = device.makeBuffer(length: 256*4,options: .storageModeShared)!
    let blit = command.makeBlitCommandEncoder()!
    blit.copy(from: color,sourceSlice: 0,sourceLevel: 0,sourceOrigin: MTLOrigin(x: 0,y: 0,z: 0),
        sourceSize: MTLSize(width: 4,height: 4,depth: 1),to: readback,destinationOffset: 0,destinationBytesPerRow: 256,destinationBytesPerImage: 1024)
    blit.endEncoding(); command.commit(); command.waitUntilCompleted()
    require(command.status == .completed, "GPU command completed")
    let sourceBytes=readback.contents().assumingMemoryBound(to: UInt8.self)
    var pixels: [UInt8] = []
    for row in 0..<4 { pixels.append(contentsOf: UnsafeBufferPointer(start: sourceBytes+row*256,count: 16)) }
    var expected: [UInt8] = []
    for y in 0..<4 { for x in 0..<4 { let sample = ((y < 2 ? 1 : 0) * 2 + x / 2) * 4; expected.append(contentsOf: colors[sample..<sample+4]) } }
    require(pixels == expected, "Metal shader UV/color orientation and full-resolution texels")
    gpuResult = "passed-offscreen-4x4-rgba-and-mip-readback"
}
var report: [String: Any] = ["cpu": "passed", "metal": gpuResult, "metalDevice": gpuDevice as Any? ?? NSNull(),
    "gpuReadback": "explicit texture-to-shared-buffer blit; discrete GPU texture CPU mapping may be stale",
    "sharedGeometryInstances": 20, "samplerConfigurations": 96,"checks":checks,"foundNativeSamplerCases":"passed"]
var ownerFailures = false
if testArguments.count >= 3 {
    let folder = URL(fileURLWithPath: testArguments[2])
    let paths = try FileManager.default.contentsOfDirectory(at: folder,includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "dff" }.sorted { $0.path < $1.path }
    let rejectedData = try Data(contentsOf: URL(fileURLWithPath: testArguments[3]))
    let expectedRejected = Set(try JSONDecoder().decode([String].self,from: rejectedData))
    var prepared = 0, skins = 0, unsupported = 0, referenceRejected = 0, draws = 0, unresolved = 0, complete = 0
    var unexpected: [String] = []
    for path in paths {
        do {
            let data = try Data(contentsOf: path)
            let decoded = try DFF.decode(data)
            if expectedRejected.contains(path.lastPathComponent) {
                unexpected.append("\(path.lastPathComponent): accepted independently invalid DFF")
                continue
            }
            let texturePath = path.deletingPathExtension().appendingPathExtension("txd")
            let dictionary = FileManager.default.fileExists(atPath: texturePath.path) ? try NativeRenderWareTXD.decode(Data(contentsOf: texturePath)) : nil
            let result = try Model.prepare(dff: decoded,txd: dictionary)
            prepared += 1; draws += result.draws.count; complete += result.isComplete ? 1 : 0
            unresolved += result.diagnostics.filter { if case .missingTexture = $0 { return true }; return false }.count
        } catch let error as Model.Failure {
            if case .unsupported(let reason) = error, reason.hasPrefix("skinned geometry") { skins += 1 }
            else { unexpected.append("\(path.lastPathComponent): \(error)") }
        } catch let error as DFF.Failure {
            if expectedRejected.contains(path.lastPathComponent) { referenceRejected += 1 }
            else if case .unsupported = error { unsupported += 1 }
            else { unexpected.append("\(path.lastPathComponent): \(error)") }
        } catch { unexpected.append("\(path.lastPathComponent): \(error)") }
    }
    report["ownerLocal"] = ["files": paths.count,"preparedStatic": prepared,"completeStaticResources": complete,
                            "renderDraws": draws,"explicitlyRejectedSkins": skins,"unsupportedDFF": unsupported,
                            "independentlyInvalidDFFRejected": referenceRejected,
                            "unresolvedMaterialNames": unresolved,"unexpected": unexpected]
    ownerFailures = !unexpected.isEmpty
}
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report,options: [.sortedKeys]))
FileHandle.standardOutput.write(Data([10]))
if ownerFailures { exit(1) }
