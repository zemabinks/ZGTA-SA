import Foundation
import simd

// Native-world lifecycle regressions. Synthetic fixtures exercise ownership
// transitions; they do not assert undocumented retail movement constants.
typealias F = SIMD3<Float>
typealias D = SIMD3<Double>
let tick = 1.0 / 60.0
var checks = 0, failures: [String] = [], measurements: [String: Any] = [:]
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { failures.append(message) }
}
func close(_ a: F, _ b: F, _ epsilon: Float = 0.0001) -> Bool { simd_distance(a,b) <= epsilon }
func finite(_ p: F) -> Bool { p.x.isFinite && p.y.isFinite && p.z.isFinite }
func flatWorld() -> SwiftRapierWorld {
    let w = SwiftRapierWorld()!
    let floor = w.addBox(halfExtents: F(100,0.1,100),position:F(0,-0.1,0))!
    w.setColliderGroups(floor,collision:131071,solver:0xffffffff)
    w.step()
    return w
}
func settle(_ c: NativeCharacterController, _ count: Int = 10) {
    for _ in 0..<count { c.update(delta:tick,displacement:.zero,geometryReady:true) }
}

// A held animation root must stop the old fall, contact events and easing,
// and the first ordinary step must start from that root, without fall debt.
do {
    let w=flatWorld(), c=NativeCharacterController(world:w)!
    c.reset(feet:F(0,0,10))
    settle(c,20)
    check(c.state.rising < -1,"fall fixture must acquire downward velocity")
    let root=F(3,2,5)
    c.update(delta:tick,displacement:.zero,geometryReady:true,motion:{ _,_,m in
        var m=m; m.heldFeet=root; return m
    })
    measurements["heldRootRising"] = c.state.rising
    check(close(c.state.feet,root),"held root has exact feet")
    check(c.state.rising == 0,"held root clears inherited fall velocity")
    check(!c.state.grounded && !c.state.propped && c.state.pressed.isEmpty,"held root clears contact history")
    c.update(delta:tick,displacement:.zero,geometryReady:true)
    check(root.z-c.state.feet.z < 0.01,"release must not resume the pre-root fall velocity")
}

// Press events describe one simulation tick, never a prior walking task.
do {
    let w=flatWorld(), c=NativeCharacterController(world:w)!
    let body=w.addBody(kind:.kinematicPosition,position:F(2,0.65,0))!
    let box=w.addBox(halfExtents:F(0.55,0.6,1),body:body)!
    w.setColliderSurface(box,surface:63,material:63)
    c.otherColliders=[box]; c.reset(feet:.zero);settle(c)
    var sawPress=false
    for _ in 0..<120 {
        c.update(delta:tick,displacement:F(0.04,0,0),geometryReady:true)
        if !c.state.pressed.isEmpty {sawPress=true;break}
    }
    check(sawPress,"native fixture must press a vehicle")
    c.update(delta:tick,displacement:F(1,0,0),geometryReady:false)
    check(c.state.pressed.isEmpty,"geometry pauses cannot publish a previous vehicle press")
    c.update(delta:tick,displacement:F(0.04,0,0),geometryReady:true)
    c.update(delta:tick,displacement:.zero,geometryReady:true,motion:{ _,_,m in
        var m=m;m.heldFeet=F(0,0,3);return m
    })
    check(c.state.pressed.isEmpty,"held roots cannot publish a previous vehicle press")
    c.setActive(false)
    check(c.state.pressed.isEmpty && c.state.rising==0 && !c.state.grounded,"deactivation clears movement state")
    c.setActive(true); c.reset(feet:.zero); settle(c)
    check(c.state.pressed.isEmpty,"reactivation cannot revive the previous press")
}

// A fresh task must not inherit the previous slope's barrier or normal.
do {
    let w=flatWorld(), q=NativeRapierCharacterQueries(world:w)!, m=NativeCharacterMotor(world:q)
    let slope=w.addBox(halfExtents:F(3,0.2,4),position:F(0,1.2,-4),
        rotation:simd_quatf(angle:Float(-25*Double.pi/180),axis:F(1,0,0)))!
    w.setColliderGroups(slope,collision:131071,solver:0xffffffff)
    w.setColliderSurface(slope,surface:2,material:17)
    var p=D(0,6,-4);m.setActive(true)
    var sawBarrier=false
    for _ in 0..<300 {
        m.step(position:&p,displacement:.zero,jump:0,delta:tick,held:false)
        w.step()
        if [0,Double.pi/2,Double.pi,Double.pi*1.5].contains(where:m.barred) {sawBarrier=true;break}
    }
    check(sawBarrier,"slippery slope fixture must establish a barrier")
    m.setActive(true);m.stand()
    check(![0,Double.pi/2,Double.pi,Double.pi*1.5].contains(where:m.barred),"reset must clear the previous slope barrier")
}
do {
    func fixture()->NativeCharacterController {
        let w=flatWorld()
        let ramp=w.addBox(halfExtents:F(3,0.2,4),position:F(0,1.2,-4),
            rotation:simd_quatf(angle:Float(-25*Double.pi/180),axis:F(1,0,0)))!
        let step=w.addBox(halfExtents:F(2,0.1,0.5),position:F(20,0.1,1))!
        for id in [ramp,step] {w.setColliderGroups(id,collision:131071,solver:0xffffffff)}
        return NativeCharacterController(world:w)!
    }
    let warm=fixture(),cold=fixture()
    warm.reset(feet:F(0,4,4.3));settle(warm,120)
    check(warm.state.grounded,"normal-history fixture must settle on the ramp")
    warm.reset(feet:F(20,0,0),grounded:true);cold.reset(feet:F(20,0,0),grounded:true)
    var maxEasing=0.0
    for _ in 0..<60 {
        warm.update(delta:tick,displacement:F(0,-0.04,0),geometryReady:true)
        cold.update(delta:tick,displacement:F(0,-0.04,0),geometryReady:true)
        maxEasing=max(maxEasing,abs(warm.state.eased-cold.state.eased))
        check(close(warm.state.feet,cold.state.feet),"teleport from slope matches fresh position")
    }
    measurements["resetSlopeEasingError"]=maxEasing
    check(maxEasing<1e-10,"teleport must clear the previous slope normal before the next step")
}

// Direct coordinator callers must not lose ordinary 5–15 FPS time. A long
// suspension is a separate discontinuity, not a burst of queued movement.
func run(_ deltas:[Double]) -> (F,Int) {
    let w=flatWorld(),c=NativeCharacterController(world:w)!
    var steps=0;w.afterStep={_ in steps += 1}
    c.reset(feet:.zero);settle(c);steps=0
    for dt in deltas {c.update(delta:dt,displacement:F(Float(2*dt),0,0),geometryReady:true)}
    return (c.state.feet,steps)
}
do {
    let base=run(Array(repeating:tick,count:120))
    for hz in [5,8,10,15,20,30,60,90,120,144] {
        let value=run(Array(repeating:1/Double(hz),count:hz*2))
        measurements["cadence\(hz)"]=["x":Double(value.0.x),"steps":value.1]
        check(value.1==120,"\(hz) Hz must preserve 120 fixed ticks")
        check(close(value.0,base.0,0.0001),"\(hz) Hz must preserve travel and grounded height")
    }
    let w=flatWorld(),c=NativeCharacterController(world:w)!
    c.reset(feet:.zero);settle(c)
    let before=c.state.feet
    c.update(delta:2,displacement:F(4,0,0),jump:6.07,geometryReady:true)
    check(close(c.state.feet,before),"suspension must not apply stale displacement or jump")
    c.update(delta:tick,displacement:.zero,geometryReady:true)
    check(close(c.state.feet,before),"suspension must not leave queued travel")
}

// Geometry pauses preserve position and physical fall velocity, while dropping
// input debt. Reloading collision cells must not replay an old jump or press.
do {
    let w=flatWorld(),c=NativeCharacterController(world:w)!
    c.reset(feet:F(0,0,4));settle(c,10)
    let before=c.state
    for _ in 0..<20 {c.update(delta:0.1,displacement:F(1,0,0),jump:6.07,geometryReady:false)}
    check(close(c.state.feet,before.feet),"geometry pause preserves feet")
    check(c.state.rising==before.rising,"geometry pause preserves physical vertical momentum")
    c.update(delta:tick,displacement:.zero,geometryReady:true)
    check(abs(c.state.feet.x-before.feet.x)<0.0001,"geometry resume drops paused travel")
    check(c.state.rising<0,"geometry resume drops paused jump")
}

// Partial high-refresh-rate input belongs to its original task. Neither a
// teleport, a vehicle handoff nor a missing-cell gap may replay it later.
do {
    let w=flatWorld(),c=NativeCharacterController(world:w)!
    for transition in 0..<3 {
        c.reset(feet:.zero);settle(c)
        let before=c.state.feet
        c.update(delta:tick/2,displacement:F(1,0,0),jump:6.07,geometryReady:true)
        if transition==0 {c.reset(feet:before,grounded:true)}
        if transition==1 {c.setActive(false);c.setActive(true)}
        if transition==2 {c.update(delta:tick/2,displacement:.zero,geometryReady:false)}
        c.update(delta:tick,displacement:.zero,geometryReady:true)
        check(close(c.state.feet,before),"transition \(transition) discards fractional travel/jump debt")
        check(c.state.rising==0,"transition \(transition) cannot relaunch a queued jump")
    }
}

// A carrying exclusion is task-local. Releasing it must restore collision
// with that exact body, rather than making its chassis permanently intangible.
do {
    let w=flatWorld(),c=NativeCharacterController(world:w)!
    let body=w.addBody(kind:.kinematicPosition,position:F(2,0.65,0))!
    let box=w.addBox(halfExtents:F(0.55,0.6,1),body:body)!
    w.setColliderGroups(box,collision:131071,solver:0xffffffff)
    c.otherColliders=[box];c.reset(feet:.zero);settle(c)
    for _ in 0..<25 {c.update(delta:tick,displacement:F(0.04,0,0),carrying:body,geometryReady:true)}
    check(c.state.feet.x>0.9,"carrying fixture approaches its excluded chassis")
    for _ in 0..<90 {c.update(delta:tick,displacement:F(0.04,0,0),geometryReady:true)}
    check(c.state.feet.x<1.2,"releasing carrying restores chassis collision")
    check(finite(c.state.feet) && c.state.grounded,"carrying release keeps a valid supported pose")
}

// Malformed external/callback motion may not poison the persistent pose.
do {
    let w=flatWorld(),c=NativeCharacterController(world:w)!
    c.reset(feet:.zero);settle(c)
    for kind in 0..<4 {
        c.update(delta:tick,displacement:.zero,geometryReady:true,motion:{ _,_,m in
            var m=m
            if kind==0 {m.heldFeet=F(.nan,0,0)}
            if kind==1 {m.displacement=F(0,.infinity,0)}
            if kind==2 {m.verticalOverride = .nan}
            if kind==3 {m.jump = .infinity}
            return m
        })
        check(finite(c.state.feet) && c.state.rising.isFinite,"invalid motion \(kind) must not poison pose or velocity")
    }
    c.reset(feet:F(.nan,0,0))
    check(finite(c.state.feet),"invalid teleport must not poison pose")
}

// Exercise every frame of native movement against the same fixed-step run,
// rather than checking only an end position that could hide bad transitions.
struct Sample {
    var feet:F;var grounded:Bool;var rising:Double;var easing:Double;var propped:Bool;var presses:Int
}
func matrix(_ name:String,_ deltas:[Double])->[Sample] {
    let w=flatWorld(),c=NativeCharacterController(world:w)!
    if name=="ceiling" {
        let id=w.addBox(halfExtents:F(8,0.1,8),position:F(0,2.25,0))!
        w.setColliderGroups(id,collision:131071,solver:0xffffffff)
    }
    if name=="wall" {
        let id=w.addBox(halfExtents:F(0.1,3,8),position:F(2,3,0))!
        w.setColliderGroups(id,collision:131071,solver:0xffffffff)
    }
    if name=="stairs" {
        for i in 0..<5 {
            let h=Float(i+1)*0.1
            let id=w.addBox(halfExtents:F(2,h,0.4),position:F(0,h,-2-Float(i)*0.8))!
            w.setColliderGroups(id,collision:131071,solver:0xffffffff)
        }
    }
    if name=="slope" || name=="slippery" {
        let id=w.addBox(halfExtents:F(3,0.2,4),position:F(0,1.2,-4),
            rotation:simd_quatf(angle:Float(-25*Double.pi/180),axis:F(1,0,0)))!
        w.setColliderGroups(id,collision:131071,solver:0xffffffff)
        w.setColliderSurface(id,surface:2,material:name=="slippery" ? 17:0)
    }
    c.reset(feet:name=="fall" ? F(0,0,6):.zero);settle(c)
    var count=0,trace:[Sample]=[]
    w.afterStep={_ in
        let s=c.state
        trace.append(Sample(feet:s.feet,grounded:s.grounded,rising:s.rising,easing:s.eased,propped:s.propped,presses:s.pressed.count))
    }
    for dt in deltas {
        c.update(delta:dt,displacement:.zero,geometryReady:true,motion:{ _,_,m in
            var m=m
            m.displacement=name=="wall" ? F(0.04,0,0):F(0,-0.04,0)
            m.jump=(name=="jump" || name=="ceiling") && count==20 ? 6.07:0
            if name=="held_root" && (40..<70).contains(count) {m.heldFeet=F(0,0,Float(1+Double(count-40)*0.02))}
            if name=="swim_override" && (40..<100).contains(count) {m.verticalOverride=count<70 ? 1:-1}
            count += 1
            return m
        })
    }
    w.afterStep=nil
    return trace
}
do {
    let names=["jump","ceiling","wall","stairs","slope","slippery","fall","held_root","swim_override"]
    var maxPosition:Float=0,maxRising=0.0,maxEasing=0.0,total=0
    for name in names {
        let baseline=matrix(name,Array(repeating:tick,count:180))
        var schedules=[5,8,15,30,60,120,144].map { hz in
            ("\(hz) Hz",Array(repeating:1/Double(hz),count:hz*3))
        }
        let uneven=(0..<60).flatMap { _ in [tick/4,tick*2,tick*0.75] }
        schedules.append(("uneven",uneven))
        for (cadence,deltas) in schedules {
            let result=matrix(name,deltas)
            check(result.count==baseline.count,"\(name) \(cadence) fixed-step count")
            for (index,pair) in zip(result,baseline).enumerated() {
                let (a,b)=pair
                maxPosition=max(maxPosition,simd_distance(a.feet,b.feet))
                maxRising=max(maxRising,abs(a.rising-b.rising));maxEasing=max(maxEasing,abs(a.easing-b.easing))
                check(close(a.feet,b.feet,0.000001),"\(name) \(cadence) frame \(index) position")
                check(abs(a.rising-b.rising)<1e-10 && abs(a.easing-b.easing)<1e-10,"\(name) \(cadence) frame \(index) velocity/easing")
                check(a.grounded==b.grounded && a.propped==b.propped && a.presses==b.presses,"\(name) \(cadence) frame \(index) contacts")
                total += 1
            }
        }
        if name=="jump" {check((baseline.map{$0.feet.z}.max() ?? 0)>0.6,"jump rises above floor")}
        if name=="ceiling" {check((baseline.map{$0.feet.z}.max() ?? 2)<0.6,"ceiling cancels upward movement")}
    }
    measurements["matrix"]=["cases":names,"comparedFrames":total,"maxPosition":Double(maxPosition),"maxRising":maxRising,"maxEasing":maxEasing]
}

let report:[String:Any] = ["checks":checks,"failures":failures,"measurements":measurements]
if CommandLine.arguments.count>1 {
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        .write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
}
for f in failures {print("FAIL: \(f)")}
print("\(failures.isEmpty ? "PASS":"FAIL"): \(checks) native character lifecycle/cadence checks; \(failures.count) failures")
if !failures.isEmpty {exit(1)}
