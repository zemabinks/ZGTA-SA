import Foundation
import simd

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("i148.col.generated.json"))) as! [String:Any]
precondition(manifest["reconstructed"] as! Bool && !(manifest["publisherCollisionAssetAvailable"] as! Bool))
let mesh = try SwiftRapierWorld.decodeSCL2(Data(contentsOf: root.appendingPathComponent("i148.col.bin")))
let world = SwiftRapierWorld(gravity: .zero)!
for part in manifest["parts"] as! [[String:Any]] {
    let start = part["indexStart"] as! Int, count = part["indexCount"] as! Int
    var remap: [UInt32:UInt32] = [:], vertices: [SIMD3<Float>] = [], indices: [UInt32] = []
    for value in mesh.indices[start..<start+count] {
        if remap[value] == nil { remap[value] = UInt32(vertices.count); vertices.append(mesh.vertices[Int(value)]) }
        indices.append(remap[value]!)
    }
    let n = indices.count/3
    let id = world.addTriangleMesh(.init(vertices: vertices,indices: indices,
        surfaces: [Int32](repeating: 2,count: n),materials: [Int32](repeating: -1,count: n)))!
    world.setColliderGroups(id,collision: 131071,solver: 0xffffffff)
    world.setColliderQueryMetadata(id,surface: 2,material: -1)
}
var maximumDistance: Float = 0,maximumNormal: Float = 0,hits = 0
for row in manifest["rays"] as! [[String:Any]] {
    func vector(_ raw: Any) -> SIMD3<Float> { let v = raw as! [Double]; return SIMD3(Float(v[0]),Float(v[1]),Float(v[2])) }
    let actual = world.raycast(origin: vector(row["origin"]!),direction: vector(row["direction"]!),distance: Float(row["distance"] as! Double))
    if let expected = row["hit"] as? [String:Any] {
        precondition(actual != nil,"Reconstructed interior lost an original floor")
        maximumDistance = max(maximumDistance,abs(actual!.distance-Float(expected["distance"] as! Double)))
        maximumNormal = max(maximumNormal,simd_distance(actual!.normal,vector(expected["normal"]!)))
        precondition(actual!.coarseSurface == 2 && actual!.coarseMaterial == -1)
        hits += 1
    } else { precondition(actual == nil,"Reconstructed interior introduced a new floor") }
}
precondition(maximumDistance < 0.0002 && maximumNormal < 0.00001)
print("PASS: reconstructed i148 has \(mesh.indices.count/3) original triangles / \((manifest["parts"] as! [Any]).count) original parts; \(hits) floor hits across 81 archived-engine rays, max distance \(maximumDistance), normal \(maximumNormal)")
