import Foundation
import simd

/// Original19737 parked-body lifecycle. A visible parked car has a kinematic
/// chassis until nearby driving or a pedestrian press promotes its real solver.
final class NativeOtherVehicles {
    typealias V = SIMD3<Double>
    typealias Pose3 = NativeUnattendedVehicle.Pose
    struct Pose {
        let id:String
        let code:String
        let position:SIMD3<Float>
        let heading:Float
        let pitch:Float
        let roll:Float
        var health = 1000
        var damage = ""
        var work = 0
        var occupied = false
        var foreignAI = false
        var kept = false
    }
    struct Snapshot {
        let physicalPose:Pose3
        let position:SIMD3<Float>
        let heading:Float
        let pitch:Float
        let roll:Float
        let transform:simd_float4x4
        let health:Int
        let damage:String
        let work:Int
        let dynamic:Bool
        let frontSpin:Double
        let rearSpin:Double
        let offsets:[Double]
        let rotor:Double
        let gearUp:Bool
    }
    private final class Entry {
        let id:String,model:String
        let definition:NativeGroundVehicle.Definition
        var source:Pose
        var pose:Pose3
        var target:Pose3
        var lastRaw:Pose
        var floorAligned=false
        var body:SwiftRapierWorld.BodyID?
        var solids:Set<SwiftRapierWorld.ColliderID> = []
        var rig:NativeUnattendedVehicle?
        var rest=0.0,sentAt = -Double.infinity,shovedAt = -Double.infinity
        var health:Int,damage:String,work:Int
        var reference:Pose3?
        var press:(direction:SIMD2<Double>,point:V,speed:Double)?
        var fallen=false
        var hauled=false
        var support:SwiftRapierWorld.ColliderID?
        var supportBody:SwiftRapierWorld.BodyID?
        var supportPosition:SIMD3<Float>?
        var workingGeneration = -1,workingValue:Int?
        var workingBody:SwiftRapierWorld.BodyID?
        var rotor=0.0,gearUp=false
        var frontSpin=0.0,rearSpin=0.0
        init(_ source:Pose,model:String,definition:NativeGroundVehicle.Definition,pose:Pose3){
            id=source.id;self.model=model;self.definition=definition;self.source=source;lastRaw=source
            self.pose=pose;target=pose;health=source.health;damage=source.damage;work=source.work
        }
        var chassisColliderIDs:Set<SwiftRapierWorld.ColliderID>{rig?.colliders ?? solids}
        var colliderIDs:Set<SwiftRapierWorld.ColliderID>{
            var result=chassisColliderIDs
            if let support{result.insert(support)}
            return result
        }
        var bodyID:SwiftRapierWorld.BodyID?{rig?.body ?? body}
    }
    private let world:SwiftRapierWorld
    private var definitions:[String:NativeGroundVehicle.Definition] = [:]
    private var couplingDefinitions:[String:NativeGroundVehicle.CouplingDefinition] = [:]
    private var workingGeneration=0
    private var entries:[String:Entry] = [:]
    private var order:[String] = []
    private(set) var colliders:Set<SwiftRapierWorld.ColliderID> = []
    private(set) var rhinos:Set<SwiftRapierWorld.ColliderID> = []
    /// These entries correspond to the original parked/remote `others` owner.
    /// Vehicle material63 below supports damage queries; the browser did not
    /// register these vehicle handles in its separate `materials` map.
    var cameraExcludedColliderIDs:Set<SwiftRapierWorld.ColliderID> {
        var result=Set<SwiftRapierWorld.ColliderID>()
        for entry in entries.values {
            guard let body=entry.bodyID,
                  NativeCameraCollisionPolicy.excludes(otherMember:true,originalMaterialMember:false,
                    dynamicBody:world.bodyKind(body) == .dynamic) else{continue}
            result.formUnion(entry.colliderIDs.filter{world.colliderBelongs($0,to:body)})
        }
        return result
    }
    var onMove:((String,[String:Any])->Void)?
    var onCollidersChanged:(()->Void)?
    var waterLevel:((V)->Double?)?
    var waterWave:((V)->NativeVehicleBuoyancy.Wave)?
    var wetness=0.0
    var random:()->Double={Double.random(in:0..<1)}
    private var now=0.0
    init(world:SwiftRapierWorld){self.world=world}
    func load(_ definitions:[String:NativeGroundVehicle.Definition]){clear();self.definitions=definitions}
    func setCouplingDefinitions(_ profiles:[String:NativeGroundVehicle.CouplingDefinition]) {
        couplingDefinitions=profiles;workingGeneration &+= 1
        for entry in entries.values{applyWorkingCollisionPose(entry);updateTrailerSupport(entry)}
        rebuildColliders()
    }
    private func applyWorkingCollisionPose(_ entry:Entry) {
        guard let body=entry.bodyID else{entry.workingBody=nil;return}
        let changed=entry.workingBody != body || entry.workingGeneration != workingGeneration
        guard changed || entry.workingValue != entry.work else{return}
        let ids=entry.chassisColliderIDs.sorted()
        if changed {for (id,shape) in zip(ids,entry.definition.chassis){_ = world.setColliderTranslationWrtParent(id,position:shape.centre)}}
        if let profile=couplingDefinitions[entry.model],let working=profile.working {
            for shape in working.movingShapes where ids.indices.contains(shape.index) {
                let position=NativeGroundVehicle.workingPosition(shape.at,value:Double(entry.work),configuration:profile)
                _ = world.setColliderTranslationWrtParent(ids[shape.index],position:SIMD3<Float>(position))
            }
        }
        entry.workingBody=body;entry.workingGeneration=workingGeneration;entry.workingValue=entry.work
    }
    private func removeTrailerSupport(_ entry:Entry) {
        if let support=entry.support{_ = world.removeCollider(support)}
        entry.support=nil;entry.supportBody=nil;entry.supportPosition=nil
    }
    /// The parked manager's support is a separate, massless sphere. It is
    /// absent from kinematic/hauled bodies and must not enter chassis indexing.
    private func updateTrailerSupport(_ entry:Entry) {
        let wheels=entry.definition.configuration.wheels
        let position:SIMD3<Float>?
        if entry.rig != nil,!entry.hauled,entry.definition.configuration.kind=="trailer",
           !wheels.isEmpty,wheels.allSatisfy({$0.centre.z>=0}),
           let hook=couplingDefinitions[entry.model]?.trailerAnchor {
            position=SIMD3(0,0.3,Float(0.55*hook.z))
        }else{position=nil}
        if let position,let support=entry.support,entry.supportBody==entry.bodyID,
           entry.supportPosition==position,world.colliderInfo(support) != nil{return}
        removeTrailerSupport(entry)
        guard let position,let body=entry.rig?.body,
              let sphere=world.addSphere(radius:0.3,body:body,position:position,friction:1,restitution:0) else{return}
        _ = world.setColliderFrictionCombine(sphere,.average)
        _ = world.setColliderGroups(sphere,collision:8454127,solver:0xffffffff)
        entry.support=sphere;entry.supportBody=body;entry.supportPosition=position
    }
    func clear(){for id in Array(order){remove(id)};entries.removeAll();order.removeAll();rebuildColliders()}
    private func rawEqual(_ a:Pose,_ b:Pose)->Bool {
        a.position==b.position && a.heading==b.heading && a.pitch==b.pitch && a.roll==b.roll && a.health==b.health && a.damage==b.damage && a.work==b.work && a.occupied==b.occupied && a.foreignAI==b.foreignAI && a.kept==b.kept
    }
    func synchronize(_ poses:[Pose],excluding:String?,near viewer:SIMD3<Float>,promoteNear:SIMD3<Float>? = nil,delta:Double=0,now:Double=ProcessInfo.processInfo.systemUptime*1000){
        self.now=now
        // Local ownership revokes parked prediction even when that entry has
        // already been promoted. Distance streaming may retain a dynamic body;
        // excluding the driven vehicle must never retain its duplicate hull.
        if let excluding {remove(excluding)}
        var wanted:Set<String> = []
        for source in poses where source.id != excluding {
            let model=String(source.code.split(separator:".").first ?? "")
            guard let definition=definitions[model],source.position.x.isFinite,source.position.y.isFinite,source.position.z.isFinite,
                  source.heading.isFinite,source.pitch.isFinite,source.roll.isFinite else{continue}
            // A locally simulated body survives distance culling until the
            // source rest/fall demotion rules have run below.
            if entries[source.id]?.rig == nil && simd_distance(source.position,viewer)>=160{continue}
            wanted.insert(source.id)
            if let old=entries[source.id],old.model != model{remove(source.id)}
            if let entry=entries[source.id]{
                let changed = !rawEqual(entry.lastRaw,source)
                entry.source=source
                // Release local simulation before applying the authoritative
                // occupied pose. Demoting afterwards overwrote that target
                // with the old parked position; a stationary remote driver
                // then never supplied another changed packet to correct it.
                if entry.rig != nil && (source.occupied || source.kept || source.foreignAI) { entry.hauled=false;demote(entry) }
                if changed {
                    entry.health=source.health;entry.damage=source.damage;entry.work=source.work
                    if let rig=entry.rig {
                        // Authoritative updates refresh damage but never drag
                        // an actively simulated parked body to its echoed pose.
                        rig.damage.load(health:Double(source.health),text:source.damage);rig.damage.events.removeAll()
                        rig.car?.setTyres(rig.damage.wheels);rig.bike?.setTyres(rig.damage.wheels)
                    } else {
                        entry.target=Self.pose(source)
                        entry.floorAligned=false
                    }
                    entry.lastRaw=source
                }
            } else {
                let entry=Entry(source,model:model,definition:definition,pose:Self.pose(source));entries[source.id]=entry;order.append(source.id)
                if !source.occupied && source.pitch==0 && source.roll==0 {
                    // ej initially has no asynchronously loaded model: its
                    // exact fallback probe dimensions are1.6m and.8m.
                    entry.floorAligned=align(&entry.pose,heading:-Double(source.heading),definition:nil)
                    entry.target=entry.pose
                }
                makeKinematic(entry)
            }
        }
        for id in Array(order) where !wanted.contains(id) && entries[id]?.rig == nil{remove(id)}
        update(delta:max(0,delta),near:promoteNear.map{V(SwiftRapierWorld.gtaToRapier($0))},now:now)
    }
    private static func pose(_ p:Pose)->Pose3{.init(position:V(SwiftRapierWorld.gtaToRapier(p.position)),rotation:NativeUnattendedVehicle.rotation(heading:Double(p.heading),pitch:Double(p.pitch),roll:Double(p.roll)))}
    private func below(_ at:V,_ distance:Double)->Double?{
        world.raycast(origin:SIMD3<Float>(at),direction:SIMD3(0,-1,0),distance:Float(distance),groups:0xffff0001).map{Double($0.distance)}
    }
    @discardableResult private func align(_ pose:inout Pose3,heading:Double,definition:NativeGroundVehicle.Definition?)->Bool{
        let length=definition.map{max(0.8,0.8*min(-$0.blastMinimum.y,$0.blastMaximum.y))} ?? 1.6
        let width=definition.map{max(0.5,0.8*min(-$0.blastMinimum.x,$0.blastMaximum.x))} ?? 0.8
        let forward=V(-sin(heading),0,-cos(heading)),right=V(cos(heading),0,-sin(heading)),height=pose.position.y+2
        func probe(_ front:Double,_ side:Double)->Double?{
            var point=pose.position+forward*front+right*side;point.y=height
            guard let distance=below(point,4),abs(height-distance-pose.position.y)<=1.5 else{return nil};return height-distance
        }
        guard let front=probe(length,0),let rear=probe(-length,0),let r=probe(0,width),let l=probe(0,-width) else{return false}
        pose.position.y=(front+rear+r+l)/4
        pose.rotation=NativeUnattendedVehicle.rotation(heading:-heading,pitch:atan2(front-rear,2*length),roll:-atan2(r-l,2*width));return true
    }
    func update(delta:Double,near:V?,now:Double){
        self.now=now
        for id in order {guard let entry=entries[id] else{continue}
            if entry.rig == nil,entry.rotor>0 {
                entry.rotor=NativeFlightDynamics.stoppedTurning(kind:entry.definition.configuration.kind,amount:entry.rotor,ticks:50*delta)
            }
            if entry.rig == nil {
                if !entry.floorAligned && !entry.source.occupied && entry.source.pitch==0 && entry.source.roll==0 {
                    // Collision cells can arrive after the first native row.
                    // Retry the same four source probes once geometry exists.
                    entry.floorAligned=align(&entry.target,heading:-Double(entry.source.heading),definition:entry.definition)
                }
                let amount=1-exp(-delta/0.15)
                if simd_distance(entry.pose.position,entry.target.position)>8{entry.pose.position=entry.target.position}
                else{entry.pose.position += (entry.target.position-entry.pose.position)*amount}
                entry.pose.rotation=simd_slerp(entry.pose.rotation,entry.target.rotation,amount)
                if simd_distance(entry.pose.position,entry.target.position)<0.005{entry.pose=entry.target}
            }
            let radius=hypot(entry.definition.length,entry.definition.width)/2
            if entry.rig == nil && entry.health>0 && !entry.source.occupied && !entry.source.foreignAI && !entry.source.kept,
               let near,simd_distance(entry.pose.position,near)<radius+6{promote(entry)}
            if let rig=entry.rig,let state=rig.state {
                let slow=simd_length(state.linearVelocity)<0.15
                let far=now-entry.shovedAt>=400 && (near.map{simd_distance(entry.pose.position,$0)>radius+11} ?? true)
                entry.rest=slow && far ? entry.rest+delta:0
                let fell=far && below(entry.pose.position,400)==nil
                if entry.health<=0 || !entry.hauled && (entry.rest>1.5 || fell) {
                    demote(entry);onMove?(entry.id,packet(entry))
                }else if now-entry.sentAt>100 {
                    entry.sentAt=now;onMove?(entry.id,packet(entry))
                }
            }
        }
    }
    private func makeKinematic(_ entry:Entry){
        removeTrailerSupport(entry)
        guard let body=world.addBody(kind:.kinematicPosition,position:SIMD3<Float>(entry.pose.position),rotation:simd_quatf(vector:SIMD4<Float>(entry.pose.rotation.vector))) else{return}
        entry.body=body;entry.solids=[]
        for shape in entry.definition.chassis {
            let collider:SwiftRapierWorld.ColliderID?
            if shape.kind=="sphere"{collider=world.addSphere(radius:shape.radius,body:body,position:shape.centre,friction:shape.friction,restitution:shape.restitution)}
            else{collider=world.addBox(halfExtents:shape.halfExtents,body:body,position:shape.centre,friction:shape.friction,restitution:shape.restitution)}
            guard let collider else{continue}
            world.setColliderGroups(collider,collision:8454127,solver:entry.definition.configuration.kind=="train" ? 0xffffffff:33554944)
            world.setColliderPiece(collider,piece:Int32(shape.piece));world.setColliderSurface(collider,surface:2,material:63);entry.solids.insert(collider)
        }
        if entry.solids.count != entry.definition.chassis.count{world.removeBody(body);entry.body=nil;entry.solids=[]}
        applyWorkingCollisionPose(entry)
        rebuildColliders()
    }
    private func promote(_ entry:Entry){
        guard entry.rig == nil,entry.definition.configuration.kind != "train" else{return}
        if let body=entry.body{world.removeBody(body);entry.body=nil;entry.solids=[]}
        entry.rig=NativeUnattendedVehicle(world:world,definition:entry.definition,pose:entry.pose,health:Double(entry.health),damage:entry.damage,fallen:entry.fallen,rotor:entry.rotor,gearUp:entry.gearUp,
            waterLevel:{[weak self] in self?.waterLevel?($0)},waterWave:{[weak self] in self?.waterWave?($0) ?? .init(height:0,normal:V(0,1,0))})
        entry.rig?.restoreWheelSpin(front:entry.frontSpin,rear:entry.rearSpin)
        entry.rig?.random=random;entry.rest=0;entry.sentAt = -Double.infinity
        if let rig=entry.rig{entry.fallen=rig.fallen}else{makeKinematic(entry)}
        applyWorkingCollisionPose(entry)
        updateTrailerSupport(entry)
        rebuildColliders()
    }
    private func demote(_ entry:Entry){
        guard let rig=entry.rig else{return}
        removeTrailerSupport(entry)
        if let state=rig.state{entry.pose = .init(position:V(state.position),rotation:NativeUnattendedVehicle.quaternion(state.rotation));entry.target=entry.pose}
        entry.rotor=rig.rotor;entry.gearUp=rig.gearUp
        entry.frontSpin=rig.frontSpin;entry.rearSpin=rig.rearSpin
        rig.dispose();entry.rig=nil;entry.reference=nil;makeKinematic(entry)
    }
    func beforeStep(delta:Double){
        for id in order {guard let entry=entries[id] else{continue}
            applyWorkingCollisionPose(entry)
            if let rig=entry.rig {
                entry.reference=entry.pose;rig.beforeStep(delta:delta,wetness:wetness,held:entry.hauled)
                if let press=entry.press{rig.shove(direction:press.direction,point:press.point,speed:press.speed)}
            }else if let body=entry.body {
                world.setNextKinematicPose(body,position:SIMD3<Float>(entry.pose.position),rotation:simd_quatf(vector:SIMD4<Float>(entry.pose.rotation.vector)))
                world.setBrowserNextKinematicRotation(body,rotation:simd_quatf(vector:SIMD4<Float>(entry.pose.rotation.vector)))
            }
            entry.press=nil
        }
    }
    func afterStep(delta:Double){
        for id in order {guard let entry=entries[id],let rig=entry.rig else{continue}
            rig.afterStep(delta:delta,reference:entry.reference ?? entry.pose)
            if entry.health>0{entry.health=max(1,min(entry.health,Int(floor(rig.damage.health+0.5))))}
            entry.damage=rig.damage.text()
            if let state=rig.state{entry.pose = .init(position:V(state.position),rotation:NativeUnattendedVehicle.quaternion(state.rotation));entry.target=entry.pose}
        }
    }
    func shove(body:SwiftRapierWorld.BodyID,direction:SIMD2<Double>,point:V,speed:Double){
        guard let entry=order.compactMap({entries[$0]}).first(where:{$0.bodyID==body}),entry.health>0,
              !entry.source.occupied,!entry.source.foreignAI,!entry.source.kept,entry.definition.configuration.kind != "train" else{return}
        if entry.rig == nil{promote(entry)}
        guard entry.rig != nil else{return}
        entry.press=(direction,point,speed);entry.shovedAt=now;entry.rest=0
    }
    func take(_ id:String)->Snapshot? {
        guard let entry=entries[id] else{return nil}
        let e=NativeUnattendedVehicle.euler(entry.pose.rotation)
        if entry.definition.configuration.kind=="bike" && (abs(e.pitch)>0.5 || abs(e.roll)>0.5) {
            entry.pose.rotation=NativeUnattendedVehicle.rotation(heading:-e.heading,pitch:0,roll:0);entry.pose.position.y += 0.3
        }
        let result=snapshot(id);remove(id);return result
    }
    func park(_ source:Pose,physicalPose:Pose3?=nil,linear:V = .zero,angular:V = .zero,rotor:Double=0,gearUp:Bool=false,wheelSpin:SIMD2<Double> = .zero) {
        remove(source.id)
        let model=String(source.code.split(separator:".").first ?? "")
        guard let definition=definitions[model] else{return}
        let entry=Entry(source,model:model,definition:definition,pose:physicalPose ?? Self.pose(source))
        entry.rotor=rotor;entry.gearUp=gearUp
        entry.frontSpin=wheelSpin.x.isFinite ? wheelSpin.x:0
        entry.rearSpin=wheelSpin.y.isFinite ? wheelSpin.y:0
        entry.floorAligned=true;entries[source.id]=entry;order.append(source.id)
        if definition.configuration.kind=="train"{makeKinematic(entry)}
        else {
            entry.rig=NativeUnattendedVehicle(world:world,definition:definition,pose:entry.pose,linear:linear,angular:angular,health:Double(source.health),damage:source.damage,rotor:rotor,gearUp:gearUp,
                waterLevel:{[weak self] in self?.waterLevel?($0)},waterWave:{[weak self] in self?.waterWave?($0) ?? .init(height:0,normal:V(0,1,0))})
            entry.rig?.restoreWheelSpin(front:entry.frontSpin,rear:entry.rearSpin)
            entry.rig?.random=random;entry.sentAt = -Double.infinity
            if let rig=entry.rig{entry.fallen=rig.fallen}else{makeKinematic(entry)}
            applyWorkingCollisionPose(entry)
            updateTrailerSupport(entry)
            rebuildColliders()
        }
    }
    func bodyID(_ id:String)->SwiftRapierWorld.BodyID?{entries[id]?.bodyID}
    func colliderIDs(_ id:String)->Set<SwiftRapierWorld.ColliderID>{entries[id]?.colliderIDs ?? []}
    func bodyState(_ id:String)->SwiftRapierWorld.BodyState?{entries[id]?.bodyID.flatMap{world.bodyState($0)}}
    func supportFrames(configurations:[String:NativeGroundVehicle.CouplingDefinition])->[NativeGroundVehicle.SupportFrame] {
        order.compactMap { id in
            guard let entry=entries[id],let body=entry.bodyID,world.bodyState(body) != nil else{return nil}
            // Body queries retain Rapier's Float state. The archived ride's
            // entry is the live visual pose, also used to draw the vehicle.
            return .init(id:id,model:entry.model,body:body,position:entry.pose.position,rotation:entry.pose.rotation,
                origin:entry.definition.configuration.origin,kind:entry.definition.configuration.kind,work:Double(entry.work),configuration:configurations[entry.model])
        }
    }
    /// Confirmed coupling pins the actual solver; distance/rest must not turn
    /// one end of a live joint into a replacement kinematic body.
    @discardableResult func haul(_ id:String)->Bool {
        guard let entry=entries[id],entry.health>0,!entry.source.occupied,!entry.source.foreignAI,!entry.source.kept,
              entry.definition.configuration.kind != "train" else{return false}
        // The archived haul transition creates a fresh solver at the current
        // parked pose, with zero initial velocities and no support sphere.
        // Releasing that held solver below preserves its acquired momentum.
        if let rig=entry.rig {
            if let state=rig.state{entry.pose = .init(position:V(state.position),rotation:NativeUnattendedVehicle.quaternion(state.rotation));entry.target=entry.pose}
            entry.rotor=rig.rotor;entry.gearUp=rig.gearUp
            removeTrailerSupport(entry);rig.dispose();entry.rig=nil;entry.reference=nil
        }
        entry.hauled=true;promote(entry)
        guard entry.rig != nil else{entry.hauled=false;return false}
        entry.rest=0;rebuildColliders();return true
    }
    func unhaul(_ id:String) {
        guard let entry=entries[id],entry.hauled else{return}
        entry.hauled=false;entry.rest=0
        updateTrailerSupport(entry);rebuildColliders()
        // Retain the current body/velocities; ordinary unattended rest rules
        // resume on subsequent steps. The release is sent without a stop pose.
        onMove?(id,packet(entry))
    }
    func couplingVehicle(_ id:String,definitions:[String:NativeGroundVehicle.CouplingDefinition])->NativeGroundVehicle.CouplingVehicle? {
        guard let entry=entries[id],let configuration=definitions[entry.model] else{return nil}
        let pose=entry.bodyID.flatMap{world.bodyState($0)}.map{Pose3(position:V($0.position),rotation:NativeUnattendedVehicle.quaternion($0.rotation))} ?? entry.pose
        return .init(id:id,body:entry.bodyID,configuration:configuration,pose:pose,health:entry.health,
            occupied:entry.source.occupied,claimed:entry.source.foreignAI || entry.source.kept,dynamic:entry.rig != nil,hauled:entry.hauled)
    }
    func couplingVehicles(definitions:[String:NativeGroundVehicle.CouplingDefinition])->[NativeGroundVehicle.CouplingVehicle] {
        order.compactMap{couplingVehicle($0,definitions:definitions)}
    }
    func snapshot(_ id:String)->Snapshot?{
        guard let entry=entries[id] else{return nil}
        let e=NativeUnattendedVehicle.euler(entry.pose.rotation),output=entry.rig?.output
        var offsets=[Double](repeating:0,count:4)
        for wheel in output?.wheels ?? [] where offsets.indices.contains(wheel.index){offsets[wheel.index]=wheel.offset}
        return .init(physicalPose:entry.pose,position:SwiftRapierWorld.rapierToGTA(SIMD3<Float>(entry.pose.position)),heading:Float(-e.heading),pitch:Float(e.pitch),roll:Float(-e.roll),
            transform:NativeGroundVehicle.transform(position:entry.pose.position,rotation:entry.pose.rotation,origin:entry.definition.configuration.origin),
            health:entry.health,damage:entry.damage,work:entry.work,dynamic:entry.rig != nil,frontSpin:entry.rig?.frontSpin ?? entry.frontSpin,rearSpin:entry.rig?.rearSpin ?? entry.rearSpin,offsets:offsets,
            rotor:entry.rig?.rotor ?? entry.rotor,gearUp:entry.rig?.gearUp ?? entry.gearUp)
    }
    func movePacket(_ id:String)->[String:Any]? {
        guard let entry=entries[id] else{return nil}
        let current=entry.bodyID.flatMap{world.bodyState($0)}.map{Pose3(position:V($0.position),rotation:NativeUnattendedVehicle.quaternion($0.rotation))}
        return packet(entry,pose:current)
    }
    private func packet(_ entry:Entry,pose:Pose3?=nil)->[String:Any]{
        func round(_ n:Double,_ scale:Double)->Double{floor(n*scale+0.5)/scale}
        let physical=pose ?? entry.pose,e=NativeUnattendedVehicle.euler(physical.rotation),p=physical.position
        return ["x":round(p.x,100),"y":round(-p.z,100),"z":round(p.y,100),"h":round(e.heading,1000),"p":round(e.pitch,1000),"r":round(e.roll,1000),"hp":entry.health,"d":entry.damage,"w":entry.work]
    }
    private func rebuildColliders(){
        colliders=[];rhinos=[]
        for entry in entries.values{colliders.formUnion(entry.colliderIDs);if entry.model=="432"{rhinos.formUnion(entry.colliderIDs)}}
        onCollidersChanged?()
    }
    @discardableResult func remove(_ id:String)->Bool {
        guard let entry=entries.removeValue(forKey:id) else{return false}
        removeTrailerSupport(entry)
        if let rig=entry.rig{rig.dispose()}else if let body=entry.body{world.removeBody(body)}
        order.removeAll{$0==id};rebuildColliders()
        return true
    }
}
