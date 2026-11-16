import Foundation
import simd

/// Adapts the shared native world to the separate pedestrian support queries.
/// Imported meshes are owner-local; a failed reload retains the last complete
/// catalog. Missing geometry never becomes an invented vehicle box.
final class NativeVehicleSupportScene:NativeMovingSupport.Scene {
    typealias V=SIMD3<Double>
    struct Driver {let id:String,velocity:V,spin:V}
    private let world:SwiftRapierWorld
    private var definitions:[String:NativeVehicleTread.Definition]=[:]
    private var treads:[String:NativeVehicleTread]=[:],models:[String:String]=[:],names:[UInt64:String]=[:]
    private(set) var entries:[NativeMovingSupport.Entry]=[]
    var otherColliders:Set<UInt64>=[]
    init(world:SwiftRapierWorld){self.world=world}
    @discardableResult func load(_ data:Data)->Bool {
        guard let doc=try? JSONSerialization.jsonObject(with:data) as? [String:Any],doc["version"] as? Int==1,
              let rows=doc["models"] as? [String:[String:Any]],!rows.isEmpty,rows.count<=4096 else{return false}
        let parsed=rows.compactMapValues(NativeVehicleTread.Definition.init)
        guard parsed.count==rows.count,rows.allSatisfy({$0.key==String($0.value["id"] as? Int ?? -1)}) else{return false}
        definitions=parsed;invalidatePoses();return true
    }
    func invalidatePoses(){treads=[:];models=[:]}
    func clear(){entries=[];names=[:];treads=[:];models=[:];otherColliders=[]}
    func synchronize(_ frames:[NativeGroundVehicle.SupportFrame],drivers:[String:Driver]=[:]) {
        let old=Dictionary(uniqueKeysWithValues:entries.map{($0.id,$0)})
        var names:[UInt64:String]=[:],live:Set<String>=[]
        entries=frames.map { frame in
            let entry=old[frame.id] ?? NativeMovingSupport.Entry(handle:frame.body,id:frame.id,vehicle:frame.id,position:frame.position,rotation:frame.rotation)
            entry.handle=frame.body;entry.vehicle=frame.id;entry.position=frame.position;entry.rotation=frame.rotation
            entry.origin=frame.origin;entry.kind=frame.kind
            let driver=drivers[frame.id];entry.driver=driver?.id;entry.velocity=driver?.velocity;entry.spin=driver?.spin
            names[frame.body]=frame.id;live.insert(frame.id)
            if models[frame.id] != frame.model {
                treads[frame.id]=definitions[frame.model].map(NativeVehicleTread.init);models[frame.id]=frame.model
            }
            if let configuration=frame.configuration {
                treads[frame.id]?.pose(work:frame.work){NativeGroundVehicle.workingPosition($0,value:$1,configuration:configuration)}
            }
            return entry
        }
        self.names=names;treads=treads.filter{live.contains($0.key)};models=models.filter{live.contains($0.key)}
    }
    func body(_ id:UInt64)->NativeMovingSupport.Body? {
        guard let state=world.bodyState(id),let kind=world.bodyKind(id) else{return nil}
        return .init(id:id,position:V(state.position),rotation:NativeUnattendedVehicle.quaternion(state.rotation),dynamic:kind == .dynamic,
            velocity:V(state.linearVelocity),spin:V(state.angularVelocity))
    }
    func ray(origin:V,distance:Double,groups:UInt32)->NativeMovingSupport.Ray? {
        guard let hit=world.raycast(origin:SIMD3<Float>(origin),direction:SIMD3(0,-1,0),distance:Float(distance),groups:groups),let body=hit.body else{return nil}
        return .init(body:body,distance:Double(hit.distance))
    }
    func nearbyTreads(at:V,radius:Double,limit:Int)->[UInt64] {
        guard limit>0 else{return []};var result:[UInt64]=[],seen:Set<UInt64>=[]
        for hit in world.sphereIntersections(center:SIMD3<Float>(at),radius:Float(radius)) {
            guard otherColliders.contains(hit.id),let body=hit.body,let name=names[body],treads[name] != nil,seen.insert(body).inserted else{continue}
            result.append(body);if result.count>=limit{break}
        };return result
    }
    func treadRay(body:UInt64,origin:V,distance:Double)->Double? {
        guard let name=names[body],let tread=treads[name],let state=world.bodyState(body) else{return nil}
        return tread.ray(origin:origin,distance:distance,bodyPosition:V(state.position),bodyRotation:NativeUnattendedVehicle.quaternion(state.rotation))
    }
    func belowStatic(origin:V,distance:Double)->Double? {
        world.raycast(origin:SIMD3<Float>(origin),direction:SIMD3(0,-1,0),distance:Float(distance),groups:0xffff0001).map{Double($0.distance)}
    }
}
