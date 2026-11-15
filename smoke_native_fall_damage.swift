private extension ClimbRuntimeHarness {
    func fallMotionForTest(delta:Double,state:NativeCharacterController.Output,intended:NativeCharacterController.Motion) -> NativeCharacterController.Motion {
        footMotion(delta:delta,state:state,intended:intended,forward:0,sideways:0,running:false)
    }
}

@main enum FallDamageGate {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),folder=root.appendingPathComponent("local-only/research/fall-damage")
        let reference=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("reference.json"))) as! [String:Any]
        var checks=0,reports:[[String:Any]]=[]
        func check(_ value:Bool,_ message:String){checks += 1;precondition(value,message)}
        for row in reference["rows"] as! [[String:Any]] {
            let v=(row["fastest"] as! NSNumber).doubleValue,h=(row["horizontal"] as! NSNumber).doubleValue
            let expected=(row["damage"] as! NSNumber).doubleValue,actual=NativeFallDamage.amount(fastest:v,horizontal:h)
            check(abs(actual-expected)<1e-10,"Actual archived landing expression mismatch at \(v)/\(h)")
            if actual>0 {check((row["weapon"] as! NSNumber).intValue==54 && (row["count"] as! NSNumber).intValue==1,"Reference damage lost environmental weapon/event identity")}
            for (index,health) in [0,1,18,25,100].enumerated() {
                let expected=(row["health"] as! [[String:Any]])[index]
                check(NativeFallDamage.health(after:actual,current:health)==(expected["health"] as! NSNumber).intValue,"Actual archived hurt/death/health boundary changed")
                check((expected["armour"] as! NSNumber).intValue==25,"Actual environmental fall hurt consumed armour")
            }
        }
        for invalid in [-1.0,Double.nan,Double.infinity] {
            check(NativeFallDamage.amount(fastest:invalid,horizontal:40)==0,"Invalid downward sample accepted")
            check(NativeFallDamage.amount(fastest:40,horizontal:invalid)==0,"Invalid horizontal sample accepted")
        }
        check(NativeFallDamage.health(after:17.2,current:18)==0,"Wire rounding revived a fatal sub-one-health result")
        // Native integration must sample the preceding requested horizontal
        // speed even though the grounded motor has stopped. Exercise exact
        // threshold edges, repeated contacts and already-dead ownership.
        for (peak,horizontal) in [(18.75,0.0),(18.750000001,0),(10,33),(10,33.000000001),(20,0),(30,0),(30.000000001,0)] {
            let actor=try ClimbRuntimeHarness(root:root,top:1.8,depth:2)
            actor.footLaunchRemaining=nil;actor.equippedWeapon=0
            actor.footAirTime=0.5;actor.footAirFall=peak;actor.footAirFell=true
            actor.footAirVelocity=SIMD2(horizontal,0)
            var events:[Int]=[];actor.onLocalHealth={events.append($0)}
            let grounded=NativeCharacterController.Output(feet:SIMD3(10,0,0.02),grounded:true,rising:0,eased:0,propped:false,pressed:[])
            let expected=NativeFallDamage.health(after:NativeFallDamage.amount(fastest:peak,horizontal:horizontal),current:100)
            for _ in 0..<60 {_=actor.fallMotionForTest(delta:1/60,state:grounded,intended:.init(displacement:.zero))}
            check(actor.health==expected && events==(expected<100 ? [expected]:[]),"Grounded collision erased horizontal impact or repeated a landing event")
            check(actor.footAirFall==0 && actor.footAirTime==0,"Consumed landing retained fall history")
            actor.health=0;actor.footAirTime=0.5;actor.footAirFall=50
            _=actor.fallMotionForTest(delta:1/60,state:grounded,intended:.init(displacement:.zero))
            check(events.count==(expected<100 ? 1:0),"Already-dead task emitted new fall damage")
        }
        // Three real floor drops exercise zero, nonfatal and fatal outcomes.
        // Every frame uses the actual current footMotion, real CLP animation
        // and native character motor; compare canonical fixed-tick traces.
        for height:Float in [3,10,30] {
            var referenceTrace:[[Double]]?
            for rate in [30,60,120,0] {
                let actor=try ClimbRuntimeHarness(root:root,top:1.8,depth:2)
                actor.footLaunchRemaining=nil;actor.equippedWeapon=0
                actor.character!.reset(feet:SIMD3(10,0,height),grounded:false)
                var healthEvents:[Int]=[],trace:[[Double]]=[],ticks=0,display=0,fastest=0.0,landed=false
                // Armour belongs to the network inventory, not this health
                // callback. The integration must publish only new health.
                actor.onLocalHealth={healthEvents.append($0)}
                while ticks<360 {
                    let delta=rate>0 ? 1/Double(rate):[1.0/144,1.0/90,1.0/42,1.0/120,1.0/30][display%5]
                    _=actor.character!.update(delta:delta,displacement:.zero,geometryReady:true,motion:{dt,state,intended in
                        fastest=max(fastest,-state.rising)
                        // Modal/input loss must preserve real airborne fall
                        // history, while cancelling only pending commands.
                        if ticks==15 {actor.cancelGameplayInput()}
                        let motion=actor.fallMotionForTest(delta:dt,state:state,intended:intended)
                        trace.append([Double(state.feet.z),state.rising,Double(actor.health),actor.footAirTime,actor.footAirFall])
                        ticks += 1;if state.grounded {landed=true}
                        return motion
                    })
                    display += 1;check(display<3000,"Drop fixture stalled")
                }
                let expectedDamage=NativeFallDamage.amount(fastest:fastest,horizontal:0)
                let expectedHealth=NativeFallDamage.health(after:expectedDamage,current:100)
                check(landed && actor.health==expectedHealth,"Actual native landing did not apply expected health")
                check(healthEvents==(expectedHealth<100 ? [expectedHealth]:[]),"Landing health was missing or published repeatedly")
                check(actor.footAnimator!.dead==(expectedHealth==0),"Fatal landing did not own death animation immediately")
                if let referenceTrace {
                    for tick in 0..<360 {for (a,b) in zip(trace[tick],referenceTrace[tick]) {check(abs(a-b)<1e-9,"Display schedule changed fall state/damage at tick\(tick)")}}
                } else {referenceTrace=trace}
                reports.append(["height":height,"displayHz":rate==0 ? "uneven":String(rate),"health":actor.health,
                                "maximumTrackedDownwardSpeed":fastest,"healthEvents":healthEvents,"ticks":ticks])
            }
        }
        // Landing consumes its fall history once. A fresh unrelated position
        // starts without an obsolete peak, using the actual task reset path.
        let climb=try ClimbRuntimeHarness(root:root,top:1.8,depth:2)
        climb.equippedWeapon=0;climb.footAirTime=1;climb.footAirFall=29;climb.footAirFell=true
        var events:[Int]=[];climb.onLocalHealth={events.append($0)}
        _=climb.frame(1/60)
        check(climb.climb != nil && climb.footAirFall==0 && climb.footAirTime==0,"New climb failed to cancel obsolete fall history")
        for _ in 0..<360 {_=climb.frame(1/60)}
        check(climb.health==100 && events.isEmpty,"Climb handoff applied a prior task's fall damage")
        let report:[String:Any]=["checks":checks,"referenceRows":(reference["rows"] as! [Any]).count,
            "factorySHA256":reference["factorySHA256"]!,"cases":reports,
            "authority":"Actual archived landing expression and native foot/motor/animation integration; not retail damage calibration",
            "limitations":["Controlled static floor and preloaded original clips","Integral native health rounding","Network stale-vitals reconciliation is a separate gate"]]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("report.json"))
        print("PASS fall damage: \(checks) checks; 12 native drop/cadence cases + climb cancellation; report \(folder.path)/report.json")
    }
}
