import Foundation
import simd

/// Projectile and area behavior translated from the archived public client's
/// cY manager in 9737.c81ad6ccfd85b371.js. Coordinates here are GTA x/y/z,
/// with z up; the browser's x/y/z uses y up and negates GTA y.
/// Rendering, inventory and multiplayer damage validation belong to callers.
final class NativeWeaponEffects {
    struct Contact {
        let distance: Float
        let normal: SIMD3<Float>
        var targetID: String? = nil
    }
    struct Target {
        let id: String
        /// Pedestrian feet or vehicle centre, in GTA coordinates.
        let position: SIMD3<Float>
    }
    struct Projectile {
        let id: UInt64
        let weapon: Int
        let model: String
        let owner: String?
        var position: SIMD3<Float>
        var velocity: SIMD3<Float>
        var age: Float = 0
        let lifetime: Float
        let rocket: Bool
        let seeking: Bool
        let speed: Float
        var targetID: String?
        var stuck = false
        var lying = false
        var spin: Float
        var rotation: Float = 0
    }
    struct Detonation {
        let weapon: Int
        let position: SIMD3<Float>
        let owner: String?
        let radius: Float
        let maximumDamage: Float

        /// The public client uses a centre 0.9 m above pedestrian feet and
        /// linear radial falloff. Its private server may validate differently.
        func damage(atFeet feet: SIMD3<Float>) -> Float {
            let distance = simd_distance(position, feet + SIMD3(0, 0, 0.9))
            return radius > 0 && distance < radius ? maximumDamage * (1 - distance / radius) : 0
        }
    }
    struct Flame {
        let position: SIMD3<Float>
        var strength: Float
    }
    struct Fire {
        let id: UInt64
        let position: SIMD3<Float>
        let owner: String?
        var remaining: Float = 8
        var burst: Float = 3
        var flames: [Flame]
    }
    struct Stream {
        let weapon: Int
        let position: SIMD3<Float>
        let direction: SIMD3<Float>
        let range: Float
        let held: Float
        let lifetime: Float
        let speed: Float
        let radius: Float
        let spread: Float
    }

    /// Return the closest solid contact along a normalized ray. A native
    /// triangle raycast preserves bounce normals and rocket impact locations.
    var trace: ((SIMD3<Float>, SIMD3<Float>, Float) -> Contact?)?
    /// Used to place the six seeded molotov fires, matching the 4 m down ray.
    var groundHeight: ((Float, Float, Float) -> Float?)?
    var onDetonation: ((Detonation) -> Void)?
    // Original cY calls these before advancing projectile position, so a fast
    // rocket's smoke begins at its actual previous point on the trajectory.
    var onTrail:((SIMD3<Float>,Float,Bool)->Void)?
    var onGas:((SIMD3<Float>,Float)->Void)?
    var onFlames:((SIMD3<Float>,Float)->Void)?
    var onStreamHit: ((String, Int) -> Void)?
    var onDouse: ((SIMD3<Float>, Float) -> Void)?
    private(set) var projectiles: [Projectile] = []
    private(set) var fires: [Fire] = []
    private(set) var streams: [Stream] = []
    private var streamHeld: [Int: Float] = [:]
    private var streamTimers: [Int: Float] = [:]
    private var nextID: UInt64 = 1

    /// Reconcile to the Mac's authoritative snapshots, then simulate between
    /// updates with the same public-client equations used by the server.
    func synchronizeServer(_ rows: [[String: Any]]) {
        let prior = Dictionary(uniqueKeysWithValues: projectiles.map { ($0.id,$0) })
        projectiles = rows.prefix(256).compactMap { row in
            guard let text = row["id"] as? String,
                  let id = UInt64(text.split(separator: "-").last ?? ""),
                  let weapon = row["weapon"] as? Int, let model = Self.model(for: weapon),
                  let p = row["position"] as? [NSNumber], p.count == 3,
                  let v = row["velocity"] as? [NSNumber], v.count == 3 else { return nil }
            let velocity = SIMD3<Float>(v[0].floatValue,v[1].floatValue,v[2].floatValue)
            return Projectile(id: id, weapon: weapon, model: model, owner: row["owner"] as? String,
                position: SIMD3(p[0].floatValue,p[1].floatValue,p[2].floatValue), velocity: velocity,
                age: (row["age"] as? NSNumber)?.floatValue ?? 0,
                lifetime: (row["lifetime"] as? NSNumber)?.floatValue ?? 2,
                rocket: row["rocket"] as? Bool == true, seeking: weapon == 20 || weapon == 36,
                speed: simd_length(velocity), targetID: nil,
                stuck: row["stuck"] as? Bool == true, lying: row["lying"] as? Bool == true,
                spin: prior[id]?.spin ?? 8, rotation: prior[id]?.rotation ?? 0)
        }
    }

    static let gravity: Float = 18
    static let rocketSpeed: Float = 65
    static let rocketLifetime: Float = 5
    static let throwSpeed: Float = 17
    static let throwLift: Float = 4.5

    static func model(for weapon: Int) -> String? {
        switch weapon {
        case 16: return "grenade"
        case 17: return "teargas"
        case 18: return "molotov"
        case 39: return "satchel"
        case 19, 20, 35, 36: return "missile"
        default: return nil
        }
    }

    static func blast(weapon: Int, position: SIMD3<Float>, owner: String? = nil) -> Detonation {
        let radius: Float = weapon == 16 || weapon == 39 ? 9 : weapon == 18 ? 6 :
            [19, 20, 35, 36, 51].contains(weapon) ? 10 : 0
        let maximum: Float = radius == 0 ? 0 : weapon == 18 ? 16.5 : 82.5
        return Detonation(weapon: weapon, position: position, owner: owner,
                          radius: radius, maximumDamage: maximum)
    }

    @discardableResult
    func lob(weapon: Int, from origin: SIMD3<Float>, direction: SIMD3<Float>,
             owner: String? = nil) -> UInt64? {
        guard [16, 17, 18, 39].contains(weapon), let model = Self.model(for: weapon),
              let direction = Self.unit(direction), Self.valid(origin) else { return nil }
        var velocity = direction * Self.throwSpeed + SIMD3<Float>(0, 0, Self.throwLift)
        if weapon == 39 { velocity *= 0.6 }
        let lifetime: Float = weapon == 16 ? 2 : weapon == 17 ? 20 : weapon == 39 ? 120 : 6
        let id = allocateID()
        projectiles.append(Projectile(id: id, weapon: weapon, model: model, owner: owner,
            position: origin, velocity: velocity, lifetime: lifetime, rocket: false,
            seeking: false, speed: simd_length(velocity), spin: Float.random(in: 6...12)))
        return id
    }

    @discardableResult
    func launch(weapon: Int, from origin: SIMD3<Float>, direction: SIMD3<Float>,
                carry: SIMD3<Float> = .zero, targetID: String? = nil,
                owner: String? = nil) -> UInt64? {
        guard [19, 20, 35, 36].contains(weapon), let model = Self.model(for: weapon),
              let direction = Self.unit(direction), Self.valid(origin), Self.valid(carry) else { return nil }
        let velocity = direction * Self.rocketSpeed + carry
        let id = allocateID()
        projectiles.append(Projectile(id: id, weapon: weapon, model: model, owner: owner,
            position: origin, velocity: velocity, lifetime: Self.rocketLifetime, rocket: true,
            seeking: weapon == 20 || weapon == 36, speed: simd_length(velocity),
            targetID: targetID, spin: 0))
        return id
    }

    /// Call each frame while the trigger is held. As in the public client,
    /// hit checks occur immediately on a new stream then every 0.3 seconds.
    /// The caller maps the returned hit to its server's damage request.
    func stream(weapon: Int, from origin: SIMD3<Float>, direction: SIMD3<Float>,
                delta: Float, people: [Target] = []) {
        guard [37, 41, 42].contains(weapon), let direction = Self.unit(direction),
              Self.valid(origin), delta.isFinite, delta > 0 else { return }
        let range: Float = weapon == 37 ? 5.1 : weapon == 41 ? 6.1 : 10.1
        let held = (streamHeld[weapon] ?? 0) + delta
        streamHeld[weapon] = held
        let value = Stream(weapon: weapon, position: origin, direction: direction,
            range: range, held: held, lifetime: 1,
            speed: weapon == 37 ? 0.5 : weapon == 41 ? 0.05 : 0.1,
            radius: weapon == 37 ? 0.0075 : 0.5, spread: weapon == 37 ? 2 : 0.01)
        streams.removeAll { $0.weapon == weapon }
        streams.append(value)
        var elapsed = (streamTimers[weapon] ?? 0.3) + delta
        if elapsed >= 0.3 {
            elapsed = 0
            for target in people {
                let offset = target.position + SIMD3(0, 0, 0.9) - origin
                let along = simd_dot(offset, direction)
                guard along >= 0, along <= range,
                      simd_length(offset - direction * along) <= 0.8,
                      trace?(origin, direction, along) == nil else { continue }
                onStreamHit?(target.id, weapon)
            }
        }
        streamTimers[weapon] = elapsed
        if weapon == 42 {
            extinguish(origin: origin, direction: direction, range: range, delta: delta)
            onDouse?(origin, delta)
        }
    }

    func endStream(weapon: Int? = nil) {
        if let weapon {
            streamHeld.removeValue(forKey: weapon)
            streamTimers.removeValue(forKey: weapon)
            streams.removeAll { $0.weapon == weapon }
        } else {
            streamHeld.removeAll(); streamTimers.removeAll(); streams.removeAll()
        }
    }

    @discardableResult
    func detonateSatchels(owner: String? = nil) -> Bool {
        let planted = projectiles.filter { $0.weapon == 39 && $0.owner == owner }
        for projectile in planted { detonate(projectile) }
        projectiles.removeAll { $0.weapon == 39 && $0.owner == owner }
        return !planted.isEmpty
    }

    func update(delta: Float, people: [Target] = [], vehicles: [Target] = []) {
        guard delta.isFinite, delta > 0 else { return }
        for index in fires.indices {
            fires[index].remaining -= delta
            fires[index].burst -= delta
        }
        fires.removeAll { $0.remaining <= 0 || !$0.flames.contains(where: { $0.strength > 0 }) }
        for fire in fires {for flame in fire.flames where flame.strength>0{onFlames?(flame.position,delta*min(1,fire.remaining))}}
        var retained: [Projectile] = []
        for var projectile in projectiles {
            projectile.age += delta
            if projectile.age >= projectile.lifetime {
                if projectile.weapon != 17 && projectile.weapon != 39 { detonate(projectile) }
                continue
            }
            if projectile.weapon==17 && projectile.lying{onGas?(projectile.position,delta)}
            if projectile.stuck || projectile.lying { retained.append(projectile); continue }
            if projectile.rocket {
                if projectile.seeking { steer(&projectile, vehicles: vehicles, delta: delta) }
                onTrail?(projectile.position,delta,false)
            } else {
                projectile.velocity.z -= Self.gravity * delta
                projectile.rotation += projectile.spin * delta
                if projectile.weapon==18{onTrail?(projectile.position,delta,true)}
            }
            let speed = simd_length(projectile.velocity)
            guard speed >= 0.0001 else { retained.append(projectile); continue }
            let way = projectile.velocity / speed, distance = speed * delta
            var contact = trace?(projectile.position, way, distance + 0.05)
            if projectile.rocket || projectile.weapon == 18 {
                let radius: Float = projectile.rocket ? 0.96 : 0.5
                for person in people where person.id != projectile.owner {
                    let offset = person.position + SIMD3(0, 0, 0.9) - projectile.position
                    let along = max(0, min(distance, simd_dot(offset, way)))
                    if simd_length(way * along - offset) < radius &&
                        along < (contact?.distance ?? .infinity) {
                        contact = Contact(distance: along, normal: -way, targetID: person.id)
                    }
                }
            }
            if let contact {
                let backoff: Float = projectile.rocket ? 0.1 : 0.05
                projectile.position += way * max(0, contact.distance - backoff)
                if projectile.rocket || projectile.weapon == 18 { detonate(projectile); continue }
                if projectile.weapon == 39 { projectile.stuck = true; retained.append(projectile); continue }
                if let normal = Self.unit(contact.normal) {
                    projectile.velocity = (projectile.velocity - normal * (2 * simd_dot(projectile.velocity, normal))) * 0.35
                    projectile.spin *= 0.5
                    if simd_length(projectile.velocity) < 1.2 && normal.z > 0.6 && contact.targetID == nil {
                        projectile.lying = true; projectile.velocity = .zero
                    }
                } else { projectile.velocity = .zero }
            } else { projectile.position += way * distance }
            retained.append(projectile)
        }
        projectiles = retained
    }

    /// Tear gas uses the public client's rectangular volume while a settled
    /// canister is active. It expires without an explosion at20seconds.
    func gassed(atFeet feet: SIMD3<Float>) -> Bool {
        projectiles.contains { value in
            value.weapon == 17 && value.lying &&
                abs(value.position.x - feet.x) < 6 && abs(value.position.y - feet.y) < 6 &&
                abs(value.position.z - feet.z) < 5
        }
    }

    func burning(atFeet feet: SIMD3<Float>) -> Bool {
        let centre = feet + SIMD3<Float>(0, 0, 1)
        return fires.contains { fire in
            let extent: Float = fire.owner == nil ? 3 : 6
            if fire.burst > 0 && abs(fire.position.x - feet.x) < extent &&
                abs(fire.position.y - feet.y) < extent && abs(fire.position.z - centre.z) < 5 { return true }
            return fire.flames.contains { $0.strength > 0 && simd_distance($0.position, centre) < sqrt(1.2) }
        }
    }

    func clear() {
        projectiles.removeAll(); fires.removeAll(); endStream()
    }

    private func allocateID() -> UInt64 { defer { nextID &+= 1 }; return nextID }

    /// Public cY.blast receives the authoritative echo separately from local
    /// projectile prediction. Remote molotovs therefore seed the same fire
    /// even when a newer snapshot already removed their projectile.
    func receiveBlast(weapon:Int,position:SIMD3<Float>,owner:String?=nil) {
        if weapon==18{ignite(at:position,owner:owner)}
    }

    private func detonate(_ projectile: Projectile) {
        func rounded(_ value: Float) -> Float { floor(value * 100 + 0.5) / 100 }
        let at = SIMD3<Float>(rounded(projectile.position.x), rounded(projectile.position.y),
                              rounded(projectile.position.z))
        let event = Self.blast(weapon: projectile.weapon, position: at, owner: projectile.owner)
        onDetonation?(event)
    }

    private func steer(_ projectile: inout Projectile, vehicles: [Target], delta: Float) {
        var target = vehicles.first { $0.id == projectile.targetID }
        var nearest: Float = 150
        if target == nil {
            for candidate in vehicles {
                let offset = candidate.position - projectile.position, distance = simd_length(offset)
                if distance > 0.0001 && distance < nearest &&
                    simd_dot(offset, projectile.velocity) / (distance * projectile.speed) > 0.75 {
                    target = candidate; nearest = distance
                }
            }
        }
        guard let target, let desired = Self.unit(target.position - projectile.position),
              let current = Self.unit(projectile.velocity) else { return }
        let angle = acos(max(-1, min(1, simd_dot(current, desired))))
        let amount = min(1, 1.6 * delta / max(angle, 0.0001))
        if let result = Self.unit(current * (1 - amount) + desired * amount) {
            projectile.velocity = result * projectile.speed
        }
    }

    private func ignite(at point: SIMD3<Float>, owner: String?) {
        // The browser seeds six flames from rounded x/(-GTA y), making the
        // same molotov visible in the same places for every client.
        let x = Int64(floor(Double(point.x) * 100 + 0.5))
        let y = Int64(floor(Double(-point.y) * 100 + 0.5))
        var seed = UInt32(truncatingIfNeeded: 0x466f45d * x) ^ UInt32(truncatingIfNeeded: 0x127409f * y)
        func random() -> Float {
            seed &+= 0x6d2b79f5
            var value = (seed ^ (seed >> 15)) &* (1 | seed)
            value = (value &+ ((value ^ (value >> 7)) &* (61 | value))) ^ value
            return Float(Double(value ^ (value >> 14)) / 4294967296)
        }
        var flames: [Flame] = []
        for index in 0..<6 {
            let angle = Float(index) / 6 * .pi * 2 + random()
            let radius = index == 0 ? 0 : 2.6 * (0.35 + 0.65 * random())
            let x = point.x + cos(angle) * radius, y = point.y - sin(angle) * radius
            if let height = groundHeight?(x, y, point.z + 1.2),
               height <= point.z + 1.2 && height >= point.z - 2.8 {
                flames.append(Flame(position: SIMD3(x, y, height), strength: 1))
            }
        }
        if flames.isEmpty { flames = [Flame(position: point, strength: 1)] }
        fires.append(Fire(id: allocateID(), position: point, owner: owner, flames: flames))
    }

    private func extinguish(origin: SIMD3<Float>, direction: SIMD3<Float>, range: Float, delta: Float) {
        for fire in fires.indices { for flame in fires[fire].flames.indices {
            let offset = fires[fire].flames[flame].position - origin
            let along = simd_dot(offset, direction)
            if along >= 0 && along <= range && simd_length(offset - direction * along) <= 1 {
                fires[fire].flames[flame].strength -= 2 * delta
            }
        } }
    }

    private static func valid(_ vector: SIMD3<Float>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }
    private static func unit(_ vector: SIMD3<Float>) -> SIMD3<Float>? {
        let length = simd_length(vector)
        return valid(vector) && length > 0.0001 ? vector / length : nil
    }
}
