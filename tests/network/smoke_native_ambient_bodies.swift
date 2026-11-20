// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
private var checks=0
private func check(_ condition:Bool,_ message:String){precondition(condition,message);checks+=1}
@main private enum Main {
    static func main(){
        let world=SwiftRapierWorld(gravity:.zero)!
        var owner:NativeAmbientPedestrianBodies?=NativeAmbientPedestrianBodies(world:world)
        func actor(_ x:Double=1,seed:UInt8=1,flags:UInt8=0,generation:UInt64=0)->NativeAmbientPedestrians.Frame {
            .init(id:1,skin:14,seed:seed,flags:flags,position:SIMD3(x,2,13),velocity:.zero,heading:0,state:nil,generation:generation)
        }
        owner!.synchronize([actor()],near:SIMD3(1,2,13),enabled:true);check(world.step(),"Actual Rapier step")
        check(owner!.colliders.count==1,"NPC body missing")
        let first=owner!.colliders.first!,info=world.colliderInfo(first)!
        check(info.body != nil && world.bodyKind(info.body!) == .kinematicPosition,"NPC lost kinematic ownership")
        check(simd_distance(info.translation,SIMD3(1,13.9,-2))<0.00001,"NPC feet/capsule/axis conversion")
        if case .capsule(let halfHeight,let radius)=info.shape{check(abs(halfHeight-0.55)<0.00001 && abs(radius-0.3)<0.00001,"Actual capsule shape changed")}
        else{preconditionFailure("Actual collider is not a capsule")}
        owner!.synchronize([actor(2)],near:SIMD3(1,2,13),enabled:true);check(world.step(),"Actual kinematic movement step")
        check(owner!.colliders==[first],"Ordinary movement recreated NPC body")
        check(simd_distance(world.colliderInfo(first)!.translation,SIMD3(2,13.9,-2))<0.00001,"Kinematic body did not follow authoritative actor")
        let walker=world.addCapsule(halfHeight:0.55,radius:0.35,position:SIMD3(2.5,13.9,-2))!;check(world.step(),"Actual contact step")
        check((world.contact(first,walker,prediction:0)?.distance ?? 1)<0,"Actual nearby character capsule did not contact NPC")
        world.removeCollider(walker)
        owner!.synchronize([actor(2,seed:2)],near:SIMD3(1,2,13),enabled:true);check(world.step(),"Identity replacement step")
        check(world.colliderInfo(first)==nil && owner!.colliders.count==1,"Identity replacement retained old contact body")
        let replaced=owner!.colliders.first!
        owner!.synchronize([actor(2,seed:2,generation:1)],near:SIMD3(1,2,13),enabled:true)
        check(world.step(),"New lifetime Rapier step")
        check(world.colliderInfo(replaced)==nil && owner!.colliders.count==1,"Same ID/skin/seed respawn retained previous physical body")
        let lifetimeBody=owner!.colliders.first!
        owner!.synchronize([actor(3,seed:2,generation:1)],near:SIMD3(1,2,13),enabled:true)
        check(owner!.colliders==[lifetimeBody],"Same lifetime movement recreated body")
        let second=owner!.colliders.first!
        owner!.synchronize([actor(2,seed:2,flags:9)],near:SIMD3(1,2,13),enabled:true)
        check(owner!.colliders.isEmpty && world.colliderInfo(second)==nil,"Dead NPC retained standing collider")
        owner!.synchronize([actor()],near:SIMD3(100,2,13),enabled:true);check(owner!.colliders.isEmpty,"Distant NPC got contact body")
        owner!.synchronize([actor()],near:SIMD3(1,2,13),enabled:true);let third=owner!.colliders.first!
        owner!.synchronize([actor()],near:SIMD3(1,2,13),enabled:false)
        check(owner!.colliders.isEmpty && world.colliderInfo(third)==nil,"Driving/inactive transition retained NPC body")
        owner!.synchronize([actor()],near:SIMD3(1,2,13),enabled:true);let last=owner!.colliders.first!;owner=nil
        check(world.colliderInfo(last)==nil,"NPC owner disposal leaked physical collider")
        print("PASS actual Rapier NPC bodies: \(checks) checks; no UIKit, vehicle runover, full character motor, server or retail acceptance")
    }
}
