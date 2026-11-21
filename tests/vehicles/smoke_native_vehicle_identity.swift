// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CoreFoundation
import simd

// ACTUAL_PACKET_STRUCTS

// Sentinel records test queue/selection ownership only, not skeletal math.
private enum NativeSkeletalActor {struct Pose:Equatable{let sentinel:Int}}
private enum NativeFlightAnimation {struct Frame{let sentinel:Int};struct Canopy{let sentinel:Int}}

/// Inert source boundaries. No physics engine, original catalogue or body is
/// loaded. The actual renderer context/rig methods and rig pose math run below.
private struct GroundFixture {
    struct Output {var steering=0.0,rearSteering=0.0,brake=0.0}
    struct Damage {var state:NativeVehicleDamage}
    struct Other {
        var transform=matrix_identity_float4x4
        var work=0,rotor=0.0,gearUp=false,dynamic=false,frontSpin=0.0,rearSpin=0.0,offsets=[Double]()
    }
    var active=true
    var workingRenderValue=0.0,output:Output?,wheelAnglesDouble=[Double](),damageController:Damage?
    var others=[String:Other](),origins=[String:Float]()
    func handlingFlags(_ value:String)->Int{0}
    func modelFlags(_ value:String)->Int{0}
    func modelOrigin(_ value:String)->Float{origins[value] ?? 0}
    func otherVehicle(_ value:String)->Other?{others[value]}
}

private final class Carrier {
    var remotePlayers=[RemotePlayer](),remoteVehicles=[RemoteVehicle]()
    var pedModels=["7":"authored-ped"],vehicleModels=["420":"authored-car","522":"authored-bike","530":"authored-work","590":"authored-carriage"]
    var driving=false,isPassenger=false,currentVehicleID:String?,activeVehicleModel="420"
    var localSkin=7,health=100,swimming=false,actionTimeRemaining=1.0,locomotionClip="AUTHORED_OWN_ACTION"
    var camera=SIMD3<Float>(999,999,999),drivingSpeed:Float=0,heading:Float=0.3,vehiclePitch:Float=0.1,steeringInput:Float=0.5
    var groundVehicle:GroundFixture?,nativeVehicleTransform:simd_float4x4?
    struct Wheel {var index:Int,offset:Double}
    var nativeVehicleWheels=[Wheel](),nativeVehicleWheelAngles=[Float](),nativeBikeDrop=[Float]()
    var nativeBikeLean:Float=0,nativeBicycleCrank:Float=0,nativeRotorTurning:Float=0,nativeAircraftNozzle:Float?
    var nativeLandingGearUp=false,vehicleLights=false
    var remoteBikeFrames=[String:NativeRemoteBikeAnimation.Frame]()
    var remoteSuspensionConfigurations=[Int:NativeRemoteSuspension.Configuration]()
    var riderDoorHolds=[String:[Int:Double]]()
    var vehicleRigTimes=[String:Double](),vehicleRigStates=[String:NativeVehicleRig.State](),vehicleRigSpins=[String:SIMD2<Double>]()
    func remoteSuspensionContact(_ ray:NativeRemoteSuspension.Ray)->NativeRemoteSuspension.Contact{fatalError("Fixture must not request physics")}
    // ACTUAL_RENDER_CONTEXT
    // ACTUAL_MODEL_INSTANCES
    private var actorOverrides:[ActorPoseOverride]=[]
    private var ownVehicleWheelClocks:[Double]{groundVehicle?.wheelAnglesDouble ?? []}
    private var pendingVehicleSnapshot:Bool?
    // ACTUAL_PED_APPEND
    private func nextPedOverride(_ index:Int)->ActorPoseOverride? {
        let occurrence=modelInstances[index].8
        // ACTUAL_PED_TAKE
        return queued
    }
    private func fallbackLocomotion(_ name:String,_ position:SIMD3<Float>,queued:ActorPoseOverride?)->String? {
        // ACTUAL_FALLBACK_LOCOMOTION
        return locomotion
    }
    private func appendOwn(name:String,code:String) {
        // ACTUAL_OWN_APPEND
    }
    private func appendRemote(_ player:RemotePlayer) {
        guard Self.remoteAppearanceIsDriver(code:player.code,ridingVehicleID:player.ridingVehicleID),let name=actorName(code:player.code)else{return}
        // ACTUAL_REMOTE_APPEND
    }
    private func appendParked(_ vehicle:RemoteVehicle) {
        guard let name=actorName(code:vehicle.code)else{return}
        // ACTUAL_PARKED_APPEND
    }
    private struct Carriage {let model:String,position:SIMD3<Float>,transform:simd_float4x4}
    private func appendCarriage(_ carriage:Carriage,identity:String?,own:Bool=false,index:Int) {
        guard let name=actorName(code:carriage.model)else{return}
        // ACTUAL_CARRIAGE_APPEND
    }
    private func render(_ index:Int,rig:NativeVehicleRig)->(simd_float4x4,NativeVehicleRig.Frame) {
        let(name,position,angle,pitch,_,_,_,vehicleContext,_)=modelInstances[index]
        let originalFoot=false
        // ACTUAL_INSTANCE_TRANSFORM
        return(transform,vehicleRigFrame(position:position,modelTransform:transform,rig:rig,context:vehicleContext!))
    }
    private func resetDraws(){modelInstances=[]}
    // Historical110 negative oracle: this compact source-owned predicate is
    // intentionally wrong. No sibling checkout or owner file is required.
    private func old110Owner(_ name:String,_ position:SIMD3<Float>)->RemotePlayer? {
        remotePlayers.first{Self.remoteAppearanceIsDriver(code:$0.code,ridingVehicleID:$0.ridingVehicleID) && $0.position==position && actorName(code:$0.code)==name}
    }
    private func old110Own(_ name:String,_ position:SIMD3<Float>)->Bool {
        driving && !isPassenger && position==camera && name==vehicleModels[activeVehicleModel]
    }
    private func old110Parked(_ name:String,_ position:SIMD3<Float>)->RemoteVehicle? {
        remoteVehicles.first{actorName(code:$0.code)==name && $0.position==position}
    }
    func run()->Int {
        var checks=0
        func check(_ value:Bool,_ note:String){checks+=1;precondition(value,note)}
        func close(_ a:simd_float4x4,_ b:simd_float4x4)->Bool{(0..<4).allSatisfy{simd_length(a[$0]-b[$0])<0.00001}}
        func changed(_ a:simd_double4x4,_ b:simd_double4x4)->Bool{(0..<4).contains{simd_length(a[$0]-b[$0])>0.01}}
        let rig=authoredRig()
        let a=player("driver-a","car-a"),b=player("driver-b","car-b",code:"420.1.1",roll:-0.45,steer:-0.6,health:0,missingWheel:false,lights:false,work:2)
        remotePlayers=[a,b];appendRemote(a);appendRemote(b)
        check(old110Owner("authored-car",b.position)?.id==a.id,"Historical110 selector must still reproduce A-for-B alias")
        check(modelInstances[0].7!.player!.id==a.id && modelInstances[1].7!.player!.id==b.id,"Actual append retains both player snapshots")
        check(modelInstances[0].7!.token != modelInstances[1].7!.token,"Distinct registry state tokens")
        check(modelInstances.map{$0.7!.appearanceCode}==[a.code,b.code],"Per-occurrence appearance survives without positional queue")
        let fa=render(0,rig:rig),fb=render(1,rig:rig)
        check(!fa.1.visible[1] && fb.1.visible[1],"Missing wheel no longer leaks")
        check(fa.1.draws[0].emissive && !fb.1.draws[0].emissive,"Lights no longer leak")
        check(!fa.1.draws[0].scorched && fb.1.draws[0].scorched,"Health/wreck appearance no longer leaks")
        check(changed(fa.1.matrices[1],fb.1.matrices[1]),"Independent front steering")
        check(vehicleRigTimes.count==2 && Set(vehicleRigTimes.keys)==["remote:vehicle:5:car-a:authored-car","remote:vehicle:5:car-b:authored-car"],"Independent state/time caches")
        for(p,m)in [(a,fa.0),(b,fb.0)] {
            let expected=Self.translation(p.position)*Self.rotationZ(-p.heading)*Self.rotationX(p.pitch)*Self.rotationY(p.roll)
            check(close(m,expected),"Existing body algebra retains this occurrence's roll")
        }
        let solo=Carrier();solo.appendRemote(b);let isolated=solo.render(0,rig:rig)
        check(close(fb.0,isolated.0) && !changed(fb.1.matrices[1],isolated.1.matrices[1]),"Second matches isolated control")
        check(fb.1.visible==isolated.1.visible && fb.1.draws[0].scorched==isolated.1.draws[0].scorched,"Isolated appearance control")
        // Replace/remove/reorder the global roster after append. The immutable
        // frame occurrence must not re-search it, even when now empty.
        remotePlayers=[b,a];check(old110Owner("authored-car",a.position)?.id==b.id,"Historical ordering negative")
        remotePlayers=[];let retained=render(1,rig:rig)
        check(close(fb.0,retained.0) && retained.1.visible[1],"Removed roster cannot alter an already appended snapshot")
        let reverse=Carrier();reverse.remotePlayers=[b,a];reverse.appendRemote(b);reverse.appendRemote(a)
        check(close(reverse.render(0,rig:rig).0,fb.0) && close(reverse.render(1,rig:rig).0,fa.0),"Reversed occurrences remain independent")

        let freeA=player("free-a",nil),freeB=player("free-b",nil,code:"420.1.1",roll:-0.7,missingWheel:false)
        let free=Carrier();free.remotePlayers=[freeA,freeB];free.appendRemote(freeA);free.appendRemote(freeB)
        check(free.old110Owner("authored-car",freeB.position)?.id==freeA.id,"IDless historical alias")
        check(free.modelInstances[0].7!.token=="remote:player:6:free-a:authored-car" && free.modelInstances[1].7!.token=="remote:player:6:free-b:authored-car","Optional registry IDs keep distinct private render keys")
        check(free.modelInstances.allSatisfy{$0.7!.player!.vehicleID==nil},"No registry IDs manufactured")
        check(free.render(1,rig:rig).1.visible[1],"IDless rig state isolated")

        let xa=NSNumber(value:1480.0).floatValue,xb=NSNumber(value:1480.00001).floatValue
        check(xa==xb,"Float equality precision negative is meaningful")
        let qa=player("quant-a","qa",position:SIMD3(xa,0,0)),qb=player("quant-b","qb",position:SIMD3(xb,0,0),missingWheel:false)
        let quant=Carrier();quant.remotePlayers=[qa,qb];quant.appendRemote(qa);quant.appendRemote(qb)
        check(quant.old110Owner("authored-car",qb.position)?.id==qa.id && quant.modelInstances[1].7!.player!.id==qb.id,"Quantized coincidence cannot replace identity")
        check(quant.render(1,rig:rig).1.visible[1],"Quantized independent wheel state")
        let away=player("away","away",position:SIMD3(11,20,30),missingWheel:false)
        let apart=Carrier();apart.remotePlayers=[a,away];apart.appendRemote(a);apart.appendRemote(away)
        check(apart.old110Owner("authored-car",away.position)?.id==away.id && apart.render(1,rig:rig).1.visible[1],"Separated position negative control")
        let bike=player("bike","bike",code:"522.0.0",missingWheel:false)
        let models=Carrier();models.remotePlayers=[a,bike];models.appendRemote(a);models.appendRemote(bike)
        check(models.old110Owner("authored-bike",bike.position)?.id==bike.id && models.modelInstances[1].7!.player!.id==bike.id,"Different model negative control")
        var passenger=player("passenger",nil,code:"s7");passenger.ridingVehicleID="car-a";passenger.ridingSeat=1
        let roles=Carrier();roles.appendRemote(player("foot",nil,code:"s7"));roles.appendRemote(passenger)
        check(roles.modelInstances.isEmpty,"Foot/passenger role gates preserve vehicle rendering distinction")
        check(Self.vehicleDrawTransform(matrix_identity_float4x4,context:nil)==matrix_identity_float4x4,"Nonvehicle transform remains untouched")
        let noWheel=Self.legacyVehicleWheel(index:0,front:true,context:nil,time:10)
        check(noWheel.offset==0 && noWheel.spin==0 && noWheel.turn==0,"Nonvehicle has no own-wheel input")

        let w=Carrier(),wrig=authoredRig(model:530,working:true)
        w.appendRemote(player("work-a","wa",code:"530.0.0",missingWheel:false,work:1))
        w.appendRemote(player("work-b","wb",code:"530.1.1",missingWheel:false,work:2))
        check(abs(w.render(0,rig:wrig).1.matrices[3][3].z-1)<1e-12 && abs(w.render(1,rig:wrig).1.matrices[3][3].z-2)<1e-12,"Independent kit/working part state")
        let bikes=Carrier(),br=authoredRig(model:522,bike:true)
        let ba=player("bike-a","ba",code:"522.0.0",missingWheel:false),bb=player("bike-b","bb",code:"522.1.1",missingWheel:false)
        bikes.remoteBikeFrames=[ba.id:.init(lean:0.2,tuck:0,pedal:nil,crank:nil,hop:0),bb.id:.init(lean:-0.3,tuck:0,pedal:nil,crank:nil,hop:0)]
        bikes.remotePlayers=[ba,bb];bikes.appendRemote(ba);bikes.appendRemote(bb)
        check(changed(bikes.render(0,rig:br).1.matrices[0],bikes.render(1,rig:br).1.matrices[0]),"Per-player bike wrapper frame remains independent")
        let doors=Carrier();doors.appendRemote(a);doors.appendRemote(player("door-b","car-b",code:b.code,missingWheel:false))
        doors.riderDoorHolds=["car-a":[0:0.2],"car-b":[0:0.8]]
        check(changed(doors.render(0,rig:rig).1.matrices[4],doors.render(1,rig:rig).1.matrices[4]),"Door hold belongs to actual registry vehicle")

        // A normal own source and both remote sources share coordinates and
        // model here. Only the explicit own append may consume own state.
        let own=Carrier();own.driving=true;own.currentVehicleID="owned";own.camera=a.position;own.drivingSpeed=3
        own.nativeVehicleTransform=Self.translation(a.position)*Self.rotationY(0.9)
        own.nativeVehicleWheels=[.init(index:0,offset:0.12),.init(index:1,offset:-0.04)]
        own.nativeVehicleWheelAngles=[0.11,0.22,0.33,0.44]
        own.groundVehicle=GroundFixture(workingRenderValue:1,output:.init(steering:0.4,rearSteering:-0.2,brake:1),wheelAnglesDouble:[0.11,0.22],damageController:nil)
        own.remotePlayers=[a,b];own.appendOwn(name:"authored-car",code:"420.2.2");own.appendRemote(a);own.appendRemote(b)
        check(own.old110Own("authored-car",a.position),"Historical coincident own misclassification negative")
        check(own.modelInstances[0].7!.own != nil && own.modelInstances[1].7!.own==nil && own.modelInstances[2].7!.own==nil,"Own source explicit, never inferred from coordinates")
        let om=own.nativeVehicleTransform!,of=own.render(0,rig:rig),remoteBefore=own.render(2,rig:rig)
        check(close(of.0,om) && !close(remoteBefore.0,om),"Exact own body does not replace remote transform")
        check(own.vehicleRigTimes.count==2 && own.vehicleRigTimes.keys.contains("own:vehicle:5:owned:authored-car") && own.vehicleRigTimes.keys.contains("remote:vehicle:5:car-b:authored-car"),"Own/remote cache domains remain separate")
        let ownWheel=Self.legacyVehicleWheel(index:0,front:true,context:own.modelInstances[0].7,time:100)
        let remoteWheel=Self.legacyVehicleWheel(index:0,front:true,context:own.modelInstances[2].7,time:100)
        check(abs(ownWheel.offset-0.12)<0.00001 && ownWheel.spin==0.11 && ownWheel.turn==0.4,"Legacy own physical wheel input preserved")
        check(remoteWheel.offset==0 && remoteWheel.spin==0 && remoteWheel.turn==0,"Legacy remote coincidence cannot consume own wheel input")
        let ownRear=Self.legacyVehicleWheel(index:1,front:false,context:own.modelInstances[0].7,time:100)
        check(ownRear.spin==0.22 && ownRear.turn==(-0.2),"Legacy rear steering domain preserved")
        own.nativeVehicleTransform=nil;own.currentVehicleID="changed";own.driving=false
        own.groundVehicle?.output?.steering = -0.9;own.nativeVehicleWheelAngles=[9,9,9,9]
        let stillOwn=own.render(0,rig:rig)
        check(close(stillOwn.0,om) && !changed(stillOwn.1.matrices[1],of.1.matrices[1]),"Own frame snapshot survives mutable producer fields")
        check(Self.legacyVehicleWheel(index:0,front:true,context:own.modelInstances[0].7,time:100).spin==0.11,"Legacy snapshot does not re-read mutable own wheel array")
        let fallback=Carrier();fallback.drivingSpeed=7;fallback.steeringInput=0.5;fallback.appendOwn(name:"authored-car",code:"420")
        let fw=Self.legacyVehicleWheel(index:0,front:true,context:fallback.modelInstances[0].7,time:2)
        check(fw.spin==40 && fw.turn==0.225,"Legacy no-physical fallback timing/steering kept")

        let p1=parked("park-a",health:1000),p2=parked("park-b",health:0)
        let parkedCarrier=Carrier();parkedCarrier.groundVehicle=GroundFixture()
        parkedCarrier.remoteVehicles=[p1,p2]
        check(parkedCarrier.old110Parked("authored-car",p2.position)?.id==p1.id,"Historical parked first-owner alias negative")
        let pa=Self.translation(p1.position)*Self.rotationY(0.2),pb=Self.translation(p2.position)*Self.rotationY(-0.4)
        parkedCarrier.groundVehicle?.others=[p1.id:.init(transform:pa,work:1000),p2.id:.init(transform:pb,work:2000)]
        parkedCarrier.appendParked(p1);parkedCarrier.appendParked(p2)
        let pfa=parkedCarrier.render(0,rig:rig),pfb=parkedCarrier.render(1,rig:rig)
        check(close(pfa.0,pa) && close(pfb.0,pb),"Coincident parked physical matrices are not overwritten in a positional dictionary")
        check(!pfa.1.draws[0].scorched && pfb.1.draws[0].scorched,"Parked health state keeps actual ID")
        check(parkedCarrier.vehicleRigTimes.count==2,"Coincident parked rig states independent")
        parkedCarrier.groundVehicle?.others[p2.id]?.transform=matrix_identity_float4x4
        parkedCarrier.groundVehicle?.others[p2.id]?.work=0
        check(close(parkedCarrier.render(1,rig:rig).0,pb),"Parked physical transform snapshot retained")
        let workPark=Carrier();workPark.groundVehicle=GroundFixture()
        let wp1=parked("wp-a",code:"530",health:1000),wp2=parked("wp-b",code:"530",health:1000)
        workPark.groundVehicle?.others=[wp1.id:.init(work:1000),wp2.id:.init(work:2000)]
        workPark.appendParked(wp1);workPark.appendParked(wp2)
        workPark.groundVehicle?.others[wp2.id]?.work=0
        check(abs(workPark.render(0,rig:wrig).1.matrices[3][3].z-1)<1e-12 && abs(workPark.render(1,rig:wrig).1.matrices[3][3].z-2)<1e-12,"Parked physical working snapshots independent and retained")

        let train=Carrier();train.driving=true;train.camera=a.position;train.activeVehicleModel="590";train.drivingSpeed=4
        let ta=Self.translation(a.position)*Self.rotationZ(0.2),tb=Self.translation(a.position)*Self.rotationZ(-0.4)
        var old110Matrices=[String:simd_float4x4]()
        let old110Key="authored-carriage:\(a.position)"
        old110Matrices[old110Key]=ta;old110Matrices[old110Key]=tb
        check(close(old110Matrices[old110Key]!,tb) && !close(old110Matrices[old110Key]!,ta),"Historical carriage positional dictionary overwrites first transform")
        train.appendCarriage(.init(model:"590",position:a.position,transform:ta),identity:"train-a",index:0)
        train.appendCarriage(.init(model:"590",position:a.position,transform:tb),identity:"train-b",index:0)
        train.appendCarriage(.init(model:"590",position:a.position,transform:tb),identity:"train-a",index:1)
        let tr=authoredRig(model:590),tf1=train.render(0,rig:tr),tf2=train.render(1,rig:tr)
        _ = train.render(2,rig:tr)
        check(close(tf1.0,ta) && close(tf2.0,tb),"Coincident train carriage matrices retain layout identity")
        check(train.vehicleRigTimes.count==3,"Different train owners and carriage indices have independent rig caches")
        check(train.modelInstances[0].7!.own==nil && train.modelInstances[1].7!.own==nil,"Carriage not misclassified as own locomotive at camera coordinate")
        check(train.modelInstances[0].7!.isCarriage && train.modelInstances[0].7!.carriageSpeed==4,"Existing carriage spin timing captured, not retuned")
        check(train.modelInstances.allSatisfy{$0.7!.appearanceCode=="590"},"Carriage appearance remains explicit per occurrence")
        let tw=Self.legacyVehicleWheel(index:0,front:true,context:train.modelInstances[0].7,time:100)
        check(tw.spin==0 && tw.turn==0,"Carriage cannot consume own locomotive legacy wheels")
        train.appendCarriage(.init(model:"590",position:a.position,transform:ta),identity:"own",own:true,index:0)
        train.appendCarriage(.init(model:"590",position:a.position,transform:tb),identity:"own",index:0)
        check(train.modelInstances[3].7!.token != train.modelInstances[4].7!.token,"Explicit own carriage cannot alias a registry vehicle literally named own")
        train.appendCarriage(.init(model:"590",position:a.position,transform:ta),identity:"other-own-train",own:true,index:0)
        check(train.modelInstances[3].7!.token != train.modelInstances[5].7!.token,"Changing own train retains parent identity in carriage cache")
        check(Self.remoteDriverRenderKey(playerID:"free-a",vehicleID:nil) != Self.remoteDriverRenderKey(playerID:"anything",vehicleID:"player:free-a"),"Registry IDs cannot impersonate IDless render keys")
        let shared=Carrier();shared.appendRemote(player("one","same"));shared.appendParked(parked("same",health:1000))
        check(shared.modelInstances[0].7!.token==shared.modelInstances[1].7!.token,"Same authoritative vehicle keeps its cache when driver/parked role changes")

        // The actual per-occurrence pose array is retained. Its
        // actual append/take expressions preserve same-skin coincident riders.
        resetDraws();actorOverrides=[]
        camera = .zero;driving=false
        let at=SIMD3<Float>.zero
        appendPed("authored-ped",at,0,0,"",0,0,pose:.init(sentinel:1),transform:pa,original:true)
        appendPed("authored-ped",at,0,0,"",0,0,pose:.init(sentinel:2),transform:pb,original:true)
        let riderA=nextPedOverride(0)!,riderB=nextPedOverride(1)!
        check(riderA.pose?.sentinel==1 && riderB.pose?.sentinel==2,"Same-skin coincident rider poses retain ordinal identity")
        check(riderA.transform==pa && riderB.transform==pb,"Same-skin coincident rider car transforms stay independent")
        check(riderA.original && riderB.original,"Original-pose sampling flags unchanged")
        check(modelInstances.allSatisfy{$0.7==nil},"Pedestrian occurrences never acquire vehicle context")
        _ = nextPedOverride(0)
        check(nextPedOverride(1)!.pose?.sentinel==2,"Consume-before-unavailable-mesh does not shift following override")
        resetDraws();actorOverrides=[]
        appendPed("authored-ped",at,0,0,"",0,0,identity:"local-marker",ownFoot:true)
        appendPed("authored-ped",at,0,0,"",0,0,identity:"own")
        let ownFoot=nextPedOverride(0)!,remoteFoot=nextPedOverride(1)!
        check(ownFoot.pose==nil && remoteFoot.pose==nil,"Nil-pose fallback controls are exercised")
        check(fallbackLocomotion("authored-ped",at,queued:ownFoot)==locomotionClip,"Own-foot fallback retains original action locomotion")
        check(fallbackLocomotion("authored-ped",at,queued:remoteFoot)==nil,"Coincident remote fallback cannot inherit own locomotion even with identity text own")
        check(fallbackLocomotion("authored-ped",at+SIMD3(1,0,0),queued:ownFoot)==nil,"Existing position eligibility still applies to own fallback")
        check(!remoteFoot.ownFoot && ownFoot.ownFoot,"Own role explicit per occurrence rather than identity spelling")
        let sampled=NativeSkeletalActor.Pose(sentinel:99)
        check((riderA.pose ?? sampled).sentinel==1 && (riderB.pose ?? sampled).sentinel==2,"Nonnil queued poses retain precedence over fallback sample")
        return checks
    }
}

private let identity:[Double]=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
private func authoredRig(model:Int=420,working:Bool=false,bike:Bool=false)->NativeVehicleRig {
    func node(_ name:String,_ parent:Int)->[String:Any] {
        ["name":name,"parent":parent,"position":[0.0,0,0],"rotation":[0.0,0,0,1],"scale":[1.0,1,1],"matrix":identity,
         "matrixAutoUpdate":true,"visible":true,"wheel":false,"damaged":false,"lowDetail":false]
    }
    let nodes=[node("AUTHORED_ROOT",-1),node("AUTHORED_FRONT_WHEEL",0),node("AUTHORED_LAMP",0),node("AUTHORED_WORK",0),node("AUTHORED_DOOR",0)]
    let wheel:[String:Any]=["node":1,"home":[0.0,0,0],"rest":[0.0,0,0,1],"lean":[0.0,0,0,1],"front":true,"left":true,"bogie":false]
    let draw:[String:Any]=["node":2,"start":0,"count":3,"materialVisible":true,"lens":0,"texture":1,"litTexture":2,"alphaTest":0.0]
    var joints:[String:Any]=["damage":[["part":0,"node":4,"rest":[0.0,0,0,1],"hinge":[0.0,0,0]]],"wheels":[wheel],"rotors":[],"gear":[],"nozzles":[],"rearSteerOnly":false]
    if working {joints["working"]=["tow":false,"turn":0.0,"lift":0.001,"parts":[["node":3,"role":"AUTHORED_LIFT","rest":[0.0,0,0,1],"home":[0.0,0,0]]]]}
    if bike {joints["bike"]=["model":0,"front":1,"rear":3,"parameters":[:],"hubs":[:],"restDrop":0.0,"frontWheels":[],"frontMudguards":[],"rearWheels":[],"pedals":[],"pedalled":false,"rearForkLength":1.0,"minimumZ":0.0]}
    let value:[String:Any]=["version":1,"id":model,"kind":"car","nodes":nodes,"draws":[draw],"joints":joints]
    return NativeVehicleRig(data:try! JSONSerialization.data(withJSONObject:value))!
}
private func player(_ id:String,_ vehicle:String?,position:SIMD3<Float>=SIMD3(10,20,30),code:String="420.0.0",roll:Float=0.2,steer:Float=0.25,health:Int=1000,missingWheel:Bool=true,lights:Bool=true,work:Float=1)->RemotePlayer {
    var p=RemotePlayer(id:id,name:"Authored",position:position,code:code,heading:0.3,pitch:0.1,roll:roll,speed:0,steer:steer,skin:7,animation:"",animationStarted:0,weapon:0,vehicleID:vehicle)
    p.vehicleHealth=health;p.vehicleDamage=String(repeating:"0",count:15)+(missingWheel ? "2000":"0000");p.lights=lights;p.kit=[0,0,0,0,0,work];return p
}
private func parked(_ id:String,code:String="420",health:Int)->RemoteVehicle {
    RemoteVehicle(row:[id,"Authored",code,10,20,30,0,0,0,health,String(repeating:"0",count:19)])!
}

let checks=Carrier().run()
let result:[String:Any]=["status":"PASS","checks":checks,"historical110AliasNegative":true,
    "actualAppendContextTransformRigExecuted":true,"authoredGeometryOnly":true,
    "coverage":["coincident/reversed/removed snapshots","IDless and float-precision coincidence","position/model/role negative controls",
                "roll/steering/tyres/lights/wreck/working/bike/door state","own physical and legacy wheel domains","parked physical snapshots","independent train layout/index/transform",
                "key namespaces and real own carriage identity","same-skin pose queue and explicit own-foot nil-pose fallback"]]
let bytes=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]);print(String(data:bytes,encoding:.utf8)!)
