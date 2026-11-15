import Foundation
import simd

/// Owns the original ground-car solver, native Rapier integration and streamed
/// SCL2 chassis contacts. Unsupported vehicle categories retain their caller's
/// existing path until their separate original solvers have been translated.
final class NativeGroundVehicle {
    struct CameraFrame {
        let position: SIMD3<Float>
        let forward: SIMD3<Float>
        let right: SIMD3<Float>
        let up: SIMD3<Float>
        let moveSpeed: SIMD3<Float>
        let turnSpeed: SIMD3<Float>
        let wheels: Int
        let maxX: Float
        let minY: Float
        let maxZ: Float
        let minimum: SIMD3<Float>
        let maximum: SIMD3<Float>
        let heightAboveRoad: Float
        let eye: SIMD3<Float>?
    }
    struct Definition {
        struct Shape {
            let kind: String
            let centre: SIMD3<Float>
            let radius: Float
            let halfExtents: SIMD3<Float>
            let friction: Float
            let restitution: Float
            let collisionGroups: UInt32
            let solverGroups: UInt32
            let piece: Int
        }
        let configuration: NativeVehicleDynamics.Configuration
        let bikeConfiguration: NativeBikeDynamics.Configuration?
        let trainConfiguration: NativeTrainDynamics.Configuration?
        let flightParameters: NativeFlightDynamics.Parameters?
        let boatParameters: NativeVehicleBuoyancy.Parameters?
        let buoyancyMinimum: SIMD3<Double>
        let buoyancyMaximum: SIMD3<Double>
        let rearExtent: Double
        let collisionDamage: Double
        let damageWidth: Double
        let width:Double,length:Double,height:Double,rigidMass:Double
        let blastMinimum:SIMD3<Double>,blastMaximum:SIMD3<Double>
        let chassis: [Shape]
        let bounds: (maxX: Float,minY: Float,maxZ: Float,minimum: SIMD3<Float>,maximum: SIMD3<Float>)
        let eye: SIMD3<Float>?
        init?(_ row: [String: Any]) {
            guard row["solverSupported"] as? Bool == true, let id = row["id"] as? Int,
                  let values = row["table"] as? [String: Any], let origin = row["origin"] as? Double,
                  let wheelRows = (row["struts"] ?? row["wheels"]) as? [[String: Any]],
                  let shapeRows = row["chassis"] as? [[String: Any]], !shapeRows.isEmpty else { return nil }
            func vector(_ raw: Any?) -> SIMD3<Double>? {
                guard let v = raw as? [Double], v.count == 3, v.allSatisfy(\.isFinite) else { return nil }
                return SIMD3(v[0],v[1],v[2])
            }
            let wheels = wheelRows.compactMap { wheel -> NativeVehicleDynamics.WheelSpecification? in
                guard let centre = vector(wheel["centre"]), let radius = wheel["radius"] as? Double,
                      let front = wheel["front"] as? Bool, let left = wheel["left"] as? Bool,
                      radius > 0 else { return nil }
                return .init(centre: centre, radius: radius, front: front, left: left)
            }
            let shapes = shapeRows.compactMap { shape -> Shape? in
                guard let kind = shape["kind"] as? String, let centre = vector(shape["centre"]),
                      ["sphere","box"].contains(kind) else { return nil }
                let radius = (shape["radius"] as? NSNumber)?.floatValue ?? 0
                let half = vector(shape["halfExtents"]) ?? .zero
                guard kind == "sphere" ? radius > 0 : half.x > 0 && half.y > 0 && half.z > 0 else { return nil }
                return Shape(kind: kind, centre: SIMD3<Float>(centre), radius: radius, halfExtents: SIMD3<Float>(half),
                    friction: (shape["friction"] as? NSNumber)?.floatValue ?? 0,
                    restitution: (shape["restitution"] as? NSNumber)?.floatValue ?? 0,
                    collisionGroups: (shape["collisionGroups"] as? NSNumber)?.uint32Value ?? 0xffffffff,
                    solverGroups: (shape["solverGroups"] as? NSNumber)?.uint32Value ?? 0xffffffff,
                    piece: (shape["piece"] as? NSNumber)?.intValue ?? 0)
            }
            guard wheels.count == wheelRows.count, shapes.count == shapeRows.count else { return nil }
            guard let bounds = row["bounds"] as? [String: Any], let box = bounds["box"] as? [String: Any],
                  let low = vector(box["min"]), let high = vector(box["max"]) else { return nil }
            self.bounds = (Float((bounds["maxX"] as? Double) ?? max(abs(low.x),abs(high.x))),
                Float((bounds["minY"] as? Double) ?? low.y),Float((bounds["maxZ"] as? Double) ?? high.z),SIMD3<Float>(low),SIMD3<Float>(high))
            rearExtent = (bounds["minY"] as? Double) ?? low.y
            damageWidth = (bounds["maxX"] as? Double) ?? max(abs(low.x),abs(high.x))
            width=(row["width"] as? Double) ?? high.x-low.x;length=(row["length"] as? Double) ?? high.y-low.y;height=(row["height"] as? Double) ?? high.z-low.z
            rigidMass=((row["massProperties"] as? [String:Any])?["mass"] as? Double) ?? Double(Float((values["mass"] as? Double) ?? 1000))
            blastMinimum=low;blastMaximum=high
            collisionDamage = (values["collisionDamage"] as? Double) ?? 0.5
            eye = vector(row["driverEye"]).map { SIMD3<Float>($0) }
            let collisionBox = (row["collision"] as? [String: Any])?["box"] as? [String: Any]
            buoyancyMinimum = vector(collisionBox?["min"]) ?? low
            buoyancyMaximum = vector(collisionBox?["max"]) ?? high
            flightParameters = (row["flying"] as? [String: Any]).flatMap { NativeFlightDynamics.Parameters($0) }
            boatParameters = (row["boat"] as? [String: Any]).flatMap { NativeVehicleBuoyancy.Parameters($0) }
            configuration = .init(table: .init(model: id, values: values), origin: origin, wheels: wheels,
                kind: row["kind"] as? String ?? "car")
            trainConfiguration = configuration.kind == "train" ? .init(model:id,origin:origin,lower:configuration.table.lower,
                minimum:low,maximum:high,carriages:row["carriages"] as? [Int] ?? []) : nil
            if configuration.kind == "bike" {
                guard let hubs = row["hubs"] as? [String: [String: Any]],
                      let front = hubs["front"], let rear = hubs["rear"],
                      let frontAt = vector(front["at"]), let rearAt = vector(rear["at"]),
                      let frontRadius = front["radius"] as? Double, let rearRadius = rear["radius"] as? Double,
                      let parameters = row["bike"] as? [String: Double] else { return nil }
                bikeConfiguration = .init(table: configuration.table, origin: origin,
                    front: .init(at: frontAt, radius: frontRadius), rear: .init(at: rearAt, radius: rearRadius),
                    parameters: parameters, pedalled: row["pedalled"] as? Bool ?? false)
            } else { bikeConfiguration = nil }
            chassis = shapes
        }
    }
    let world: SwiftRapierWorld
    private lazy var others = NativeOtherVehicles(world:world)
    var otherColliders: Set<SwiftRapierWorld.ColliderID> {others.colliders}
    var onOtherMove:((String,[String:Any])->Void)?
    var onOtherCollidersChanged:(()->Void)?
    func synchronizeOtherVehicles(_ poses:[NativeOtherVehicles.Pose],excluding:String?,near position:SIMD3<Float>,
                                  promoteNear:SIMD3<Float>?=nil,delta:Double=0,wetness:Double=0) {
        others.wetness=wetness
        others.synchronize(poses,excluding:excluding,near:position,promoteNear:promoteNear,delta:delta)
    }
    func otherVehicle(_ id:String)->NativeOtherVehicles.Snapshot?{others.snapshot(id)}
    func takeOtherVehicle(_ id:String)->NativeOtherVehicles.Snapshot?{others.take(id)}
    func shoveOtherVehicle(body:UInt64,direction:SIMD2<Double>,point:SIMD3<Double>,speed:Double){
        others.shove(body:body,direction:direction,point:point,speed:speed)
    }
    func parkCurrentVehicle(id:String,code:String,health:Int,damage:String,work:Int) {
        guard let rigid,let current=world.bodyState(rigid) else{exit();return}
        let position=SwiftRapierWorld.rapierToGTA(current.position)
        let pose=NativeUnattendedVehicle.Pose(position:SIMD3<Double>(current.position),rotation:NativeUnattendedVehicle.quaternion(current.rotation))
        let angle=NativeUnattendedVehicle.euler(pose.rotation),rotor=dynamics?.flight?.turning ?? 0,gear=landingGearUp
        let source=NativeOtherVehicles.Pose(id:id,code:code,position:position,heading:Float(-angle.heading),pitch:Float(angle.pitch),roll:Float(-angle.roll),health:health,damage:damage,work:work)
        exit()
        others.park(source,physicalPose:pose,linear:SIMD3<Double>(current.linearVelocity),angular:SIMD3<Double>(current.angularVelocity),rotor:rotor,gearUp:gear)
    }
    private var definitions: [String: Definition] = [:]
    private var audioTopCache:[String:Double] = [:]
    private var cells: [String: [SwiftRapierWorld.ColliderID]] = [:]
    private var cellData: [String: Data] = [:]
    private var materialClasses: [Int] = []
    private struct CollisionPart: Equatable { let indexStart:Int;let indexCount:Int }
    private var collisionFallbackParts: [String:[CollisionPart]] = [:]
    private var loadedCells: Set<String> = []
    private var rigid: SwiftRapierWorld.BodyID?
    private(set) var chassisColliders: Set<SwiftRapierWorld.ColliderID> = []
    var onContactForces: (([SwiftRapierWorld.ContactForceEvent], SwiftRapierWorld.BodyID, Double) -> Void)?
    private(set) var damageController: NativeVehicleDamageController?
    var onDamageEvents: (([NativeVehicleDamage.Event], NativeVehicleDamage.Body) -> Void)?
    var onCollisions:(([NativeVehicleDamageController.Collision],NativeVehicleDamage.Body)->Void)?
    /// Original Rapier Y-up surface-query boundary, separated base/wave parts.
    var waterLevel: ((SIMD3<Double>) -> Double?)?
    var waterWave: ((SIMD3<Double>) -> NativeVehicleBuoyancy.Wave)?
    private var dynamics: NativeVehicleDynamics?
    private var bikeDynamics: NativeBikeDynamics?
    private var trainDynamics: NativeTrainDynamics?
    private var tracks: NativeTrainTracks?
    struct Carriage { let model:String;let transform:simd_float4x4;let position:SIMD3<Float> }
    private(set) var carriages:[Carriage] = []
    private var accumulator = 0.0
    private var visualWheelSpeed = 0.0
    private(set) var forwardSpeed = 0.0
    private(set) var output: NativeVehicleDynamics.Output?
    private var wheelClocks = [Double](repeating:0,count:4)
    var wheelAngles:[Float] {wheelClocks.map(Float.init)}
    var wheelAnglesDouble:[Double] {wheelClocks}
    private(set) var modelPosition = SIMD3<Float>.zero
    private(set) var bodyPosition = SIMD3<Float>.zero
    private(set) var modelTransform = matrix_identity_float4x4
    private(set) var orientation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
    private(set) var heading: Float = 0
    private(set) var pitch: Float = 0
    private(set) var roll: Float = 0
    private(set) var speed: Float = 0
    private(set) var model = ""
    var active: Bool { rigid != nil }
    var nativeLinearVelocity:SIMD3<Float> {
        guard let rigid,let state=world.bodyState(rigid) else{return .zero}
        return SwiftRapierWorld.rapierToGTA(state.linearVelocity)
    }
    var nativeAngularVelocity:SIMD3<Float> {
        guard let rigid,let state=world.bodyState(rigid) else{return .zero}
        return SwiftRapierWorld.rapierToGTA(state.angularVelocity)
    }
    var bikeLean: Float { Float(bikeDynamics?.lean ?? 0) }
    var bikeDrop: [Float] { bikeDynamics?.drop.map(Float.init) ?? [] }
    var bicyclePedal: Int { bikeDynamics?.pedal ?? 0 }
    var bicycleCrank: Float { Float(bikeDynamics?.crank ?? 0) }
    var bicycleHop: Float { Float(bikeDynamics?.hop ?? 0) }
    var bikeFullLean: Float { Float(definitions[model]?.bikeConfiguration?.parameters["fullAnimLean"] ?? 0) }
    var rotorTurning: Float { Float(dynamics?.flight?.turning ?? 0) }
    var aircraftNozzle: Float? {
        guard let flight=dynamics?.flight,flight.jets else { return nil }
        return Float(flight.nozzle)
    }
    var landingGearUp: Bool { dynamics?.flight?.gearUp ?? false }
    var onWater: Bool { dynamics?.buoyancy?.onWater ?? false }
    var lostInWater: Bool { dynamics?.buoyancy?.lost ?? false }
    var heard:NativeVehicleDynamics.HeardSnapshot? {bikeDynamics?.heard ?? dynamics?.heard}
    var drivesTop:Double {definitions[model].map{0.78*$0.configuration.table.maxVelocity/3.6} ?? 40}
    var rotorScalar:Double {dynamics?.flight?.rotor ?? 0}
    var flightThrottle:Double {dynamics?.flight?.throttle ?? 0}
    struct AudioSnapshot {
        let body:SwiftRapierWorld.BodyState;let speed:Double,top:Double,rotorTurning:Double,rotorScalar:Double,flightThrottle:Double
        let gas:Double?
        let heard:NativeVehicleDynamics.HeardSnapshot?;let skid:Double,surface:Int;let flat:Bool,nitro:Bool
    }
    func audioSnapshot()->AudioSnapshot? {
        guard let rigid,let body=world.bodyState(rigid) else{return nil}
        let wheels=output?.wheels ?? [],speed=abs(forwardSpeed)/50,gas=output?.gas ?? 0
        func isRear(_ index:Int)->Bool {bikeDynamics != nil ? index>=2:index==1 || index==3}
        let rear=wheels.contains{isRear($0.index) && $0.state==2}
        var skid=0.0,surface=2
        for wheel in wheels where wheel.compression<1 && wheel.state != 0 {
            surface=wheel.surface
            if wheel.state==1 {if abs(gas)>0.4 {skid += (abs(gas)-0.4)/0.6*0.75}}
            else if wheel.state==2 {if rear || isRear(wheel.index) {skid += 0.75*min(1,speed)}}
            else if speed>=0.04 {skid += 1.2*min(5*speed,1)}
        }
        return .init(body:body,speed:forwardSpeed,top:drivesTop,rotorTurning:dynamics?.flight?.turning ?? 0,rotorScalar:rotorScalar,flightThrottle:flightThrottle,gas:output?.gas,
            heard:heard,skid:skid,surface:surface,flat:wheels.contains{$0.tyre==1 && $0.counts>0},nitro:dynamics?.nitroBurning ?? false)
    }
    struct HullAudio {let gas:Double;let afloat:Bool;let up:Double;let slam:Double}
    func takeHullAudio()->HullAudio? {
        guard definitions[model]?.configuration.kind=="boat",let buoyancy=dynamics?.buoyancy,let rigid,let body=world.bodyState(rigid) else{return nil}
        let q=body.rotation;return .init(gas:buoyancy.gas,afloat:buoyancy.onWater,
            up:1-2*(Double(q.imag.x)*Double(q.imag.x)+Double(q.imag.z)*Double(q.imag.z)),slam:buoyancy.takeSlam())
    }
    var aloft:Bool {dynamics?.flight != nil && (output?.wheels.allSatisfy({$0.counts<=0}) ?? true)}
    /// Original19737.uw base vehicle kit. Special working-vehicle attachment
    /// controllers can supply their original override before this value.
    func wireKit(tuck:Double)->[Double]? {
        guard let definition=definitions[model] else{return nil}
        func round3(_ value:Double)->Double {floor(value*1000+0.5)/1000}
        var kit:[Double]?
        if let bike=bikeDynamics {
            kit=[round3(bike.lean),round3(tuck)]
            if definition.bikeConfiguration?.pedalled == true {
                let phase=((bike.crank.truncatingRemainder(dividingBy:1))+1).truncatingRemainder(dividingBy:1)
                kit! += [Double(bike.pedal),round3(phase),round3(bike.hop)]
            }
        }
        func put(_ index:Int,_ value:Double) {if kit==nil{kit=[]};while kit!.count<=index{kit!.append(0)};kit![index]=value}
        if let flight=dynamics?.flight,flight.jets {put(5,floor(flight.nozzle/5000*100+0.5)/100)}
        else if definition.configuration.table.flags&64 != 0 {put(5,round3(-(output?.rearSteering ?? 0)))}
        if landingGearUp && [476,519,577,520,553,592].contains(definition.configuration.table.model) {put(6,1)}
        if aloft {put(7,1)}
        return kit
    }
    func setLandingGear(_ raised: Bool) {
        guard let definition=definitions[model],[476,519,577,520,553,592].contains(definition.configuration.table.model),!raised || aloft else{return}
        dynamics?.flight?.setGear(raised)
    }
    var cameraFrame: CameraFrame? {
        guard let rigid, let body = world.bodyState(rigid), let definition = definitions[model] else { return nil }
        return CameraFrame(position:modelPosition,forward:orientation.act(SIMD3(0,1,0)),right:orientation.act(SIMD3(1,0,0)),up:orientation.act(SIMD3(0,0,1)),
            moveSpeed:SwiftRapierWorld.rapierToGTA(body.linearVelocity)/50,turnSpeed:SwiftRapierWorld.rapierToGTA(body.angularVelocity)/50,
            wheels:trainDynamics != nil ? 4:output?.wheels.filter { $0.counts > 0 }.count ?? 0,maxX:definition.bounds.maxX,minY:definition.bounds.minY,maxZ:definition.bounds.maxZ,
            minimum:definition.bounds.minimum,maximum:definition.bounds.maximum,heightAboveRoad:Float(definition.configuration.origin),eye:definition.eye)
    }

    init?() {
        guard let world = SwiftRapierWorld(gravity: SIMD3(0,-18,0)) else { return nil }
        world.enableArchivedStepping()
        if let seabed = world.addBox(halfExtents: SIMD3(150,1,150), position: SIMD3(0,-71,0)) {
            world.setColliderGroups(seabed, collision: 131071, solver: 0xffffffff)
        }
        self.world = world
        others.waterLevel = {[weak self] in self?.waterLevel?($0)}
        others.waterWave = {[weak self] in self?.waterWave?($0) ?? .init(height:0,normal:SIMD3(0,1,0))}
        others.onMove = {[weak self] in self?.onOtherMove?($0,$1)}
        others.onCollidersChanged = {[weak self] in self?.onOtherCollidersChanged?()}
        world.beforeStep = {[weak self] in self?.others.beforeStep(delta:$0)}
        world.afterStep = {[weak self] in self?.others.afterStep(delta:$0)}
    }

    @discardableResult func loadDefinitions(_ data: Data) -> Int {
        guard let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = document["models"] as? [String: [String: Any]] else { return 0 }
        definitions = rows.compactMapValues { Definition($0) }
        audioTopCache.removeAll()
        others.load(rows.compactMapValues { row in var value=row;value["solverSupported"]=true;return Definition(value) })
        let classes = document["materialClasses"] as? [Int] ?? []
        let parts = (document["collisionFallbackParts"] as? [String:[[String:Any]]] ?? [:]).mapValues { rows in
            rows.compactMap { row -> CollisionPart? in
                guard let start=row["indexStart"] as? Int,let count=row["indexCount"] as? Int,
                      start>=0,count>=0,start%3==0,count%3==0 else { return nil }
                return CollisionPart(indexStart:start,indexCount:count)
            }
        }
        let changedMaterials = classes.count == 256 && classes != materialClasses
        if changedMaterials || parts != collisionFallbackParts {
            if changedMaterials { materialClasses = classes };collisionFallbackParts = parts
            for identifiers in cells.values { for id in identifiers { world.removeCollider(id) } }
            cells.removeAll(); loadedCells.removeAll()
            for (name,contents) in cellData { installCell(name,data:contents) }
        }
        return definitions.count
    }
    @discardableResult func loadTracks(_ data:Data)->Bool {guard let tracks=NativeTrainTracks(data:data) else{return false};self.tracks=tracks;return true}
    func supports(_ model: String) -> Bool { guard let definition=definitions[model] else{return false};return definition.trainConfiguration == nil || tracks != nil }
    func modelOrigin(_ model: String) -> Float? { definitions[model].map { Float($0.configuration.origin) } }
    func modelFlags(_ model:String)->Int {definitions[model]?.configuration.table.modelFlags ?? 0}
    func handlingFlags(_ model:String)->Int {definitions[model]?.configuration.table.flags ?? 0}
    func remoteAudioTop(model:String)->Double? {
        if let value=audioTopCache[model]{return value}
        guard let definition=definitions[model] else{return nil}
        let value=NativeVehicleDynamics.transmissionSnapshot(table:definition.configuration.table).max*50
        audioTopCache[model]=value;return value
    }
    func isCellLoaded(_ name: String) -> Bool { loadedCells.contains(name) }
    func installCell(_ name: String, data: Data) {
        cellData[name] = data
        guard !loadedCells.contains(name), materialClasses.count == 256,
              let mesh = try? SwiftRapierWorld.decodeSCL2(data) else { return }
        if mesh.indices.isEmpty { loadedCells.insert(name); return }
        // Original39943 groups each cell by normalized traction surface and
        // representative sound material, preserving first-use Map order. The
        // raw face material remains available for original `each` queries.
        struct Group { let surface:Int;let material:Int;var faces:[Int] }
        var groups:[Group] = [], lookup:[Int:Int] = [:]
        for face in 0..<(mesh.indices.count/3) {
            let raw = mesh.materials.indices.contains(face) ? Int(mesh.materials[face]) : -1
            let sound = raw == 17 || raw == 18 ? raw : materialClasses.indices.contains(raw) ? materialClasses[raw] : -1
            let rawSurface = mesh.surfaces.indices.contains(face) ? Int(mesh.surfaces[face]) : 2
            let surface = rawSurface <= 5 ? rawSurface : 2, key = 256 * surface + sound
            if let index = lookup[key] { groups[index].faces.append(face) }
            else { lookup[key] = groups.count; groups.append(Group(surface:surface,material:sound,faces:[face])) }
        }
        if let parts=collisionFallbackParts[name] {
            guard parts.allSatisfy({ $0.indexStart+$0.indexCount<=mesh.indices.count }) else { return }
            groups=parts.map { Group(surface:2,material:-1,faces:Array(($0.indexStart/3)..<(($0.indexStart+$0.indexCount)/3))) }
        }
        var installed:[SwiftRapierWorld.ColliderID] = []
        for group in groups {
            var vertices:[SIMD3<Float>] = groups.count == 1 ? mesh.vertices : [],indices:[UInt32] = [],surfaces:[Int32] = [],materials:[Int32] = []
            var remap:[UInt32:UInt32] = [:]
            for face in group.faces {
                let triangle = Array(mesh.indices[face*3..<face*3+3])
                for original in triangle {
                    if groups.count == 1 { indices.append(original) }
                    else {
                        if remap[original] == nil { remap[original] = UInt32(vertices.count);vertices.append(mesh.vertices[Int(original)]) }
                        indices.append(remap[original]!)
                    }
                }
                surfaces.append(Int32(group.surface));materials.append(mesh.materials.indices.contains(face) ? mesh.materials[face] : -1)
            }
            if indices.isEmpty { continue }
            guard let collider = world.addTriangleMesh(.init(vertices:vertices,indices:indices,surfaces:surfaces,materials:materials)) else {
                for id in installed { world.removeCollider(id) };return
            }
            world.setColliderGroups(collider, collision:131071,solver:0xffffffff)
            world.setColliderQueryMetadata(collider,surface:Int32(group.surface),material:Int32(group.material))
            installed.append(collider)
        }
        cells[name] = installed;loadedCells.insert(name)
    }
    func retainCells(_ names: Set<String>) {
        for (name, colliders) in cells where !names.contains(name) { for collider in colliders { world.removeCollider(collider) } }
        cells = cells.filter { names.contains($0.key) };cellData = cellData.filter { names.contains($0.key) };loadedCells.formIntersection(names)
    }

    static func rotation(heading: Float, pitch: Float = 0, roll: Float = 0) -> simd_quatf {
        // Three composes its YXZ quaternion in JS Double precision, then the
        // Rapier boundary rounds its four components once to Float32.
        let y=simd_quatd(angle:-Double(heading),axis:SIMD3(0,1,0))
        let x=simd_quatd(angle:Double(pitch),axis:SIMD3(1,0,0))
        let z=simd_quatd(angle:-Double(roll),axis:SIMD3(0,0,1))
        return simd_quatf(vector:SIMD4<Float>((y*x*z).vector))
    }
    static func modelOffset(origin: Float, heading: Float, pitch: Float = 0, roll: Float = 0) -> SIMD3<Float> {
        SwiftRapierWorld.rapierToGTA(rotation(heading:heading,pitch:pitch,roll:roll).act(SIMD3(0,origin,0)))
    }
    @discardableResult func enter(model: String, modelPosition: SIMD3<Float>, heading: Float, pitch: Float = 0, roll: Float = 0,
                                  bodyPose:NativeUnattendedVehicle.Pose?=nil) -> Bool {
        guard let definition = definitions[model] else { return false }
        let rotation = bodyPose.map{simd_quatf(vector:SIMD4<Float>($0.rotation.vector))} ?? Self.rotation(heading:heading,pitch:pitch,roll:roll)
        let position = bodyPose.map{SIMD3<Float>($0.position)} ?? (SwiftRapierWorld.gtaToRapier(modelPosition) - rotation.act(SIMD3(0,Float(definition.configuration.origin),0)))
        let train:NativeTrainDynamics? = definition.trainConfiguration.flatMap { configuration in tracks.flatMap { NativeTrainDynamics(configuration:configuration,tracks:$0,position:SIMD3<Double>(position),heading:-Double(heading)) } }
        let bike = definition.bikeConfiguration.flatMap { NativeBikeDynamics(configuration: $0) }
        let dynamics = bike == nil && train == nil ? NativeVehicleDynamics(configuration: definition.configuration) : nil
        guard train != nil || bike != nil || dynamics != nil else { return false }
        if let dynamics {
            if let parameters = definition.flightParameters {
                dynamics.flight = NativeFlightDynamics(parameters:parameters,kind:definition.configuration.kind,
                    rearExtent:definition.rearExtent,jets:definition.configuration.table.model == 520,hover:definition.configuration.table.model == 539)
            }
            dynamics.buoyancy = NativeVehicleBuoyancy(table:definition.configuration.table,minimum:definition.buoyancyMinimum,maximum:definition.buoyancyMaximum,parameters:definition.boatParameters)
            dynamics.buoyancy?.waterLevel = { [weak self] point in self?.waterLevel?(point) }
            dynamics.buoyancy?.wave = { [weak self] point in self?.waterWave?(point) ?? .init(height:0,normal:SIMD3(0,1,0)) }
        }
        exit()
        let mass:SwiftRapierWorld.Mass
        if let bike {mass = .init(value:Float(bike.mass),centre:SIMD3<Float>(bike.centre),turnMass:Float(bike.turnMass))}
        else if let dynamics {mass = .init(value:Float(dynamics.mass),centre:SIMD3<Float>(dynamics.centre),turnMass:Float(dynamics.turnMass))}
        else {mass = .init(value:0,turnMass:0)}
        let initialPosition:SIMD3<Float>,initialRotation:simd_quatf,kind:SwiftRapierWorld.BodyKind
        if let train {initialPosition=SIMD3<Float>(train.initial.position);initialRotation=simd_quatf(vector:SIMD4<Float>(train.initial.rotation.vector));kind = .kinematicVelocity}
        else {initialPosition=position;initialRotation=rotation;kind = .dynamic}
        guard let body=world.addBody(kind:kind,position:initialPosition,rotation:initialRotation,mass:mass) else{return false}
        for shape in definition.chassis {
            let collider: SwiftRapierWorld.ColliderID?
            if shape.kind == "sphere" { collider = world.addSphere(radius: shape.radius, body: body, position: shape.centre, friction: shape.friction, restitution: shape.restitution) }
            else { collider = world.addBox(halfExtents: shape.halfExtents, body: body, position: shape.centre, friction: shape.friction, restitution: shape.restitution) }
            guard let collider else { world.removeBody(body); return false }
            world.setColliderGroups(collider, collision: shape.collisionGroups, solver: shape.solverGroups)
            world.setColliderPiece(collider, piece: Int32(shape.piece))
            world.setColliderSurface(collider, surface: 2, material: 63)
            world.setContactForceEvents(collider)
            chassisColliders.insert(collider)
        }
        // Original62540.tp applies rbSetRotation after building the body;
        // its Float quaternion is normalized at this setter boundary.
        world.setBrowserRotation(body,rotation:initialRotation)
        rigid = body; self.dynamics = dynamics; bikeDynamics = bike; trainDynamics = train; self.model = model
        let table = definition.configuration.table
        let damage = NativeVehicleDamageController(world:world,mass:table.mass,collisionDamage:definition.collisionDamage,
            maxX:definition.damageWidth,flags:table.modelFlags,model:table.model,origin:definition.configuration.origin,flight:dynamics?.flight != nil)
        damage.onEvents = { [weak self] events,body in self?.handleDamageEvents(events,body:body) }
        damage.onCollisions = {[weak self] collisions,body in self?.onCollisions?(collisions,body)}
        damage.isOtherVehicle = { [weak self] id in self?.others.colliders.contains(id) == true }
        damage.isRhino = { [weak self] id in self?.others.rhinos.contains(id) == true }
        damageController = damage
        // The native query bridge refreshes body/collider transforms and its
        // query BVH directly; creation must not advance the shared world.
        updatePose()
        return true
    }
    func exit() {
        if let rigid { world.removeBody(rigid) }
        rigid = nil; dynamics = nil; bikeDynamics = nil; trainDynamics = nil; carriages = []; output = nil; accumulator = 0; model = ""; speed = 0
        wheelClocks = [Double](repeating:0,count:4)
        visualWheelSpeed = 0
        forwardSpeed = 0
        chassisColliders.removeAll()
        damageController = nil
    }
    func teleport(modelPosition: SIMD3<Float>, heading: Float) {
        guard let rigid, let definition = definitions[model] else { return }
        let rotation = Self.rotation(heading:heading)
        let position = SwiftRapierWorld.gtaToRapier(modelPosition) - rotation.act(SIMD3(0,Float(definition.configuration.origin),0))
        if let configuration=definition.trainConfiguration,let tracks,
           let train=NativeTrainDynamics(configuration:configuration,tracks:tracks,position:SIMD3<Double>(position),heading:-Double(heading)) {
            trainDynamics=train
            world.setBodyState(.init(position:SIMD3<Float>(train.initial.position),rotation:simd_quatf(vector:SIMD4<Float>(train.initial.rotation.vector))),for:rigid)
        } else {world.setBodyState(.init(position: position, rotation: rotation), for: rigid)}
        accumulator = 0; updatePose()
    }
    func setDamageHinges(_ gta:[Int:SIMD3<Double>]) {
        damageController?.hinges=gta.mapValues{SIMD3($0.x,$0.z,-$0.y)}
    }
    /// Original62540.tt: source damage/shape intersection plus the original
    /// centre-of-mass angular impulse. Rhino432 alone reduces blast damage.
    func applyBlast(centre:SIMD3<Float>) {
        applyBlast(centre:SIMD3<Double>(SwiftRapierWorld.gtaToRapier(centre)),subdued:false,
                   scale:definitions[model]?.configuration.table.model == 432 ? 0.3:1)
    }
    private func applyBlast(centre:SIMD3<Double>,subdued:Bool,scale:Double = 1) {
        guard let rigid,let definition=definitions[model],let damage=damageController,let current=world.bodyState(rigid) else{return}
        let table=definition.configuration.table
        guard let result=NativeVehicleDamage.explosion(body:damage.body(current),minimum:definition.blastMinimum,
            maximum:definition.blastMaximum,mass:table.mass,centre:centre,subdued:subdued) else{return}
        damage.state.inflict(result.damage*scale)
        guard let force=result.force,let point=result.point else{return}
        let q=current.rotation,rotation=simd_quatd(ix:Double(q.imag.x),iy:Double(q.imag.y),iz:Double(q.imag.z),r:Double(q.real))
        let arm=point-rotation.act(SIMD3(table.comX,table.comZ,-table.comY))
        let angular=SIMD3<Double>(current.angularVelocity)+simd_cross(arm,force)/table.turnMass*50
        world.setVelocities(rigid,linear:current.linearVelocity,angular:SIMD3<Float>(angular))
    }
    private func handleDamageEvents(_ events:[NativeVehicleDamage.Event],body:NativeVehicleDamage.Body) {
        if events.contains(where:{$0.type=="blow"}),let rigid,let definition=definitions[model],let damage=damageController,
           !(definition.configuration.kind=="bike" && [481,509,510].contains(definition.configuration.table.model)),
           let current=world.bodyState(rigid) {
            var linear=current.linearVelocity;linear.y=Float(Double(linear.y)+6.5)
            world.setVelocities(rigid,linear:linear,angular:current.angularVelocity)
            let maximum=definition.blastMaximum
            let rightScale=(damage.random()*1.5-0.75)*maximum.x
            let frontScale=(damage.random()*1.5-0.75)*maximum.y
            var point:SIMD3<Double>=body.position
            point += body.right*rightScale;point += body.forward*frontScale
            point.y -= 1.25*maximum.z;applyBlast(centre:point,subdued:true)
        }
        onDamageEvents?(events,body)
    }
    func update(delta: Double, input: NativeVehicleDynamics.Input, currentCell: String) {
        guard let rigid, dynamics != nil || bikeDynamics != nil || trainDynamics != nil, loadedCells.contains(currentCell) else { return }
        accumulator += min(max(0,delta),0.2)
        let fixed = 1.0 / 60
        while accumulator + 1e-12 >= fixed {
            guard let body = world.bodyState(rigid) else { exit(); return }
            if let trainDynamics {
                let wrecked=damageController?.state.wrecked ?? false
                let result=trainDynamics.step(delta:fixed,throttle:wrecked ? 0:input.throttle,handbrake:input.handbrake || wrecked)
                world.setBodyState(.init(position:SIMD3<Float>(result.pose.position),rotation:simd_quatf(vector:SIMD4<Float>(result.pose.rotation.vector)),
                    linearVelocity:SIMD3<Float>(result.linearVelocity),angularVelocity:SIMD3<Float>(result.angularVelocity)),for:rigid)
                world.setBrowserRotation(rigid,rotation:simd_quatf(vector:SIMD4<Float>(result.pose.rotation.vector)))
                if let requested=world.bodyState(rigid) {
                    let q=requested.rotation,rotation=simd_quatd(ix:Double(q.imag.x),iy:Double(q.imag.y),iz:Double(q.imag.z),r:Double(q.real))
                    forwardSpeed = -rotation.conjugate.act(SIMD3<Double>(requested.linearVelocity)).z
                }
                world.step();_ = world.drainContactForceEvents()
                for index in wheelClocks.indices {wheelClocks[index] -= trainDynamics.speed*fixed/0.36}
                accumulator -= fixed;continue
            }
            let rotation = body.rotation
            let state = NativeVehicleDynamics.BodyState(position: SIMD3<Double>(body.position),
                rotation: simd_quatd(ix: Double(rotation.imag.x),iy: Double(rotation.imag.y),iz: Double(rotation.imag.z),r: Double(rotation.real)),
                linearVelocity: SIMD3<Double>(body.linearVelocity), angularVelocity: SIMD3<Double>(body.angularVelocity))
            let cast: (SIMD3<Double>,SIMD3<Double>,Double)->NativeVehicleDynamics.RayHit? = { [world] origin,direction,distance in
                guard let hit = world.raycast(origin: SIMD3<Float>(origin), direction: SIMD3<Float>(direction), distance: Float(distance), excludingBody: rigid) else { return nil }
                return .init(distance: Double(hit.distance), normal: SIMD3<Double>(hit.normal), surface: hit.coarseSurface, material: hit.coarseMaterial)
            }
            let result: NativeVehicleDynamics.Output
            var controls = input
            if let damage = damageController?.state {
                dynamics?.setTyres(damage.wheels);bikeDynamics?.setTyres(damage.wheels)
                if damage.wrecked {controls = .init();controls.handbrake=true;controls.nobody=input.nobody}
            }
            if input.drive != nil {
                if definitions[model]?.configuration.kind=="heli" {controls.drive = .init(throttle:0,steer:0,handbrake:true)}
                else if definitions[model]?.configuration.kind=="plane" {
                    controls.drive = .init(throttle:forwardSpeed>0.5 ? min(0,controls.throttle):0,
                        steer:max(-1,min(1,controls.yaw+(aloft ? 0:controls.steer))),handbrake:controls.handbrake)
                }
            }
            if let bikeDynamics { result = bikeDynamics.step(delta: fixed, input: controls, body: state, raycast: cast) }
            else { result = dynamics!.step(delta: fixed, input: controls, body: state, raycast: cast) }
            output = result
            forwardSpeed = -state.rotation.conjugate.act(SIMD3<Double>(SIMD3<Float>(result.linearVelocity))).z
            if definitions[model]?.configuration.kind == "car" { for front in [true,false] {
                let axle = result.wheels.filter { ($0.index == 0 || $0.index == 2) == front }
                let mean = axle.isEmpty ? 0 : axle.reduce(0) { $0 + $1.spin } / Double(axle.count)
                for wheel in axle { wheelClocks[wheel.index] -= mean * fixed / 0.36 }
            } } else {
                // Original62540 updates visual wheel clocks after reading
                // back the newly requested Float32 body velocity. Aircraft
                // retain/decay their previous wheel speed while airborne.
                let speed = forwardSpeed
                if dynamics?.flight != nil && result.wheels.allSatisfy({$0.counts<=0}) {visualWheelSpeed *= exp(-1.2*fixed)}
                else {visualWheelSpeed=speed}
                let frontRadius=definitions[model]?.bikeConfiguration?.front.radius ?? 0.36
                let rearRadius=definitions[model]?.bikeConfiguration?.rear.radius ?? 0.36
                let rear=bikeDynamics?.rearSpin ?? visualWheelSpeed
                wheelClocks[0] -= visualWheelSpeed*fixed/frontRadius;wheelClocks[2]=wheelClocks[0]
                if !controls.handbrake {wheelClocks[1] -= rear*fixed/rearRadius}
                wheelClocks[3]=wheelClocks[1]
            }
            world.setVelocities(rigid, linear: SIMD3<Float>(result.linearVelocity), angular: SIMD3<Float>(result.angularVelocity))
            world.step()
            let contacts = world.drainContactForceEvents()
            if let current=world.bodyState(rigid) {
                damageController?.step(previous:body,current:current,contacts:contacts,chassis:chassisColliders,delta:fixed)
            }
            onContactForces?(contacts,rigid,fixed)
            accumulator -= fixed
        }
        updatePose()
    }
    private func updatePose() {
        guard let rigid, let state = world.bodyState(rigid), let definition = definitions[model] else { return }
        bodyPosition = SwiftRapierWorld.rapierToGTA(state.position)
        let q=state.rotation,rotation=simd_quatd(ix:Double(q.imag.x),iy:Double(q.imag.y),iz:Double(q.imag.z),r:Double(q.real))
        modelTransform=Self.transform(position:SIMD3<Double>(state.position),rotation:rotation,origin:definition.configuration.origin)
        modelPosition=SIMD3(modelTransform[3].x,modelTransform[3].y,modelTransform[3].z)
        let x=SIMD3(modelTransform[0].x,modelTransform[0].y,modelTransform[0].z)
        let y=SIMD3(modelTransform[1].x,modelTransform[1].y,modelTransform[1].z)
        let z=SIMD3(modelTransform[2].x,modelTransform[2].y,modelTransform[2].z)
        let basis = simd_float3x3(columns: (x,y,z)); orientation = simd_quatf(basis)
        heading = atan2(y.x,y.y); pitch = asin(max(-1,min(1,y.z)))
        roll = atan2(-x.z,z.z)
        speed = simd_dot(state.linearVelocity,state.rotation.act(SIMD3(0,0,-1)))
        if let trainDynamics {
            let configurations=trainDynamics.configuration.carriages.compactMap{definitions[String($0)]?.trainConfiguration}
            let poses=trainDynamics.carriages(body:.init(position:SIMD3<Double>(state.position),rotation:rotation),configurations:configurations)
            carriages=zip(configurations,poses).map { configuration,pose in
                let transform=Self.transform(position:pose.position,rotation:pose.rotation,origin:configuration.origin)
                return Carriage(model:String(configuration.model),transform:transform,position:SIMD3(transform[3].x,transform[3].y,transform[3].z))
            }
        }
    }
    static func transform(position:SIMD3<Double>,rotation:simd_quatd,origin:Double)->simd_float4x4 {
        let x=rotation.imag.x,y=rotation.imag.y,z=rotation.imag.z,w=rotation.real,x2=x+x,y2=y+y,z2=z+z
        let xx=x*x2,xy=x*y2,xz=x*z2,yy=y*y2,yz=y*z2,zz=z*z2,wx=w*x2,wy=w*y2,wz=w*z2
        let right=SIMD3(1-(yy+zz),xy+wz,xz-wy),up=SIMD3(xy-wz,1-(xx+zz),yz+wx),back=SIMD3(xz+wy,yz-wx,1-(xx+yy))
        func gta(_ v:SIMD3<Double>)->SIMD3<Float>{SIMD3(Float(v.x),Float(-v.z),Float(v.y))}
        return simd_float4x4(columns:(SIMD4(gta(right),0),SIMD4(gta(-back),0),SIMD4(gta(up),0),SIMD4(gta(position+up*origin),1)))
    }
}
