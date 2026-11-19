// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main struct CollisionSmoke {
    static func vector(_ value: SIMD3<Float>) -> [Double] { [Double(value.x),Double(value.y),Double(value.z)] }
    static func optional<T>(_ value: T?) -> Any { if let value { return value }; return NSNull() }
    static func surface(_ s: NativeRenderWareCollision.Surface) -> [String: Any] {
        ["material": Int(s.material),"flags": optional(s.flags.map(Int.init)),"brightness": optional(s.brightness.map(Int.init)),
         "lighting": Int(s.lighting),"day": Int(s.dayLight),"night": Int(s.nightLight)]
    }
    static func mesh(_ mesh: NativeRenderWareCollision.Mesh) -> [String: Any] {
        ["vertices": mesh.vertices.map(vector),"faces": mesh.faces.map {
            ["indices": [Int($0.a),Int($0.b),Int($0.c)],"surface": surface($0.surface)] as [String: Any] }]
    }
    static func describe(_ model: NativeRenderWareCollision.Model) -> [String: Any] {
        var value: [String: Any] = ["version": model.version.rawValue,"name": optional(model.name),"id": optional(model.modelID.map(Int.init)),
            "flags": optional(model.flags.map(Int.init)),"physical": model.hasCollisionVolumes,
            "bounds": ["min": vector(model.bounds.minimum),"max": vector(model.bounds.maximum),
                "center": vector(model.bounds.center),"radius": Double(model.bounds.radius)],
            "spheres": model.spheres.map { ["center": vector($0.center),"radius": Double($0.radius),"surface": surface($0.surface)] as [String: Any] },
            "boxes": model.boxes.map { ["min": vector($0.minimum),"max": vector($0.maximum),"surface": surface($0.surface)] as [String: Any] },
            "mesh": mesh(model.mesh),"groups": model.faceGroups.map {
                ["min": vector($0.minimum),"max": vector($0.maximum),"first": $0.firstFace,"last": $0.lastFace] as [String: Any] }]
        value["shadow"] = model.shadowMesh.map(mesh) ?? NSNull()
        return value
    }
    static func main() throws {
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]
        var results: [[String: Any]] = []
        for item in manifest {
            do {
                var data = try Data(contentsOf: URL(fileURLWithPath: item["path"] as! String))
                if let prefix = item["prefix"] as? Int { data = Data(data.prefix(prefix)) }
                var limits = NativeRenderWareCollision.Limits()
                switch item["limit"] as? String {
                case "bytes": limits.fileBytes = 8
                case "models": limits.models = 1
                case "spheres": limits.spheres = 0
                case "boxes": limits.boxes = 0
                case "faces": limits.faces = 0
                case "vertices": limits.vertices = 2
                case "groups": limits.faceGroups = 0
                case "totalPrimitives": limits.totalPrimitives = 1
                case "totalVertices": limits.totalVertices = 2
                case "chunks": limits.chunks = 1
                case "dffBytes": limits.dffBytes = 8
                default: break
                }
                switch item["mode"] as? String {
                case "embedded":
                    let values = try NativeRenderWareCollision.embedded(inDFF: data,limits: limits)
                    let entries: [[String: Any]] = values.map { ["offset": $0.pluginOffset,"bytes": $0.payloadBytes,
                        "legacy": $0.headerlessLegacy,"models": $0.models.map(describe)] }
                    results.append(["accepted": true,"embedded": entries])
                case "legacy":
                    let value = try NativeRenderWareCollision.decodeHeaderlessCOL1(data,limits: limits)
                    results.append(["accepted": true,"models": [describe(value)]])
                default:
                    let values = try NativeRenderWareCollision.decode(data,limits: limits)
                    results.append(["accepted": true,"models": values.map(describe)])
                }
            } catch { results.append(["accepted": false,"error": String(describing: error)]) }
        }
        try JSONSerialization.data(withJSONObject: results,options: [.sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
}
