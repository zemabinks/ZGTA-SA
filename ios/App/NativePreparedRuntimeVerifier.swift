// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CoreFoundation
import ImageIO
import CoreGraphics
import Metal
import simd

/// Activation checks for this prepared profile, not an original-game parity certificate.
/// Store has verified every blob's size/SHA before supplying `file`. We check the
/// declared world graph, decode the bootstrap exterior, and sequentially decode
/// every indexed native actor family. Raw archives, obsolete ANM1 caches and every
/// streamed world cell are not loaded into memory or uploaded to a GPU here.
enum NativePreparedRuntimeVerifier {
    static let identity = "zgta-prepared-v1-runtime-v1"
    struct Diagnostics {
        /// Deterministic malformed-UV handling, never original UV recovery.
        let repairedUVComponentsByResource: [String: Int]
    }
    enum Failure: Error, LocalizedError {
        case invalid(String, String)
        var errorDescription: String? {
            if case let .invalid(path, reason) = self { return "Prepared runtime \(path): \(reason)" }
            return nil
        }
    }
    static func validate(_ manifest: NativeResourceManifest,
                         file: @escaping (String) throws -> URL) throws {
        _ = try inspect(manifest, file: file)
    }
    static func inspect(_ manifest: NativeResourceManifest,
                        file: @escaping (String) throws -> URL) throws -> Diagnostics {
        try manifest.validate()
        let check = Check(manifest: manifest, file: file)
        try check.run()
        return Diagnostics(repairedUVComponentsByResource: check.repairedUVs)
    }

    private final class Check {
        let resources: [String: NativeResourceManifest.Resource]
        let file: (String) throws -> URL
        var readBytes: Int64 = 0
        var repairedUVs = [String: Int]()
        init(manifest: NativeResourceManifest, file: @escaping (String) throws -> URL) {
            resources = Dictionary(uniqueKeysWithValues: manifest.resources.map { ($0.path, $0) })
            self.file = file
        }
        func require(_ path: String) throws -> NativeResourceManifest.Resource {
            guard let value = resources[path], value.required else { throw Failure.invalid(path, "missing required graph resource") }
            return value
        }
        func bytes(_ path: String, limit: Int64 = 128 * 1_024 * 1_024) throws -> Data {
            let resource = try require(path)
            guard resource.bytes <= limit, readBytes <= 2_147_483_648 - resource.bytes else {
                throw Failure.invalid(path, "runtime verification budget exceeded")
            }
            readBytes += resource.bytes
            let data = try Data(contentsOf: file(path), options: .mappedIfSafe)
            guard data.count == resource.bytes else { throw Failure.invalid(path, "verified resource size changed") }
            return data
        }
        func object(_ path: String) throws -> [String: Any] {
            let data = try bytes(path, limit: 32 * 1_024 * 1_024)
            guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw Failure.invalid(path, "expected metadata object")
            }
            try finiteJSON(result, path: path, depth: 0)
            return result
        }
        func finiteJSON(_ value: Any, path: String, depth: Int) throws {
            guard depth < 32 else { throw Failure.invalid(path, "metadata nesting exceeds bound") }
            if let number = value as? NSNumber, !number.doubleValue.isFinite { throw Failure.invalid(path, "nonfinite metadata") }
            if let array = value as? [Any] { for item in array { try finiteJSON(item, path: path, depth: depth + 1) } }
            if let object = value as? [String: Any] { for item in object.values { try finiteJSON(item, path: path, depth: depth + 1) } }
        }
        func integer(_ value: Any?) -> Int? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return Int(exactly: number.doubleValue)
        }
        func name(_ value: String) -> Bool {
            (1...40).contains(value.utf8.count) && value.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
        }
        func u32(_ data: Data, _ at: Int) -> Int {
            Int(data[at]) | Int(data[at + 1]) << 8 | Int(data[at + 2]) << 16 | Int(data[at + 3]) << 24
        }
        func f32(_ data: Data, _ at: Int) -> Float { Float(bitPattern: UInt32(u32(data, at))) }
        func matrix(_ data: Data, _ at: Int) -> simd_float4x4 {
            func column(_ offset: Int) -> SIMD4<Float> { SIMD4(f32(data, offset), f32(data, offset + 4), f32(data, offset + 8), f32(data, offset + 12)) }
            return simd_float4x4(columns: (column(at), column(at + 16), column(at + 32), column(at + 48)))
        }
        func finite(_ matrix: simd_float4x4) -> Bool { (0..<4).allSatisfy { matrix[$0].x.isFinite && matrix[$0].y.isFinite && matrix[$0].z.isFinite && matrix[$0].w.isFinite } }
        func rigJoints(_ rig: NativeVehicleRig, path: String) throws {
            let d = rig.document, j = d.joints
            func node(_ value: Int) -> Bool { d.nodes.indices.contains(value) }
            func values(_ raw: [Double], _ count: Int) -> Bool { raw.count == count && raw.allSatisfy(\.isFinite) }
            guard j.damage.allSatisfy({ node($0.node) && (0..<64).contains($0.part) && values($0.rest, 4) && values($0.hinge, 3) }),
                  j.wheels.allSatisfy({ node($0.node) && values($0.home, 3) && values($0.rest, 4) && values($0.lean, 4) }),
                  j.rotors.allSatisfy({ node($0.node) && values($0.rest, 4) }),
                  j.gear.allSatisfy({ node($0.node) && values($0.axis, 3) && $0.angle.isFinite && values($0.over, 16) && values($0.at, 3) && values($0.undo, 16) }),
                  j.nozzles.allSatisfy({ node($0.node) }) else { throw Failure.invalid(path, "invalid vehicle joint references") }
            if let bike = j.bike {
                var referenced: [Int] = [bike.model, bike.front, bike.rear]
                if let crank = bike.crank { referenced.append(crank) }
                referenced.append(contentsOf: bike.frontWheels)
                referenced.append(contentsOf: bike.frontMudguards)
                referenced.append(contentsOf: bike.rearWheels)
                referenced.append(contentsOf: bike.pedals)
                guard referenced.allSatisfy(node), bike.parameters.values.allSatisfy(\.isFinite), bike.restDrop.isFinite,
                      bike.rearForkLength.isFinite, bike.rearForkLength > 0, bike.minimumZ.isFinite,
                      bike.hubs.values.allSatisfy({ values($0.at, 3) && $0.radius.isFinite && $0.radius > 0 }) else { throw Failure.invalid(path, "invalid bike joints") }
            }
        }

        func mesh(_ data: Data, path: String) throws -> WorldBinary {
            let value = try WorldBinary(data: data)
            let count = value.vertices.count
            let exact = 16 + count * 28 + value.indices.count * 4 + (count + count % 2) * 2 + value.layers * 2
            // Browser world files align the final UInt16 sharp table to four
            // bytes; our own model exporter also emits the unpadded form.
            let validEnd = data.count == exact || (data.count == (exact + 3) / 4 * 4 && data[exact...].allSatisfy { $0 == 0 })
            guard validEnd, value.vertices.allSatisfy({ vertex in
                let p = vertex.position, uv = vertex.uvLayer
                return p.x.isFinite && p.y.isFinite && p.z.isFinite && abs(p.x) < 1_000_000 && abs(p.y) < 1_000_000 && abs(p.z) < 1_000_000 && uv.x.isFinite && uv.y.isFinite
            }) else { throw Failure.invalid(path, "invalid geometry length or coordinates") }
            if value.repairedUVComponents > 0 { repairedUVs[path] = value.repairedUVComponents }
            return value
        }
        func image(_ data: Data, path: String, layers: Int, cell: Int, columns: Int) throws {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
                  CGImageSourceGetStatus(source) == .statusComplete,
                  let type = CGImageSourceGetType(source), type as String == "public.png",
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = integer(properties[kCGImagePropertyPixelWidth]), let height = integer(properties[kCGImagePropertyPixelHeight]),
                  width == cell * columns, height >= ((layers + columns - 1) / columns) * cell,
                  height <= 16_384, width * height <= 64 * 1_024 * 1_024,
                  let decoded = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
                  decoded.width == width, decoded.height == height,
                  let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw Failure.invalid(path, "atlas cannot decode or does not cover geometry layers")
            }
            context.draw(decoded, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        func graphWorld(_ index: [String: Any]) throws {
            let path = "game/world/index.json"
            guard integer(index["cell"]) == 64, integer(index["columns"]) == 32,
                  let tiles = index["tiles"] as? [[String: Any]], (1...64).contains(tiles.count),
                  let detail = index["detail"] as? [String: Any], integer(detail["cell"]) == 128,
                  integer(detail["columns"]) == 16, let cells = detail["cells"] as? [[String: Any]],
                  let inside = index["inside"] as? [String: Any], let interiors = inside["cells"] as? [[String: Any]],
                  (1...256).contains(cells.count), interiors.count <= 256,
                  let water = index["water"] as? [[Double]], water.count <= 20_000,
                  water.allSatisfy({ [9, 12].contains($0.count) && $0.allSatisfy(\.isFinite) }) else { throw Failure.invalid(path, "invalid world metadata") }
            var seen = Set<String>()
            for (rows, prefix) in [(tiles, "t"), (cells, "c"), (interiors, "i")] {
                for row in rows {
                    let key: String
                    if prefix == "t", let tile = row["name"] as? String,
                       tile.first == "t", let id = Int(tile.dropFirst()), (0..<64).contains(id), tile == "t\(id)" { key = tile }
                    else if prefix != "t", let id = integer(row["cell"]), (0..<256).contains(id) { key = prefix + String(id) }
                    else { throw Failure.invalid(path, "invalid world cell identity") }
                    guard seen.insert(key).inserted, let layers = integer(row["layers"]), (1...4096).contains(layers),
                          let triangles = integer(row["triangles"]), (1..<1_000_000).contains(triangles) else { throw Failure.invalid(path, "invalid world cell shape") }
                    if prefix == "t" {
                        guard let groups = row["groups"] as? [[Int]], groups.count <= 1024,
                              groups.allSatisfy({ $0.count == 3 && (-1..<256).contains($0[0]) && $0[1] >= 0 && $0[2] >= 0 && $0[1] <= triangles * 3 && $0[2] <= triangles * 3 - $0[1] && $0[1] % 3 == 0 && $0[2] % 3 == 0 }) else {
                            throw Failure.invalid(path, "invalid far-world draw ranges")
                        }
                    } else {
                        guard let blend = integer(row["blend"]), (0...(triangles * 3)).contains(blend), blend % 3 == 0,
                              let sharp = integer(row["sharp"]), (0...layers).contains(sharp) else { throw Failure.invalid(path, "invalid detailed-world draw ranges") }
                    }
                    for suffix in [".bin", ".png"] { _ = try require("game/world/" + key + suffix) }
                    if prefix != "t" { _ = try require("game/world/" + key + ".col.bin") }
                    if key == "t2" || key == "c59" {
                        let base = "game/world/" + key
                        let world = try mesh(bytes(base + ".bin"), path: base + ".bin")
                        guard world.layers == layers, world.indices.count == triangles * 3 else { throw Failure.invalid(base, "world index and geometry disagree") }
                        try image(bytes(base + ".png", limit: 64 * 1_024 * 1_024), path: base, layers: layers,
                                  cell: prefix == "t" ? 64 : 128, columns: prefix == "t" ? 32 : 16)
                        if prefix == "c" { try collision(bytes(base + ".col.bin"), path: base) }
                    }
                }
            }
            guard seen.contains("t2"), seen.contains("c59") else { throw Failure.invalid(path, "missing native bootstrap exterior") }
        }
        func collision(_ data: Data, path: String) throws {
            guard data.count >= 16, u32(data, 0) == 0x324c4353 else { throw Failure.invalid(path, "invalid collision header") }
            let vertices = u32(data, 4), triangles = u32(data, 8), flags = u32(data, 12)
            let end = 16 + vertices * 12 + triangles * 12 + ((triangles + 3) / 4) * 4 + (flags & 1 == 1 ? triangles : 0)
            guard vertices < 1_000_000, triangles < 1_000_000, flags <= 1, data.count >= end else { throw Failure.invalid(path, "invalid collision length") }
            for at in stride(from: 16, to: 16 + vertices * 12, by: 4) {
                let value = f32(data, at)
                guard value.isFinite, abs(value) < 1_000_000 else { throw Failure.invalid(path, "invalid collision coordinate") }
            }
            _ = try WorldCollision(data: data)
        }
        func skin(_ data: Data, mesh: WorldBinary, path: String, device: MTLDevice,
                  library: NativeSkeletalAnimationLibrary) throws {
            guard let actor = NativeSkeletalActor(data: data, vertexCount: mesh.vertices.count, device: device),
                  let pose = actor.pose(clip: "ped/idle_stance", elapsed: 0.17, library: library),
                  !pose.palette.isEmpty, pose.palette.allSatisfy(finite),
                  actor.positions(pose: pose).allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
                throw Failure.invalid(path, "skeleton/animation cannot form a native pose")
            }
            // Reconstruct the exporter bind pose. Equal vertex counts alone do
            // not bind an SKN1 to the matching ordered geometry.
            let frames = u32(data, 8), bones = u32(data, 12)
            var globals = [simd_float4x4](), palette = [simd_float4x4]()
            let basis = matrix(data, 80) * matrix(data, 16)
            var offset = 144
            for _ in 0..<frames {
                let parent = Int(Int32(bitPattern: UInt32(u32(data, offset))))
                let local = matrix(data, offset + 8)
                globals.append(parent < 0 ? local : globals[parent] * local); offset += 72
            }
            for _ in 0..<bones {
                palette.append(basis * globals[u32(data, offset)] * matrix(data, offset + 4)); offset += 68
            }
            for index in mesh.vertices.indices {
                let point = SIMD4(f32(data, offset), f32(data, offset + 4), f32(data, offset + 8), 1)
                var bind = SIMD4<Float>.zero
                for slot in 0..<4 { bind += (palette[Int(data[offset + 12 + slot])] * point) * f32(data, offset + 16 + slot * 4) }
                let expected = mesh.vertices[index].position
                guard bind.x.isFinite, bind.y.isFinite, bind.z.isFinite,
                      simd_length(SIMD3(bind.x - expected.x, bind.y - expected.y, bind.z - expected.z)) < 0.005 else {
                    throw Failure.invalid(path, "skeleton bind vertices do not match the indexed mesh")
                }
                offset += 32
            }
        }
        func run() throws {
            let index = try object("game/native/models/index.json")
            var tables = [String: [String: String]]()
            for kind in ["vehicles", "peds", "weapons"] {
                guard let table = index[kind] as? [String: String], !table.isEmpty, table.count <= 1024,
                      table.allSatisfy({ Int($0.key).map { $0 >= 0 && $0 <= 65535 } == true && name($0.value) }) else {
                    throw Failure.invalid("models/index.json", "invalid model namespace")
                }
                tables[kind] = table
            }
            guard tables["peds"]?["7"] == "male01", tables["vehicles"]?["420"] == "taxi" else {
                throw Failure.invalid("models/index.json", "native default player or taxi identity is missing")
            }
            let skins = try NativeSAMPSkinCatalog(data: bytes("game/native/samp-skins.json", limit: 2_000_000))
            for mapping in skins.mappings.values {
                if let id = mapping.nativeID, tables["peds"]?[String(id)] != mapping.model { throw Failure.invalid("samp-skins.json", "skin namespace disagrees with model index") }
            }
            guard skins.nativeSkin(forLegacy: 7) == 7, skins.model(forLegacy: 7) == "male01" else { throw Failure.invalid("samp-skins.json", "wrong default skin mapping") }
            try graphWorld(object("game/world/index.json"))
            guard let device = MTLCreateSystemDefaultDevice() else { throw Failure.invalid("Metal", "native skeletal runtime unavailable") }
            guard let library = NativeSkeletalAnimationLibrary(data: try bytes("game/native/models/animations.clips.bin")) else {
                throw Failure.invalid("animations.clips.bin", "invalid native animation library")
            }
            // Old packages remain valid without this optional fixed body. Once
            // declared, all twelve exact sources and the actual actor upload
            // must pass; a bare descriptor cannot advertise a playable CJ.
            if resources[NativeCJProfile.descriptorPath] != nil {
                let profile=try NativeCJProfile.decode(bytes(NativeCJProfile.descriptorPath,limit:65_536))
                var body=[String:Data]()
                for item in profile.files {
                    let resource=try require(item.path)
                    guard resource.bytes==Int64(item.bytes),resource.sha256==item.sha256 else{
                        throw Failure.invalid(item.path,"fixed player descriptor disagrees with the prepared manifest")
                    }
                    body[item.role]=try bytes(item.path,limit:Int64(item.bytes))
                }
                let candidate=try profile.prepare(body),plan=try NativeRenderWarePedModel.prepareCJ(candidate)
                let uploaded=try NativeRenderWarePedModel.Uploaded(plan:plan,device:device)
                guard uploaded.actor.pose(clip:"ped/idle_stance",elapsed:0,library:library) != nil else{
                    throw Failure.invalid(NativeCJProfile.descriptorPath,"fixed player cannot sample the installed animation library")
                }
            }
            for clip in ["ped/idle_stance", "ped/walk_player", "ped/run_player", "ped/car_sit", "ped/car_sitp", "ped/car_getin_lhs", "ped/car_getout_lhs"] {
                guard library.contains(clip), library.duration(of: clip) != nil else { throw Failure.invalid("animations.clips.bin", "missing core clip \(clip)") }
            }
            let gait = try object("game/world/peds.json")
            guard let styles = gait["styles"] as? [String: [String: Any]], !styles.isEmpty, styles.count <= 512,
                  let pedestrians = gait["peds"] as? [[Any]], (1...2048).contains(pedestrians.count),
                  pedestrians.contains(where: { $0.count >= 5 && $0[0] as? String == "male01" }) else {
                throw Failure.invalid("world/peds.json", "missing native player gait metadata")
            }
            let gaitDecoder = try NativeFootAnimationDefinitions(data: JSONSerialization.data(withJSONObject: gait))
            let defaultGait = gaitDecoder.style(model: "male01", library: library)
            guard [defaultGait.walk, defaultGait.run, defaultGait.sprint, defaultGait.idle].allSatisfy(library.contains) else {
                throw Failure.invalid("world/peds.json", "default gait references unavailable animations")
            }
            let riderData = try bytes("game/native/riders.json", limit: 4_000_000)
            let riders = try JSONDecoder().decode(NativeRiderDefinitions.self, from: riderData)
            let physics = try object("game/native/vehicles.physics.json")
            let seating = try object("game/native/seating.json")
            guard let physicalModels = physics["models"] as? [String: [String: Any]], integer(physics["version"]) == 1,
                  let seatModels = seating["models"] as? [String: [String: Any]], integer(seating["version"]) == 1,
                  physicalModels.count <= 1024, riders.models.count <= 1024 else { throw Failure.invalid("vehicle metadata", "invalid model tables") }
            let foot = try object("game/native/foot-animation.json")
            guard integer(foot["version"]) == 1, let profiles = foot["weapons"] as? [[String: Any]], (1...256).contains(profiles.count) else { throw Failure.invalid("foot-animation.json", "invalid weapon profiles") }
            let ids = profiles.compactMap { integer($0["id"]) }
            guard ids.count == profiles.count, Set(ids).count == ids.count else { throw Failure.invalid("foot-animation.json", "duplicate/invalid weapon profile") }
            _ = try NativeFootWeaponAnimation.load(data: JSONSerialization.data(withJSONObject: foot))
            let weapons = try object("game/native/weapons.json")
            guard let definitions = weapons["definitions"] as? [[String: Any]], (1...256).contains(definitions.count), weapons["stats"] is [String: Any] else { throw Failure.invalid("weapons.json", "invalid weapon definitions") }
            var weaponNames = [Int: String]()
            var weaponIDs = Set<Int>()
            for row in definitions {
                guard let id = integer(row["id"]), (0...255).contains(id), weaponIDs.insert(id).inserted else { throw Failure.invalid("weapons.json", "invalid weapon identity") }
                // Damage-cause definitions such as explosions have no inventory
                // slot or model. Indexed holdable weapons do require a slot.
                if let slot = integer(row["slot"]) {
                    guard (0...15).contains(slot) else { throw Failure.invalid("weapons.json", "invalid inventory slot") }
                } else if !(row["slot"] is NSNull) || row["modelName"] is String {
                    throw Failure.invalid("weapons.json", "missing inventory slot")
                }
                if let model = row["modelName"] as? String { weaponNames[id] = model }
            }
            // This exporter report is advisory: owner-added valid SKN1 families
            // need not have been appended to an older report. Actual decoder
            // and bind-vertex association below remain mandatory for every ped.
            let skeletons = resources["game/native/models/skeletons.json"] == nil ? [:] : try object("game/native/models/skeletons.json")
            for kind in ["peds", "vehicles", "weapons"] {
                for (id, model) in tables[kind]!.sorted(by: { $0.key < $1.key }) {
                    try autoreleasepool {
                        let base = "game/native/models/" + model
                        let geometry = try mesh(bytes(base + ".bin"), path: base + ".bin")
                        try image(bytes(base + ".png", limit: 64 * 1_024 * 1_024), path: base, layers: geometry.layers, cell: 128, columns: 8)
                        if kind == "peds" {
                            let path = base + ".skel.bin", resource = try require(path)
                            if let metadata = skeletons[model] as? [String: Any] {
                                guard metadata["sha256"] as? String == resource.sha256,
                                      integer(metadata["vertices"]) == geometry.vertices.count, integer(metadata["bytes"]) == Int(resource.bytes) else { throw Failure.invalid(path, "skeleton family metadata mismatch") }
                            }
                            try skin(bytes(path), mesh: geometry, path: path, device: device, library: library)
                        } else if kind == "vehicles" {
                            guard let physical = physicalModels[id], integer(physical["id"]) == Int(id), physical["model"] as? String == model,
                                  let rider = riders.models[id], rider.model == model, rider.origin.isFinite, rider.seats.count <= 16,
                                  let seatingRow = seatModels[id], seatingRow["clips"] is [String: String],
                                  rider.seats.allSatisfy({ seat in seat.at.count == 3 && seat.at.allSatisfy(\.isFinite) && (seat.shift.map { $0.count == 3 && $0.allSatisfy(\.isFinite) } ?? true) && (seat.via.map { $0.count == 3 && $0.allSatisfy(\.isFinite) } ?? true) && (seat.turn?.isFinite ?? true) }) else { throw Failure.invalid(base, "vehicle/rider/physics identity or seat mismatch") }
                            if !rider.seats.isEmpty { guard let sit = rider.clips["sit"], library.contains(sit) else { throw Failure.invalid(base, "missing real rider animation") } }
                            let rigJSON = try bytes(base + ".rig.json", limit: 32_000_000)
                            guard let raw = try JSONSerialization.jsonObject(with: rigJSON) as? [String: Any], raw["model"] as? String == model,
                                  let rig = NativeVehicleRig(data: rigJSON), rig.document.id == Int(id) else { throw Failure.invalid(base, "vehicle rig identity/decode mismatch") }
                            try rigJoints(rig, path: base)
                            let binary = try bytes(base + ".rig.bin"), atlas = try bytes(base + ".rig.png", limit: 64_000_000)
                            guard rig.validatesAssetFamily(binary: binary, atlas: atlas), let decoded = rig.meshData(binary) else { throw Failure.invalid(base, "vehicle family hashes/encoding mismatch") }
                            let rigMesh = try mesh(decoded, path: base + ".rig.bin")
                            guard rig.document.draws.allSatisfy({ $0.start <= rigMesh.indices.count && $0.count <= rigMesh.indices.count - $0.start && $0.start % 3 == 0 && $0.count % 3 == 0 }) else { throw Failure.invalid(base, "vehicle draw exceeds geometry") }
                            try image(atlas, path: base + ".rig.png", layers: rigMesh.layers, cell: 128, columns: 8)
                            let normalPath = base + ".rig.normals.bin", normalResource = try require(normalPath)
                            let normals = try bytes(normalPath)
                            guard normals.count == rigMesh.vertices.count * 12, rig.document.normalsSHA256.map({ $0 == normalResource.sha256 }) ?? true else { throw Failure.invalid(base, "vehicle normal family mismatch") }
                            for at in stride(from: 0, to: normals.count, by: 4) { guard f32(normals, at).isFinite else { throw Failure.invalid(base, "nonfinite vehicle normal") } }
                        } else if weaponNames[Int(id)!] != model { throw Failure.invalid(base, "weapon identity disagrees with index") }
                    }
                }
            }
        }
    }
}
