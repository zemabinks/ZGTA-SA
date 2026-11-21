// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CoreGraphics

final class RendererBoundary {var rebases=0;func rebaseLegacyObjectClock(){rebases+=1}}
final class Controller {
    var frameClock=NativeGameFrameClock()
    var aiming=true,firePressed=true
    var stick=NativeVirtualStickState(),heldKeys=Set([4]),gate=NativeControllerInputGate()
    var resets=0
    var renderer:RendererBoundary?=RendererBoundary()
    func resetControls(){resets+=1;aiming=false;firePressed=false;stick.reset();heldKeys.removeAll();gate.reset()}
    func next(_ timestamp:Double,active:Bool=true)->NativeGameFrameClock.Frame {
        let timing=frameClock.advance(timestamp:timestamp,active:active)
        // ACTUAL_CONTROLLER_DISCONTINUITY
        return timing
    }
}
@main enum Main {
    static var checks=0
    static func check(_ value:Bool,_ message:String){checks+=1;if !value{print("FAIL \(message)");exit(1)}}
    static func main(){
        let c=Controller()
        c.stick.begin(at:CGPoint(x:50,y:50),bounds:CGRect(x:0,y:0,width:200,height:200));c.stick.move(to:CGPoint(x:50,y:6))
        _=c.gate.accepts(active:true,axes:[0],pressed:false)
        _=c.next(100)
        let stalled=c.next(100.7)
        check(c.resets==0 && c.aiming && c.firePressed,"Foreground hitch synthesized aim/fire release")
        check(!c.heldKeys.isEmpty && c.stick.active && c.stick.value.y == -1,"Foreground hitch discarded delivered key/touch input")
        check(!c.gate.needsNeutral,"Foreground hitch stranded a held controller behind neutral gate")
        check(stalled.delta==0 && stalled.steps.isEmpty && stalled.discontinuity,"Hitch accumulated a large physics command")
        check(c.renderer!.rebases==1,"Skipped simulation debt did not rebase external object clock")
        let resumed=c.next(100.7+1.0/60)
        check(abs(resumed.delta-1.0/60)<0.000001 && resumed.steps.count==1,"Following frame inherited hitch debt")
        check(c.aiming && c.resets==0,"Following frame dropped the retained aim latch")
        let boundary=Controller();_=boundary.next(10);let half=boundary.next(10.5)
        check(!half.discontinuity && half.steps.count==30 && abs(half.steps.reduce(0,+)-0.5)<0.000001,"Ordinary accepted0.5s boundary changed")
        let reverse=c.next(99)
        check(reverse.discontinuity && reverse.delta==0 && c.resets==1,"Clock reversal did not retire invalid input epoch")
        check(!c.aiming && !c.firePressed && c.heldKeys.isEmpty && !c.stick.active && c.gate.needsNeutral,"Actual reset boundary did not clear held inputs")
        for hz in [20,30,60,120] {
            var clock=NativeGameFrameClock();_=clock.advance(timestamp:10,active:true);var total=0.0
            for n in 1...hz {let f=clock.advance(timestamp:10+Double(n)/Double(hz),active:true);total+=f.delta;check(!f.discontinuity,"Ordinary display cadence reset input")}
            check(abs(total-1)<0.000001,"Ordinary low-FPS movement time was dropped")
        }
        print("PASS \(checks) actual frame-clock/controller-branch checks; authored clocks and control reset boundary, no UIKit/App/retail claim")
    }
}
