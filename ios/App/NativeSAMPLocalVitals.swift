// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Local GTA vital values for a legacy SA-MP session. RPC14/66 are the server
/// setters; RPC115 reports a locally observed hit and has no health ACK. Keep
/// fractional values between simulation steps, separately from HUD/sync bytes.
struct NativeSAMPLocalVitals {
    static let maximum = 1_000_000.0
    struct Cause: Equatable {
        let weapon: UInt8
        let source: UInt16
    }
    struct Damage: Equatable {
        let amount: Float
        let weapon: Int
        let source: UInt16
        let body: Int
        let absorbed: Double
        let lostHealth: Double
        let killed: Bool
    }
    private(set) var health = 100.0
    private(set) var armour = 0.0
    private(set) var fatalCause: Cause?
    var dead: Bool { health < 1 }
    var displayHealth: Int { dead ? 0 : Int(ceil(health)) }
    var displayArmour: Int { Int(ceil(armour)) }
    // The legacy uncompressed sync fields are integer health/armour bytes.
    // Do not feed their quantization back into the local simulation owner.
    var wireHealth: Int { dead ? 0 : Int(min(255,health)) }
    var wireArmour: Int { Int(min(255,armour)) }

    mutating func reset() { self = Self() }
    /// A known fatal gameplay event has no inferred damage amount. Preserve
    /// armour and its explicit cause;255 denotes an untyped compatibility kill.
    @discardableResult mutating func kill(weapon:Int,source:UInt16=65535)->Bool{
        guard !dead,(0...54).contains(weapon) || weapon==255 else{return false}
        health=0;fatalCause=Cause(weapon:UInt8(weapon),source:source);return true
    }
    @discardableResult mutating func seed(health hp: Double? = nil, armour ap: Double? = nil) -> Bool {
        guard hp.map({$0.isFinite && (0...Self.maximum).contains($0)}) ?? true,
              ap.map({$0.isFinite && (0...Self.maximum).contains($0)}) ?? true else { return false }
        if let hp {
            health = hp
            if dead { health=0; fatalCause=fatalCause ?? Cause(weapon:255,source:65535) }
            else { fatalCause=nil }
        }
        if let ap { armour=ap }
        return true
    }
    /// Call only for real local damage supplied by the native gameplay owner.
    /// This does not guess damage from received bullets or server hit notices.
    mutating func hurt(_ amount: Double, weapon: Int, source: UInt16 = 65535, body: Int = 3) -> Damage? {
        guard amount.isFinite, amount > 0, amount <= 10000, !dead,
              (0...54).contains(weapon), (3...9).contains(body), Float(amount)>0 else { return nil }
        let absorbed = [53,54].contains(weapon) ? 0 : min(armour,amount)
        armour -= absorbed
        let lost=amount-absorbed
        health=max(0,health-lost)
        if dead { health=0; fatalCause=Cause(weapon:UInt8(weapon),source:source) }
        return Damage(amount:Float(amount),weapon:weapon,source:source,body:body,
                      absorbed:absorbed,lostHealth:lost,killed:dead)
    }
}
