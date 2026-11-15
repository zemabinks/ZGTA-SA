import Foundation
import simd

func collision(rectangles:[(Float,Float,Float,Float,Float)])->WorldCollision {
    var vertices:[SIMD3<Float>]=[],indices:[UInt32]=[]
    for (minX,maxX,y,minZ,maxZ) in rectangles {
        let base=UInt32(vertices.count)
        vertices += [SIMD3(minX,y,minZ),SIMD3(maxX,y,minZ),SIMD3(maxX,y,maxZ),SIMD3(minX,y,maxZ)]
        indices += [base,base+1,base+2,base,base+2,base+3]
    }
    var data=Data()
    func u32(_ value:UInt32){var little=value.littleEndian;withUnsafeBytes(of:&little){data.append(contentsOf:$0)}}
    u32(0x324c4353);u32(UInt32(vertices.count));u32(UInt32(indices.count/3));u32(0)
    for p in vertices {u32(p.x.bitPattern);u32(p.y.bitPattern);u32(p.z.bitPattern)}
    for index in indices {u32(index)}
    return try! WorldCollision(data:data)
}

struct FixturePlayer {let id:String;let position:SIMD3<Float>}
final class FixtureRenderer {
    var position=SIMD3<Float>.zero,aimDirection=SIMD3<Float>(0,1,0)
    var eventFeet:SIMD3<Float>?
    var shotFeet:SIMD3<Float> {eventFeet ?? position}
    var muzzleOverride:NativeWeaponMuzzle.Sample?
    var recordedRays:[(Int,SIMD3<Float>,SIMD3<Float>)]=[]
    var geometry:WorldCollision?=collision(rectangles:[])
    var visibilityCalls:[(SIMD3<Float>,SIMD3<Float>)]=[]
    func hasClearShot(from:SIMD3<Float>,to:SIMD3<Float>)->Bool {
        visibilityCalls.append((from,to));return geometry?.lineOfSight(from:from,to:to) ?? false
    }
    func weaponMuzzle(weapon:Int,left:Bool)->NativeWeaponMuzzle.Sample? {
        muzzleOverride ?? NativeWeaponMuzzle.sample(weapon:weapon,left:left,feet:shotFeet,definition:nil,pose:nil)
    }
    func recordWeaponShot(weapon:Int,origin:SIMD3<Float>,direction:SIMD3<Float>) {recordedRays.append((weapon,origin,direction))}
}
final class FixtureWeapons {
    struct Weapon {var range:Float=35;var fireKind="INSTANT_HIT"}
    var selected=22,current=Weapon()
}
final class FixtureAudio {var count=0;func shot(weapon:Int){count += 1}}
final class FixtureNetwork {
    struct Shot {let weapon:Int;let origin:SIMD3<Float>;let end:SIMD3<Float>;let player:String?;let ticket:NativeShotTicket;let streamPlayers:[String]}
    let sequence=NativeShotSequence()
    var orderedPlayers:[FixturePlayer]=[],shots:[Shot]=[]
    init(){precondition(sequence.negotiate("target-geometry-fixture"))}
    func reserveShot()->NativeShotTicket? {sequence.reserve()}
    @discardableResult func sendWeaponShot(weapon:Int,from:SIMD3<Float>,to:SIMD3<Float>,player:String?,ticket:NativeShotTicket,streamPlayers:[String]=[])->Bool {
        guard sequence.claim(ticket) else{return false}
        shots.append(.init(weapon:weapon,origin:from,end:to,player:player,ticket:ticket,streamPlayers:streamPlayers));return true
    }
}
final class ShotEmissionHarness {
    var renderer:FixtureRenderer?=FixtureRenderer()
    let weapons=FixtureWeapons(),audio=FixtureAudio(),network=FixtureNetwork()
    var aiming=true
    // ACTUAL_EMISSION_METHODS
    @discardableResult func fire(left:Bool=false)->Bool {
        guard let ray=currentShotRay(weapon:weapons.selected,left:left),let ticket=network.reserveShot() else{return false}
        emitWeaponShot(weapon:weapons.selected,left:left,ticket:ticket,ray:ray)
        return true
    }
}

@main enum ShotTargetingSmoke {
 static func main() throws {
    typealias T=NativeShotTargeting
    let root=URL(fileURLWithPath:CommandLine.arguments[1])
    var checks=0
    func candidate(_ id:String,_ feet:SIMD3<Float>)->T.Candidate {.init(id:id,point:T.torso(feet:feet))}
    func select(_ feet:SIMD3<Float>,_ target:SIMD3<Float>,_ aiming:Bool=true)->T.Selection? {
        let origin=T.muzzle(feet:feet),point=T.torso(feet:target),ray=T.Ray(origin:origin,direction:point-origin,range:100)!
        return T.select(ray:ray,aiming:aiming,candidates:[candidate("target",target)],visible:{_,_ in true})
    }
    let origin=T.muzzle(feet:.zero)
    var baseline:[[String:Any]]=[]
    for target in [SIMD3<Float>(0,1,0),SIMD3(0,1,0.6)] {
        let point=T.torso(feet:target),ray=T.Ray(origin:origin,direction:point-origin,range:35)!
        let old=simd_dot(simd_normalize(target),ray.direction)
        precondition(old<0.994 && select(.zero,target) != nil,"Reproduced flat/upward torso aim must no longer be rejected by feet geometry")
        baseline.append(["targetFeet":[target.x,target.y,target.z],"oldCosine":old,"threshold":0.994,"baselineAccepted":false,"fixedAccepted":true]);checks += 1
    }
    // Aimed/hip policy is retained; change geometry, not cone width.
    for aiming in [false,true] {
        let threshold:Float=aiming ? 0.994:0.95
        for delta:Float in [-0.0001,0.0001] {
            let angle=acos(threshold)+delta,ray=T.Ray(origin:origin,direction:SIMD3(0,1,0),range:35)!
            let point=origin+SIMD3(sin(angle)*10,cos(angle)*10,0)
            let result=T.select(ray:ray,aiming:aiming,candidates:[.init(id:"cone",point:point)],visible:{_,_ in true})
            precondition((result != nil)==(delta<0));checks += 1
        }
    }
    for heading in [-Double.pi,-179*Double.pi/180,0,Double.pi/2,359*Double.pi/180] {
        for pitch in [-0.6,-0.2,0,0.2,0.6] {for distance:Float in [0.51,1,2,35] {
            let facing=SIMD3<Float>(Float(sin(heading)*cos(pitch)),Float(cos(heading)*cos(pitch)),Float(sin(pitch)))
            for own in [SIMD3<Float>.zero,SIMD3(1480,-1738,13)] {
                let muzzle=T.muzzle(feet:own),point=muzzle+facing*distance,ray=T.Ray(origin:muzzle,direction:facing,range:36)!
                var seen:(SIMD3<Float>,SIMD3<Float>)?
                let result=T.select(ray:ray,aiming:true,candidates:[.init(id:"exact",point:point)],visible:{a,b in seen=(a,b);return true})
                precondition(result?.point==point && seen!.0==muzzle && seen!.1==point)
                checks += 1
            }
        }}
    }
    let ray=T.Ray(origin:origin,direction:SIMD3(0,20,0),range:35)!
    precondition(ray.direction==SIMD3(0,1,0) && ray.end==origin+SIMD3(0,35,0));checks += 1
    for (distance,accepted):(Float,Bool) in [(0.5,false),(0.5001,true),(35,true),(Float(35).nextUp,false)] {
        let result=T.select(ray:ray,aiming:true,candidates:[.init(id:"range",point:origin+SIMD3(0,distance,0))],visible:{_,_ in true})
        precondition((result != nil)==accepted);checks += 1
    }
    let tie=T.Candidate(id:"first",point:origin+SIMD3(0,5,0)),second=T.Candidate(id:"second",point:tie.point)
    precondition(T.select(ray:ray,aiming:true,candidates:[tie,second],visible:{_,_ in true})?.id=="first");checks += 1
    for direction in [SIMD3<Float>.zero,SIMD3(.nan,0,1),SIMD3(.infinity,0,1)] {
        precondition(T.Ray(origin:origin,direction:direction,range:35)==nil);checks += 1
    }
    for range:Float in [0,-1,.nan,.infinity] {precondition(T.Ray(origin:origin,direction:SIMD3(0,1,0),range:range)==nil);checks += 1}
    precondition(T.Ray(origin:SIMD3(.nan,0,0),direction:SIMD3(0,1,0),range:35)==nil);checks += 1
    precondition(T.select(ray:ray,aiming:true,candidates:[.init(id:"nan",point:SIMD3(.nan,1,2))],visible:{_,_ in preconditionFailure("Invalid target reached LOS")})==nil);checks += 1

    // Real triangle LOS: low cover can clear the torso segment, taller cover
    // blocks it, and an offset candidate can be visible around a narrow wall.
    let target=SIMD3<Float>(0,10,0),point=T.torso(feet:target),aim=T.Ray(origin:origin,direction:point-origin,range:35)!
    for (height,accepted):(Float,Bool) in [(1.2,true),(1.4,false),(3,false)] {
        let geometry=collision(rectangles:[(-2,2,5,0,height)])
        let selected=T.select(ray:aim,aiming:true,candidates:[candidate("cover",target)],visible:geometry.lineOfSight)
        precondition((selected != nil)==accepted);checks += 1
    }
    let narrow=collision(rectangles:[(-0.25,0.25,3,0,3)])
    let around=T.select(ray:ray,aiming:false,candidates:[candidate("blocked",SIMD3(0,5,0)),candidate("clear",SIMD3(2,8,0))],visible:narrow.lineOfSight)
    precondition(around?.id=="clear");checks += 1
    let highTarget=SIMD3<Float>(0,10,4),highPoint=T.torso(feet:highTarget),highRay=T.Ray(origin:origin,direction:highPoint-origin,range:35)!
    let upperWall=collision(rectangles:[(-2,2,5,2.8,3.6)])
    precondition(T.select(ray:highRay,aiming:true,candidates:[candidate("upward-wall",highTarget)],visible:upperWall.lineOfSight)==nil);checks += 1

    // Execute current VC methods; the captured selected point and LOS segment
    // must be exactly the origin/endpoint forwarded with the reserved ticket.
    let emission=ShotEmissionHarness(),renderer=emission.renderer!,feet=SIMD3<Float>(0,1,0.6),torso=T.torso(feet:feet)
    renderer.aimDirection=torso-T.muzzle(feet:renderer.position)
    emission.network.orderedPlayers=[.init(id:"elevated",position:feet)]
    precondition(emission.fire() && emission.network.shots.count==1 && emission.audio.count==1)
    let shot=emission.network.shots[0]
    precondition(shot.origin==T.muzzle(feet:renderer.position) && shot.end==torso && shot.player=="elevated")
    precondition(renderer.visibilityCalls[0].0==shot.origin && renderer.visibilityCalls[0].1==shot.end && shot.ticket.sequence==1)
    precondition(emission.fire(left:true) && emission.network.shots[1].ticket.sequence==2 && emission.network.shots[1].origin==shot.origin);checks += 4
    renderer.geometry=nil
    precondition(emission.fire() && emission.network.shots.last!.player==nil && emission.audio.count==3,"Missing geometry must not produce a player hit claim");checks += 1
    renderer.geometry=collision(rectangles:[(-2,2,0.5,0,3)])
    precondition(emission.fire() && emission.network.shots.last!.player==nil,"Wall must block target selection before a hit claim");checks += 1
    renderer.aimDirection = .zero
    let reserved=emission.network.sequence.reserved
    precondition(!emission.fire() && emission.network.sequence.reserved==reserved,"Invalid ray must be rejected before reserving a ticket");checks += 1
    renderer.aimDirection=SIMD3(0,1,0);emission.weapons.current.fireKind="PROJECTILE";emission.weapons.current.range=200
    precondition(emission.fire());let projectile=emission.network.shots.last!
    precondition(projectile.player==nil && projectile.end==projectile.origin+SIMD3(0,100,0) && emission.audio.count==4);checks += 2
    let event=ShotEmissionHarness(),eventRenderer=event.renderer!,eventFeet=SIMD3<Float>(4,8,2),eventTarget=SIMD3<Float>(4,18,2)
    eventRenderer.eventFeet=eventFeet
    eventRenderer.aimDirection=T.torso(feet:eventTarget)-T.muzzle(feet:eventFeet)
    event.network.orderedPlayers=[.init(id:"event-target",position:eventTarget)]
    precondition(event.fire());let eventShot=event.network.shots[0]
    precondition(eventShot.origin==T.muzzle(feet:eventFeet) && eventShot.origin != T.muzzle(feet:eventRenderer.position),"Fixed-step shot incorrectly used stale display feet")
    precondition(eventShot.player=="event-target" && eventShot.end==T.torso(feet:eventTarget) && eventShot.ticket.sequence==1)
    eventRenderer.eventFeet=nil
    eventRenderer.aimDirection=T.torso(feet:eventTarget)-T.muzzle(feet:eventRenderer.position)
    precondition(event.fire() && event.network.shots[1].origin==T.muzzle(feet:eventRenderer.position) && event.network.shots[1].ticket.sequence==2,"Outside an animation event the existing display-feet fallback must remain")
    checks += 4
    let blocked=ShotEmissionHarness(),blockedRenderer=blocked.renderer!
    blockedRenderer.muzzleOverride = .init(weapon:22,skill:1,origin:SIMD3(0,1,1.35),safetyOrigin:SIMD3(0,0,1.35),handOrigin:SIMD3(0,0.6,1.35),requestedLeft:false,usedLeft:false,fallbackReason:nil)
    blockedRenderer.geometry=collision(rectangles:[(-2,2,0.5,0,3)])
    blocked.network.orderedPlayers=[.init(id:"behind-wall",position:SIMD3(0,5,0))]
    precondition(blocked.fire());let safeShot=blocked.network.shots[0]
    precondition(safeShot.origin==SIMD3(0,0,1.35) && safeShot.player==nil,"A barrel crossing a wall cannot create a shot past it")
    precondition(blockedRenderer.recordedRays.last!.1==safeShot.origin);checks += 3
    let stream=ShotEmissionHarness(),streamRenderer=stream.renderer!
    stream.weapons.selected=37;stream.weapons.current.range=5.1;stream.weapons.current.fireKind="AREA_EFFECT"
    streamRenderer.aimDirection=SIMD3(0,1,0)
    stream.network.orderedPlayers=[.init(id:"side-a",position:SIMD3(0.7,2,0.45)),.init(id:"side-b",position:SIMD3(-0.7,2,0.45)),.init(id:"outside",position:SIMD3(0.81,2,0.45))]
    precondition(stream.fire());let streamShot=stream.network.shots[0]
    precondition(streamShot.player==nil && streamShot.streamPlayers==["side-a","side-b"],"Stream must use all eligible cylinder targets, not the aim cone")
    precondition(streamShot.end==streamShot.origin+SIMD3(0,5.1,0) && streamRenderer.recordedRays.last!.1==streamShot.origin);checks += 3

    let report:[String:Any]=["checks":checks,"baseline":baseline,"evidence":"Actual selection helper, current extracted VC emission methods, real triangle LOS and real shot-sequence tickets; no retail parity claim",
      "limits":["Muzzle1.35m and torso1.15m offsets remain body approximations","No per-hand or bone-derived hitboxes","Renderer native cross-cell occlusion gate is tested separately","No UIKit, GPU or live multiplayer playtest"]]
    let destination=root.appendingPathComponent("local-only/research/combat-targeting.json")
    try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:destination)
    print("PASS native shot targeting:",checks,"checks; close/upward feet mismatch reproduced and fixed; real LOS/current emission/tickets agree")
 }
}
