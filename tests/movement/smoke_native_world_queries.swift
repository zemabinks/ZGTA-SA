import Foundation
import simd
typealias WorldVector=SIMD3<Float>
final class QueryFixture {
    final class Vehicle {
        let world=SwiftRapierWorld(gravity:.zero)!
        var loaded=Set<String>()
        func isCellLoaded(_ name:String)->Bool {loaded.contains(name)}
    }
    let groundVehicle:Vehicle?=Vehicle()
    var character:NativeCharacterController?
    var camera=WorldVector(-1,-100,0)
    var networkInterior:Int?
    var interiorForTest:Bool {isInterior}
    // RENDERER_SCENE_OWNERSHIP
    var activeDetails:Set<String>=["c119"]
    var collisionRequests=NativeCollisionRequests(),desiredPhysicsCells=Set<String>(),requested=Set<String>()
    func loadCollision(name:String){requested.insert(name)}
    // Explicit appearance boundary: the actual query still requests original
    // surface detail, while this carrier exercises real Rapier geometry only.
    var sharpRequests=0
    func loadWorldSharpIfNeeded(){sharpRequests+=1}
    func query(_ start:WorldVector,_ way:WorldVector,_ distance:Float)->NativeWorldRay.Result {
        worldRay(from:start,direction:way,distance:distance,groups:0xffff0083)
    }
    // RENDERER_QUERY
}
@main enum WorldQueriesSmoke {
 static func main() {
    var checks=0
    func check(_ condition:Bool,_ label:String){checks += 1;precondition(condition,label)}
    let scene=QueryFixture(),manager=scene.groundVehicle!,world=manager.world
    scene.camera.z=701;check(scene.interiorForTest,"archive fallback interior heuristic")
    scene.networkInterior=0;check(!scene.interiorForTest,"legacy explicit exterior overrides altitude")
    scene.camera.z=0;scene.networkInterior=3;check(scene.interiorForTest,"legacy explicit interior overrides altitude")
    scene.networkInterior=nil
    let start=WorldVector(-1,-100,1.35),way=WorldVector(1,0,0)
    manager.loaded=["c119","c120"]
    scene.character=NativeCharacterController(world:world)
    scene.character?.reset(feet:scene.camera)
    if case .clear=scene.query(start,way,2) {checks += 1}else{fatalError("Own walker/probe must not block the Renderer ray")}
    let wall=world.addBox(halfExtents:WorldVector(0.05,2,2),position:SwiftRapierWorld.gtaToRapier(WorldVector(0.5,-100,1.35)))!
    if case .hit(let hit)=scene.query(start,way,2) {
        check(abs(hit.distance-1.45)<0.0001,"Ray reaches solid geometry across cell edge")
        check(hit.normal.x < -0.99,"Native normal returns in GTA axes")
    }else{fatalError("Cross-cell wall was missed")}
    manager.loaded.remove("c120")
    if case .unavailable(let at)=scene.query(start,way,2){check(abs(at-1)<0.0001,"Missing cell stops camera at its boundary")}
    else{fatalError("Missing geometry must not be a clear ray")}
    check(scene.requested.contains("c120"),"Renderer requests missing ray geometry")
    check(scene.sharpRequests==3,"Actual query retains original surface-detail admission")
    let cameraTable=try! Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
    let follow=try! NativeGameCamera(data:cameraTable)
    follow.setDirection(heading:Float.pi/2,pitch:0)
    follow.trace={_,_,_ in 0.1}
    follow.unavailableDistance={_,_,_ in 0.1}
    let closeBoundary=follow.followFoot(.init(position:WorldVector(-0.1,-100,0)),delta:1/60)!
    check(abs(closeBoundary.source.x+0.1)<0.0001,"On-foot wall minimum cannot push camera through unknown geometry")
    let aimingBoundary=follow.followFoot(.init(position:WorldVector(-0.1,-100,0),weapon:22,aiming:true),delta:1/60)!
    check(abs(aimingBoundary.aimSource!.x+0.1)<0.0001,"Aiming camera also respects sub-minimum streaming boundary")
    follow.unavailableDistance=nil
    let solidWall=follow.followFoot(.init(position:WorldVector(-0.1,-100,0)),delta:1/60)!
    check(abs(solidWall.source.x+0.5)<0.0001,"Loaded solid wall retains original minimum camera reach")
    let before=world.addBox(halfExtents:WorldVector(0.05,2,2),position:SwiftRapierWorld.gtaToRapier(WorldVector(-0.5,-100,1.35)))!
    if case .hit=scene.query(start,way,2){checks += 1}else{fatalError("Known wall before unknown boundary still blocks")}
    world.removeCollider(before);world.removeCollider(wall)
    let corner=NativeWorldRay.coverage(from:WorldVector(-1,1,1),to:WorldVector(1,-1,1),interior:false,loaded:{["c135","c120"].contains($0)})!
    check(corner.cells==["c135","c120"] && corner.firstUnavailable==nil,"Corner-only unrelated tile is not required")
    let high=NativeWorldRay.coverage(from:WorldVector(0,0,699.9),to:WorldVector(1,0,701),interior:false,loaded:{$0.hasPrefix("c")})!
    check(high.firstUnavailable==nil && high.cells.allSatisfy{$0.hasPrefix("c")},"Muzzle height does not change actor scene")
    var requests=NativeCollisionRequests()
    requests.request(Set((0..<30).map{"c\($0)"}),now:1,visible:["c119"])
    check(requests.retained(now:1,visible:["c119"]).count==9,"Eight extra collision cells bound residency")
    check(requests.retained(now:4,visible:["c119"])==["c119"],"Unused prediction cells expire")
    requests.request(["i4"],now:5,visible:[]);requests.reset()
    check(requests.retained(now:5,visible:[]).isEmpty,"Scene reset drops old requests")
    var reference:[NativeWeaponEffects.Projectile]?
    for hz in [15,20,30,60,90,120,144] {
        let effects=NativeWeaponEffects()
        effects.lob(weapon:16,from:WorldVector(0,0,100),direction:way)
        effects.launch(weapon:35,from:WorldVector(0,0,100),direction:way)
        for _ in 0..<hz*2 {effects.advance(delta:1/Double(hz))}
        if let reference {
            check(effects.projectiles.count==reference.count,"Fixed prediction preserves lifetime across FPS")
            for (a,b) in zip(effects.projectiles,reference) {
                check(a.position==b.position && a.velocity==b.velocity && a.age==b.age,"Identical fixed ticks at every display rate")
            }
        }else{reference=effects.projectiles}
    }
    let waiting=NativeWeaponEffects();var trails=0
    waiting.onTrail={_,_,_ in trails += 1};waiting.geometryAvailable={_,_,_ in false}
    waiting.launch(weapon:35,from:WorldVector(0,0,10),direction:way);waiting.advance(delta:0.2)
    check(waiting.projectiles[0].position==WorldVector(0,0,10) && abs(waiting.projectiles[0].age-0.2)<0.0001 && trails==0,"Missing geometry holds motion while the existing lifetime policy advances without fake impacts/trails")
    waiting.geometryAvailable={_,_,_ in true};waiting.advance(delta:0.2)
    check(abs(waiting.projectiles[0].position.x-13)<0.0001 && trails==12,"Prediction resumes without catch-up through missing walls")
    waiting.advance(delta:1.0);check(trails==12,"Suspension does not run a giant projectile step")
    let expiring=NativeWeaponEffects();var blockedBlasts=0,blockedTrails=0
    expiring.geometryAvailable={_,_,_ in false}
    expiring.onDetonation={_ in blockedBlasts+=1};expiring.onTrail={_,_,_ in blockedTrails+=1}
    expiring.launch(weapon:35,from:WorldVector(0,0,10),direction:way)
    for _ in 0..<360 {expiring.advance(delta:1.0/60)}
    check(expiring.projectiles.isEmpty && blockedBlasts==0 && blockedTrails==0,"Blocked prediction expires without inventing a blast or retaining an immortal projectile")
    let malformed:[[String:Any]]=[
        ["id":"p-1","weapon":16,"position":[0,0,10],"velocity":[1,0,0]],
        ["id":"p-1","weapon":16,"position":[0,0,10],"velocity":[1,0,0]],
        ["id":"p-2","weapon":16,"position":[0,0,10],"velocity":[Double.greatestFiniteMagnitude,0,0]]]
    waiting.synchronizeServer(malformed);waiting.synchronizeServer(malformed)
    check(waiting.projectiles.count==1,"Duplicate/overflow snapshot cannot poison reconciliation")
    let stream=NativeWeaponEffects(),barrier=SwiftRapierWorld(gravity:.zero)!
    let block=barrier.addBox(halfExtents:WorldVector(0.1,2,0.1),position:SwiftRapierWorld.gtaToRapier(WorldVector(1,0.35,0.9)))!
    stream.trace={o,d,n in barrier.raycast(origin:SwiftRapierWorld.gtaToRapier(o),direction:SwiftRapierWorld.gtaToRapier(d),distance:n).map{.init(distance:$0.distance,normal:SwiftRapierWorld.rapierToGTA($0.normal))}}
    var hits=0;stream.onStreamHit={_,_ in hits += 1}
    stream.stream(weapon:37,from:WorldVector(0,0,0.9),direction:way,delta:0.1,people:[.init(id:"side",position:WorldVector(2,0.7,0))])
    check(hits==0,"Off-axis stream victim is checked on its actual occlusion segment")
    barrier.removeCollider(block)
    stream.geometryAvailable={_,_,_ in false}
    stream.stream(weapon:37,from:WorldVector(0,0,0.9),direction:way,delta:0.3,people:[.init(id:"side",position:WorldVector(2,0.7,0))])
    check(hits==0,"Unloaded geometry cannot authorize a stream hit")
    let fire=NativeWeaponEffects();fire.groundHeight={_,_,_ in 0};fire.receiveBlast(weapon:18,position:WorldVector(3,0,0))
    let initial=fire.fires[0].flames.map(\.strength)
    fire.trace={_,_,_ in .init(distance:0.5,normal:WorldVector(-1,0,0))}
    fire.stream(weapon:42,from:WorldVector(0,0,0.9),direction:way,delta:0.4)
    check(fire.fires[0].flames.map(\.strength)==initial,"Extinguisher cannot erase a fire through solid geometry")
    print("PASS streamed world/prediction: \(checks) checks; extracted Renderer ray, native cross-cell wall, missing geometry, fixed FPS, stream/fire occlusion and snapshot validation")
 }
}
