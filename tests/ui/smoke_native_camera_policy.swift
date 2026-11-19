// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

private enum Failure:Error {case check(String)}
private var checks=0
private func require(_ value:@autoclosure()->Bool,_ message:String)throws {
    checks += 1
    if !value(){throw Failure.check(message)}
}
private final class QueryCarrier {
    struct Queries {let walker,probe:UInt64}
    struct Character {let queries:Queries?}
    var groundVehicle:NativeGroundVehicle?
    var driving=true,isPassenger=false,isInterior=false
    var currentVehicleID:String?
    var character:Character?
    var legacyCollisionWorld:NativeRenderWareCollisionWorld?
    var collisionRequests=NativeCollisionRequests()
    var activeDetails=Set<String>(),desiredPhysicsCells=Set<String>(),requestedCells=Set<String>()
    var passiveCameraTrace:NativePassiveCameraTrace?
    var passiveCameraRay:NativePassiveCameraTrace.Ray?
    init(_ manager:NativeGroundVehicle){groundVehicle=manager}
    func loadCollision(name:String){requestedCells.insert(name)}
    func query(_ origin:SIMD3<Float>,_ direction:SIMD3<Float>,_ distance:Float,vehiclePolicy:Bool=true)->Float? {
        cameraRay(from:origin,direction:direction,distance:distance,originalVehiclePolicy:vehiclePolicy)
    }
    // ACTUAL_RENDERER_QUERY_METHODS
}

/// All numbers below describe independently authored test shapes, not a GTA
/// handling row, model, collision resource or inferred retail specification.
private func definition(_ id:Int,radius:Double=0.5)->[String:Any] {
    var row:[String:Any]=["id":id,"kind":"car","solverSupported":true,"origin":1.0,"width":2.0,"height":2.0,"length":4.0]
    row["table"]=["mass":1000.0,"turnMass":2000.0,"collisionDamage":0.0]
    row["wheels"]=[[String:Any]]()
    row["chassis"]=[["kind":"sphere","centre":[0.0,1.0,0.0],"radius":radius,"collisionGroups":8454127]] as [[String:Any]]
    row["bounds"]=["box":["min":[-1.0,-2.0,0.0],"max":[1.0,2.0,2.0]]]
    return row
}
private func emptyCell()->Data {
    var data=Data()
    for word:UInt32 in [0x324c4353,0,0,0]{var value=word.littleEndian;withUnsafeBytes(of:&value){data.append(contentsOf:$0)}}
    return data
}
private func cameraData()throws->Data {
    let profile:[Double]=[1,1,0.2,3,12,0.4,1,1,0.9,0.2,0.1,0.05,1,0.7,1.4]
    let kinds=["car","bike","heli","plane"]
    var document:[String:Any]=[:]
    document["vehicleProfiles"]=Dictionary(uniqueKeysWithValues:kinds.map{($0,profile)})
    document["vehicleDistances"]=Dictionary(uniqueKeysWithValues:kinds.map{($0,[-0.5,1.0,4.0])})
    document["vehicleAngles"]=Dictionary(uniqueKeysWithValues:kinds.map{($0,[0.05,0.1,0.2])})
    document["cinematic"]=["ground":[20.0,5.0,2.0,30.0],"air":[60.0,20.0,8.0,100.0]]
    document["footDistances"]=[1.0,2.0,4.0]
    document["footSights"]=Dictionary(uniqueKeysWithValues:["scope","camera","rocket"].map{($0,["first":70.0,"least":10.0,"most":100.0])})
    document["footWeaponFov"]=[[Double]]();document["weaponSights"]=[String:String]()
    return try JSONSerialization.data(withJSONObject:document)
}
private func readyManager()throws->NativeGroundVehicle {
    let manager=NativeGroundVehicle()!
    let data=try JSONSerialization.data(withJSONObject:["models":["9001":definition(9001),"9002":definition(9002,radius:0.3)],"materialClasses":[Int](repeating:0,count:256)])
    try require(manager.loadDefinitions(data)==2,"authored definitions load")
    let floor=manager.world.addBox(halfExtents:SIMD3(200,0.1,200),position:SIMD3(0,-0.1,0))!
    manager.world.setColliderGroups(floor,collision:131071,solver:0xffffffff)
    manager.installCell("c136",data:emptyCell())
    try require(manager.isCellLoaded("c136"),"authored empty collision cell accepted")
    return manager
}
private func lifecycle(_ output:URL)throws {
    let manager=try readyManager(),world=manager.world,carrier=QueryCarrier(manager)
    var pose=NativeOtherVehicles.Pose(id:"authored-car",code:"9001",position:SIMD3(20,20,3),heading:0,pitch:0,roll:0,occupied:true)
    func sync(_ near:SIMD3<Float>?=nil){manager.synchronizeOtherVehicles([pose],excluding:nil,near:pose.position,promoteNear:near,delta:0)}
    func rayOrigin()->SIMD3<Float>{manager.otherVehicle(pose.id)!.position+SIMD3(0,-3,1)}
    sync()
    let initial=manager.otherColliders
    try require(initial.count==1 && manager.cameraExcludedOtherColliders.isEmpty,"remote kinematic remains camera-solid")
    try require(initial.allSatisfy{world.colliderInfo($0)?.material==63},"native damage material63 is present")
    try require(carrier.query(rayOrigin(),SIMD3(0,1,0),6) != nil,"material63 must not become original registry membership")
    pose.occupied=false;sync(pose.position)
    let promoted=manager.otherColliders
    try require(promoted.count==1 && promoted.isDisjoint(with:initial),"promotion replaces collider handles")
    try require(initial.allSatisfy{world.colliderInfo($0)==nil},"replaced kinematic handles removed")
    try require(manager.otherVehicle(pose.id)?.dynamic==true,"real unattended solver promoted")
    try require(manager.cameraExcludedOtherColliders==promoted,"only promoted other is excluded")
    try require(carrier.query(rayOrigin(),SIMD3(0,1,0),6)==nil,"promoted other must not obstruct the driven camera")
    try require(carrier.query(rayOrigin(),SIMD3(0,1,0),6,vehiclePolicy:false) != nil,"legacy adapter retains previous solid-body policy")
    carrier.driving=false
    try require(carrier.query(rayOrigin(),SIMD3(0,1,0),6,vehiclePolicy:false)==nil,"on-foot retains its world-only collision mask")
    carrier.driving=true
    pose.occupied=true;sync()
    let demoted=manager.otherColliders
    try require(manager.cameraExcludedOtherColliders.isEmpty,"occupied demotion clears exclusion")
    try require(promoted.allSatisfy{world.colliderInfo($0)==nil},"demotion removes promoted handles")
    try require(carrier.query(rayOrigin(),SIMD3(0,1,0),6) != nil,"demoted remote body obstructs again")
    pose.occupied=false;sync(pose.position)
    let prior=manager.otherColliders
    pose = .init(id:pose.id,code:"9002",position:pose.position,heading:0,pitch:0,roll:0,occupied:true);sync()
    try require(prior.allSatisfy{world.colliderInfo($0)==nil} && manager.cameraExcludedOtherColliders.isEmpty,"model replacement does not retain old exclusion")
    try require(carrier.query(rayOrigin(),SIMD3(0,1,0),6) != nil,"replacement kinematic shape stays solid")
    pose.occupied=false;sync(pose.position)
    let removed=manager.otherColliders
    try require(manager.removeOtherVehicle(id:pose.id),"explicit removal")
    try require(manager.otherColliders.isEmpty && manager.cameraExcludedOtherColliders.isEmpty,"removal drops membership and exclusions")
    try require(removed.allSatisfy{world.colliderInfo($0)==nil},"removed handles are dead")
    sync(pose.position)
    let stale=manager.otherColliders.first!
    _ = world.removeCollider(stale)
    try require(manager.cameraExcludedOtherColliders.isEmpty,"out-of-owner collider removal cannot retain an exclusion")
    manager.clearOtherVehicles();sync(pose.position)
    let external=manager.otherColliders.first!,body=world.colliderInfo(external)!.body!
    _ = world.removeBody(body)
    try require(manager.cameraExcludedOtherColliders.isEmpty,"out-of-owner body removal cannot preserve stale exclusion")
    manager.clearOtherVehicles();sync(pose.position);manager.clearOtherVehicles()
    try require(manager.cameraExcludedOtherColliders.isEmpty && manager.otherColliders.isEmpty,"reset clears all memberships")
    try require(demoted.isDisjoint(with:manager.cameraExcludedOtherColliders),"old handles never regain exclusion")
    sync(pose.position)
    let handedOff=manager.otherColliders
    try require(manager.takeOtherVehicle(pose.id) != nil,"dynamic owner handoff")
    try require(manager.cameraExcludedOtherColliders.isEmpty && handedOff.allSatisfy{world.colliderInfo($0)==nil},"taking ownership clears the old camera namespace")

    // Actual native bodies outside the proven others owner must stay solid.
    for kind:SwiftRapierWorld.BodyKind in [.fixed,.kinematicPosition,.dynamic] {
        let at=SIMD3<Float>(50,1,-50)
        let body=world.addBody(kind:kind,position:at)!,collider=world.addSphere(radius:0.5,body:body)!
        world.setColliderGroups(collider,collision:8454127,solver:0xffffffff)
        world.setColliderSurface(collider,surface:2,material:63)
        try require(carrier.query(SwiftRapierWorld.rapierToGTA(at+SIMD3(0,0,3)),SIMD3(0,1,0),6) != nil,"unregistered body/material must stay camera-solid")
        _ = world.removeBody(body)
    }
    try require(manager.enter(model:"9001",modelPosition:SIMD3(80,80,2),heading:0),"own authored body enter")
    let own=manager.chassisColliders
    let ownOrigin=manager.bodyPosition+SIMD3(0,-3,1)
    try require(carrier.query(ownOrigin,SIMD3(0,1,0),6)==nil,"own body explicit exclusion preserved")
    try require(!own.isEmpty && manager.cameraExcludedOtherColliders.isEmpty,"own body is not original-other membership")
    manager.exit()

    // SA-MP authored custom objects keep their explicit camera flag, without
    // altering physical shape membership or treating raw COL material as S.
    let objects=try NativeRenderWareCollisionWorld(world:world);carrier.legacyCollisionWorld=objects
    let surface=NativeRenderWareCollision.Surface(material:77,flags:nil,brightness:nil,lighting:0)
    let model=NativeRenderWareCollision.Model(version:.col3,name:"authored_camera",modelID:0,
        bounds:.init(minimum:SIMD3(repeating:-1),maximum:SIMD3(repeating:1),center:.zero,radius:2),flags:2,
        spheres:[.init(center:.zero,radius:0.5,surface:surface)],boxes:[],mesh:.init(vertices:[],faces:[]),faceGroups:[],shadowMesh:nil)
    let handle=try objects.insert(.init(id:123,model:model,transform:.init(position:SIMD3(100,100,1))))
    let ids=objects.colliderIDs(for:handle)!
    for policy in [true,false] {
        try require(carrier.query(SIMD3(100,97,1),SIMD3(0,1,0),6,vehiclePolicy:policy) != nil,"camera-enabled legacy object stays solid")
        try objects.setCameraCollision(handle,enabled:false)
        try require(carrier.query(SIMD3(100,97,1),SIMD3(0,1,0),6,vehiclePolicy:policy)==nil,"explicit legacy camera exclusion preserved")
        try require(world.raycast(origin:SIMD3(100,1,-97),direction:SIMD3(0,0,-1),distance:6) != nil,"camera flag leaves actual collision intact")
        try objects.setCameraCollision(handle,enabled:true)
    }
    try require(objects.remove(handle),"legacy removal accepted")
    try require(ids.allSatisfy{world.colliderInfo($0)==nil},"legacy removal is complete")
    let boundary=carrier.query(SIMD3(374,10,1),SIMD3(1,0,0),3)
    try require(boundary != nil && abs(boundary!-1)<0.0001,"missing cell boundary remains authoritative")
    try require(carrier.requestedCells.contains("c137"),"actual Renderer still requests missing collision cells")

    // Explicit material-map membership is a tested policy seam only. Native
    // remote-ped ownership is absent, and the production vehicle owner does
    // not claim that these authored tags are original registry membership.
    let expectedMembership=[false,false,false,false,false,true,true,true]
    var membershipIndex=0
    for other in [false,true] {for tagged in [false,true] {for dynamic in [false,true] {
        let excluded=NativeCameraCollisionPolicy.excludes(otherMember:other,originalMaterialMember:tagged,dynamicBody:dynamic)
        try require(excluded == expectedMembership[membershipIndex],"explicit membership truth table")
        membershipIndex += 1
    }}}
    let actorAt=SIMD3<Float>(150,1,-150),actorBody=world.addBody(kind:.kinematicPosition,position:actorAt)!
    let actorShape=world.addSphere(radius:0.4,body:actorBody)!
    world.setColliderGroups(actorShape,collision:8454127,solver:0xffffffff)
    world.setColliderSurface(actorShape,surface:2,material:77)
    try require(carrier.query(SIMD3(150,147,1),SIMD3(0,1,0),6) != nil,"an unregistered actor's numeric material does not establish original membership")
    let actorExcluded: Set<UInt64>=NativeCameraCollisionPolicy.excludes(otherMember:true,originalMaterialMember:true,dynamicBody:false) ? [actorShape]:[]
    try require(world.raycast(origin:actorAt+SIMD3(0,0,3),direction:SIMD3(0,0,-1),distance:6,excludingColliders:actorExcluded)==nil,"explicit authored tagged-other contract filters actual native geometry")
    _ = world.removeBody(actorBody)
    let recording=NativePassiveCameraTrace(directory:output.appendingPathComponent("ray-metadata"))
    carrier.passiveCameraTrace=recording
    pose.occupied=true;sync()
    _ = carrier.query(rayOrigin(),SIMD3(0,1,0),6)
    try require(carrier.passiveCameraRay?.originalOtherMember==true && carrier.passiveCameraRay?.originalMaterialMember==false,"passive query reports independent memberships")
    try require(carrier.passiveCameraRay?.bodyKind=="kinematic-position","passive query records actual body kind")
    _ = carrier.query(SIMD3(374,10,1),SIMD3(1,0,0),3)
    try require(carrier.passiveCameraRay?.result=="unavailable","passive query distinguishes missing coverage from a solid hit")
    carrier.passiveCameraTrace=nil
    _ = try finish(recording)
}

private func finish(_ recorder:NativePassiveCameraTrace)throws->NativePassiveCameraTrace.Summary {
    var summary:NativePassiveCameraTrace.Summary?
    recorder.stop{summary=$0}
    // A real timer makes the CLI runloop wait rather than spin when no main
    // callback is queued yet; background utility I/O must get scheduling time.
    let timer=Timer(timeInterval:0.01,repeats:true){_ in}
    RunLoop.current.add(timer,forMode:.default)
    defer{timer.invalidate()}
    let deadline=Date().addingTimeInterval(15)
    while summary==nil && Date()<deadline{_ = RunLoop.current.run(mode:.default,before:Date().addingTimeInterval(0.005))}
    try require(summary != nil,"writer completion arrives without blocking the main queue")
    return summary!
}

private func cameraObservations()throws {
    let data=try cameraData()
    for hz in [15,30,60,120] {for view in 1...6 {
        let reference=try NativeGameCamera(data:data),observed=try NativeGameCamera(data:data)
        try require(reference.onVehicleObservation==nil,"passive observations default off")
        reference.setVehicleView(view);observed.setVehicleView(view)
        var latest:NativeGameCamera.VehicleObservation?,count=0,randomA:UInt32=1,randomB:UInt32=1
        observed.onVehicleObservation={latest=$0;count += 1}
        func random(_ seed:inout UInt32)->Double{seed=seed&*1664525&+1013904223;return Double(seed)/Double(UInt32.max)}
        for step in 0..<120 {
            let x=Float(sin(Double(step)*0.1)),y=Float(cos(Double(step)*0.07))
            reference.lookPixels(x:x,y:y,driving:true);observed.lookPixels(x:x,y:y,driving:true)
            let input=NativeGameCamera.Vehicle(position:SIMD3(20+Float(step)*0.01,20,2),forward:SIMD3(0,1,0),right:SIMD3(1,0,0),up:SIMD3(0,0,1),
                moveSpeed:SIMD3(0,0.1,0),bounds:.init(maxX:1,minY:-2,maxZ:1,min:SIMD3(-1,-2,-1),max:SIMD3(1,2,1)),heightAboveRoad:1,eye:SIMD3(-0.3,0,0.2))
            reference.trace={_,_,_ in step%3==0 ? 1.2:nil};observed.trace=reference.trace
            let now=Double(step)*1000/Double(hz)
            if step==10 {reference.shake(at:input.position,strength:0.4,nowMilliseconds:now);observed.shake(at:input.position,strength:0.4,nowMilliseconds:now)}
            let a=reference.followVehicle(input,delta:1/Float(hz),nowMilliseconds:now,random:{random(&randomA)})!
            let b=observed.followVehicle(input,delta:1/Float(hz),nowMilliseconds:now,random:{random(&randomB)})!
            try require(a.source==b.source && a.target==b.target && a.verticalFov==b.verticalFov && a.heading==b.heading && a.pitch==b.pitch,"observation must not change camera algebra/shake")
            try require(randomA==randomB,"observation must not consume random inputs")
            try require(latest?.orbitPixels==[Double(x),Double(y)] && latest?.view==view && latest?.delta==1/Float(hz),"observed view/time/orbit reflect actual inputs")
            try require(latest?.actualEye==[b.source.x,b.source.y,b.source.z],"observation includes post-shake actual eye")
        }
        try require(count==120,"exactly one observation per valid follow call")
        observed.onVehicleObservation=nil
        _ = observed.followVehicle(.init(position:.zero,forward:SIMD3(0,1,0),right:SIMD3(1,0,0),bounds:.init(maxX:1,minY:-2,maxZ:1)),delta:1/60)
        try require(count==120,"stopping observation detaches callback")
    }}
}
private func record(_ stamp:Double=1,eye:[Float]=[0,0,1])->NativePassiveCameraTrace.Record {
    .init(camera:nil,ray:nil,draw:.init(monotonicMilliseconds:stamp,eye:eye,target:[0,1,1],nearPlane:0.15,farPlane:100,verticalFov:50,aspect:2,legacyCameraOverride:false))
}
private func lines(_ summary:NativePassiveCameraTrace.Summary)throws->[[String:Any]] {
    let data=try Data(contentsOf:summary.file)
    try require(data.count==summary.bytes,"summary accounts for actual file bytes")
    return try data.split(separator:10).map{try JSONSerialization.jsonObject(with:Data($0)) as! [String:Any]}
}
private func writer(_ output:URL)throws {
    let delayed=DispatchQueue(label:"authored.camera.writer-delayed")
    delayed.suspend()
    let directory=output.appendingPathComponent("bounded-pending")
    let recorder=NativePassiveCameraTrace(directory:directory,limits:.init(records:20,bytes:8192,pending:2),writerQueue:delayed)
    for i in 0..<10{recorder.submit(record(Double(i)))}
    try require(!FileManager.default.fileExists(atPath:directory.path),"submission performs no filesystem work on caller thread")
    var waiting:NativePassiveCameraTrace.Summary?
    recorder.stop{waiting=$0}
    try require(waiting==nil,"completion does not run before queued writes")
    delayed.resume()
    let timer=Timer(timeInterval:0.01,repeats:true){_ in};RunLoop.current.add(timer,forMode:.default)
    defer{timer.invalidate()}
    let deadline=Date().addingTimeInterval(10)
    while waiting==nil && Date()<deadline{_ = RunLoop.current.run(mode:.default,before:Date().addingTimeInterval(0.005))}
    try require(waiting != nil,"delayed writer completes")
    let summary=waiting!
    try require(summary.submitted==2 && summary.written==2 && summary.droppedQueue==8,"pending limit accounts for discarded records")
    try require(summary.error==nil && summary.bytes<=8192,"bounded writer finishes within disk budget")
    let rows=try lines(summary)
    try require(rows.count==4 && rows.first?["schema"] as? String=="zgta-passive-camera-v1" && rows.last?["summary"] != nil,"journal header/records/summary are genuine JSON")
    try require((rows.last?["summary"] as? [String:Any])?["bytes"] as? Int==summary.bytes,"persisted summary includes its own footer bytes")
    try require(!((rows.last?["summary"] as? [String:Any])?["file"] as? String ?? "").contains("/"),"journal omits the filesystem account/path")
    let again=try finish(recorder)
    try require(again.bytes==summary.bytes && again.written==summary.written,"repeated stop is idempotent")
    recorder.submit(record())
    let stoppedBytes=try Data(contentsOf:summary.file).count
    try require(stoppedBytes==summary.bytes,"stopped writer never appends late records")

    let held=DispatchQueue(label:"authored.camera.writer-held");held.suspend()
    let limited=NativePassiveCameraTrace(directory:output.appendingPathComponent("bounded-records"),limits:.init(records:3,bytes:8192,pending:20),writerQueue:held)
    for _ in 0..<10{limited.submit(record())};held.resume()
    let count=try finish(limited)
    try require(count.submitted==3 && count.written==3 && count.droppedLimit==7,"record limit is independent of writer speed")
    let bytes=NativePassiveCameraTrace(directory:output.appendingPathComponent("bounded-bytes"),limits:.init(records:20,bytes:8192,pending:20))
    for _ in 0..<20{bytes.submit(record(1,eye:[Float](repeating:1,count:1800)))}
    let capped=try finish(bytes)
    try require(capped.droppedBytes>0 && capped.bytes<=8192,"actual encoded size enforces disk cap")
    _ = try lines(capped)
    let bad=NativePassiveCameraTrace(directory:output.appendingPathComponent("bad-number"))
    bad.submit(record(.nan));let encoding=try finish(bad)
    try require(encoding.droppedEncoding==1 && encoding.written==0 && encoding.error==nil,"invalid diagnostic number cannot break camera or file lifecycle")
    let obstructed=output.appendingPathComponent("not-a-directory")
    try Data([1]).write(to:obstructed)
    let failed=NativePassiveCameraTrace(directory:obstructed);failed.submit(record())
    let error=try finish(failed)
    try require(error.error != nil && error.droppedIO==1,"I/O failure is reported and dropped record accounted")
    try require(error.error=="NSCocoaErrorDomain:516" && !(error.error ?? "").contains("/"),"I/O diagnostics retain a numeric cause without localized paths")
    let retained=output.appendingPathComponent("retained")
    try FileManager.default.createDirectory(at:retained,withIntermediateDirectories:true)
    let unrelated=retained.appendingPathComponent("unrelated.txt");try Data([7]).write(to:unrelated)
    for _ in 0..<6{let capture=NativePassiveCameraTrace(directory:retained);capture.submit(record());_ = try finish(capture)}
    let files=try FileManager.default.contentsOfDirectory(at:retained,includingPropertiesForKeys:nil)
    try require(files.filter{$0.pathExtension=="jsonl"}.count==4 && FileManager.default.fileExists(atPath:unrelated.path),"retention bounds only diagnostic files")
}

do {
    let output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    try lifecycle(output)
    try cameraObservations()
    try writer(output)
    let report:[String:Any]=["status":"PASS","checks":checks,"runtime":"actual host Rapier/Swift and extracted Renderer queries","originalResourcesUsed":false]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("report.json"))
    print("PASS \(checks) camera policy checks")
}catch{fputs("FAIL \(error)\n",stderr);exit(1)}
