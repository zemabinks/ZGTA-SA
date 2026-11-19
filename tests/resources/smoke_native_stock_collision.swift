// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

private enum TestFailure: Error { case check(String) }
private var checks = 0
private func check(_ value: Bool, _ reason: String) throws {
    checks += 1
    if !value { throw TestFailure.check(reason) }
}
private typealias COL = NativeRenderWareCollision
private typealias CW = NativeRenderWareCollisionWorld
private func vector(_ v: SIMD3<Float>) -> [Float] { [v.x,v.y,v.z] }
private func surface(_ s: COL.Surface) -> [String: Any] {
    ["material": Int(s.material), "flags": s.flags.map { Int($0) as Any } ?? NSNull(),
     "brightness": s.brightness.map { Int($0) as Any } ?? NSNull(), "lighting": Int(s.lighting),
     "day": Int(s.dayLight), "night": Int(s.nightLight)]
}
private func mesh(_ m: COL.Mesh) -> [String: Any] {
    ["vertices": m.vertices.map(vector), "faces": m.faces.map {
        ["indices": [$0.a,$0.b,$0.c], "surface": surface($0.surface)] as [String: Any]
    }]
}
private func model(_ m: COL.Model) -> [String: Any] {
    ["version": m.version.rawValue, "name": m.name as Any? ?? NSNull(), "id": m.modelID.map { Int($0) as Any } ?? NSNull(),
     "flags": m.flags.map { Int($0) as Any } ?? NSNull(), "physical": m.hasCollisionVolumes,
     "bounds": ["min": vector(m.bounds.minimum), "max": vector(m.bounds.maximum), "center": vector(m.bounds.center), "radius": m.bounds.radius],
     "spheres": m.spheres.map { ["center": vector($0.center), "radius": $0.radius, "surface": surface($0.surface)] as [String: Any] },
     "boxes": m.boxes.map { ["min": vector($0.minimum), "max": vector($0.maximum), "surface": surface($0.surface)] as [String: Any] },
     "mesh": mesh(m.mesh), "groups": m.faceGroups.map { ["min": vector($0.minimum), "max": vector($0.maximum), "first": $0.firstFace, "last": $0.lastFace] as [String: Any] },
     "shadow": m.shadowMesh.map(mesh) as Any? ?? NSNull()]
}
private func physical(_ m: COL.Model) throws -> [String: Any] {
    let world = SwiftRapierWorld()!, owner = try CW(world: world)
    let turn = simd_quatf(angle: 0.3, axis: simd_normalize(SIMD3<Float>(1,2,3)))
    let pose = CW.Transform(position: SIMD3(20,30,10), rotation: turn)
    let handle = try owner.insert(.init(id: 1, model: m, transform: pose, cameraCollision: false))
    let ids = owner.colliderIDs(for: handle)!
    try check(ids.count == m.spheres.count + m.boxes.count + (m.mesh.faces.isEmpty ? 0 : 1), "only authored physical primitives")
    try check(world.step(), "initial physical step")
    var probes = 0
    let centers = m.spheres.map { $0.center } + m.boxes.map { ($0.minimum + $0.maximum) * 0.5 }
    let surfaces = m.spheres.map { $0.surface } + m.boxes.map { $0.surface }
    for (index, center) in centers.enumerated() {
        let position = pose.position + turn.act(center)
        let probe = world.addSphere(radius: 0.01, position: CW.toRapier(position))!
        let contact = world.contact(probe, ids[index], prediction: 0.01)
        try check(contact != nil && contact!.distance < 0, "actual authored volume contact after full-basis transform")
        try check(owner.metadata(collider: ids[index])?.surface?.material == surfaces[index].material, "actual raw material association")
        try check(world.colliderInfo(ids[index])?.piece == Int(surfaces[index].flags ?? 255), "raw piece flags preserved")
        _ = world.removeCollider(probe); probes += 1
    }
    try check(owner.cameraExcludedColliderIDs == Set(ids), "camera exclusion preserves physical colliders")
    let moved = CW.Transform(position: SIMD3(23,31,11), rotation: simd_quatf(angle: -0.4, axis: SIMD3(0,0,1)))
    try owner.move(handle, to: moved); try check(world.step(), "actual authored kinematic move")
    if let center = centers.first {
        let position = moved.position + moved.rotation.act(center)
        let probe = world.addSphere(radius: 0.01, position: CW.toRapier(position))!
        try check(world.contact(probe, ids[0], prediction: 0.01)?.distance ?? 1 < 0, "moved authored collider, no world baking")
        _ = world.removeCollider(probe)
    }
    try check(owner.remove(handle) && ids.allSatisfy { world.colliderInfo($0) == nil }, "authored cleanup")
    return ["physicalColliders": ids.count, "primitiveContactProbes": probes,
            "mainFaces": m.mesh.faces.count, "shadowFacesExcluded": m.shadowMesh?.faces.count ?? 0]
}
@main struct StockCollisionSmoke {
    static func main() throws {
        let manifest = URL(fileURLWithPath: CommandLine.arguments[1]), output = URL(fileURLWithPath: CommandLine.arguments[2])
        let cases = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as! [[String: Any]]
        var results: [[String: Any]] = []
        for row in cases {
            do {
                var limits = NativeSAMPStockCollisionCatalog.Limits()
                if row["limit"] as? String == "bytes" { limits.metadataBytes = 1 }
                if row["limit"] as? String == "models" { limits.models = 1 }
                if row["limit"] as? String == "records" { limits.records = 1 }
                if row["limit"] as? String == "aliases" { limits.aliases = 1 }
                if row["limit"] as? String == "file" { limits.fileBytes = 72 }
                let catalog = try NativeSAMPStockCollisionCatalog.decode(Data(contentsOf: URL(fileURLWithPath: row["catalog"] as! String)), limits: limits)
                let base = row["baseURL"] as? String
                let url = base.map { URL(string: $0)! } ?? URL(fileURLWithPath: row["assetRoot"] as! String, isDirectory: true)
                let resolution = try catalog.resolve(modelID: Int32(row["id"] as! Int), modelName: row["name"] as! String,
                                                     source: row["source"] as? String, line: row["line"] as? Int,
                                                     stockManifestSHA256: row["stockManifestSHA256"] as? String,
                                                     assetBaseURL: url, allowLocalFiles: row["local"] as? Bool ?? true)
                switch resolution {
                case .missing: results.append(["outcome": "missing"])
                case .noAuthoredCollision: results.append(["outcome": "no-authored-collision"])
                case .ambiguous(_,_,let files): results.append(["outcome": "ambiguous", "count": files.count])
                case .unique(let file):
                    if row["resolveOnly"] as? Bool == true {
                        results.append(["outcome": "unique", "aliases": file.metadata.sources.count]); continue
                    }
                    let path = (row["data"] as? String).map { URL(fileURLWithPath: $0) } ?? file.url
                    var data = try Data(contentsOf: path)
                    if let prefix = row["prefix"] as? Int { data = data.prefix(prefix) }
                    let decoded = try catalog.prepare(data, for: file)
                    var result: [String: Any] = ["outcome": "prepared", "model": model(decoded)]
                    if row["physics"] as? Bool == true { result["physics"] = try physical(decoded) }
                    results.append(result)
                }
            } catch {
                results.append(["outcome": "rejected", "error": String(describing: error)])
            }
        }
        let result: [String: Any] = ["cases": results, "physicalChecks": checks]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]).write(to: output)
    }
}
