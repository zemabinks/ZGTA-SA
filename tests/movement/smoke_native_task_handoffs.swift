// Real original CLP clips + current extracted task coordinator + native Rapier.
// Controlled water surfaces and intent isolate the update-owner boundary.
@main enum TaskHandoffsGate {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let baseline=CommandLine.arguments[2]=="baseline",dt=1.0/60
        let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/models/animations.clips.bin")))!
        var checks=0,failures:[String]=[],cases:[[String:Any]]=[]
        func check(_ value:Bool,_ message:String) { checks += 1;if !value {failures.append(message)} }
        func frameDifference(_ a:NativeFootAnimation.Frame,_ b:NativeFootAnimation.Frame)->Double {
            guard a.blends.map(\.clip)==b.blends.map(\.clip) else{return 1000}
            return zip(a.blends,b.blends).reduce(0){max($0,max(abs($1.0.time-$1.1.time),abs($1.0.weight-$1.1.weight)))}
        }
        for owner in ["water","jetpack","parachute"] {
            let next=FixedVelocityHarness(library:library,mode:owner)
            next.footAirTime=1;next.footAirFall=29;next.footAirFell=true
            let airborne=NativeCharacterController.Output(feet:SIMD3(1480,0,100),grounded:false,rising:-12,eased:0,propped:false,pressed:[])
            if owner=="water" {next.waterEdge=1479}
            if owner=="jetpack" {next.personalFlight.takeOff(heading:0)}
            _=next.motion(delta:dt,state:airborne,intended:.init(displacement:.zero))
            check(next.footAirTime==0 && next.footAirFall==0 && !next.footAirFell,
                  "\(owner) inherited obsolete ordinary-foot fall damage history")
            check(next.health==100,"New movement owner applied obsolete foot fall damage")
        }
        for exit in ["missing-water","negative-depth","shallow-ground","haul-complete"] {
            let a=FixedVelocityHarness(library:library,mode:"water"),b=FixedVelocityHarness(library:library,mode:"water")
            a.waterEdge=1479;b.waterEdge=1479
            let state=NativeCharacterController.Output(feet:SIMD3(1480,0,100),grounded:false,rising:0,eased:0,propped:false,pressed:[])
            for _ in 0..<120 {
                _=a.motion(delta:dt,state:state,intended:.init(displacement:.zero))
                _=b.motion(delta:dt,state:state,intended:.init(displacement:.zero))
            }
            var departing=state
            if exit=="missing-water" {a.water=false}
            if exit=="negative-depth" {departing = .init(feet:SIMD3(1480,0,103),grounded:false,rising:0,eased:0,propped:false,pressed:[])}
            if exit=="shallow-ground" {
                departing = .init(feet:SIMD3(1480,0,101),grounded:true,rising:0,eased:0,propped:false,pressed:[])
                for _ in 0..<18 {
                    _=a.swimController.step(delta:dt,depth:1,grounded:true,heading:0)
                    _=b.swimController.step(delta:dt,depth:1,grounded:true,heading:0)
                }
            }
            if exit=="haul-complete" {
                for h in [a,b] {
                    _=h.swimController.step(delta:dt,depth:2,feet:SIMD3(1480,100,0),jump:true,ledge:{SIMD3(1480,102,0)})
                    for _ in 0..<47 {_=h.swimController.step(delta:dt,depth:2)}
                }
            }
            b.swimController.stop()
            _=a.motion(delta:dt,state:departing,intended:.init(displacement:.zero))
            // A successful outgoing task owns one update. A stopped task
            // hands that same tick to foot; it must not advance animation too.
            let expected=b.footAnimator!.update(delta:dt,input:.init(ratio:1))
            let difference=frameDifference(a.footAnimationFrame!,expected)
            check(!a.swimController.on,"\(exit): fixture did not exit swimming")
            check(difference<1e-12,"\(exit): outgoing swim advanced animation in the foot-owned tick")
            cases.append(["case":exit,"maximumBlendTimeOrWeightDifference":difference])
        }
        let flight=NativePersonalFlightController()
        flight.dive(velocity:SIMD3(2,-12,3),rising:-12,heading:3.13)
        flight.steer(open:true)
        _=flight.step(delta:dt)
        for _ in 0..<180 {_=flight.step(delta:dt)}
        let landing=flight.step(delta:dt,grounded:true)
        check(landing?.landed?.canopy==true && flight.state==10,"Canopy landing fixture failed")
        flight.wear(true);flight.steer(up:true);flight.takeOff(heading:-3.13,velocity:SIMD3(2,3,4))
        _=flight.step(delta:dt,heading:-3.13)
        let animation=NativeFlightAnimation(duration:library.duration(of:))
        let visual=animation.update(delta:dt,input:.init(state:flight.state,pitch:flight.pitch,roll:flight.roll),position:.zero,heading:0)
        check(flight.flying && (flight.state==12 || flight.state==13),"New jetpack task retained obsolete landed parachute phase")
        check(visual.jet?.visible==true && visual.canopy==nil,"New jetpack task rendered obsolete canopy instead of pack")
        cases.append(["case":"landed-canopy-to-jetpack","state":flight.state,"flying":flight.flying,"jetVisible":visual.jet?.visible ?? false,"canopy":visual.canopy != nil])
        // Exercise actual motor→Renderer water/foot/flight ownership across
        // display schedules, including a new jetpack during canopy/foot tails.
        // Compare fixed-tick root positions, facing, phases and real CLP times.
        var reference:FixedVelocityHarness?
        for rate in [30,60,120,0] {
            let run=FixedVelocityHarness(library:library,mode:"water")
            run.waterEdge=1479
            var clock=NativeGameFrameClock(),now=0.0,frames=0
            while run.ticks<240 {
                let frame=clock.advance(timestamp:now,active:true)
                for slice in frame.steps {
                    let before=run.character!.state.feet
                    let output=run.character!.update(delta:slice,displacement:.zero,geometryReady:true,motion:{dt,state,intended in
                        if run.ticks==120 {run.water=false}
                        if run.ticks==150 {
                            run.personalFlight.wear(true)
                            run.personalFlight.takeOff(heading:-Double(run.actorHeading),velocity:run.character!.stepVelocity)
                        }
                        return run.motion(delta:dt,state:state,intended:intended)
                    })
                    run.publish(start:before,camera:output.feet,delta:Float(slice))
                    check(run.character!.movementAvailable,"Valid scheduled motion unavailable")
                    check(run.character!.currentVelocity==run.character!.stepVelocity,"Scheduled observable/committed velocity differ")
                }
                now += rate>0 ? 1/Double(rate):[1.0/144,1.0/90,1.0/42,1.0/120,1.0/30][frames%5]
                frames += 1;check(frames<2000,"Task cadence fixture stalled")
            }
            if let reference {
                for tick in 0..<240 {
                    for (a,b) in zip(run.traces[tick],reference.traces[tick]) {check(abs(a-b)<1e-9,"\(rate)Hz task handoff body/state changed at tick\(tick)")}
                    check((run.poses[tick]["clips"] as! [String]) == (reference.poses[tick]["clips"] as! [String]),"Cadence changed a handoff clip")
                    for (a,b) in zip(run.poses[tick]["values"] as! [Double],reference.poses[tick]["values"] as! [Double]) {check(abs(a-b)<1e-9,"Cadence changed a handoff animation time/weight")}
                }
            } else {reference=run}
            check(run.traces[119][6]>0 && run.traces[120][6]>0,"Swim phase history absent")
            check(!run.swimController.on && run.personalFlight.flying,"Scheduled ownership did not complete water→foot→flight")
            cases.append(["case":"water-foot-flight","displayHz":rate==0 ? "uneven":String(rate),"frames":frames,"fixedTicks":run.ticks])
        }
        for wait in [0,30,120] {
            let old=NativePersonalFlightController(),fresh=NativePersonalFlightController()
            old.dive(velocity:SIMD3(1,0,2),rising:-12,heading:3.13);old.steer(open:true)
            for _ in 0..<181 {_=old.step(delta:dt)}
            _=old.step(delta:dt,grounded:true)
            for _ in 0..<wait {_=old.step(delta:dt)}
            let pose=NativeFlightAnimation(duration:library.duration(of:))
            _=pose.update(delta:dt,input:.init(state:old.state),position:.zero,heading:3.13)
            for pilot in [old,fresh] {
                pilot.wear(true);pilot.steer(x:0.5,y:0.25,up:true)
                pilot.takeOff(heading:-3.13,velocity:SIMD3(2,3,4))
                check(pilot.linearVelocity==SIMD3(2,3,4) && pilot.heading == -3.13 && pilot.worn,"Takeoff lost supplied physical state")
            }
            for tick in 0..<120 {
                let a=old.step(delta:dt,heading:3.13)!,b=fresh.step(delta:dt,heading:3.13)!
                check(a.move==b.move && a.rise==b.rise && old.heading==fresh.heading && old.state==fresh.state,
                      "Obsolete canopy contaminated new jetpack at wait\(wait)/tick\(tick)")
                let frame=pose.update(delta:dt,input:.init(state:old.state,pitch:old.pitch,roll:old.roll),position:.zero,heading:old.heading)
                check(frame.jet?.visible==true && frame.canopy==nil,"Old canopy remained after new flight owner")
            }
        }
        let h=FixedVelocityHarness(library:library,mode:"wall"),c=h.character!
        for _ in 0..<30 {_=c.update(delta:dt,displacement:.zero,geometryReady:true)}
        _=c.update(delta:dt,displacement:SIMD3(0.02,0,0),geometryReady:true)
        let velocity=c.stepVelocity,feet=c.state.feet
        check(velocity.x>0 && c.currentVelocity==velocity && c.movementAvailable,"Valid movement snapshot not available")
        _=c.update(delta:dt/2,displacement:.zero,geometryReady:true)
        check(c.currentVelocity==velocity && c.movementAvailable,"No-tick display frame erased committed movement")
        _=c.update(delta:dt,displacement:SIMD3(3,0,0),geometryReady:false)
        check(c.stepVelocity==velocity && c.state.feet==feet,"Geometry pause changed committed physical motion")
        check(c.currentVelocity == .zero && !c.movementAvailable,"Geometry pause exported stale observable speed")
        _=c.update(delta:dt/2,displacement:.zero,geometryReady:true)
        check(c.currentVelocity==velocity && c.movementAvailable,"Geometry resume lost committed snapshot before next tick")
        for invalid in [0.0,Double.nan,Double.infinity,0.6,-1] {
            _=c.update(delta:invalid,displacement:.zero,geometryReady:true)
            check(c.currentVelocity == .zero && !c.movementAvailable,"Invalid/suspended clock exposed stale movement")
            check(c.stepVelocity==velocity,"Invalid clock destroyed physical handoff velocity")
        }
        c.reset(feet:SIMD3(1480,0,3));check(c.currentVelocity == .zero && !c.movementAvailable,"Reset advertised an unstepped snapshot")
        _=c.update(delta:dt,displacement:.zero,geometryReady:true)
        let rising=c.state.rising,fall=c.stepVelocity
        c.cancelPendingInput()
        check(c.currentVelocity==fall && c.state.rising==rising,"Input cancellation erased physical motion")
        _=c.update(delta:dt,displacement:.zero,geometryReady:false)
        check(c.currentVelocity == .zero && c.state.rising==rising && c.stepVelocity==fall,"Geometry pause destroyed airborne momentum")
        c.setActive(false);check(c.currentVelocity == .zero && !c.movementAvailable,"Inactive ownership advertised movement")
        let report:[String:Any]=["authority":"Actual native Renderer task methods, real original CLP library and native Rapier; controlled water/intent; no retail runtime claim","mode":baseline ? "baseline":"verify","checks":checks,"failures":failures,"cases":cases]
        let output=root.appendingPathComponent("local-only/research/task-handoffs/\(baseline ? "baseline":"report").json")
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output)
        print("\(failures.isEmpty ? "PASS":"RECORDED FAILURE") task handoffs: \(checks) checks; \(failures.count) failed; \(output.path)")
        if !baseline {precondition(failures.isEmpty,failures.joined(separator:"\n"))}
    }
}
