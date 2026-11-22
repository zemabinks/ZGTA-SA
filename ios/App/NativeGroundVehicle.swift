import Foundation
import simd

/// Owns the original ground-car solver, native Rapier integration and streamed
/// SCL2 chassis contacts. Unsupported vehicle categories retain their caller's
/// existing path until their separate original solvers have been translated.
final class NativeGroundVehicle {
    /// Optional owner-imported coupling facts. Missing/invalid data disables
    /// coupling rather than inventing an anchor from the visible mesh.
    struct CouplingDefinition {
        struct Working {
            struct Plate {let x:Double,y:Double,z:Double,halfX:Double,halfY:Double,halfZ:Double}
            struct MovingShape {let index:Int,at:SIMD3<Double>}
            let tow:Bool,available:Bool,frame:String?,turn:Double?,lift:Double?,up:Double?,down:Double?
            let plates:[Plate]
            let pivot:SIMD3<Double>?,movingShapes:[MovingShape]
        }
        let id:Int,kind:String,origin:Double,minimum:SIMD3<Double>,maximum:SIMD3<Double>
        let rearAnchor:SIMD3<Double>?,trailerAnchor:SIMD3<Double>?,frontAnchor:SIMD3<Double>
        let targets:Set<Int>,working:Working?
        init?(_ row:[String:Any]) {
            func vector(_ raw:Any?)->SIMD3<Double>? {guard let a=raw as? [Double],a.count==3,a.allSatisfy(\.isFinite) else{return nil};return SIMD3(a[0],a[1],a[2])}
            guard let id=row["id"] as? Int,id>=0,let kind=row["kind"] as? String,
                  let origin=row["origin"] as? Double,origin.isFinite,
                  let low=vector(row["minimum"]),let high=vector(row["maximum"]),
                  low.x<=high.x,low.y<=high.y,low.z<=high.z,let front=vector(row["frontAnchor"]),
                  let targets=row["targets"] as? [Int],targets.count<64,targets.allSatisfy({$0>=0}) else{return nil}
            let rear=vector(row["rearAnchor"]),hook=vector(row["trailerAnchor"])
            for key in ["rearAnchor","trailerAnchor"] where row[key] != nil && !(row[key] is NSNull) {
                guard vector(row[key]) != nil else{return nil}
            }
            self.id=id;self.kind=kind;self.origin=origin;minimum=low;maximum=high;frontAnchor=front;rearAnchor=rear;trailerAnchor=hook;self.targets=Set(targets)
            if let work=row["working"] as? [String:Any] {
                let fields=["turn","lift","up","down"]
                guard fields.allSatisfy({work[$0]==nil || (work[$0] as? Double)?.isFinite==true}) else{return nil}
                let rawPlates=work["plates"] as? [[Double]] ?? []
                guard work["plates"]==nil || work["plates"] is [[Double]],rawPlates.count<=32,
                      rawPlates.allSatisfy({$0.count==6 && $0.allSatisfy(\.isFinite) && $0[3]>0 && $0[4]>0 && $0[5]>0}) else{return nil}
                let plates=rawPlates.map{Working.Plate(x:$0[0],y:$0[1],z:$0[2],halfX:$0[3],halfY:$0[5],halfZ:$0[4])}
                let rawMoving=work["movingShapes"] as? [[String:Any]] ?? []
                guard work["movingShapes"]==nil || work["movingShapes"] is [[String:Any]],rawMoving.count<=4096 else{return nil}
                var moving:[Working.MovingShape]=[];var indices:Set<Int>=[]
                for row in rawMoving {guard let index=row["index"] as? Int,index>=0,indices.insert(index).inserted,let at=vector(row["at"]) else{return nil};moving.append(.init(index:index,at:at))}
                let pivot=vector(work["pivot"])
                guard work["pivot"]==nil || work["pivot"] is NSNull || pivot != nil else{return nil}
                working=Working(tow:work["tow"] as? Bool ?? false,available:work["available"] as? Bool ?? true,frame:work["frame"] as? String,turn:work["turn"] as? Double,lift:work["lift"] as? Double,up:work["up"] as? Double,down:work["down"] as? Double,plates:plates,pivot:pivot,movingShapes:moving)
            } else {working=nil}
        }
    }
    struct CouplingVehicle {
        let id:String,body:SwiftRapierWorld.BodyID?,configuration:CouplingDefinition
        let pose:NativeUnattendedVehicle.Pose
        let health:Int,occupied:Bool,claimed:Bool,dynamic:Bool,hauled:Bool
    }
    struct SupportFrame {
        let id:String,model:String,body:SwiftRapierWorld.BodyID
        let position:SIMD3<Double>,rotation:simd_quatd,origin:Double,kind:String,work:Double
        let configuration:CouplingDefinition?
    }
    func supportFrames()->[SupportFrame]{others.supportFrames(configurations:couplingDefinitions)}
    struct WorkingFrame {
        let value:Int,preciseValue:Double,kitValue:Double,localTowAnchor:SIMD3<Double>?,canAcquireTow:Bool,dropRequested:Bool
    }
    struct WorkingState {
        private(set) var angle=0.0
        private var wasTowed=false,freed=false,dropped=false,drop=false
        mutating func seat(value:Int,tow:Bool) {self=WorkingState();angle=Double(min(2500,max(0,value)))*(tow ? 8:1)}
        mutating func update(delta:Double,pad:Double,towed:Bool,configuration:CouplingDefinition.Working) {
            guard delta.isFinite,delta>0 else{return}
            let ticks=50*delta,control=pad.isFinite ? max(-1,min(1,pad)):0,x=128*control
            if configuration.tow {
                if towed && !wasTowed {angle=max(0,angle-100);freed=false}
                wasTowed=towed
                if abs(x)>10 {
                    if x>0 {angle=max(towed ? 10000:0,angle-2*x*ticks)}
                    else if angle<20000 {angle=min(20000,angle-6*x*ticks)}
                }
                if towed && angle<19900 {freed=true}
                if towed && angle>=20000 && freed && !dropped {drop=true;dropped=true}
                if angle<20000 {dropped=false}
            } else if abs(x)>10 {
                let rate=configuration.lift != nil ? (x>=0 ? -(configuration.down ?? 0):-(configuration.up ?? 0)):10
                angle=min(2500,max(0,angle+control*rate*ticks))
            }
        }
        func frame(_ configuration:CouplingDefinition,towed:Bool)->WorkingFrame? {
            guard let work=configuration.working else{return nil}
            let value=Int(floor(min(2500,max(0,work.tow ? angle/8:angle))+0.5))
            let bar=work.tow ? SIMD3<Double>(0,(1-angle/20000)/2+0.5,1.05-configuration.minimum.y):nil
            return .init(value:value,preciseValue:work.tow ? angle/8:angle,kitValue:Double(value)/1000,localTowAnchor:bar,
                canAcquireTow:work.tow && !towed && angle>=20000 && !dropped,dropRequested:drop)
        }
        mutating func consumeDrop()->Bool {let requested=drop;drop=false;return requested}
    }
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
        let exitGeometry:NativeVehicleExitPlanner.Geometry?
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
            exitGeometry=NativeVehicleExitPlanner.Geometry(row)
            chassis = shapes
        }
    }
    let world: SwiftRapierWorld
    private lazy var others = NativeOtherVehicles(world:world)
    var otherColliders: Set<SwiftRapierWorld.ColliderID> {others.colliders}
    /// Only proven original-other dynamic vehicles. Kinematic neighbors stay
    /// camera-solid; no native material ID is promoted to registry membership.
    var cameraExcludedOtherColliders:Set<SwiftRapierWorld.ColliderID>{others.cameraExcludedColliderIDs}
    var onOtherMove:((String,[String:Any])->Void)?
    var onCouplingStep:((Double)->Void)?
    /// Stages external kinematic world geometry exactly once per native tick,
    /// before existing coupling and unattended-body force owners run.
    var onKinematicStep:((Double)->Void)?
    var onOtherCollidersChanged:(()->Void)?
    func synchronizeOtherVehicles(_ poses:[NativeOtherVehicles.Pose],excluding:String?,near position:SIMD3<Float>,
                                  promoteNear:SIMD3<Float>?=nil,delta:Double=0,wetness:Double=0) {
        others.wetness=wetness
        others.synchronize(poses,excluding:excluding,near:position,promoteNear:promoteNear,delta:delta)
    }
    func otherVehicle(_ id:String)->NativeOtherVehicles.Snapshot?{others.snapshot(id)}
    func shotVehicleColliders(id:String)->Set<UInt64>{others.colliderIDs(id)}
    /// Exclusion is for camera queries only; colliders remain physically live.
    func otherVehicleColliders(id:String)->Set<UInt64>{
        guard let body=others.bodyID(id)else{return []}
        return Set(others.colliders.filter{world.colliderInfo($0)?.body==body})
    }
    func takeOtherVehicle(_ id:String)->NativeOtherVehicles.Snapshot?{others.take(id)}
    /// Explicit disappearance differs from omission in a streamed full list.
    /// It must revoke even a moving/pushed parked hull immediately.
    @discardableResult func removeOtherVehicle(id:String)->Bool {trainLayouts.removeValue(forKey:id);return others.remove(id)}
    func clearOtherVehicles() {others.clear();trainLayouts.removeAll()}
    func shoveOtherVehicle(body:UInt64,direction:SIMD2<Double>,point:SIMD3<Double>,speed:Double){
        others.shove(body:body,direction:direction,point:point,speed:speed)
    }
    func parkCurrentVehicle(id:String,code:String,health:Int,damage:String,work:Int) {
        guard let rigid,let current=world.bodyState(rigid) else{exit();return}
        let position=SwiftRapierWorld.rapierToGTA(current.position)
        let pose=NativeUnattendedVehicle.Pose(position:SIMD3<Double>(current.position),rotation:NativeUnattendedVehicle.quaternion(current.rotation))
        let angle=NativeUnattendedVehicle.euler(pose.rotation),rotor=dynamics?.flight?.turning ?? 0,gear=landingGearUp
        let spin=SIMD2(wheelClocks[0],wheelClocks[1])
        let source=NativeOtherVehicles.Pose(id:id,code:code,position:position,heading:Float(-angle.heading),pitch:Float(angle.pitch),roll:Float(-angle.roll),health:health,damage:damage,work:work)
        exit()
        others.park(source,physicalPose:pose,linear:SIMD3<Double>(current.linearVelocity),angular:SIMD3<Double>(current.angularVelocity),rotor:rotor,gearUp:gear,wheelSpin:spin)
    }
    private var definitions: [String: Definition] = [:]
    private var couplingDefinitions:[String:CouplingDefinition] = [:]
    /// Source working-axis convention: specialDown minus specialUp.
    var workingControl=0.0
    var workingTowed=false
    private var workingState=WorkingState()
    private(set) var workingPlateColliders:Set<SwiftRapierWorld.ColliderID>=[]
    private var workingShapeBody:SwiftRapierWorld.BodyID?,workingShapeValue:Double?
    var hasWorkingControls:Bool {couplingDefinitions[model]?.working?.available == true}
    var workingValue:Int? {workingFrame?.value}
    var workingRenderValue:Double? {workingFrame?.preciseValue}
    var workingFrame:WorkingFrame? {couplingDefinitions[model].flatMap{workingState.frame($0,towed:workingTowed)}}
    func setWorkingValue(_ value:Int) {guard let configuration=couplingDefinitions[model]?.working else{return};workingState.seat(value:value,tow:configuration.tow);updateWorkingPlateColliders();updateWorkingShapeColliders()}
    func consumeWorkingDrop()->Bool {workingState.consumeDrop()}
    @discardableResult func loadCouplingDefinitions(_ data:Data)->Int {
        guard let document=try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              document["version"] as? Int==1,let rows=document["models"] as? [String:[String:Any]] else{return 0}
        let parsed=rows.compactMapValues(CouplingDefinition.init)
        guard parsed.count==rows.count,parsed.allSatisfy({String($0.value.id)==$0.key}) else{return 0}
        couplingDefinitions=parsed;workingShapeBody=nil;workingShapeValue=nil;others.setCouplingDefinitions(parsed);updateWorkingPlateColliders();updateWorkingShapeColliders();return parsed.count
    }
    func ownedCouplingVehicle(id:String)->CouplingVehicle? {
        guard let configuration=couplingDefinitions[model],let rigid,let state=world.bodyState(rigid) else{return nil}
        return .init(id:id,body:rigid,configuration:configuration,
            pose:.init(position:SIMD3<Double>(state.position),rotation:NativeUnattendedVehicle.quaternion(state.rotation)),
            health:Int(damageController?.state.health ?? 1000),occupied:true,claimed:false,dynamic:true,hauled:false)
    }
    func otherCouplingVehicle(id:String)->CouplingVehicle? {others.couplingVehicle(id,definitions:couplingDefinitions)}
    func drawnCouplingVehicles()->[CouplingVehicle] {others.couplingVehicles(definitions:couplingDefinitions)}
    func haulOtherVehicle(id:String)->CouplingVehicle? {guard others.haul(id) else{return nil};return otherCouplingVehicle(id:id)}
    func unhaulOtherVehicle(id:String) {others.unhaul(id)}
    func otherVehicleMovePacket(_ id:String)->[String:Any]? {others.movePacket(id)}
    private func updateWorkingPlateColliders() {
        guard let rigid,let definition=definitions[model],let profile=couplingDefinitions[model],
              let work=profile.working,work.available,!work.plates.isEmpty,let first=definition.chassis.first else{
            for id in workingPlateColliders{world.removeCollider(id)};workingPlateColliders=[];return
        }
        let lift=workingState.angle*(work.lift ?? 0)
        func local(_ plate:CouplingDefinition.Working.Plate)->SIMD3<Float>{SIMD3(Float(plate.x),Float(profile.origin+plate.z+lift),Float(-plate.y))}
        if workingPlateColliders.count != work.plates.count {
            for id in workingPlateColliders{world.removeCollider(id)};workingPlateColliders=[]
            for plate in work.plates {
                guard let collider=world.addBox(halfExtents:SIMD3(Float(plate.halfX),Float(plate.halfY),Float(plate.halfZ)),body:rigid,position:local(plate),friction:1,restitution:0) else{
                    for id in workingPlateColliders{world.removeCollider(id)};workingPlateColliders=[];return
                }
                world.setColliderGroups(collider,collision:first.collisionGroups,solver:first.solverGroups)
                world.setColliderFrictionCombine(collider,.average)
                world.setColliderSurface(collider,surface:2,material:63);workingPlateColliders.insert(collider)
            }
        }
        for (id,plate) in zip(workingPlateColliders.sorted(),work.plates) {_ = world.setColliderTranslationWrtParent(id,position:local(plate))}
    }
    static func workingPosition(_ at:SIMD3<Double>,value:Double,configuration:CouplingDefinition)->SIMD3<Double> {
        guard value.isFinite,let work=configuration.working,work.available,!work.tow else{return at}
        if let lift=work.lift {return at+SIMD3(0,value*lift,0)}
        guard let pivot=work.pivot,let turn=work.turn else{return at}
        return pivot+simd_quatd(angle:value*turn,axis:SIMD3(1,0,0)).act(at-pivot)
    }
    private func updateWorkingShapeColliders() {
        guard let rigid,let definition=definitions[model] else{workingShapeBody=nil;workingShapeValue=nil;return}
        let value=workingRenderValue ?? 0,ids=chassisColliders.sorted(),changedBody=workingShapeBody != rigid
        guard changedBody || workingShapeValue != value else{return}
        if changedBody {for (id,shape) in zip(ids,definition.chassis){_ = world.setColliderTranslationWrtParent(id,position:shape.centre)}}
        if let profile=couplingDefinitions[model],let work=profile.working {
            for shape in work.movingShapes where ids.indices.contains(shape.index) {
                let position=Self.workingPosition(shape.at,value:value,configuration:profile)
                _ = world.setColliderTranslationWrtParent(ids[shape.index],position:SIMD3<Float>(position))
            }
        }
        workingShapeBody=rigid;workingShapeValue=value
    }
    private var audioTopCache:[String:Double] = [:]
    private var cells: [String: [SwiftRapierWorld.ColliderID]] = [:]
    private var cellData: [String: Data] = [:]
    private var materialClasses: [Int] = []
    fileprivate struct CollisionPart: Equatable { let indexStart:Int;let indexCount:Int }
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
    /// The owned bicycle shares the player's existing50Hz stamina budget.
    /// Nil callbacks retain the standalone/unattended solver's original defaults.
    var staminaLeft:(()->Double)?
    var takeStamina:((Double)->Bool)?
    var restStamina:((Double)->Void)?
    private var dynamics: NativeVehicleDynamics?
    private var bikeDynamics: NativeBikeDynamics?
    private var bikeEjection:NativeBikeEjection?
    private var bikeContact=false,bikeOccupied=false
    func takeBikeEjection()->NativeBikeEjection.Event? {bikeEjection?.take()}
    private var trainDynamics: NativeTrainDynamics?
    private var tracks: NativeTrainTracks?
    private var trainLayouts:[String:NativeTrainDynamics] = [:]
    struct Carriage { let model:String;let transform:simd_float4x4;let position:SIMD3<Float> }
    private(set) var carriages:[Carriage] = []
    private var accumulator = 0.0
    private var visualWheelSpeed = 0.0
    private(set) var forwardSpeed = 0.0
    private(set) var output: NativeVehicleDynamics.Output?
    private var wheelClocks = [Double](repeating:0,count:4)
    var wheelAngles:[Float] {wheelClocks.map(Float.init)}
    var wheelAnglesDouble:[Double] {wheelClocks}
    /// Visual axle counters only; body, momentum and solver contacts retain
    /// their existing entry policy. Invalid external counters start at zero.
    func restoreWheelSpin(front:Double,rear:Double) {
        let front=front.isFinite ? front:0,rear=rear.isFinite ? rear:0
        wheelClocks=[front,rear,front,rear]
    }
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
    func cancelPendingInput() {bikeDynamics?.cancelPendingHop();workingControl=0}
    var bikeFullLean: Float { Float(definitions[model]?.bikeConfiguration?.parameters["fullAnimLean"] ?? 0) }
    var rotorTurning: Float { Float(dynamics?.flight?.turning ?? 0) }
    var aircraftNozzle: Float? {
        guard let flight=dynamics?.flight,flight.jets else { return nil }
        return Float(flight.nozzle)
    }
    var landingGearUp: Bool { dynamics?.flight?.gearUp ?? false }
    var onWater: Bool { dynamics?.buoyancy?.onWater ?? false }
    var lostInWater: Bool {
        guard let rigid,let definition=definitions[model],let state=world.bodyState(rigid) else{return false}
        if let afloat=dynamics?.buoyancy{return afloat.lost}
        let point=SIMD3<Double>(state.position)
        guard let level=waterLevel?(point) else{return false}
        return point.y+definition.configuration.origin+0.4<level
    }
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
        if let frame=workingFrame {kit=[frame.kitValue]}
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
        world.beforeStep = {[weak self] delta in self?.onKinematicStep?(delta);self?.onCouplingStep?(delta);self?.others.beforeStep(delta:delta)}
        world.afterStep = {[weak self] in self?.others.afterStep(delta:$0)}
    }

    @discardableResult func loadDefinitions(_ data: Data) -> Int {
        guard let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = document["models"] as? [String: [String: Any]] else { return 0 }
        definitions = rows.compactMapValues { Definition($0) }
        couplingDefinitions=rows.compactMapValues{($0["coupling"] as? [String:Any]).flatMap(CouplingDefinition.init)}
        trainLayouts.removeAll()
        audioTopCache.removeAll()
        others.load(rows.compactMapValues { row in var value=row;value["solverSupported"]=true;return Definition(value) })
        others.setCouplingDefinitions(couplingDefinitions)
        workingShapeBody=nil;workingShapeValue=nil
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
    @discardableResult func loadTracks(_ data:Data)->Bool {guard let tracks=NativeTrainTracks(data:data) else{return false};self.tracks=tracks;trainLayouts.removeAll();return true}
    /// Original91584.wY is a model-layout operation for every locomotive,
    /// independent of whether this player currently owns its physical motor.
    func trainCarriages(id:String,model:String,bodyPosition:SIMD3<Float>,heading:Float,pitch:Float=0,roll:Float=0,
                        bodyPose:NativeUnattendedVehicle.Pose?=nil)->[Carriage] {
        guard let configuration=definitions[model]?.trainConfiguration,!configuration.carriages.isEmpty,let tracks else {
            trainLayouts.removeValue(forKey:id);return []
        }
        let position=bodyPose?.position ?? SIMD3<Double>(SwiftRapierWorld.gtaToRapier(bodyPosition))
        let q=bodyPose?.rotation ?? NativeUnattendedVehicle.quaternion(Self.rotation(heading:heading,pitch:pitch,roll:roll))
        guard position.x.isFinite,position.y.isFinite,position.z.isFinite,q.vector.x.isFinite,q.vector.y.isFinite,
              q.vector.z.isFinite,q.vector.w.isFinite else {return []}
        let layout:NativeTrainDynamics
        if let cached=trainLayouts[id],cached.configuration.model==configuration.model, cached.tracks === tracks {layout=cached}
        else {
            guard let created=NativeTrainDynamics(configuration:configuration,tracks:tracks,position:position,heading:0) else{return []}
            trainLayouts[id]=created;layout=created
        }
        let configurations=configuration.carriages.compactMap{definitions[String($0)]?.trainConfiguration}
        return makeCarriages(configurations:configurations,poses:layout.carriages(body:.init(position:position,rotation:q),configurations:configurations))
    }
    func retainTrainCarriageLayouts(_ ids:Set<String>) {trainLayouts=trainLayouts.filter{ids.contains($0.key)}}
    var trainCarriageLayoutCount:Int {trainLayouts.count}
    private func makeCarriages(configurations:[NativeTrainDynamics.Configuration],poses:[NativeTrainDynamics.Pose])->[Carriage] {
        zip(configurations,poses).map { configuration,pose in
            let transform=Self.transform(position:pose.position,rotation:pose.rotation,origin:configuration.origin)
            return Carriage(model:String(configuration.model),transform:transform,position:SIMD3(transform[3].x,transform[3].y,transform[3].z))
        }
    }
    func supports(_ model: String) -> Bool { guard let definition=definitions[model] else{return false};return definition.trainConfiguration == nil || tracks != nil }
    func exitPosition(wanted:SIMD3<Float>?,seat:SIMD3<Double>?,side:Int,
                      below:(SIMD3<Double>,Double)throws->Double?,
                      along:(SIMD3<Double>,SIMD3<Double>,Double)throws->Double?,
                      fits:(SIMD3<Double>,Double,UInt64)throws->Bool) throws -> SIMD3<Float>? {
        guard let rigid,let state=world.bodyState(rigid),let geometry=definitions[model]?.exitGeometry else{return nil}
        let q=state.rotation
        let feet=try NativeVehicleExitPlanner.place(geometry:geometry,
            pose:.init(position:SIMD3<Double>(state.position),rotation:simd_quatd(ix:Double(q.imag.x),iy:Double(q.imag.y),iz:Double(q.imag.z),r:Double(q.real))),
            seat:seat,side:side,wanted:wanted.map{SIMD3<Double>(SwiftRapierWorld.gtaToRapier($0))},
            below:below,along:along,fits:{try fits($0,$1,rigid)})
        return SwiftRapierWorld.rapierToGTA(SIMD3<Float>(feet))
    }
    func modelOrigin(_ model: String) -> Float? { definitions[model].map { Float($0.configuration.origin) } }
    func modelLength(_ model:String)->Double? {definitions[model]?.length}
    func chassisShapes(_ model:UInt16)->[Definition.Shape]? {definitions[String(model)]?.chassis}
    /// Query another peer's existing chassis without acquiring or parking it.
    func passengerExitPosition(id:String,model:String,wanted:SIMD3<Float>?,seat:SIMD3<Double>?,side:Int,
                              below:(SIMD3<Double>,Double)throws->Double?,
                              along:(SIMD3<Double>,SIMD3<Double>,Double)throws->Double?,
                              fits:(SIMD3<Double>,Double,UInt64)throws->Bool)throws->SIMD3<Float>? {
        guard let body=others.bodyID(id),let state=world.bodyState(body),let geometry=definitions[model]?.exitGeometry else{return nil}
        let q=state.rotation
        let feet=try NativeVehicleExitPlanner.place(geometry:geometry,
            pose:.init(position:SIMD3<Double>(state.position),rotation:simd_quatd(ix:Double(q.imag.x),iy:Double(q.imag.y),iz:Double(q.imag.z),r:Double(q.real))),
            seat:seat,side:side,wanted:wanted.map{SIMD3<Double>(SwiftRapierWorld.gtaToRapier($0))},
            below:below,along:along,fits:{try fits($0,$1,body)})
        return SwiftRapierWorld.rapierToGTA(SIMD3<Float>(feet))
    }
    func modelFlags(_ model:String)->Int {definitions[model]?.configuration.table.modelFlags ?? 0}
    func handlingFlags(_ model:String)->Int {definitions[model]?.configuration.table.flags ?? 0}
    func electric(_ model:String)->Bool {definitions[model]?.configuration.table.electric ?? false}
    func remoteAudioTop(model:String)->Double? {
        if let value=audioTopCache[model]{return value}
        guard let definition=definitions[model] else{return nil}
        let value=NativeVehicleDynamics.transmissionSnapshot(table:definition.configuration.table).max*50
        audioTopCache[model]=value;return value
    }
    func isCellLoaded(_ name: String) -> Bool { loadedCells.contains(name) }
    /// Immutable material/fallback snapshot. CPU preparation may use this on
    /// a serial worker; it never reads or mutates this physics-world owner.
    struct CellConfiguration: Equatable {
        fileprivate let materialClasses:[Int],parts:[CollisionPart]?
        var ready:Bool{materialClasses.count==256}
    }
    struct PreparedCell {
        fileprivate struct Part {let mesh:SwiftRapierWorld.TriangleMesh;let surface:Int,material:Int}
        fileprivate let configuration:CellConfiguration,parts:[Part]
    }
    enum CellPreparationError:Error {case configuration,invalidParts}
    func cellConfiguration(_ name:String)->CellConfiguration {
        .init(materialClasses:materialClasses,parts:collisionFallbackParts[name])
    }
    static func prepareCell(_ data:Data,configuration:CellConfiguration)throws->PreparedCell {
        guard configuration.ready else{throw CellPreparationError.configuration}
        let mesh=try SwiftRapierWorld.decodeSCL2(data)
        // Preserve the existing first-use surface/sound grouping and raw
        // per-face materials; only the CPU execution owner changes.
        struct Group { let surface:Int;let material:Int;var faces:[Int] }
        var groups:[Group] = [], lookup:[Int:Int] = [:]
        for face in 0..<(mesh.indices.count/3) {
            let raw = mesh.materials.indices.contains(face) ? Int(mesh.materials[face]) : -1
            let sound = raw == 17 || raw == 18 ? raw : configuration.materialClasses.indices.contains(raw) ? configuration.materialClasses[raw] : -1
            let rawSurface = mesh.surfaces.indices.contains(face) ? Int(mesh.surfaces[face]) : 2
            let surface = rawSurface <= 5 ? rawSurface : 2, key = 256 * surface + sound
            if let index = lookup[key] { groups[index].faces.append(face) }
            else { lookup[key] = groups.count; groups.append(Group(surface:surface,material:sound,faces:[face])) }
        }
        if let parts=configuration.parts {
            guard parts.allSatisfy({ part in
                let end=part.indexStart.addingReportingOverflow(part.indexCount)
                return !end.overflow && end.partialValue<=mesh.indices.count
            }) else { throw CellPreparationError.invalidParts }
            groups=parts.map { Group(surface:2,material:-1,faces:Array(($0.indexStart/3)..<(($0.indexStart+$0.indexCount)/3))) }
        }
        var prepared:[PreparedCell.Part]=[]
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
            prepared.append(.init(mesh:.init(vertices:vertices,indices:indices,surfaces:surfaces,materials:materials),surface:group.surface,material:group.material))
        }

        return .init(configuration:configuration,parts:prepared)
    }
    /// Keep the old synchronous entry point for existing explicit callers and
    /// deferred metadata rebuilds. Streamed renderer cells use prepared data.
    func installCell(_ name:String,data:Data) {
        cellData[name]=data
        guard !loadedCells.contains(name),let prepared=try? Self.prepareCell(data,configuration:cellConfiguration(name))else{return}
        _=installCell(name,data:data,prepared:prepared)
    }
    func deferCellData(_ name:String,data:Data){cellData[name]=data}
    @discardableResult func installCell(_ name:String,data:Data,prepared:PreparedCell)->Bool {
        guard prepared.configuration==cellConfiguration(name),prepared.configuration.ready else{return false}
        cellData[name]=data
        if loadedCells.contains(name){return true}
        var installed:[SwiftRapierWorld.ColliderID]=[]
        for part in prepared.parts {
            guard let collider=world.addTriangleMesh(part.mesh)else {
                for id in installed{world.removeCollider(id)};return false
            }
            world.setColliderGroups(collider,collision:131071,solver:0xffffffff)
            world.setColliderQueryMetadata(collider,surface:Int32(part.surface),material:Int32(part.material))
            installed.append(collider)
        }
        cells[name]=installed;loadedCells.insert(name);return true
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
        guard let definition = definitions[model],
              modelPosition.x.isFinite,modelPosition.y.isFinite,modelPosition.z.isFinite,
              heading.isFinite,pitch.isFinite,roll.isFinite else { return false }
        let rotation = bodyPose.map{simd_quatf(vector:SIMD4<Float>($0.rotation.vector))} ?? Self.rotation(heading:heading,pitch:pitch,roll:roll)
        let position = bodyPose.map{SIMD3<Float>($0.position)} ?? (SwiftRapierWorld.gtaToRapier(modelPosition) - rotation.act(SIMD3(0,Float(definition.configuration.origin),0)))
        let quaternion=rotation.vector,norm=simd_length_squared(quaternion)
        guard position.x.isFinite,position.y.isFinite,position.z.isFinite,
              quaternion.x.isFinite,quaternion.y.isFinite,quaternion.z.isFinite,quaternion.w.isFinite,
              norm.isFinite,norm>=0.000001 else {return false}
        let train:NativeTrainDynamics? = definition.trainConfiguration.flatMap { configuration in tracks.flatMap { NativeTrainDynamics(configuration:configuration,tracks:$0,position:SIMD3<Double>(position),heading:-Double(heading)) } }
        let bike = definition.bikeConfiguration.flatMap { NativeBikeDynamics(configuration: $0) }
        let dynamics = bike == nil && train == nil ? NativeVehicleDynamics(configuration: definition.configuration) : nil
        guard train != nil || bike != nil || dynamics != nil else { return false }
        if let bike {
            bike.takeBreath = {[weak self] amount in self?.takeStamina?(amount) ?? true}
            bike.restBreath = {[weak self] amount in self?.restStamina?(amount)}
        }
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
        if bikeDynamics != nil {bikeEjection=NativeBikeEjection(model:Int(model) ?? 0,mass:table.mass)}
        damage.onImpact = {[weak self] intensity,way,body,previous in
            guard let self else{return}
            self.bikeEjection?.impact(intensity:intensity,way:way,body:body,previousVelocity:previous,occupied:self.bikeOccupied)
        }
        damage.onCollisions = {[weak self] collisions,body in self?.onCollisions?(collisions,body)}
        damage.isOtherVehicle = { [weak self] id in self?.others.colliders.contains(id) == true }
        damage.isRhino = { [weak self] id in self?.others.rhinos.contains(id) == true }
        damageController = damage
        // The native query bridge refreshes body/collider transforms and its
        // query BVH directly; creation must not advance the shared world.
        updateWorkingPlateColliders()
        updateWorkingShapeColliders()
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
        damageController = nil;bikeEjection=nil;bikeContact=false;bikeOccupied=false
        workingPlateColliders=[]
        workingShapeBody=nil;workingShapeValue=nil
        workingControl=0;workingTowed=false;workingState=WorkingState()
    }
    func teleport(modelPosition: SIMD3<Float>, heading: Float,bodyPose:NativeUnattendedVehicle.Pose?=nil) {
        guard active, definitions[model] != nil,
              modelPosition.x.isFinite, modelPosition.y.isFinite,
              modelPosition.z.isFinite, heading.isFinite else { return }
        // Original62540.place/lift rebuilds the solver through tp. Moving only
        // the rigid body left wheel compression/counts, transmission inertia,
        // steering, flight thrust and cached contact output at the old place.
        // Damage is a separate controller in that source and survives tp.
        let currentModel = model, damage = damageController,work=workingValue
        let fun = dynamics?.fun ?? bikeDynamics?.fun ?? 0
        let manual = dynamics?.manual ?? bikeDynamics?.manual ?? false
        guard enter(model:currentModel,modelPosition:modelPosition,heading:heading,bodyPose:bodyPose) else { return }
        dynamics?.fun = fun; bikeDynamics?.fun = fun
        dynamics?.manual = manual; bikeDynamics?.manual = manual
        damageController = damage
        if let work {setWorkingValue(work)}
        if let damage { dynamics?.setTyres(damage.state.wheels); bikeDynamics?.setTyres(damage.state.wheels) }
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
        guard delta.isFinite, delta > 0, let rigid,
              dynamics != nil || bikeDynamics != nil || trainDynamics != nil,
              loadedCells.contains(currentCell) else { return }
        accumulator += min(max(0,delta),0.2)
        let fixed = 1.0 / 60
        while accumulator + 1e-12 >= fixed {
            guard let body = world.bodyState(rigid) else { exit(); return }
            if let trainDynamics {
                let wrecked=damageController.map{$0.state.wrecked || $0.state.health<=0} ?? false
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
            if let work=couplingDefinitions[model]?.working {
                let alive=damageController.map{!$0.state.wrecked && $0.state.health>0} ?? true
                workingState.update(delta:fixed,pad:alive ? workingControl:0,towed:workingTowed,configuration:work)
                updateWorkingPlateColliders()
                updateWorkingShapeColliders()
            }
            if let bikeDynamics,let staminaLeft {bikeDynamics.breathLeft=staminaLeft()}
            if let damage = damageController?.state {
                dynamics?.setTyres(damage.wheels);bikeDynamics?.setTyres(damage.wheels)
                if damage.wrecked || damage.health<=0 {
                    cancelPendingInput()
                    controls = .init();controls.handbrake=true
                    controls.nobody=input.nobody || damage.health<=0
                }
            }
            if input.drive != nil {
                if definitions[model]?.configuration.kind=="heli" {controls.drive = .init(throttle:0,steer:0,handbrake:true)}
                else if definitions[model]?.configuration.kind=="plane" {
                    controls.drive = .init(throttle:forwardSpeed>0.5 ? min(0,controls.throttle):0,
                        steer:max(-1,min(1,controls.yaw+(aloft ? 0:controls.steer))),handbrake:controls.handbrake)
                }
            }
            let gravity=world.legacyGravity.map(Double.init)
            if let bikeDynamics { result = bikeDynamics.step(delta: fixed, input: controls, body: state,gravity:gravity, raycast: cast) }
            else { result = dynamics!.step(delta: fixed, input: controls, body: state,gravity:gravity ?? 0.008, raycast: cast) }
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
            bikeOccupied = !input.nobody
            bikeEjection?.step(delta:fixed,up:state.rotation.act(SIMD3(0,1,0)),velocity:result.linearVelocity,
                contact:bikeContact,occupied:bikeOccupied)
            world.setVelocities(rigid, linear: SIMD3<Float>(result.linearVelocity), angular: SIMD3<Float>(result.angularVelocity))
            world.step()
            let contacts = world.drainContactForceEvents()
            if let current=world.bodyState(rigid) {
                damageController?.step(previous:body,current:current,contacts:contacts,chassis:chassisColliders,delta:fixed,drowning:dynamics?.buoyancy?.drowning ?? false)
                bikeContact=damageController?.contactSeen ?? false
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
            carriages=makeCarriages(configurations:configurations,poses:poses)
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

/// Driver exit placement. Geometry is imported locally; candidate selection
/// and query ownership are independent native code. Coordinates here are the
/// physics world's Y-up axes; geometry/seat values use the model's GTA axes.
enum NativeVehicleExitPlanner {
    typealias V = SIMD3<Double>
    enum Placement {case ready(SIMD3<Float>?),unavailable}
    enum QueryError:Error {case unavailable}
    struct Geometry {
        struct Sphere {let centre:V,radius:Double}
        struct Box {let minimum:V,maximum:V}
        let origin:Double,height:Double,minimum:V,maximum:V
        let spheres:[Sphere],boxes:[Box]
        init?(_ row:[String:Any]) {
            func vector(_ value:Any?)->V? {
                guard let a=value as? [Double],a.count==3,a.allSatisfy(\.isFinite) else{return nil}
                return V(a[0],a[1],a[2])
            }
            guard let origin=row["origin"] as? Double,origin.isFinite,
                  let height=row["height"] as? Double,height.isFinite,height>0,
                  let bounds=row["bounds"] as? [String:Any],let box=bounds["box"] as? [String:Any],
                  let low=vector(box["min"]),let high=vector(box["max"]),low.x<=high.x,low.y<=high.y,low.z<=high.z else{return nil}
            var spheres:[Sphere]=[],boxes:[Box]=[]
            if let collision=row["collision"] as? [String:Any] {
                for r in collision["spheres"] as? [[String:Any]] ?? [] {
                    guard let centre=vector(r["center"]),let radius=r["radius"] as? Double,radius.isFinite,radius>0 else{return nil}
                    spheres.append(.init(centre:centre,radius:radius))
                }
                for r in collision["boxes"] as? [[String:Any]] ?? [] {
                    guard let a=vector(r["min"]),let b=vector(r["max"]),a.x<=b.x,a.y<=b.y,a.z<=b.z else{return nil}
                    boxes.append(.init(minimum:a,maximum:b))
                }
            }
            if spheres.isEmpty && boxes.isEmpty {
                guard let width=row["width"] as? Double,width.isFinite,width>0,
                      let length=row["length"] as? Double,length.isFinite,length>0 else{return nil}
                let wheels=row["wheels"] as? [[String:Any]] ?? []
                let bottom=0.9*min(0.4,wheels.compactMap{$0["radius"] as? Double}.min() ?? 0.4)
                boxes=[.init(minimum:V(-0.47*width,-0.47*length,bottom-origin),maximum:V(0.47*width,0.47*length,max(bottom+0.4,0.85*height)-origin))]
            }
            self.origin=origin;self.height=height;minimum=low;maximum=high;self.spheres=spheres;self.boxes=boxes
        }
    }
    struct Pose {var position:V,rotation:simd_quatd}
    private struct Candidate {var start:V,direction:V}
    /// A throwing query means streamed geometry is unknown, not empty. The
    /// caller keeps vehicle ownership and retries after those cells arrive.
    static func place(geometry g:Geometry,pose:Pose,seat:V?,side:Int,wanted:V?,aboard:Bool=false,
                      below:(V,Double)throws->Double?,along:(V,V,Double)throws->Double?,
                      fits:(V,Double)throws->Bool) throws -> V {
        func rotate(_ value:V,_ q:simd_quatd)->V {
            let t=2*simd_cross(q.imag,value)
            return value+q.real*t+simd_cross(q.imag,t)
        }
        let inverse=simd_quatd(ix:-pose.rotation.imag.x,iy:-pose.rotation.imag.y,iz:-pose.rotation.imag.z,r:pose.rotation.real)
        func world(_ p:V)->V {pose.position+rotate(V(p.x,g.origin+p.z,-p.y),pose.rotation)}
        func local(_ p:V)->V {let v=rotate(p-pose.position,inverse);return V(v.x,-v.z,v.y-g.origin)}
        func outsideHull(_ feet:V)->Bool {
            for lift in [0.35,0.72,1.08,1.4500000000000002] {
                let p=local(feet+V(0,lift,0))
                for sphere in g.spheres where simd_length(p-sphere.centre)<sphere.radius+0.35+0.04 {return false}
                for box in g.boxes {
                    let nearest=simd_min(box.maximum,simd_max(box.minimum,p))
                    if simd_length(p-nearest)<0.35+0.04 {return false}
                }
            }
            return true
        }
        let middleZ=(g.minimum.z+g.maximum.z)/2
        let seated=seat ?? V(0,(g.minimum.y+g.maximum.y)/2,middleZ)
        let centre=world(V(0,seated.y,middleZ)),door=world(V(seated.x,seated.y,middleZ))
        func reachable(_ feet:V)throws->Bool {
            let vector=feet+V(0,1,0)-door,distance=simd_length(vector)
            if distance<0.5{return true}
            let hit=try along(door,vector/distance,distance)
            return hit == nil || hit!>distance-0.35
        }
        func candidate(_ at:V,_ widening:Double,_ allowAir:Bool)throws->V? {
            let proposed=world(at),origin=V(proposed.x,max(proposed.y,centre.y)+1.2,proposed.z)
            let distance=try below(origin,14),floor=distance.map{origin.y-$0}
            var feet:V
            if let floor,floor>=centre.y-g.height-3 {feet=V(proposed.x,floor,proposed.z)}
            else {guard allowAir else{return nil};feet=proposed-V(0,0.9,0)}
            guard outsideHull(feet),try fits(feet,widening),try reachable(feet) else{return nil}
            return feet
        }
        let airborne=try below(centre,g.height+3)==nil
        let preferred=side<0 ? -1.0:1.0,desired=wanted.map(local)
        let width:Double
        if let desired,(desired.x<0 ? -1.0:desired.x>0 ? 1.0:0)==preferred {width=abs(desired.x)}
        else {width=max(-g.minimum.x,g.maximum.x)+0.45}
        let fore=desired?.y ?? seated.y
        let sides=[Candidate(start:V(preferred*width,fore,seated.z),direction:V(preferred,0,0)),Candidate(start:V(-preferred*width,fore,seated.z),direction:V(-preferred,0,0))]
        var ends=[Candidate(start:V(seated.x,g.maximum.y+0.6,seated.z),direction:V(0,1,0)),Candidate(start:V(seated.x,g.minimum.y-0.6,seated.z),direction:V(0,-1,0))]
        if seated.y-g.minimum.y<g.maximum.y-seated.y {ends.reverse()}
        var raised:[Candidate]=[]
        if abs(rotate(V(1,0,0),pose.rotation).y)>0.6 {
            raised=[Candidate(start:V(seated.x,fore,g.maximum.z+0.45),direction:V(0,0,1)),Candidate(start:V(seated.x,fore,g.minimum.z-0.45),direction:V(0,0,-1))]
        }
        func horizontal(_ c:Candidate)->Bool {abs(rotate(V(c.direction.x,c.direction.z,-c.direction.y),pose.rotation).y)<0.75}
        let lateral=([sides[0]]+raised+[sides[1]]).filter(horizontal)
        let near=[0.0,0.15,0.3,0.45,0.6,0.8,1],far=[1.3,1.6,2.0,2.5,3]
        let routes=lateral.map{($0,near)}+lateral.map{($0,far)}+ends.filter(horizontal).map{($0,near+far)}
        func search(_ widening:Double,_ allowAir:Bool)throws->V? {
            for (path,distances) in routes {for distance in distances {
                if let feet=try candidate(path.start+path.direction*distance,widening,allowAir){return feet}
            }}
            return nil
        }
        func aboveDoor()throws->V? {
            var height=0.0
            while height<=7 {
                let feet=V(door.x,centre.y+height,door.z)
                if outsideHull(feet) {return try fits(feet,0) && reachable(feet) ? feet:nil}
                height += 0.2
            }
            return nil
        }
        func standingAboard()throws->V? {
            guard aboard,let seat else{return nil}
            let origin=world(seat);var lift = -1.1
            while lift<=1.5 {
                let feet=origin+V(0,lift,0)
                if outsideHull(feet) {return try fits(feet,0) ? feet:nil}
                lift += 0.1
            }
            return nil
        }
        if let feet=try standingAboard(){return feet}
        if airborne {
            if let feet=try search(0.2,true) ?? search(0,true) ?? aboveDoor(){return feet}
        } else {
            if let feet=try search(0.2,false) ?? search(0,false) ?? aboveDoor() ?? search(0,true){return feet}
        }
        let distance=try below(door,14)
        return door-V(0,distance ?? 0.9,0)
    }
}
