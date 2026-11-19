// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
import Darwin

// The real renderer entry branch and visual-counter getter are inserted here.
// This disposable host carrier is never linked into the App.
final class OwnedWheelEntryProbe {
    let groundVehicle:NativeGroundVehicle
    var pendingVehicleSnapshot:NativeOtherVehicles.Snapshot?
    var activeVehicleModel="900",camera=SIMD3<Float>.zero,heading:Float=0,vehiclePitch:Float=0,vehicleFallbackRoll:Float=0
    var currentVehicleID:String?="authored-owner"
    struct Vehicle {let id:String,work:Int}
    var remoteVehicles=[Vehicle]()
    init(_ ground:NativeGroundVehicle){groundVehicle=ground}
    // ACTUAL_COUNTER_GETTER
    func admit(){guard !groundVehicle.active else{return}
        // ACTUAL_ENTRY_HANDOFF
    }
    var counters:[Double]{ownVehicleWheelClocks}
}

// Opaque records permit executing the literal raw wheel selector without a
// model/texture/graphics context. They carry no game data or render algorithm.
enum NativeVehicleRig{struct Input{}}
struct RemotePlayer{}
struct RemoteVehicle{}
final class RawWheelProbe{
    // ACTUAL_RAW_CONTEXT
    // ACTUAL_RAW_SELECTOR
    static func sample(_ angles:[Float],known:Bool,exact:Bool,index:Int=0,speed:Float=3,time:Float=10)->Float{
        let own=OwnVehicleDrawSnapshot(input:.init(),doors:nil,wheelOffsets:[:],wheelAngles:angles,speed:speed,steering:0,rearSteering:0,fallbackSteering:0,wheelPhaseOwned:known)
        let context=VehicleDrawContext(source:.own(own),token:"authored",appearanceCode:"900",roll:0,origin:0,exactTransform:exact ? matrix_identity_float4x4:nil,heldDoorID:nil)
        return legacyVehicleWheel(index:index,front:index%2==0,context:context,time:time).spin
    }
}

@main enum OwnedWheelPhaseGate {
    struct Failure:Error {let message:String}
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws{checks+=1;if !value{throw Failure(message:message)}}
    static func near(_ a:Double,_ b:Double,_ message:String)throws{try check(a.isFinite && b.isFinite && abs(a-b)<1e-9,message)}
    static func row(_ id:Int)->[String:Any]{
        var wheels=[[String:Any]]()
        for front in [true,false]{for left in [true,false]{wheels.append(["centre":[left ? -0.65:0.65,0.0,front ? 1.0:-1.0],"radius":0.36,"front":front,"left":left])}}
        return ["id":id,"solverSupported":true,"kind":"car","origin":0.55,
            "table":["mass":1100.0,"turnMass":2600.0,"springs":1.1,"damping":0.12,"traction":0.7,"drag":1.8],
            "wheels":wheels,"chassis":[["kind":"box","centre":[0.0,0,0],"halfExtents":[0.7,0.32,1.3],"friction":0.5]],
            "bounds":["box":["min":[-0.7,-1.3,-0.32],"max":[0.7,1.3,0.32]]]]
    }
    static func make()throws->NativeGroundVehicle{
        guard let ground=NativeGroundVehicle()else{throw Failure(message:"actual physics manager")}
        let data=try JSONSerialization.data(withJSONObject:["models":["900":row(900),"901":row(901)],"materialClasses":[Int](repeating:0,count:256)])
        try check(ground.loadDefinitions(data)==2,"authored definitions admitted")
        var flat=Data();func word(_ value:UInt32){var value=value.littleEndian;withUnsafeBytes(of:&value){flat.append(contentsOf:$0)}}
        [UInt32(0x324c4353),4,2,1].forEach(word)
        for value:Float in [-1000,-1000,0,1000,-1000,0,1000,1000,0,-1000,1000,0]{word(value.bitPattern)}
        [UInt32(0),1,2,0,2,3].forEach(word);flat.append(contentsOf:[2,2,0,0,1,1,0,0])
        ground.installCell("floor",data:flat);try check(ground.isCellLoaded("floor"),"authored floor installed")
        return ground
    }
    static func body(_ ground:NativeGroundVehicle)throws->(UInt64,SwiftRapierWorld.BodyState){
        guard let collider=ground.chassisColliders.first,let id=ground.world.colliderInfo(collider)?.body,let state=ground.world.bodyState(id)else{throw Failure(message:"actual owned body")};return(id,state)
    }
    static func run()throws{
        let historical=CommandLine.arguments.contains("historical")
        if !historical{
            let expected:[Float]=[7.25,-2.5,7.25,-2.5]
            for index in expected.indices{
                try near(Double(RawWheelProbe.sample(expected,known:true,exact:false,index:index)),Double(expected[index]),"pending raw phase lost")
                try near(Double(RawWheelProbe.sample(expected,known:false,exact:true,index:index)),Double(expected[index]),"physical raw phase lost")
                try near(Double(RawWheelProbe.sample(expected,known:false,exact:false,index:index)),Double(Float(10)*Float(3)/Float(0.35)),"unknown fallback counter froze")
            }
            try near(Double(RawWheelProbe.sample([],known:true,exact:false)),Double(Float(10)*Float(3)/Float(0.35)),"absent pending index changed fallback")
        }
        var reference:[Double]?
        let schedules=[15,30,60,120].map{hz in [Double](repeating:1/Double(hz),count:hz*2)}+[(0..<40).flatMap{_ in [0.011,0.019,0.020]}]
        for frames in schedules{
            let ground=try make();try check(ground.enter(model:"900",modelPosition:SIMD3(0,0,1.1),heading:0),"ordinary authored entry")
            var input=NativeVehicleDynamics.Input();input.throttle=0.7
            for delta in frames{ground.update(delta:delta,input:input,currentCell:"floor")}
            let angles=ground.wheelAnglesDouble
            try check(angles.count==4 && abs(angles[0])+abs(angles[1])>0.1,"real owned solver rolled wheels")
            try near(angles[0],angles[2],"front axle counters diverged");try near(angles[1],angles[3],"rear axle counters diverged")
            if let reference{for index in angles.indices{try near(angles[index],reference[index],"elapsed schedule changed wheel phase")}}else{reference=angles}
            let (_,before)=try body(ground)
            ground.parkCurrentVehicle(id:"authored-owner",code:"900",health:1000,damage:"",work:0)
            try check(!ground.active,"park did not retire owned solver")
            guard let parked=ground.otherVehicle("authored-owner")else{throw Failure(message:"parked presentation exists")}
            try near(parked.frontSpin,angles[0],"owned park lost front wheel phase")
            try near(parked.rearSpin,angles[1],"owned park lost rear wheel phase")
            try check(!historical,"historical unexpectedly preserved owned phase")
            let parkedBody=ground.otherVehicleColliders(id:"authored-owner").first.flatMap{ground.world.colliderInfo($0)?.body}.flatMap{ground.world.bodyState($0)}!
            try check(parkedBody.position==before.position && parkedBody.rotation.vector==before.rotation.vector,"visual handoff changed parked pose")
            try check(parkedBody.linearVelocity==before.linearVelocity && parkedBody.angularVelocity==before.angularVelocity,"visual handoff changed parked momentum")
            guard let taken=ground.takeOtherVehicle("authored-owner")else{throw Failure(message:"parked owner acquisition")}
            try check(ground.otherVehicle("authored-owner")==nil,"acquisition retained duplicate parked representation")
            let probe=OwnedWheelEntryProbe(ground);probe.pendingVehicleSnapshot=taken
            try check(probe.counters==[taken.frontSpin,taken.rearSpin,taken.frontSpin,taken.rearSpin],"pending source lost visual axle counters")
            probe.activeVehicleModel="unsupported";probe.admit()
            try check(!ground.active && probe.pendingVehicleSnapshot != nil,"failed entry consumed pending owner")
            probe.activeVehicleModel="900";probe.camera=taken.position;probe.heading=taken.heading;probe.admit()
            try check(ground.active && probe.pendingVehicleSnapshot==nil,"successful entry did not consume owner")
            for index in angles.indices{try near(ground.wheelAnglesDouble[index],angles[index],"park-to-owned entry lost phase")}
            let (_,admitted)=try body(ground);let colliders=ground.chassisColliders
            ground.restoreWheelSpin(front:12.25,rear:-7.5)
            let (_,restored)=try body(ground)
            try check(restored.position==admitted.position && restored.rotation.vector==admitted.rotation.vector,"counter restore changed owned pose")
            try check(restored.linearVelocity==admitted.linearVelocity && restored.angularVelocity==admitted.angularVelocity,"counter restore changed owned momentum")
            try check(colliders==ground.chassisColliders,"counter restore recreated collision geometry")
            try check(probe.counters==[12.25,-7.5,12.25,-7.5],"active solver does not own counters")
            ground.restoreWheelSpin(front:.nan,rear:.infinity)
            try check(ground.wheelAnglesDouble==[0,0,0,0],"non-finite counters reached draw input")
            ground.exit();try check(ground.wheelAnglesDouble==[0,0,0,0],"exit leaked counters")
            try check(ground.enter(model:"901",modelPosition:SIMD3(4,0,1),heading:0),"replacement model entry")
            try check(ground.wheelAnglesDouble==[0,0,0,0],"replacement inherited prior phase")
            ground.exit();ground.clearOtherVehicles()
        }
    }
    static func main(){do{try run();print("PASS \(checks) actual Rapier owned/parked wheel-phase checks; literal renderer handoff and counter getter; no GPU or retail claim")}catch{print("FAIL \(checks) \(error)");exit(2)}}
}
