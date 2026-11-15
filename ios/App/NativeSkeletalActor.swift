import Foundation
import Metal
import simd

private struct SkeletonReader {
    let bytes: [UInt8]
    var offset = 0
    enum Invalid: Error { case data }
    mutating func u32() throws -> UInt32 {
        guard offset + 4 <= bytes.count else { throw Invalid.data }
        defer { offset += 4 }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 |
            UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
    mutating func integer() throws -> Int { Int(Int32(bitPattern: try u32())) }
    mutating func float() throws -> Float {
        let value = Float(bitPattern: try u32())
        guard value.isFinite else { throw Invalid.data }
        return value
    }
    mutating func vector() throws -> SIMD3<Float> { try SIMD3(float(), float(), float()) }
    mutating func matrix() throws -> simd_float4x4 {
        var columns: [SIMD4<Float>] = []
        for _ in 0..<4 { columns.append(try SIMD4(float(), float(), float(), float())) }
        return simd_float4x4(columns: (columns[0], columns[1], columns[2], columns[3]))
    }
    mutating func string() throws -> String {
        guard offset + 2 <= bytes.count else { throw Invalid.data }
        let count = Int(bytes[offset]) | Int(bytes[offset + 1]) << 8
        offset += 2
        guard offset + count <= bytes.count,
              let value = String(bytes: bytes[offset..<(offset + count)], encoding: .utf8) else { throw Invalid.data }
        offset += count
        return value
    }
}

/// Shared raw ANP3 tracks, exported once for all locally hosted pedestrians.
/// This retains every clip in each archived block, rather than vertex poses.
final class NativeSkeletalAnimationLibrary {
    fileprivate struct Key {
        let time: Float
        let turn: simd_quatf
        let originalTurn: SIMD4<Float>
        let place: SIMD3<Float>?
    }
    fileprivate struct Clip {
        let duration: Float
        let tracks: [Int: [Key]]
    }
    private let clips: [String: Clip]
    private let aliases: [String: (source: String, base: String)]
    private var joined: [String: Clip] = [:]
    var clipCount: Int { clips.count }
    var aliasCount: Int { aliases.count }
    var clipNames: [String] { clips.keys.sorted() }

    init?(data: Data) {
        var reader = SkeletonReader(bytes: [UInt8](data))
        do {
            guard try reader.u32() == 0x31504c43 else { return nil } // CLP1
            let count = Int(try reader.u32()), aliasCount = Int(try reader.u32())
            guard try reader.u32() == 1, count > 0, count <= 20_000,
                  aliasCount <= 20_000 else { return nil }
            var decoded: [String: Clip] = [:]
            for _ in 0..<count {
                let name = try reader.string(), duration = try reader.float()
                let trackCount = Int(try reader.u32())
                guard !name.isEmpty, decoded[name] == nil, duration >= 0,
                      duration < 3600, trackCount <= 512 else { return nil }
                var tracks: [Int: [Key]] = [:]
                for _ in 0..<trackCount {
                    let bone = try reader.integer(), keyCount = Int(try reader.u32())
                    let positioned = try reader.u32()
                    guard bone >= 0, bone <= 10_000, keyCount > 0, keyCount <= 100_000,
                          positioned <= 1, tracks[bone] == nil else { return nil }
                    var keys: [Key] = []
                    keys.reserveCapacity(keyCount)
                    for _ in 0..<keyCount {
                        let time = try reader.float()
                        let vector = try SIMD4<Float>(reader.float(), reader.float(), reader.float(), reader.float())
                        guard simd_length_squared(vector) > 0.000001,
                              time >= 0, time >= (keys.last?.time ?? 0) else { return nil }
                        let place = positioned == 1 ? try reader.vector() : nil
                        keys.append(Key(time: time, turn: simd_quatf(vector: simd_normalize(vector)), originalTurn: vector, place: place))
                    }
                    tracks[bone] = keys
                }
                decoded[name] = Clip(duration: duration, tracks: tracks)
            }
            var mapped: [String: (String, String)] = [:]
            for _ in 0..<aliasCount {
                let alias = try reader.string(), source = try reader.string(), base = try reader.string()
                guard !alias.isEmpty, mapped[alias] == nil, decoded[source] != nil,
                      base.isEmpty || decoded[base] != nil else { return nil }
                mapped[alias] = (source, base)
            }
            guard reader.offset == reader.bytes.count, decoded["ped/idle_stance"]?.tracks[0] != nil else { return nil }
            clips = decoded
            aliases = mapped
        } catch { return nil }
    }

    func canonicalName(forWire name: String) -> String? {
        let lowered = name.lowercased()
        if clips[lowered] != nil || aliases[lowered] != nil { return lowered }
        let parts = lowered.split(separator: "/")
        if parts.count >= 2 {
            let original = String(parts[0]) + "/" + String(parts[1])
            if clips[original] != nil { return original }
        }
        return nil
    }
    func contains(_ name: String) -> Bool { canonicalName(forWire: name) != nil }
    func duration(of name: String) -> Double? { clip(name).map { Double($0.duration) } }
    func hasRoot(_ name: String) -> Bool { clip(name)?.tracks[0] != nil }
    func hasBone(_ bone: Int, in name: String) -> Bool { clip(name)?.tracks[bone] != nil }

    fileprivate func clip(_ name: String) -> Clip? {
        guard let canonical = canonicalName(forWire: name) else { return nil }
        if let direct = clips[canonical] { return direct }
        if let cached = joined[canonical] { return cached }
        guard let alias = aliases[canonical], let selected = clips[alias.source] else { return nil }
        var tracks = clips[alias.base]?.tracks ?? [:]
        tracks.merge(selected.tracks) { _, action in action }
        let combined = Clip(duration: selected.duration, tracks: tracks)
        joined[canonical] = combined
        return combined
    }

    fileprivate func time(_ elapsed: Double, clip: Clip, looping: Bool) -> Float {
        guard elapsed.isFinite, clip.duration > 0 else { return 0 }
        let positive = max(0, elapsed)
        return Float(looping ? positive.truncatingRemainder(dividingBy: Double(clip.duration)) :
                        min(positive, Double(clip.duration)))
    }

    fileprivate static func sample(_ keys: [Key], time: Float) -> Key {
        if time <= keys[0].time { return keys[0] }
        if time >= keys[keys.count - 1].time { return keys[keys.count - 1] }
        var low = 0, high = keys.count - 1
        while high - low > 1 {
            let middle = (low + high) / 2
            if keys[middle].time <= time { low = middle } else { high = middle }
        }
        let left = keys[low], right = keys[high]
        let alpha = min(1, max(0, (time - left.time) / max(0.000001, right.time - left.time)))
        let position: SIMD3<Float>?
        if let a = left.place, let b = right.place { position = a + (b - a) * alpha }
        else { position = left.place ?? right.place }
        return Key(time: time, turn: simd_slerp(left.turn, right.turn, alpha), originalTurn: left.originalTurn, place: position)
    }

    struct OriginalSample {
        let bone: Int
        let turn: SIMD4<Float>
        let place: SIMD3<Float>?
    }

    /// 49368.XM samples the quantized ANP3 quaternion before normalization.
    /// Normalizing individual keys changes the original weighted pose result.
    struct DoubleSample {let bone:Int;let turn:SIMD4<Double>;let place:SIMD3<Double>?}
    func originalDoubleSamples(_ name:String,at time:Double)->[DoubleSample] {
        guard let clip=clip(name) else{return []}
        return clip.tracks.map{bone,keys in let value=Self.originalSample(keys,time:time);return DoubleSample(bone:bone,turn:value.0,place:value.1)}
    }

    func originalSamples(_ name: String, at time: Double) -> [OriginalSample] {
        guard let clip = clip(name) else { return [] }
        return clip.tracks.map { bone, keys in
            let value = Self.originalSample(keys, time: time)
            return OriginalSample(bone: bone, turn: SIMD4(value.0), place: value.1.map { SIMD3<Float>($0) })
        }
    }

    func rootPosition(_ name:String,at time:Double)->SIMD3<Double> {
        guard let keys=clip(name)?.tracks[0] else{return .zero}
        return Self.originalSample(keys,time:time).1 ?? .zero
    }

    func travel(_ name: String, at time: Double) -> SIMD2<Double> {
        guard let keys = clip(name)?.tracks[0], let point = Self.originalSample(keys, time: time).1 else { return .zero }
        return SIMD2(point.x, point.y)
    }

    func cycleTravel(_ name: String) -> SIMD2<Double> {
        guard let duration = duration(of: name) else { return .zero }
        return travel(name, at: duration) - travel(name, at: 0)
    }

    private static func originalSample(_ keys: [Key], time: Double) -> (SIMD4<Double>, SIMD3<Double>?) {
        var low = 0, high = keys.count - 1
        if time >= Double(keys[high].time) { low = high }
        else {
            while high - low > 1 {
                let middle = (low + high) / 2
                if Double(keys[middle].time) <= time { low = middle } else { high = middle }
            }
        }
        let next = min(keys.count - 1, low + 1), left = keys[low], right = keys[next]
        let span = Double(right.time) - Double(left.time)
        let alpha = span > 0.000001 ? min(1, max(0, (time - Double(left.time)) / span)) : 0
        let a = slerpOriginal(SIMD4<Double>(left.originalTurn), SIMD4<Double>(right.originalTurn), alpha)
        let place: SIMD3<Double>?
        if let x = left.place, let y = right.place {
            let start = SIMD3<Double>(x), end = SIMD3<Double>(y)
            place = start + (end - start) * alpha
        } else { place = (left.place ?? right.place).map { SIMD3<Double>($0) } }
        return (a, place)
    }

    fileprivate static func slerpOriginal(_ from: SIMD4<Double>, _ to: SIMD4<Double>, _ alpha: Double) -> SIMD4<Double> {
        var b = to, cosine = simd_dot(from,to)
        if cosine < 0 { b = -b;cosine = -cosine }
        // The shipped 85339 Quaternion differs from stock Three: its near
        // branch normalizes a linear interpolation even at alpha zero/one.
        if cosine >= 0.9995 { return simd_normalize(from*(1-alpha)+b*alpha) }
        let angle = acos(cosine),sine = sin(angle)
        return from*(sin((1-alpha)*angle)/sine)+b*(sin(alpha*angle)/sine)
    }

    fileprivate var rootReference: Key { Self.sample(clips["ped/idle_stance"]!.tracks[0]!, time: 0) }
}

/// The vertex layout matches SkeletalShaders.metal. Original DFF coordinates
/// are preserved; the runtime palette produces native game coordinates.
struct NativeSkinVertex {
    let point: SIMD4<Float>
    let bones: SIMD4<UInt32>
    let weights: SIMD4<Float>
}

struct NativeSkeletalLayer {
    enum Mask {
        case all, upperBody, arms, lowerBody
        fileprivate func includes(_ bone: Int) -> Bool {
            let legs = bone == 0 || bone == 1 || (41...59).contains(bone)
            let arms = (21...39).contains(bone)
            switch self {
            case .all: return true
            case .upperBody: return !legs
            case .arms: return arms
            case .lowerBody: return legs
            }
        }
    }
    let clip: String
    let elapsed: Double
    var weight: Float = 1
    var mask: Mask = .all
    var looping: Bool? = nil
}

final class NativeSkeletalActor {
    struct OriginalAim {
        var look: Float = 0
        var spinePitch: Float = 0
        var rightArm: Float = 0
        var leftArm: Float = 0
        var pitch: Float = 0
        var yaw: Float = 0
        var twin: Float = 0
        var previousRightArm: Float = 0
        var previousLeftArm: Float = 0
        var previousPitch: Float = 0
        var previousYaw: Float = 0
    }
    struct Pose {
        let palette: [simd_float4x4]
        let hand: simd_float4x4
        let pelvis: simd_float4x4
        fileprivate let localTurns: [simd_quatf]
        fileprivate let localPlaces: [SIMD3<Float>]
        fileprivate let nativeGlobals: [simd_float4x4]
        fileprivate let rootTurn: simd_quatf
        fileprivate let rootHeight: Float
        fileprivate var figurePosition=SIMD3<Double>.zero
        fileprivate var rawTurns:[SIMD4<Double>]?
        fileprivate var rawPlaces:[SIMD3<Double>]?
    }
    private struct Frame {
        let parent: Int
        let bone: Int
        let rest: simd_float4x4
    }
    private struct Bone { let frame: Int; let inverseBind: simd_float4x4 }
    let skinVertices: MTLBuffer
    let vertexCount: Int
    private let vertices: [NativeSkinVertex]
    private let frames: [Frame]
    private let restTurns: [simd_quatf]
    private let restPlaces: [SIMD3<Float>]
    private let bones: [Bone]
    private let byBone: [Int: Int]
    private let correction: simd_float4x4
    private let axis: simd_float4x4

    init?(data: Data, vertexCount: Int, device: MTLDevice,allowAccessory: Bool = false) {
        var reader = SkeletonReader(bytes: [UInt8](data))
        do {
            guard try reader.u32() == 0x314e4b53 else { return nil } // SKN1
            let count = Int(try reader.u32()), frameCount = Int(try reader.u32()), boneCount = Int(try reader.u32())
            guard count == vertexCount, count > 0, count < 100_000,
                  frameCount > 0, frameCount <= 512, boneCount > 0, boneCount <= 64 else { return nil }
            let correction = try reader.matrix(), axis = try reader.matrix()
            var frames: [Frame] = [], byBone: [Int: Int] = [:]
            for index in 0..<frameCount {
                let parent = try reader.integer(), bone = try reader.integer(), rest = try reader.matrix()
                guard parent >= -1, parent < index, bone >= -1 else { return nil }
                if bone >= 0 {
                    guard byBone[bone] == nil else { return nil }
                    byBone[bone] = index
                }
                frames.append(Frame(parent: parent, bone: bone, rest: rest))
            }
            var bones: [Bone] = []
            for _ in 0..<boneCount {
                let frame = Int(try reader.u32()), inverse = try reader.matrix()
                guard frame < frameCount else { return nil }
                bones.append(Bone(frame: frame, inverseBind: inverse))
            }
            var vertices: [NativeSkinVertex] = []
            vertices.reserveCapacity(count)
            for _ in 0..<count {
                let point = try reader.vector()
                guard reader.offset + 4 <= reader.bytes.count else { return nil }
                let ids = reader.bytes[reader.offset..<(reader.offset + 4)].map { UInt32($0) }
                reader.offset += 4
                let weights = try SIMD4<Float>(reader.float(), reader.float(), reader.float(), reader.float())
                guard ids.allSatisfy({ $0 < boneCount }), weights.min() >= 0,
                      abs(weights.sum() - 1) < 0.01 else { return nil }
                vertices.append(NativeSkinVertex(point: SIMD4(point, 1),
                    bones: SIMD4(ids[0], ids[1], ids[2], ids[3]), weights: weights))
            }
            guard reader.offset == reader.bytes.count, (byBone[0] != nil || allowAccessory), byBone[1] != nil,
                  let buffer = device.makeBuffer(bytes: vertices,
                    length: vertices.count * MemoryLayout<NativeSkinVertex>.stride, options: .storageModeShared) else { return nil }
            self.skinVertices = buffer
            self.vertexCount = count
            self.vertices = vertices
            self.frames = frames
            self.restTurns = frames.map { simd_quatf($0.rest) }
            self.restPlaces = frames.map { SIMD3($0.rest.columns.3.x, $0.rest.columns.3.y, $0.rest.columns.3.z) }
            self.bones = bones
            self.byBone = byBone
            self.correction = correction
            self.axis = axis
        } catch { return nil }
    }

    /// With a locomotion base, the action's upper-body tracks leave the root,
    /// pelvis and legs running their own cycle. This is the browser's bone mask.
    func pose(clip name: String, elapsed: Double, library: NativeSkeletalAnimationLibrary,
              locomotion: String? = nil, locomotionElapsed: Double = 0,
              layers: [NativeSkeletalLayer] = [], previous: Pose? = nil,
              transition: Float = 1, looping: Bool? = nil) -> Pose? {
        guard let action = library.clip(name) else { return nil }
        var turns = restTurns
        var places = restPlaces
        var rootTurn = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
        var rootHeight: Float = 0
        let reference = library.rootReference
        func apply(_ clip: NativeSkeletalAnimationLibrary.Clip, elapsed: Double,
                   looping: Bool, weight: Float, mask: NativeSkeletalLayer.Mask) {
            let time = library.time(elapsed, clip: clip, looping: looping)
            let share = min(1, max(0, weight))
            for (bone, keys) in clip.tracks where mask.includes(bone) {
                guard let index = byBone[bone] else { continue }
                let key = NativeSkeletalAnimationLibrary.sample(keys, time: time)
                if bone == 0 {
                    let rotation = key.turn * reference.turn.inverse
                    rootTurn = simd_slerp(rootTurn, rotation, share)
                    let height = (key.place?.z ?? 0) - (reference.place?.z ?? 0)
                    rootHeight += (height - rootHeight) * share
                } else {
                    turns[index] = simd_slerp(turns[index], key.turn, share)
                    if let place = key.place { places[index] += (place - places[index]) * share }
                }
            }
        }
        if let locomotion, let base = library.clip(locomotion) {
            apply(base, elapsed: locomotionElapsed, looping: NativePedestrianMotion.loops(locomotion),
                  weight: 1, mask: .all)
            apply(action, elapsed: elapsed, looping: looping ?? NativePedestrianMotion.loops(name),
                  weight: 1, mask: .upperBody)
        } else {
            apply(action, elapsed: elapsed, looping: looping ?? NativePedestrianMotion.loops(name),
                  weight: 1, mask: .all)
        }
        for layer in layers {
            if let clip = library.clip(layer.clip) {
                apply(clip, elapsed: layer.elapsed, looping: layer.looping ?? NativePedestrianMotion.loops(layer.clip),
                      weight: layer.weight, mask: layer.mask)
            }
        }
        if let previous, previous.localTurns.count == turns.count {
            let share = min(1, max(0, transition))
            for index in turns.indices {
                turns[index] = simd_slerp(previous.localTurns[index], turns[index], share)
                places[index] = previous.localPlaces[index] + (places[index] - previous.localPlaces[index]) * share
            }
            rootTurn = simd_slerp(previous.rootTurn, rootTurn, share)
            rootHeight = previous.rootHeight + (rootHeight - previous.rootHeight) * share
        }
        var root = simd_float4x4(rootTurn)
        let pivot = SIMD3<Float>(0, 0, axis.columns.3.z)
        let rotated = root * SIMD4(pivot, 1)
        root.columns.3 = SIMD4(pivot - SIMD3(rotated.x, rotated.y, rotated.z) + SIMD3(0, 0, rootHeight), 1)
        var globals: [simd_float4x4] = []
        globals.reserveCapacity(frames.count)
        for index in frames.indices {
            var local = simd_float4x4(turns[index])
            local.columns.3 = SIMD4(places[index], 1)
            globals.append(frames[index].parent >= 0 ? globals[frames[index].parent] * local : local)
        }
        let nativeBasis = root * axis * correction
        let native = globals.map { nativeBasis * $0 }
        let palette = bones.map { native[$0.frame] * $0.inverseBind }
        let hand = byBone[26].map { native[$0] } ?? matrix_identity_float4x4
        let pelvis = native[byBone[1]!]
        return Pose(palette: palette, hand: hand, pelvis: pelvis, localTurns: turns,
                    localPlaces: places, nativeGlobals: native, rootTurn: rootTurn, rootHeight: rootHeight)
    }

    func transform(bone: Int, in pose: Pose) -> simd_float4x4? {
        byBone[bone].map { pose.nativeGlobals[$0] }
    }

    /// Direct public-browser pose path. The original root track is a local
    /// bone transform, not a rotation relative to idle. After converting the
    /// browser Y-up group back to GTA coordinates its only outer transform is
    /// figure.position.z=1. The legacy baked floor/correction is inappropriate
    /// here and would rotate the character's whole body away from its pose.
    func originalPose(blends: [NativeSkeletalBlend], library: NativeSkeletalAnimationLibrary,
                      aim: OriginalAim = OriginalAim(), hiddenBones: Set<Int> = [],
                      previous: Pose? = nil, transition: Float = 1, figurePitch: Float = 0,figureRoll: Float = 0,legBend: SIMD2<Float> = .zero) -> Pose {
        struct Accumulator {
            var turn = SIMD4<Double>.zero
            var place = SIMD3<Double>.zero
            var weight: Double = 0
        }
        var sums = Array(repeating: Accumulator(), count: frames.count)
        var rootPlace = SIMD3<Double>.zero
        var spineCompensation: NativeSkeletalBlend?
        func accumulate(_ index: Int, _ turn: SIMD4<Float>, _ place: SIMD3<Float>, _ weight: Double) {
            var q = SIMD4<Double>(turn)
            if simd_dot(sums[index].turn, q) < 0 { q = -q }
            sums[index].turn += q * weight
            sums[index].place += SIMD3<Double>(place) * weight
            sums[index].weight += weight
        }
        for blend in blends {
            if blend.operation == .spineCompensation { spineCompensation = blend; continue }
            if blend.operation == .fillRest {
                for (_, index) in byBone where sums[index].weight < 1 {
                    accumulate(index, restTurns[index].vector, restPlaces[index], 1 - sums[index].weight)
                }
                continue
            }
            guard blend.weight > 0.0001 else { continue }
            let samples = library.originalSamples(blend.clip, at: blend.time).filter { sample in
                !(blend.skipArms && ((21...29).contains(sample.bone) || (31...39).contains(sample.bone))) &&
                !(blend.skipLegs && (sample.bone == 0 || sample.bone == 1 || (41...59).contains(sample.bone)))
            }
            if blend.operation == .replace {
                for sample in samples {
                    guard let index = byBone[sample.bone] else { continue }
                    sums[index].turn *= 1 - blend.weight; sums[index].place *= 1 - blend.weight
                    sums[index].weight *= 1 - blend.weight
                }
                if samples.contains(where: { $0.bone == 0 }) { rootPlace *= 1 - blend.weight }
            }
            for sample in samples {
                guard let index = byBone[sample.bone] else { continue }
                if sample.bone == 0 {
                    if let place = sample.place {
                        rootPlace.x += (blend.zeroSide ? 0 : Double(place.x)) * blend.weight
                        rootPlace.z += Double(place.z) * blend.weight
                        if blend.rooted { rootPlace.y += Double(place.y) * blend.weight }
                    }
                    accumulate(index, sample.turn, restPlaces[index], blend.weight)
                } else { accumulate(index, sample.turn, sample.place ?? restPlaces[index], blend.weight) }
            }
        }
        var turns = restTurns, places = restPlaces
        for (bone, index) in byBone {
            let sum = sums[index]
            guard sum.weight >= 0.000001, simd_length_squared(sum.turn) >= 0.00000001 else { continue }
            turns[index] = simd_quatf(vector: SIMD4(simd_normalize(sum.turn)))
            places[index] = bone == 0 ? restPlaces[index] + SIMD3(rootPlace / sum.weight) : SIMD3(sum.place / sum.weight)
        }
        // Three.Matrix4.compose keeps 1-(yy+zz) on the diagonal. SIMD's
        // quaternion matrix constructor substitutes w²+x²-y²-z²; those are
        // equivalent only for unit quaternions. R6's crouched spine correction
        // intentionally retains raw ANP3 quaternion magnitudes.
        func originalMatrix(_ value: simd_quatf) -> simd_float4x4 {
            let q = value.vector
            let x2 = q.x + q.x, y2 = q.y + q.y, z2 = q.z + q.z
            let xx = q.x*x2, xy = q.x*y2, xz = q.x*z2
            let yy = q.y*y2, yz = q.y*z2, zz = q.z*z2
            let wx = q.w*x2, wy = q.w*y2, wz = q.w*z2
            return simd_float4x4(columns:(SIMD4(1-(yy+zz),xy+wz,xz-wy,0),SIMD4(xy-wz,1-(xx+zz),yz+wx,0),SIMD4(xz+wy,yz-wx,1-(xx+yy),0),SIMD4(0,0,0,1)))
        }
        func originalSlerp(_ a: simd_quatf,_ b: simd_quatf,_ weight: Float) -> simd_quatf {
            simd_quatf(vector:SIMD4(NativeSkeletalAnimationLibrary.slerpOriginal(SIMD4<Double>(a.vector),SIMD4<Double>(b.vector),Double(weight))))
        }
        func globals() -> [simd_float4x4] {
            var result: [simd_float4x4] = []
            for index in frames.indices {
                var local = originalMatrix(turns[index]); local.columns.3 = SIMD4(places[index], 1)
                if hiddenBones.contains(frames[index].bone) {
                    local.columns.0 = .zero; local.columns.1 = .zero; local.columns.2 = .zero
                }
                result.append(frames[index].parent >= 0 ? result[frames[index].parent] * local : local)
            }
            return result
        }
        func axisTurn(_ bone: Int, _ axis: SIMD3<Float>, _ angle: Float) {
            guard angle != 0, let index = byBone[bone] else { return }
            let current = globals(), rotation = simd_quatf(current[index])
            let localAxis = simd_normalize(rotation.inverse.act(axis))
            turns[index] = turns[index] * simd_quatf(angle: angle, axis: localAxis)
        }
        if let blend = spineCompensation, let pelvis = byBone[1], let root = byBone[0], let spine = byBone[2] {
            let samples = library.originalSamples(blend.clip, at: min(blend.time, library.duration(of: blend.clip) ?? 0))
            if let pelvisSample = samples.first(where: { $0.bone == 1 }) {
                let rootTurn = samples.first(where: { $0.bone == 0 }).map { simd_quatf(vector: $0.turn) } ?? turns[root]
                let desired = rootTurn * simd_quatf(vector: pelvisSample.turn)
                var correction = (turns[root] * turns[pelvis]).inverse * desired
                if blend.weight < 1 {
                    let value = NativeSkeletalAnimationLibrary.slerpOriginal(SIMD4<Double>(correction.vector), SIMD4(0,0,0,1), 1-blend.weight)
                    correction = simd_quatf(vector: SIMD4(value))
                }
                turns[spine] = correction * turns[spine]
            }
        }
        // 49368.R6.from: preserve the new ROOT and smoothstep the other bones.
        if let previous, previous.localTurns.count == turns.count, transition < 1 {
            let value = min(1, max(0, transition)), share = value * value * (3 - 2 * value)
            for (_, index) in byBone where frames[index].bone != 0 {
                turns[index] = originalSlerp(previous.localTurns[index], turns[index], share)
                places[index] = previous.localPlaces[index] + (places[index] - previous.localPlaces[index]) * share
            }
        }
        if abs(legBend.x)>=0.001 || abs(legBend.y)>=0.001 {
            for bone in [41,51] {
                if let index=byBone[bone] {turns[index] = turns[index]*simd_quatf(angle:legBend.x,axis:SIMD3(0,0,1))*simd_quatf(angle:legBend.y,axis:SIMD3(0,1,0))}
            }
        }
        if aim.look != 0 {
            axisTurn(4, SIMD3(0, 0, 1), aim.look * 0.4)
            axisTurn(5, SIMD3(0, 0, 1), aim.look * 0.6)
        }
        axisTurn(3, SIMD3(1, 0, 0), aim.spinePitch)
        func arm(left: Bool, weight: Float, pitch: Float, yaw: Float) {
            guard weight > 0.001, let upper = byBone[left ? 32 : 22], let fore = byBone[left ? 33 : 23],
                  let hand = byBone[left ? 34 : 24] else { return }
            let previousUpper = turns[upper], previousFore = turns[fore], previousHand = turns[hand]
            turns[upper] = restTurns[upper]; turns[fore] = restTurns[fore]
            var current = globals()
            let target = SIMD3(-sin(yaw) * cos(pitch), cos(yaw) * cos(pitch), sin(pitch))
            let upperPlace = SIMD3(current[upper].columns.3.x, current[upper].columns.3.y, current[upper].columns.3.z)
            let handPlace = SIMD3(current[hand].columns.3.x, current[hand].columns.3.y, current[hand].columns.3.z)
            let pointing = simd_normalize(handPlace - upperPlace)
            let swing = simd_quatf(from: pointing, to: target)
            let parent = frames[upper].parent
            let parentTurn = parent >= 0 ? simd_quatf(current[parent]) : simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
            turns[upper] = originalSlerp(previousUpper, parentTurn.inverse * (swing * simd_quatf(current[upper])), weight)
            turns[fore] = originalSlerp(previousFore, restTurns[fore], weight)
            current = globals()
            var upright = simd_normalize(SIMD3<Float>(0, 0, 1) - target * sin(pitch))
            if left { upright = -upright }
            let side = simd_cross(upright, target)
            let basis = simd_float3x3(columns: (target, side, upright))
            let handParent = frames[hand].parent
            let handParentTurn = handParent >= 0 ? simd_quatf(current[handParent]) : simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1))
            turns[hand] = originalSlerp(previousHand, handParentTurn.inverse * simd_quatf(basis), weight)
        }
        arm(left: false, weight: aim.previousRightArm, pitch: aim.previousPitch, yaw: aim.previousYaw)
        arm(left: true, weight: aim.previousLeftArm, pitch: aim.previousPitch, yaw: aim.previousYaw)
        if aim.twin > 0, let index = byBone[3] {
            let current = globals(), direction = simd_quatf(current[index]).act(SIMD3(0, 1, 0))
            axisTurn(3, SIMD3(0, 0, 1), -atan2(-direction.x, direction.y) * aim.twin)
            if let clavicle = byBone[21] { turns[clavicle] = originalSlerp(turns[clavicle], restTurns[clavicle], aim.twin) }
        }
        arm(left: false, weight: aim.rightArm, pitch: aim.pitch, yaw: aim.yaw)
        arm(left: true, weight: aim.leftArm, pitch: aim.pitch, yaw: aim.yaw)
        var lift = matrix_identity_float4x4; lift.columns.3.z = 1
        if figurePitch != 0 { lift *= originalMatrix(simd_quatf(angle:figurePitch,axis:SIMD3<Float>(1,0,0))) }
        if figureRoll != 0 {lift *= originalMatrix(simd_quatf(angle:figureRoll,axis:SIMD3<Float>(0,1,0)))}
        let native = globals().map { lift * $0 }, palette = bones.map { native[$0.frame] * $0.inverseBind }
        return Pose(palette: palette, hand: byBone[24].map { native[$0] } ?? matrix_identity_float4x4,
                    pelvis: native[byBone[1]!], localTurns: turns, localPlaces: places, nativeGlobals: native,
                    rootTurn: simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1)), rootHeight: 0)
    }

    func bind(pose: Pose, encoder: MTLRenderCommandEncoder) {
        encoder.setVertexBuffer(skinVertices, offset: 0, index: 2)
        pose.palette.withUnsafeBytes { raw in
            if let base = raw.baseAddress { encoder.setVertexBytes(base, length: raw.count, index: 3) }
        }
    }

    /// CPU reference used to compare the runtime palette and Metal skinning.
    func positions(pose: Pose) -> [SIMD3<Float>] {
        vertices.map { vertex in
            var point = SIMD4<Float>.zero
            for slot in 0..<4 where vertex.weights[slot] > 0 {
                point += (pose.palette[Int(vertex.bones[slot])] * vertex.point) * vertex.weights[slot]
            }
            return SIMD3(point.x, point.y, point.z)
        }
    }
}

extension NativeSkeletalActor {
    /// Public bA's distinct raw seated poser. Unlike R6 it samples the full
    /// root translation and sequentially slerps without normalizing keys.
    func riderPose(frame: NativeRiderAnimation.Frame,library: NativeSkeletalAnimationLibrary,
                   figurePosition: SIMD3<Float>,figureTurn: Float = 0,previous:Pose? = nil,transition:Double = 1) -> Pose {
        var turns=restTurns.map{SIMD4<Double>($0.vector)},places=restPlaces.map{SIMD3<Double>($0)}
        func apply(_ name:String,_ time:Double,_ weight:Double){
            for sample in library.originalDoubleSamples(name,at:time){
                guard let index=byBone[sample.bone] else{continue}
                let point=sample.bone==0 ? SIMD3<Double>(restPlaces[index])+(sample.place ?? .zero):sample.place ?? SIMD3<Double>(restPlaces[index])
                if weight>=1{turns[index]=sample.turn;places[index]=point}
                else{turns[index]=NativeSkeletalAnimationLibrary.slerpOriginal(turns[index],sample.turn,weight);places[index]+=(point-places[index])*weight}
            }
        }
        if let clip=frame.base{apply(clip,frame.time,1)}
        for mix in frame.mixes where mix.weight>0.001{apply(mix.clip,mix.time,min(1,mix.weight))}
        var anchor=SIMD3<Double>(figurePosition)
        if let previous {
            for(_,index)in byBone {
                let oldTurn=previous.rawTurns?[index] ?? SIMD4<Double>(previous.localTurns[index].vector)
                let oldPlace=previous.rawPlaces?[index] ?? SIMD3<Double>(previous.localPlaces[index])
                turns[index]=NativeSkeletalAnimationLibrary.slerpOriginal(oldTurn,turns[index],transition)
                places[index]=oldPlace+(places[index]-oldPlace)*transition
            }
            anchor=previous.figurePosition+(anchor-previous.figurePosition)*transition
        }
        func compose(_ q:SIMD4<Double>,_ point:SIMD3<Double>)->simd_float4x4 {
            let x2=q.x+q.x,y2=q.y+q.y,z2=q.z+q.z
            let xx=q.x*x2,xy=q.x*y2,xz=q.x*z2,yy=q.y*y2,yz=q.y*z2,zz=q.z*z2,wx=q.w*x2,wy=q.w*y2,wz=q.w*z2
            return simd_float4x4(columns:(SIMD4<Float>(SIMD4(1-(yy+zz),xy+wz,xz-wy,0)),SIMD4<Float>(SIMD4(xy-wz,1-(xx+zz),yz+wx,0)),SIMD4<Float>(SIMD4(xz+wy,yz-wx,1-(xx+yy),0)),SIMD4<Float>(SIMD4(point,1))))
        }
        let figure=compose(SIMD4<Double>(simd_quatf(angle:figureTurn,axis:SIMD3<Float>(0,0,1)).vector),anchor)
        var globals:[simd_float4x4]=[]
        for index in frames.indices{let local=compose(turns[index],places[index]);globals.append(frames[index].parent>=0 ? globals[frames[index].parent]*local:local)}
        let native=globals.map{figure*$0},palette=bones.map{native[$0.frame]*$0.inverseBind}
        return Pose(palette:palette,hand:byBone[24].map{native[$0]} ?? matrix_identity_float4x4,pelvis:native[byBone[1]!],localTurns:turns.map{simd_quatf(vector:SIMD4<Float>($0))},localPlaces:places.map{SIMD3<Float>($0)},nativeGlobals:native,rootTurn:simd_quatf(angle:0,axis:SIMD3<Float>(0,0,1)),rootHeight:0,figurePosition:anchor,rawTurns:turns,rawPlaces:places)
    }

}


extension NativeSkeletalActor {
    /// 54205 canopy: persist bone state and ease every tracked quaternion and
    /// positioned key directly. This is separate from R6 and the seated root.
    func canopyPose(clip:String,time:Double,easing:Double,pitch:Double,roll:Double,library:NativeSkeletalAnimationLibrary,previous:Pose?)->Pose {
        var turns=previous?.localTurns ?? restTurns,places=previous?.localPlaces ?? restPlaces
        for sample in library.originalSamples(clip,at:time) {
            guard let index=byBone[sample.bone] else{continue}
            let value=NativeSkeletalAnimationLibrary.slerpOriginal(SIMD4<Double>(turns[index].vector),SIMD4<Double>(sample.turn),easing)
            turns[index]=simd_quatf(vector:SIMD4<Float>(value))
            if let place=sample.place {places[index]+=(place-places[index])*Float(easing)}
        }
        func compose(_ q:simd_quatf)->simd_float4x4 {
            let q=q.vector,x=q.x*2,y=q.y*2,z=q.z*2
            return simd_float4x4(columns:(SIMD4(1-(q.y*y+q.z*z),q.x*y+q.w*z,q.x*z-q.w*y,0),SIMD4(q.x*y-q.w*z,1-(q.x*x+q.z*z),q.y*z+q.w*x,0),SIMD4(q.x*z+q.w*y,q.y*z-q.w*x,1-(q.x*x+q.y*y),0),SIMD4(0,0,0,1)))
        }
        var figure=compose(simd_quatf(angle:Float(pitch),axis:SIMD3(1,0,0)))*compose(simd_quatf(angle:Float(roll),axis:SIMD3(0,1,0)))
        figure.columns.3.z=1
        var globals:[simd_float4x4]=[]
        for index in frames.indices {
            var local=compose(turns[index]);local.columns.3=SIMD4(places[index],1)
            globals.append(frames[index].parent>=0 ? globals[frames[index].parent]*local:local)
        }
        let native=globals.map{figure*$0},palette=bones.map{native[$0.frame]*$0.inverseBind}
        return Pose(palette:palette,hand:byBone[24].map{native[$0]} ?? matrix_identity_float4x4,pelvis:native[byBone[1]!],localTurns:turns,localPlaces:places,nativeGlobals:native,rootTurn:simd_quatf(vector:SIMD4(0,0,0,1)),rootHeight:0)
    }
}


extension NativeSkeletalActor {
    /// bA.stood: root supplies horizontal feet; the figure anchor projected
    /// onto z=-origin supplies the upright ground plane beneath the car.
    func riderFeet(pose:Pose,model:simd_float4x4,origin:Float)->(position:SIMD3<Float>,heading:Float)? {
        guard let root=transform(bone:0,in:pose) else{return nil}
        let world=model*root,plane=model*SIMD4(Float(pose.figurePosition.x),Float(pose.figurePosition.y),-origin,1)
        let direction=world*SIMD4<Float>(0,1,0,0)
        return(SIMD3(world.columns.3.x,world.columns.3.y,plane.z),atan2(direction.x,direction.y))
    }
}
