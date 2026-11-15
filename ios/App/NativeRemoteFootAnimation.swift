import Foundation
import simd

/// Public nC remote-pedestrian wrapper around the same R6 controller used by
/// the local player. Inputs are the decoded/interpolated public snapshot; all
/// coordinates here are GTA Z-up and native clockwise heading.
final class NativeRemoteFootAnimation {
    struct Snapshot {
        var position = SIMD3<Double>.zero
        var heading: Double = 0
        var velocity = SIMD3<Double>.zero
        var movement: Double = 0
        var airborne = false
        var crouching = false
        var weapon = 0
        var aim: Double?
        var action = 0
        var shots = 0
        var latestShots: Int?
        var life: Double = 100
        var armour: Double = 0
        var down = 0
        var paused = false
        var riding = false
        var pitch: Double = 0
        var roll: Double = 0
        var script: String?
        var nearFlooredTarget = false
    }
    private struct Flight { var at: Double;var jumped: Bool;var fell = false;var fastest: Double = 0 }
    let animator: NativeFootAnimation
    private let weapons: [Int:NativeFootWeaponAnimation]
    private var previousAction = 0
    private var previousDown = 0
    private var life: Double?
    private var hitUntil: Double = -.infinity
    private var deathClip: String?
    private var previousScript: String?
    private var fired: Int?
    private var flight: Flight?
    private var ground: Double?
    var hasUnsupportedFlight: Bool = false

    init(library: NativeSkeletalAnimationLibrary,style: NativeFootAnimationStyle,weapons: [Int:NativeFootWeaponAnimation],random: ()->Double = {Double.random(in:0..<1)}) {
        animator = NativeFootAnimation(library:library,style:style,random:random)
        self.weapons = weapons
    }

    func update(delta: Double,nowMilliseconds now: Double,snapshot state: Snapshot) -> NativeFootAnimation.Frame {
        let action = state.action & 63
        let feature = !state.riding && ((20...35).contains(action) || action == 36) ? action : 0
        if feature != previousAction { changeAction(from:previousAction,to:feature);previousAction = feature }
        animator.arm(weapons[state.weapon])
        let sum = state.life+state.armour
        let downKinds = ["koSkidBack","koSpinR","koSkidFront","koSpinL","floorHit","floorHitF"]
        let down = (1...6).contains(state.down) ? downKinds[state.down-1] : nil
        if let down,state.life > 0 && previousDown != state.down { _ = animator.knock(down) }
        previousDown = state.down
        if state.life <= 0 {
            if !animator.dead { animator.die(down ?? deathClip ?? "koFront") }
        } else {
            if animator.dead { animator.revive() }
            if feature != 30 { deathClip = nil }
            if let life,sum < life {
                let hit = NativePedestrianReaction.reaction(.init(weapon:22,still:state.movement < 0.05 && !state.airborne,crouched:state.crouching,damage:life-sum,now:now,until:hitUntil))
                hitUntil = hit.until
                if let kind = hit.kind { animator.flinch(kind,stun:hit.stun) }
            }
        }
        life = sum
        let script = state.life > 0 && !state.riding ? Self.manual(state.script) : nil
        if script?.wire != previousScript {
            let old = previousScript;previousScript = script?.wire
            if let old,animator.tagged == old { animator.rest() }
            if let script { _ = animator.act(script.clip,loop:script.how == "l",once:script.how == "o",tag:script.wire) }
        }
        let aiming = state.aim != nil && state.weapon != 0
        let weapon = weapons[state.weapon]
        let velocity = state.paused ? .zero : state.velocity
        var input = NativeFootAnimation.Input()
        input.ratio = min(2,state.movement);input.sprint = state.movement >= 3
        if input.sprint && animator.sprintSpeed > 0 {
            input.pace = min(1.3,max(1,hypot(velocity.x,velocity.y)/animator.sprintSpeed))
        }
        input.crouch = state.crouching
        if feature == 28 || feature == 36 || (aiming && !((weapon?.arm ?? false) && !state.crouching)) {
            let side = velocity.x*cos(state.heading)-velocity.y*sin(state.heading)
            let forward = velocity.x*sin(state.heading)+velocity.y*cos(state.heading)
            let speed = hypot(side,forward)
            let share = state.movement > 0.05 && speed > 0.001 ? min(1,state.movement)/speed : 0
            input.strafe = SIMD2(side*share,forward*share)
        }
        let latest = state.latestShots ?? state.shots
        if fired == nil || latest < fired! { fired = min(state.shots,latest) }
        if state.shots > fired!+3 { fired = state.shots-3 }
        let pending = state.shots > fired!
        if pending { _ = animator.fire(held:false,aside:state.movement > 1 ? "run" : state.nearFlooredTarget ? "ground" : nil) }
        if state.airborne {
            var current = flight ?? Flight(at:now,jumped:velocity.z > 0)
            current.fastest = max(current.fastest,-velocity.z)
            if velocity.z < -5 && state.position.z-(ground ?? -.infinity) > 4 { current.fell = true }
            input.air = current.fell ? "fall" : current.jumped ? "jump" : now-current.at > 350 ? "glide" : nil
            flight = current
        } else {
            ground = state.position.z
            if let previous = flight {
                if previous.jumped || now-previous.at > 350 {
                    input.land = previous.fell ? (previous.fastest > 20 ? "koSkidBack":"collapse") : state.movement > 1.5 && state.movement > 0.05 ? "land":"fallLand"
                }
                flight = nil
            }
        }
        input.gun = aiming ? .init(pitch:state.aim ?? 0) : nil
        input.guarding = feature == 28 || feature == 36;input.block = feature == 28
        if (10...16).contains(action),!state.riding {
            input.swim = .init(state:action-9,rate:state.movement,pitch:state.pitch)
            input.swimming = true
        }
        input.position=state.position;input.heading=state.heading
        if (50...62).contains(action),!state.riding {input.fly = .init(state:action-49,pitch:state.pitch,roll:state.roll)}
        hasUnsupportedFlight = false
        let frame = animator.update(delta:delta,input:input)
        if frame.shot && pending { fired! += 1 }
        return frame
    }

    private func changeAction(from old: Int,to next: Int) {
        if next == 29 {
            _ = animator.act("knife/kill_knife_player",once:true,blend:8);return
        }
        if next == 30 {
            _ = animator.act("knife/kill_knife_ped_damage",blend:8);deathClip = "knife/kill_knife_ped_die";return
        }
        switch next {
        case 20:_ = animator.act("ped/climb_jump",rooted:true,blend:8)
        case 21:_ = animator.act("ped/climb_idle",loop:true,rooted:true,blend:4)
        case 22:_ = animator.act("ped/climb_pull",rooted:true,cut:true)
        case 23:_ = animator.act("ped/climb_stand",rooted:true,paused:true,blend:4)
        case 24:_ = animator.act("ped/climb_stand",rooted:true,cut:true)
        case 25:_ = animator.act("ped/climb_jump_b",rooted:true,cut:true)
        default:
            if (20...25).contains(old) {
                if old == 24 { _ = animator.act("ped/climb_stand_finish",cut:true,once:true) }
                else if old == 25 { _ = animator.act("ped/climb_jump2fall",rooted:true,cut:true,once:true) }
                else { animator.rest() }
            }
            if next == 26 || next == 27 { _ = animator.roll(next == 27 ? 1:-1) }
        }
        if next == 31 { _ = animator.act("ped/gas_cwr",loop:true) }
        else if old == 31 { animator.rest() }
        if (32...35).contains(next) {
            let clip = ["vend_use","vend_use_pt2","vend_drink_p","vend_eat_p"][next-32]
            _ = animator.act("vending/"+clip,blend:8)
        } else if (32...35).contains(old) { animator.rest() }
    }
    private struct Manual {var wire:String;var clip:String;var how:String}
    private static func manual(_ wire: String?) -> Manual? {
        guard let wire else { return nil }
        let parts = wire.split(separator:"/",omittingEmptySubsequences:false)
        func valid(_ value: Substring) -> Bool {
            !value.isEmpty && value.count <= 24 && value.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
        }
        guard parts.count == 4,valid(parts[0]),valid(parts[1]),["l","h","o"].contains(String(parts[2])),
              parts[3].count == 1,parts[3].utf8.allSatisfy({(48...57).contains($0)}),!["sex","blowjobz","snm"].contains(String(parts[0])) else { return nil }
        return Manual(wire:wire,clip:String(parts[0])+"/"+String(parts[1]),how:String(parts[2]))
    }
}
