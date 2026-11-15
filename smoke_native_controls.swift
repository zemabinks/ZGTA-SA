import Foundation
import CoreGraphics
import simd

// Compile with the actual NativeGameInput + NativeGameCamera + ServerAddress.
let metadata = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ label: String) { checks += 1; precondition(value(), label) }
func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6, _ label: String) { expect(abs(a-b) <= tolerance, "\(label): \(a) != \(b)") }
for hz in [15,20,30,60,90,120,144] {
    var clock = NativeGameFrameClock()
    _ = clock.advance(timestamp: 10, active: true)
    var duration = 0.0, steps = 0
    for i in 1...hz * 10 {
        let frame = clock.advance(timestamp: 10 + Double(i) / Double(hz), active: true)
        expect(!frame.discontinuity, "ordinary cadence")
        close(frame.steps.reduce(0,+), frame.delta, 1e-12, "slices preserve time")
        expect(frame.steps.allSatisfy { $0 > 0 && $0 <= 1.0 / 60.0 + 1e-12 }, "bounded slices")
        duration += frame.delta; steps += frame.steps.count
    }
    close(duration, 10, 1e-10, "10 seconds at \(hz)Hz")
    expect(steps >= 600, "low FPS keeps simulation time")
}
var clock = NativeGameFrameClock()
_ = clock.advance(timestamp: 1, active: true)
let hitch = clock.advance(timestamp: 1.25, active: true)
expect(hitch.steps.count == 15, "250ms bounded catch-up")
close(hitch.delta, 0.25, 0, "hitch elapsed")
let suspended = clock.advance(timestamp: 10, active: true)
expect(suspended.discontinuity && suspended.steps.isEmpty, "long suspension has no giant movement")
expect(clock.advance(timestamp: 11, active: false).steps.isEmpty, "background stops game clock")
close(clock.advance(timestamp: 20, active: true).delta, 1.0 / 60.0, 0, "foreground starts fresh")
expect(clock.advance(timestamp: 19, active: true).discontinuity, "backwards clock reset")
expect(clock.advance(timestamp: .nan, active: true).steps.isEmpty, "invalid clock reset")

var gate = NativeControllerInputGate()
expect(!gate.accepts(active: true, axes: [0,0,1], pressed: true), "held trigger on connect blocked")
expect(gate.accepts(active: true, axes: [0,0,0], pressed: false), "neutral reconnect arms")
expect(gate.accepts(active: true, axes: [1,0,0], pressed: true), "fresh press accepted")
expect(!gate.accepts(active: false, axes: [1,0,0], pressed: true), "overlay input blocked")
for _ in 0..<120 { expect(!gate.accepts(active: true, axes: [1,0,0], pressed: true), "held controls cannot resume through overlay") }
expect(!gate.accepts(active: true, axes: [0,0,0], pressed: true), "release buttons as well as sticks")
expect(gate.accepts(active: true, axes: [0,0,0], pressed: false), "release to rearm")
gate.reset(); expect(!gate.accepts(active: true, axes: [0,0,0.5], pressed: false), "disconnect requires release")
expect(!gate.accepts(active: true, axes: [.nan], pressed: false), "nonfinite controller blocked")
let diagonal = NativeInputMath.stick(x: 1,y: 1)
close(Double(hypot(diagonal.x, diagonal.y)),1,1e-6,"diagonal is bounded")
expect(NativeInputMath.stick(x:.infinity,y:0) == .zero,"invalid stick")
expect(NativeInputMath.stick(x:0.02,y:0.02) == .zero,"radial drift deadzone")

for size in [CGSize(width:190,height:155),CGSize(width:150,height:155)] {
    let bounds = CGRect(origin:.zero,size:size)
    for p in [CGPoint(x:0,y:0),CGPoint(x:size.width-1,y:1),CGPoint(x:1,y:size.height-1),CGPoint(x:size.width-1,y:size.height-1)] {
        var stick = NativeVirtualStickState();stick.begin(at:p,bounds:bounds)
        expect(stick.active && stick.value == .zero,"floating touch begins neutral at safe-area edge")
        let origin=stick.origin,extent=NativeVirtualStickState.travel+NativeVirtualStickState.knobRadius
        expect(origin.x-extent >= 0 && origin.y-extent >= 0 && origin.x+extent <= size.width && origin.y+extent <= size.height,"ring/knob stay in hit zone")
        stick.move(to:CGPoint(x:p.x+100,y:p.y-100))
        close(hypot(stick.value.x,stick.value.y),1,1e-12,"stick travel bounded")
        stick.reset();expect(!stick.active && stick.value == .zero,"touch cancellation resets")
        stick.move(to:CGPoint(x:999,y:999));expect(stick.value == .zero,"old touch cannot resume after reset")
    }
}

var headings:[Float] = []
for hz in [30,60,120] {
    let camera = try NativeGameCamera(data:metadata)
    camera.setDirection(heading:0,pitch:0)
    for _ in 0..<hz * 2 { camera.lookAnalog(x:0.4,y:0.1,delta:1/Float(hz)) }
    headings.append(camera.heading)
    close(Double(camera.pitch),-0.15 * Double(camera.heading),1e-5,"look axis ratio")
}
for value in headings { close(Double(value),Double(headings[0]),1e-5,"look is elapsed-time based") }
let camera=try NativeGameCamera(data:metadata)
camera.setDirection(heading:1,pitch:0.2);camera.lookAnalog(x:1,y:1,delta:-1);camera.lookPixels(x:.nan,y:0)
close(Double(camera.heading),1,0,"invalid input preserves heading")
expect(camera.followFoot(.init(position:.zero),delta:-1) == nil,"negative camera frame rejected")
let before:Float = .pi - 0.01, after:Float = -.pi + 0.01
let frame=NativeGameCamera.Frame(source:.zero,target:SIMD3(0,1,0),verticalFov:70,heading:after,pitch:0.1,hidesPlayer:false,aimSource:nil)
let direction=camera.resumeFoot(from:frame,fallbackHeading:before,fallbackPitch:0)
close(Double(direction.x-before),0.02,1e-6,"vehicle exit uses shortest angle at wrap")
let far=SIMD3<Float>(2000,-2000,50)
let actual=camera.followFoot(.init(position:far),delta:1/60)!
let fresh=try NativeGameCamera(data:metadata);fresh.resetFoot(heading:direction.x,pitch:direction.y)
let wanted=fresh.followFoot(.init(position:far),delta:1/60)!
close(Double(simd_distance(actual.source,wanted.source)),0,1e-6,"foot exit has no stale chase anchor")
let vehicle=NativeGameCamera.Vehicle(position:SIMD3(50,20,5),forward:SIMD3(0,1,0),right:SIMD3(1,0,0),bounds:.init(maxX:1,minY:-2,maxZ:1.5))
camera.lookPixels(x:900,y:-300,driving:true);_ = camera.followVehicle(vehicle,delta:1/60)
camera.lookPixels(x:100,y:100,driving:true);camera.beginVehicle()
let car=camera.followVehicle(vehicle,delta:1/60)!
let clean=try NativeGameCamera(data:metadata);clean.beginVehicle()
let newCar=clean.followVehicle(vehicle,delta:1/60)!
close(Double(simd_distance(car.source,newCar.source)),0,1e-6,"new vehicle discards old pending manual look")
// Match the real draw contract: analog deltas accumulate once per display
// frame, then the camera may consume several bounded integration slices.
var vehicleAngles: [Float] = []
for hz in [30,60,120] {
    let camera = try NativeGameCamera(data:metadata);camera.beginVehicle()
    var clock = NativeGameFrameClock();_ = clock.advance(timestamp:1,active:true)
    var frame: NativeGameCamera.Frame?
    for tick in 1...hz * 2 {
        let timing = clock.advance(timestamp:1+Double(tick)/Double(hz),active:true)
        camera.lookAnalog(x:0.2,y:0,delta:Float(timing.delta),driving:true)
        for slice in timing.steps { frame = camera.followVehicle(vehicle,delta:Float(slice)) }
    }
    vehicleAngles.append(frame!.heading)
}
for angle in vehicleAngles { close(Double(NativeGameCamera.shortestAngle(angle-vehicleAngles[0])),0,1e-5,"vehicle look delta consumed exactly once per display frame") }
print("PASS: native input/cadence/camera lifecycle \(checks) checks; 15/20/30/60/90/120/144Hz, suspension, controller rearm, safe-area stick bounds and shortest-angle mode handoff")
