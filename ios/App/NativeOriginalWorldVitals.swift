import Foundation

/// The original browser service has no independent-server health ACK owner.
/// Keep fractional local damage between packets; ceiling is a presentation/
/// reporting operation, never a per-hit mutation of the underlying health.
final class NativeOriginalWorldVitals {
    struct Hit: Equatable {
        let damage: Double
        let weapon: Int
        var source: String?
        var point: SIMD3<Double>?
        var piece: Int?
        var quiet = false
        init(damage: Double, weapon: Int, source: String? = nil, point: SIMD3<Double>? = nil,
             piece: Int? = nil, quiet: Bool = false) {
            self.damage=damage; self.weapon=weapon; self.source=source; self.point=point; self.piece=piece; self.quiet=quiet
        }
    }
    struct Context {
        /// The actual guard owner must also verify frontal facing/source point.
        var frontMeleeParry = false
        var swimming = false
    }
    struct Result: Equatable {
        var applied = false
        var killed = false
        var absorbed = 0.0
        var lostHealth = 0.0
        var startBurning = false
        var startGas = false
        var douse = false
        var parried = false
        var quiet = false
    }
    enum FatalCause: Equatable { case hit(Hit), selfKill }
    struct PendingFatal: Equatable { let token: UInt64; let untilMilliseconds: Double; let cause: FatalCause }
    private(set) var health = 100.0
    private(set) var armour = 0.0
    private(set) var dead = false
    private(set) var godly = false
    private(set) var pendingFatal: PendingFatal?
    private var fatalToken: UInt64 = 0
    var wireHealth: Int { dead || pendingFatal != nil ? 0 : max(1, Int(ceil(health))) }
    var wireArmour: Int { Int(ceil(armour)) }
    var displayHealth: Int { dead ? 0 : Int(ceil(health)) }
    var displayArmour: Int { Int(ceil(armour)) }

    @discardableResult func begin(health: Double, armour: Double, wasted: Bool = false) -> Bool {
        guard health.isFinite, armour.isFinite else { return false }
        cancelPendingFatal(); godly=false; dead=wasted
        self.health = wasted ? 0 : min(100, max(1, health))
        self.armour = min(100, max(0, armour))
        return true
    }
    @discardableResult func setHealth(_ value: Double) -> Bool {
        guard !dead, value.isFinite else { return false }
        health=min(100,max(1,value)); return true
    }
    @discardableResult func setArmour(_ value: Double) -> Bool {
        guard value.isFinite else { return false }; armour=min(100,max(0,value));return true
    }
    func setGodly(_ value: Bool) { godly=value; if value && !dead { health=100 } }
    /// Staff values below1 are a kill request, not the alive health setter.
    /// A vehicle owner may defer that request through the same exit handshake.
    @discardableResult func staffHealth(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        if value >= 1 { return setHealth(value) }
        guard !dead else { return false }; kill(); return true
    }
    func kill() { cancelPendingFatal(); health=0; dead=true }
    /// The browser's c6.respawn does not heal a living actor. Only a completed
    /// dead-to-live transition restores100 health and clears armour.
    func respawn() {
        cancelPendingFatal()
        guard dead else { return }; dead=false;health=100;armour=0
    }
    @discardableResult func hurt(_ hit: Hit, context: Context = Context()) -> Result {
        var result=Result(); result.quiet=hit.quiet
        guard hit.damage.isFinite, hit.damage>0, !dead, !godly else { return result }
        if hit.weapon == 37 && !hit.quiet { result.startBurning=true;return result }
        if [41,42].contains(hit.weapon), !context.swimming {
            result.startGas=true;result.douse=hit.weapon==42;result.quiet=true
        }
        if context.frontMeleeParry, (0...15).contains(hit.weapon), hit.weapon != 9 {
            result.parried=true;return result
        }
        let absorbed = [53,54].contains(hit.weapon) ? 0 : min(armour,hit.damage)
        armour -= absorbed
        let lost=hit.damage-absorbed
        health -= lost
        result.applied=true;result.absorbed=absorbed;result.lostHealth=lost
        if health < 1 { health=0;dead=true;result.killed=true;cancelPendingFatal() }
        return result
    }
    /// Original onShot predicts fatal driving hits against ordinary armour
    /// before calling hurt. Preserve that actual admission expression even
    /// though fall/drown hurt later bypass armour. A pending hit suppresses
    /// further seated hits; its source identity remains with the game owner.
    @discardableResult func deferMovingCarFatal(_ hit: Hit, nowMilliseconds: Double,
        drivingCar: Bool, speed: Double) -> PendingFatal? {
        guard pendingFatal == nil,!dead,hit.damage.isFinite,hit.damage>0,nowMilliseconds.isFinite,
              speed.isFinite,drivingCar,abs(speed)>0.5,
              health-max(0,hit.damage-armour)<1 else { return nil }
        return enqueue(.hit(hit),nowMilliseconds:nowMilliseconds)
    }
    @discardableResult func deferMovingCarSelfKill(nowMilliseconds: Double,
        drivingCar: Bool, speed: Double) -> PendingFatal? {
        guard pendingFatal == nil,!dead,nowMilliseconds.isFinite,speed.isFinite,
              drivingCar,abs(speed)>0.5 else { return nil }
        return enqueue(.selfKill,nowMilliseconds:nowMilliseconds)
    }
    /// Native placement can wait for streamed collision even where the
    /// browser synchronously exits. Retain that immediate cause until the
    /// real exit succeeds, without inventing the moving-car two-second wait.
    @discardableResult func deferNativeExitFatal(_ hit:Hit,nowMilliseconds:Double)->PendingFatal? {
        guard pendingFatal==nil,!dead,hit.damage.isFinite,hit.damage>0,nowMilliseconds.isFinite,
              health-max(0,hit.damage-armour)<1 else{return nil}
        return enqueue(.hit(hit),nowMilliseconds:nowMilliseconds,delay:0)
    }
    @discardableResult func deferNativeExitSelfKill(nowMilliseconds:Double)->PendingFatal? {
        guard pendingFatal==nil,!dead,nowMilliseconds.isFinite else{return nil}
        return enqueue(.selfKill,nowMilliseconds:nowMilliseconds,delay:0)
    }
    private func enqueue(_ cause: FatalCause,nowMilliseconds: Double,delay:Double=2000) -> PendingFatal? {
        guard fatalToken < UInt64.max else { return nil };fatalToken+=1
        let value=PendingFatal(token:fatalToken,untilMilliseconds:nowMilliseconds+delay,cause:cause)
        guard value.untilMilliseconds.isFinite else { return nil };pendingFatal=value;return value
    }
    /// Keep the pending identity until the actual native vehicle exit succeeds;
    /// unloaded collision geometry must not lose or prematurely apply damage.
    func readyFatal(nowMilliseconds: Double,driving: Bool,wrecked: Bool) -> PendingFatal? {
        guard nowMilliseconds.isFinite,driving,!wrecked,let pending=pendingFatal,
              nowMilliseconds>=pending.untilMilliseconds else { return nil };return pending
    }
    func consumeFatal(token: UInt64) -> FatalCause? {
        guard let pending=pendingFatal,pending.token==token else { return nil }
        pendingFatal=nil;return pending.cause
    }
    func cancelPendingFatal() { pendingFatal=nil }
}
