import Foundation
import simd

/// Query boundary for the public client's on-foot motor. All coordinates use
/// Rapier's Y-up axes; the visual actor's feet are 1.7 m below `position`.
protocol NativeCharacterQueries: AnyObject {
    typealias V = SIMD3<Double>
    var walker: UInt64 { get }
    var probe: UInt64 { get }
    func setEnabled(_ collider: UInt64, _ enabled: Bool)
    func setTranslation(_ collider: UInt64, _ position: V)
    func intersections(center: V, halfHeight: Double, radius: Double,
                       excludingCollider: UInt64?, excludingBody: UInt64?) -> [NativeCharacterCollider]
    func contact(_ first: UInt64, _ second: UInt64, prediction: Double) -> NativeCharacterContact?
    func movement(center: V, desired: V, excludingColliders: Set<UInt64>,
                  excludingBodies: Set<UInt64>) -> NativeCharacterMovement
    func ray(origin: V, distance: Double, groups: UInt32,
             excludingBodies: Set<UInt64>) -> NativeCharacterHit?
    func castBall(origin: V, radius: Double, distance: Double, groups: UInt32,
                  excludingColliders: Set<UInt64>, excludingBodies: Set<UInt64>,
                  requireBody: Bool) -> NativeCharacterHit?
    func project(_ collider: UInt64, point: V) -> V?
}

struct NativeCharacterCollider {
    var id: UInt64
    var body: UInt64?
    var dynamic: Bool
    var translation: SIMD3<Double>
    var material: Int = -1
}
struct NativeCharacterContact {
    var distance: Double
    var normal2: SIMD3<Double>
    var point1: SIMD3<Double>
    var point2: SIMD3<Double>
}
struct NativeCharacterHit {
    var collider: NativeCharacterCollider
    var distance: Double
    var normal: SIMD3<Double>
}
struct NativeCharacterMovement {
    var translation: SIMD3<Double>
    var normals: [SIMD3<Double>]
}

/// Literal state/force translation of archived module 39943.jE. The separate
/// query boundary permits replay against the original JS measurements as well
/// as the native Rust engine, without coupling gameplay to Metal or UIKit.
final class NativeCharacterMotor {
    typealias V = SIMD3<Double>
    struct Press {
        var body: UInt64
        var direction: SIMD2<Double>
        var point: V
        var speed: Double
    }
    private let world: any NativeCharacterQueries
    var otherColliders = Set<UInt64>()
    private var ignoredBodies = Set<UInt64>()
    private var avoidedColliders = Set<UInt64>()
    private var carryingBody: UInt64?
    private var normal = V(0,1,0)
    private var barrier = V.zero
    private var easing: Double = 0
    private var previousEasing: Double = 0
    private var wedgedFrames = 0
    private var current: V = .zero
    private var desired: V = .zero
    private var lastNormals: [V] = []
    private var contactDirection = V.zero
    private var delta: Double = 0
    private(set) var grounded = false
    private(set) var rising: Double = 0
    private(set) var propped = false
    private(set) var pressed: [Press] = []
    private let slope = cos(55 * Double.pi / 180)

    init(world: any NativeCharacterQueries) {
        self.world = world
        world.setEnabled(world.walker, false)
    }
    static func gravity(_ velocity: Double, _ delta: Double) -> Double {
        let value = velocity - 20 * delta
        return value * pow(max(0,1-abs(value)/8750),50*delta)
    }
    func setActive(_ active: Bool) {
        world.setEnabled(world.walker, active)
        resetMotion()
    }
    /// A new walking task must not inherit a prior surface normal, carrying
    /// exclusions or contact event. Continuous streaming pauses use the
    /// narrower clearContactEvents() operation instead, preserving momentum.
    func resetMotion() {
        rising = 0; grounded = false; propped = false
        wedgedFrames = 0; easing = 0; previousEasing = 0; pressed = []
        normal = V(0,1,0); barrier = .zero; carryingBody = nil
        ignoredBodies.removeAll(); avoidedColliders.removeAll()
        current = .zero; desired = .zero; lastNormals.removeAll()
        contactDirection = .zero; delta = 0
    }
    /// These results belong to the most recent actual movement tick. They
    /// cannot be re-published while an external root or absent cells pause it.
    func clearContactEvents() { pressed.removeAll(); propped = false; barrier = .zero }
    func stand() { grounded = true; rising = 0 }
    func eased(_ alpha: Double = 1) -> Double { previousEasing + (easing-previousEasing)*alpha }
    func barred(_ angle: Double) -> Bool {
        grounded && -sin(angle)*barrier.x-cos(angle)*barrier.z < 0
    }
    private func length(_ v: V) -> Double { simd_length(v) }
    private func resized(_ v: V, _ size: Double) -> V { v / (length(v) == 0 ? 1 : length(v)) * size }

    private func contacts(at point: V, carrying: UInt64?) {
        ignoredBodies.removeAll()
        var correction = V.zero
        for collider in world.intersections(center: point, halfHeight: 0.55, radius: 0.35,
                                             excludingCollider: world.walker, excludingBody: nil) {
            guard let body = collider.body, otherColliders.contains(collider.id) else { continue }
            ignoredBodies.insert(body)
            guard body != carrying,
                  let contact = world.contact(world.walker,collider.id,prediction: 0),
                  contact.distance < 0, contact.distance >= -0.15 else { continue }
            var direction = contact.normal2
            if simd_dot(direction,point-collider.translation) < 0 { direction = -direction }
            let inward = simd_dot(desired,direction)
            if inward < 0 { desired += direction * -inward }
            correction += direction * (0.03-contact.distance)
        }
        let smallCenter = point + V(0,0.225,0)
        for collider in world.intersections(center: smallCenter,halfHeight: 0.32500000000000007,radius: 0.31,
                                             excludingCollider: world.walker,excludingBody: nil) {
            if let body = collider.body, !otherColliders.contains(collider.id) { ignoredBodies.insert(body) }
        }
        if length(correction) > 0.2 { correction = resized(correction,0.2) }
        desired += correction
        avoidedColliders.removeAll(); pressed.removeAll()
        var constraints: [(V,Double,UInt64,V)] = []
        for collider in world.intersections(center: point,halfHeight: 0.55,radius: 0.6,
                                             excludingCollider: world.walker,excludingBody: nil) {
            guard let body = collider.body, otherColliders.contains(collider.id),body != carrying,
                  !ignoredBodies.contains(body),
                  let contact = world.contact(world.walker,collider.id,prediction: 0.25),
                  contact.distance > 0 else { continue }
            let direction = contact.point1-contact.point2
            let size = length(direction),horizontal = hypot(direction.x,direction.z)
            guard size >= 1e-5,horizontal >= 1e-5,direction.y <= 0.3*size,direction.y >= -0.9*size else { continue }
            constraints.append((V(direction.x/horizontal,0,direction.z/horizontal),
                                max(0,contact.distance-0.03),body,contact.point2))
            avoidedColliders.insert(collider.id)
            if constraints.count >= 12 { break }
        }
        if delta > 0 {
            for (direction,gap,body,point) in constraints {
                let inward = -simd_dot(desired,direction)
                guard inward-gap > 0 else { continue }
                if let index = pressed.firstIndex(where: { $0.body == body }) {
                    if pressed[index].speed*delta < inward {
                        pressed[index] = Press(body: body,direction: SIMD2(-direction.x,-direction.z),point: point,speed: inward/delta)
                    }
                } else { pressed.append(Press(body: body,direction: SIMD2(-direction.x,-direction.z),point: point,speed: inward/delta)) }
            }
        }
        for _ in 0..<2 {
            for (direction,gap,_,_) in constraints {
                let amount = -simd_dot(desired,direction)-gap
                if amount > 0 { desired += direction*amount }
            }
        }
    }
    @discardableResult
    private func move(_ value: V) -> V {
        let result = world.movement(center: current+V(0,0.225,0),desired: value,
                                   excludingColliders: avoidedColliders.union([world.walker]),
                                   excludingBodies: ignoredBodies)
        lastNormals = result.normals; current += result.translation
        return result.translation
    }
    private func collidedHorizontally() -> Bool {
        contactDirection = .zero
        for n in lastNormals {
            let sign: Double = n.y < 0 ? -1 : 1
            contactDirection.x += n.x*sign; contactDirection.z += n.z*sign
        }
        return length(contactDirection) > 0.15
    }
    @discardableResult
    private func lift(_ value: Double) -> Bool {
        abs(value) < 1e-5 || abs(move(V(0,value,0)).y-value) < 0.002
    }
    private func ground(x: Double,z: Double,height: Double,reach: Double) -> NativeCharacterHit? {
        var excludes = ignoredBodies
        if let carryingBody { excludes.insert(carryingBody) }
        return world.ray(origin: V(x,height+0.8,z),distance: 0.8+reach,groups: 0xffff0041,
                         excludingBodies: excludes)
    }

    /// Input `displacement` is horizontal travel for this fixed step; `jump`
    /// supplies 6.07 for the standard jump, or another positive impulse.
    func step(position: inout V,displacement: V,jump: Double,delta dt: Double,
              held: Bool,verticalOverride: Double? = nil,carrying: UInt64? = nil) {
        guard dt > 0,dt.isFinite,position.x.isFinite,position.y.isFinite,position.z.isFinite,
              displacement.x.isFinite,displacement.y.isFinite,displacement.z.isFinite,
              jump.isFinite,verticalOverride?.isFinite != false else {
            clearContactEvents(); return
        }
        current = position-V(0,0.8,0)
        world.setTranslation(world.walker,current)
        let overridden = verticalOverride != nil
        previousEasing = easing; easing *= exp(-12*dt)
        if abs(easing) < 1e-4 { easing = 0 }
        if let verticalOverride { rising = held && verticalOverride < 0 ? 0 : verticalOverride }
        else if grounded && rising <= 0 { rising = jump > 0 ? jump : 0 }
        else { rising = held ? 0 : Self.gravity(rising,dt) }
        let standing = !overridden && grounded && rising <= 0
        desired = V(displacement.x,standing ? 0 : rising*dt,displacement.z)
        delta = dt; contacts(at: current,carrying: carrying)
        if let carrying { ignoredBodies.insert(carrying) }
        carryingBody = carrying; barrier = .zero; propped = false
        if standing {
            desired.y = 0
            if carrying == nil {
                let bottom = current.y-0.9
                for index in 0..<3 {
                    if index > 0 && hypot(desired.x,desired.z) < 1e-6 { break }
                    guard let hit = ground(x: current.x+(index > 0 ? desired.x : 0),
                                           z: current.z+(index > 0 ? desired.z : 0),height: bottom,reach: 0.4) else {
                        if index > 0 { break }; continue
                    }
                    let up = abs(hit.normal.y),sign: Double = hit.normal.y < 0 ? -1 : 1
                    let x = hit.normal.x*sign,z = hit.normal.z*sign,side = hypot(x,z)
                    if side < 0.001 { if index > 0 { break }; continue }
                    let slippery = hit.collider.material == 17 || hit.collider.material == 18
                    if slippery && index == 0 && side > 0.05 { barrier = V(x/side,0,z/side) }
                    let blocked = slippery ? up < 0.87 : up < slope && index > 0 && bottom+0.8-hit.distance > bottom+0.02
                    if !blocked { if index > 0 { break }; continue }
                    let amount = (index > 0 || !slippery ? 0 : dt)-min(0,(desired.x*x+desired.z*z)/side)
                    if amount <= 0 && index > 0 { break }
                    if index > 1 && !slippery { desired = V(0,desired.y,0) }
                    else { desired.x += x/side*amount; desired.z += z/side*amount }
                }
            }
        }
        let before = current
        var moved = move(desired)
        if standing && abs(moved.y) > 0.001 { current = before; moved = .zero }
        var wall = !standing && rising < 0 && collidedHorizontally()
        if !overridden && rising > 0 && moved.y < rising*dt*0.5 { rising = 0 }
        let bottom = current.y-0.9
        let reach = (standing && carrying == nil ? 0.4 : 0)+0.02+0.001
        var hit = ground(x: current.x,z: current.z,height: bottom,reach: reach)
        if hit == nil && standing && carrying == nil && wedgedFrames == 0 {
            hit = ground(x: current.x+0.02,z: current.z+0.02,height: bottom,reach: reach)
        }
        var landed = false,stepEase: Double = 0
        var separation = hit.map { 0.8-$0.distance+0.02 } ?? -Double.infinity
        var nextNormal = hit.map { $0.normal * ($0.normal.y < 0 ? -1 : 1) } ?? V.zero
        var excludes = ignoredBodies
        if let carrying { excludes.insert(carrying) }
        let castOrigin = V(current.x,bottom+0.8,current.z)
        if let cast = world.castBall(origin: castOrigin,radius: 0.35,distance: 0.45+reach,groups: 0xffff0086,
                                     excludingColliders: avoidedColliders,excludingBodies: excludes,requireBody: true),
           cast.distance > 1e-4,
           let point = world.project(cast.collider.id,point: castOrigin-V(0,cast.distance,0)) {
            let offset = castOrigin-V(0,cast.distance,0)-point
            if simd_length_squared(offset) >= 1e-8 {
                let n = simd_normalize(offset),height = 0.45-cast.distance+0.02
                if height > separation && n.y >= slope { separation = height; nextNormal = n }
            }
        }
        if separation > -Double.infinity {
            let side = hypot(nextNormal.x,nextNormal.z)
            if overridden { if separation > 0 { lift(separation) }; landed = true }
            else if nextNormal.y >= slope {
                if rising <= 0 || simd_dot(desired,nextNormal) <= 0 {
                    if standing {
                        let moving = hypot(moved.x,moved.z) > 1e-6
                        let prior = moving ? -(normal.x*moved.x+normal.z*moved.z)/normal.y : 0
                        let next = moving ? -(nextNormal.x*moved.x+nextNormal.z*moved.z)/nextNormal.y : 0
                        stepEase = separation > max(prior,next) ? separation-max(prior,next) :
                            separation < min(prior,next) ? separation-min(prior,next) : 0
                    } else { stepEase = max(0,current.y+separation-before.y-max(0,rising*dt)) }
                    if lift(separation) || !standing { landed = true }
                    else { current = before; stepEase = 0; landed = true; nextNormal = normal }
                }
            } else if rising <= 0 {
                if standing && separation > 0.02 { current = before }
                else if separation > 0 && side > 0.001 {
                    lift(separation)
                    let amount = min(0.3,separation*nextNormal.y/side)
                    desired = V(nextNormal.x/side*amount,0,nextNormal.z/side*amount)
                    let displaced = move(desired)
                    let down = -(nextNormal.x*displaced.x+nextNormal.z*displaced.z)/nextNormal.y
                    if let floor = ground(x: current.x,z: current.z,height: current.y-0.9,reach: max(0,-down)+0.02+0.001) {
                        lift(0.8-floor.distance+0.02)
                    }
                    rising = max(-8,rising+20*dt*nextNormal.y*nextNormal.y); propped = !standing
                }
                landed = standing && separation > 0.02
            } else if separation > 0 { lift(separation) }
        }
        if landed {
            wedgedFrames = 0
            if !overridden {
                rising = 0; normal = nextNormal
                if abs(stepEase) > 0.01 { easing = min(0.5,max(-0.5,easing-stepEase)) }
            }
        } else if !overridden && !held && carrying == nil && (standing ? wedgedFrames > 0 : rising < 0) {
            var velocity = (current.y-before.y)/dt
            var wedged = length(current-before) < 0.5*dt
            if standing {
                let previous = current
                wedged = move(V(0,-0.05,0)).y > -0.04000000000000001
                if wedged { current = previous; wall = collidedHorizontally() }
                velocity = wedged ? 0 : -0.05/dt
            }
            if velocity > 0.5*rising { rising = max(rising,min(0,velocity)-2); propped = !standing }
            if wedged && wall {
                let previous = current
                desired = resized(V(contactDirection.x,0,contactDirection.z),0.03)
                let displacement = move(desired)
                wedged = hypot(displacement.x,displacement.z) < 0.015
                if wedged { current = previous }
            }
            wedgedFrames = wedged ? wedgedFrames+1 : 0
            if wedgedFrames > 12 { landed = true; rising = 0; normal = V(0,1,0) }
        } else { wedgedFrames = 0 }
        grounded = landed; world.setTranslation(world.walker,current)
        position = current+V(0,0.8,0)
    }

    func fits(_ position: V,widening: Double = 0,excludingBody: UInt64? = nil) -> Bool {
        let colliders = world.intersections(center: position+V(0,1.05,0),halfHeight: 0.55-widening,
                                            radius: 0.35+widening,excludingCollider: world.walker,
                                            excludingBody: excludingBody)
        return !colliders.contains { !$0.dynamic || otherColliders.contains($0.id) }
    }
    func inVehicle(_ position: V) -> Bool {
        world.intersections(center: position+V(0,1.05,0),halfHeight: 0.55,radius: 0.35,
                            excludingCollider: world.walker,excludingBody: nil)
            .contains { otherColliders.contains($0.id) }
    }
}
