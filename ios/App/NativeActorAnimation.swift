import Foundation
import Metal
import simd

/// Vertex frames baked from the archived DFF skin and ANP3 clips on the Mac.
/// The original game files and these generated frames stay outside the app.
struct NativeActorAnimation {
    private let frames: [String: [MTLBuffer]]
    private let framesPerSecond: Int

    init?(data: Data, vertexCount: Int, device: MTLDevice) {
        let bytes = [UInt8](data)
        func u32(_ offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 |
                Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        guard bytes.count >= 16, bytes[0...3].elementsEqual([65, 78, 77, 49]),
              u32(4) == vertexCount, vertexCount > 0, vertexCount < 100_000 else { return nil }
        let clipCount = u32(8)
        let fps = u32(12)
        guard clipCount > 0, clipCount <= 128, fps > 0, fps <= 120 else { return nil }
        var offset = 16
        var decoded: [String: [MTLBuffer]] = [:]
        for _ in 0..<clipCount {
            guard offset + 20 <= bytes.count else { return nil }
            let nameBytes = bytes[offset..<(offset + 16)].prefix { $0 != 0 }
            let name = String(bytes: nameBytes, encoding: .ascii) ?? ""
            let count = u32(offset + 16)
            offset += 20
            guard !name.isEmpty, count > 0, count <= 1000,
                  vertexCount <= Int.max / 12,
                  count <= (bytes.count - offset) / (vertexCount * 12) else { return nil }
            let frameLength = vertexCount * 12
            var buffers: [MTLBuffer] = []
            buffers.reserveCapacity(count)
            for _ in 0..<count {
                let buffer = data.withUnsafeBytes { raw -> MTLBuffer? in
                    guard let base = raw.baseAddress else { return nil }
                    return device.makeBuffer(bytes: base.advanced(by: offset),
                                             length: frameLength, options: .storageModeShared)
                }
                guard let buffer else { return nil }
                buffers.append(buffer)
                offset += frameLength
            }
            guard decoded[name] == nil else { return nil }
            decoded[name] = buffers
        }
        guard offset == bytes.count else { return nil }
        frames = decoded
        framesPerSecond = fps
    }

    func contains(_ clip: String) -> Bool { frames[clip] != nil }

    func duration(of clip: String) -> Double? {
        guard let count = frames[clip]?.count else { return nil }
        return Double(max(0, count - 1)) / Double(framesPerSecond)
    }

    func sample(clip: String, elapsed: Double, looping: Bool? = nil) -> (MTLBuffer, MTLBuffer, Float)? {
        guard let options = frames[clip], !options.isEmpty else { return nil }
        guard elapsed.isFinite else { return nil }
        let phase = min(1_000_000_000, max(0, elapsed * Double(framesPerSecond)))
        let step = Int(phase)
        let last = options.count - 1
        let repeats = looping ?? NativePedestrianMotion.loops(clip)
        let index = repeats ? step % options.count : min(last, step)
        let next = repeats ? (index + 1) % options.count : min(last, index + 1)
        return (options[index], options[next], Float(phase - floor(phase)))
    }
}

/// Per-frame right-hand transforms from the archived pedestrian skeleton.
/// Weapon vertices remain in their original RenderWare local coordinates.
struct NativeActorAttachment {
    private let frames: [String: [simd_float4x4]]
    private let framesPerSecond: Int

    init?(data: Data) {
        let bytes = [UInt8](data)
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
                UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        guard bytes.count >= 16, bytes[0...3].elementsEqual([72, 78, 68, 49]) else { return nil }
        let count = Int(u32(4)), fps = Int(u32(8))
        guard count > 0, count <= 128, fps > 0, fps <= 120 else { return nil }
        var offset = 16
        var decoded: [String: [simd_float4x4]] = [:]
        for _ in 0..<count {
            guard offset + 20 <= bytes.count else { return nil }
            let name = String(bytes: bytes[offset..<(offset + 16)].prefix { $0 != 0 },
                              encoding: .ascii) ?? ""
            let frameCount = Int(u32(offset + 16))
            offset += 20
            guard !name.isEmpty, frameCount > 0, frameCount <= 1000,
                  frameCount <= (bytes.count - offset) / 64 else { return nil }
            var matrices: [simd_float4x4] = []
            matrices.reserveCapacity(frameCount)
            for _ in 0..<frameCount {
                let values = (0..<16).map { Float(bitPattern: u32(offset + $0 * 4)) }
                guard values.allSatisfy(\.isFinite) else { return nil }
                matrices.append(simd_float4x4(columns: (
                    SIMD4(values[0], values[1], values[2], values[3]),
                    SIMD4(values[4], values[5], values[6], values[7]),
                    SIMD4(values[8], values[9], values[10], values[11]),
                    SIMD4(values[12], values[13], values[14], values[15]))))
                offset += 64
            }
            guard decoded[name] == nil else { return nil }
            decoded[name] = matrices
        }
        guard offset == bytes.count else { return nil }
        frames = decoded
        framesPerSecond = fps
    }

    func frame(clip: String, elapsed: Double) -> simd_float4x4? {
        guard let options = frames[clip], !options.isEmpty else { return nil }
        guard elapsed.isFinite else { return nil }
        let phase = min(1_000_000_000, max(0, elapsed * Double(framesPerSecond)))
        let step = Int(phase)
        let repeats = NativePedestrianMotion.loops(clip)
        let index = repeats ? step % options.count : min(options.count - 1, step)
        let next = repeats ? (index + 1) % options.count : min(options.count - 1, index + 1)
        let left = options[index], right = options[next]
        let alpha = Float(phase - floor(phase))
        let rotation = simd_slerp(simd_quatf(left), simd_quatf(right), alpha)
        var blended = simd_float4x4(rotation)
        blended.columns.3 = left.columns.3 + (right.columns.3 - left.columns.3) * alpha
        return blended
    }
}

/// Animation selection independent of rendering and input. The clips named
/// here are backed by locally baked ANP3 data. Water detection and collision
/// remain the movement controller's responsibility.
struct NativePedestrianMotion {
    private(set) var clip = "idle_stance"
    private(set) var elapsed: Double = 0
    var crouching = false
    var swimming = false
    var underwater = false
    var health = 100
    private var wasAirborne = false
    private var action: String?
    private var actionRemaining: Double = 0

    private static let loopingClips: Set<String> =
        ["idle_stance", "walk_player", "run_player", "sprint_civi", "gun_stand",
         "weapon_crouch", "guncrouchfwd", "guncrouchbwd", "duck_idle", "jump_glide",
         "fall_fall", "car_sit", "swim_tread", "swim_breast", "swim_crawl",
         "swim_under", "swim_glide", "bat_idle", "idle_csaw"]

    static func loops(_ clip: String) -> Bool { loopingClips.contains(clip) }

    mutating func perform(_ name: String, duration: Double) {
        guard health > 0, duration.isFinite, duration > 0 else { return }
        action = name
        actionRemaining = duration
        clip = name
        elapsed = 0
    }

    mutating func clearAction() { action = nil; actionRemaining = 0 }

    mutating func update(delta: Double, moving: Bool, running: Bool,
                         airborne: Bool, verticalSpeed: Float, weapon: Int,
                         driving: Bool = false, backwards: Bool = false) {
        let step = min(0.1, max(0, delta))
        elapsed += step
        actionRemaining = max(0, actionRemaining - step)
        if actionRemaining == 0 { action = nil }
        defer { wasAirborne = airborne }
        if health <= 0 {
            action = nil
            select("death_front")
        } else if let action {
            select(action)
        } else if driving {
            select("car_sit")
        } else if swimming {
            select(underwater ? (moving ? "swim_under" : "swim_glide") :
                moving ? (running ? "swim_crawl" : "swim_breast") : "swim_tread")
        } else if airborne {
            select(verticalSpeed > 1 ? "jump_launch" : "jump_glide")
        } else if wasAirborne {
            perform("jump_land", duration: 0.233)
        } else if crouching {
            select(moving ? (backwards ? "guncrouchbwd" : "guncrouchfwd") : "weapon_crouch")
        } else {
            select(moving ? (running ? "run_player" : "walk_player") :
                weapon > 0 ? "gun_stand" : "idle_stance")
        }
    }

    private mutating func select(_ name: String) {
        if name != clip { clip = name; elapsed = 0 }
    }

    static func clip(forWire animation: String, weapon: Int, health: Int = 100) -> String {
        guard health > 0 else { return "death_front" }
        let parts = animation.lowercased().split(separator: "/")
        let name = parts.count > 1 ? String(parts[1]) : String(parts.first ?? "")
        let aliases = ["walk": "walk_player", "run": "run_player", "idle": "idle_stance",
                       "ko_shot_front": "death_front", "duck_cower": "duck_idle",
                       "swim_dive_under": "swim_dive",
                       "colt45_crouchfire": "pistol_cfire", "colt45_crouchreload": "pistol_creload",
                       "silencecrouchfire": "silence_cfire", "crouchreload": "silence_creload",
                       "python_crouchfire": "python_cfire", "python_crouchreload": "python_creload",
                       "shotgun_crouchfire": "shotgun_cfire", "buddy_crouchfire": "buddy_cfire",
                       "buddy_crouchreload": "buddy_creload", "uzi_crouchfire": "uzi_cfire",
                       "uzi_crouchreload": "uzi_creload", "rifle_crouchfire": "rifle_cfire",
                       "rifle_crouchload": "rifle_cload"]
        if let alias = aliases[name] { return alias }
        if loops(name) || ["jump_launch", "jump_land", "fall_land", "death_front", "hit_front",
                           "fighta_1", "fighta_2", "fighta_3", "car_getin_lhs", "car_getout_lhs",
                           "climb_pull", "climb_stand", "swim_dive", "colt45_fire", "colt45_reload",
                           "sawnoff_reload", "python_fire", "python_reload", "shotgun_fire",
                           "silence_fire", "silence_reload",
                           "buddy_fire", "buddy_reload", "uzi_fire", "uzi_reload", "rifle_fire",
                           "rifle_load", "bat_1", "csaw_1"].contains(name) { return name }
        return weapon > 0 ? "gun_stand" : "idle_stance"
    }

    static func wireAnimation(for clip: String) -> String {
        if clip.contains("/") {
            return clip.split(separator: "/").count >= 4 ? clip : clip + "/l/1"
        }
        let special = ["death_front": "ped/ko_shot_front", "duck_idle": "ped/duck_cower",
                       "swim_dive": "swim/swim_dive_under",
                       "pistol_cfire": "colt45/colt45_crouchfire",
                       "pistol_creload": "colt45/colt45_crouchreload",
                       "sawnoff_reload": "colt45/sawnoff_reload",
                       "silence_fire": "silenced/silence_fire", "silence_reload": "silenced/silence_reload",
                       "silence_cfire": "silenced/silencecrouchfire",
                       "silence_creload": "silenced/crouchreload",
                       "rifle_cload": "rifle/rifle_crouchload"]
        if let source = special[clip] { return source + "/l/1" }
        let group: String
        if clip.hasPrefix("swim_") { group = "swim" }
        else if clip.hasPrefix("bat_") { group = "baseball" }
        else if clip.hasPrefix("csaw_") || clip == "idle_csaw" { group = "chainsaw" }
        else if let match = ["colt45", "python", "shotgun", "buddy", "uzi", "rifle"]
            .first(where: { clip.hasPrefix($0 + "_") }) { group = match }
        else { group = "ped" }
        let original = clip.replacingOccurrences(of: "_cfire", with: "_crouchfire")
            .replacingOccurrences(of: "_creload", with: "_crouchreload")
        return group + "/" + original + "/l/1"
    }
}

struct NativeWeaponAnimation {
    let fire: String
    let reload: String
    let crouchFire: String
    let crouchReload: String

    static func forWeapon(_ id: Int) -> NativeWeaponAnimation {
        let group: String
        switch id {
        case 23: group = "silence"
        case 24: group = "python"
        case 25: group = "shotgun"
        case 27: group = "buddy"
        case 28, 32: group = "uzi"
        case 29...31, 33, 34: group = "rifle"
        default: group = "colt45"
        }
        let reload = group == "rifle" ? "rifle_load" : group == "shotgun" ? "gun_stand" :
            id == 26 ? "sawnoff_reload" : group + "_reload"
        let crouchReload = group == "rifle" ? "rifle_cload" : group == "colt45" ? "pistol_creload" :
            group == "shotgun" ? "weapon_crouch" : group + "_creload"
        return NativeWeaponAnimation(fire: group + "_fire", reload: reload,
                                     crouchFire: group == "colt45" ? "pistol_cfire" : group + "_cfire",
                                     crouchReload: crouchReload)
    }
}
