import Foundation
import simd

// Only rendering dependencies unrelated to this actual camera call are spies.
final class CameraMotionHarness {
    final class Flight {var chuting=false,flying=false}
    final class Swim {var hauled:Int?}
    let gameCamera:NativeGameCamera
    let personalFlight=Flight(),swimController=Swim()
    var gameCameraFrame:NativeGameCamera.Frame?
    var camera=SIMD3<Float>.zero,actorHeading:Float=0
    var equippedWeapon=0,aiming=false,crouching=true,climb:Int?
    struct WeaponDefinition { var aims:Bool;var arm=false }
    var footWeaponDefinitions:[Int:WeaponDefinition]=[:]
    var health=100,driving=false
    var swimming:Bool {false}
    // ACTUAL_RENDERER_AIM_PREDICATES
    var cameraLookDirection:String?
    var lastFootVelocity=SIMD3<Double>.zero
    var character:NativeCharacterController?
    // ACTUAL_RENDERER_CURRENT_VELOCITY
    init(data:Data)throws {gameCamera=try NativeGameCamera(data:data);gameCamera.setDirection(heading:0,pitch:0)}
    func render(step:Double)->NativeGameCamera.Frame {
        // ACTUAL_RENDERER_CAMERA_CALL
        return gameCameraFrame!
    }
}

@main struct CameraMotionCheck {
    static var checks=0
    static func check(_ value:Bool,_ reason:String){checks+=1;precondition(value,reason)}
    static func main() throws {
        let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
        var results:[[String:Any]]=[]
        for hz in [15,30,60,120,144,0] {
            let world=SwiftRapierWorld()!,motor=NativeCharacterController(world:world)!
            let floor=world.addBox(halfExtents:SIMD3(100,0.1,100),position:SIMD3(0,-0.1,0))!
            world.setColliderGroups(floor,collision:0x0087ffff,solver:0xffffffff)
            motor.reset(feet:SIMD3(0,0,0.03),grounded:true)
            let fixed=try CameraMotionHarness(data:data),legacy=try NativeGameCamera(data:data)
            fixed.character=motor
            legacy.setDirection(heading:0,pitch:0)
            var clock=NativeGameFrameClock();_=clock.advance(timestamp:0,active:true)
            let pattern=hz==0 ? [1.0/144,1.0/30,1.0/120,1.0/15,1.0/60]:[1.0/Double(hz)]
            var t=0.0,frames=0,newZ:[Float]=[],oldZ:[Float]=[],last=SIMD3<Float>.zero,repeated=0
            while t<6-1e-8 {
                let dt=min(pattern[frames%pattern.count],6-t);t+=dt;frames+=1
                let timing=clock.advance(timestamp:t,active:true)
                for step in timing.steps {_=motor.update(delta:step,displacement:SIMD3(Float(step),0,0),geometryReady:true)}
                let pose=motor.state.feet
                if pose==last {repeated+=1};last=pose
                fixed.camera=pose;fixed.lastFootVelocity=motor.stepVelocity
                for step in timing.steps {
                    let actual=fixed.render(step:step)
                    let old=legacy.followFoot(.init(position:pose,crouching:true),delta:Float(step))!
                    check(actual.source.x.isFinite && actual.source.y.isFinite && actual.source.z.isFinite,"nonfinite camera")
                    if t>5 {
                        newZ.append(actual.source.z-pose.z);oldZ.append(old.source.z-pose.z)
                        check(abs(actual.source.z-pose.z-1.4)<0.00002,"repeated fixed pose changed moving crouch height at \(hz)Hz")
                    }
                }
            }
            check(abs(motor.stepVelocity.x-1)<0.00005,"test did not measure committed motor velocity")
            if hz>=120 {check(repeated>0,"high-rate case did not include no-tick frames")}
            if hz != 60 {check(oldZ.contains{abs($0-1.4)>0.05},"legacy path did not reproduce cadence-dependent crouch depression")}
            results.append(["displayHz":hz==0 ? "jitter":String(hz),"frames":frames,"repeatedPoses":repeated,
                            "legacyHeightMin":oldZ.min()!,"legacyHeightMax":oldZ.max()!,
                            "fixedHeightMin":newZ.min()!,"fixedHeightMax":newZ.max()!])
            // Standing still must use actual blocked/resting motion, not held input.
            for _ in 0..<120 {
                _=motor.update(delta:1/60,displacement:.zero,geometryReady:true)
                fixed.camera=motor.state.feet;fixed.lastFootVelocity=motor.stepVelocity
                _=fixed.render(step:1/60)
            }
            check(abs(fixed.gameCameraFrame!.source.z-fixed.camera.z-0.9)<0.00003,"stationary crouch failed to settle")
            // A zero-tick resumed display retains the last physical movement state.
            _=motor.update(delta:1/60,displacement:SIMD3(1.0/60,0,0),geometryReady:true)
            fixed.lastFootVelocity=motor.stepVelocity;fixed.camera=motor.state.feet
            fixed.gameCamera.resetFoot(heading:0,pitch:0)
            check(abs(fixed.render(step:0).source.z-fixed.camera.z-1.4)<0.00003,"reset discarded current committed motion")
            motor.reset(feet:SIMD3(0,0,0.03),grounded:true)
            fixed.lastFootVelocity=motor.stepVelocity;fixed.camera=motor.state.feet
            fixed.gameCamera.resetFoot(heading:0,pitch:0)
            check(abs(fixed.render(step:0).source.z-fixed.camera.z-0.9)<0.00003,"teleport retained obsolete camera motion")
            _=motor.update(delta:1/60,displacement:SIMD3(1.0/60,0,0),geometryReady:true)
            let committed=motor.stepVelocity
            _=motor.update(delta:1/60,displacement:SIMD3(1.0/60,0,0),geometryReady:false)
            check(motor.stepVelocity==committed && fixed.currentFootVelocity == .zero,"streaming suspension destroyed momentum or exported movement")
            fixed.camera=motor.state.feet;fixed.gameCamera.resetFoot(heading:0,pitch:0)
            check(abs(fixed.render(step:0).source.z-fixed.camera.z-0.9)<0.00003,"unavailable movement retained moving-camera stance")
        }
        // Nil/invalid hints preserve the archived camera path exactly.
        for invalid:Float? in [nil,-1,.nan,.infinity] {
            let a=try NativeGameCamera(data:data),b=try NativeGameCamera(data:data)
            for i in 0..<120 {
                let p=SIMD3<Float>(Float(i)/60,0,0)
                let actual=a.followFoot(.init(position:p,crouching:true,planarSpeed:invalid),delta:1/60)!
                let expected=b.followFoot(.init(position:p,crouching:true),delta:1/60)!
                check(actual.source==expected.source && actual.target==expected.target,"invalid hint changed archived contract")
            }
        }
        let shaken=try NativeGameCamera(data:data),normal=try NativeGameCamera(data:data)
        let vehicle=NativeGameCamera.Vehicle(position:SIMD3(0,0,1),forward:SIMD3(0,1,0),right:SIMD3(1,0,0),
            bounds:.init(maxX:1,minY:-2,maxZ:1.5))
        _=shaken.followVehicle(vehicle,delta:1/60,nowMilliseconds:1000,random:{0.9})
        _=normal.followVehicle(vehicle,delta:1/60,nowMilliseconds:1000,random:{0.9})
        shaken.shake(at:SIMD3(0,0,1),strength:0.6,nowMilliseconds:1000)
        let before=shaken.followVehicle(vehicle,delta:1/60,nowMilliseconds:1016,random:{0.9})!
        let expectedBefore=normal.followVehicle(vehicle,delta:1/60,nowMilliseconds:1016,random:{0.9})!
        check(before.source != expectedBefore.source,"shake reset fixture did not start an effect")
        shaken.cancelShake()
        let after=shaken.followVehicle(vehicle,delta:1/60,nowMilliseconds:1033,random:{preconditionFailure("old shake consumed randomness after world reset")})!
        let expectedAfter=normal.followVehicle(vehicle,delta:1/60,nowMilliseconds:1033,random:{0.9})!
        check(after.source==expectedAfter.source && after.target==expectedAfter.target,"previous peer camera shake survived world reset")
        let report:[String:Any]=["pass":true,"checks":checks,"cases":results,
                                "scope":"Native motor/render ownership; original retail-runtime parity remains unverified"]
        print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),encoding:.utf8)!)
    }
}
