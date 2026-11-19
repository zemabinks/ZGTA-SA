import Foundation
import simd

/// Original module78338 motorcycle forces and module40405 bicycle controls.
/// Four suspension rays represent the two contact patches; these are separate
/// from the four-wheel car solver and retain their original lean/stability law.
final class NativeBikeDynamics {
    typealias V = SIMD3<Double>
    typealias Input = NativeVehicleDynamics.Input
    typealias BodyState = NativeVehicleDynamics.BodyState
    typealias Hit = NativeVehicleDynamics.RayHit
    typealias Output = NativeVehicleDynamics.Output
    struct Hub { var at: V; var radius: Double }
    struct Configuration {
        let table: NativeVehicleDynamics.Table
        let origin: Double
        let front: Hub
        let rear: Hub
        let parameters: [String: Double]
        var pedalled = false
    }
    private final class Wheel {
        let index: Int, radius: Double, spring: Double, length: Double, top: V, start: V
        var compression = 1.0, counts = 0.0, state = 0, tyre = 0
        var point = V.zero, normal = V(0,1,0), surface = 2, material = -1
        var spin = 0.0, road = 0.0
        var front: Bool { index < 2 }
        init(index: Int, hub: Hub, share: Double, configuration: Configuration) {
            self.index = index; radius = hub.radius
            spring = configuration.table.upper - configuration.table.lower; length = spring + radius
            top = V(0,hub.at.y + share * radius,hub.at.z + configuration.table.upper)
            start = V(0,configuration.origin + top.z,-top.y)
        }
    }
    private let configuration: Configuration
    private let table: NativeVehicleDynamics.Table
    private let transmission: NativeVehicleDynamics
    private let wheels: [Wheel]
    let mass: Double, turnMass: Double, centre: V
    private var steerInput = 0.0, leanInput = 0.0, desiredSteer = 0.0, steer = 0.0
    private var gas = 0.0, brake = 0.0, leanAngle = 0.0, reserve = 1.0
    private var heardAccel=0.0,heardBrake=0.0,heardGrounded=0.0,heardClimb=0.0,heardLean=0.0
    private var heardHandbrake=false
    var heard:NativeVehicleDynamics.HeardSnapshot {.init(box:transmission.transmissionSnapshot,gear:transmission.transmissionGear,
        accel:heardAccel,brake:heardBrake,handbrake:heardHandbrake,grounded:heardGrounded,spin:0,climb:heardClimb,bike:true,lean:heardLean)}
    private var states = [0,0], drops = [0.0,0.0], slipping = false, burnout = false
    private var move = V.zero, turn = V.zero, bodyCentre = V.zero
    private var right = V(1,0,0), forward = V(0,0,-1), up = V(0,1,0), stepSize = 1.0
    private var orientation = simd_quatd(ix:0,iy:0,iz:0,r:1)
    private var random: () -> Double
    var fun = 0
    var manual: Bool { get { transmission.manual } set { transmission.manual = newValue } }
    @discardableResult func shift(_ direction: Int) -> String { transmission.shift(direction) }
    var lean: Double { leanAngle + bicycleLean }
    var drop: [Double] { drops }
    var rearSpin: Double { wheels[2].spin * 50 }
    private(set) var pedal = 0
    private(set) var crank = 0.0
    var hop:Double {hopTime>0 ? -1:min(1,hopCharge/25)}
    /// Losing input ownership cancels a pending gesture, rather than releasing
    /// it as a new jump. An already launched hop keeps its timer and momentum.
    func cancelPendingHop() {hopCharge=0}
    private var bicycleLean = 0.0, hopCharge = 0.0, hopTime = 0.0, previouslyPedalling = false, sprintPedal = false
    private var pedalCounter = 0.0, pedalCooldown = 0.0, pedalHeld = -1.0
    var breathLeft = 1.0
    var takeBreath: (Double) -> Bool = { _ in true }
    var restBreath: (Double) -> Void = { _ in }

    init?(configuration: Configuration, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        guard configuration.front.radius > 0, configuration.rear.radius > 0,
              let transmission = NativeVehicleDynamics(configuration: .init(table: configuration.table, origin: configuration.origin, wheels: [])) else { return nil }
        self.configuration = configuration; table = configuration.table; self.transmission = transmission
        mass = table.mass; turnMass = table.turnMass
        centre = V(table.comX,configuration.origin + 0.1,-table.comY); self.random = random
        wheels = [(configuration.front,0.5),(configuration.front,-0.5),(configuration.rear,0.5),(configuration.rear,-0.5)].enumerated().map {
            Wheel(index:$0.offset,hub:$0.element.0,share:$0.element.1,configuration:configuration)
        }
    }
    private func parameter(_ name: String) -> Double { configuration.parameters[name] ?? 0 }
    private static func clamp(_ value: Double,_ low: Double,_ high: Double) -> Double { min(high,max(low,value)) }
    private static func normalized(_ v: V) -> V { let n = simd_length(v); return n > 0 ? v/n : v }
    private func speed(at p: V) -> V { move - simd_cross(p-bodyCentre,turn) }
    private func pushTurn(_ force: V,at p: V) { turn += simd_cross(p-bodyCentre,force)/turnMass }
    private func push(_ force: V,at p: V) { move += force/mass; pushTurn(force,at:p) }
    private func torque(_ axis: V,_ amount: Double,_ arm: V) { turn += simd_cross(arm,axis*amount) }
    private func effectiveMass(_ arm: V,_ direction: V) -> Double { 1/(simd_length_squared(simd_cross(arm,direction))/turnMass+1/mass) }
    private func touching(_ index: Int) -> Bool { wheels[index].counts > 0 || wheels[index+1].counts > 0 }
    private func lowest(_ index: Int) -> Wheel { wheels[index].compression < wheels[index+1].compression ? wheels[index] : wheels[index+1] }
    private func contactPoint(_ index: Int) -> V {
        let first = wheels[index], selected = lowest(index)
        return orientation.act(V(0,first.top.z-selected.compression*first.spring-first.radius,-first.top.y))
    }
    private static func projected(_ v: V,on normal: V) -> V { normalized(v-normal*simd_dot(v,normal)) }
    func setTyres(_ values: [Int]) {
        for wheel in wheels { let index = wheel.front ? 0 : 1; wheel.tyre = values.indices.contains(index) && values[index] == 1 ? 1 : 0 }
    }
    private func tyre(point: V,drive: Double,braking: Double,traction: Double,rear: Bool,
                      onlyAxle: Bool,burst: Bool,along: V,across: V,velocity: V) {
        var side = 0.0, longitudinal = 0.0, drive = drive
        let isBraking = braking != 0
        if isBraking { drive = 0 }
        let powered = drive != 0, reverse = drive < 0, speed = simd_dot(velocity,along), slot = rear ? 1 : 0
        if states[slot] != 0 { slipping = true }; states[slot] = 0
        var limit = traction*stepSize
        if slipping { limit *= table.loss }
        let lateral = onlyAxle ? 0 : simd_dot(velocity,across)
        if lateral != 0 {
            side = -lateral/2
            if burst { side += min(speed,0.12)*(2*random()-1)*0.05 }
        }
        if powered { longitudinal = drive; side = Self.clamp(side,-limit,limit) }
        else if speed != 0 {
            longitudinal = -speed/2
            var braking = braking
            if !isBraking && abs(gas)<0.01 {
                braking = configuration.pedalled ? (abs(longitudinal)<0.05 ? 0.45/(mass+200)*stepSize : 0) : 0.54/(mass+200)*stepSize
            }
            if braking > limit { if abs(speed)>0.005 { states[slot] = 3 } }
            else { longitudinal = Self.clamp(longitudinal,-braking,braking) }
        }
        let squared = side*side+longitudinal*longitudinal
        if squared > limit*limit {
            if states[slot] != 3 { states[slot] = powered && speed<0.1 ? 1 : 2 }
            let magnitude = sqrt(squared), loss = slipping ? 1 : table.loss
            side *= limit*loss/magnitude; longitudinal *= limit*loss/magnitude
        }
        guard side != 0 || longitudinal != 0 else { return }
        let force = along*longitudinal+across*side, magnitude = simd_length(force), direction = Self.normalized(force)
        move += direction*magnitude
        let impulse = direction*(magnitude*effectiveMass(point,direction)), lateralImpulse = simd_dot(impulse,right)
        if !(rear && (isBraking || reverse)) { pushTurn((impulse-right*lateralImpulse)*2,at:point-right*simd_dot(point,right)) }
        pushTurn(right*lateralImpulse,at:forward*simd_dot(point,forward))
    }
    private func pedalControl(step: Double,pressed: Bool,held: Bool) -> Double {
        let hasBreath = pedalCounter>0 || breathLeft>0, elapsed = max(0,step-pedalCooldown)
        pedalCooldown = max(0,pedalCooldown-step)
        pedalHeld = pressed ? 0 : held ? (pedalHeld>=0 ? pedalHeld+step : 0) : -1
        if pressed && hasBreath { pedalCounter = min(10,pedalCounter+4); pedalCooldown = max(0,2-step) }
        else if held && hasBreath { pedalCounter = max(1,pedalCounter-elapsed*0.7) }
        else if pedalCounter>0 { pedalCounter = max(0,pedalCounter-elapsed*0.2) }
        let over = pedalCounter>5
        if over || pedalCounter>0 && hasBreath {
            if takeBreath(step*(over ? 0.4 : 0)) { return 1+(over ? pedalCounter/5-1 : 0) }
            pedalCounter = 0
        }
        return 0
    }
    func step(delta: Double,input: Input,body: BodyState,gravity:Double?=nil,raycast: (V,V,Double)->Hit?) -> Output {
        var drivenInput = input, hopImpulse = 0.0
        if configuration.pedalled {
            let step = 50*delta, throttle = input.throttle, pedalling = throttle>0.05
            let effort = pedalControl(step:step,pressed:pedalling && !previouslyPedalling,held:pedalling)
            previouslyPedalling = pedalling; sprintPedal = effort>1.2 || sprintPedal && effort>1
            if !sprintPedal { restBreath(step*(1-max(0,throttle)/2)/2) }
            if input.hop && hopTime<=0 { hopCharge = min(25,hopCharge+step) }
            else if hopCharge>0 { hopImpulse = min(hopCharge/25,1)+1; hopCharge = 0; hopTime = 0.3 }
            hopTime = max(0,hopTime-delta)
            let hopping = hopCharge>0 || hopTime>0
            let power = hopping || throttle < -0.05 ? 0 : pedalling || effort>0 ? 0.5+0.5*max(0,effort-1) : 0
            pedal = power>0 ? (sprintPedal ? 2 : 1) : 0
            if pedal>0 { crank += (pedal==1 ? 1.1 : 2.2)*delta }
            let angle = crank*Double.pi*2, mountain = table.model==510
            let sway = pedal==2 ? cos(angle)*(mountain ? 0.087 : 0.3) : pedal==1 ? sin(angle)*(mountain ? 0.02 : 0.07) : 0
            bicycleLean += (sway-bicycleLean)*min(1,0.2*step)
            drivenInput.throttle = power>0 ? power : hopping ? 0 : throttle
        }
        let base = stepCore(delta:delta,input:drivenInput,body:body,gravity:gravity ?? 0.008,serverGravity:gravity != nil,raycast:raycast)
        guard hopImpulse != 0 && touching(0) && touching(2) else { return base }
        // The browser bicycle wrapper reads back f32 velocities from Rapier
        // before adding its hop, so preserve that rounding boundary here.
        let linear = V(SIMD3<Float>(base.linearVelocity))+up*(0.06*hopImpulse*50)
        let angular = V(SIMD3<Float>(base.angularVelocity))+simd_cross(forward,up)*(0.01*hopImpulse*50)
        return Output(linearVelocity:linear,angularVelocity:angular,steering:base.steering,rearSteering:0,
            gear:base.gear,gas:base.gas,brake:base.brake,burnout:base.burnout,wheelSpeed:base.wheelSpeed,wheels:base.wheels)
    }
    private func stepCore(delta: Double,input: Input,body: BodyState,gravity:Double,serverGravity:Bool,raycast: (V,V,Double)->Hit?) -> Output {
        stepSize = 50*delta; orientation = body.rotation
        right = orientation.act(V(1,0,0)); up = orientation.act(V(0,1,0)); forward = orientation.act(V(0,0,-1))
        let place = body.position+up*configuration.origin
        move = body.linearVelocity/50; turn = body.angularVelocity/50
        let probability = floor(40*abs(simd_dot(move,forward)))+98
        var bump = false
        for wheel in wheels {
            if wheel.index==0 || wheel.index==2 { bump = wheel.tyre==1 && 100>floor(random()*probability) }
            let start = orientation.act(wheel.start-V(0,configuration.origin,0))+place
            if let hit = raycast(start,-up,wheel.length) {
                wheel.point = start-up*hit.distance-place; wheel.normal = hit.normal; wheel.surface = hit.surface; wheel.material = hit.material
                let radiusShare = 1-wheel.spring/wheel.length
                let fraction = hit.distance/wheel.length+(bump ? 0.2*wheel.radius/wheel.length : 0)
                wheel.compression = min(1,(fraction-radiusShare)/(1-radiusShare))
            } else { wheel.compression = 1 }
        }
        let oldContacts = wheels.filter { $0.counts>0 }.count, oldFront = touching(0), oldRear = touching(2)
        steerInput = Self.clamp(steerInput+(-input.steer-steerInput)*min(1,0.2*stepSize),-1,1)
        leanInput = Self.clamp(leanInput+(input.lean-leanInput)*min(1,0.2*stepSize),-1,1)
        let throttle = Self.clamp(input.throttle,-1,1), oldSpeed = simd_dot(move,forward)
        let accelerate = input.accelerate ?? max(0,throttle), braking = input.brake ?? max(0,-throttle)
        burnout = false
        if let pedals = input.pedals { gas = pedals.x; brake = pedals.y }
        else if abs(oldSpeed)<0.01 && accelerate>150.0/255 && braking>150.0/255 && !configuration.pedalled && !input.riderless {
            burnout = true; gas = accelerate; brake = braking
        } else if abs(oldSpeed)<0.01 || oldSpeed*throttle>=0 { gas = throttle; brake = 0 }
        else { gas = 0; brake = abs(throttle) }
        desiredSteer = table.lock*Double.pi/180*steerInput*abs(steerInput)
        let comShift = parameter(leanInput<0 ? "leanBakCom" : "leanFwdCom")*leanInput
        bodyCentre = orientation.act(V(table.comX,0.1,-(table.comY+comShift)))
        let lowSpeed = min(simd_length(move),0.1)
        if leanInput<0 {
            if brake==0 && !input.handbrake || oldContacts==0 {
                let power = table.model==468 ? 0.7*gas+0.3 : 0.5*gas+0.5
                torque(up,-leanInput*parameter("leanBakForce")*lowSpeed*power*stepSize,forward)
            }
        } else if oldContacts==0 { torque(up,-leanInput*parameter("leanFwdForce")*lowSpeed*stepSize,forward) }
        // Three Quaternion.invert() conjugates its assumed-unit quaternion;
        // normalizing/dividing the f32 body quaternion changes its damping.
        let localTurn = orientation.conjugate.act(turn), nose = forward.y
        var resistance = 1.0, pitchDamping = 0.9995
        if oldFront {
            if !oldRear { resistance = 100; if nose<0 { pitchDamping *= min(0.25*abs(parameter("stoppieAng")-nose),0.075)+0.9 } }
        } else {
            resistance = 100
            if oldRear && nose>0 { pitchDamping -= min(0.2*abs(parameter("wheelieAng")-nose),0.05) }
            else { pitchDamping = 0.98 }
        }
        let localPitch = localTurn.x, localRoll = -localTurn.z
        pitchDamping = pow(pitchDamping/(resistance*localPitch*localPitch+1),stepSize)
        let rollDamping = pow(0.9/(1000*localRoll*localRoll+1),stepSize)
        turn += right*(localPitch*(pitchDamping-1)); turn += forward*(localRoll*(rollDamping-1))
        move.y -= gravity*stepSize
        let drag = fun&2 != 0 ? 0 : table.drag<=0.01 ? table.drag : table.drag/1000/2
        move *= pow(1-simd_length(move)*drag,stepSize); turn *= pow(0.99,stepSize)
        var impulses = [Double](repeating:0,count:4), directions = [V](repeating:-up,count:4), oldPointSpeed = [V](repeating:.zero,count:4)
        for wheel in wheels where wheel.compression<1 {
            var normal = wheel.normal; if simd_dot(directions[wheel.index],normal)>0 { normal = -normal }
            let share = wheel.front ? table.suspBias : 1-table.suspBias
            let force = (1-wheel.compression)*(min(stepSize,3)*mass)*table.springs*share*0.016
            impulses[wheel.index] = force; push(normal*force,at:wheel.point)
        }
        for wheel in wheels where wheel.compression<1 {
            oldPointSpeed[wheel.index] = speed(at:wheel.point)
            if wheel.normal.y>0.35 { directions[wheel.index] = -wheel.normal }
        }
        for wheel in wheels where wheel.compression<1 {
            let direction = directions[wheel.index], old = simd_dot(oldPointSpeed[wheel.index],direction), current = simd_dot(speed(at:wheel.point),direction)
            var change = -Self.clamp(min(stepSize,3)*table.damping,-0.25,0.25)*old
            if change>0 && change+current>0 { change = current>=0 ? 0 : -current }
            else if change<0 && change+current<0 { change = current<=0 ? 0 : -current }
            let force = min(effectiveMass(wheel.point-bodyCentre,direction)*change,0.999*abs(impulses[wheel.index]))
            push(direction*force,at:wheel.point)
        }
        var contacts = 0, rearContact = 0, averageNormal = V.zero
        for wheel in wheels {
            wheel.counts = wheel.compression<1 ? 4 : max(wheel.counts-stepSize,0)
            if wheel.counts>0 { contacts += 1; if !wheel.front { rearContact = 1 }; averageNormal += wheel.normal }
        }
        if contacts>0 { averageNormal /= Double(contacts); if simd_dot(averageNormal,up)<(-0.5) { averageNormal = -averageNormal } }
        else { averageNormal = V(0,1,0) }
        let frontTouch = touching(0), rearTouch = touching(2), frontPoint = contactPoint(0), rearPoint = contactPoint(2)
        let forwardSpeed = simd_dot(move,forward)
        let engine = transmission.stepTransmission(delta:delta,throttle:gas,speed:forwardSpeed,contacts:rearContact,smoothing:false)
        if frontTouch && !rearTouch && nose<parameter("stoppieAng") { brake *= max(0,1-(parameter("stoppieAng")-nose)/0.15) }
        let brakeForce = transmission.transmissionBrake*brake*stepSize, frontBrake = 2*table.brakeBias, rearBrake = 2*(1-table.brakeBias)
        let frontGrip = 2*table.bias, traction = table.traction/250*0.25
        if abs(move.x)<0.01 && abs(move.z)<0.01 && desiredSteer==0 { steer *= pow(0.96,stepSize) }
        else {
            var share = 1.0
            if forwardSpeed>0.01 && wheels[0].counts>0 && wheels[1].counts>0 {
                var limit = 4*NativeVehicleDynamics.surfaceTraction[2]*parameter("speedSteer")*traction
                let surface = lowest(2).surface
                if surface==3 || surface==4 { limit *= parameter("slipSteer") }
                share = asin(min(limit/(forwardSpeed*forwardSpeed),1))/(table.lock*Double.pi/180)
                if desiredSteer<0 && leanAngle<0 || desiredSteer>0 && leanAngle>0 { share *= 2 }
                share = min(share,1)
            }
            steer = desiredSteer*share
        }
        let beforeTyres = move; slipping = false
        func grip(_ wheel: Wheel) -> Double {
            let surface = wheel.surface
            let base = NativeVehicleDynamics.surfaceTraction.indices.contains(surface) ? NativeVehicleDynamics.surfaceTraction[surface] : NativeVehicleDynamics.surfaceTraction[2]
            return base*(input.wetness>0 ? 1+NativeVehicleDynamics.wetCoefficient(material:wheel.material,surface:surface)*input.wetness : 1)
        }
        func frontTyre() {
            guard frontTouch else { return }
            let wheel = lowest(0), along = Self.projected(forward*cos(steer)-right*sin(steer),on:wheel.normal)
            let across = Self.normalized(simd_cross(along,wheel.normal))
            tyre(point:frontPoint,drive:0,braking:brakeForce*frontBrake,traction:grip(wheel)*traction*frontGrip*(wheel.tyre==1 ? 0.4 : 1),
                rear:false,onlyAxle:!rearTouch,burst:wheel.tyre==1,along:along,across:across,velocity:speed(at:frontPoint))
        }
        let frontLast = table.flags&8388608 != 0
        if !frontLast { frontTyre() }
        if rearTouch {
            let wheel = lowest(2), along = Self.projected(forward,on:wheel.normal), across = Self.normalized(simd_cross(along,wheel.normal))
            var braking = brakeForce, share = 1.0, burnoutShare = 0.0
            if input.handbrake { braking = 20000; reserve = 1 }
            else if burnout { braking = 0; share = 0; burnoutShare = 1 }
            else if reserve<1 && gas>0.75 { share = reserve; burnoutShare = 1-reserve }
            if burnoutShare != 0 { pushTurn(rearPoint*stepSize,at:right*(-0.0007*burnoutShare*turnMass*desiredSteer)) }
            tyre(point:rearPoint,drive:engine,braking:braking*rearBrake,traction:grip(wheel)*traction*(2-frontGrip)*(wheel.tyre==1 ? 0.4 : 1)*share,
                rear:true,onlyAxle:false,burst:wheel.tyre==1,along:along,across:across,velocity:speed(at:rearPoint))
        }
        if burnout && states[1]==1 { reserve = max(0,reserve-0.002*stepSize) }
        else if reserve<1 { reserve = min(1,reserve+0.005*stepSize) }
        if frontLast { frontTyre() }
        if fun&2 != 0 && gas>0 && rearContact>0 && forwardSpeed>=0 && 50*forwardSpeed<150 { move += forward*transmission.boostForce(throttle:gas,contacts:rearContact,delta:delta) }
        if gas<0 && states[1]==1 { states[1] = 0 }
        for wheel in wheels { wheel.state = states[wheel.front ? 0 : 1] }
        let road = rearTouch ? simd_dot(speed(at:rearPoint),forward) : 0
        wheels[2].road = road
        if rearTouch && states[1]==1 && gas>0.05 {
            let target = max(abs(road),abs(transmission.transmissionMaximum)*min(1,gas))
            wheels[2].spin += (target-wheels[2].spin)*(1-pow(0.92,stepSize))
        } else { wheels[2].spin = road }
        heardAccel=input.pedals != nil ? max(0,gas):accelerate;heardBrake=input.pedals != nil ? brake:braking
        heardHandbrake=input.handbrake;heardGrounded=Double(rearContact);heardClimb=50*move.y;heardLean=leanAngle
        let leanRight = Self.normalized(simd_cross(forward,averageNormal))
        var desiredLean = contacts==0 ? -(0.008*(0.5*(desiredSteer/(table.lock*Double.pi/180))))*stepSize : simd_dot(move-beforeTyres,leanRight)
        let maximumLean = parameter("maxLean")*(wheels[0].tyre==1 ? 0.4 : 1)
        desiredLean = Self.clamp(desiredLean/(0.008*max(stepSize,0.01)),-maximumLean,maximumLean)
        let leanDecay = pow(parameter("desLean"),stepSize)
        leanAngle = asin(desiredLean)*(1-leanDecay)+leanAngle*leanDecay
        for (slot,index) in [0,2].enumerated() {
            let wheel = lowest(index), hub = slot==0 ? configuration.front : configuration.rear
            let wanted = wheel.top.z-max(0,min(1,wheel.compression))*wheel.spring-hub.at.z
            drops[slot] += (wanted-drops[slot])*min(1,0.75*stepSize)
        }
        // A small custom-gravity increment is not evidence of rest. Require
        // actual supporting suspension and downward gravity in this profile;
        // otherwise a stationary low-gravity bike never begins falling.
        // Nil retains the existing browser profile's exact stabilization law.
        let mayRest = !serverGravity || (gravity>=0 && wheels.contains{$0.compression<1})
        if mayRest && engine==0 && brakeForce==0 && abs(move.x)<0.005 && abs(move.y)<0.005 && abs(move.z)<0.005 {
            move = .zero; turn -= up*simd_dot(turn,up)
        }
        if !input.riderless { torque(up,-0.07*Self.clamp(simd_dot(right,averageNormal),-1,1)*stepSize,right) }
        func balance(_ target: Double,_ low: Double,_ lower: Double,_ stability: Double,_ steeringShare: Double) {
            var difference = target-forward.y
            if difference>0.15 { difference = max(0.3-difference,0) }
            else if difference<low { difference = min(lower-difference,0) }
            torque(up,0.5*stepSize*stability*min(simd_length(move),0.1)*difference,forward)
            torque(right,0.5*steeringShare*stepSize*steer*parameter("wheelieSteer"),forward)
        }
        let frontAir = wheels[0].counts==0 && wheels[1].counts==0, rearAir = wheels[2].counts==0 && wheels[3].counts==0
        if frontAir && !rearAir && forward.y>0 { balance(parameter("wheelieAng"),-0.08,-0.14,parameter("wheelieStab"),1) }
        else if rearAir && !frontAir && forward.y<0 { balance(parameter("stoppieAng"),-0.15,-0.3,parameter("stoppieStab"),min(5*simd_length(move),1)) }
        return Output(linearVelocity:move*50,angularVelocity:turn*50,steering:steer,rearSteering:0,gear:transmission.transmissionGear,
            gas:gas,brake:brake,burnout:burnout,wheelSpeed:abs(wheels[2].spin)*50,
            wheels:wheels.map { .init(index:$0.index,compression:$0.compression,offset:table.lower,counts:$0.counts,state:$0.state,spin:$0.spin*50,point:$0.point,normal:$0.normal,tyre:$0.tyre,surface:$0.surface) })
    }
}
