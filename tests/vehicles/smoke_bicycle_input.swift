import Foundation
import simd

// RendererInputContext and rendererInput() are generated from the actual
// Renderer mapping by tests/vehicles/smoke_bicycle_input.py, rather than copied here.
@main enum BicycleInputSmoke {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let definitions=try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/vehicles.physics.json"))
        var floor=Data()
        func word(_ value:UInt32){var little=value.littleEndian;withUnsafeBytes(of:&little){floor.append(contentsOf:$0)}}
        [UInt32(0x324c4353),4,2,1].forEach(word)
        for value:Float in [-1000,-1000,0,1000,-1000,0,1000,1000,0,-1000,1000,0]{word(value.bitPattern)}
        [UInt32(0),1,2,0,2,3].forEach(word);floor.append(contentsOf:[2,2,0,0,1,1,0,0])
        var checks=0
        func check(_ value:Bool,_ label:String){checks+=1;precondition(value,label)}
        func fresh()->NativeGroundVehicle {
            let car=NativeGroundVehicle()!;precondition(car.loadDefinitions(definitions)==212)
            car.installCell("floor",data:floor);precondition(car.enter(model:"481",modelPosition:SIMD3(0,0,1.1),heading:0))
            for _ in 0..<90{car.update(delta:1/60,input:.init(),currentCell:"floor")}
            precondition(car.output!.wheels.prefix(2).contains{$0.counts>0} && car.output!.wheels.suffix(2).contains{$0.counts>0})
            return car
        }
        func tick(_ car:NativeGroundVehicle,_ context:RendererInputContext = .init(),delta:Double=1/60){
            car.update(delta:delta,input:rendererInput(car,context),currentCell:"floor")
        }
        func charge(_ car:NativeGroundVehicle){var context=RendererInputContext();context.hop=true;for _ in 0..<30{tick(car,context)}}
        do {
            let car=fresh();let height=car.modelPosition.z;var brake=RendererInputContext();brake.brake=true
            for _ in 0..<60{tick(car,brake);check(car.bicycleHop==0,"Actual Renderer brake charged a bicycle hop")}
            for _ in 0..<15{tick(car);check(car.bicycleHop==0,"Brake release launched a bicycle hop")}
            check(car.modelPosition.z-height<0.15,"Braking invented vertical motion")
        }
        do {
            let car=fresh();charge(car);check(car.bicycleHop>0.99,"Explicit hop did not charge")
            tick(car);check(car.bicycleHop == -1 && car.nativeLinearVelocity.z>3,"Explicit release did not launch a grounded hop")
            let velocity=car.nativeLinearVelocity;car.cancelPendingInput()
            check(car.nativeLinearVelocity==velocity && car.bicycleHop == -1,"Cancellation erased an already launched hop")
        }
        do {
            let car=fresh();charge(car);let velocity=car.nativeLinearVelocity;car.cancelPendingInput()
            check(car.bicycleHop==0 && car.nativeLinearVelocity==velocity,"Cancellation failed to discard only unlaunched charge")
            tick(car);check(car.bicycleHop==0 && car.nativeLinearVelocity.z<1,"Focus/menu cancellation became a hop release")
        }
        do {
            let car=fresh();charge(car);var boarding=RendererInputContext();boarding.inside=false;boarding.hop=true
            boarding.forward=1;boarding.turn=1;boarding.sideways=1;boarding.lookVertical=1;boarding.lift=1;boarding.jets=1
            let input=rendererInput(car,boarding)
            check(!input.hop && input.throttle==0 && input.steer==0 && input.lean==0 && input.pitch==0 && input.roll==0 && input.yaw==0 && input.jets==0 && input.handbrake,"Unseated driver retained active control channels")
            car.update(delta:1/60,input:input,currentCell:"floor")
            check(car.bicycleHop==0 && car.nativeLinearVelocity.z<1,"Boarding ownership loss released stored hop charge")
        }
        do {
            let car=fresh();charge(car);car.damageController!.state.load(health:0,text:"")
            var held=NativeVehicleDynamics.Input();held.hop=true;held.throttle=1
            car.update(delta:1/60,input:held,currentCell:"floor")
            check(car.bicycleHop==0 && car.nativeLinearVelocity.z<1,"Wrecked bicycle released stored charge")
        }
        do {
            let car=fresh();charge(car);car.exit()
            check(car.enter(model:"481",modelPosition:SIMD3(0,0,1.1),heading:0),"Bicycle re-entry failed")
            tick(car);check(car.bicycleHop==0,"Entry inherited the previous rider's hop charge")
        }
        var original=NativeVehicleDynamics.Input();original.throttle=1;original.steer=1;original.lean=1;original.pitch=1;original.roll=1;original.yaw=1;original.jets=1;original.hop=true
        original.accelerate=1;original.brake=1;original.pedals=SIMD2(1,1);original.drive = .init(throttle:1,steer:1,handbrake:false,pedals:SIMD2(1,1))
        original.pad=true;original.wetness=0.7;original.suspensionOffsets=[0.1,0.2,0.3,0.4];original.nobody=true
        let denied=NativeVehicleInputOwnership.gated(original,enabled:false)
        check(denied.pad && denied.wetness==0.7 && denied.suspensionOffsets==original.suspensionOffsets && denied.nobody,"Ownership gating discarded passive solver state")
        check(denied.accelerate==nil && denied.brake==nil && denied.pedals==nil && denied.drive?.pedals==nil && denied.drive?.throttle==0 && denied.drive?.steer==0 && denied.drive?.handbrake==true,"Explicit drive overrides escaped ownership gate")
        // The same exact60Hz simulation must survive common display cadences.
        func trajectory(_ hz:Int)->(SIMD3<Float>,SIMD3<Float>) {
            let car=fresh();var context=RendererInputContext();context.hop=true
            for _ in 0..<hz/2{tick(car,context,delta:1/Double(hz))}
            context.hop=false
            for _ in 0..<hz/2{tick(car,context,delta:1/Double(hz))}
            return(car.modelPosition,car.nativeLinearVelocity)
        }
        let reference=trajectory(60)
        for hz in [30,120]{let actual=trajectory(hz);check(simd_distance(actual.0,reference.0)<1e-5 && simd_distance(actual.1,reference.1)<1e-5,"Hop cadence changed with display refresh")}
        // Use the same shared budget that foot/swim consume, with the existing
        // independently ported original bike sprint profile as the unit oracle.
        final class Pool {var value=NativeStamina()}
        let pool=Pool(),bike=fresh(),counter=NativeSprintController()
        _=pool.value.take(300);var expected=pool.value,previous=false,sprint=false
        bike.staminaLeft={pool.value.left};bike.takeStamina={pool.value.take($0)};bike.restStamina={pool.value.rest($0)}
        let profile=NativeSprintController.Profile.forMode(.bike),step=50.0/60
        for frame in 0..<240 {
            let held=frame%12<6,throttle=held ? 1.0:0.0
            let effort=counter.control(profile,ticks:step,tapped:held && !previous,held:held,staminaLeft:expected.left,take:{expected.take($0)})
            previous=held;sprint=effort>1.2 || sprint && effort>1
            if !sprint{expected.rest(step*(1-max(0,throttle)/2)/2)}
            var context=RendererInputContext();context.forward=Float(throttle)
            // Cancelling a nonexistent hop must not reset pedalling or its cost.
            bike.cancelPendingInput();tick(bike,context)
            check(abs(pool.value.value-expected.value)<1e-10,"Owned bicycle stamina units/state differ from shared bike profile")
        }
        check(pool.value.value<50,"Rapid pedalling did not debit shared stamina")
        let afterBike=pool.value.value;bike.exit();_=pool.value.take(30)
        let footValue=pool.value.value
        check(abs(afterBike-footValue-10)<1e-10,"Shared stamina did not retain foot handoff debit")
        check(bike.enter(model:"481",modelPosition:SIMD3(0,0,1.1),heading:0),"Re-enter shared-stamina bicycle")
        check(pool.value.value==footValue,"Bike re-entry reset the shared pool")
        bike.teleport(modelPosition:SIMD3(3,4,2),heading:0)
        check(pool.value.value==footValue,"Bike solver rebuild reset the shared pool")
        print("PASS: \(checks) actual Renderer/bicycle/body/ownership/shared-stamina checks; explicit hop, cancellation, braking, wreck/entry and30/60/120Hz")
    }
}
