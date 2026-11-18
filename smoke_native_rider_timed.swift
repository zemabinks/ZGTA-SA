// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
import Darwin

@main enum RiderTimedSmoke {
    typealias F=RiderClockSmoke
    typealias Fixture=(NativeRiderDefinitions.Definition,NativeSkeletalAnimationLibrary,[String:Double])
    struct Failure:Error {let message:String}
    static var checks=0,negativeWitnesses:[[String:Double]]=[]
#if HISTORICAL_CONTROLS
    static let historicalExecuted=true
#else
    static let historicalExecuted=false
#endif
    static func check(_ value:Bool,_ message:String)throws {
        checks+=1;if !value{throw Failure(message:message)}
    }
    static func near(_ a:Double,_ b:Double,_ message:String,_ tolerance:Double=1e-9)throws {
        try check(a.isFinite && b.isFinite && abs(a-b)<=tolerance,message)
    }
    static func interval(_ start:Double,_ end:Double)->NativeRiderPoseClock.Interval {
        .init(start:start,end:end,rejection:nil)
    }
    static func delta(_ interval:NativeRiderPoseClock.Interval,command:Double=0)throws->Double {
        switch interval.admission(commandAt:command) {
        case .elapsed(let value):return value
        case .rejected:throw Failure(message:"unexpected rejected interval")
        }
    }
    static func rejected(_ interval:NativeRiderPoseClock.Interval,command:Double=0)throws {
        switch interval.admission(commandAt:command) {
        case .rejected:try check(true,"rejected")
        case .elapsed:throw Failure(message:"rejected sample flattened to valid zero")
        }
    }
    static func capture(_ a:NativeRiderPlayback.Capture?,_ b:NativeRiderPlayback.Capture?)throws {
        switch (a,b) {
        case (nil,nil):try check(true,"nil capture")
        case (.current?,.current?):try check(true,"current capture")
        case (.sample(let a)?,.sample(let b)?):
            try pose(a.pose,b.pose);try check(simd_distance(a.anchor,b.anchor)<1e-9,"captured anchor")
        default:throw Failure(message:"capture kind or event lost")
        }
    }
    static func pose(_ a:NativeRiderAnimation.Frame,_ b:NativeRiderAnimation.Frame)throws {
        try check(a.base==b.base,"sample base");try near(a.time,b.time,"sample time")
        try check(a.mixes.count==b.mixes.count,"sample mixes count")
        for (x,y) in zip(a.mixes,b.mixes) {
            try check(x.clip==y.clip,"mix clip");try near(x.time,y.time,"mix time");try near(x.weight,y.weight,"mix weight")
        }
    }
    static func frame(_ a:NativeRiderPlayback.Frame,_ b:NativeRiderPlayback.Frame)throws {
        try pose(a.sample.pose,b.sample.pose)
        try check(simd_distance(a.sample.anchor,b.sample.anchor)<1e-9,"final anchor")
        try near(a.turn,b.turn,"final turn");try capture(a.capture,b.capture)
        try check(a.captureSerial==b.captureSerial,"capture serial")
        try near(a.transition,b.transition,"final transition")
        try check(a.transitioning==b.transitioning,"final transitioning flag")
        try check(a.doorPart==b.doorPart,"final held door")
        try near(a.doorOpen,b.doorOpen,"final door angle")
        try check(a.state==b.state,"final state")
        if let x=a.releasedDoor,let y=b.releasedDoor {
            try check(x.0==y.0,"released part");try near(x.1,y.1,"released angle")
        } else {try check(a.releasedDoor==nil && b.releasedDoor==nil,"terminal release lost")}
    }
    static func consumed(_ value:NativeRiderPlayback,_ steps:[Double],input:NativeRiderAnimation.Input = .init())throws->NativeRiderPlayback.Frame {
        var last:NativeRiderPlayback.Frame?,held:NativeRiderPlayback.Capture?,release:(Int,Double)?
        for step in steps {
            guard let row=value.update(delta:step,input:input) else{throw Failure(message:"direct state missing")}
            last=row
            if let event=row.capture{held=event}
            if let event=row.releasedDoor{release=event}
        }
        guard var last else{throw Failure(message:"empty authored schedule")}
        last.capture=held;last.releasedDoor=release
        return last
    }
    static func clockChecks()throws {
        var clock=NativeRiderPoseClock()
        try near(delta(clock.interval(at:100,active:true),command:100),0,"first frame zero")
        let ordinary=clock.interval(at:100.2,active:true)
        try near(delta(ordinary,command:99),0.2,"full old command interval")
        try near(delta(ordinary,command:100.19),0.01,"late command intersection")
        try near(delta(ordinary,command:100.2),0,"same frame new command")
        try rejected(ordinary,command:100.21)
        try rejected(ordinary,command:.nan)
        let long=clock.interval(at:101,active:true)
        try rejected(long);try rejected(long,command:101);try rejected(long,command:100.9)
        try near(delta(clock.interval(at:101.02,active:true)),0.02,"long sample not queued")
        try rejected(clock.interval(at:101,active:true))
        try near(delta(clock.interval(at:101.03,active:true)),0.03,"backward clock rebase")
        try rejected(clock.interval(at:.infinity,active:true))
        try near(delta(clock.interval(at:104,active:true)),0,"nonfinite resets baseline")
        try rejected(clock.interval(at:104.1,active:false))
        try near(delta(clock.interval(at:109,active:true)),0,"inactive time discarded")
        try near(delta(clock.interval(at:109.04,active:true)),0.04,"active time after first resume")
        clock.reset(at:120)
        try near(delta(clock.interval(at:120.02,active:true)),0.02,"explicit resume floor")
        clock.reset();try near(delta(clock.interval(at:150,active:true)),0,"session reset fresh frame")
        clock.reset(at:.nan);try near(delta(clock.interval(at:151,active:true)),0,"invalid reset fresh frame")
        var exact=NativeRiderPoseClock();_=exact.interval(at:0,active:true)
        try near(delta(exact.interval(at:0.5,active:true)),0.5,"half second admitted")
        try rejected(exact.interval(at:1.0000001,active:true),command:1.0000001)
    }
    static func exactSingleCallChecks()throws {
        let fixture=try F.fixture(F.authored)
        for dt in [0,Double.leastNonzeroMagnitude,0.0001,0.025,0.1.nextDown,0.1] {
            let timed=try F.playback(fixture),direct=try F.playback(fixture)
            timed.enter(at:0,side:-1);direct.enter(side:-1)
            let a=timed.update(interval:interval(0,dt),input:.init())!
            let b=direct.update(delta:dt,input:.init())!
            try frame(a,b)
            try frame(timed.update(interval:interval(dt,dt),input:.init())!,direct.update(delta:0,input:.init())!)
        }
        let untimed=try F.playback(fixture)
        untimed.enter(side:-1)
        let first=untimed.update(interval:interval(5,5.2),input:.init())!
        try near(first.sample.pose.time,0,"untimed migration primes at draw")
        let next=untimed.update(interval:interval(5.2,5.4),input:.init())!
        try near(next.sample.pose.time,0.2,"untimed migration next interval")
        untimed.leave(side:-1)
        let fresh=untimed.update(interval:interval(5.4,5.6),input:.init())!
        try near(fresh.sample.pose.time,0,"untimed replacement invalidates old epoch")
    }
    static func wrapperChecks()throws {
        let fixtures=[try F.fixture(F.authored),try F.fixture(["open":0.03125,"getIn":0.0625,"closeIn":0.03125,"getOut":0.03125,"closeOut":0.03125]),try F.fixture([:])]
        let schedules:[(Double,[Double])] = [
            (0.1.nextUp,[0.1,0.1.nextUp-0.1]),(0.125,[0.1,0.025]),(0.2,[0.1,0.1]),
            (0.3.nextDown,[0.1,0.1,0.3.nextDown-0.2]),(0.3,[0.1,0.1,0.3-0.2]),
            (0.1*3,[0.1,0.1,0.1]),(0.5.nextDown,[0.1,0.1,0.1,0.1,0.5.nextDown-0.4]),
            (0.5,[0.1,0.1,0.1,0.1,0.5-0.4])]
        for fixture in fixtures {
            for leave in [false,true] {
                for (dt,steps) in schedules {
                    let timed=try F.playback(fixture),direct=try F.playback(fixture)
                    if leave {timed.sit(at:0);timed.leave(at:0,side:-1);direct.sit();direct.leave(side:-1)}
                    else{timed.enter(at:0,side:-1);direct.enter(side:-1)}
                    let actual=timed.update(interval:interval(0,dt),input:.init())!
                    let expected=try consumed(direct,steps)
                    try frame(actual,expected)
                    let next=timed.update(interval:interval(dt,dt),input:.init())!
                    try check(next.capture==nil && next.releasedDoor==nil,"folded events do not replay")
                    try check(next.captureSerial==actual.captureSerial,"serial stable after folded event")
                }
            }
        }
        // Current capture must survive an earlier slice even with no boundary.
        let current=try F.playback(fixtures[0]);current.sit(at:0);current.leave(at:0,side:-1)
        let leaving=current.update(interval:interval(0,0.2),input:.init())!
        if case .current?=leaving.capture{try check(true,"current preserved")}else{throw Failure(message:"current capture lost across slices")}
        // Multiple boundaries finish before the last slice. Final fields win;
        // the last exact outgoing capture and terminal door release still win.
        let tiny=try F.playback(fixtures[1]);tiny.enter(at:0,side:-1)
        let final=tiny.update(interval:interval(0,0.5),input:.init())!
        try check(final.state == .inside && !final.transitioning && final.doorPart==nil,"final frame semantics after early completion")
        try near(final.transition,1,"final transition after early completion")
        try check(final.releasedDoor?.0==2 && final.captureSerial==4,"release/serial across slices")
        if case .sample(let sample)?=final.capture {
            try check(sample.pose.base=="invented/closein","last capture source phase")
            try near(sample.pose.time,0.03125,"exact final outgoing sample")
        }else{throw Failure(message:"last raw sample capture missing")}
        // No injected callback occurs inside Playback: the literal caller only
        // enqueues once after receiving the folded final Frame.
        let carrier=RendererCarrier();carrier.ownRiderPlayback=tiny;carrier.now=0.5
        var completions=0
        try check(carrier.beginVehicleExit{completions+=1},"literal local exit admission")
        let stood=tiny.update(interval:interval(0.5,1),input:.init())!
        try check(completions==0 && DispatchQueue.main.queued.isEmpty,"no inter-slice callback")
        carrier.consumeDriver(stood)
        try check(carrier.pendingVehicleExit==nil && DispatchQueue.main.queued.count==1 && completions==0,"once-only deferred completion")
        try check(carrier.groundVehicle!.damageController!.state.releases.count==1,"terminal physical release once")
        let hold=tiny.update(interval:interval(1,1),input:.init())!
        carrier.consumeDriver(hold)
        try check(DispatchQueue.main.queued.count==1 && carrier.groundVehicle!.damageController!.state.releases.count==1,"completion/release not replayed")
        DispatchQueue.main.flush();try check(completions==1,"completion delivered once")
        carrier.pendingVehicleExit={completions+=1};carrier.consumePassenger(hold)
        try check(DispatchQueue.main.queued.count==1 && completions==1,"passenger completion stays deferred")
        DispatchQueue.main.flush();try check(completions==2,"passenger deferred completion once")
    }
    static func rejectedChecks()throws {
        let zero=try F.fixture(["open":0,"getIn":0,"closeIn":0,"getOut":0,"closeOut":0])
        for commandAt in [0,1,0.9] {
            let value=try F.playback(zero);value.enter(at:commandAt,side:-1)
            var clock=NativeRiderPoseClock();_=clock.interval(at:0,active:true)
            let rejected=value.update(interval:clock.interval(at:1,active:true),input:.init())!
            try check(rejected.state == .entering && rejected.captureSerial==1,"long global gap/new epoch drains empty phases")
            let admitted=value.update(interval:clock.interval(at:1.1,active:true),input:.init())!
            try check(admitted.state == .inside && admitted.captureSerial==4,"next admitted time drains empty phases")
        }
#if HISTORICAL_CONTROLS
        let historical=HistoricalRiderPlayback(definition:zero.0,library:zero.1)!,oldClock=HistoricalRendererCarrier()
        _=oldClock.successfulDraw(at:100);historical.enter()
        try check(historical.update(delta:oldClock.successfulDraw(at:101),input:.init())!.state == .inside,"literal historical long-gap/empty-phase negative")
#endif
        for bad in [Double.nan,Double.infinity,-0.1,0,0.1,0.5000001] {
            let value=try F.playback(zero);value.enter(at:0,side:-1)
            let invalid=NativeRiderPoseClock.Interval(start:0,end:0,rejection:bad)
            let first=value.update(interval:invalid,input:.init())!
            try check(first.state == .entering && first.captureSerial==1,"rejected sentinel became valid zero")
            let valid=value.update(interval:interval(0,0),input:.init())!
            try check(valid.state == .inside && valid.captureSerial==4,"genuine valid zero remains valid")
        }
        let f=try F.fixture(F.authored),value=try F.playback(f)
        value.enter(at:0);_=value.update(interval:interval(0,0.2),input:.init())
        let before=value.update(interval:interval(0.2,0.2),input:.init())!
        for bad in [Double.nan,Double.infinity,-0.1,0.500001] {
            let held=value.update(interval:.init(start:0.2,end:0.2,rejection:bad),input:.init())!
            try frame(held,before)
        }
    }
    static func rateChecks()throws {
        let f=try F.fixture(["open":10,"getIn":10,"closeIn":10])
        for rate in [5,8,10,15,60,120] {
            let current=try F.playback(f),clock=RendererCarrier()
            clock.now=100;let first=clock.successfulDraw()
            current.enter(at:first.0)
            _=current.update(interval:first.2,input:.init())
#if HISTORICAL_CONTROLS
            let old=HistoricalRiderPlayback(definition:f.0,library:f.1)!,oldClock=HistoricalRendererCarrier()
            old.enter()
            _=old.update(delta:oldClock.successfulDraw(at:100),input:.init())
            var historical:HistoricalRiderPlayback.Frame!
#endif
            var final:NativeRiderPlayback.Frame!
            for frame in 1...rate {
                clock.now=100+Double(frame)/Double(rate);let step=clock.successfulDraw()
                final=current.update(interval:step.2,input:.init())!
#if HISTORICAL_CONTROLS
                historical=old.update(delta:oldClock.successfulDraw(at:clock.now),input:.init())!
#endif
                try check(step.1<=0.1,"shared fallback clock still capped")
            }
            try near(final.sample.pose.time,1,"admitted finite phase elapsed at \(rate)Hz")
#if HISTORICAL_CONTROLS
            let expected=min(1,Double(rate)*0.1)
            try near(historical.sample.pose.time,expected,"literal historical cap witness")
            if rate<10{try check(historical.sample.pose.time<final.sample.pose.time-0.1,"historical negative must fail corrected elapsed contract")}
            else{try near(historical.sample.pose.time,final.sample.pose.time,"ordinary historical control")}
            negativeWitnesses.append(["authoredRate":Double(rate),"currentPhaseSeconds":final.sample.pose.time,"historicalPhaseSeconds":historical.sample.pose.time])
#else
            negativeWitnesses.append(["authoredRate":Double(rate),"currentPhaseSeconds":final.sample.pose.time])
#endif
        }
        let clock=RendererCarrier(),value=try F.playback(f)
        clock.now=10;_=clock.successfulDraw();value.enter(at:10)
        for dt in [0.2,0.125,0.03,0.1,0.005,0.24,0.3] {clock.now+=dt;_=value.update(interval:clock.successfulDraw().2,input:.init())}
        try near(value.update(interval:interval(clock.now,clock.now),input:.init())!.sample.pose.time,1,"jitter full finite time")
    }
    static func rendererOwnershipChecks()throws {
        let f=try F.fixture(F.authored),clock=RendererCarrier()
        clock.riderDefinitions = .init(models:["invented":f.0])
        clock.now=100;_=clock.successfulDraw()
        let own=try F.playback(f);own.sit(at:100);clock.ownRiderPlayback=own
        var ready=0;clock.now=100.19
        try check(clock.beginVehicleExit{ready+=1},"late local input admitted")
        clock.now=100.2;let step=clock.successfulDraw()
        let leaving=own.update(interval:step.2,input:.init())!
        try near(leaving.sample.pose.time,0.01,"literal local leave epoch")
#if HISTORICAL_CONTROLS
        let old=HistoricalRiderPlayback(definition:f.0,library:f.1)!,oldClock=HistoricalRendererCarrier()
        _=oldClock.successfulDraw(at:100);old.sit();old.leave()
        try near(old.update(delta:oldClock.successfulDraw(at:100.2),input:.init())!.sample.pose.time,0.1,"literal historical late-command precredit negative")
#endif
        try check(clock.beginVehicleExit{ready+=100},"duplicate exit acknowledges pending owner")
        clock.now=100.4
        try near(own.update(interval:clock.successfulDraw().2,input:.init())!.sample.pose.time,0.21,"duplicate input does not reset epoch")
        try check(ready==0,"no premature local completion")
        clock.pendingVehicleExit=nil;clock.driving=false
        try check(!clock.beginVehicleExit{ready+=100},"revoked local owner rejects exit")
        // Fresh local owners admitted by actual draw command blocks start at
        // zero even when the global interval contains older active time.
        let local=RendererCarrier();local.now=1;_=local.successfulDraw();local.now=1.2
        var s=local.successfulDraw()
        let driver=local.ownDriver(s.2,at:s.0,age:0.2,definition:f.0,library:f.1)!
        try near(driver.sample.pose.time,0,"new local driver cannot consume precreation time")
        local.ownRiderPlayback=nil;local.passengerSeat=1;local.now=1.4;s=local.successfulDraw()
        let passenger=local.ownPassenger(s.2,at:s.0,definition:f.0,library:f.1)!
        try near(passenger.sample.pose.time,0,"new local passenger cannot consume precreation time")
        local.ownRiderPlayback=nil;local.now=1.6;s=local.successfulDraw()
        try check(local.ownDriver(s.2,at:s.0,age:4,definition:f.0,library:f.1)!.state == .inside,"old-entry sit policy preserved")
        // Same-frame commands replace the epoch and latest state, including
        // leave->enter and sit cancellation. Death is current input, not debt.
        let commands=try F.playback(f)
        commands.enter(at:2);commands.leave(at:2)
        let exit=commands.update(interval:interval(1.8,2),input:.init(dead:true))!
        try check(exit.state == .leaving,"same-frame enter/leave latest state")
        try near(exit.sample.pose.time,0,"same-frame leave zero age")
        if case .current?=exit.capture{}else{throw Failure(message:"same-frame current capture")}
        commands.enter(at:2.1);let enter=commands.update(interval:interval(2,2.1),input:.init())!
        try check(enter.state == .entering,"same-frame reentry owns new queue");try near(enter.sample.pose.time,0,"new entry epoch")
        commands.sit(at:2.1);let seated=commands.update(interval:interval(2,2.1),input:.init(dead:true))!
        try check(seated.state == .inside && seated.capture==nil && seated.doorPart==nil,"sit cancellation owns final frame")
        var deadFixture=try F.fixture(["deadLeft":1,"open":1,"getIn":1,"closeIn":1])
        deadFixture.0.clips["deadLeft"]="invented/deadleft"
        let dead=try F.playback(deadFixture);dead.sit(at:0)
        try check(dead.update(interval:interval(0,0.2),input:.init(dead:true))!.sample.pose.base=="invented/deadleft","latest dead input kept across slices")
        // Foreground rebase through the literal Renderer lifecycle method.
        local.now=10;local.resetDisplayClock();local.now=10.02
        try near(delta(local.successfulDraw().2),0.02,"literal resume floor")
        try check(local.renderClock.resets==1,"existing render clock still resets")
        UIApplication.shared.applicationState = .inactive;local.now=10.1
        try rejected(local.successfulDraw().2)
        UIApplication.shared.applicationState = .active;local.now=13;local.resetDisplayClock();local.now=13.03
        try near(delta(local.successfulDraw().2),0.03,"no suspension debt after return")
        local.clearPoseClock();local.now=20
        let cleared=local.successfulDraw()
        try near(delta(cleared.2),0,"literal multiplayer reset clears pose history")
        try near(cleared.1,0,"existing shared clock reset preserved")
        try check(local.remoteServerTimeOffsetMilliseconds==nil,"existing server clock reset preserved")
    }
    static func remoteChecks()throws {
        let f=try F.fixture(F.authored)
        for driver in [false,true] {
            let carrier=RendererCarrier();var player=Player(),actor=Actor()
            func draw(_ time:Double,consume:Bool=true,model:String="invented")->NativeRiderPlayback.Frame? {
                carrier.now=time;let s=carrier.successfulDraw()
                guard consume else{return nil}
                if driver{return carrier.driver(s.2,at:s.0,player:player,model:model,actor:actor,source:f.0,library:f.1)}
                return carrier.passenger(s.2,at:s.0,player:player,vehicleID:player.vehicleID!,model:model,actor:actor,definition:f.0,library:f.1)
            }
            _=draw(100,consume:false)
            try near(draw(100.2)!.sample.pose.time,0,"new remote command zero age")
            try near(draw(100.4)!.sample.pose.time,0.2,"duplicate action does not reset")
            player.action=0
            try near(draw(100.45)!.sample.pose.time,0.25,"ignored default while entering preserves epoch")
            _=draw(100.6,consume:false);_=draw(100.8,consume:false)
            try near(draw(101)!.sample.pose.time,0.45,"culled/resource owner receives latest global interval only")
            // No successful draws were made during this gap. It is admitted
            // globally through0.5; no per-owner previous-visible clock exists.
            try near(draw(101.2)!.sample.pose.time,0.65,"failed draw does not consume a clock sample")
            let held=draw(102)!
            try near(held.sample.pose.time,0.65,"long active gap holds phase")
            actor=Actor()
            try near(draw(102.2)!.sample.pose.time,0,"actor replacement creates a fresh owner")
            player.vehicleID="replacement"
            try near(draw(102.4)!.sample.pose.time,0,"vehicle replacement creates fresh owner")
            if !driver {player.ridingSeat=0;try near(draw(102.6)!.sample.pose.time,0,"seat replacement creates fresh owner")}
            try near(draw(102.8,model:"replacement-model")!.sample.pose.time,0,"model replacement creates fresh owner")
            player.action=2
            try near(draw(103)!.sample.pose.time,0,"new remote leave starts at admission")
            try check(carrier.remoteRiderPlayback[player.id]!.1.state == .leaving,"remote latest leave state")
            player.action=1;player.life=0
            try near(draw(103.2)!.sample.pose.time,0,"dead input does not age a new command")
        }
    }
    static func queuedExitOwnershipChecks()throws {
        let f=try F.fixture(["open":0.03125,"getIn":0.03125,"closeIn":0.03125,"getOut":0.03125,"closeOut":0.03125])
#if HISTORICAL_CONTROLS
        let historical=RendererCarrier(),old=try F.playback(f)
        historical.ownRiderPlayback=old;old.sit()
        var staleCompletions=0
        _=historical.beginHistoricalVehicleExit{staleCompletions+=1}
        historical.consumeDriver(old.update(delta:0.2,input:.init())!)
        let stale=DispatchQueue.main.queued.removeFirst(),replacement=try F.playback(f)
        replacement.sit(at:0.2);historical.admitOwnerForTest(replacement)
        stale()
        try check(staleCompletions==1,"literal historical dequeued callback reaches replacement negative")
#endif
        for passenger in [false,true] {
            let carrier=RendererCarrier(),playback=try F.playback(f)
            carrier.ownRiderPlayback=playback;playback.sit(at:0);carrier.now=0
            var completions=0
            try check(carrier.beginVehicleExit{completions+=1},"normal queued exit admitted")
            let frame=playback.update(interval:interval(0,0.2),input:.init())!
            try check(frame.state == .stood,"actual exit phases complete before queue")
            if passenger {carrier.consumePassenger(frame);carrier.consumePassenger(frame)}
            else {carrier.consumeDriver(frame);carrier.consumeDriver(frame)}
            try check(DispatchQueue.main.queued.count==1 && completions==0,"one deferred completion for repeated final frame")
            DispatchQueue.main.flush()
            try check(completions==1,"unchanged owner completion delivered once")
        }
        // The ready closure is removed from pendingVehicleExit by the actual
        // caller before each invalidation. Clearing pending alone cannot save
        // it; its captured generation, object identity and driving must guard it.
        for mode in ["reset","placement","new-driver-same-id","new-passenger-same-id","identity-only","driving-only"] {
            let carrier=RendererCarrier(),old=try F.playback(f)
            carrier.ownRiderPlayback=old;old.sit(at:0);carrier.now=0
            var completions=0
            _=carrier.beginVehicleExit{completions+=1}
            let stood=old.update(interval:interval(0,0.2),input:.init())!
            carrier.consumeDriver(stood)
            try check(carrier.pendingVehicleExit==nil && DispatchQueue.main.queued.count==1,"old exit has already been dequeued")
            let dequeued=DispatchQueue.main.queued.removeFirst(),serial=carrier.vehicleExitSerial
            let replacement=try F.playback(f);replacement.sit(at:0.2)
            switch mode {
            case "reset":carrier.resetOwnerForTest();try check(carrier.vehicleExitSerial != serial,"actual reset discard advances generation");carrier.admitOwnerForTest(replacement)
            case "placement":carrier.revokeVehicleForServerPlacement();try check(carrier.vehicleExitSerial != serial,"actual authoritative TP revoke advances generation");carrier.admitOwnerForTest(replacement)
            case "new-driver-same-id":carrier.admitOwnerForTest(replacement);try check(carrier.vehicleExitSerial != serial,"actual driver-enter reset advances generation")
            case "new-passenger-same-id":carrier.admitOwnerForTest(replacement,passenger:true);try check(carrier.vehicleExitSerial != serial,"actual passenger-enter reset advances generation")
            case "identity-only":carrier.ownRiderPlayback=replacement;try check(carrier.vehicleExitSerial==serial,"identity-only adversarial fixture")
            default:carrier.driving=false;try check(carrier.ownRiderPlayback === old && carrier.vehicleExitSerial==serial,"driving-only adversarial fixture")
            }
            if carrier.driving {try check(carrier.currentVehicleID=="same-id","same vehicle identifier intentionally retained")}
            dequeued()
            try check(completions==0,"stale dequeued exit reached a replacement owner: "+mode)
        }
        var owner:RendererCarrier?=RendererCarrier()
        owner!.ownRiderPlayback=try F.playback(f);owner!.ownRiderPlayback!.sit(at:0)
        var completions=0
        _=owner!.beginVehicleExit{completions+=1}
        let stood=owner!.ownRiderPlayback!.update(interval:interval(0,0.2),input:.init())!
        owner!.consumeDriver(stood)
        let dequeued=DispatchQueue.main.queued.removeFirst()
        weak var releasedPlayback=owner!.ownRiderPlayback
        weak var releasedOwner=owner
        owner=nil
        try check(releasedOwner==nil && releasedPlayback==nil,"queued callback does not retain retired renderer or playback")
        dequeued();try check(completions==0,"disposed owner callback is harmless")
    }
    static func main() {
        do {
            try clockChecks();try exactSingleCallChecks();try wrapperChecks();try rejectedChecks()
            try rateChecks();try rendererOwnershipChecks();try remoteChecks();try queuedExitOwnershipChecks()
            let result:[String:Any]=["status":"PASS","checks":checks,"fixtureChecks":F.checks,
                "authoredRateWitnesses":negativeWitnesses,
                "literalHistoricalWitnesses":historicalExecuted ? negativeWitnesses:[],"actualPlaybackAndCLP1":true,
                "historicalExecuted":historicalExecuted,"literalHistoricalQueuedExitWitness":historicalExecuted,
                "literalRendererClockCommandsCacheAndCompletion":true,"renderedOrRetailAcceptance":false]
            print(String(data:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),encoding:.utf8)!)
        }catch {
            let reason=(error as? Failure)?.message ?? String(describing:error)
            let result:[String:Any]=["status":"FAIL","checks":checks,"fixtureChecks":F.checks,"failure":reason]
            print(String(data:try! JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),encoding:.utf8)!)
            exit(1)
        }
    }
}
