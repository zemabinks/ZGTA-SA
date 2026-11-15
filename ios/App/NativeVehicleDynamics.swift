import Foundation
import simd

/// Translation of the public browser's module 23895 ground-vehicle solver.
/// Coordinates and velocities here use its Rapier Y-up convention; conversion
/// to the renderer's GTA Z-up convention belongs at the integration boundary.
/// Rapier supplies body integration, collision response and wheel ray queries.
final class NativeVehicleDynamics {
    typealias Vector = SIMD3<Double>
    struct Table {
        var model: Int
        var maxVelocity = 160.0, acceleration = 20.0, brakes = 7.0, lock = 30.0, traction = 0.75
        var drive = "R"
        var mass = 1500.0, turnMass = 3750.0, drag = 2.0
        var comX = 0.0, comY = 0.0, comZ = 0.0
        var loss = 0.8, bias = 0.5, brakeBias = 0.55, springs = 1.2, damping = 0.1
        var upper = 0.25, lower = -0.15, gears = 5.0, inertia = 10.0, suspBias = 0.5, antiDive = 0.3
        var flags = 0, modelFlags = 0
        var ratio = 1.0, pulls = 0.0, spool = 0.0
        var submerged = 100.0
        var abs = false

        init(model: Int, values: [String: Any]) {
            self.model = model
            func number(_ name: String, _ fallback: Double) -> Double {
                (values[name] as? NSNumber)?.doubleValue ?? fallback
            }
            maxVelocity = number("maxVelocity", maxVelocity); acceleration = number("acceleration", acceleration)
            brakes = number("brakes", brakes); lock = number("lock", lock); traction = number("traction", traction)
            drive = values["drive"] as? String ?? drive
            mass = number("mass", mass); turnMass = number("turnMass", mass * 2.5); drag = number("drag", drag)
            comX = number("comX", comX); comY = number("comY", comY); comZ = number("comZ", comZ)
            loss = number("loss", loss); bias = number("bias", bias); brakeBias = number("brakeBias", brakeBias)
            springs = number("springs", springs); damping = number("damping", damping)
            upper = number("upper", upper); lower = number("lower", lower); gears = number("gears", gears)
            inertia = number("inertia", inertia); suspBias = number("suspBias", suspBias); antiDive = number("antiDive", antiDive)
            flags = Int(number("flags", 0)); modelFlags = Int(number("modelFlags", 0))
            ratio = number("ratio", ratio); pulls = number("pulls", pulls); spool = number("spool", spool)
            submerged = number("submerged", submerged)
            abs = values["abs"] as? Bool ?? false
        }

        init(model: Int, row: [Any]) {
            let names = ["maxVelocity", "acceleration", "brakes", "lock", "traction", "drive",
                         "mass", "turnMass", "drag", "comX", "comY", "comZ", "loss", "bias",
                         "brakeBias", "springs", "damping", "upper", "lower", "gears", "inertia",
                         "suspBias", "antiDive", "flags"]
            var values: [String: Any] = [:]
            for (index, name) in names.enumerated() where index < row.count { values[name] = row[index] }
            if row.count > 28 { values["modelFlags"] = row[28] }
            self.init(model: model, values: values)
        }
    }
    struct WheelSpecification {
        let centre: Vector
        let radius: Double
        let front: Bool
        let left: Bool
    }
    struct Configuration {
        let table: Table
        let origin: Double
        let wheels: [WheelSpecification]
        var kind = "car"
        var hydraulics = false
        var nitro = false
    }
    struct BodyState {
        var position: Vector
        var rotation: simd_quatd
        var linearVelocity: Vector
        var angularVelocity: Vector
    }
    struct RayHit {
        let distance: Double
        let normal: Vector
        var surface = 2
        var material = -1
    }
    struct Input {
        struct Drive {var throttle=0.0,steer=0.0;var handbrake=false;var accelerate:Double?,brake:Double?;var pedals:SIMD2<Double>?}
        var throttle = 0.0, steer = 0.0, lean = 0.0
        var handbrake = false, abandoned = false, pad = false
        var riderless = false, hop = false
        var accelerate: Double? = nil, brake: Double? = nil
        var pedals: SIMD2<Double>? = nil
        var suspensionOffsets: [Double] = []
        var wetness = 0.0
        var pitch = 0.0, roll = 0.0, yaw = 0.0, jets = 0.0
        var nobody = false
        var drive:Drive?
    }
    struct TransmissionSnapshot {
        struct Gear {let max:Double,up:Double,down:Double}
        let gears:[Gear];let count:Int;let max:Double,reverse:Double
    }
    struct HeardSnapshot {
        let box:TransmissionSnapshot;let gear:Int;let accel:Double,brake:Double;let handbrake:Bool
        let grounded:Double,spin:Double,climb:Double;let bike:Bool;let lean:Double
    }
    struct WheelSnapshot {
        let index: Int
        let compression: Double
        let offset: Double
        let counts: Double
        let state: Int
        let spin: Double
        let point: Vector
        let normal: Vector
        var tyre=0
        var surface=2
    }
    struct Output {
        let linearVelocity: Vector
        let angularVelocity: Vector
        let steering: Double
        let rearSteering: Double
        let gear: Int
        let gas: Double
        let brake: Double
        let burnout: Bool
        let wheelSpeed: Double
        let wheels: [WheelSnapshot]
    }
    private struct Gear { var max = 0.0, up = 0.0, down = 0.0 }
    private struct Gearbox {
        var accel: Double, brake: Double, max: Double, flat: Double, reverse: Double
        var gears: [Gear], count: Int, inertia: Double, flags: Int, pulls: Double, spool: Double
        init(_ table: Table) {
            let limited = 0x1000000
            var acceleration = 0.4 * table.acceleration * 0.0004
            var speed = 0.00555556 * table.maxVelocity
            let threshold = acceleration / 6
            var candidate = speed
            while candidate > 0 {
                candidate -= 0.01
                if table.drag >= 0.01 {
                    if candidate * candidate * (table.drag / 2) / 1000 <= threshold { break }
                } else if -((1 / (candidate * candidate * table.drag + 1) - 1) * candidate) <= threshold { break }
            }
            let flat: Double, reverse: Double
            if table.model == 441 { flat = candidate; reverse = -candidate }
            else if table.flags & limited != 0 { flat = candidate / 1.2; reverse = Swift.min(-flat / 4, -0.2) }
            else {
                speed = 1.2 * candidate; flat = candidate
                reverse = Set([448,461,462,463,468,481,509,510,521,522,523,581,586]).contains(table.model) ? -0.05 : Swift.min(-0.3 * candidate, -0.2)
            }
            acceleration /= table.drive == "4" ? 4 : 2
            let count = Swift.max(1, Int(floor(table.gears + 0.5)))
            var gears = Array(repeating: Gear(), count: count + 1)
            let half = 0.5 * speed / Double(count), span = speed - half
            for index in 1...count {
                gears[index].max = Double(index) * span / Double(count) + half
                let difference = gears[index].max - gears[index - 1].max
                if index >= count { gears[index].up = speed }
                else {
                    gears[index + 1].down = 0.42 * difference + gears[index - 1].max
                    gears[index].up = 0.6667 * difference + gears[index - 1].max
                }
            }
            gears[0] = Gear(max: reverse, up: -0.01, down: reverse)
            gears[1].down = -0.01
            if table.ratio != 1 && count > 1 {
                speed = Swift.max(1.02 * gears[count - 1].max, speed * table.ratio)
                gears[count].max = speed; gears[count].up = speed
            }
            self.accel = acceleration; self.brake = 0.0004 * table.brakes
            self.max = speed; self.flat = flat; self.reverse = reverse; self.gears = gears
            self.count = count; self.inertia = table.inertia; self.flags = table.flags
            self.pulls = table.pulls; self.spool = table.spool
        }
    }
    private struct Transmission {
        var gear = 1, ratio = 0.0, smooth = 0.0
        var changing = 0.0, since: Double? = nil, spooled = 0.0
        var manual = false, chosen = 1
    }
    private final class Wheel {
        let index: Int, front: Bool, left: Bool
        let radius: Double, spring: Double, length: Double, start: Vector
        var compression = 1.0, counts = 0.0, state = 0, offset: Double
        var point = Vector.zero, normal = Vector(0,1,0)
        var surface = 2, material = -1, tyre = 0
        var spin = 0.0, road = 0.0
        init(index: Int, specification: WheelSpecification, table: Table) {
            self.index = index; front = specification.front; left = specification.left
            radius = specification.radius; spring = table.upper - table.lower
            length = spring + radius; start = specification.centre + Vector(0,table.upper,0)
            offset = table.lower
        }
    }
    private let configuration: Configuration
    private let table: Table
    private let gearbox: Gearbox
    var flight: NativeFlightDynamics?
    var buoyancy: NativeVehicleBuoyancy?
    private var transmission = Transmission()
    private let wheels: [Wheel]
    let mass: Double
    let turnMass: Double
    let centre: Vector
    private let flags: Int
    private var steeringInput = 0.0, steering = 0.0, rearSteering = 0.0, gas = 0.0, braking = 0.0
    private var burnout = false, simultaneous = 0.0, engineReserve = 1.0, soundSpin = 0.0
    private var heardAccel=0.0,heardBrake=0.0,heardGrounded=0.0,heardClimb=0.0
    private var heardHandbrake=false
    var transmissionSnapshot:TransmissionSnapshot {.init(gears:gearbox.gears.map{.init(max:$0.max,up:$0.up,down:$0.down)},count:gearbox.count,max:gearbox.max,reverse:gearbox.reverse)}
    static func transmissionSnapshot(table:Table)->TransmissionSnapshot {
        let box=Gearbox(table);return .init(gears:box.gears.map{.init(max:$0.max,up:$0.up,down:$0.down)},count:box.count,max:box.max,reverse:box.reverse)
    }
    var heard:HeardSnapshot {.init(box:transmissionSnapshot,gear:transmission.gear,accel:heardAccel,brake:heardBrake,handbrake:heardHandbrake,
        grounded:heardGrounded,spin:soundSpin,climb:heardClimb,bike:false,lean:0)}
    var fun = 0
    var nitroBurning:Bool {engineReserve<0}
    var manual: Bool {
        get { transmission.manual }
        set {
            if transmission.manual != newValue {
                transmission.manual = newValue; transmission.chosen = max(1, transmission.gear)
            }
        }
    }
    private var move = Vector.zero, turn = Vector.zero, bodyCentre = Vector.zero
    private var forward = Vector(0,0,-1), right = Vector(1,0,0), up = Vector(0,1,0)
    private var stepSize = 1.0, abandoned = false, slipping = false
    private var contactPoints = Array(repeating: Vector.zero, count: 4)
    private var contactSpeeds = Array(repeating: Vector.zero, count: 4)
    private var random: () -> Double

    init?(configuration: Configuration, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        guard ["car", "trailer", "boat", "plane", "heli"].contains(configuration.kind), configuration.table.mass > 0,
              configuration.table.turnMass > 0, configuration.wheels.isEmpty || configuration.table.upper > configuration.table.lower,
              configuration.table.inertia > 0, configuration.table.lock > 0 else { return nil }
        self.configuration = configuration; table = configuration.table
        gearbox = Gearbox(configuration.table)
        mass = table.mass; turnMass = table.turnMass * (configuration.kind == "boat" ? 0.5 : 1)
        centre = Vector(table.comX, configuration.origin + table.comZ, -table.comY)
        flags = table.flags | (configuration.hydraulics ? 131072 : 0)
        self.random = random
        var made: [Wheel] = []
        for (index, pair) in [(true,true),(false,true),(true,false),(false,false)].enumerated() {
            let options = configuration.wheels.filter { $0.front == pair.0 && $0.left == pair.1 }
            guard let selected = options.min(by: { pair.0 ? $0.centre.z < $1.centre.z : $0.centre.z > $1.centre.z }) else { continue }
            made.append(Wheel(index: index, specification: selected, table: configuration.table))
        }
        wheels = made
    }

    func setTyres(_ states: [Int]) {
        for wheel in wheels { wheel.tyre = states.indices.contains(wheel.index) ? states[wheel.index] : 0 }
    }
    func fireNitro() { if engineReserve >= 1 { engineReserve = -0.000001 } }
    @discardableResult func shift(_ direction: Int) -> String {
        if transmission.gear == 0 { return "reverse" }
        let chosen = max(1, min(gearbox.count, transmission.chosen)) + (direction < 0 ? -1 : direction > 0 ? 1 : 0)
        if chosen < 1 { return "bottom" }; if chosen > gearbox.count { return "top" }
        transmission.chosen = chosen
        return direction > 0 ? "up" : "down"
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double { min(high, max(low, value)) }
    private static func normalized(_ value: Vector) -> Vector {
        let length = simd_length(value); return length > 0 ? value / length : value
    }
    private func speed(at point: Vector) -> Vector { move - simd_cross(point - bodyCentre, turn) }
    private func pushTurn(_ force: Vector, at point: Vector) { turn += simd_cross(point - bodyCentre, force) / turnMass }
    private func push(_ force: Vector, at point: Vector) { move += force / mass; pushTurn(force, at: point) }
    private func effectiveMass(_ arm: Vector, _ direction: Vector) -> Double {
        1 / (simd_length_squared(simd_cross(arm, direction)) / turnMass + 1 / mass)
    }

    var transmissionGear: Int { transmission.gear }
    var transmissionMaximum: Double { gearbox.gears[transmission.gear].max }
    var transmissionBrake: Double { gearbox.brake }
    /// The motorcycle module invokes the same original gearbox with smoothing
    /// disabled; keeping that parameter explicit preserves both callers.
    func stepTransmission(delta: Double, throttle: Double, speed: Double, contacts: Int,
                          nitro: Bool = false, smoothing: Bool = true) -> Double {
        stepSize = 50 * delta
        return engineForce(throttle: throttle, speed: speed, contacts: contacts, nitro: nitro, smoothing: smoothing)
    }
    func boostForce(throttle: Double, contacts: Int, delta: Double) -> Double {
        9 * 2 * gearbox.accel * 0.4 * throttle * (50 * delta) * Double(contacts)
    }
    private func engineForce(throttle: Double, speed: Double, contacts: Int, nitro: Bool, smoothing: Bool = true) -> Double {
        if speed < gearbox.reverse { return 0 }
        var allowed = smoothing && transmission.changing <= 0.001
        var contactCount = contacts
        if transmission.changing > 0.001 { transmission.changing -= stepSize }
        if transmission.manual && gearbox.count > 1 {
            let reverse = throttle < 0 || speed < -0.01 && throttle <= 0
            if reverse { transmission.chosen = 1 }
            transmission.chosen = max(1, min(gearbox.count, transmission.chosen))
            let selected = reverse ? 0 : transmission.chosen
            if transmission.gear != selected {
                transmission.gear = selected
                if allowed { transmission.changing = 1 - stepSize }
                transmission.since = 1; allowed = false; contactCount = 0
            }
            let gear = gearbox.gears[transmission.gear]
            var force = gearForce(gear, throttle: throttle, speed: speed, contacts: contactCount, nitro: nitro, allowed: allowed)
            if transmission.gear >= 2 && speed < gear.down { force *= max(0.3, speed / gear.down) }
            return force
        }
        while speed <= gearbox.max {
            let gear = gearbox.gears[transmission.gear]
            var resolved = false, down = false
            if speed > gear.up {
                if transmission.gear == 0 && throttle <= 0 { resolved = true }
                else if transmission.gear < gearbox.count { transmission.gear += 1 }
                else { break }
            } else {
                if speed >= gear.down || transmission.gear == 0 || transmission.gear == 1 && throttle >= 0 { resolved = true }
                down = true
            }
            if resolved { return gearForce(gear, throttle: throttle, speed: speed, contacts: contactCount, nitro: nitro, allowed: allowed) }
            if down { transmission.gear -= 1 }
            if allowed { transmission.changing = 1 - stepSize }
            transmission.since = 1; allowed = false; contactCount = 0
            if speed < gearbox.reverse { break }
        }
        return 0
    }

    private func gearForce(_ gear: Gear, throttle: Double, speed: Double, contacts: Int, nitro: Bool, allowed: Bool) -> Double {
        var multiplier: Double
        if gearbox.count == 1 { multiplier = 1 }
        else if transmission.gear >= 1 {
            let fraction = Double(transmission.gear - 1) / Double(gearbox.count - 1)
            multiplier = pow(1 - fraction, 2) * (gearbox.flags & 1 != 0 ? 5 : gearbox.flags & 2 != 0 ? 4 : 3) + 1
            if gearbox.pulls != 0 { multiplier *= 1 + gearbox.pulls * (2 * fraction - 1) }
        } else { multiplier = 4.5 }
        var force = multiplier * gearbox.accel * (nitro ? 2 : 1) * 0.4 * throttle * stepSize
        if gearbox.spool != 0 {
            transmission.spooled = Self.clamp(transmission.spooled + stepSize * (throttle > 0.5 ? 1 : -4) / (50 * gearbox.spool), 0, 1)
            force *= 0.5 + 0.5 * transmission.spooled
        }
        if allowed {
            if contacts != 0 {
                let portion = gearbox.max / Double(gearbox.count) / 3
                let numerator: Double, denominator: Double
                if transmission.gear == 0 { numerator = portion - speed; denominator = portion - gearbox.gears[0].down }
                else if transmission.gear == 1 { numerator = portion + speed; denominator = portion + gearbox.gears[1].up }
                else { numerator = speed - gear.down; denominator = gear.up - gear.down }
                let ratio = numerator / denominator
                if transmission.since == nil { transmission.since = 1 }
                if transmission.since! > 0.999 {
                    let since = transmission.since!, decay = pow(0.85, since)
                    let smooth = Self.clamp(1 - (ratio - transmission.ratio) / since * (nitro ? 0.5 : 1) * gearbox.inertia, 0.1, 1)
                    transmission.ratio = ratio
                    transmission.smooth = smooth * (1 - decay) + decay * transmission.smooth
                    transmission.since = 0
                }
                transmission.since! += stepSize
                force *= transmission.smooth
            } else {
                transmission.ratio = min(1, transmission.ratio + abs(throttle) / gearbox.inertia * stepSize * 0.1)
                transmission.smooth = 0.1; transmission.since = 1
            }
        }
        let excess: Double
        if gear.max >= 0 || speed >= gear.max {
            if gear.max <= 0 || speed <= gear.max { return force }
            excess = speed - gear.max
        } else { excess = gear.max - speed }
        return force * (1 - min(excess / 0.05, 1))
    }

    static let surfaceTraction = [6.0, 3.6, 4.5, 3.2, 3.0, 2.8]
    private static let wetRoad: Set<Int> = [0,1,4,7,24,25,34,42,43,61,66,69,70,71,72,158,159,160]
    private static let wetMud: Set<Int> = [9,10,11,12,13,14,15,16,18,19,20,23,45,50,51,52,53,54,55,56,57,58,59,60,62,63,64,67,68,145,146,147,148,149,150,151,152,153]
    private static let wetSand: Set<Int> = [28,29,30,31,32,33]
    static func wetCoefficient(material: Int, surface: Int) -> Double {
        if material >= 0 {
            if wetRoad.contains(material) { return -0.25 }
            if wetMud.contains(material) { return -0.4 }
            if wetSand.contains(material) { return 0.5 }
            return material == 17 ? 0.4 : 0
        }
        return surface == 4 ? 0.5 : surface == 3 ? -0.4 : -0.25
    }

    // Module 23895 eE: combined longitudinal/lateral tyre impulse, including
    // brake lock, powered-wheel spin, traction loss, ABS and anti-dive torque.
    private func applyTyre(forward tangent: Vector, right lateral: Vector, velocity: Vector,
                           point: Vector, grounded: Int, driveForce: Double,
                           brakeForce: Double, traction: Double, wheel: Wheel, abs: Bool) {
        var side = 0.0, longitudinal = 0.0, limit = traction * stepSize
        let along = simd_dot(tangent, velocity), across = simd_dot(lateral, velocity)
        let brakes = brakeForce != 0, powered = !brakes && driveForce != 0
        if wheel.state != 0 {
            slipping = true; limit *= table.loss
            if wheel.state == 1 { limit *= 1 - 0.2 * Swift.abs(gas) }
        }
        wheel.state = 0
        if across != 0 {
            side = -across / Double(grounded)
            if wheel.tyre == 1 { side += min(along, 0.3) * (2 * random() - 1) * 0.13 }
        }
        if powered { longitudinal = driveForce; side = Self.clamp(side, -limit, limit) }
        else if along != 0 {
            longitudinal = -along / Double(grounded)
            var brakingLimit = brakeForce
            if !brakes && Swift.abs(gas) < 0.01 {
                brakingLimit = configuration.kind == "plane" ? 0 : 0.9 / mass * stepSize / (abandoned ? 50.0 / 30 : 1)
                if mass < 500 { brakingLimit *= 0.1 }
                else if table.model == 441 { brakingLimit *= 0.2 }
            }
            if brakingLimit > limit {
                if abs && brakes {
                    let maximum = 0.995 * sqrt(max(0, limit * limit - side * side))
                    longitudinal = Self.clamp(longitudinal, -maximum, maximum)
                } else if Swift.abs(along) > 0.005 { wheel.state = 3 }
            } else { longitudinal = Self.clamp(longitudinal, -brakingLimit, brakingLimit) }
        }
        let magnitudeSquared = side * side + longitudinal * longitudinal
        if magnitudeSquared > limit * limit {
            if wheel.state != 3 {
                var spinThreshold = 0.3
                if along > 0.15 && wheel.front { spinThreshold += spinThreshold }
                wheel.state = powered && spinThreshold * limit < Swift.abs(longitudinal) ? 1 : 2
            }
            var loss = table.loss
            if slipping { loss = 1 }
            else if wheel.state == 1 { loss *= 1 - 0.2 * Swift.abs(gas) }
            let magnitude = sqrt(magnitudeSquared)
            longitudinal *= limit * loss / magnitude; side *= limit * loss / magnitude
        }
        if longitudinal == 0 && side == 0 { return }
        let force = tangent * longitudinal + lateral * side
        var torqueForce = force
        var antiDive = false
        if table.antiDive > 0 {
            if brakes { antiDive = true; torqueForce -= tangent * (table.antiDive * longitudinal) }
            else if powered { antiDive = true; torqueForce -= tangent * (0.5 * table.antiDive * longitudinal) }
        }
        let magnitude = simd_length(force), torqueMagnitude = antiDive ? simd_length(torqueForce) : magnitude
        let direction = Self.normalized(force)
        let torqueDirection = antiDive ? Self.normalized(torqueForce) : direction
        move += direction * magnitude
        pushTurn(torqueDirection * (torqueMagnitude * effectiveMass(point, torqueDirection)), at: point)
    }

    private func applyAxle(front: Bool, angle: Double?, traction: Double, driveForce: Double,
                           brakeForce: Double, handbrake: Bool, grounded: Int, wetness: Double) {
        let axle = wheels.filter { $0.front == front }
        let driven = table.drive == "4" || table.drive == (front ? "F" : "R")
        var suspensionShare = 2 * table.suspBias
        var limit = traction, braking = brakeForce, abs = table.abs
        if !front {
            suspensionShare = 2 - suspensionShare
            if !handbrake || flags & 64 != 0 {
                if driven && burnout {
                    braking = 0; limit = 0
                    if let wheel = axle.first(where: { $0.left }) ?? axle.first {
                        pushTurn(contactPoints[wheel.index] * stepSize,
                            at: right * (-0.002 * min(1, 3000 / turnMass) * turnMass * steering))
                    }
                } else if !configuration.nitro && (table.drive == "R" || table.drive == "4") { limit *= engineReserve }
            } else { braking = 20_000; abs = false }
        }
        func updateBurnoutReserve() {
            if !front && !configuration.nitro {
                if burnout && driven && axle.contains(where: { $0.state == 1 }) { engineReserve = min(3, engineReserve + stepSize / 1000) }
                else if engineReserve > 1 { engineReserve = pow(0.995, stepSize) * (engineReserve - 1) + 1 }
            }
        }
        guard axle.contains(where: { $0.counts > 0 }) else { updateBurnoutReserve(); return }
        let brakeShare = front ? 2 * table.brakeBias : 2 - 2 * table.brakeBias
        let gripShare = front ? 2 * table.bias : 2 - 2 * table.bias
        let sine = sin(angle ?? 0), cosine = cos(angle ?? 0)
        for wheel in axle where wheel.counts > 0 {
            var along = Self.normalized(forward - wheel.normal * simd_dot(forward, wheel.normal))
            var across = Self.normalized(simd_cross(along, wheel.normal))
            if angle != nil {
                let rotated = along * cosine - across * sine
                across = across * cosine + along * sine; along = rotated
            }
            let surface = Self.surfaceTraction.indices.contains(wheel.surface) ? wheel.surface : 2
            var wheelGrip = Self.surfaceTraction[surface] * limit
            let weatherGrip = wetness > 0 ? 1 + Self.wetCoefficient(material: wheel.material, surface: wheel.surface) * wetness : 1
            wheelGrip *= weatherGrip * min(suspensionShare * table.springs * 4 * (1 - wheel.compression), 2)
            if flags & 2097152 != 0 && wheel.surface > 2 { wheelGrip *= 1.4 }
            else if flags & 1048576 != 0 && wheel.surface > 2 { wheelGrip *= 1.15 }
            if wheel.tyre == 1 { wheelGrip *= 0.5 }
            applyTyre(forward: along, right: across, velocity: contactSpeeds[wheel.index],
                point: contactPoints[wheel.index], grounded: grounded, driveForce: driven ? driveForce : 0,
                brakeForce: braking * brakeShare, traction: wheelGrip * gripShare, wheel: wheel, abs: abs)
            if driven && gas < 0 && wheel.state == 1 { wheel.state = 0 }
        }
        updateBurnoutReserve()
    }

    func step(delta: Double, input originalInput: Input, body: BodyState,
              raycast: (Vector, Vector, Double) -> RayHit?) -> Output {
        var input=originalInput
        if let drive=originalInput.drive {
            input.throttle=drive.throttle;input.steer=drive.steer;input.handbrake=drive.handbrake
            input.accelerate=drive.accelerate;input.brake=drive.brake;input.pedals=drive.pedals
        }
        stepSize = 50 * delta
        let orientation = body.rotation
        right = orientation.act(Vector(1,0,0)); up = orientation.act(Vector(0,1,0))
        forward = orientation.act(Vector(0,0,-1))
        let place = body.position + up * configuration.origin
        bodyCentre = orientation.act(centre - Vector(0,configuration.origin,0))
        move = body.linearVelocity / 50; turn = body.angularVelocity / 50
        for wheel in wheels {
            let offset = input.suspensionOffsets.indices.contains(wheel.index) ? input.suspensionOffsets[wheel.index] : 0
            let start = orientation.act(wheel.start - Vector(0,configuration.origin + offset,0)) + place
            let contact = flight?.gearUp == true ? nil : raycast(start, -up, wheel.length)
            if let hit = contact, wheel.tyre < 2 {
                var fraction = hit.distance / wheel.length
                if wheel.tyre == 1 && 100 > floor(random() * (floor(40 * Swift.abs(simd_dot(move, forward))) + 98)) {
                    fraction = min(1, fraction + wheel.radius / wheel.length / 4)
                }
                wheel.point = start - up * hit.distance - place
                wheel.normal = hit.normal; wheel.surface = hit.surface; wheel.material = hit.material
                let radiusShare = 1 - wheel.spring / wheel.length
                wheel.compression = (fraction - radiusShare) / (1 - radiusShare)
                wheel.offset = min(table.upper, table.upper + wheel.radius * (wheel.tyre == 1 ? 0.75 : 1) - hit.distance) - offset
            } else { wheel.compression = 1; wheel.offset = table.lower - offset }
            if table.model == 539, up.y >= 0.3, let buoyancy {
                let end = start - up * wheel.length
                let previous = wheel.compression < 1 ? place.y + wheel.point.y : -Double.infinity
                if let water = buoyancy.waterLevel(end), water > previous, end.y - 1 < water {
                    let distance = Self.clamp((start.y - water) / max(up.y,0.01),0,wheel.length)
                    let radiusShare = 1 - wheel.spring / wheel.length
                    wheel.compression = min(1,(distance / wheel.length - radiusShare) / (1 - radiusShare))
                    wheel.offset = min(table.upper,table.upper + wheel.radius - distance) - offset
                    wheel.point = start - up * distance - place; wheel.normal = Vector(0,1,0); wheel.surface = 2
                }
            }
        }
        abandoned = input.abandoned
        steeringInput = Self.clamp(steeringInput + (-input.steer - steeringInput) / 5 * stepSize, -1, 1)
        let throttle = Self.clamp(input.throttle, -1, 1), velocity = simd_dot(move, forward)
        burnout = false
        let accelerating = input.accelerate ?? max(0, throttle), brakeInput = input.brake ?? max(0, -throttle)
        simultaneous = accelerating > 150.0 / 255 && brakeInput > 150.0 / 255 && Swift.abs(velocity) < 0.1 ? accelerating : 0
        if let pedals = input.pedals { gas = pedals.x; braking = pedals.y }
        else if Swift.abs(velocity) < 0.01 {
            if simultaneous == 0 || buoyancy?.hasBoat == true || flight != nil { gas = throttle; braking = 0 }
            else { burnout = true; gas = accelerating; braking = brakeInput }
        } else if velocity >= 0 {
            gas = throttle < 0 ? 0 : throttle; braking = throttle < 0 ? -throttle : 0
        } else if throttle >= 0 && (gas <= 0.5 || velocity <= -0.15) { gas = 0; braking = throttle }
        else { gas = throttle; braking = 0 }
        if configuration.kind == "plane" {
            if velocity > 0.35 { braking *= 0.5 }
            else if input.pedals == nil, braking == 0, abs(originalInput.throttle) < 10.0 / 255, simd_length(move) < 0.1 { braking = 0.5 }
        }
        steering = table.lock * Double.pi / 180 * (configuration.kind == "plane" ? steeringInput * max(1 - velocity,0.1) : steeringInput * Swift.abs(steeringInput))
        if flags & 64 != 0 {
            rearSteering = input.handbrake ? -steering + (rearSteering + steering) * pow(0.1, stepSize) : rearSteering * pow(0.9, stepSize)
        }
        move.y -= 0.008 * stepSize
        let drag = fun & 2 != 0 ? 0 : (table.drag <= 0.01 ? table.drag : table.drag / 1000 / 2) * (flight?.drag ?? 1)
        move *= pow(1 - simd_length(move) * drag, stepSize)
        turn *= pow(0.99, stepSize)
        let lowSpeed = Swift.abs(velocity) < 0.15
        var springImpulses = Array(repeating: 0.0, count: 4)
        var dampingDirections = Array(repeating: -up, count: 4)
        for wheel in wheels where wheel.compression < 1 {
            let share = wheel.front ? table.suspBias : 1 - table.suspBias
            var stiffness = table.springs
            if flags & 65536 != 0 && flags & 131072 != 0 && lowSpeed { stiffness *= 1.5 }
            var normal = wheel.normal
            if simd_dot(dampingDirections[wheel.index], normal) > 0 { normal = -normal }
            let force = min(stepSize, 3) * mass * (1 - wheel.compression) * stiffness * share * 0.016
            springImpulses[wheel.index] = force
            push(normal * force, at: wheel.point)
        }
        for wheel in wheels where wheel.compression < 1 {
            contactSpeeds[wheel.index] = speed(at: wheel.point)
            if wheel.normal.y > 0.35 { dampingDirections[wheel.index] = -wheel.normal }
        }
        for wheel in wheels where wheel.compression < 1 {
            var damping = table.damping
            if flags & 131072 != 0 && damping > 0.1 && lowSpeed { damping = 0.1 }
            let direction = dampingDirections[wheel.index]
            let oldSpeed = simd_dot(contactSpeeds[wheel.index], direction)
            let currentSpeed = simd_dot(speed(at: wheel.point), direction)
            var change = -(Self.clamp(min(stepSize, 3) * damping, -0.25, 0.25) * oldSpeed)
            if change > 0 && change + currentSpeed > 0 { change = currentSpeed >= 0 ? 0 : -currentSpeed }
            else if change < 0 && change + currentSpeed < 0 { change = currentSpeed <= 0 ? 0 : -currentSpeed }
            var impulse = effectiveMass(wheel.point - bodyCentre, direction) * change
            let maximum = 0.999 * Swift.abs(springImpulses[wheel.index])
            if impulse > maximum { impulse = maximum }
            push(direction * impulse, at: wheel.point)
        }
        for wheel in wheels {
            contactPoints[wheel.index] = wheel.compression >= 1 ?
                orientation.act(wheel.start - Vector(0,configuration.origin + wheel.length,0)) : wheel.point
            contactSpeeds[wheel.index] = speed(at: contactPoints[wheel.index])
        }
        let forwardSpeed = simd_dot(move, forward), brakeForce = gearbox.brake * braking * stepSize
        var grounded = 0, drivenContacts = 0
        for wheel in wheels {
            if wheel.compression >= 1 {
                wheel.counts = max(wheel.counts - stepSize, 0)
                if wheel.counts <= 0 { continue }
            } else { wheel.counts = 4 }
            grounded += 1
            if table.drive == "4" || table.drive == (wheel.front ? "F" : "R") { drivenContacts += 1 }
        }
        if engineReserve < 0 { engineReserve -= stepSize / 1000; if engineReserve < -1 { engineReserve = 0.000001 } }
        else if configuration.nitro && engineReserve < 1 { engineReserve = min(1, stepSize / 100 * max(0.25, 1 - gas) + engineReserve) }
        let previousGear = transmission.gear
        let driveForce = engineForce(throttle: gas, speed: forwardSpeed, contacts: drivenContacts,
                                    nitro: configuration.nitro && engineReserve < 0)
        let traction = table.traction / 250 * 0.25 * (table.model == 539 && originalInput.throttle == 0 ? 4 : 1)
        var steeringShare = 1.0
        if forwardSpeed > 0.01 && wheels.contains(where: { ($0.index == 0 || $0.index == 1) && $0.counts > 0 }) {
            let sideSpeed = simd_dot(move, right)
            steeringShare = asin(min(Self.surfaceTraction[2] * traction * 16 / (forwardSpeed * forwardSpeed), 1)) / (table.lock * Double.pi / 180)
            if steering < 0 && sideSpeed > 0.05 || steering > 0 && sideSpeed < -0.05 || input.handbrake || steeringShare > 1 { steeringShare = 1 }
        }
        steering *= steeringShare
        if transmission.gear > previousGear && gas > 0.4 && braking < 0.1 && forwardSpeed > 0.15 &&
            wheels.contains(where: { $0.front && $0.compression < 1 }) && wheels.contains(where: { !$0.front && $0.compression < 1 }) {
            pushTurn(up * (-0.008 * min(turnMass, 2500)), at: -forward)
        }
        let frontAngle: Double? = flags & 32 != 0 || table.model == 520 ? nil : steering
        let rearAngle: Double? = flags & 32 != 0 ? -steering : flags & 64 != 0 ? rearSteering : nil
        if flags & 8388608 == 0 {
            applyAxle(front: true, angle: frontAngle, traction: traction, driveForce: driveForce,
                brakeForce: brakeForce, handbrake: input.handbrake, grounded: grounded, wetness: input.wetness)
        }
        applyAxle(front: false, angle: rearAngle, traction: traction, driveForce: driveForce,
            brakeForce: brakeForce, handbrake: input.handbrake, grounded: grounded, wetness: input.wetness)
        if flags & 8388608 != 0 {
            applyAxle(front: true, angle: frontAngle, traction: traction, driveForce: driveForce,
                brakeForce: brakeForce, handbrake: input.handbrake, grounded: grounded, wetness: input.wetness)
        }
        if fun & 2 != 0 && gas > 0 && drivenContacts > 0 && forwardSpeed >= 0 && 50 * forwardSpeed < 150 {
            move += forward * (9 * 2 * gearbox.accel * 0.4 * gas * stepSize * Double(drivenContacts))
        }
        let spinThrottle = Swift.abs(gas) > 0.05 ? gas : simultaneous
        let spinMaximum = Swift.abs(gearbox.gears[transmission.gear].max) * min(1, Swift.abs(spinThrottle))
        for wheel in wheels {
            let driven = table.drive == "4" || table.drive == (wheel.front ? "F" : "R")
            let road = simd_dot(contactSpeeds[wheel.index], forward)
            wheel.road = road
            if wheel.counts > 0 && wheel.state != 1 && !(driven && !wheel.front && simultaneous != 0 && wheel.state != 3) {
                wheel.spin = wheel.state == 3 ? 0 : road
            } else if driven && Swift.abs(spinThrottle) > 0.05 {
                let wanted = (spinThrottle < 0 ? -1.0 : 1) * max(Swift.abs(road), spinMaximum)
                wheel.spin += (wanted - wheel.spin) * (1 - pow(0.92, stepSize))
            } else { wheel.spin *= pow(0.95, stepSize) }
        }
        if table.model == 539 { for wheel in wheels { wheel.state = 0 } }
        var spin = 0.0
        for wheel in wheels where table.drive == "4" || table.drive == (wheel.front ? "F" : "R") {
            if wheel.counts <= 0 && Swift.abs(gas) > 0.5 { spin += 10 }
            else if wheel.state == 1 { spin += 1 }
        }
        spin *= table.drive == "4" ? 0.25 : 0.5
        let spinDecay = pow(spin >= soundSpin ? 0.95 : 0.7, stepSize)
        soundSpin = soundSpin * spinDecay + (1 - spinDecay) * spin
        heardAccel=input.pedals != nil ? max(0,gas):accelerating;heardBrake=input.pedals != nil ? braking:brakeInput
        heardHandbrake=input.handbrake;heardGrounded=Double(drivenContacts);heardClimb=50*move.y
        if flight != nil || buoyancy != nil {
            let body = NativeVehicleForces(move:move,turn:turn,right:right,forward:forward,up:up,middle:bodyCentre,place:place,
                quaternion:orientation,mass:mass,turnMass:turnMass,wheels:grounded)
            flight?.step(body,input:originalInput,step:stepSize)
            var buoyancyInput=input
            if flight != nil && buoyancy?.hasBoat == true {buoyancyInput.throttle=originalInput.throttle}
            buoyancy?.step(body,input:buoyancyInput,step:stepSize,wheels:grounded)
            move = body.move; turn = body.turn
        }
        if input.pad && configuration.kind == "car" && flight == nil && table.model != 539 && grounded == 0 {
            let amount = (Set([444,556,557]).contains(table.model) ? 0.0025 : 0.0007) * min(1, 3000 / turnMass) * turnMass * stepSize
            let steer = Self.clamp(input.steer, -1, 1), lean = -Self.clamp(input.lean, -1, 1)
            func allows(_ axis: Vector, _ value: Double) -> Bool {
                simd_dot(turn, axis) * (value < 0 ? -1 : value > 0 ? 1 : 0) < 0.02
            }
            if input.handbrake {
                if steer != 0 && allows(-up, steer) { pushTurn(right * (steer * amount), at: bodyCentre + forward) }
            } else if steer != 0 && allows(forward, steer) { pushTurn(right * (steer * amount), at: bodyCentre + up) }
            if lean != 0 && allows(right, lean) { pushTurn(up * (lean * amount), at: bodyCentre + forward) }
        }
        if gas == 0 && !(flight != nil && originalInput.throttle != 0) && table.model != 539 && Swift.abs(move.x) < 0.0045 && Swift.abs(move.y) < 0.0045 && Swift.abs(move.z) < 0.0045 && wheels.contains(where: { $0.compression < 1 }) {
            move = .zero; turn.y = 0
        }
        if wheels.count < 3 && buoyancy?.hasBoat != true && configuration.kind != "trailer" {
            turn += forward * (0.1 * right.y * stepSize)
            turn += forward * (-simd_dot(turn, forward) * min(1, 0.3 * stepSize))
        } else if wheels.count < 3 && configuration.kind == "trailer" {
            turn += forward * (-simd_dot(turn, forward) * min(1, 0.08 * stepSize))
        }
        let drivenWheels = wheels.filter { table.drive == "4" || table.drive == ($0.front ? "F" : "R") }
        let wheelSpeed = 50 * (drivenWheels.isEmpty ? wheels : drivenWheels).reduce(0) { max($0, Swift.abs($1.spin)) }
        return Output(linearVelocity: move * 50, angularVelocity: turn * 50,
            steering: buoyancy?.hasBoat == true ? buoyancy!.rudder : steering, rearSteering: flags & 32 != 0 ? -steering : flags & 64 != 0 ? rearSteering : 0,
            gear: transmission.gear, gas: gas, brake: braking, burnout: burnout, wheelSpeed: wheelSpeed,
            wheels: wheels.map { WheelSnapshot(index: $0.index, compression: $0.compression, offset: $0.offset,
                counts: $0.counts, state: $0.state, spin: $0.spin * 50, point: $0.point, normal: $0.normal,tyre:$0.tyre,surface:$0.surface) })
    }
}
