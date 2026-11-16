import Foundation
import CoreFoundation

/// Validated commands from the original browser service. These are distinct
/// from independent-server extensions such as `flightgear` and health ACKs.
/// Applying them remains the responsibility of the active native gameplay owner.
enum NativeOriginalWorldCommands {
    struct WeaponAmount: Equatable { let id: Int; let amount: Double }
    struct VehicleHit: Equatable {
        let vehicle: String?
        let damage: Double
        let weapon: Int?
        let wheel: Int?
        let from: String?
    }
    struct Staff: Equatable {
        let freeze: Bool?
        let health: Double?
        let armour: Double?
        let give: WeaponAmount?
        let take: Int?
        /// Applied only when `take` actually removed an owned weapon.
        let back: WeaponAmount?
        /// Target total ammunition, not an additive grant. The arsenal must
        /// check whether this weapon already exists or its slot is empty.
        let fill: WeaponAmount?
        let arm: [WeaponAmount]?
        let jetpack: Bool
        let skin: Int?
        let disarm: Bool
        let respawn: Bool
        let clear: Bool
    }
    struct Teleport: Equatable {
        /// Original/GTA coordinates, Z-up. No physics-axis conversion here.
        let point: SIMD3<Double>
        let ground: Bool
        /// Original tp.h is degrees. Hello.spot/wake.at use radians instead.
        let heading: Double?
        let out: SIMD2<Double>?
        var nativeHeading:Float?{heading.flatMap{let value = -Float($0 * .pi/180);return value.isFinite ? value:nil}}
    }
    struct Escape: Equatable {
        let command: String
        let allowed: Bool
        let reason: String?
        let seconds: Double
    }
    enum Event: Equatable {
        case vehicleHit(VehicleHit)
        case staff(Staff)
        case repairVehicle
        case flipVehicle
        case slap(Double)
        case dress(skin: Int, note: String?)
        case teleport(Teleport)
        case wake(point: SIMD3<Double>, heading: Double)
        case escape(Escape)
        case cash(Double)
        case day(shift: Double, hold: Double?)
        case weather(Int?)
        case passive(on: Bool, wait: Double)
        case shield(seconds: Double)
        case name(String)
        case profile(String)
        case style(Int)
        case heal(Double)
    }

    /// Number.isFinite semantics: strings and JSON booleans are not numbers.
    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }
    static func integer(_ value: Any?) -> Int? {
        guard let number = number(value), number.rounded(.towardZero) == number,
              abs(number) <= 9_007_199_254_740_991 else { return nil }
        return Int(exactly: number)
    }
    static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }
    /// A few legacy staff flags use JavaScript truthiness rather than strict
    /// booleans. Keep this explicit; do not coerce numeric fields the same way.
    static func truthy(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        if let number = value as? NSNumber { return number.doubleValue != 0 && !number.doubleValue.isNaN }
        if let text = value as? String { return !text.isEmpty }
        return true
    }
    private static func amount(_ value: Any?, integerAmount: Bool) -> WeaponAmount? {
        guard let row = value as? [Any], row.count >= 2, let id = integer(row[0]),
              let amount = number(row[1]), !integerAmount || integer(row[1]) != nil else { return nil }
        return WeaponAmount(id: id, amount: amount)
    }
    private static func pair(_ value: Any?) -> SIMD2<Double>? {
        guard let row = value as? [Any], row.count == 2,
              let x = number(row[0]), let y = number(row[1]) else { return nil }
        return SIMD2(x, y)
    }
    private static func vector(_ value: Any?) -> SIMD3<Double>? {
        guard let row = value as? [Any], row.count == 3,
              let x = number(row[0]), let y = number(row[1]), let z = number(row[2]) else { return nil }
        return SIMD3(x, y, z)
    }
    private static func rounded(_ value: Double) -> Double { floor(value + 0.5) }

    static func decode(_ message: [String: Any]) -> [Event] {
        guard let type = message["t"] as? String else { return [] }
        switch type {
        case "vhit", "hit":
            guard type == "vhit" || truthy(message["car"]),
                  let damage = number(message["d"]), type == "vhit" || damage > 0 else { return [] }
            return [.vehicleHit(VehicleHit(vehicle: message["v"] as? String, damage: damage,
                weapon: type == "hit" ? integer(message["w"]) ?? 0 : integer(message["w"]), wheel: integer(message["wh"]), from: message["from"] as? String))]
        case "staff":
            let rows = (message["arm"] as? [Any]).map { $0.prefix(4096).compactMap { amount($0, integerAmount: false) } }
            return [.staff(Staff(freeze: boolean(message["freeze"]), health: number(message["hp"]),
                armour: number(message["armour"]), give: amount(message["give"], integerAmount: true),
                take: integer(message["take"]), back: amount(message["back"], integerAmount: true),
                fill: amount(message["fill"], integerAmount: true), arm: rows,
                jetpack: truthy(message["jetpack"]), skin: integer(message["skin"]),
                disarm: truthy(message["disarm"]), respawn: truthy(message["respawn"]), clear: truthy(message["clear"])))]
        case "fix": return [.repairVehicle]
        case "flip": return [.flipVehicle]
        case "slap":
            guard let height = number(message["h"]), height > 0 else { return [] }
            return [.slap(min(height, 100))]
        case "dress":
            guard let skin = integer(message["skin"]) else { return [] }
            return [.dress(skin: skin, note: message["say"] as? String)]
        case "tp":
            guard let x = number(message["x"]), let y = number(message["y"]), let z = number(message["z"]) else { return [] }
            return [.teleport(Teleport(point: SIMD3(x,y,z), ground: number(message["g"]) == 1,
                                      heading: number(message["h"]), out: pair(message["out"])))]
        case "wake":
            guard let row = message["at"] as? [Any], row.count == 4,
                  let point = vector(Array(row.prefix(3))), let heading = number(row[3]) else { return [] }
            return [.wake(point: point, heading: heading)]
        case "escape":
            guard let command = message["c"] as? String else { return [] }
            return [.escape(Escape(command: command, allowed: truthy(message["go"]),
                reason: message["no"] as? String, seconds: number(message["s"]).map { max(1, rounded($0)) } ?? 0))]
        case "cash", "collect":
            return number(message["cash"]).map { [.cash($0)] } ?? []
        case "day": return [.day(shift: number(message["shift"]) ?? 0, hold: number(message["hold"]))]
        case "weather":
            let weather = integer(message["w"])
            return [.weather(weather.flatMap { $0 >= 0 ? $0 : nil })]
        case "passive":
            return [.passive(on: boolean(message["on"]) == true,
                wait: number(message["w"]).map { max(0, rounded($0)) } ?? 0)]
        case "shield": return [.shield(seconds: number(message["s"]).map { min(60, max(0, $0)) } ?? 0)]
        case "name": return (message["name"] as? String).map { [.name($0)] } ?? []
        case "profile": return (message["name"] as? String).map { [.profile($0)] } ?? []
        case "style": return integer(message["style"]).map { [.style($0)] } ?? []
        case "dose": return number(message["heal"]).map { [.heal($0)] } ?? []
        default: return []
        }
    }

    /// The browser's callback affects the currently occupied vehicle. The
    /// service already routed the event; `v` is not a second ownership check.
    /// Rhino immunity is weapon-specific, so do not subtract actor health or
    /// collapse a missing weapon to unarmed before applying it.
    static func vehicleDamage(_ message: [String: Any], driving: Bool, model: Int) -> VehicleHit? {
        guard driving, case .vehicleHit(let hit)? = decode(message).first else { return nil }
        if model == 432, hit.weapon.map({ (0...15).contains($0) }) != true { return nil }
        return hit
    }
}
