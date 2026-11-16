import Foundation
import simd

/// Ordered operations used by the public 49368.R6 animation accumulator.
/// Additive clips sum sign-corrected quaternions; replacements attenuate only
/// the bones present in the replacement, and rest fills any missing weight.
struct NativeSkeletalBlend {
    enum Operation { case add, replace, fillRest, spineCompensation }
    var operation: Operation = .add
    var clip = ""
    var time: Double = 0
    var weight: Double = 1
    var zeroSide = false
    var rooted = false
    var skipArms = false
    var skipLegs = false
}

struct NativeFootAnimationStyle {
    var walk = "ped/walk_player"
    var run = "ped/run_player"
    var sprint = "ped/sprint_civi"
    var idle = "ped/idle_stance"
    var turn = 50 * 9 * Double.pi / 180
    var skates: SIMD2<Double>?
}

/// Reads the original archived /game/world/peds.json and applies 66799.r's
/// model/type/modal fallback. No native replacement gait table is required.
final class NativeFootAnimationDefinitions {
    private let styles: [String: [String: Any]]
    private struct Ped { let model: String; let style: String; let type: String; let turn: Double }
    private let peds: [Ped]
    init(data: Data) throws {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        styles = json["styles"] as? [String: [String: Any]] ?? [:]
        peds = (json["peds"] as? [[Any]] ?? []).compactMap { row in
            guard row.count >= 5, let model = row[0] as? String, let style = row[2] as? String,
                  let type = row[3] as? String else { return nil }
            return Ped(model: model, style: style, type: type, turn: (row[4] as? NSNumber)?.doubleValue ?? 9)
        }
    }
    func style(model: String, type: String? = nil, library: NativeSkeletalAnimationLibrary) -> NativeFootAnimationStyle {
        var selected = peds.first { $0.model == model.lowercased() }
        if selected == nil, let type {
            var counts: [String: Int] = [:], highest = 0
            for ped in peds where ped.type == type {
                let key = "\(ped.style)|\(ped.turn)", count = (counts[key] ?? 0) + 1
                counts[key] = count
                if count > highest { selected = ped; highest = count }
            }
        }
        selected = selected ?? peds.first { $0.model == "special01" }
        guard let ped = selected else { return NativeFootAnimationStyle() }
        let config = styles[ped.style] ?? [:], block = config["block"] as? String ?? "ped"
        var result = NativeFootAnimationStyle()
        func named(_ key: String, _ fallback: String) -> String {
            guard let name = config[key] as? String else { return fallback }
            if library.contains("ped/" + name) { return "ped/" + name }
            return library.contains(block + "/" + name) ? block + "/" + name : fallback
        }
        result.walk = named("walk", result.walk); result.run = named("run", result.run)
        result.sprint = named("sprint", result.sprint); result.idle = named("idle", result.idle)
        result.turn = 50 * ped.turn * Double.pi / 180
        if block == "skate" { result.skates = SIMD2(5.0 / 15, 8.0 / 15) }
        return result
    }
}

/// Public browser 49368.R6 locomotion, air, landing, roll, knockdown,
/// flinch, scripted actions and death. Distances come from ANP3 bone-zero
/// tracks, including cycle wrap, rather than a native metres/second stride.
final class NativeFootAnimation {
    struct GunAim { var pitch: Double = 0; var yaw: Double = 0 }
    struct GunControl { var fire = false; var aim = false; var held = false; var pushed = false; var ready = true }
    struct Input {
        var ratio: Double = 0
        var sprint = false
        var pace: Double = 1
        var air: String?
        var land: String?
        var crouch = false
        var strafe: SIMD2<Double>?
        var look: Double = 0
        var guarding = false
        var swimming = false
        var swim: NativeSwimAnimation.Input?
        var fly: NativeFlightAnimation.Input?
        var position=SIMD3<Double>.zero
        var heading:Double=0
        var gun: GunAim?
        var block = false
        var poise = false
    }
    struct Frame {
        var blends: [NativeSkeletalBlend]
        /// Keep selection/inventory intact while both hands belong to a
        /// traversal pose, including its blend out and swim-to-ledge handoff.
        var handWeaponVisible: Bool {
            !blends.contains { $0.weight > 0 && ($0.clip.hasPrefix("ped/climb_") ||
                $0.clip.hasPrefix("swim/") || $0.clip == "ped/swim_tread") }
        }
        var travel: SIMD2<Double>
        var steps: [String]
        var look: Double
        var sprintShare: Double
        var crouchShare: Double
        var aim = NativeSkeletalActor.OriginalAim()
        var shot = false
        var shotLeft = false
        /// One event per emitted projectile/stream tick; true is left hand.
        var shots:[Bool] = []
        var hiddenBones: Set<Int> = []
        var figurePitch: Float = 0
        var figureRoll: Float = 0
        var legBend=SIMD2<Float>.zero
        var flight:NativeFlightAnimation.Frame?    }
    private struct Action {
        var kind: String
        var clip: String
        var time: Double = 0
        var weight: Double = 0
        var ending = false
        var down: Double?
        var speed: Double = 1
    }
    private struct Script {
        var clip: String
        var time: Double = 0
        var weight: Double = 0
        var loop: Bool
        var ending = false
        var rooted: Bool
        var once: Bool
        var paused: Bool
        var blend: Double
        var tag: String?
    }
    private struct Flinch { var clip: String; var time: Double = 0; var stun: Bool }
    private let library: NativeSkeletalAnimationLibrary
    private lazy var swimAnimation = NativeSwimAnimation(duration:{ [unowned self] in self.duration($0) })
    private lazy var flightAnimation = NativeFlightAnimation(duration:{ [unowned self] in self.library.duration(of:$0) })
    private let baseStyle: NativeFootAnimationStyle
    private(set) var style: NativeFootAnimationStyle
    private var phase: Double
    private var idleTime: Double
    private var crouchPhase: Double = 0
    private var sprint: Double = 0
    private var strafe: Double = 0
    private var crouch: Double = 0
    private var crouchVelocity: Double = 0
    private var crouchMoving: Double = 0
    private var crouchClip: String?
    private var straight: Double = 1
    private var directionWeights = SIMD4<Double>.zero
    private var directionTargets = SIMD4<Double>.zero
    private var strafePhase: Double = 0
    private var airWeights = SIMD3<Double>.zero
    private var airTimes = SIMD3<Double>.zero
    private var airTime: Double = 0
    private var fell = false
    private var stoppedRatio: Double = 0
    private var stoppedTime: Double = 0
    private var action: Action?
    private var script: Script?
    private var flinching: Flinch?
    private var death: Action?
    private(set) var lostHead = false
    private var lastTravel = SIMD2<Double>.zero
    private enum GunState { case aim, fire, reload }
    private var weapon: NativeFootWeaponAnimation?
    private var weaponFireClip: String?
    private var gunState = GunState.aim
    private var gunTime: Double = 0
    private var gunFired = false
    private var leftFired = false
    private var gunLeft = false
    private var gunSpare: Double = 0
    private var gunStream: Double = 0
    private let gunCycle = NativeGunAnimation()
    private var gunControl: GunControl?
    private var fireHeld = false
    private var gunBlend: Double = 0
    private var guardBlend: Double = 0
    private var blockBlend: Double = 0
    private var poiseBlend: Double = 0
    private var parryTime: Double?
    private var swingIndex = 0
    private var swingTime: Double = .infinity
    private var swingAside: String?
    private var priorWeapon: PriorWeapon?
    private struct PriorWeapon {
        var definition: NativeFootWeaponAnimation
        var clip: String?
        var time: Double
        var blockAt: Double
        var held: Double
        var guarding: Double
        var blocking: Double
        var poising: Double
        var pitch: Double
        var yaw: Double
        var arm: Bool
        var twin: Bool
        var most: Double
        var fade: Double = 1
    }
    private var lastGunClip: String?
    private var lastGunTime: Double = 0
    private var lastBlockAt: Double = 0
    private var lastAim = GunAim()
    private var lastArm = false
    private var lastTwin = false
    private var reportedGuard = false
    private var reportedBlock = false
    private var lastKnockCode=0
    var moveSpeed: Double = 1
    var onStep: ((String) -> Void)?

    static let actions: [String: String] = [
        "jump":"jump_glide", "glide":"fall_glide", "fall":"fall_fall",
        "launch":"jump_launch", "launchR":"jump_launch_r", "getUp":"getup", "getUpFront":"getup_front",
        "land":"jump_land", "fallLand":"fall_land", "collapse":"fall_collapse", "fallFront":"fall_front",
        "stop":"run_stop", "stopR":"run_stopr", "crouch":"weapon_crouch", "crouchFwd":"guncrouchfwd", "crouchBwd":"guncrouchbwd",
        "rollL":"crouch_roll_l", "rollR":"crouch_roll_r", "rollOutL":"car_rollout_lhs", "rollOutR":"car_rollout_rhs",
        "gunStand":"gun_stand", "strafeFwd":"gunmove_fwd", "strafeBwd":"gunmove_bwd", "strafeL":"gunmove_l", "strafeR":"gunmove_r",
        "flinch":"shot_partial", "flinchB":"shot_partial_b", "flinchL":"shot_leftp", "flinchR":"shot_rightp",
        "hitFront":"hit_front", "hitL":"hit_l", "hitBack":"hit_back", "hitR":"hit_r", "hitWalk":"hit_walk", "hitBehind":"hit_behind",
        "damArmLBk":"dam_arml_frmbk", "damArmLFt":"dam_arml_frmft", "damArmLLt":"dam_arml_frmlt",
        "damArmRBk":"dam_armr_frmbk", "damArmRFt":"dam_armr_frmft", "damArmRRt":"dam_armr_frmrt",
        "damLegLBk":"dam_legl_frmbk", "damLegLFt":"dam_legl_frmft", "damLegLLt":"dam_legl_frmlt",
        "damLegRBk":"dam_legr_frmbk", "damLegRFt":"dam_legr_frmft", "damLegRRt":"dam_legr_frmrt",
        "damStomachFt":"dam_stomach_frmft", "damStomachLt":"dam_stomach_frmlt", "damStomachBk":"dam_stomach_frmbk", "damStomachRt":"dam_stomach_frmrt",
        "koFront":"ko_shot_front", "koSkidFront":"ko_skid_front", "koSkidBack":"ko_skid_back", "koSpinL":"ko_spin_l", "koSpinR":"ko_spin_r",
        "floorHit":"floor_hit", "floorHitF":"floor_hit_f", "drown":"drown",
        "guardFwd":"fightsh_fwd", "guardBwd":"fightsh_bwd", "guardL":"fightsh_left", "guardR":"fightsh_right"
    ]
    private static let floorKinds: Set<String> = ["koSkidBack","koSkidFront","koSpinL","koSpinR","floorHit","floorHitF"]
    private static let busyKinds: Set<String> = ["collapse","koSkidBack","koSkidFront","koSpinL","koSpinR","getUp","fallFront","getUpFront","rollOutL","rollOutR","floorHit","floorHitF"]
    init(library: NativeSkeletalAnimationLibrary, style: NativeFootAnimationStyle = NativeFootAnimationStyle(), random: () -> Double = { Double.random(in: 0..<1) }) {
        self.library = library; self.style = style; self.baseStyle = style
        phase = random(); idleTime = 3 * random()
    }
    var walkSpeed: Double { speed(style.walk) }
    var runSpeed: Double { speed(style.run) }
    var sprintSpeed: Double { speed(style.sprint) }
    var sprints: Bool { style.run != style.sprint }
    var sprintShare: Double { sprint }
    var side: Double { lastTravel.x }
    var busy: Bool { death != nil || action.map { Self.busyKinds.contains($0.kind) || ($0.kind == "fallLand" && $0.time < 0.6 * duration($0.clip)) } == true }
    var rolling: Bool { action.map { !$0.ending && ["rollL","rollR"].contains($0.kind) } == true }
    var floored: Bool { action.map { Self.floorKinds.contains($0.kind) || ["getUp","getUpFront"].contains($0.kind) } == true }
    var reportedDown:Int {floored ? lastKnockCode:0}
    var dead: Bool { death != nil }
    var fallen: Bool { death.map { $0.time >= duration($0.clip) } == true }
    var acting: Bool { script.map { !$0.ending } == true }
    var tagged: String? { script.flatMap { $0.ending ? nil : $0.tag } }
    var acted: Bool { script.map { $0.ending || (!$0.loop && $0.time >= duration($0.clip)) } ?? true }
    var stunned: Bool { flinching.map { $0.stun && death == nil && $0.time < duration($0.clip) } == true }
    var armedWith: Int? { weapon?.id }
    var reloading: Bool { gunState == .reload }
    var firing: Bool { usesGunCycle ? gunState == .reload || gunCycle.firing : gunState != .aim }
    var gunUp: Bool { usesGunCycle && gunCycle.on }
    var gunShooting: Bool { usesGunCycle && gunCycle.shooting }
    var gunEnded: Bool { gunCycle.ended }
    var fired: Bool { usesGunCycle ? gunCycle.firing && gunCycle.fired : gunState == .fire && gunFired }
    var swinging: Bool { swingAside != "run" && swingActive }
    var aside: String? { swingAside }
    var swing: Int { swingIndex }
    var gunLoop: NativeFootWeaponAnimation.Loop? { usesGunCycle ? activeLoop : nil }
    var reportedAction: Int {
        if rolling { return action?.kind == "rollR" ? 27 : 26 }
        return reportedBlock ? 28 : reportedGuard ? 36 : 0
    }
    private var crouchedGun: Bool { crouch > 0.5 && weapon?.clip("crouchFire") != nil }
    private var fireClip: String? { crouchedGun ? weapon?.clip("crouchFire") : weaponFireClip }
    private var reloadClip: String? { crouch > 0.5 ? weapon?.clip("crouchReload") ?? weapon?.clip("reload") : weapon?.clip("reload") }
    private var twinCount: Double { weapon?.twin == true ? 2 : 1 }
    private var usesGunCycle: Bool { weapon != nil && weapon?.swings == nil && weapon?.through != true && fireClip != nil }
    private var activeLoop: NativeFootWeaponAnimation.Loop? {
        guard let weapon else { return nil }
        if let swings = weapon.swings, !swings.isEmpty {
            if swingAside == "run", let moving = weapon.moving { return moving.loop }
            if swingAside == "ground", let ground = weapon.ground { return ground.loop }
            return swings[swingIndex % swings.count].loop
        }
        return crouchedGun ? weapon.crouched : weapon.loop
    }
    private var gunConfiguration: NativeGunAnimation.Configuration? {
        guard let loop = activeLoop, let fireClip else { return nil }
        return NativeGunAnimation.Configuration(loop: loop, length: duration(fireClip), breakout: weapon?.breakout ?? .infinity,
            twin: weapon?.twin ?? false, continuous: weapon?.continuous ?? false, crouched: crouchedGun)
    }
    private var swingActive: Bool {
        weapon?.swings != nil && weapon != nil && death == nil && (gunState == .fire || gunTime < (fireClip.map(duration) ?? 0))
    }
    func arm(_ definition: NativeFootWeaponAnimation?) {
        guard weapon?.id != definition?.id else { return }
        let most = max(gunBlend, guardBlend, poiseBlend)
        if let weapon, most > (priorWeapon.map { $0.most * $0.fade } ?? 0) {
            priorWeapon = PriorWeapon(definition: weapon, clip: gunBlend > 0 ? lastGunClip : nil, time: lastGunTime,
                blockAt: lastBlockAt, held: gunBlend, guarding: guardBlend, blocking: blockBlend, poising: poiseBlend,
                pitch: lastAim.pitch, yaw: lastAim.yaw, arm: lastArm, twin: lastTwin, most: most)
        }
        gunBlend = 0; guardBlend = 0; blockBlend = 0; poiseBlend = 0; parryTime = nil
        lastGunClip = nil; lastArm = false; lastTwin = false
        weapon = definition; weaponFireClip = definition?.clip("fire")
        swingAside = nil; swingIndex = 0; swingTime = .infinity
        gunState = .aim; gunTime = .infinity; gunLeft = false; gunSpare = 0
        gunCycle.drop(); gunControl = nil; fireHeld = false
        style = baseStyle
        if let selected = definition?.style {
            for (key,name) in selected {
                let resolved = resolve(name)
                switch key { case "walk":style.walk=resolved ?? style.walk;case "run":style.run=resolved ?? style.run;case "sprint":style.sprint=resolved ?? style.sprint;case "idle":style.idle=resolved ?? style.idle;default:break }
            }
            style.skates = nil
        }
        moveSpeed = definition?.moveSpeed ?? 1
    }
    func control(_ value: GunControl) { gunControl = value }
    @discardableResult func fire(held: Bool = true, aside: String? = nil) -> Bool {
        guard let weapon, fireClip != nil, death == nil, gunState == .aim else { return false }
        if usesGunCycle {
            if held { fireHeld = true } else if let config = gunConfiguration { gunCycle.shoot(config) }
            return true
        }
        var again: Double?
        if let swings = weapon.swings {
            let prior = swingAside
            swingAside = aside == "run" && weapon.moving != nil ? "run" : aside == "ground" && weapon.ground != nil ? "ground" : nil
            swingIndex = swingAside != nil || prior != nil || !(swingTime < 0.35) ? 0 : (swingIndex + 1) % swings.count
            weaponFireClip = swingAside == "run" ? weapon.moving?.clip : swingAside == "ground" ? weapon.ground?.clip : swings[swingIndex].clip
            if swingAside == "ground" && prior == "ground" && swingTime < 0.35 { again = weapon.ground?.loop.again }
        }
        guard let loop = activeLoop else { return false }
        gunState = .fire; gunTime = (again ?? (held ? loop.start : max(0, loop.start))) + gunSpare
        gunSpare = 0; gunFired = false; leftFired = false; gunStream = 0.02
        return true
    }
    @discardableResult func reload() -> Double {
        guard weapon?.reloads == true, let clip = reloadClip, death == nil else { return 0 }
        gunState = .reload; gunTime = 0; return duration(clip) * twinCount
    }
    /// Native inventory reload takes ownership of the pending gun request.
    /// Keep raw reload() compatible with the animation API, but never let its
    /// suspended pre-muzzle trigger fire later when server readiness returns.
    /// This also cancels pending fire when no dedicated reload clip exists.
    @discardableResult func beginReload() -> Double {
        cancelInput()
        return reload()
    }
    func cancelReload() {if gunState == .reload {gunState = .aim;gunTime = .infinity}}
    func cancelFire() {
        if usesGunCycle { if let config = gunConfiguration { gunCycle.cancel(config) };return }
        if gunState == .fire && weapon?.swings == nil { gunState = .aim; gunTime = .infinity }
    }
    func cancelInput() {
        fireHeld=false;gunControl=nil
        if usesGunCycle,let config=gunConfiguration {gunCycle.cancelInput(config)}
        else {cancelFire()}
    }
    /// A lost input/task cannot retain an unconsumed melee hit marker. Preserve
    /// equipment and allow the existing pose blend to fade out normally.
    func cancelMeleeInput() {
        guard weapon?.use=="melee" else{return}
        gunState = .aim;gunTime = .infinity;gunSpare=0;gunFired=false;leftFired=false
        fireHeld=false;gunControl=nil;swingTime = .infinity;swingAside=nil;parryTime=nil
    }
    func resetFlight() {flightAnimation.reset()}
    /// Hard task discontinuity. Keep equipment/style and death state, but do
    /// not replay an old jump, landing, aim/trigger or water/flight modifier.
    func resetMovementTask() {
        cancelInput();action=nil;script=nil;flinching=nil
        airWeights = .zero;airTimes = .zero;airTime=0;fell=false
        stoppedRatio=0;stoppedTime=0;lastTravel = .zero
        sprint=0;strafe=0;crouch=0;crouchVelocity=0;crouchMoving=0;crouchPhase=0;crouchClip=nil
        straight=1;directionWeights = .zero;directionTargets = .zero;strafePhase=0
        gunCycle.drop();gunState = .aim;gunTime = .infinity;gunFired=false;leftFired=false;gunLeft=false;gunSpare=0;gunStream=0
        gunBlend=0;guardBlend=0;blockBlend=0;poiseBlend=0;parryTime=nil
        swingIndex=0;swingTime = .infinity;swingAside=nil;weaponFireClip=weapon?.clip("fire")
        priorWeapon=nil;lastGunClip=nil;lastGunTime=0;lastBlockAt=0;lastAim=GunAim();lastArm=false;lastTwin=false
        reportedGuard=false;reportedBlock=false
        swimAnimation=NativeSwimAnimation(duration:{[unowned self] in self.duration($0)})
        flightAnimation.reset()
    }
    func parry() { parryTime = 0 }

    func armWeaponStyle(weapon: Int, flags: Int = 0) {
        var selected = baseStyle
        let names: [String]?
        if flags & 512 != 0 { names = ["walk_rocket","run_rocket","run_rocket","idle_rocket"] }
        else if weapon == 9 { names = ["walk_csaw","run_csaw","run_csaw","idle_csaw"] }
        else if [25,27,30,31,33,34].contains(weapon) { names = ["walk_armed","run_armed","run_armed","idle_armed"] }
        else if [2,3,5,6,7,8].contains(weapon) { names = ["walk_player","run_player","run_player","idle_stance"] }
        else { names = nil }
        if let names {
            selected.walk = "ped/" + names[0]; selected.run = "ped/" + names[1]
            selected.sprint = "ped/" + names[2]; selected.idle = "ped/" + names[3]; selected.skates = nil
        }
        style = selected
    }
    @discardableResult private func start(_ kind: String) -> Double {
        guard let clip = named(kind) else { return 0 }
        action = Action(kind: kind, clip: clip, weight: action?.weight ?? 0)
        return duration(clip)
    }
    @discardableResult func launch() -> Double { min(0.5, start(phase < 0.5 ? "launch" : "launchR")) }
    func cancelQueuedLaunch() {
        if action?.kind=="launch" || action?.kind=="launchR" {action=nil}
    }
    @discardableResult func roll(_ side: Double) -> Bool { death == nil && !rolling && start(side > 0 ? "rollR" : "rollL") > 0 }
    @discardableResult func rollOut(_ side: Double) -> Double {
        guard death == nil else { return 0 }
        let length = start(side > 0 ? "rollOutR" : "rollOutL")
        if length > 0 { action?.weight = 1; action?.down = 0 }
        return length
    }
    @discardableResult func knock(_ kind: String = "koSkidBack") -> Bool {
        guard death == nil, !Self.floorKinds.contains(action?.kind ?? ""), Self.floorKinds.contains(kind), start(kind) > 0 else { return false }
        action?.weight = 1; action?.down = 0.7; flinching = nil; gunState = .aim
        lastKnockCode=(["koSkidBack","koSpinR","koSkidFront","koSpinL","floorHit","floorHitF"].firstIndex(of:kind) ?? -1)+1
        return true
    }
    @discardableResult func act(_ clip: String, loop: Bool = false, rooted: Bool = false, cut: Bool = false,
                               once: Bool = false, paused: Bool = false, blend: Double = 6, tag: String? = nil) -> Bool {
        guard death == nil, let clip = resolve(clip), duration(clip) > 0 else { return false }
        script = Script(clip: clip, weight: cut ? 1 : script?.weight ?? 0, loop: loop,
                        rooted: rooted, once: once, paused: paused, blend: blend, tag: tag)
        return true
    }
    func rest(cut: Bool = false) { if cut { script = nil } else { script?.ending = true } }
    func flinch(_ kind: String = "flinch", stun: Bool = false) {
        guard death == nil, !floored, let clip = named(kind) ?? resolve(kind) ?? named("flinch") else { return }
        flinching = Flinch(clip: clip, stun: stun)
    }
    func die(_ kind: String = "koFront", fallen: Bool = false,correctExisting:Bool=false) {
        guard let clip = named(kind) ?? resolve(kind) ?? named("koFront") else { return }
        if var existing=death {
            // A status snapshot can precede its hit event. Correct the
            // authoritative cause without restarting the visible death clock.
            if correctExisting {existing.kind=kind;existing.clip=clip;existing.time=min(existing.time,duration(clip));death=existing}
            return
        }
        death = Action(kind: kind, clip: clip, time: fallen ? duration(clip) : 0, weight: fallen ? 1 : 0)
        action = nil; flinching = nil; gunState = .aim; gunCycle.drop(); fireHeld = false
    }
    func revive() { death = nil; lostHead = false }
    func loseHead() { lostHead = true }

    func update(delta: Double, input: Input = Input()) -> Frame {
        reportedGuard = input.guarding && death == nil
        reportedBlock = input.block && reportedGuard
        let dt = max(0, delta.isFinite ? delta : 0)
        let ratio = death == nil ? min(2, max(0, input.ratio)) : 0
        func fade(_ value: Double, _ on: Bool, _ rise: Double, _ fall: Double) -> Double { min(1, max(0, value + (on ? rise : -fall) * dt)) }
        sprint = fade(sprint, input.sprint && ratio > 0.5 && input.strafe == nil, 5, 5)
        strafe = input.strafe == nil ? fade(strafe, false, 0, 8) : strafe + (1 - strafe) * min(1, 8 * dt)
        let direction = input.crouch || death != nil ? nil : input.strafe
        let magnitude = direction.map { abs($0.x) + abs($0.y) } ?? 0
        let directionMoving = magnitude >= 0.1
        straight = fade(straight, !directionMoving, 8, 8)
        if let direction, directionMoving {
            directionTargets = SIMD4(max(0, direction.y), max(0, -direction.y), max(0, -direction.x), max(0, direction.x)) / magnitude
            for index in 0..<4 { directionWeights[index] += min(8 * dt, max(-8 * dt, directionTargets[index] - directionWeights[index])) }
        } else if straight > 0.95 { strafePhase = 0; directionWeights = .zero; directionTargets = .zero }
        let directionWeight = directionWeights.sum()
        let strafeSpeed = directionMoving ? 1.15 * moveSpeed * min(1, simd_length(direction ?? .zero)) : 0
        crouch = fade(crouch, input.crouch && death == nil, 4, 4)
        var shot = false
        var shotEvents:[Bool] = []
        if usesGunCycle && death == nil && gunState != .reload, let config = gunConfiguration {
            var control = gunControl ?? GunControl(aim: input.gun != nil)
            if fireHeld { control.fire = true; control.held = true }
            gunCycle.control(fire: control.fire, aim: control.aim, held: control.held, pushed: control.pushed, ready: control.ready)
            let emitted = gunCycle.step(delta: dt, configuration: config)
            if emitted != 0 {
                shot=true;fireHeld=false;gunLeft=weapon?.continuous != true && emitted==2
                if config.continuous {shotEvents=Array(repeating:false,count:emitted)}
                else {
                    if emitted&1 != 0 {shotEvents.append(false)}
                    if emitted&2 != 0 {shotEvents.append(true)}
                }
            }
            gunBlend = max(gunCycle.blend, gunBlend - 4 * dt)
        } else { gunBlend = fade(gunBlend, death == nil && weapon != nil && fireClip != nil && (input.gun != nil || gunState != .aim || swingActive), 16, 4) }
        gunControl = nil
        guardBlend = fade(guardBlend, input.guarding && death == nil && weapon?.clip("guardIdle") != nil && gunState == .aim, 8, 5)
        blockBlend = fade(blockBlend, input.block && input.guarding && death == nil && weapon?.clip("guardBlock") != nil && gunState == .aim, 8, 5)
        poiseBlend = fade(poiseBlend, input.poise && death == nil && weapon?.clip("poise") != nil && gunState == .aim, 8, 5)
        if var prior = priorWeapon { prior.fade -= 8 * dt; priorWeapon = prior.fade <= 0 ? nil : prior }
        let priorHeld = priorWeapon.map { $0.held * $0.fade } ?? 0
        let priorGuard = priorWeapon.flatMap { $0.definition.clip("guardIdle") == nil ? nil : $0.guarding * $0.fade } ?? 0
        let airKinds = ["jump","glide","fall"], airRates = [8.0,4,4]
        for index in 0..<3 {
            airWeights[index] = fade(airWeights[index], input.air == airKinds[index], airRates[index], 6)
            airTimes[index] = airWeights[index] > 0 ? airTimes[index] + dt : 0
        }
        var steps: [String] = []
        func step(_ name: String) { steps.append(name); onStep?(name) }
        if let air = input.air {
            airTime += dt; fell = fell || air == "fall"
            if ["launch","launchR"].contains(action?.kind ?? "") { action?.ending = true }
        } else if airTime > 0 || input.land != nil {
            let landing: String? = input.land ?? (airTime <= 0.2 ? nil : airTime > 1.5 ? "collapse" : fell || airTime > 0.9 ? "fallLand" : ratio > 1.5 ? "land" : "fallLand")
            if let landing, death == nil, !Self.floorKinds.contains(action?.kind ?? ""), start(landing) > 0 {
                action?.weight = 1
                if ["fallLand","collapse"].contains(landing) { step(landing) }
                if input.sprint && ratio >= 1.5 { action?.speed = 2 }
                if ["koSkidBack","fallFront"].contains(landing) { action?.down = 0.7 }
            }
            airTime = 0; fell = false
        }
        if ratio >= 1.5 && sprint > 0.5 { stoppedRatio = ratio; stoppedTime = 0 } else { stoppedTime += dt }
        if input.air == nil && input.strafe == nil && death == nil && crouch < 0.5 && stoppedRatio >= 1.5 && stoppedTime < 0.4 && ratio < 0.25 && action == nil {
            _ = start(phase < 0.5 ? "stop" : "stopR"); stoppedRatio = 0
        }
        let nonSprint = 1 - sprint, nonStrafe = 1 - strafe
        let idleWeight = nonStrafe * nonSprint * max(0, 1 - ratio) + strafe * (directionWeight > 0 ? straight : 1)
        let weights = [idleWeight, nonStrafe * nonSprint * (ratio <= 1 ? ratio : 2 - ratio), nonStrafe * nonSprint * max(0, ratio - 1), nonStrafe * sprint]
        let clips = [style.idle, style.walk, style.run, style.sprint]
        var rate: Double = 0, movingWeight: Double = 0
        for index in 1..<4 where weights[index] > 0 && duration(clips[index]) > 0 {
            // R6 compares prepared clip identity: armed styles can share the
            // very same run/sprint clip, so index-based multipliers are wrong.
            let multiplier: Double = clips[index] == style.sprint ? input.pace : clips[index] == style.run ? 1.12 : 1
            rate += weights[index] * multiplier / duration(clips[index]); movingWeight += weights[index]
        }
        let before = phase
        if movingWeight > 0 { phase += rate / movingWeight * dt }
        let wrapped = phase >= 1
        phase = phase.truncatingRemainder(dividingBy: 1); idleTime += dt
        let stepping = death == nil && !input.swimming && input.swim == nil && input.air == nil && crouch < 0.5 && movingWeight > 0.5 && !(action.map { $0.weight > 0.5 } ?? false)
        if stepping, let skates = style.skates {
            let running = sprint > 0.5 || ratio > 1, clip = running ? style.run : style.walk
            if wrapped { step(running ? "skateL" : "skateWalkL") }
            else if crossed((running ? skates.y : skates.x) / max(0.000001, duration(clip)), before, phase, false) { step(running ? "skateR" : "skateWalkR") }
        } else if stepping && footstep(before, phase, wrapped) { step(sprint > 0.5 ? "sprint" : ratio > 1 ? "run" : "walk") }
        var blends: [NativeSkeletalBlend] = [], travel = SIMD2<Double>.zero
        func add(_ clip: String, _ time: Double, _ weight: Double, replace: Bool = false, zeroSide: Bool = false, rooted: Bool = false, keepMotion: Bool = false, skipArms: Bool = false, skipLegs: Bool = false) {
            guard weight > 0.0001, library.contains(clip) else { return }
            if replace && !skipLegs && library.hasRoot(clip) && !keepMotion { travel *= 1 - weight }
            blends.append(NativeSkeletalBlend(operation: replace ? .replace : .add, clip: clip, time: time, weight: weight, zeroSide: zeroSide, rooted: rooted, skipArms: skipArms, skipLegs: skipLegs))
        }
        let gunStand = named("gunStand"), aimIdle = gunStand == nil ? 0 : 1 - (1 - gunBlend) * (1 - priorHeld)
        let guardedIdle = (1 - guardBlend) * (1 - priorGuard)
        let idleClips: [(String?, Double)] = [
            (style.idle,idleWeight * (1 - aimIdle) * guardedIdle),
            (gunStand,idleWeight * aimIdle * guardedIdle),
            (weapon?.clip("guardIdle"),idleWeight * guardBlend),
            (priorWeapon?.definition.clip("guardIdle"),idleWeight * priorGuard * (1 - guardBlend))
        ]
        for (clip,weight) in idleClips {
            if let clip, duration(clip) > 0 { add(clip, idleTime.truncatingRemainder(dividingBy: duration(clip)), weight) }
        }
        for index in 1..<4 where weights[index] > 0.0001 && duration(clips[index]) > 0 {
            let clip = clips[index], length = duration(clip)
            add(clip, index == 0 ? idleTime.truncatingRemainder(dividingBy: length) : phase * length, weights[index])
            if index != 0 { travel += displacement(clip, before * length, phase * length, wrapped) * weights[index] }
        }
        let strafeKinds = input.guarding && named("guardFwd") != nil ? ["guardFwd","guardBwd","guardL","guardR"] : ["strafeFwd","strafeBwd","strafeL","strafeR"]
        var strafeDuration: Double = 0, strafeWeight: Double = 0
        for index in 0..<4 {
            if let clip = named(strafeKinds[index]), directionTargets[index] > 0 { strafeDuration += duration(clip) * directionTargets[index]; strafeWeight += directionTargets[index] }
        }
        let previousStrafe = strafePhase
        if strafeDuration > 0 { strafePhase += dt * strafeSpeed * strafeWeight / strafeDuration }
        let strafeWrapped = strafePhase >= 1; strafePhase = strafePhase.truncatingRemainder(dividingBy: 1)
        if death == nil && !input.swimming && input.swim == nil && input.air == nil && crouch < 0.5 && strafe * (1 - straight) > 0.5 && strafeDuration > 0 && footstep(previousStrafe, strafePhase, strafeWrapped) { step("walk") }
        for index in 0..<4 {
            guard let clip = named(strafeKinds[index]) else { continue }
            let weight = strafe * (1 - straight), visual = directionWeight > 0 ? weight * directionWeights[index] / directionWeight : 0
            add(clip, strafePhase * duration(clip), visual, zeroSide: true)
            let moving = weight * directionTargets[index]
            if moving > 0.0001 { travel += displacement(clip, previousStrafe * duration(clip), strafePhase * duration(clip), strafeWrapped, side: true) * moving }
        }
        blends.append(NativeSkeletalBlend(operation: .fillRest))
        if crouch > 0, let base = named("crouch") {
            let sign = input.strafe.map { $0.y == 0 ? 0 : $0.y > 0 ? 1.0 : -1.0 } ?? 1
            let target = ratio > 0.05 ? sign * min(1, ratio) : 0
            crouchVelocity += min(3.5 * dt, max(-3.5 * dt, target - crouchVelocity))
            if crouchVelocity != 0 { crouchClip = named(crouchVelocity < 0 ? "crouchBwd" : "crouchFwd") }
            crouchMoving = fade(crouchMoving, crouchVelocity != 0, 8, 4)
            if crouchMoving <= 0 { crouchClip = nil }
            add(base, idleTime.truncatingRemainder(dividingBy: duration(base)), crouch, replace: true)
            if let clip = crouchClip {
                let previous = crouchPhase, length = duration(clip)
                if crouchVelocity != 0 { crouchPhase += dt * max(0.6, abs(crouchVelocity)) / length }
                let wrapped = crouchPhase >= 1; crouchPhase = crouchPhase.truncatingRemainder(dividingBy: 1)
                if death == nil && input.air == nil && crouch > 0.5 && crouchMoving > 0.5 && [1.0/15, 0.5+1.0/15].contains(where: { crossed(($0 + 0.2 / length).truncatingRemainder(dividingBy: 1), previous, crouchPhase, wrapped) }) { step("crouch") }
                add(clip, crouchPhase * length, crouch * crouchMoving, replace: true)
                travel += displacement(clip, previous * length, crouchPhase * length, wrapped) * (crouch * crouchMoving)
            }
        } else { crouchVelocity = 0; crouchMoving = 0; crouchClip = nil }
        for index in 0..<3 {
            if let clip = named(airKinds[index]), airWeights[index] > 0 { add(clip, min(airTimes[index], duration(clip)), airWeights[index], replace: true) }
        }
        if let current = action, let down = current.down, current.time >= duration(current.clip) {
            action?.down = down - dt
            if down - dt <= 0 {
                if death != nil || start(["koSkidFront","floorHitF","fallFront"].contains(current.kind) && named("getUpFront") != nil ? "getUpFront" : "getUp") <= 0 { action?.down = nil; action?.ending = true }
            }
        }
        if var current = action {
            let previous = current.time, length = duration(current.clip)
            current.time = min(length, current.time + dt * current.speed)
            let rolling = ["rollL","rollR"].contains(current.kind)
            if ["stop","stopR"].contains(current.kind) && ratio > 0.3 { current.ending = true }
            if current.down == nil && current.time >= length - 0.15 { current.ending = true }
            current.weight = fade(current.weight, !current.ending, 8, 5)
            add(current.clip, current.time, current.weight, replace: true, zeroSide: rolling)
            travel += displacement(current.clip, previous, current.time, false, side: rolling) * current.weight
            action = current.ending && current.weight <= 0 ? nil : current
        }
        if gunState != .fire { gunSpare = 0 }
        let previousGunTime = gunTime
        if gunState == .fire, let weapon, let loop = activeLoop {
            gunTime += dt
            if weapon.continuous == true {
                gunStream += dt
                if gunTime >= loop.fire && gunStream >= 0.02 { gunStream = min(gunStream - 0.02, 0.02); shot = true; gunFired = true;shotEvents.append(false) }
            } else if weapon.twin && gunFired && !leftFired && gunTime >= loop.fire + loop.interval / 2 - 0.006 {
                shot = true; leftFired = true; gunLeft = true;shotEvents.append(true)
            } else if !gunFired && gunTime >= loop.fire { shot = true; gunFired = true; gunLeft = false;shotEvents.append(false) }
            if gunTime >= loop.start + loop.interval - 0.006 {
                gunSpare = min(gunTime - loop.start - loop.interval, loop.interval - 0.006)
                gunState = .aim; swingTime = 0
            }
        } else if gunState == .reload {
            gunTime += dt
            if gunTime >= (reloadClip.map(duration) ?? 0) * twinCount { gunState = .aim }
        } else if weapon?.through == true { gunTime += dt; swingTime += dt }
        let selectedGunClip = gunBlend > 0 && weapon != nil ? (gunState == .reload ? reloadClip : fireClip) : nil
        let rollReduction = action.map { ["rollL","rollR"].contains($0.kind) ? $0.weight : 0 } ?? 0
        let heldWeight = gunBlend * (1 - rollReduction)
        if let prior = priorWeapon {
            if let clip = prior.clip { add(clip, prior.time, priorHeld * (gunBlend > 0 ? heldWeight / gunBlend : 1), replace: true, keepMotion: true) }
            if let clip = prior.definition.clip("guardBlock") { add(clip, prior.blockAt, prior.blocking * prior.fade, replace: true) }
            if let clip = prior.definition.clip("poise") { add(clip, 0, prior.poising * prior.fade, replace: true) }
        }
        lastGunClip = selectedGunClip
        if let selectedGunClip {
            if gunState == .fire && gunTime < 0, let lead = weapon?.clip("lead") { lastGunClip = lead; lastGunTime = duration(lead) + gunTime }
            else if gunState == .reload { lastGunTime = gunTime.truncatingRemainder(dividingBy: duration(selectedGunClip)) }
            else if usesGunCycle { lastGunTime = min(gunCycle.time, duration(selectedGunClip)) }
            else if gunState != .aim || (weapon?.through == true && gunTime < .infinity) { lastGunTime = min(gunTime, duration(selectedGunClip)) }
            else { lastGunTime = min(activeLoop?.start ?? 0, duration(selectedGunClip)) }
        }
        if let clip = lastGunClip {
            if crouchedGun && crouchMoving > 0 {
                add(clip, lastGunTime, heldWeight * (1 - crouchMoving), replace: true, keepMotion: true)
                add(clip, lastGunTime, heldWeight, replace: true, keepMotion: true, skipLegs: true)
                blends.append(NativeSkeletalBlend(operation: .spineCompensation, clip: clip, time: lastGunTime, weight: heldWeight))
            } else { add(clip, lastGunTime, heldWeight, replace: true, keepMotion: swingAside == "run" || crouchedGun) }
        }
        if weapon?.swings != nil && swingAside == nil, let selectedGunClip, gunState != .reload && previousGunTime >= 0 && previousGunTime < duration(selectedGunClip) {
            travel += displacement(selectedGunClip, previousGunTime, min(gunTime, duration(selectedGunClip)), false) * heldWeight
        }
        if blockBlend > 0, let clip = weapon?.clip("guardBlock") {
            if let parry = parryTime { parryTime = parry + dt >= 0.3 ? nil : parry + dt }
            let guardAt: Double = weapon?.guardAt ?? 0
            let guardTo: Double = weapon?.guardTo ?? 0
            var offset: Double = 0
            if let parry = parryTime { offset = (1 - abs(1 - parry / 0.3 * 2)) * (guardTo - guardAt) }
            lastBlockAt = min(guardAt + offset, duration(clip))
            add(clip, lastBlockAt, blockBlend, replace: true)
        } else { parryTime = nil }
        if poiseBlend > 0, let clip = weapon?.clip("poise") { add(clip, 0, poiseBlend, replace: true) }
        let swim = swimAnimation.update(delta:dt,input:death == nil ? input.swim : nil)
        for blend in swim.blends { add(blend.clip,blend.time,blend.weight,replace:true) }
        let flight=flightAnimation.update(delta:dt,input:death == nil ? input.fly:nil,position:input.position,heading:input.heading)
        for blend in flight.blends {add(blend.clip,blend.time,blend.weight,replace:true)}
        if var current = flinching {
            current.time += dt; let length = duration(current.clip)
            if current.time >= length { flinching = nil }
            else {
                add(current.clip, current.time, min(1, 16 * current.time, (length - current.time) * 8), replace: true, keepMotion: current.stun, skipArms: current.stun && gunBlend > 0.5, skipLegs: current.stun && crouch > 0.5)
                flinching = current
            }
        }
        if var current = script {
            if !current.paused { current.time += dt }
            let length = duration(current.clip)
            if current.loop { current.time = current.time.truncatingRemainder(dividingBy: length) }
            if current.once && current.time >= length - 0.15 { current.ending = true }
            current.weight = fade(current.weight, !current.ending && death == nil, current.blend, current.blend)
            if current.weight <= 0 && (current.ending || death != nil) { script = nil }
            else { add(current.clip, min(current.time, length), current.weight, replace: true, rooted: current.rooted); script = current }
        }
        if var current = death {
            let previous = current.time
            current.time = min(duration(current.clip), current.time + dt); current.weight = min(1, current.weight + 4 * dt)
            add(current.clip, current.time, current.weight, replace: true)
            travel += displacement(current.clip, previous, current.time, false) * current.weight
            death = current
        }
        lastTravel = travel
        var aim = NativeSkeletalActor.OriginalAim(look: Float(death == nil ? input.look : 0))
        if let prior = priorWeapon {
            if !prior.arm {
                let pitch: Double = min(1.2, max(-1.2, prior.pitch))
                let amount: Double = pitch * priorHeld * (1 - gunBlend)
                aim.spinePitch += Float(amount)
            }
            aim.previousRightArm = prior.arm ? Float(priorHeld) : 0
            aim.previousLeftArm = prior.twin ? Float(priorHeld) : 0
            aim.previousPitch = Float(prior.pitch); aim.previousYaw = Float(prior.yaw)
        }
        if let gun = input.gun, gun.pitch != 0 && gunBlend > 0 && (weapon?.arm != true || crouchedGun) {
            aim.spinePitch += Float(min(1.2, max(-1.2, gun.pitch)) * gunBlend)
        }
        lastAim = input.gun ?? GunAim(); lastArm = false; lastTwin = false
        if selectedGunClip != nil && gunState != .reload && !crouchedGun {
            lastArm = weapon?.arm == true
            lastTwin = weapon?.twin == true && !library.hasBone(32, in: selectedGunClip!)
            aim.pitch = Float(lastAim.pitch); aim.yaw = Float(lastAim.yaw)
            aim.twin = lastTwin ? Float(gunBlend) : 0
            aim.rightArm = lastArm ? Float(gunBlend) : 0
            aim.leftArm = lastTwin ? Float(gunBlend) : 0
        }
        return Frame(blends: blends, travel: travel, steps: steps, look: death == nil ? input.look : 0, sprintShare: sprint, crouchShare: crouch, aim: aim, shot: shot, shotLeft: gunLeft,shots:shotEvents, hiddenBones: lostHead ? [5] : [],figurePitch:Float(flight.figureControlled ? flight.figurePitch:swim.figurePitch),figureRoll:Float(flight.figureRoll),legBend:SIMD2<Float>(flight.bend),flight:flightAnimation.showing || flight.figureControlled ? flight:nil)
    }

    private func duration(_ name: String) -> Double { library.duration(of: name) ?? 0 }
    private func speed(_ name: String) -> Double { let length = duration(name); return length > 0 ? library.cycleTravel(name).y / length : 0 }
    private func resolve(_ name: String) -> String? { library.canonicalName(forWire: name.contains("/") ? name : "ped/" + name) }
    private func named(_ name: String) -> String? { resolve(Self.actions[name] ?? name) }
    private func displacement(_ name: String, _ from: Double, _ to: Double, _ wrap: Bool, side: Bool = false) -> SIMD2<Double> {
        var value = library.travel(name, at: to) - library.travel(name, at: from)
        if wrap { value += library.cycleTravel(name) }
        if !side { value.x = 0 }
        return value
    }
    private func crossed(_ threshold: Double, _ before: Double, _ after: Double, _ wrap: Bool) -> Bool { wrap ? threshold > before || threshold <= after : threshold > before && threshold <= after }
    private func footstep(_ before: Double, _ after: Double, _ wrap: Bool) -> Bool { crossed(1.0/15, before, after, wrap) || crossed(0.5+1.0/15, before, after, wrap) }
}
