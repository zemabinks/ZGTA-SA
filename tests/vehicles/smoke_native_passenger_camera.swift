// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
import Darwin

// HTTP and physics storage are explicit boundaries. The actual camera, source
// coordinate functions, wire value types and Renderer adapter/frame methods
// are compiled below. No network call is permitted or simulated as successful.
protocol NativeResourceTask:AnyObject{func resume();func cancel()}
struct ServerAddress{func path(_ value:String)->URL{preconditionFailure("Camera fixture must not resolve HTTP")}}
enum NativeResourceTransport {
    static func dataTask(with url:URL,completionHandler:@escaping(Data?,URLResponse?,Error?)->Void)->NativeResourceTask {
        preconditionFailure("Camera fixture must not request HTTP")
    }
}
enum SwiftRapierWorld {
    // ACTUAL_AXIS_CONVERSION
}
enum NativeGroundVehicle {
    // ACTUAL_GROUND_COORDINATES
}
// ACTUAL_WIRE_TYPES

final class CameraBodyStorage {
    struct Info{let body:UInt64?}
    struct State{let linearVelocity:SIMD3<Float>;let angularVelocity:SIMD3<Float>}
    var infos:[UInt64:Info]=[:],states:[UInt64:State]=[:]
    func colliderInfo(_ id:UInt64)->Info?{infos[id]}
    func bodyState(_ id:UInt64)->State?{states[id]}
}
final class CameraGroundStorage {
    struct Other{let transform:simd_float4x4}
    let world=CameraBodyStorage()
    var owned:NativeGroundVehicle.CameraFrame?
    var ownedReads=0
    var cameraFrame:NativeGroundVehicle.CameraFrame?{ownedReads+=1;return owned}
    var others:[String:Other]=[:],colliders:[String:Set<UInt64>]=[:]
    func otherVehicle(_ id:String)->Other?{others[id]}
    func otherVehicleColliders(id:String)->Set<UInt64>{colliders[id] ?? []}
}
final class CameraAdapterHarness {
    // ACTUAL_CAMERA_DEFINITION
    // ACTUAL_SHARED_FRAME_TYPE
    var passengerSeat:Int?
    var isPassenger:Bool{passengerSeat != nil}
    var currentVehicleID:String?,passengerFrame:SharedVehicleFrame?
    var activeVehicleModel="900",vehicleKind="car",driving=true
    var groundVehicle:CameraGroundStorage?=CameraGroundStorage()
    var cameraVehicleDefinitions:[String:CameraVehicleDefinition]=[:]
    var riderDefinitions:NativeRiderDefinitions?
    var camera=SIMD3<Float>.zero,heading:Float=0,vehiclePitch:Float=0,vehicleFallbackRoll:Float=0
    var vehicleRoll:Float{vehicleFallbackRoll}
    var drivingSpeed:Float=0,flightVerticalSpeed:Float=0
    var vehicleWirePosition=SIMD3<Float>.zero,nativeVehicleTransform:simd_float4x4?
    var currentWireVelocity=SIMD3<Float>.zero,currentWireAngularVelocity=SIMD3<Float>.zero
    var remoteVehicles:[RemoteVehicle]=[],remotePlayers:[RemotePlayer]=[]
    // Prediction is a storage boundary; this test does not simulate its physics.
    func predictedVehicle(_ value:RemoteVehicle)->RemoteVehicle{value}
    func vehicleModelOrigin(_ code:String)->Float{cameraVehicleDefinitions[String(code.split(separator:".")[0])]?.origin ?? 0}
    // ACTUAL_RENDERER_MATRICES
    // ACTUAL_SHARED_FRAME_METHOD
    // ACTUAL_CAMERA_ADAPTER
}

@main enum PassengerCameraSmoke {
    struct Failure:Error{let message:String}
    static var checks=0,outputFrames=0
    static func check(_ value:Bool,_ message:String)throws{checks+=1;if !value{throw Failure(message:message)}}
    static func near(_ a:SIMD3<Float>,_ b:SIMD3<Float>,_ message:String)throws{
        try check(a.x.isFinite && a.y.isFinite && a.z.isFinite && simd_distance(a,b)<0.00008,message)
    }
    static func column(_ matrix:simd_float4x4,_ index:Int)->SIMD3<Float>{let c=matrix[index];return SIMD3(c.x,c.y,c.z)}
    static func cameraData()throws->Data{
        // Invented metadata with the real schema; no owner assets or goldens.
        let profile:[Double]=[1.1,0.9,0.3,6,10,0.6,0.8,0.7,0.9,0.3,0.04,0.06,0.7,0.9,1.4]
        let kinds=["car","bike","heli","plane"]
        let data:[String:Any]=["vehicleProfiles":Dictionary(uniqueKeysWithValues:kinds.map{($0,profile)}),
            "vehicleDistances":Dictionary(uniqueKeysWithValues:kinds.map{($0,[2.0,4,6])}),
            "vehicleAngles":Dictionary(uniqueKeysWithValues:kinds.map{($0,[0.06,0.08,0.1])}),
            "cinematic":["ground":[10,3,2,20],"air":[30,5,6,60]],"footDistances":[1,2,3],
            "footSights":Dictionary(uniqueKeysWithValues:["scope","camera","rocket"].map{($0,["first":55,"least":15,"most":80])}),
            "footWeaponFov":[[22,65]],"weaponSights":["34":"scope"]]
        return try JSONSerialization.data(withJSONObject:data)
    }
    static func configure(_ harness:CameraAdapterHarness,origin:Float,kind:String="car"){
        let bounds=CameraAdapterHarness.CameraVehicleDefinition.Bounds(maxX:1,minY:-2,maxZ:1.5,
            box:.init(min:[-1,-2,-0.4],max:[1,2,1.5]))
        harness.cameraVehicleDefinitions["900"] = .init(kind:kind,origin:origin,bounds:bounds,driverEye:[-0.4,0.1,-0.1])
        let seats=[NativeRiderDefinitions.Seat(at:[-0.4,0.1,-0.1],side:-1,rear:false,opens:true,door:2,via:nil,shift:nil,turn:nil),
                   NativeRiderDefinitions.Seat(at:[0.4,0.1,-0.1],side:1,rear:false,opens:true,door:3,via:nil,shift:[0.03,-0.02,0.01],turn:nil),
                   NativeRiderDefinitions.Seat(at:[0.4,-0.7,-0.1],side:1,rear:true,opens:true,door:5,via:nil,shift:nil,turn:nil)]
        harness.riderDefinitions = .init(models:["900":.init(model:"invented",astride:false,clips:[:],seats:seats,origin:Double(origin),bike:nil,afloat:false,group:nil)])
    }
    static func car(_ id:String="shared",position:SIMD3<Float>,heading:Float,pitch:Float,roll:Float)->RemoteVehicle {
        RemoteVehicle(row:[id,"Authored","900.0.0.0.",position.x,position.y,position.z,-heading,pitch,-roll,1000,""])!
    }
    static func player(position:SIMD3<Float>,heading:Float,pitch:Float,roll:Float,velocity:SIMD3<Float>,spin:SIMD3<Float>)->RemotePlayer {
        var result=RemotePlayer(id:"2",name:"Authored",position:position,code:"900.0.0.0.",heading:heading,pitch:pitch,roll:roll,
            speed:7,steer:0,skin:1,animation:"",animationStarted:0,weapon:0,vehicleID:"shared")
        result.velocity=velocity;result.angularVelocity=spin;return result
    }
    static func pose(body:SIMD3<Float>,heading:Float,pitch:Float,roll:Float,origin:Float)->simd_float4x4 {
        let rotation=NativeGroundVehicle.rotation(heading:heading,pitch:pitch,roll:roll)
        return NativeGroundVehicle.transform(position:SIMD3<Double>(SwiftRapierWorld.gtaToRapier(body)),
            rotation:simd_quatd(ix:Double(rotation.imag.x),iy:Double(rotation.imag.y),iz:Double(rotation.imag.z),r:Double(rotation.real)),origin:Double(origin))
    }
    static func output(_ actual:NativeGameCamera.Vehicle,_ expected:NativeGameCamera.Vehicle,_ data:Data)throws{
        for hz in [15,30,60,120] {for view in [2,4,5] {
            let a=try NativeGameCamera(data:data),b=try NativeGameCamera(data:data)
            a.setVehicleView(view);b.setVehicleView(view)
            for _ in 0..<hz {
                let count=max(1,Int(ceil((1.0/Double(hz))/(1.0/60)-1e-8))),dt=Float(1.0/Double(hz)/Double(count))
                for _ in 0..<count {
                    let aa=a.followVehicle(actual,delta:dt,nowMilliseconds:1000,random:{0.5})!
                    let bb=b.followVehicle(expected,delta:dt,nowMilliseconds:1000,random:{0.5})!
                    try near(aa.source,bb.source,"actual camera source diverged from shared body/seat")
                    try near(aa.target,bb.target,"actual camera target diverged from shared body/seat")
                    try check(abs(aa.verticalFov-bb.verticalFov)<0.00001,"camera FOV changed by role adapter")
                    outputFrames+=1
                }
            }
        }}
    }
    static func main() {
        do {
            let data=try cameraData()
            var configurations=0
            for origin:Float in [0,0.35,1.2] {for yaw:Float in [0,.pi/2,.pi,-.pi/2] {for roll:Float in [0,0.4] {
                let h=CameraAdapterHarness();configure(h,origin:origin)
                h.passengerSeat=1;h.currentVehicleID="shared";h.heading=yaw;h.vehiclePitch=0.2;h.vehicleFallbackRoll=roll
                let body=SIMD3<Float>(10,20,3),matrix=pose(body:body,heading:yaw,pitch:0.2,roll:roll,origin:origin)
                let velocity=SIMD3<Float>(4,6,2),spin=SIMD3<Float>(0.2,0.3,0.4)
                h.remotePlayers=[player(position:body,heading:yaw,pitch:0.2,roll:roll,velocity:velocity,spin:spin)]
                h.remoteVehicles=[car(position:body,heading:yaw,pitch:0.2,roll:roll)]
                let shared=h.sharedVehicleFrame(id:"shared")!;h.passengerFrame=shared;h.camera=column(shared.transform,3)
                try near(column(shared.transform,3),column(matrix,3),"shared MODEL ROOT/origin changed")
                let actual=h.nativeCameraVehicle()!
                let seat=h.riderDefinitions!.models["900"]!.seats[1].position!
                try near(actual.eye ?? .zero,seat,"passenger eye lost selected seat")
                try near(actual.position,column(matrix,3),"passenger model origin applied twice")
                try near(actual.right,column(matrix,0),"passenger roll lost right basis")
                try near(actual.forward,column(matrix,1),"passenger pitch/yaw lost forward basis")
                try near(actual.up ?? .zero,column(matrix,2),"passenger roll lost up basis")
                try near(actual.moveSpeed,velocity/50,"passenger sideslip/vertical velocity lost")
                try near(actual.turnSpeed,spin/50,"passenger angular velocity lost")
                try check(h.groundVehicle!.ownedReads==0,"passenger consulted unrelated owned body")
                let bounds=actual.bounds
                let expected=NativeGameCamera.Vehicle(kind:"car",position:column(matrix,3),forward:column(matrix,1),right:column(matrix,0),up:column(matrix,2),
                    moveSpeed:velocity/50,turnSpeed:spin/50,wheels:4,bounds:bounds,heightAboveRoad:origin,eye:seat)
                try output(actual,expected,data);configurations+=1
            }}}
            let h=CameraAdapterHarness();configure(h,origin:0.35)
            h.passengerSeat=1;h.currentVehicleID="shared"
            try check(h.nativeCameraVehicle()==nil,"missing passenger frame fell back to driver")
            let m=pose(body:SIMD3(10,20,3),heading:0,pitch:0,roll:0.3,origin:0.35)
            h.passengerFrame = .init(vehicle:car("wrong",position:.zero,heading:0,pitch:0,roll:0),transform:m,speed:0,velocity:.zero)
            try check(h.nativeCameraVehicle()==nil,"wrong vehicle frame accepted")
            h.passengerFrame = .init(vehicle:car(position:.zero,heading:0,pitch:0,roll:0),transform:m,speed:0,velocity:.zero)
            h.cameraVehicleDefinitions=[:];try check(h.nativeCameraVehicle()==nil,"missing camera definition fell back to driver")
            configure(h,origin:0.35);h.passengerSeat=7
            try check(h.nativeCameraVehicle()!.eye==nil,"missing selected seat invented driver eye")
            h.passengerSeat=2
            try near(h.nativeCameraVehicle()!.eye!,h.riderDefinitions!.models["900"]!.seats[2].position!,"rear seat camera uses front seat")

            // Preserve the owned-driver fast path despite stale passenger data.
            h.passengerSeat=nil;h.vehicleKind="helicopter"
            let stored=NativeGroundVehicle.CameraFrame(position:SIMD3(3,4,5),forward:SIMD3(0,1,0),right:SIMD3(1,0,0),up:SIMD3(0,0,1),
                moveSpeed:SIMD3(0.1,0.2,0.3),turnSpeed:SIMD3(0.2,0.3,0.4),wheels:0,maxX:2,minY:-3,maxZ:2,
                minimum:SIMD3(-2,-3,-1),maximum:SIMD3(2,3,2),heightAboveRoad:0.7,eye:SIMD3(-0.5,0,0.2))
            h.groundVehicle!.owned=stored
            let driver=h.nativeCameraVehicle()!;try check(driver.kind=="heli" && driver.wheels==0,"owned driver path changed")
            try near(driver.position,stored.position,"driver position changed");try near(driver.moveSpeed,stored.moveSpeed,"driver velocity changed")
            try near(driver.turnSpeed,stored.turnSpeed,"driver angular velocity changed");try near(driver.eye!,stored.eye!,"driver eye changed")

            // Actual shared-frame parked-body query with explicit physics storage.
            h.groundVehicle!.owned=nil;h.driving=false;h.remotePlayers=[]
            let body=SIMD3<Float>(10,20,3);h.remoteVehicles=[car(position:body,heading:0,pitch:0,roll:0)]
            let parkedMatrix=pose(body:body,heading:0,pitch:0,roll:0,origin:0.35)
            h.groundVehicle!.others["shared"] = .init(transform:parkedMatrix)
            h.groundVehicle!.colliders["shared"]=[9]
            h.groundVehicle!.world.infos[9] = .init(body:8)
            h.groundVehicle!.world.states[8] = .init(linearVelocity:SIMD3(2,3,-4),angularVelocity:SIMD3(0.2,0.3,-0.4))
            let parked=h.sharedVehicleFrame(id:"shared")!
            try near(parked.velocity,SIMD3(2,4,3),"parked velocity axes lost")
            try near(parked.angularVelocity,SIMD3(0.2,0.4,0.3),"parked spin axes lost")
            h.groundVehicle!.world.states=[:]
            let missing=h.sharedVehicleFrame(id:"shared")!
            try near(missing.velocity,.zero,"missing parked motion invented");try near(missing.angularVelocity,.zero,"missing parked spin invented")
            let result:[String:Any]=["status":"PASS","checks":checks,"configurations":configurations,"actualCameraOutputFrames":outputFrames,
                "actualRendererAdapter":true,"actualNativeGameCamera":true,"physicsStorageSpy":true,"syntheticMetadata":true,"renderedOrRetailAcceptance":false]
            print(String(data:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),encoding:.utf8)!)
        }catch{
            let result:[String:Any]=["status":"FAIL","checks":checks,"failure":(error as? Failure)?.message ?? String(describing:error)]
            print(String(data:try! JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),encoding:.utf8)!);exit(1)
        }
    }
}
