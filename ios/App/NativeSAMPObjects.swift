// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Independent object RPC decoding and session ownership. Reference:
/// open.mp Shared/NetCode/object.hpp and Objects/object.hpp, commit
/// 72bf89ce4c8164f7f7b8271ffc7323bc45ea005f. All rotations remain GTA degrees;
/// the renderer performs its coordinate conversion once at the draw boundary.
enum NativeSAMPObjects {
    enum Failure: Error { case invalid, limit }
    enum Parent: Equatable { case vehicle(UInt16), object(UInt16), player(UInt16) }
    struct Attachment: Equatable {
        let parent: Parent
        let offset, rotation: SIMD3<Float>
        let syncRotation: Bool
    }
    enum Material: Hashable {
        case texture(model: UInt16, dictionary: String, texture: String, abgr: UInt32)
        case text(size: UInt8, font: String, fontSize: UInt8, bold: Bool,
                  foregroundARGB: UInt32, backgroundARGB: UInt32, alignment: UInt8, text: String)
    }
    struct Instance: Equatable {
        let id: UInt16
        let model: Int32
        var position, rotation: SIMD3<Float>
        let drawDistance: Float
        let cameraCollision: Bool
        var attachment: Attachment?
        var materials: [UInt8: Material]
    }
    enum Event {
        case create(Instance), destroy(UInt16), position(UInt16, SIMD3<Float>), rotation(UInt16, SIMD3<Float>)
        case move(UInt16, from: SIMD3<Float>, to: SIMD3<Float>, speed: Float, rotation: SIMD3<Float>)
        case stop(UInt16), attach(UInt16, Attachment), material(UInt16, UInt8, Material)
    }

    static func decode(_ rpc: NativeSAMPProtocol.RPC,
                       encoding: NativeSAMPTextCodec.Encoding = .windows1252) throws -> Event? {
        var reader = try NativeSAMPProtocol.Reader(rpc.data, bits: rpc.bits)
        func id(_ r: inout NativeSAMPProtocol.Reader) throws -> UInt16 {
            let value = UInt16(try r.integer(2))
            guard value != .max else { throw Failure.invalid }; return value
        }
        func vector(_ r: inout NativeSAMPProtocol.Reader) throws -> SIMD3<Float> {
            let value = try r.vector()
            guard value.x.magnitude <= 10_000_000, value.y.magnitude <= 10_000_000,
                  value.z.magnitude <= 10_000_000 else { throw Failure.limit }
            return value
        }
        func string(_ r: inout NativeSAMPProtocol.Reader) throws -> String {
            let count = Int(try r.integer(1))
            return NativeSAMPTextCodec.decode(try r.bytes(count * 8), encoding: encoding)
        }
        func material(_ r: inout NativeSAMPProtocol.Reader) throws -> (UInt8, Material) {
            let kind = try r.integer(1), slot = UInt8(try r.integer(1))
            guard slot < 16 else { throw Failure.invalid }
            switch kind {
            case 1:
                let model = UInt16(try r.integer(2)), dictionary = try string(&r), texture = try string(&r)
                return (slot, .texture(model: model, dictionary: dictionary, texture: texture, abgr: try r.integer(4)))
            case 2:
                let size = UInt8(try r.integer(1)), font = try string(&r), fontSize = UInt8(try r.integer(1))
                let bold = try r.integer(1), foreground = try r.integer(4), background = try r.integer(4)
                let alignment = UInt8(try r.integer(1))
                guard (10...140).contains(size), size % 10 == 0, fontSize > 0, bold <= 1, alignment <= 2 else { throw Failure.invalid }
                let text = NativeSAMPTextCodec.decode(try NativeSAMPTextCodec.compressed(&r, maxBytes: 2048), encoding: encoding)
                return (slot, .text(size: size, font: font, fontSize: fontSize, bold: bold == 1,
                                   foregroundARGB: foreground, backgroundARGB: background, alignment: alignment, text: text))
            default: throw Failure.invalid
            }
        }
        let event: Event
        switch rpc.id {
        case 44:
            let object = try id(&reader), model = Int32(bitPattern: try reader.integer(4))
            let position = try vector(&reader), rotation = try vector(&reader), distance = try reader.float()
            let disableCamera = try reader.integer(1), vehicle = UInt16(try reader.integer(2)), parent = UInt16(try reader.integer(2))
            guard model != 0, distance >= 0, distance <= 100_000, disableCamera <= 1,
                  vehicle == .max || parent == .max else { throw Failure.invalid }
            var attachment: Attachment?
            if vehicle != .max || parent != .max {
                let offset = try vector(&reader), turn = try vector(&reader), sync = try reader.integer(1)
                guard sync <= 1 else { throw Failure.invalid }
                attachment = Attachment(parent: vehicle != .max ? .vehicle(vehicle):.object(parent),
                                        offset: offset, rotation: turn, syncRotation: sync == 1)
            }
            let count = Int(try reader.integer(1)); guard count <= 16 else { throw Failure.limit }
            var materials: [UInt8: Material] = [:]
            for _ in 0..<count {
                let (slot, value) = try material(&reader)
                guard materials.updateValue(value, forKey: slot) == nil else { throw Failure.invalid }
            }
            event = .create(Instance(id: object, model: model, position: position, rotation: rotation,
                                     drawDistance: distance, cameraCollision: disableCamera == 0,
                                     attachment: attachment, materials: materials))
        case 47: event = .destroy(try id(&reader))
        case 45: event = .position(try id(&reader), try vector(&reader))
        case 46: event = .rotation(try id(&reader), try vector(&reader))
        case 99:
            let object = try id(&reader), from = try vector(&reader), to = try vector(&reader), speed = try reader.float()
            guard speed > 0, speed <= 100_000 else { throw Failure.invalid }
            event = .move(object, from: from, to: to, speed: speed, rotation: try vector(&reader))
        case 122: event = .stop(try id(&reader))
        case 75:
            let object = try id(&reader), player = try id(&reader), offset = try vector(&reader), rotation = try vector(&reader)
            event = .attach(object, Attachment(parent: .player(player), offset: offset, rotation: rotation, syncRotation: true))
        case 84:
            let object = try id(&reader), (slot, value) = try material(&reader)
            event = .material(object, slot, value)
        default: return nil
        }
        guard reader.remaining == 0 else { throw Failure.invalid }
        return event
    }

    /// Monotonic, elapsed-time movement. The server linearly interpolates raw
    /// Euler degrees; silently taking a shortest arc would change its motion.
    /// Missing attached parents remain unresolved, rather than drawing at zero.
    final class Store {
        private struct Motion {
            let from, to, rotationFrom, rotationTo: SIMD3<Float>
            let started, duration, rotationDuration: Double
            let speed, rotationSpeed: Float
            init(from: SIMD3<Float>, to: SIMD3<Float>, rotationFrom: SIMD3<Float>, rotationTo: SIMD3<Float>,
                 started: Double, speed: Float, rotationSpeed: Float? = nil) {
                self.from = from; self.to = to; self.rotationFrom = rotationFrom; self.rotationTo = rotationTo
                self.started = started; self.speed = speed
                let distance = Double(simd_length(to - from)), rotation = Double(simd_length(rotationTo - rotationFrom))
                duration = distance / Double(speed)
                let rate = rotationSpeed ?? (distance > 0 ? Float(rotation / duration):0)
                self.rotationSpeed = rate
                rotationDuration = rate > 0 ? rotation / Double(rate):.infinity
            }
        }
        private var objects: [UInt16: Instance] = [:]
        private var motion: [UInt16: Motion] = [:]
        private var clock = -Double.infinity
        let maximumObjects: Int
        init(maximumObjects: Int = 4096) { self.maximumObjects = max(1, min(65535, maximumObjects)) }
        var count: Int { objects.count }
        func reset() { objects.removeAll(); motion.removeAll(); clock = -.infinity }
        private func advance(_ time: Double) throws -> Double {
            guard time.isFinite else { throw Failure.invalid }; clock = max(clock, time); return clock
        }
        private func sample(_ id: UInt16, at time: Double) -> Instance? {
            guard var object = objects[id] else { return nil }
            if let move = motion[id] {
                let elapsed = max(0, time - move.started)
                let ratio = Float(move.duration > 0 ? min(1, elapsed / move.duration):1)
                object.position = move.from + (move.to - move.from) * ratio
                let rotationRatio = ratio == 1 ? 1:Float(move.rotationDuration > 0 ? min(1, elapsed / move.rotationDuration):1)
                object.rotation = move.rotationFrom + (move.rotationTo - move.rotationFrom) * rotationRatio
            }
            return object
        }
        func instances(at time: Double) throws -> [Instance] {
            let time = try advance(time)
            return objects.keys.sorted().compactMap { sample($0, at: time) }
        }
        /// Render and fixed-step consumers can sample the same motion at their
        /// own timestamps. Observing it must not advance the command clock or
        /// clamp an earlier physical substep to a later display-frame pose.
        func sampledInstances(at time:Double)throws->[Instance] {
            guard time.isFinite else{throw Failure.invalid}
            return objects.keys.sorted().compactMap{sample($0,at:time)}
        }
        func apply(_ event: Event, at time: Double) throws {
            let time = try advance(time)
            switch event {
            case .create(let value):
                guard objects[value.id] != nil || objects.count < maximumObjects else { throw Failure.limit }
                objects[value.id] = value; motion.removeValue(forKey: value.id)
            case .destroy(let id): objects.removeValue(forKey: id); motion.removeValue(forKey: id)
            case .move(let id, let from, let to, let speed, let rotation):
                guard var value = sample(id, at: time) else { return }
                guard speed.isFinite, speed > 0 else { throw Failure.invalid }
                var target = rotation
                for axis in 0..<3 where target[axis] <= -1000 { target[axis] = value.rotation[axis] }
                value.position = from; value.attachment = nil; objects[id] = value
                motion[id] = Motion(from: from, to: to, rotationFrom: value.rotation, rotationTo: target,
                                    started: time, speed: speed)
            case .stop(let id): objects[id] = sample(id, at: time); motion.removeValue(forKey: id)
            case .position(let id, let point):
                guard var value = sample(id, at: time) else { return }
                value.position = point; objects[id] = value
                if let move = motion[id] {
                    motion[id] = Motion(from: point, to: move.to, rotationFrom: value.rotation, rotationTo: move.rotationTo,
                                        started: time, speed: move.speed, rotationSpeed: move.rotationSpeed)
                }
            case .rotation(let id, let rotation):
                guard var value = sample(id, at: time) else { return }
                value.rotation = rotation; objects[id] = value
                if let move = motion[id] {
                    motion[id] = Motion(from: value.position, to: move.to, rotationFrom: rotation, rotationTo: move.rotationTo,
                                        started: time, speed: move.speed, rotationSpeed: move.rotationSpeed)
                }
            case .attach(let id, let attachment):
                guard var value = sample(id, at: time) else { return }
                value.attachment = attachment; objects[id] = value; motion.removeValue(forKey: id)
            case .material(let id, let slot, let material): objects[id]?.materials[slot] = material
            }
        }
    }
}
