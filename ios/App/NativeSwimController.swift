import Foundation
import simd

/// Literal public module 19863.dp movement/oxygen state, using Rapier Y-up
/// axes and browser yaw. Caller supplies water depth above the player's feet.
final class NativeSwimController {
    typealias V = SIMD3<Double>
    enum State: Int { case tread = 1, breast, crawl, dive, under, glide, out }
    struct Output { var move: V = .zero;var rise: Double = 0;var hurt: Double = 0 }
    private struct Haul { var from: V;var to: V;var time: Double }
    private(set) var on = false
    private(set) var state: State = .tread
    private(set) var ratio: Double = 0
    private var angle: Double = 0
    private var floatTurn: Double = 0
    private var elapsed: Double = 0
    private var ashoreTime: Double = 0
    private var surfaceOffset: Double = 0.55
    private var oxygen: Double = 1150
    private var splashed = false
    private var haul: Haul?
    private var push: Double = 0
    private var sprint: Double = 0
    private var diveRequested = false
    private var requestedPitch: Double = 0
    private var velocity = V.zero
    private var breastSpeed = 3.01/1.3
    private var crawlSpeed = 2.5/0.9
    private var underSpeed = 2.5/1.5
    var under: Bool { on && (state == .under || state == .glide) }
    var pitch: Double { state == .under || state == .glide ? angle : 0 }
    var pace: Double { max(1,sprint) }
    var breath: Double { oxygen/1150 }
    var turns: Bool { state != .dive && state != .out && ((state == .under || state == .glide) || push > 0) }
    let turnRate: Double = 4
    func consumeSplash() -> Bool { defer { splashed = false };return splashed }
    var hauled: V? {
        guard let haul else { return nil }
        let up = min(1,haul.time/0.45),across = clamp((haul.time-0.45)/0.35,0,1)
        return V(haul.from.x+(haul.to.x-haul.from.x)*across,
                 haul.from.y+(haul.to.y+0.02-haul.from.y)*(1-(1-up)*(1-up)),
                 haul.from.z+(haul.to.z-haul.from.z)*across)
    }
    private func clamp(_ value: Double,_ lo: Double,_ hi: Double) -> Double { min(hi,max(lo,value)) }
    private func offset(_ state: State) -> Double { state == .crawl ? 0.2 : state == .breast ? 0.4 : 0.55 }
    func setSpeeds(breast: Double?,crawl: Double?,under: Double?) {
        if let breast,breast > 0 { breastSpeed = breast }
        if let crawl,crawl > 0 { crawlSpeed = crawl }
        if let under,under > 0 { underSpeed = under }
    }
    func ashore(_ delta: Double) { oxygen = min(1150,oxygen+100*delta) }
    func revive() { oxygen = 1150 }
    func enters(_ depth: Double?) -> Bool { depth.map { $0 > 1.6 } ?? false }
    func enter(velocity: V,rising: Double,depth: Double) {
        on = true;haul = nil;self.velocity = V(velocity.x,rising,velocity.z)
        ratio = 0;floatTurn = 0;elapsed = 0;ashoreTime = 0;surfaceOffset = 0.55;splashed = rising < -1
        state = depth > 3 ? .glide : .tread;angle = depth > 3 ? 80*Double.pi/180 : 0
    }
    func stop() { on = false;haul = nil;ratio = 0;angle = 0;floatTurn = 0 }
    func steer(push: Double = 0,sprint: Double = 0,dive: Bool = false,pitch: Double = 0) {
        self.push = push;self.sprint = sprint
        if !diveRequested { diveRequested = dive }
        requestedPitch = pitch
    }
    func step(delta: Double,depth: Double?,grounded: Bool = false,heading: Double = 0,
              feet: V? = nil,jump: Bool = false,ledge: (() -> V?)? = nil,dead: Bool = false) -> Output? {
        guard on,delta > 0,delta.isFinite else { return nil }
        var result = Output();let dive = diveRequested;diveRequested = false
        if var hauling = haul {
            hauling.time += delta;haul = hauling
            if hauling.time >= 0.8 { stop();return nil };return result
        }
        guard let depth else { stop();return nil }
        ashoreTime = grounded && depth <= 1.6 && !under ? ashoreTime+delta : 0
        if (depth < 0 && state != .out) || ashoreTime > 0.3 { stop();return nil }
        let ticks = 50*delta,drag = pow(0.9,ticks),surface = depth-1
        var desiredOffset: Double = -1
        elapsed += delta
        if dead {
            state = .tread;ratio = 0;velocity *= drag;desiredOffset = 0.2
        } else {
            if state == .tread || state == .breast {
                if jump {
                    state = .out;elapsed = 0
                    if let feet,let top = ledge?() {
                        haul = Haul(from: feet,to: top,time: 0);velocity = .zero;return result
                    }
                    velocity.y = 8.0/70*50
                } else if dive { state = .dive;elapsed = 0;ratio = 0;splashed = true }
            }
            var forward = V(-sin(heading),0,-cos(heading))
            if state == .tread || state == .breast || state == .crawl {
                let amount = 0.07*50*delta
                ratio = push-ratio > amount ? ratio+amount : push
                state = sprint != 0 ? .crawl : ratio > 0.5 ? .breast : .tread
                angle *= pow(0.95,ticks)
                surfaceOffset += clamp(offset(state)-surfaceOffset,-delta,delta);desiredOffset = surfaceOffset
                let speed = state == .crawl ? crawlSpeed*max(1,sprint) : state == .breast ? breastSpeed*min(1,ratio) : 0
                velocity = velocity*drag+forward*(speed*(1-drag))
            } else if state == .dive {
                velocity *= drag;velocity.y -= 5*min(1,elapsed/1.07)*(1-drag)
                if elapsed >= 1.07 { state = .glide;angle = -35*Double.pi/180;floatTurn = 0 }
            } else if state == .under || state == .glide {
                let turn = clamp((requestedPitch-angle)*10,-1,1)
                if floatTurn == 0 || turn > 0 { angle += delta*turn }
                angle = clamp(angle+0.05*delta,-80*Double.pi/180,80*Double.pi/180)
                state = sprint != 0 || push > 0.5 ? .under : .glide
                let speed = state == .under ? underSpeed*max(1,sprint) : 0
                forward *= cos(angle)*speed;forward.y = sin(angle)*speed+0.5
                velocity = velocity*drag+forward*(1-drag)
                if surface < 0.65 && angle > Double.pi/4 {
                    state = .tread;floatTurn = 0;surfaceOffset = 0.55
                } else if angle >= 0 {
                    if surface >= 0.65 { floatTurn = floatTurn <= 0.001 ? 0 : floatTurn*pow(0.95,ticks) }
                    else {
                        if floatTurn > 0.025 { floatTurn *= pow(0.95,ticks) }
                        if floatTurn < 0.025 { floatTurn = min(0.025,floatTurn+delta/10) }
                        angle += ticks*floatTurn;desiredOffset = (0.55-0.2)*(4*angle/Double.pi)*0.75+0.2
                    }
                } else if surface+sin(angle) >= 0.65 {
                    floatTurn = floatTurn > 0.001 ? floatTurn*pow(0.95,ticks) : 0
                } else { floatTurn = min(0.05,floatTurn+delta/10);angle += ticks*floatTurn }
            } else if state == .out {
                velocity.x *= drag;velocity.z *= drag;velocity.y -= 14*delta
                if elapsed >= 0.65 || (velocity.y < 0 && surface >= 0.55) { state = .tread;surfaceOffset = 0.55 }
            }
            if state == .under || state == .glide {
                oxygen = max(0,oxygen-ticks*(state == .under ? 2 : 1))
                if oxygen <= 0 { result.hurt = 49.5*delta }
            } else { oxygen = min(1150,oxygen+2*ticks) }
        }
        if desiredOffset > 0 {
            let limit: Double = dead ? 1.2 : 5
            let desired = clamp((surface-desiredOffset)/delta,-limit,limit)
            velocity.y += clamp(desired-velocity.y,-50*delta,50*delta)
        }
        if grounded && velocity.y < 0 && !dead { velocity.y = max(velocity.y,-0.5) }
        result.move = V(velocity.x*delta,0,velocity.z*delta);result.rise = velocity.y
        return result
    }
}
