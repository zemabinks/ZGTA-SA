// SPDX-License-Identifier: AGPL-3.0-only
// Validate the independently authored visual fixture with the actual CPU
// importers and, when available, the actual Metal resource uploader.
import Foundation
import Metal
import simd

@main struct VisualAssetSmoke {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("usage: visual-assets MODEL_DIRECTORY") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let source = try Data(contentsOf: root.appendingPathComponent("qa-sign.dff"))
        let dff = try NativeRenderWareDFF.decode(source)
        let txd = try NativeRenderWareTXD.decode(Data(contentsOf: root.appendingPathComponent("qa-sign.txd")))
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            checks += 1; precondition(value(), "visual fixture: \(message)")
        }
        check(dff.frames.count == 1 && dff.atomics.count == 1 && dff.geometries.count == 1, "one static clump")
        let mesh = dff.geometries[0]
        check(mesh.vertexCount == 4 && mesh.triangles.count == 2 && mesh.skin == nil, "full rectangular sign, not triangle")
        check(mesh.positions == [SIMD3(-3,0,0),SIMD3(3,0,0),SIMD3(-3,0,2),SIMD3(3,0,2)], "authored positions")
        check(mesh.textureCoordinates == [[SIMD2(0,1),SIMD2(1,1),SIMD2(0,0),SIMD2(1,0)]], "full nonclipped UV rectangle")
        check(mesh.normals.allSatisfy { $0 == SIMD3(0,-1,0) }, "face toward initial camera")
        check(mesh.triangles.map { [$0.a,$0.b,$0.c,$0.material] } == [[0,1,2,0],[2,1,3,0]], "both front-facing triangles use slot zero")
        check(mesh.materials.count == 1 && mesh.materials[0].textureName == "qa_sign", "server text replaces material slot zero")
        check(txd.textures.count == 1 && txd.textures[0].name == "qa_sign", "matching independently authored texture")
        check(txd.textures[0].mipLevels.count == 1 && txd.textures[0].mipLevels[0].width == 4 && txd.textures[0].mipLevels[0].height == 4, "texture dimensions")
        check(txd.textures[0].mipLevels[0].rgba8 == Data(repeating: 255,count: 64), "exact RGBA pixels")
        let embedded = try NativeRenderWareCollision.embedded(inDFF: source)
        check(embedded.count == 1 && embedded[0].models.count == 1 && !embedded[0].headerlessLegacy, "framed COL3 clump plugin")
        let col = embedded[0].models[0]
        check(col.version == .col3 && col.hasCollisionVolumes && col.boxes.count == 1, "physical box")
        check(col.mesh.faces.isEmpty && col.mesh.vertices.isEmpty && col.spheres.isEmpty && col.shadowMesh == nil, "only authored collision")
        check(col.boxes[0].minimum == SIMD3(-3,-0.15,0) && col.boxes[0].maximum == SIMD3(3,0.15,2), "box matches sign")
        let plan = try NativeRenderWareModel.prepare(dff: dff,txd: txd)
        check(plan.isComplete && plan.draws.count == 1 && plan.instances.count == 1, "complete actual static render plan")
        check(plan.geometries[0].indices.count == 6 && plan.geometries[0].parts[0].material == 0, "GPU draw material")
        var gpu = "unavailable"
        if let device = MTLCreateSystemDefaultDevice() {
            let uploaded = try NativeRenderWareModel.Uploaded(plan: plan,device: device)
            check(uploaded.geometries.count == 1 && uploaded.textures.count == 1 && uploaded.textures[0].width == 4, "actual GPU upload")
            gpu = device.name
        }
        let result: [String:Any] = ["status":"PASS","checks":checks,"gpu":gpu,"renderedAppTest":false]
        print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),as:UTF8.self))
    }
}
