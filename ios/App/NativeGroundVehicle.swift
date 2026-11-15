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
        let flightParameters: NativeFlightDynamics.Parameters?
        let boatParameters: NativeVehicleBuoyancy.Parameters?
        let buoyancyMinimum: SIMD3<Double>
        let buoyancyMaximum: SIMD3<Double>
        let rearExtent: Double
        let collisionDamage: Double
        let damageWidth: Double
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
            collisionDamage = (values["collisionDamage"] as? Double) ?? 0.5
            eye = vector(row["driverEye"]).map { SIMD3<Float>($0) }
            let collisionBox = (row["collision"] as? [String: Any])?["box"] as? [String: Any]
            buoyancyMinimum = vector(collisionBox?["min"]) ?? low
            buoyancyMaximum = vector(collisionBox?["max"]) ?? high
            flightParameters = (row["flying"] as? [String: Any]).flatMap { NativeFlightDynamics.Parameters($0) }
            boatParameters = (row["boat"] as? [String: Any]).flatMap { NativeVehicleBuoyancy.Parameters($0) }
            configuration = .init(table: .init(model: id, values: values), origin: origin, wheels: wheels,
                kind: row["kind"] as? String ?? "car")
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
    func synchronizeOtherVehicles(_ poses:[NativeOtherVehicles.Pose],excluding:String?,near position:SIMD3<Float>) {
        others.synchronize(poses,excluding:excluding,near:position)
    }
    private var definitions: [String: Definition] = [:]
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
    /// Original Rapier Y-up surface-query boundary, separated base/wave parts.
    var waterLevel: ((SIMD3<Double>) -> Double?)?
    var waterWave: ((SIMD3<Double>) -> NativeVehicleBuoyancy.Wave)?
    private var dynamics: NativeVehicleDynamics?
    private var bikeDynamics: NativeBikeDynamics?
    private var accumulator = 0.0
    private(set) var output: NativeVehicleDynamics.Output?
    private(set) var wheelAngles = [Float](repeating: 0, count: 4)
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
    var bikeLean: Float { Float(bikeDynamics?.lean ?? 0) }
    var bikeDrop: [Float] { bikeDynamics?.drop.map(Float.init) ?? [] }
    var bicyclePedal: Int { bikeDynamics?.pedal ?? 0 }
    var bicycleCrank: Float { Float(bikeDynamics?.crank ?? 0) }
    var rotorTurning: Float { Float(dynamics?.flight?.turning ?? 0) }
    var aircraftNozzle: Float? {
        guard let flight=dynamics?.flight,flight.jets else { return nil }
        return Float(flight.nozzle)
    }
    var landingGearUp: Bool { dynamics?.flight?.gearUp ?? false }
    var onWater: Bool { dynamics?.buoyancy?.onWater ?? false }
    var lostInWater: Bool { dynamics?.buoyancy?.lost ?? false }
    func setLandingGear(_ raised: Bool) { dynamics?.flight?.setGear(raised) }
    var cameraFrame: CameraFrame? {
        guard let rigid, let body = world.bodyState(rigid), let definition = definitions[model] else { return nil }
        return CameraFrame(position:modelPosition,forward:orientation.act(SIMD3(0,1,0)),right:orientation.act(SIMD3(1,0,0)),up:orientation.act(SIMD3(0,0,1)),
            moveSpeed:SwiftRapierWorld.rapierToGTA(body.linearVelocity)/50,turnSpeed:SwiftRapierWorld.rapierToGTA(body.angularVelocity)/50,
            wheels:output?.wheels.filter { $0.counts > 0 }.count ?? 0,maxX:definition.bounds.maxX,minY:definition.bounds.minY,maxZ:definition.bounds.maxZ,
            minimum:definition.bounds.minimum,maximum:definition.bounds.maximum,heightAboveRoad:Float(definition.configuration.origin),eye:definition.eye)
    }

    init?() {
        guard let world = SwiftRapierWorld(gravity: SIMD3(0,-18,0)) else { return nil }
        world.enableArchivedStepping()
        if let seabed = world.addBox(halfExtents: SIMD3(150,1,150), position: SIMD3(0,-71,0)) {
            world.setColliderGroups(seabed, collision: 131071, solver: 0xffffffff)
        }
        self.world = world
    }

    @discardableResult func loadDefinitions(_ data: Data) -> Int {
        guard let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = document["models"] as? [String: [String: Any]] else { return 0 }
        definitions = rows.compactMapValues { Definition($0) }
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
    func supports(_ model: String) -> Bool { definitions[model] != nil }
    func modelOrigin(_ model: String) -> Float? { definitions[model].map { Float($0.configuration.origin) } }
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
    @discardableResult func enter(model: String, modelPosition: SIMD3<Float>, heading: Float, pitch: Float = 0, roll: Float = 0) -> Bool {
        guard let definition = definitions[model] else { return false }
        let bike = definition.bikeConfiguration.flatMap { NativeBikeDynamics(configuration: $0) }
        let dynamics = bike == nil ? NativeVehicleDynamics(configuration: definition.configuration) : nil
        guard bike != nil || dynamics != nil else { return false }
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
        let rotation = Self.rotation(heading:heading,pitch:pitch,roll:roll)
        let position = SwiftRapierWorld.gtaToRapier(modelPosition) - rotation.act(SIMD3(0,Float(definition.configuration.origin),0))
        let mass = SwiftRapierWorld.Mass(value: Float(bike?.mass ?? dynamics!.mass),
            centre: SIMD3<Float>(bike?.centre ?? dynamics!.centre), turnMass: Float(bike?.turnMass ?? dynamics!.turnMass))
        guard let body = world.addBody(position: position, rotation: rotation, mass: mass) else { return false }
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
        rigid = body; self.dynamics = dynamics; bikeDynamics = bike; self.model = model
        let table = definition.configuration.table
        let damage = NativeVehicleDamageController(world:world,mass:table.mass,collisionDamage:definition.collisionDamage,
            maxX:definition.damageWidth,flags:table.modelFlags,model:table.model,origin:definition.configuration.origin,flight:dynamics?.flight != nil)
        damage.onEvents = { [weak self] events,body in self?.onDamageEvents?(events,body) }
        damage.isOtherVehicle = { [weak self] id in self?.others.colliders.contains(id) == true }
        damage.isRhino = { [weak self] id in self?.others.rhinos.contains(id) == true }
        damageController = damage
        // Update the broad phase once before the original solver casts wheels.
        // The initial stationary body has gravity disabled, matching the browser.
        world.step(); updatePose()
        return true
    }
    func exit() {
        if let rigid { world.removeBody(rigid) }
        rigid = nil; dynamics = nil; bikeDynamics = nil; output = nil; accumulator = 0; model = ""; speed = 0
        wheelAngles = [Float](repeating: 0, count: 4)
        chassisColliders.removeAll()
        damageController = nil
    }
    func teleport(modelPosition: SIMD3<Float>, heading: Float) {
        guard let rigid, let definition = definitions[model] else { return }
        let rotation = simd_quatf(angle: -heading, axis: SIMD3(0,1,0))
        let position = SwiftRapierWorld.gtaToRapier(modelPosition) - rotation.act(SIMD3(0,Float(definition.configuration.origin),0))
        world.setBodyState(.init(position: position, rotation: rotation), for: rigid)
        accumulator = 0; updatePose()
    }
    func update(delta: Double, input: NativeVehicleDynamics.Input, currentCell: String) {
        guard let rigid, dynamics != nil || bikeDynamics != nil, loadedCells.contains(currentCell) else { return }
        accumulator += min(max(0,delta),0.2)
        let fixed = 1.0 / 60
        while accumulator + 1e-12 >= fixed {
            guard let body = world.bodyState(rigid) else { exit(); return }
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
                controls.nobody = controls.nobody || damage.wrecked
            }
            if let bikeDynamics { result = bikeDynamics.step(delta: fixed, input: controls, body: state, raycast: cast) }
            else { result = dynamics!.step(delta: fixed, input: controls, body: state, raycast: cast) }
            output = result
            if bikeDynamics != nil, let specification = definitions[model]?.bikeConfiguration {
                let forward = state.rotation.act(SIMD3(0,0,-1))
                let front = simd_dot(state.linearVelocity,forward)
                let rear = bikeDynamics?.rearSpin ?? front
                wheelAngles[0] -= Float(front*fixed/specification.front.radius)
                wheelAngles[1] = wheelAngles[0]
                wheelAngles[2] -= Float(rear*fixed/specification.rear.radius)
                wheelAngles[3] = wheelAngles[2]
            } else { for front in [true,false] {
                let axle = result.wheels.filter { ($0.index == 0 || $0.index == 2) == front }
                let mean = axle.isEmpty ? 0 : axle.reduce(0) { $0 + $1.spin } / Double(axle.count)
                for wheel in axle { wheelAngles[wheel.index] -= Float(mean * fixed / 0.36) }
            } }
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
        modelPosition = SwiftRapierWorld.rapierToGTA(state.position + state.rotation.act(SIMD3(0,Float(definition.configuration.origin),0)))
        func rotated(_ point: SIMD3<Float>) -> SIMD3<Float> { SwiftRapierWorld.rapierToGTA(state.rotation.act(SwiftRapierWorld.gtaToRapier(point))) }
        let x = rotated(SIMD3(1,0,0)), y = rotated(SIMD3(0,1,0)), z = rotated(SIMD3(0,0,1))
        let basis = simd_float3x3(columns: (x,y,z)); orientation = simd_quatf(basis)
        modelTransform = simd_float4x4(columns: (SIMD4(x,0),SIMD4(y,0),SIMD4(z,0),SIMD4(modelPosition,1)))
        heading = atan2(y.x,y.y); pitch = asin(max(-1,min(1,y.z)))
        roll = atan2(-x.z,z.z)
        speed = simd_dot(state.linearVelocity,state.rotation.act(SIMD3(0,0,-1)))
    }
}
