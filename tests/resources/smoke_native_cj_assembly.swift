// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit
import simd

@main enum CJAssemblySmoke {
    static var checks = 0
    enum Failure: Error { case check(String) }
    static func check(_ value: Bool, _ reason: String) throws { checks += 1; if !value { throw Failure.check(reason) } }
    static func reject(_ reason: String, _ body: () throws -> Void) throws {
        do { try body() } catch { checks += 1; return }; throw Failure.check("expected rejection: " + reason)
    }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x",$0) }.joined() }
    static func texture(_ name: String, _ rgba: [UInt8], width: Int = 2, height: Int = 2) -> NativeRenderWareTXD.Texture {
        .init(name: name,maskName: "",filterAddressing: 0x1102,rasterFormat: 0x500,d3dFormat: 21,depth: 32,nativeFlags: 1,
            mipLevels: [.init(width: width,height: height,encodedByteCount: rgba.count,rgba8: Data(rgba),containsTransparentPixels: true)])
    }
    static func modified(_ dff: NativeRenderWareDFF, uv: [[SIMD2<Float>]]? = nil, skin: NativeRenderWareDFF.Skin? = nil,
                         transform: simd_float4x4? = nil) -> NativeRenderWareDFF {
        let g = dff.geometries[0]
        let geo = NativeRenderWareDFF.Geometry(flags: g.flags,vertexCount: g.vertexCount,textureCoordinates: uv ?? g.textureCoordinates,
            prelitColors: g.prelitColors,triangles: g.triangles,materials: g.materials,morphTargets: g.morphTargets,skin: skin ?? g.skin)
        let frames: [NativeRenderWareDFF.Frame]
        if let transform {
            frames = dff.frames.enumerated().map { i,f in
                .init(name: f.name,parent: f.parent,flags: f.flags,localTransform: i == 0 ? transform : f.localTransform,
                    worldTransform: transform * f.worldTransform,hierarchy: f.hierarchy)
            }
        } else { frames = dff.frames }
        return .init(version: dff.version,frames: frames,geometries: [geo],atomics: dff.atomics)
    }
    static func paletteVariant(_ model: NativeRenderWareDFF, extra: Bool, positive: Bool = false) -> NativeRenderWareDFF {
        let old = model.geometries[0].skin!
        var frames = model.frames
        let root = frames.firstIndex { $0.hierarchy?.nodes.isEmpty == false }!
        let hierarchy = frames[root].hierarchy!
        let nodes: [NativeRenderWareDFF.HAnimNode] = extra ? hierarchy.nodes + [.init(id:303,index:2,flags:0)] :
            hierarchy.nodes.map { .init(id:$0.id,index:1-$0.index,flags:$0.flags) }
        let frame = frames[root]
        frames[root] = .init(name:frame.name,parent:frame.parent,flags:frame.flags,localTransform:frame.localTransform,
            worldTransform:frame.worldTransform,hierarchy:.init(version:hierarchy.version,id:hierarchy.id,flags:hierarchy.flags,keyFrameSize:hierarchy.keyFrameSize,nodes:nodes))
        var indices = old.indices, weights = old.weights, inverse = old.inverseBindMatrices
        if extra {
            frames.append(.init(name:"extra",parent:root,flags:0,localTransform:matrix_identity_float4x4,worldTransform:frame.worldTransform,
                hierarchy:.init(version:0x100,id:303,flags:0,keyFrameSize:0,nodes:[])))
            inverse.append(matrix_identity_float4x4)
            for i in indices.indices { indices[i].z = 2 }
            if positive { weights[0] = SIMD4(0.9,0,0.1,0) }
        } else {
            inverse.reverse()
            for i in indices.indices { for j in 0..<4 { indices[i][j] = 1-indices[i][j] } }
        }
        let skin = NativeRenderWareDFF.Skin(boneCount:extra ? 3:2,usedBones:extra ? [0,1,2]:[0,1],maximumWeights:4,
            indices:indices,weights:weights,inverseBindMatrices:inverse)
        let changed = modified(model,skin:skin)
        return .init(version:model.version,frames:frames,geometries:changed.geometries,atomics:model.atomics)
    }
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let normalData = try Data(contentsOf: folder.appendingPathComponent("normal-stream.dff"))
        let templateData = try Data(contentsOf: folder.appendingPathComponent("template.dff"))
        let normal = try NativeCJAssembly.normalClump(from: normalData), template = try NativeRenderWareDFF.decode(templateData)
        try check(normal.frames[normal.atomics[0].frame].name == "Normal","third named clump")
        try reject("ordinary parser must reject concatenated clumps") { _ = try NativeRenderWareDFF.decode(normalData) }
        for name in ["wrong-order","truncated","nonzero-tail","whole-sector-tail","missing-variant"] {
            let data = try Data(contentsOf: folder.appendingPathComponent(name+".dff"))
            try reject(name) { _ = try NativeCJAssembly.normalClump(from: data) }
        }
        let padded = try Data(contentsOf: folder.appendingPathComponent("sector-padded.dff"))
        try check(try NativeCJAssembly.normalClump(from: padded).geometries[0].vertexCount == 4,"bounded allocation padding")
        let parts = NativeCJAssembly.Component.allCases.map { NativeCJAssembly.Part(component: $0,normal: normal) }
        let body = try NativeCJAssembly.prepare(template: template,parts: parts)
        try check(body.dff.geometries[0].vertexCount == 20 && body.dff.geometries[0].triangles.count == 10,"all components joined")
        try check(body.skeleton.bones.count == 2 && body.animationStyleModel == "null","player palette/style")
        for vertex in body.skeleton.vertices {
            try check(vertex.bones.max() < 2 && abs(vertex.weights.sum()-1)<0.00001,"valid common palette influences")
        }
        try check(body.skeleton.floor == -1,"one common body floor")
        try reject("missing component") { _ = try NativeCJAssembly.prepare(template: template,parts: Array(parts.dropLast())) }
        try reject("duplicate component") { _ = try NativeCJAssembly.prepare(template: template,parts: [parts[0],parts[0],parts[2],parts[3],parts[4]]) }
        var altered = parts; altered[1] = .init(component: .head,normal: modified(normal,uv: []))
        try reject("missing material UV") { _ = try NativeCJAssembly.prepare(template: template,parts: altered) }
        var shift = matrix_identity_float4x4; shift.columns.3.x = 1
        altered[1] = .init(component: .head,normal: modified(normal,transform: shift))
        try reject("independent component basis") { _ = try NativeCJAssembly.prepare(template: template,parts: altered) }
        var limits = NativeCJAssembly.Limits(); limits.vertices = 19
        try reject("whole-body budget") { _ = try NativeCJAssembly.prepare(template: template,parts: parts,limits: limits) }
        let old = normal.geometries[0].skin!, weights = old.weights.enumerated().map { i,w in i == 0 ? SIMD4<Float>(0.9,0,0,0) : w }
        let badSkin = NativeRenderWareDFF.Skin(boneCount: old.boneCount,usedBones: old.usedBones,maximumWeights: old.maximumWeights,
            indices: old.indices,weights: weights,inverseBindMatrices: old.inverseBindMatrices)
        altered[1] = .init(component: .head,normal: modified(normal,skin: badSkin))
        try reject("invalid influence normalization") { _ = try NativeCJAssembly.prepare(template: template,parts: altered) }
        altered = parts; altered[1] = .init(component:.head,normal:paletteVariant(normal,extra:false))
        try check(try NativeCJAssembly.prepare(template:template,parts:altered).skeleton.encodedSKN1() == body.skeleton.encodedSKN1(),"palette order joined by ID")
        altered[1] = .init(component:.head,normal:paletteVariant(normal,extra:true))
        let zeroExtra = try NativeCJAssembly.prepare(template:template,parts:altered)
        try check(zeroExtra.parts[1].unusedExtraBoneIDs == [303] && zeroExtra.dff.geometries[0].skin!.indices.allSatisfy { $0.max()<2 },"unused absent bones never reach shader")
        altered[1] = .init(component:.head,normal:paletteVariant(normal,extra:true,positive:true))
        try reject("positive missing template bone") { _ = try NativeCJAssembly.prepare(template:template,parts:altered) }

        let base = texture("skin",Array(repeating: [UInt8](arrayLiteral: 100,120,140,255),count: 4).flatMap { $0 })
        let cut = texture("vest",[255,0,0,0, 1,2,3,1, 4,5,6,128, 7,8,9,255])
        let dictionary = NativeRenderWareTXD.TextureDictionary(version: 0,deviceID: 2,textures: [base,cut],decodedByteCount: 32)
        let recipe = NativeCJTextures.Recipe(output: "torso",base: .init(dictionary: "fixture",texture: "skin"),
            nonzeroAlphaCuts: [.init(dictionary: "fixture",texture: "vest")])
        let composed = try NativeCJTextures.compose([recipe],dictionaries: ["fixture":dictionary])
        try check(composed.textures[0].mipLevels[0].rgba8 == Data([100,120,140,255,1,2,3,1,4,5,6,128,7,8,9,255]),"nonzero alpha copies all channels without source-over")
        try reject("duplicate output") { _ = try NativeCJTextures.compose([recipe,recipe],dictionaries: ["fixture":dictionary]) }
        try reject("missing dictionary") { _ = try NativeCJTextures.compose([recipe],dictionaries: [:]) }
        let wrong = NativeRenderWareTXD.TextureDictionary(version: 0,deviceID: 2,textures: [base,texture("vest",[1,2,3,4],width: 1,height: 1)],decodedByteCount: 20)
        try reject("cut dimensions") { _ = try NativeCJTextures.compose([recipe],dictionaries: ["fixture":wrong]) }
        var tlimits = NativeCJTextures.Limits(); tlimits.decodedOutputBytes = 15
        try reject("decoded byte budget") { _ = try NativeCJTextures.compose([recipe],dictionaries: ["fixture":dictionary],limits: tlimits) }
        let rules = Data("rule\nCUTS head cs_head\nCUTS hands cs_hands\nend\n".utf8)
        let rule = try NativeCJClothesRules.validateFixedNormal(models: ["vest","head","hands","jeans","sneaker"],data: rules)
        try check(rule.commands == 2 && rule.cutsceneReplacements == 2,"cutscene rules not applied to gameplay")
        for ending in ["\r\n","\r"] {
            let bytes = Data("rule\nCUTS head cs_head\nend\n".replacingOccurrences(of:"\n",with:ending).utf8)
            try check(try NativeCJClothesRules.validateFixedNormal(models:["head"],data:bytes).commands == 1,"original Windows line endings")
        }
        try reject("unresolved normal rule") { _ = try NativeCJClothesRules.validateFixedNormal(models: ["vest"],data: Data("rule\nHIDE vest hands\nend".utf8)) }
        try reject("unbalanced ignore") { _ = try NativeCJClothesRules.validateFixedNormal(models: ["vest"],data: Data("rule\nIGNORE hat\nend".utf8)) }
        try reject("unknown rule") { _ = try NativeCJClothesRules.validateFixedNormal(models: ["vest"],data: Data("rule\nNEW vest\nend".utf8)) }
        let txd = try Data(contentsOf: folder.appendingPathComponent("fixture.txd"))
        let dataParts = Dictionary(uniqueKeysWithValues: NativeCJAssembly.Component.allCases.map { ($0,NativeCJResources.ComponentSource(modelName: $0.rawValue,dff: normalData)) })
        let recipes = ["torso","head","legs","feet"].map { NativeCJTextures.Recipe(output: $0,base: .init(dictionary: "fixture",texture: "cloth"),nonzeroAlphaCuts: []) }
        let inputs = NativeCJResources.Input(template: templateData,components: dataParts,dictionaries: ["fixture":txd],recipes: recipes,clothesRules: rules)
        let prepared = try NativeCJResources.prepare(inputs)
        try check(prepared.assembly.dff.geometries[0].vertexCount == 20 && prepared.textures.textures.count == 4,"actual binary resource preparation")
        try check(try NativeCJResources.prepare(inputs).contentIdentity == prepared.contentIdentity,"stable content identity")

        let report: [String: Any] = ["status":"PASS","checks":checks,"fixture":"authored-only",
            "limits":["Fixed Normal candidate preparation only; no authenticated default wardrobe or runtime skin0 registration", "No full wardrobe/body morph, retail silhouette, animation timing, GPU or device acceptance in this CPU gate"]]
        try JSONSerialization.data(withJSONObject: report,options: [.prettyPrinted,.sortedKeys]).write(to: folder.appendingPathComponent("report.json"))
        print("PASS CJ CPU assembly: \(checks) checks")
    }
}
