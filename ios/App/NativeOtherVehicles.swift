import Foundation
import simd

/// Original remote/parked manager's62540/19737 kinematic chassis path. Reuses
/// the actual23895 chassis builder output, collision masks and piece labels.
/// Dynamic unattended promotion/towing remains a separate manager state.
final class NativeOtherVehicles {
    struct Pose {
        let id:String
        let code:String
        let position:SIMD3<Float>
        let heading:Float
        let pitch:Float
        let roll:Float
    }
    private struct Entry {
        let model:String
        let body:SwiftRapierWorld.BodyID
        let colliders:Set<SwiftRapierWorld.ColliderID>
        let rhino:Bool
    }
    private let world:SwiftRapierWorld
    private var definitions:[String:NativeGroundVehicle.Definition] = [:]
    private var entries:[String:Entry] = [:]
    private(set) var colliders:Set<SwiftRapierWorld.ColliderID> = []
    private(set) var rhinos:Set<SwiftRapierWorld.ColliderID> = []
    init(world:SwiftRapierWorld) {self.world = world}
    func load(_ definitions:[String:NativeGroundVehicle.Definition]) {
        clear();self.definitions = definitions
    }
    func clear() {
        for entry in entries.values {world.removeBody(entry.body)}
        entries.removeAll();colliders.removeAll();rhinos.removeAll()
    }
    func synchronize(_ poses:[Pose],excluding:String?,near position:SIMD3<Float>) {
        var wanted:Set<String> = []
        for pose in poses where pose.id != excluding && simd_distance(pose.position,position)<160 {
            let model=String(pose.code.split(separator:".").first ?? "")
            guard let definition=definitions[model],pose.position.x.isFinite,pose.position.y.isFinite,pose.position.z.isFinite,
                  pose.heading.isFinite,pose.pitch.isFinite,pose.roll.isFinite else {continue}
            wanted.insert(pose.id)
            if let old=entries[pose.id],old.model != model {remove(pose.id)}
            let translation=SwiftRapierWorld.gtaToRapier(pose.position)
            let rotation=NativeGroundVehicle.rotation(heading:pose.heading,pitch:pose.pitch,roll:pose.roll)
            if entries[pose.id] == nil {
                guard let body=world.addBody(kind:.kinematicPosition,position:translation,rotation:rotation) else {continue}
                var shapes:Set<SwiftRapierWorld.ColliderID> = []
                for shape in definition.chassis {
                    let id:SwiftRapierWorld.ColliderID?
                    if shape.kind == "sphere" {id=world.addSphere(radius:shape.radius,body:body,position:shape.centre,friction:shape.friction,restitution:shape.restitution)}
                    else {id=world.addBox(halfExtents:shape.halfExtents,body:body,position:shape.centre,friction:shape.friction,restitution:shape.restitution)}
                    guard let id else {continue}
                    // Original19737.B installs PARKED and W sets OTHERS solver
                    // groups for every category except train carriages.
                    world.setColliderGroups(id,collision:8454127,solver:definition.configuration.kind == "train" ? 0xffffffff:33554944)
                    world.setColliderPiece(id,piece:Int32(shape.piece));world.setColliderSurface(id,surface:2,material:63)
                    shapes.insert(id)
                }
                guard shapes.count == definition.chassis.count else {world.removeBody(body);wanted.remove(pose.id);continue}
                entries[pose.id] = Entry(model:model,body:body,colliders:shapes,rhino:model == "432")
                colliders.formUnion(shapes);if model == "432" {rhinos.formUnion(shapes)}
            }
            if let entry=entries[pose.id] {world.setNextKinematicPose(entry.body,position:translation,rotation:rotation)}
        }
        for id in Array(entries.keys) where !wanted.contains(id) {remove(id)}
    }
    private func remove(_ id:String) {
        guard let entry=entries.removeValue(forKey:id) else {return}
        world.removeBody(entry.body);colliders.subtract(entry.colliders);rhinos.subtract(entry.colliders)
    }
}
