// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main struct RenderWareSkeletonSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let cases = try JSONSerialization.jsonObject(with: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]
        var results: [[String: Any]] = []
        for (index, item) in cases.enumerated() {
            do {
                let model = try NativeRenderWareDFF.decode(Data(contentsOf: URL(fileURLWithPath: item["path"] as! String)))
                var limits = NativeRenderWareSkeleton.Limits()
                switch item["limit"] as? String {
                case "vertices": limits.vertices = 3
                case "frames": limits.frames = 2
                case "bones": limits.bones = 1
                case "indices": limits.indices = 3
                default: break
                }
                let plan = try NativeRenderWareSkeleton.prepare(model, limits: limits)
                let file = root.appendingPathComponent("result-\(index).skn")
                try plan.encodedSKN1().write(to: file)
                let palette = plan.restPalette()
                let points = plan.vertices.map { vertex -> [Double] in
                    var point = SIMD4<Float>.zero
                    for influence in 0..<4 {
                        point += palette[Int(vertex.bones[influence])] * SIMD4(vertex.position, 1) * vertex.weights[influence]
                    }
                    return [Double(point.x), Double(point.y), Double(point.z)]
                }
                results.append(["accepted": true, "skn": file.path, "floor": Double(plan.floor),
                    "vertexOrder": plan.vertices.map { [$0.sourceIndex, $0.materialIndex] },
                    "indices": plan.indices.map(Int.init), "restPoints": points,
                    "frameSourceOrder": plan.frames.map(\.sourceIndex)])
            } catch { results.append(["accepted": false, "error": String(describing: error)]) }
        }
        try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]).write(to:
            root.appendingPathComponent("results.json"))
    }
}
