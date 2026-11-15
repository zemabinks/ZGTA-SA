import Foundation
import simd

/// Public54205.$l: parachute and jetpack movement in original Rapier Y-up axes.
final class NativePersonalFlightController {
    typealias V=SIMD3<Double>
    enum State:Int {case dive=1,accelerate,diveLeft,diveRight,opening,float,decelerate,steerLeft,steerRight,landed,pack,hover,thrust}
    struct Landing {let speed:Double;let canopy:Bool;let dead:Bool}
    struct Step {let move:V;let rise:Double;let landed:Landing?}
    private struct Opening {let lean:Double,roll:Double,forward:Double,rise:Double}
    private var chute=0,lean=0.0,chuteRoll=0.0,forward=0.0,rise=0.0,elapsed=0.0,maximumFall=0.0
    private var opening:Opening?
    private(set) var worn=false
    private(set) var flying=false
    private var jetPitch=0.0,jetRoll=0.0,jetVertical=0.0,stopping=false
    private(set) var heading=0.0
    private var velocity=V.zero
    private var x=0.0,y=0.0,open=false,up=false,down=false,brake=false
    private static let radians=Double.pi/180
    var chuting:Bool {(1...9).contains(chute)}
    var on:Bool {chuting || flying}
    var state:Int {chute != 0 ? chute:worn ? flying ? jetVertical>0 || jetRoll != 0 ? State.thrust.rawValue:State.hover.rawValue:State.pack.rawValue:0}
    var pitch:Double {flying ? jetPitch:lean*Self.radians}
    var roll:Double {flying ? jetRoll:chuteRoll*Self.radians}
    var linearVelocity:V {flying ? velocity:V(velocity.x,rise,velocity.z)}
    func wear(_ value:Bool) {
        worn=value;if !value {flying=false}
        jetPitch=0;jetRoll=0;jetVertical=0;velocity = .zero
    }
    func dives(rising:Double,height:Double?)->Bool {chute==0 && !flying && rising < -10 && (height == nil || height!>20)}
    func dive(velocity:V,rising:Double,heading:Double) {
        chute=State.dive.rawValue;lean=0;chuteRoll=0;elapsed=0
        maximumFall = -rising;rise=rising;self.heading=heading
        self.velocity=V(velocity.x,0,velocity.z);open=false
    }
    var lifts:Bool {worn && !flying && !chuting && (up || y != 0)}
    func takeOff(heading:Double,velocity:V? = nil) {flying=true;self.heading=heading;self.velocity=velocity ?? .zero}
    /// Clear pending controls without interrupting physical flight or changing
    /// its momentum, equipment, phase or facing.
    func cancelInput() {x=0;y=0;open=false;up=false;down=false;brake=false}
    func stop() {
        // A discontinuity cancels queued controls as well as current motion.
        // Equipment and physical facing survive teleport/death/water handoff.
        chute=0;flying=false;lean=0;chuteRoll=0;forward=0;rise=0;elapsed=0;maximumFall=0;opening=nil
        jetPitch=0;jetRoll=0;jetVertical=0;stopping=false;velocity = .zero
        cancelInput()
    }
    func steer(x:Double=0,y:Double=0,open:Bool=false,up:Bool=false,down:Bool=false,stop:Bool=false) {
        self.x=x;self.y=y;if !self.open {self.open=open};self.up=up;self.down=down;brake=stop
    }
    private static func clamp(_ x:Double,_ low:Double=0,_ high:Double=1)->Double {max(low,min(high,x))}
    private static func angle(_ x:Double)->Double {
        let turn=2*Double.pi,value=x+Double.pi
        return ((value.truncatingRemainder(dividingBy:turn)+turn).truncatingRemainder(dividingBy:turn))-Double.pi
    }
    private var axes:(forward:V,right:V) {(V(-sin(heading),0,-cos(heading)),V(cos(heading),0,-sin(heading)))}
    func step(delta:Double,grounded:Bool=false,heading:Double=0,height:Double?=nil)->Step? {
        if chuting {return parachuteStep(delta,grounded:grounded)}
        if chute==State.landed.rawValue {elapsed += delta;if elapsed>=2.17 {chute=0}}
        return flying ? jetpackStep(delta,grounded:grounded,heading:heading,height:height):nil
    }
    private func parachuteStep(_ delta:Double,grounded:Bool)->Step {
        let ticks=25*delta,ease=1-pow(0.95,ticks)
        elapsed += delta
        if chute<=State.diveRight.rawValue {
            chuteRoll += (30*x-chuteRoll)*ease;lean += (-30*y-lean)*ease
            heading=Self.angle(heading-chuteRoll*Self.radians*0.2*ticks)
            let way=axes.forward;forward = -lean/30*32
            let drag=1-pow(0.99,ticks)
            velocity.x += (way.x*forward-velocity.x)*drag;velocity.z += (way.z*forward-velocity.z)*drag
            let falling=rise-20*delta
            rise=max(-30,falling*pow(max(0,1-abs(falling)/8750),50*delta))
            maximumFall=max(maximumFall,-rise)
            if abs(x)>0.3125 || abs(y)>0.3125 {
                chute=abs(x)>abs(y) ? (x>0 ? State.diveRight.rawValue:State.diveLeft.rawValue):(y>0 ? State.accelerate.rawValue:State.dive.rawValue)
            } else {chute=State.dive.rawValue}
            if open && !grounded {chute=State.opening.rawValue;elapsed=0;opening=Opening(lean:lean,roll:chuteRoll,forward:forward,rise:rise)}
        } else if chute==State.opening.rawValue {
            let fade=Self.clamp(1-elapsed/0.5),share=Self.clamp((elapsed-0.5)/2.33),start=opening!
            lean=start.lean*fade;chuteRoll=start.roll*fade
            forward=start.forward+(5-start.forward)*share;rise=start.rise+(-5-start.rise)*share
            let way=axes.forward;velocity=V(way.x*forward,0,way.z*forward)
            if share>=1 {chute=State.float.rawValue}
        } else {
            chuteRoll += (30*x-chuteRoll)*ease;lean=0
            heading=Self.angle(heading-chuteRoll*Self.radians*(1.0/15)*ticks)
            forward=5;let way=axes.forward;velocity=V(way.x*forward,0,way.z*forward)
            let turning=abs(x)>0.3125 && abs(x)>abs(y),slowing = !turning && y < -0.3125
            rise += ((slowing ? -1.5:-5)-rise)*ease
            chute=turning ? (x>0 ? State.steerRight.rawValue:State.steerLeft.rawValue):(slowing ? State.decelerate.rawValue:State.float.rawValue)
        }
        open=false
        let movement=V(velocity.x*delta,0,velocity.z*delta),rising=rise
        var landing:Landing?
        if grounded && elapsed>0.1 {
            let canopy=chute>=State.opening.rawValue
            landing=Landing(speed:canopy ? -rise:maximumFall,canopy:canopy,dead:canopy ? -rise>10:maximumFall>20)
            chute=canopy ? State.landed.rawValue:0;elapsed=0;lean=0;chuteRoll=0;velocity = .zero
        }
        return Step(move:movement,rise:rising,landed:landing)
    }
    private func jetpackStep(_ delta:Double,grounded:Bool,heading:Double,height:Double?)->Step? {
        let ticks=50*delta
        self.heading=Self.angle(self.heading+Self.clamp(Self.angle(heading-self.heading),-9*delta,9*delta))
        let direction=axes
        stopping=brake && !grounded
        jetVertical=stopping ? 0:down ? -1:up || y != 0 ? 1:0
        let target = -1.309*y*(grounded ? 128.0/60*0.3515625:1)
        jetPitch=stopping ? jetPitch*pow(0.9,ticks):target+(jetPitch-target)*pow(0.9,ticks)
        if stopping {jetRoll=0}
        else if x != 0 {jetRoll=Self.clamp(jetRoll+2.5*(x>0 ? 1:-1)*delta,-1,1)}
        else {jetRoll=abs(jetRoll)<=5*delta ? 0:jetRoll-5*(jetRoll>0 ? 1:-1)*delta}
        var force=V(0,-20,0)
        if stopping {
            force.y += 20
            let speed=simd_length(velocity)
            if speed<0.2 {velocity = .zero}else {force += velocity * (-10/speed)}
        } else {
            force.y += 20*(jetVertical>=0 ? 0.8:0.4)
            if jetVertical>0 {
                let thrust=0.6*20*Self.clamp(1-((height ?? 0)-100)/100)
                force += direction.forward * (-sin(jetPitch)*thrust);force.y += cos(jetPitch)*thrust
            }
            force += direction.right * (0.3*jetRoll*20)
        }
        velocity += force*delta
        velocity *= pow(max(0,1-simd_length(velocity)/50*0.02),ticks)
        if grounded && velocity.y<=0 {
            velocity = .zero
            if jetVertical<=0 {flying=false;jetPitch=0;jetRoll=0;return nil}
        }
        return Step(move:V(velocity.x*delta,0,velocity.z*delta),rise:velocity.y,landed:nil)
    }
}
