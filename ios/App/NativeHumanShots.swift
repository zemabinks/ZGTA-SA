// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CoreFoundation
import simd

/// Received ordinary shots are presentation observations, never damage grants.
/// Foot packets wait for the existing animation marker. Vehicle appearances
/// use the packet ray immediately; these two source paths have different rules.
final class NativeHumanShots {
    typealias V = SIMD3<Double>
    struct Packet {
        let shooter: String
        let weapon: Int
        let origin: V, end: V
        let kind: NativeOrdinaryShot.Impact?
        let piece: Int?
        let target:String?
        let reportsWorldShot: Bool

        init?(_ row: [String: Any]) {
            func number(_ value: Any?) -> Double? {
                guard let value = value as? NSNumber,
                      CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
                return value.doubleValue
            }
            func integer(_ value: Any?) -> Int? { number(value).flatMap(Int.init(exactly:)) }
            func point(_ value: Any?) -> V? {
                guard let values = value as? [Any], values.count == 3,
                      let x = number(values[0]), let y = number(values[1]), let z = number(values[2]) else { return nil }
                return V(x,y,z)
            }
            guard let shooter = row["from"] as? String, !shooter.isEmpty,
                  let weapon = integer(row["w"]), (0...255).contains(weapon),
                  let origin = point(row["o"]), let end = point(row["h"]) else { return nil }
            self.shooter = shooter; self.weapon = weapon; self.origin = origin; self.end = end
            // Human ht is not the compact-traffic kind: 3 is a car, while
            // unrecognized values are world hits. Only exactly 4 notifies
            // the original world's separate object-interaction callback.
            switch integer(row["ht"]) {
            case 0: kind = nil
            case 1: kind = .person
            case 2,3: kind = .car
            default: kind = .world
            }
            piece = integer(row["bp"]); reportsWorldShot = integer(row["ht"]) == 4
            if let id=row["id"]as?String{target=id}
            else if let id=integer(row["id"]){target=String(id)}
            else{target=nil}
        }
        var event: NativeOrdinaryShot.Event {
            .init(weapon:weapon,origin:origin,end:end,impact:kind,piece:piece)
        }
    }
    struct Immediate {
        let event: NativeOrdinaryShot.Event
        var soundWeapon: Int { event.weapon == 38 ? 31 : event.weapon }
    }
    struct Marker {
        let event: NativeOrdinaryShot.Event
        /// Smoke, casing, pass-by and sound use the current held muzzle even
        /// if a distant packet origin owns the tracer and hit presentation.
        let muzzle: V, direction: V
        let left: Bool
        let usedPacket: Bool
        let reportsWorldShot: Bool
    }
    private struct Queued { let packet: Packet; let receivedMilliseconds: Double }
    struct Strike {
        let weapon:Int,origin:V,piece:Int?,atMilliseconds:Double
    }
    private var pending: [String: [Queued]] = [:]
    private var strikes:[String:Strike]=[:]
    func clear() { pending.removeAll();strikes.removeAll() }
    func retain(_ shooters: Set<String>) {
        pending = pending.filter { shooters.contains($0.key) }
        strikes = strikes.filter { shooters.contains($0.key) }
    }
    /// A packet explains a later authoritative life change; it cannot apply
    /// that change itself. The original requires an existing person owner.
    func observeStrike(_ packet:Packet,targetReady:Bool,at now:Double) {
        guard targetReady,packet.kind == .person,let target=packet.target,
              now.isFinite,(now*1000).isFinite else{return}
        strikes[target]=Strike(weapon:packet.weapon,origin:packet.origin,piece:packet.piece,atMilliseconds:now*1000)
    }
    func clearStrike(_ target:String){strikes[target]=nil}
    func recentStrike(_ target:String,at now:Double)->Strike? {
        guard now.isFinite,(now*1000).isFinite,let hit=strikes[target]else{return nil}
        if now*1000-hit.atMilliseconds<1000{return hit}
        strikes[target]=nil;return nil
    }
    func queued(_ shooter: String) -> Int { pending[shooter]?.count ?? 0 }

    /// `footAppearance` is the original s-prefix identity, including seated
    /// passengers. Drawing or loading a pedestrian does not create authority.
    func receive(_ packet: Packet, footAppearance: Bool, at now: Double) -> Immediate? {
        guard now.isFinite,(now*1000).isFinite else { return nil }
        if !footAppearance { return .init(event:packet.event) }
        var queue = pending[packet.shooter] ?? []
        queue.append(.init(packet:packet,receivedMilliseconds:now*1000))
        if queue.count > 6 { queue.removeFirst(queue.count-6) }
        pending[packet.shooter] = queue
        return nil
    }

    /// Call exactly once per current gun-animation firing marker. Merely
    /// receiving a packet must not advance that animation or consume a shot.
    func marker(shooter: String, weapon: Int, left: Bool, at now: Double,
                muzzle: V, heading: Double, pitch: Double, range: Double,
                along: NativeOrdinaryShot.Along?) -> Marker? {
        guard now.isFinite,(now*1000).isFinite, NativeOrdinaryShot.finite(muzzle), heading.isFinite,
              pitch.isFinite, range.isFinite, range >= 0 else { return nil }
        let direction = V(sin(heading)*cos(pitch),cos(heading)*cos(pitch),sin(pitch))
        var queue = pending[shooter] ?? []
        // Keep the original millisecond comparison. A seconds subtraction
        // such as1.6-1 is slightly greater than.6 and drops an exact600ms hit.
        while let first=queue.first,now*1000-first.receivedMilliseconds > 600 {queue.removeFirst()}
        let packet = queue.isEmpty ? nil : queue.removeFirst().packet
        pending[shooter] = queue.isEmpty ? nil : queue
        let event: NativeOrdinaryShot.Event
        if let packet {
            let origin = simd_distance(muzzle,packet.origin) < 3 ? muzzle : packet.origin
            event = .init(weapon:weapon,origin:origin,end:packet.end,impact:packet.kind,piece:packet.piece)
        } else {
            let distance = (along?(muzzle,direction,range)).flatMap { value -> Double? in
                value.isFinite && value >= 0 && value <= range ? value : nil
            }
            event = .init(weapon:weapon,origin:muzzle,end:muzzle+direction*(distance ?? range),
                          impact:distance == nil ? nil:.world)
        }
        return .init(event:event,muzzle:muzzle,direction:direction,left:left,
                     usedPacket:packet != nil,reportsWorldShot:packet?.reportsWorldShot ?? false)
    }
}
