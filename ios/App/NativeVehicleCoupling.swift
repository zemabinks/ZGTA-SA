import Foundation
import simd

/// Confirmed local coupling constraints. Independent server authority owns the
/// topology; candidate detection never creates a speculative joint. All anchor
/// geometry is imported locally and remains in Rapier Y-up body coordinates.
final class NativeVehicleCoupling {
    typealias V=SIMD3<Double>
    enum Kind:String,Hashable {case trailer,tow}
    struct Link:Hashable {let parent:String,trailer:String;let kind:Kind}
    struct Request:Hashable {
        let parent:String,trailer:String?;let kind:Kind,generation:UInt64
        init(parent:String,trailer:String?,kind:Kind,generation:UInt64=0){self.parent=parent;self.trailer=trailer;self.kind=kind;self.generation=generation}
    }
    struct Guide {let id:String,bar:V,hitch:V,gap:Double,high:Double,near:Bool}
    private struct Physical {
        let link:Link,joint:SwiftRapierWorld.JointID,parent:SwiftRapierWorld.BodyID,trailer:SwiftRapierWorld.BodyID
        let bar:V,hitch:V
    }
    private weak var ground:NativeGroundVehicle?
    private let world:SwiftRapierWorld
    private var connection:String?
    private(set) var revision = -1
    private(set) var owner:String?
    private var topology:[Link]=[]
    private var physical:[Link:Physical]=[:]
    private var invalid:Set<Link>=[]
    private var pending:Set<Request>=[]
    private var inFlight:Set<Request>=[]
    private var rejectedUntil:[Request:Double]=[:]
    private var releasedID:String?,releasedAt = -Double.infinity
    private var now=0.0
    private var generation:UInt64=0
    /// Return true only after the current connection accepted the request for
    /// delivery. Its own sequence/ACK owner must not replay uncertain actions.
    var onRequest:((Request)->Bool)?
    init(ground:NativeGroundVehicle){self.ground=ground;world=ground.world}
    deinit {for item in physical.values{_ = world.removeJoint(item.joint);ground?.unhaulOtherVehicle(id:item.link.trailer)}}
    var towing:String? {chain.first?.trailer}
    var behind:String? {chain.dropFirst().first?.trailer}
    var towedCar:String? {chain.first(where:{$0.kind == .tow})?.trailer}
    var activeJointCount:Int {physical.count}
    private var chain:[Link] {
        guard let owner else{return []}
        var result:[Link]=[],parent=owner
        for _ in 0..<2 {guard let link=topology.first(where:{$0.parent==parent}) else{break};result.append(link);parent=link.trailer}
        return result
    }
    func reset(connection:String?=nil) {
        for link in chain.reversed(){removePhysical(link,recordRelease:false)}
        for link in Array(physical.keys){removePhysical(link,recordRelease:false)}
        topology=[];invalid=[];pending=[];inFlight=[];rejectedUntil=[:];revision = -1;self.connection=connection;releasedID=nil;releasedAt = -.infinity;owner=nil;now=0;generation &+= 1
    }
    func setOwnedVehicle(_ id:String?) {
        guard id != owner else{return}
        for link in chain.reversed(){removePhysical(link,recordRelease:false)}
        pending=[];inFlight=[];rejectedUntil=[:];invalid=[];owner=id;generation &+= 1
    }
    @discardableResult func applyTopology(_ links:[Link],revision:Int,connection:String,nowMilliseconds:Double)->Bool {
        guard self.connection==connection,revision>=0,revision>=self.revision,nowMilliseconds.isFinite,
              Self.validTopology(links) else{return false}
        if revision==self.revision {return Set(links)==Set(topology)}
        now=max(now,nowMilliseconds)
        let previous=chain;topology=links
        let wanted=Set(chain)
        for link in previous.reversed() where !wanted.contains(link){removePhysical(link,recordRelease:true)}
        for link in Array(physical.keys) where !wanted.contains(link){removePhysical(link,recordRelease:true)}
        invalid=invalid.intersection(Set(links));self.revision=revision;rejectedUntil=[:]
        pending=pending.filter {request in
            if let target=request.trailer {return !links.contains(Link(parent:request.parent,trailer:target,kind:request.kind))}
            return links.contains(where:{$0.parent==request.parent})
        }
        reconcile(towAnchor:nil)
        return true
    }
    private static func validTopology(_ links:[Link])->Bool {
        guard links.count<=4096 else{return false}
        var parents:Set<String>=[],targets:Set<String>=[]
        for link in links {
            guard !link.parent.isEmpty,!link.trailer.isEmpty,link.parent.count<=128,link.trailer.count<=128,
                  link.parent != link.trailer,parents.insert(link.parent).inserted,targets.insert(link.trailer).inserted else{return false}
        }
        let rows=Dictionary(uniqueKeysWithValues:links.map{($0.parent,$0)})
        for link in links {
            var seen:Set<String>=[link.parent],current:Link?=link,count=0
            while let row=current {
                count+=1
                guard count<=2,seen.insert(row.trailer).inserted else{return false}
                if row.kind == .tow && rows[row.trailer] != nil{return false}
                current=rows[row.trailer]
            }
        }
        return true
    }
    private func endpoint(_ id:String)->NativeGroundVehicle.CouplingVehicle? {
        id==owner ? ground?.ownedCouplingVehicle(id:id):ground?.otherCouplingVehicle(id:id)
    }
    private func point(_ vehicle:NativeGroundVehicle.CouplingVehicle,_ local:V)->V {vehicle.pose.position+vehicle.pose.rotation.act(local)}
    private func removePhysical(_ link:Link,recordRelease:Bool) {
        guard let item=physical.removeValue(forKey:link) else{return}
        _ = world.removeJoint(item.joint)
        ground?.unhaulOtherVehicle(id:link.trailer)
        if recordRelease {releasedID=link.trailer;releasedAt=now}
    }
    private func compatible(_ parent:NativeGroundVehicle.CouplingVehicle,_ target:NativeGroundVehicle.CouplingVehicle,_ kind:Kind)->Bool {
        guard target.health>0,!target.occupied,!target.claimed else{return false}
        if kind == .tow {return parent.configuration.working?.tow==true && parent.configuration.working?.available==true && target.configuration.kind=="car"}
        return parent.configuration.targets.contains(target.configuration.id) && parent.configuration.rearAnchor != nil && target.configuration.trailerAnchor != nil
    }
    private func anchors(_ link:Link,_ parent:NativeGroundVehicle.CouplingVehicle,_ target:NativeGroundVehicle.CouplingVehicle,towAnchor:V?)->(V,V)? {
        if link.kind == .tow {guard let towAnchor else{return nil};return(towAnchor,target.configuration.frontAnchor)}
        guard let rear=parent.configuration.rearAnchor,let hook=target.configuration.trailerAnchor else{return nil};return(rear,hook)
    }
    private func broken(_ item:Physical)->Bool {
        guard world.jointExists(item.joint),let parent=endpoint(item.link.parent),let target=endpoint(item.link.trailer),
              parent.body==item.parent,target.body==item.trailer,parent.health>0,compatible(parent,target,item.link.kind) else{return true}
        let separation=simd_distance(point(parent,item.bar),point(target,item.hitch))
        if item.link.kind == .tow {return separation>3}
        let facing=simd_dot(parent.pose.rotation.act(V(0,0,-1)),target.pose.rotation.act(V(0,0,-1)))
        let up=simd_dot(parent.pose.rotation.act(V(0,1,0)),target.pose.rotation.act(V(0,1,0)))
        return facing < -0.3 || up<0 || separation>1.5
    }
    private func reconcile(towAnchor:V?) {
        guard connection != nil,let owner,!topology.contains(where:{$0.trailer==owner}) else{return}
        let rows=chain,epoch=generation
        for (index,link) in rows.enumerated() {
            if physical[link] != nil {continue}
            guard !invalid.contains(link),let parent=endpoint(link.parent),let target=endpoint(link.trailer),
                  parent.health>0,compatible(parent,target,link.kind),let body=parent.body,
                  let (bar,hook)=anchors(link,parent,target,towAnchor:towAnchor) else{break}
            let separation=simd_distance(point(parent,bar),point(target,hook))
            guard separation.isFinite else{break}
            if separation > (link.kind == .tow ? 3:1.5) {
                // Confirmation can arrive after both live endpoints have moved
                // beyond the ordinary break distance. No joint exists to trip
                // broken(), so retain explicit cleanup intent for this suffix.
                // Missing/streaming bodies or anchors continue waiting instead.
                guard let targetBody=target.body,targetBody != body,
                      world.bodyState(body) != nil,world.bodyState(targetBody) != nil else{break}
                for removed in rows.dropFirst(index).reversed() {
                    invalid.insert(removed);removePhysical(removed,recordRelease:true)
                    if generation != epoch{return}
                }
                break
            }
            guard let promoted=ground?.haulOtherVehicle(id:link.trailer),let other=promoted.body,other != body else{break}
            guard let joint=world.createSphericalJoint(body1:body,body2:other,anchor1:SIMD3<Float>(bar),anchor2:SIMD3<Float>(hook),contactsEnabled:false) else{
                ground?.unhaulOtherVehicle(id:link.trailer);break
            }
            physical[link]=Physical(link:link,joint:joint,parent:body,trailer:other,bar:bar,hitch:hook)
        }
    }
    private func send(_ request:Request) {
        let epoch=generation
        let request=Request(parent:request.parent,trailer:request.trailer,kind:request.kind,generation:epoch)
        guard !pending.contains(request),(rejectedUntil[request] ?? -.infinity)<=now else{return}
        inFlight.insert(request);defer{inFlight.remove(request)}
        guard onRequest?(request)==true,generation==epoch,(rejectedUntil[request] ?? -.infinity)<=now else{return}
        if let target=request.trailer {
            if topology.contains(Link(parent:request.parent,trailer:target,kind:request.kind)){return}
        }else if !topology.contains(where:{$0.parent==request.parent}){return}
        pending.insert(request)
    }
    /// Negative ACK retry policy, separate from the original released-target
    /// cooldown: at most one unchanged acquisition attempt per500ms. Cleanup
    /// requests never wait behind this backoff. Scope resets with its owner.
    func rejectRequest(_ request:Request) {
        guard request.generation==generation else{return}
        let outstanding=pending.remove(request) != nil || inFlight.contains(request)
        guard outstanding,request.trailer != nil else{return}
        rejectedUntil[request]=now+500
    }
    func requestRelease(nowMilliseconds:Double,secondOnly:Bool=false) {
        guard nowMilliseconds.isFinite else{return};now=max(now,nowMilliseconds)
        let rows=chain
        guard let row=secondOnly ? rows.dropFirst().first:rows.first else{return}
        send(Request(parent:row.parent,trailer:nil,kind:row.kind))
    }
    func removeVehicle(_ id:String) {
        let rows=chain
        let relevant=owner==id || rows.contains(where:{$0.parent==id || $0.trailer==id}) || pending.contains(where:{$0.parent==id || $0.trailer==id}) || inFlight.contains(where:{$0.parent==id || $0.trailer==id})
        for link in rows.dropFirst(rows.firstIndex(where:{$0.parent==id || $0.trailer==id}) ?? rows.count).reversed() {
            invalid.insert(link);removePhysical(link,recordRelease:true)
        }
        pending=pending.filter{$0.parent != id && $0.trailer != id}
        rejectedUntil=rejectedUntil.filter{$0.key.parent != id && $0.key.trailer != id}
        if owner==id {setOwnedVehicle(nil)}
        else if relevant {generation &+= 1;pending=[];inFlight=[];rejectedUntil=[:]}
    }
    func update(nowMilliseconds:Double,towAnchor:V?=nil,canAcquireTow:Bool=false) {
        guard nowMilliseconds.isFinite,connection != nil else{return};now=max(now,nowMilliseconds)
        rejectedUntil=rejectedUntil.filter{$0.value>now}
        let towAnchor=towAnchor.flatMap{$0.x.isFinite && $0.y.isFinite && $0.z.isFinite ? $0:nil}
        let epoch=generation,rowsBefore=chain
        for link in rowsBefore {
            guard var item=physical[link] else{continue}
            if link.kind == .tow,let towAnchor {
                _ = world.setJointAnchor1(item.joint,anchor:SIMD3<Float>(towAnchor))
                item=Physical(link:item.link,joint:item.joint,parent:item.parent,trailer:item.trailer,bar:towAnchor,hitch:item.hitch);physical[link]=item
            }
            if broken(item) {
                let index=rowsBefore.firstIndex(of:link)!
                for removed in rowsBefore.dropFirst(index).reversed(){invalid.insert(removed);removePhysical(removed,recordRelease:true)}
                if generation != epoch{return}
                break
            }
        }
        reconcile(towAnchor:towAnchor)
        if generation != epoch{return}
        // A broken constraint is removed immediately, but its confirmed link
        // remains cleanup intent until authority removes it. A transport that
        // declined delivery must get another chance on the next fixed step;
        // accepted pending requests are still deduplicated and never replayed.
        if let broken=chain.first(where:{invalid.contains($0)}) {
            send(Request(parent:broken.parent,trailer:nil,kind:broken.kind));return
        }
        guard pending.isEmpty,chain.count<2,let owner,let head=endpoint(owner),head.health>0 else{return}
        let rows=chain
        if rows.contains(where:{$0.kind == .tow}){return}
        let parentID=rows.last?.trailer ?? owner
        guard let parent=endpoint(parentID),parentID==owner || rows.allSatisfy({physical[$0] != nil}) else{return}
        let kind:Kind=parentID==owner && parent.configuration.working?.tow==true ? .tow:.trailer
        guard kind != .tow || canAcquireTow else{return}
        let bar=kind == .tow ? towAnchor:parent.configuration.rearAnchor
        guard let bar else{return}
        let at=point(parent,bar)
        for target in ground?.drawnCouplingVehicles() ?? [] {
            guard target.id != owner,target.id != parentID,!rows.contains(where:{$0.trailer==target.id}),!target.hauled,
                  compatible(parent,target,kind),!topology.contains(where:{$0.trailer==target.id || $0.parent==target.id}),
                  !(target.id==releasedID && now-releasedAt<2500) else{continue}
            let hook=kind == .tow ? target.configuration.frontAnchor:target.configuration.trailerAnchor
            guard let hook else{continue};let there=point(target,hook),horizontal=hypot(there.x-at.x,there.z-at.z)
            guard kind == .tow ? horizontal<0.5 && abs(there.y-at.y)<1:horizontal<=0.4 && abs(there.y-at.y)<=1 else{continue}
            let request=Request(parent:parentID,trailer:target.id,kind:kind,generation:generation)
            if (rejectedUntil[request] ?? -.infinity)>now{continue}
            send(request);break
        }
    }
    func guide(target:String?=nil,reach:Double=30)->Guide? {
        guard reach.isFinite,reach>0,chain.count<2,let owner else{return nil}
        let parentID=chain.last?.trailer ?? owner
        guard let parent=endpoint(parentID),let rear=parent.configuration.rearAnchor else{return nil}
        let bar=point(parent,rear);var result:Guide?
        for row in ground?.drawnCouplingVehicles() ?? [] {
            guard (target==nil || target==row.id),compatible(parent,row,.trailer),!row.hauled,
                  !topology.contains(where:{$0.trailer==row.id || $0.parent==row.id}),let hook=row.configuration.trailerAnchor else{continue}
            let hitch=point(row,hook),gap=hypot(hitch.x-bar.x,hitch.z-bar.z),high=abs(hitch.y-bar.y)
            guard gap<(result?.gap ?? reach) else{continue}
            result=Guide(id:row.id,bar:bar,hitch:hitch,gap:gap,high:high,near:gap<=0.8 && high<=1)
        }
        return result
    }
}
