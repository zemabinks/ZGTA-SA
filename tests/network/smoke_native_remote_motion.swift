// SPDX-License-Identifier: AGPL-3.0-only
// COMMON

private struct Failure: Error,CustomStringConvertible {let description:String;init(_ text:String){description=text}}
private var checks=0
private func check(_ value:Bool,_ text:String)throws{guard value else{throw Failure(text)};checks+=1}
private func close(_ a:SIMD3<Float>,_ b:SIMD3<Float>,_ epsilon:Float=0.0002)->Bool{simd_distance(a,b)<epsilon}
private final class PacketOwner {
    var players:[String:RemotePlayer]=[:],vehicles:[String:RemoteVehicle]=[:]
    var playerOrder:[String]=[]
    var remoteAnimationTimes:[String:(String,Double)]=[:]
    var receiptTime:Double=0
    var serverTimeOffsetMilliseconds:Double?=nil
    var orderedPlayers:[RemotePlayer]{playerOrder.compactMap{players[$0]}}
    var orderedVehicles:[RemoteVehicle]{Array(vehicles.values)}
    var onPlayers:(([RemotePlayer])->Void)?
    var onVehicles:(([RemoteVehicle])->Void)?
    func receive(_ rows:[[Any]],at time:Double){receiptTime=time;updateRows(rows)}
    // ACTUAL_PACKET
}
private final class SceneOwner {
    let weaponFlashes=NativeWeaponFlash(),humanShots=NativeHumanShots()
    var presentedAmbientPedestrians:[NativeAmbientPedestrians.Frame]=[]
    var remoteServerTimeOffsetMilliseconds:Double?
    var support:[String:SIMD3<Float>]=[:]
    func remoteSupportPosition(_ player:RemotePlayer)->SIMD3<Float>?{support[player.id]}
    func recordRemoteAnimationPackets(){}
    func ensureFixedCJ(){}
    // ACTUAL_SCENE
    func drawnFeet(_ id:String)->SIMD3<Float>?{
        guard let player=presentedRemotePlayers.first(where:{$0.id==id})else{return nil}
        // ACTUAL_DRAW
        return footPosition
    }
    var retainedOwners:Int{remoteFootMotions.count}
    var retainedSamples:Int{remoteFootMotions.values.map{$0.motion.snapshots.count}.max() ?? 0}
}
private final class ControllerOwner {
    let network=PacketOwner()
    var renderer:SceneOwner?=SceneOwner()
    init(){
        // ACTUAL_HOOKUP
    }
    // ACTUAL_MELEE
    func instant()->[NativeShotTargeting.Candidate]{
        let renderer=self.renderer!
        // ACTUAL_INSTANT
        return candidates
    }
    func stream()->[NativeShotTargeting.Candidate]{
        let renderer=self.renderer!
        // ACTUAL_STREAM
        return candidates
    }
    func melee()->[NativeMeleeTargeting.Candidate]{meleeCandidates}
}
private func row(_ x:Float,_ time:Double,id:String="walk",code:String="s7",velocity:Float=1.6,heading:Float=0,skin:Int=7,clock:Double?=nil)->[Any]{
    var result=[Any](repeating:NSNull(),count:44)
    result[0]=id;result[1]="Authored Walker";result[2]=code
    result[3]=x;result[4] = -1738;result[5]=13
    result[6] = -heading;result[7]=0;result[8]=0;result[9]=0;result[10]=0
    result[13]=velocity;result[14]=0;result[15]=0;result[16]=clock ?? (50000+time*1000)
    result[18]=100;result[24]=velocity==0 ? 0:1;result[27]=22;result[29]=0
    result[30]=0;result[31]=skin;result[32]=0;result[38]=0;result[41]="ped/walk_player/l/1"
    return result
}
private struct KernelReference:Decodable {
    struct Point:Decodable {let at:Double,delay:Double,heading:Double;let position:[Double],velocity:[Double];let index:Int}
    struct Input:Decodable {let at:Double,heading:Double,ordinary:Bool;let position:[Double],velocity:[Double],acceleration:[Double]}
    struct Case:Decodable {let name:String;let snapshots:[Input];let points:[Point]}
    let cases:[Case]
}
@main private enum Main {
    static func main(){do{try run()}catch{fputs("FAIL \(error)\n",stderr);exit(1)}}
    static func run()throws {
        let retired=SceneOwner()
        let packet=NativeHumanShots.Packet(["from":"gone","w":31,"o":[0,0,1.3],"h":[0,4,1.3],"ht":0])!
        _=retired.humanShots.receive(packet,footAppearance:true,at:1)
        retired.weaponFlashes.fire(identity:"gone",weapon:31,left:false,twin:false,at:1)
        retired.weaponFlashes.fire(identity:"own",weapon:31,left:false,twin:false,at:1)
        retired.remotePlayers=[]
        try check(retired.humanShots.queued("gone")==0,"roster removal retains queued shot from retired actor")
        try check(!retired.weaponFlashes.visible(identity:"gone",weapon:31,left:false,at:1.01),"roster removal retains retired actor flash")
        try check(retired.weaponFlashes.visible(identity:"own",weapon:31,left:false,at:1.01),"remote roster removal retires local holder")
        var schedules:[String:[SIMD3<Float>]]=[:]
        for hz in [20,30,60,120] {
            let owner=ControllerOwner(),renderer=owner.renderer!
            var previous:SIMD3<Float>?,held=0,movingSteps=0,largest:Float=0
            var atSeconds:[SIMD3<Float>]=[]
            for frame in 0...hz*6 {
                let time=1000+Double(frame)/Double(hz)
                if frame%(hz/5)==0 {owner.network.receive([row(1480+Float(time-1000)*1.6,time)],at:time)}
                renderer.advanceRemoteFootPresentation(at:time,active:true)
                let point=renderer.drawnFeet("walk")!
                if frame>hz*2,let previous {let distance=simd_distance(previous,point);movingSteps+=1;if distance<0.000001{held+=1};largest=max(largest,distance)}
                if frame%hz==0 {atSeconds.append(point)}
                try check(point.z==13,"Own/browser-world feet gained a legacy/skeleton metre")
                previous=point
            }
            try check(held<=1,"remote foot draw freezes between200ms packets instead of advancing at display cadence")
            try check(largest<1.6/Float(hz)*1.35,"Warm root has a packet-sized step")
            try check(renderer.retainedSamples<=40,"Per-actor history exceeds40")
            schedules[String(hz)]=atSeconds
            print("motion Hz=\(hz) movingSteps=\(movingSteps) held=\(held) largest=\(largest)")
        }
        let reference=schedules["60"]!
        for values in schedules.values {for index in 0..<reference.count {try check(close(values[index],reference[index]),"Playback depends on display frequency")}}
        let owner=ControllerOwner(),renderer=owner.renderer!
        owner.network.receive([row(10,1000)],at:1000)
        owner.network.receive([row(10.32,1000.2)],at:1000.2)
        renderer.advanceRemoteFootPresentation(at:1000.25,active:true)
        let feet=renderer.drawnFeet("walk")!
        try check(feet.x<10.32 && feet.x>10,"Two snapshots are not sampled between their feet")
        try check(close(owner.instant()[0].point,NativeShotTargeting.torso(feet:feet)),"Instant aiming disagrees with drawn feet")
        try check(close(owner.stream()[0].point,feet+SIMD3(0,0,0.9)),"Stream aiming disagrees with drawn feet")
        try check(close(owner.melee()[0].feet,feet),"Melee disagrees with drawn feet")
        try check(owner.network.players["walk"]!.position.x==10.32,"Presentation rewrote authoritative packet position")
        let rawBefore=owner.network.players["walk"]!
        owner.network.receive([row(99,1000.4,clock:1050200)],at:1000.4)
        renderer.advanceRemoteFootPresentation(at:1000.4,active:true)
        try check(renderer.drawnFeet("walk")!.x<11,"Duplicate sender clock created a warp")
        // Sender wall clocks may jump backwards. The receipt clock still owns
        // ordering; a decreasing wall value must not strand this peer forever.
        owner.network.receive([row(10.64,1000.6,clock:2)],at:1000.6)
        renderer.advanceRemoteFootPresentation(at:1000.7,active:true)
        try check(renderer.drawnFeet("walk")!.x<11,"Sender clock selected a local epoch")
        var old=rawBefore;old.packetReceivedAt=999;old.packetClockMilliseconds=3
        renderer.remotePlayers=[old];renderer.advanceRemoteFootPresentation(at:1000.7,active:true)
        try check(renderer.drawnFeet("walk")!.x>=10,"Old receipt changed actor identity")
        owner.network.receive([row(10.8,1000.8,velocity:0)],at:1000.8)
        renderer.advanceRemoteFootPresentation(at:1001.2,active:true)
        try check(abs(renderer.drawnFeet("walk")!.x-10.8)<0.08,"Stop packet overshoots or fails to settle")
        renderer.advanceRemoteFootPresentation(at:1001.3,active:true)
        let bounded=renderer.drawnFeet("walk")!
        renderer.advanceRemoteFootPresentation(at:1001.31,active:true)
        try check(simd_distance(renderer.drawnFeet("walk")!,bounded)<0.02,"Stale prediction rolled back to raw feet")
        owner.network.receive([row(500,1001.4)],at:1001.4)
        renderer.advanceRemoteFootPresentation(at:1001.4,active:true)
        try check(renderer.drawnFeet("walk")!.x==500,"Teleport swept through old history")
        owner.network.receive([row(500.2,1001.6,code:"s2")],at:1001.6)
        renderer.advanceRemoteFootPresentation(at:1001.6,active:true)
        try check(renderer.presentedRemotePlayers[0].code=="s2" && renderer.drawnFeet("walk")!.x==500.2,"Appearance inherited another root timeline")
        renderer.advanceRemoteFootPresentation(at:1001.6,active:false)
        try check(renderer.retainedOwners==0,"Background kept prediction owners")
        renderer.advanceRemoteFootPresentation(at:1010,active:true)
        try check(renderer.drawnFeet("walk")!.x<501,"Resume extrapolated background time")
        owner.network.receive([],at:1010.1)
        try check(renderer.presentedRemotePlayers.isEmpty && renderer.retainedOwners==0,"Streamout kept ghost root")
        owner.network.receive([row(-10,1010.2)],at:1010.2)
        renderer.advanceRemoteFootPresentation(at:1010.2,active:true)
        try check(renderer.drawnFeet("walk")!.x == -10,"Reconnected ID inherited history")
        var attached=owner.network.players["walk"]!;attached.supportVehicleID="truck";attached.supportOffset=SIMD3(0,0,1)
        renderer.support["walk"]=SIMD3(20,30,40);renderer.remotePlayers=[attached]
        renderer.advanceRemoteFootPresentation(at:1010.3,active:true)
        try check(renderer.retainedOwners==0 && renderer.drawnFeet("walk")==SIMD3(20,30,40),"Moving support was independently smoothed")
        var passenger=attached;passenger.supportVehicleID=nil;passenger.ridingVehicleID="car";passenger.ridingSeat=1
        renderer.remotePlayers=[passenger];renderer.advanceRemoteFootPresentation(at:1010.4,active:true)
        try check(renderer.retainedOwners==0 && renderer.presentedRemotePlayers[0].position==passenger.position,"Passenger root lost seat ownership")
        let motion=NativeRemoteFootMotion<Int>()
        try check(!motion.record(.init(at:.nan,position:.zero,heading:0,velocity:.zero,ordinary:true,state:0)),"NaN receipt accepted")
        try check(motion.record(.init(at:1,position:.zero,heading:Double.pi-0.1,velocity:.zero,ordinary:true,state:1)),"Initial snapshot rejected")
        try check(!motion.record(.init(at:1,position:.zero,heading:0,velocity:.zero,ordinary:true,state:2)),"Equal receipt accepted")
        try check(motion.record(.init(at:1.2,position:SIMD3(0.2,0,0),heading:-Double.pi+0.1,velocity:SIMD3(1,0,0),ordinary:true,state:3)),"Second snapshot rejected")
        let yaw=motion.sample(at:1.25)!.heading
        try check(abs(yaw)>3,"Yaw took the long way through zero")
        try check(motion.sample(at:.infinity)==nil,"Infinite display clock accepted")
        let end=motion.sample(at:3)!.position
        try check(simd_distance(end,motion.sample(at:100)!.position)<0.00001,"Prediction exceeds its bounded horizon")
        let jitter=ControllerOwner(),jitterScene=jitter.renderer!
        let arrivals:[Double]=[0,0.17,0.39,0.60,0.79,1.02,1.20,1.42,1.59,1.80,2.01,2.21,2.4]
        var arrival=0,lastFeet:SIMD3<Float>?,maximum:Float=0
        for frame in 0...156 {
            let now=2000+Double(frame)/60
            while arrival<arrivals.count && 2000+arrivals[arrival]<=now+1e-9 {
                let at=2000+arrivals[arrival]
                jitter.network.receive([row(Float(arrivals[arrival])*1.6,at)],at:at);arrival+=1
            }
            jitterScene.advanceRemoteFootPresentation(at:now,active:true)
            let point=jitterScene.drawnFeet("walk")!
            if frame>60,let lastFeet {maximum=max(maximum,simd_distance(lastFeet,point))}
            lastFeet=point
        }
        try check(maximum<0.075,"Jitter creates a packet-sized root correction")
        var paused=jitter.network.players["walk"]!;paused.paused=true;paused.packetReceivedAt=2002.7
        jitterScene.remotePlayers=[paused];jitterScene.advanceRemoteFootPresentation(at:2002.7,active:true)
        let pausedAt=jitterScene.drawnFeet("walk")!
        jitterScene.advanceRemoteFootPresentation(at:2003,active:true)
        try check(close(pausedAt,jitterScene.drawnFeet("walk")!),"Paused actor kept stale velocity")
        var dead=paused;dead.paused=false;dead.life=0;dead.packetReceivedAt=2003.1
        jitterScene.remotePlayers=[dead];jitterScene.advanceRemoteFootPresentation(at:2003.1,active:true)
        try check(jitterScene.presentedRemotePlayers[0].life==0,"Death waited for an old presentation state")
        let fastFlight=NativeRemoteFootMotion<Int>()
        for i in 0...10 {
            let at=3000+Double(i)*0.2
            fastFlight.record(.init(at:at,position:SIMD3(Double(i)*4,0,20),heading:0,velocity:SIMD3(20,0,0),ordinary:false,state:i))
        }
        try check(fastFlight.snapshots.count==11,"Legitimate fast flight was mistaken for a walking warp")
        try check(abs(fastFlight.sample(at:3002.1)!.position.x-42)<0.001,"Special-mode velocity predictor lost continuous motion")
        if CommandLine.arguments.count>1 {
            let reference=try JSONDecoder().decode(KernelReference.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
            var points=0
            for item in reference.cases {
                let snapshots=item.snapshots.enumerated().map { index,value in
                    NativeRemoteFootMotion<Int>.Snapshot(at:value.at,position:SIMD3(value.position),heading:value.heading,
                        velocity:SIMD3(value.velocity),ordinary:value.ordinary,state:index,acceleration:SIMD3(value.acceleration))
                }
                for point in item.points {
                    let sample=NativeRemoteFootMotion<Int>.sample(snapshots,at:point.at,delay:point.delay)!
                    try check(simd_distance(sample.position,SIMD3(point.position))<1e-8,"Archived interpolation position differs: "+item.name)
                    try check(simd_distance(sample.velocity,SIMD3(point.velocity))<1e-8,"Archived interpolation velocity differs: "+item.name)
                    try check(abs(atan2(sin(sample.heading-point.heading),cos(sample.heading-point.heading)))<1e-8,"Archived interpolation yaw differs: "+item.name)
                    try check(sample.state==point.index,"Archived interpolation discrete-state endpoint differs: "+item.name)
                    points+=1
                }
            }
            print("PASS private archived interpolation kernel: \(reference.cases.count) authored cases; \(points) actual-helper samples")
        }
        print("PASS actual remote motion packet/scene/targeting: \(checks) checks; authored clocks only")
    }
}
