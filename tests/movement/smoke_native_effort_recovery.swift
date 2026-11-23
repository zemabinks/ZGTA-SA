// Receives actual current Renderer methods plus the existing real-CLP/native
// world harnesses. Controlled poses isolate effort and breath ownership.
private extension FixedVelocityHarness {
    func testWater(delta:Double,state:NativeCharacterController.Output,push:Double,running:Bool) {
        _=swimmingMotion(delta:delta,state:state,intended:.init(displacement:.zero),push:push,running:running)
    }
    func testParachute(delta:Double,state:NativeCharacterController.Output) {
        _=personalFlightMotion(delta:delta,state:state,intended:.init(displacement:.zero),forward:0,sideways:0,running:false)
    }
}
private extension ClimbRuntimeHarness {
    func testFoot(delta:Double,state:NativeCharacterController.Output,forward:Float,running:Bool) {
        _=footMotion(delta:delta,state:state,intended:.init(displacement:.zero),forward:forward,sideways:0,running:running)
    }
}
@main enum EffortRecoveryGate {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/models/animations.clips.bin")))!
        var scalars:[[String:Any]]=[],water:[[String:Any]]=[],foot:[[String:Any]]=[],parachute:[[String:Any]]=[]
        func budget(_ value:Double)->NativeStamina {var s=NativeStamina();_=s.take((150-value)*3);return s}
        for initial in [-150.0,-100,-90,-0.001,0,0.1,10,149.9,150] {
            for under in [false,true] {
                var s=budget(initial);if under{s.prepareUnderwater()}
                scalars.append(["kind":"under","initial":initial,"under":under,"actual":s.value])
            }
            for ratio in [0.0,0.999,1,1.001,2.13] {for ticks in [0.0,50.0/15,50.0/30,50.0/60,50.0/120,50.0/144,25] {
                var s=budget(initial);s.restForLocomotion(ticks:ticks,ratio:ratio)
                scalars.append(["kind":"recovery","initial":initial,"ratio":ratio,"ticks":ticks,"actual":s.value])
            }}
        }
        var guardChecks=0
        for initial in [-150.0,0,150] {for ticks in [-1.0,Double.nan,Double.infinity] {
            var s=budget(initial);let old=s.value;s.restForLocomotion(ticks:ticks,ratio:0)
            precondition(s.value==old,"Invalid recovery clock changed effort");guardChecks+=1
        }}
        for initial in [-150.0,0,150] {for ratio in [Double.nan,Double.infinity] {
            var s=budget(initial);let old=s.value;s.restForLocomotion(ticks:1,ratio:ratio)
            precondition(s.value==old,"Invalid movement ratio changed effort");guardChecks+=1
        }}
        let rates=[15,30,60,120,144,0]
        func delta(_ rate:Int,_ frame:Int)->Double {rate>0 ? 1/Double(rate):[1.0/144,1.0/90,1.0/42,1.0/120,1.0/30][frame%5]}
        for hz in rates {for kind in ["breast","dive","under-exhausted","dead-under","death-revive","shore-recovery"] {
            let h=FixedVelocityHarness(library:library,mode:"water")
            h.actorHeading=0;h.heading=0;h.swimHeadingTarget=0;h.waterEdge=1479
            let depth=kind=="breast" || kind=="dive" ? 2.0:5.0
            let initial=kind=="breast" ? -20.0:kind=="dead-under" ? -100:-150
            h.stamina=budget(initial);h.swimController.enter(velocity:.zero,rising:0,depth:depth)
            var rows:[[String:Any]]=[]
            for index in 0..<360 {
                let dt=delta(hz,index)
                let reset=kind=="death-revive" && index==180
                h.health=kind=="dead-under" || kind=="death-revive" && (60..<180).contains(index) ? 0:100
                if reset {h.stamina.reset();h.sprintController.reset();h.swimController.revive()}
                let activeWater = !(kind=="shore-recovery" && index>=120)
                h.water=activeWater
                let running=kind != "breast" && kind != "shore-recovery"
                let tap=running && index%20==0,dive=kind=="dive" && index==6
                h.pendingSprintTap=tap;h.pendingDive=dive
                let state=NativeCharacterController.Output(feet:SIMD3(1480,0,Float(102-depth)),grounded:false,rising:0,eased:0,propped:false,pressed:[])
                // Deliberately isolate the outgoing swim method. A completed
                // tick's receiving foot recovery is outside these rows.
                h.testWater(delta:dt,state:state,push:1,running:running)
                rows.append(["delta":dt,"health":h.health,"reset":reset,"depth":activeWater ? depth:NSNull(),"running":running,"tap":tap,"dive":dive,"push":1,
                             "value":h.stamina.value,"counter":h.sprintController.counter,"breath":h.swimController.breath,
                             "display":h.swimmingBreath as Any? ?? NSNull(),"on":h.swimController.on,"state":h.swimController.on ? h.swimController.state.rawValue:0])
            }
            water.append(["name":"water-\(kind)-\(hz)","initial":initial,"depth":depth,"frames":rows])
        }}
        for hz in rates {for dead in [false,true] {
            let h=FixedVelocityHarness(library:library,mode:"parachute")
            h.stamina=budget(-150)
            _=h.sprintController.control(.forMode(.foot),ticks:1,tapped:true,held:true,staminaLeft:100,take:{_ in true})
            let initialCounter=h.sprintController.counter,initial=h.stamina.value
            h.personalFlight.dive(velocity:.zero,rising:-12,heading:0)
            var rows:[[String:Any]]=[]
            for index in 0..<250 {
                let dt=delta(hz,index);if dead && index>=100 {h.health=0}
                let active=h.personalFlight.chuting,health=h.health
                if index==25 {h.pendingParachuteOpen=true}
                h.testParachute(delta:dt,state:.init(feet:SIMD3(1480,0,100),grounded:false,rising:-12,eased:0,propped:false,pressed:[]))
                rows.append(["delta":dt,"health":health,"chuting":active,"value":h.stamina.value,"initialCounter":initialCounter,"counter":h.sprintController.counter])
            }
            parachute.append(["name":"parachute-\(dead ? "death":"live")-\(hz)","initial":initial,"frames":rows])
        }}
        for hz in rates {for kind in ["idle","moving","air-idle","air-moving","sprint-air","dead","death-revive"] {
            let h=try ClimbRuntimeHarness(root:root,top:0.75,depth:0.6)
            h.footLaunchRemaining=nil;h.equippedWeapon=0;h.stamina=budget(-100)
            var rows:[[String:Any]]=[]
            for index in 0..<240 {
                let dt=delta(hz,index),reset=kind=="death-revive" && index==180
                if reset {h.stamina.reset();h.sprintController.reset();h.footSprintPace=0}
                h.health=kind=="dead" || kind=="death-revive" && (60..<180).contains(index) ? 0:100
                let airborne=kind=="air-idle" || kind=="air-moving" && index>=30 || kind=="sprint-air" && index>=60
                let running=kind=="sprint-air",tap=running && index%20==0
                let forward:Float=["moving","air-moving","sprint-air"].contains(kind) ? 1:0
                h.pendingSprintTap=tap
                h.testFoot(delta:dt,state:.init(feet:SIMD3(0,0,4),grounded:!airborne,rising:0,eased:0,propped:false,pressed:[]),forward:forward,running:running)
                rows.append(["delta":dt,"reset":reset,"health":h.health,"airborne":airborne,"running":running,"tap":tap,
                             "ratio":h.footLocomotion.reportedRatio,"value":h.stamina.value,"counter":h.sprintController.counter])
            }
            foot.append(["name":"foot-\(kind)-\(hz)","initial":-100,"frames":rows])
        }}
        let result:[String:Any]=["scalars":scalars,"water":water,"foot":foot,"parachute":parachute,"nativeGuardChecks":guardChecks]
        try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
        print("Recorded actual Renderer effort/breath traces: \(water.count) water, \(foot.count) foot, \(parachute.count) flight cases; \(guardChecks) invalid-input guards")
    }
}
