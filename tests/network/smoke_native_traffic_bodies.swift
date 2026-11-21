// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
private var checks=0
private func check(_ condition:Bool,_ message:String){precondition(condition,message);checks+=1}
@main private enum Main {
    static func main(){
        let world=SwiftRapierWorld(gravity:.zero)!
        var owner:NativeAmbientTrafficBodies?=NativeAmbientTrafficBodies(world:world)
        // Authored chassis shape; original game files are not embedded here.
        let box=NativeAmbientTrafficBodies.Shape(kind:"box",centre:SIMD3(0,0.75,0),halfExtents:SIMD3(1,0.5,2),radius:0,friction:0.6,restitution:0.1,piece:3)
        func frame(_ x:Double=1,generation:UInt64=1,model:UInt16=420,heading:Double=0,pitch:Double=0)->NativeAmbientTrafficBodies.Snapshot{
            .init(id:17,generation:generation,model:model,position:SIMD3(x,2,13),heading:heading,pitch:pitch)
        }
        let origin=SIMD3<Float>(1,2,13)
        func synchronize(_ frames:[NativeAmbientTrafficBodies.Snapshot],enabled:Bool=true,available:Bool=true){
            owner!.synchronize(frames,near:origin,enabled:enabled,shapes:{_ in available ? [box]:nil})
            check(world.step(),"Actual Rapier step")
        }
        synchronize([frame()],available:false);check(owner!.colliders.isEmpty,"Missing original chassis received invented body")
        synchronize([frame()]);check(owner!.colliders.count==1,"Traffic chassis missing")
        let first=owner!.colliders.first!,info=world.colliderInfo(first)!
        check(world.bodyKind(info.body!) == .kinematicPosition,"Server traffic acquired dynamic/client ownership")
        check(simd_distance(info.translation,SIMD3(1,13.75,-2))<1e-5,"Ground/model-origin or GTA/Rapier basis error")
        if case .box(let half)=info.shape{check(simd_distance(half,SIMD3(1,0.5,2))<1e-5,"Original chassis dimensions changed")}
        else{preconditionFailure("Expected actual authored cuboid")}
        check(owner!.trafficID(for:first)==17,"Collider mapping entered registered/human ID namespace")
        synchronize([frame(2)]);check(owner!.colliders==[first],"Ordinary motion recreated traffic body")
        check(simd_distance(world.colliderInfo(first)!.translation,SIMD3(2,13.75,-2))<1e-5,"Traffic collider did not follow presented pose")
        let probe=world.addSphere(radius:0.4,position:SIMD3(3.2,13.75,-2))!
        check(world.step(),"Actual overlap step");check((world.contact(first,probe,prediction:0)?.distance ?? 1)<0,"Traffic has no actual nearby contact")
        world.removeCollider(probe)
        synchronize([frame(2,heading:Double.pi/2,pitch:Double.pi/6)])
        let rotation=world.bodyState(info.body!)!.rotation
        let forward=rotation.act(SIMD3<Float>(0,0,-1))
        check(simd_distance(forward,SIMD3(Float(cos(Double.pi/6)),0.5,0))<1e-5,"Mixed heading/pitch chassis does not match rendered GTA Rz*Rx basis")
        synchronize([frame(2,generation:2)]);check(world.colliderInfo(first)==nil && owner!.colliders.count==1,"ID reuse retained previous chassis")
        let reused=owner!.colliders.first!;synchronize([frame(2,generation:2,model:411)])
        check(world.colliderInfo(reused)==nil && owner!.colliders.count==1,"Model replacement retained previous shape owner")
        let distant=owner!.colliders.first!;synchronize([frame(100)])
        check(owner!.colliders.isEmpty && world.colliderInfo(distant)==nil,"Distance retirement leaked traffic collider")
        let many=(UInt16(0)..<UInt16(40)).map{NativeAmbientTrafficBodies.Snapshot(id:$0,generation:1,model:420,position:SIMD3(1+Double($0)/10,2,13),heading:0,pitch:0)}
        synchronize(many);check(owner!.colliders.count==NativeAmbientTrafficBodies.maximumBodies,"Traffic body budget is unbounded")
        let bounded=owner!.colliders;synchronize([],enabled:false)
        check(owner!.colliders.isEmpty && bounded.allSatisfy{world.colliderInfo($0)==nil},"Inactive/streamout traffic retained bodies")
        synchronize([frame()]);let last=owner!.colliders.first!;owner=nil
        check(world.colliderInfo(last)==nil,"Traffic owner disposal leaked chassis")
        print("PASS actual Rapier traffic bodies: \(checks) checks; authored shapes, contact, mixed-axis pose and bounded lifecycle. No original traffic AI, runover, server transfer, device or retail acceptance")
    }
}
