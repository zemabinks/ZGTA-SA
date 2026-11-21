// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CoreFoundation
import simd

// ACTUAL_PLAYER
// ACTUAL_VEHICLE_SEATS
// ACTUAL_REMOTE_VEHICLE

// Read-only admitted snapshots and identity tokens. These boundaries do not
// implement simulation, rig sampling, geometry or production owner predicates.
final class NativeSkeletalActor {}
final class NativeVehicleRig {}
final class Playback {enum State {case out,entering,inside,leaving,stood};var state:State = .inside}
struct TrafficActor {var generation:UInt64=42,flags:UInt8=0,deadSeats:UInt8=0,crewCount:UInt8?=3}
final class Traffic {var actors:[UInt16:TrafficActor]=[:]}
final class NativeAmbientTrafficScene {
    struct Frame {
        struct Identity {let id:UInt16}
        struct Body {var position:SIMD3<Double>;var heading:Double=0,pitch:Double=0}
        let identity:Identity,generation:UInt64,code:String
        var body:Body
    }
    let traffic=Traffic()
}
enum NativeOtherVehicles {
    struct Snapshot {
        var position:SIMD3<Float>,heading:Float=0,pitch:Float=0,roll:Float=0,health:Int=1000,damage:String="",work:Int=0
        var rotor:Double=0,gearUp=false,dynamic=false,frontSpin:Double=0,rearSpin:Double=0,offsets:[Double]=[]
        var transform:simd_float4x4
    }
}
final class GroundSnapshot {
    var snapshots:[String:NativeOtherVehicles.Snapshot]=[:],origin:Float=0,reads=0
    func otherVehicle(_ id:String)->NativeOtherVehicles.Snapshot?{reads+=1;return snapshots[id]}
    func modelOrigin(_ code:String)->Float{origin}
}
struct Seat {var id:UInt16=3,generation:UInt64=42,index:Int=0,skin:Int=7,dead=false}
final class Rider {var falling=false}
final class Retention {var thrown=false;func isThrown(id:UInt16,generation:UInt64)->Bool{thrown}}

final class Harness {
    // ACTUAL_OCCUPANT_FRAME
    // ACTUAL_VEHICLE_FRAME
    struct OwnVehicleDrawSnapshot {}
    // ACTUAL_PARKED_SNAPSHOT
    // ACTUAL_DRAW_CONTEXT
    var localShotVehicles:[LocalShotVehicleFrame]=[]
    // Retained solely to compile the historical predicate negative control.
    var localShotVehiclesAt=100.0,now=100.1
    var source="source-A",localShotVehicleSource:String?="source-A"
    let localShotPlayerOwners=NativeShotOwners.Ledger<NativeShotOwners.Player>()
    let localShotRegisteredOwners=NativeShotOwners.Ledger<NativeShotOwners.Vehicle>()
    var remotePlayers:[RemotePlayer]=[]{didSet{recordLocalShotPlayerOwners()}}
    var presentedRemotePlayers:[RemotePlayer]{get{remotePlayers}set{remotePlayers=newValue}}
    var remoteVehicles:[RemoteVehicle]=[]{didSet{recordLocalShotRegisteredOwners()}}
    var presentedAmbientTraffic:[NativeAmbientTrafficScene.Frame]=[]
    var skeletalActors:[String:NativeSkeletalActor]=[:],pedModels=["7":"ped"]
    var localShotMeshes:[String:NativeLocalShotMesh]=[:],vehicleRigs:[String:NativeVehicleRig]=[:]
    var vehicleRigMeshes:[String:Int]=[:],remoteRiderPlayback:[String:(String,Playback)]=[:]
    let ambientTraffic=NativeAmbientTrafficScene(),trafficRiderRetention=Retention()
    var trafficOccupantSeats:[Seat]=[],trafficRiderOwners:[String:Rider]=[:]
    var groundVehicle:GroundSnapshot?=GroundSnapshot()
    func fixedCJSourceIdentity()->String{source}
    func riderMonotonicNow()->Double{now}
    // ACTUAL_DRIVER_ROLE
    // ACTUAL_PLAYER_ADMISSION
    // ACTUAL_VEHICLE_ADMISSION
    // ACTUAL_VEHICLE_INCARNATION
    // ACTUAL_OCCUPANT_INCARNATION
    // ACTUAL_OCCUPANT_QUERY
    // ACTUAL_CURRENT_BODY
    // ACTUAL_VEHICLE_QUERY
    // ACTUAL_REMOTE_CONTEXT
    // ACTUAL_PARKED_CONTEXT
    // ACTUAL_TRAFFIC_CONTEXT
    // ACTUAL_BODY_TRANSFORM
    // ACTUAL_RENDER_KEY
    // ACTUAL_SHOT_MATRIX
    // ACTUAL_PREDICTED_VEHICLE
    // ACTUAL_APPLY_SNAPSHOT
    // ACTUAL_MODEL_ORIGIN
    // ACTUAL_TRANSLATION
    // ACTUAL_ROTATION_X
    // ACTUAL_ROTATION_Y
    // ACTUAL_ROTATION_Z
    // ACTUAL_VEHICLE_HITS
}

@main struct Gate {
    static var checks=0
    static func check(_ condition:Bool,_ message:String){checks+=1;if !condition{print("FAIL: \(message)");exit(1)}}
    static func close(_ a:SIMD3<Double>,_ b:SIMD3<Double>)->Bool{simd_distance(a,b)<0.00001}
    static func origin(_ m:simd_double4x4)->SIMD3<Double>{SIMD3(m.columns.3.x,m.columns.3.y,m.columns.3.z)}
    static func mesh()->NativeLocalShotMesh {
        NativeLocalShotMesh(positions:[SIMD3(-1,0,-1),SIMD3(1,0,-1),SIMD3(1,0,1),SIMD3(-1,0,1)],
            indices:[0,1,2,0,2,3],surfaces:[.init(node:0,start:0,count:6,side:2,transparent:false,opacity:1,additive:false)])!
    }
    static func player(id:String="p",skin:Int=7,driver:Bool=false,car:String="car",seat:Int=1,position:SIMD3<Float> = .zero,heading:Float=0)->RemotePlayer {
        var p=RemotePlayer(id:id,name:id,position:position,code:driver ? "420":"s7",heading:heading,pitch:0,roll:0,speed:0,steer:0,skin:skin,animation:"",animationStarted:0,weapon:0,vehicleID:driver ? car:nil)
        if !driver{p.ridingVehicleID=car;p.ridingSeat=seat}
        return p
    }
    static func registered(_ id:String="car",code:String="420")->RemoteVehicle{RemoteVehicle(row:[id,id,code,0,0,0,0])!}
    static func base(traffic:Bool=false,driver:Bool=false)->Harness {
        let h=Harness(),actor=NativeSkeletalActor(),geometry=mesh(),rig=NativeVehicleRig()
        h.skeletalActors["ped"]=actor;h.localShotMeshes["taxi"]=geometry;h.vehicleRigs["taxi"]=rig;h.vehicleRigMeshes["taxi"]=1
        let occupant:Harness.LocalShotOccupantFrame
        let owner:Harness.LocalShotVehicleFrame.Owner,key:String,target:NativeLocalShots.Target
        let spheres=[NativeLocalShots.BodySphere(center:SIMD3(0,0,0.5),radius:0.15,piece:9,bone:5)]
        if traffic {
            h.ambientTraffic.traffic.actors[3]=TrafficActor();h.trafficOccupantSeats=[Seat()];h.trafficRiderOwners["c3.0"]=Rider()
            h.presentedAmbientTraffic=[.init(identity:.init(id:3),generation:42,code:"420",body:.init(position:.zero))]
            occupant = .init(owner:.traffic(id:3,generation:42,seat:0,skin:7),model:"ped",actor:actor,incarnation:42,hit:.init(id:"c3.0",spheres:spheres))
            owner = .traffic(3,42);key="traffic:3:42";target = .init(id:"t3",kind:3)
        }else {
            h.remotePlayers=[player(driver:driver)];h.remoteRiderPlayback["p"]=("bound",Playback())
            let occupantOwner=Harness.LocalShotOccupantFrame.Owner.player(id:"p",skin:7,car:"car",seat:driver ? 0:1,driver:driver)
            occupant = .init(owner:occupantOwner,model:"ped",actor:actor,incarnation:h.localShotOccupantIncarnation(occupantOwner)!,hit:.init(id:"p",spheres:spheres))
            owner = driver ? .player("p","420"):.registered("car","420");key="vehicle:car";target = .init(id:driver ? "p":"car",kind:driver ? 2:3)
            h.remoteVehicles=[registered()]
        }
        h.localShotVehicles=[.init(owner:owner,key:key,target:target,mesh:geometry,model:"taxi",rig:ObjectIdentifier(rig),incarnation:h.localShotVehicleIncarnation(owner)!,body:matrix_identity_double4x4,matrices:[matrix_identity_double4x4],visible:[true],low:SIMD3(repeating:-1),high:SIMD3(repeating:1),nominalTyres:[.init(index:0,center:.zero,radius:0.2)],occupants:[occupant],tyres:[.init(index:0,center:.zero,radius:0.2)])]
        return h
    }
    static func occupantCount(_ h:Harness)->Int{h.currentLocalShotVehicleFrames().reduce(0){$0+$1.occupants.count}}
    static func ray(_ x:Double)->NativeLocalShots.Ray{.init(origin:SIMD3(x,-5,0),direction:SIMD3(0,1,0),range:20,minimum:0)}
    static func main(){
        var h=base(driver:true);h.remotePlayers[0].position.x=10
        var frames=h.currentLocalShotVehicleFrames()
        check(frames.count==1 && close(origin(frames[0].body),SIMD3(10,0,0)),"Moving owner kept its previous draw body")
        let actual=h.localVehicleShotHits(ray(10),frames:frames)
        check(actual.count==1 && actual[0].target.kind==2 && abs(actual[0].distance-5)<0.00001,"Fresh body did not reach actual triangle resolver")
        check(actual[0].target.wheel==0,"Nominal tyre zero did not follow fresh body")
        check(h.localVehicleShotHits(ray(0),frames:frames).isEmpty,"Old body still accepted a hull ray")
        h.remotePlayers[0].position.x=20
        check(h.localVehicleShotHits(ray(10),frames:frames).count==1,"Frozen emission changed after later admission")
        check(close(origin(h.currentLocalShotVehicleFrames()[0].body),SIMD3(20,0,0)),"Next emission did not observe current body")
        h=base(driver:true);h.groundVehicle!.origin=2;h.remotePlayers=[player(driver:true,position:SIMD3(10,20,5),heading:.pi/2)]
        let rotated=h.currentLocalShotVehicleFrames()[0].body*SIMD4<Double>(1,0,0,1)
        check(close(SIMD3(rotated.x,rotated.y,rotated.z),SIMD3(10,19,7)),"Yaw sign or original model origin changed")
        h=base();var exact=matrix_identity_float4x4;exact.columns.3=SIMD4(7,8,9,1)
        h.groundVehicle!.origin=100;h.groundVehicle!.snapshots["car"] = .init(position:SIMD3(90,80,70),transform:exact)
        frames=h.currentLocalShotVehicleFrames()
        check(close(origin(frames[0].body),SIMD3(7,8,9)),"Physical exact transform lost priority or received origin twice")
        check(h.groundVehicle!.reads==2,"Shot query advanced/repeated physical sampling unexpectedly")
        check(close(frames[0].occupants[0].hit.spheres[0].center,SIMD3(0,0,0.5)),"Human manual-follow world pose was rebased as ordinary compact seat")
        h=base(traffic:true);h.presentedAmbientTraffic[0].body.position=SIMD3(10,0,0)
        frames=h.currentLocalShotVehicleFrames()
        check(close(origin(frames[0].body),SIMD3(10,0,0)),"Compact query ignored already admitted presentation body")
        check(close(frames[0].occupants[0].hit.spheres[0].center,SIMD3(10,0,0.5)),"Active compact seat did not follow current hull")
        check(close(frames[0].tyres[0].center,SIMD3(10,0,0)),"Compact tyre did not follow current hull")
        h=base();h.now=1000;check(h.currentLocalShotVehicleFrames().count==1,"Valid owned geometry expired solely with render time")
        h.now=99;check(h.currentLocalShotVehicleFrames().count==1,"Wall-clock reversal changed owner validity")
        h=base();let p=h.remotePlayers[0];h.remotePlayers=[];h.remotePlayers=[p]
        check(occupantCount(h)==0 && h.currentLocalShotVehicleFrames().count==1,"Reused player ID inherited old occupant spheres or removed valid registered cover")
        h=base();let v=h.remoteVehicles[0];h.remoteVehicles=[];h.remoteVehicles=[v]
        check(h.currentLocalShotVehicleFrames().isEmpty,"Reused registry ID inherited old completed geometry")
        h=base(driver:true);let driver=h.remotePlayers[0];h.remotePlayers=[];h.remotePlayers=[driver]
        check(h.currentLocalShotVehicleFrames().isEmpty,"Reused driver ID inherited old completed hull")
        h=base(traffic:true);var promoted=registered("promoted");promoted.trafficSourceID=3;h.remoteVehicles=[promoted]
        check(h.currentLocalShotVehicleFrames().isEmpty,"Promoted compact hull was admitted twice")
        h=base(driver:true);h.remotePlayers[0].position.x = .nan
        check(h.currentLocalShotVehicleFrames().isEmpty,"Nonfinite current root entered geometry")
        h=base();check(occupantCount(h)==1,"Current live passenger was rejected")
        h.remotePlayers[0].life=0
        check(h.currentLocalShotVehicleFrames().count==1,"Dead passenger removed otherwise valid hull cover")
        check(occupantCount(h)==0,"Cached passenger remained damageable after death")
        h=base();h.remotePlayers.removeAll();check(occupantCount(h)==0,"Removed player retained cached body")
        h=base();h.remotePlayers=[player(skin:8)];check(occupantCount(h)==0,"Replacement skin reused cached spheres")
        h=base();h.remotePlayers=[player(car:"other")];check(occupantCount(h)==0,"Passenger switched hull without retiring spheres")
        h=base();h.remotePlayers=[player(seat:2)];check(occupantCount(h)==0,"Passenger switched seats without retiring spheres")
        for state in [Playback.State.out,.stood] {h=base();h.remoteRiderPlayback["p"]!.1.state=state;check(occupantCount(h)==0,"Retired/standing rider supplied cached body")}
        h=base();h.remoteRiderPlayback["p"]!.1.state = .leaving;check(occupantCount(h)==1,"Valid retained leaving pose was discarded")
        h=base();h.skeletalActors["ped"]=NativeSkeletalActor();check(occupantCount(h)==0,"Replaced rig reused cached spheres")
        h=base();h.pedModels["7"]="replacement";check(occupantCount(h)==0,"Changed skin resource reused cached body")
        h=base();h.localShotMeshes["taxi"]=mesh();check(h.currentLocalShotVehicleFrames().isEmpty,"Replaced mesh reused cached hull")
        h=base();h.vehicleRigs["taxi"]=NativeVehicleRig();check(h.currentLocalShotVehicleFrames().isEmpty,"Replaced built rig reused cached matrices")
        h=base();h.vehicleRigMeshes.removeAll();check(h.currentLocalShotVehicleFrames().isEmpty,"Unready vehicle retained hull")
        h=base(driver:true);check(occupantCount(h)==1,"Current driver was rejected")
        h.remotePlayers=[player(driver:true,car:"other")];check(h.currentLocalShotVehicleFrames().isEmpty,"Same model driver switched registered identity but kept old hull")
        h=base(driver:true);h.remotePlayers=[player()];check(h.currentLocalShotVehicleFrames().isEmpty,"New passenger role retained driver hull")
        h=base(traffic:true);check(occupantCount(h)==1,"Current traffic crew was rejected")
        h.ambientTraffic.traffic.actors[3]!.deadSeats=1
        check(h.currentLocalShotVehicleFrames().count==1 && occupantCount(h)==0,"Dead traffic occupant retained body or erased hull cover")
        h=base(traffic:true);h.ambientTraffic.traffic.actors[3]!.generation=43;check(h.currentLocalShotVehicleFrames().isEmpty,"Traffic ID reuse retained old frame")
        h=base(traffic:true);h.ambientTraffic.traffic.actors[3]!.flags=32;check(occupantCount(h)==0,"Hidden traffic crew retained body")
        h=base(traffic:true);h.trafficRiderOwners["c3.0"]!.falling=true;check(occupantCount(h)==0,"Falling rider remained a seated target")
        h=base(traffic:true);h.trafficRiderOwners.removeAll();check(occupantCount(h)==0,"Retired traffic controller supplied old body")
        h=base(traffic:true);h.trafficRiderRetention.thrown=true;check(occupantCount(h)==0,"Detached traffic crew supplied old seated body")
        h=base(traffic:true);h.trafficOccupantSeats[0].skin=8;check(occupantCount(h)==0,"Traffic crew replacement reused old skin")
        h=base(traffic:true);h.presentedAmbientTraffic=[];check(h.currentLocalShotVehicleFrames().isEmpty,"Missing admitted compact presentation reused body")
        h=base();h.source="source-B";check(h.currentLocalShotVehicleFrames().isEmpty,"Changed resource source retained frame")
        print("PASS \(checks) actual owner/current-body/triangle/tyre/lifetime checks; authored snapshot and identity boundaries, no App/retail claim")
    }
}
