import Foundation
import simd

/// Public module 66242 damage, serialization and physical door state. Body
/// vectors use the browser's Y-up frame; move/turn use original /50 units.
final class NativeVehicleDamage {
    typealias V = SIMD3<Double>
    struct Body { var position:V;var right:V;var forward:V;var up:V;var move:V;var turn:V }
    struct Velocity { var move:V;var turn:V }
    struct Door {
        var open:Double;var closed:Double = 0;var direction:Int;var axis:Int
        var angle:Double = 0;var previousAngle:Double = 0;var angularVelocity:Double = 0;var state:Int = 0
    }
    struct Event {
        var type:String;var part:Int? = nil;var kind:String? = nil;var torn:Bool? = nil
        var point:V? = nil;var force:Double? = nil
    }
    struct Decoded { var looks:[Int];var open:[Bool];var lights:[Int];var wheels:[Int] }
    struct Explosion { var damage:Double;var force:V?;var point:V? }
    static func explosion(body:Body,minimum:V,maximum:V,mass:Double,centre:V,subdued:Bool = false,radius:Double = 9,visible:Double = 300) -> Explosion? {
        let distance = simd_length(body.position-centre)
        guard distance < radius else { return nil }
        var result = Explosion(damage:1100*min(1,2*(radius-distance)/radius))
        let relative = centre-body.position
        let local = V(simd_dot(relative,body.right),simd_dot(relative,body.forward),simd_dot(relative,body.up))
        let point = simd_min(maximum,simd_max(minimum,local))
        var direction = point-local,length = simd_length(direction)
        if length < 0.0001 { direction = V(0,0,1);length = 1 }
        direction /= length
        if direction.z >= 0 { if direction.z < 0.2 && direction.z > 0 { direction.z += 0.2 } }
        else { direction.z = -0.2 }
        func world(_ v:V) -> V { body.right*v.x+body.forward*v.y+body.up*v.z }
        let worldPoint = world(point)
        var scale = min(1,2*(radius-simd_length(worldPoint+body.position-centre))/radius)
        if subdued { scale *= 0.2 };scale *= min(1,mass/3000)*visible
        if scale > 0 { result.force = world(direction)*scale;result.point = worldPoint }
        return result
    }
    static let nodes = ["bonnet_dummy","boot_dummy","door_lf_dummy","door_rf_dummy","door_lr_dummy","door_rr_dummy","wing_lf_dummy","wing_rf_dummy","windscreen_dummy","bump_front_dummy","bump_rear_dummy"]
    private static let axes:[V] = [V(1,0,0),V(0,1,0),V(0,0,1),V(-1,0,0),V(0,-1,0),V(0,0,-1)]
    private static let special:[Int:(Double,Int,Int)] = [425:(0.3 * .pi,3,1),476:(0.6 * .pi,3,1),512:(0.6 * .pi,3,1),513:(0.6 * .pi,3,1),520:(0.6 * .pi,3,1),519:(-0.75 * .pi,2,1),553:(-0.4 * .pi,4,2)]
    private let mass:Double,collisionScale:Double,width:Double,flags:Int,model:Int
    private let special:Bool
    private var panels = [Int](repeating:0,count:7)
    private(set) var lights = [Int](repeating:0,count:4)
    private(set) var wheels = [Int](repeating:0,count:4)
    private var doorStates = [Int](repeating:0,count:6)
    private(set) var doors:[Door]
    private(set) var looks = [Int](repeating:0,count:11)
    private(set) var health:Double = 1000
    private(set) var wrecked = false
    var godly = false
    private var fireWarmth:Double = 0,fireTicks:Double = 0,upsideTicks:Double = 0
    private(set) var intensity:Double = 0
    private var contactPiece = 0,contactPoint:V?,contactNormal:V?,contactBuilding = false,contactRhino = false
    var events:[Event] = []
    var burning:Bool { health < 250 && !wrecked }
    init(mass:Double,collisionDamage:Double = 0.5,maxX:Double = 1,flags:Int = 0,model:Int = 0) {
        self.mass = mass;collisionScale = collisionDamage*2000/mass;width = max(0.3,maxX)
        self.flags = flags;self.model = model;special = Self.special[model] != nil
        doors = Self.makeDoors(flags:flags,model:model);resetDoorStates()
    }
    private static func makeDoors(flags:Int,model:Int) -> [Door] {
        func door(_ angle:Double,_ direction:Int,_ axis:Int,_ latch:Int) -> Door { Door(open:angle,direction:direction|latch,axis:axis) }
        let half = Double.pi/2
        var rows = [
            flags&16 != 0 ? door(-0.3 * .pi,4,0,32) : door(0.3 * .pi,1,0,32),
            flags&32 != 0 ? door(-0.4 * .pi,5,0,16) : flags&64 != 0 ? door(0.5 * .pi,2,0,16) : door(-0.3 * .pi,4,0,16),
            door(flags&2 != 0 ? -half : -0.4 * .pi,4,2,16),door(flags&2 != 0 ? half : 0.4 * .pi,4,2,16),
            flags&1 != 0 ? door(-half,0,2,16) : door(-0.4 * .pi,4,2,16),
            flags&1 != 0 ? door(half,3,2,16) : door(0.4 * .pi,4,2,16)]
        if let (angle,direction,axis) = special[model] { rows[2] = door(angle,direction,axis,16) }
        return rows
    }
    private func resetDoorStates() {
        doorStates = [Int](repeating:0,count:6)
        if flags&256 != 0 { for index in 2..<6 { doorStates[index] = 4 } }
        if special { doorStates[2] = 0 }
    }
    private func setLook(_ part:Int?,_ look:Int) {
        guard let part,looks.indices.contains(part),looks[part] != look else { return }
        looks[part] = look;events.append(Event(type:"look",part:part))
    }
    func isOpen(_ part:Int) -> Bool { (0..<6).contains(part) && (doorStates[part] == 1 || doorStates[part] == 3) }
    func letGo(_ door:Int,angle:Double) {
        guard doors.indices.contains(door),doorStates[door] != 4 else { return }
        let old = doorStates[door],closed = abs(angle) < 0.02
        doorStates[door] = closed ? 2 * ((old == 3 || old == 2) ? 1 : 0) : (old == 2 || old == 3 ? 3 : 1)
        doors[door].angle = closed ? 0 : angle;doors[door].previousAngle = closed ? 0 : angle;doors[door].angularVelocity = 0
    }
    private func panelPart(_ panel:Int) -> Int? { [0:6,1:7,4:8,5:9,6:10][panel] }
    private func advancePanel(_ panel:Int,random:() -> Double) -> Bool {
        guard panels.indices.contains(panel) else { return false }
        if panels[panel] == 2 {
            if Int(floor(random()*Double(panel == 4 ? 2 : 8))) == 0 { panels[panel] = 3;return true }
            return false
        }
        if panels[panel] != 3 { panels[panel] += 1;return true };return false
    }
    private func updatePanel(_ panel:Int) {
        guard let part = panelPart(panel) else { return }
        if panels[panel] == 1 || panels[panel] == 2 { setLook(part,1) }
        else if panels[panel] == 3 {
            if looks[part] != 2 { events.append(Event(type:"fly",part:part,kind:"panel")) }
            setLook(part,2)
        }
    }
    private func updateDoor(_ door:Int) {
        switch doorStates[door] {
        case 2:
            setLook(door,1)
            if doors[door].previousAngle != 0 { doors[door].angle = 0;doors[door].previousAngle = 0;doors[door].angularVelocity = 0 }
        case 4:
            if looks[door] != 2 { events.append(Event(type:"fly",part:door,kind:door == 0 ? "bonnet" : door == 1 ? "boot" : "door")) }
            setLook(door,2)
        case 1,3: if door == 0 { doors[door].angularVelocity = 0.2 }
        default:break
        }
    }
    private func warmFire() { if fireWarmth < 225 { fireWarmth = 225;fireTicks = 0 } }
    func record(intensity:Double,piece:Int,point:V?,normal:V?,building:Bool,rhino:Bool = false) {
        guard !godly,intensity > self.intensity else { return }
        self.intensity = intensity;contactPiece = piece;contactPoint = point;contactNormal = normal
        contactBuilding = building;contactRhino = rhino
    }
    private func damageComponent(_ component:Int,force:Double,random:()->Double) {
        let kind:Int,index:Int
        if component <= 4 { kind = 1;index = component-1 }
        else if component == 5 { kind = 3;index = 0 }
        else if component == 6 { kind = 4;index = 1 }
        else if component <= 10 { kind = 2;index = component-5 }
        else if component <= 14 { kind = 5;index = component-11 }
        else { kind = 0;index = component-11 }
        let factor = [2.5,1.25,3.2,1.4,2.5,2.8][kind]
        guard force*factor*(component == 15 ? 0.6 : 1) > 150 else { return }
        switch kind {
        case 0: if advancePanel(index,random:random) { updatePanel(index) }
        case 1: if wheels[index] < 2 { wheels[index] += 1 }
        case 2,3,4:
            var changed = false
            switch doorStates[index] {
            case 0,1:
                doors[index].previousAngle = doors[index].angle;doors[index].angle = 0;doors[index].angularVelocity = 0
                doorStates[index] = 2;changed = true
            case 2:doorStates[index] = 3;changed = true
            case 3:if Int(floor(random()*8)) == 0 { doorStates[index] = 4;changed = true }
            default:break
            }
            if changed { updateDoor(index) }
        case 5:
            lights[index] = 1;if advancePanel(index,random:random) { updatePanel(index) }
        default:break
        }
    }
    func process(body:Body,ticks:Double,random:()->Double = {Double.random(in:0..<1)}) {
        let impact = intensity,piece = contactPiece;intensity = 0
        upsideTicks = body.up.y < -0.5 && simd_length_squared(body.move) < 0.0025 && !wrecked && !godly ? upsideTicks+2*ticks : 0
        if upsideTicks > 1000 && health >= 250 { health = 249;warmFire() }
        if impact > 0 && !wrecked {
            let threshold = mass/1500*25
            if !(contactBuilding && contactNormal.map { simd_dot($0,body.up) > 0.6 } == true) && impact > threshold {
                let speed = simd_length_squared(body.move)
                if speed > 0.0004,let point = contactPoint { events.append(Event(type:"sparks",point:point,force:impact)) }
                if body.up.y > 0 || speed > 0.3 {
                    func hit(_ component:Int) { damageComponent(component,force:4*impact,random:random) }
                    func side() -> Double { contactPoint.map { simd_dot($0-body.position,body.right)/width } ?? 0 }
                    switch piece {
                    case 1:hit(5)
                    case 2:hit(6)
                    case 3:
                        hit(16)
                        let across = side(),rightward = contactNormal.map { simd_dot($0,body.right) } ?? 0
                        if across > 0.7 || (across > 0.5 && rightward < -0.5 && 0.35*mass < impact) { hit(12) }
                        else if across > -0.7 || (across > -0.5 && rightward > 0.5 && 0.35*mass < impact) { hit(11) }
                        if panels[5] != 0 && 0.2*mass < impact { hit(5) }
                        if panels[5] >= 2 && 0.2*mass < impact { hit(15) }
                    case 4:
                        hit(17)
                        if flags&1 != 0 && 0.35*mass < impact {
                            let across = side();if across > 0.1 { hit(10) } else if across < -0.1 { hit(9) }
                        }
                        if panels[6] < 2 { hit(6) }
                    case 5:if !special || model == 425 { hit(7) }
                    case 6:hit(8)
                    case 7:hit(9)
                    case 8:hit(10)
                    case 9:hit(11)
                    case 10:hit(12)
                    case 19:hit(15)
                    default:break
                    }
                }
                let damage = (impact-threshold)*collisionScale*0.6*(contactRhino ? 15 : 1)
                if damage > 0 { let before = health;health -= damage/2;if health <= 0 && before >= 1 { health = 1 } }
            }
            if health < 250 { warmFire() }
        }
        if health < 250 && !wrecked {
            fireTicks += floor(20*ticks)
            if fireTicks > 5000 { events.append(Event(type:"blow")) }
        } else { fireTicks = 0 }
    }
    func swing(body:Body,previous:Velocity,current:Velocity,hinge:(Int)->V?,ticks:Double,intensity:Double,
               random:()->Double = {Double.random(in:0..<1)}) {
        for index in 0..<6 {
            let state = doorStates[index]
            if state == 4 || (index == 1 && flags&128 != 0) { continue }
            let closed = state == 0 || state == 2
            if closed && (intensity <= 100 || index == 0) { continue }
            guard let hinge = hinge(index) else { continue }
            let after = simd_cross(current.turn,hinge)+current.move
            let before = simd_cross(previous.turn,hinge)+previous.move
            var acceleration = after-before
            acceleration.y += ticks*(doors[index].direction&32 != 0 ? 0.0016 : 0.008)
            let components = V(simd_dot(acceleration,body.right),simd_dot(acceleration,body.forward),simd_dot(acceleration,body.up))
            var door = doors[index]
            if closed {
                let turn = simd_cross(components,Self.axes[door.direction&15])[door.axis]
                let threshold = (0.75+0.75*random())*0.1
                let opens = door.open >= door.closed ? turn > threshold : turn < -threshold
                if !opens { continue };doorStates[index] = state == 0 ? 1 : 3
            }
            if index == 0 && door.direction&15 == 1 { door.angularVelocity += 0.05*sin(door.angle+0.1)*simd_dot(body.forward,body.move) }
            var way = Self.axes[door.direction&15]
            let a = sin(door.angle),c = cos(door.angle),u = (door.axis+1)%3,v = (door.axis+2)%3
            let first = a*way[v]-c*way[u],second = a*way[u]+c*way[v]
            way[u] = first;way[v] = second
            let torque = simd_cross(components,way)[door.axis]
            if abs(torque) > 0.001 || abs(door.angularVelocity) > 0.001 { door.angularVelocity += torque }
            door.angularVelocity *= pow(0.97,ticks);door.angularVelocity = min(0.5,max(-0.5,door.angularVelocity))
            door.angle += door.angularVelocity*ticks;door.state = 0
            let positive = door.open >= door.closed
            let pastOpen = positive ? door.angle > door.open : door.angle < door.open
            let pastClosed = positive ? door.angle < door.closed : door.angle > door.closed
            var latched = false
            if pastOpen { door.angularVelocity *= -0.8;door.angle = door.open;door.state = 1 }
            else if pastClosed {
                door.angle = door.closed
                if door.direction&16 != 0 && abs(door.angularVelocity) > 0.1 { door.angularVelocity = 0;door.state = 4;latched = true }
                else { door.angularVelocity *= door.direction&32 != 0 ? -0.9 : -0.4;door.state = 2 }
            }
            doors[index] = door
            if latched { doorStates[index] = 2*(doorStates[index] == 1 ? 0 : 1) }
            if index == 0 && door.state == 1 && simd_dot(body.move,body.forward) > 0.4 {
                doorStates[index] = 4;events.append(Event(type:"fly",part:0,kind:"bonnet",torn:true));setLook(0,2)
            }
        }
    }
    func inflict(_ amount:Double) {
        guard !godly,!wrecked,amount > 0 else { return }
        health = max(0,health-amount);if health < 250 { warmFire() }
    }
    @discardableResult func burst(_ wheel:Int) -> Bool {
        guard !godly,!wrecked,wheels.indices.contains(wheel),wheels[wheel] == 0 else { return false }
        wheels[wheel] = 1;events.append(Event(type:"look"));return true
    }
    func blowUp(random:()->Double = {Double.random(in:0..<1)}) {
        guard !godly,!wrecked else { return }
        wrecked = true;health = 0;fireTicks = 0;wheels[Int(floor(random()*4))] = 2;doorStates = [Int](repeating:4,count:6)
        for _ in 0..<3 { _ = advancePanel(5,random:random);_ = advancePanel(6,random:random) }
        lights = [Int](repeating:0,count:4);panels = [Int](repeating:0,count:7);fireWarmth = 250
        for index in 0..<6 { updateDoor(index) }
        events.append(Event(type:"fly",part:0,kind:"wheel"));wheels[0] = 2
    }
    func fix() {
        health = 1000;fireWarmth = 0;fireTicks = 0;wrecked = false;upsideTicks = 0
        panels = [Int](repeating:0,count:7);resetDoorStates();lights = [Int](repeating:0,count:4);wheels = [Int](repeating:0,count:4)
        doors = Self.makeDoors(flags:flags,model:model)
        for index in looks.indices { setLook(index,0) };intensity = 0
    }
    static func decode(_ text:String) -> Decoded? {
        guard text.utf8.count == 19,text.utf8.allSatisfy({ (48...52).contains($0) }) else { return nil }
        let values = text.utf8.map {Int($0)-48}
        return Decoded(looks:values[0..<11].map {$0 >= 3 ? $0-3 : $0},open:values[0..<11].map {$0 >= 3},
            lights:values[11..<15].map {$0 == 1 ? 1 : 0},wheels:values[15..<19].map {$0 == 2 ? 2 : $0 == 1 ? 1 : 0})
    }
    func load(health:Double,text:String) {
        fix()
        if let decoded = Self.decode(text) {
            for index in looks.indices {
                let look = decoded.looks[index],open = decoded.open[index]
                if index >= 6 {
                    if let panel = [6:0,7:1,8:4,9:5,10:6][index] { panels[panel] = look == 2 ? 3 : look == 1 ? 2 : 0 }
                } else if doorStates[index] != 4 { doorStates[index] = look == 2 ? 4 : look == 1 ? (open ? 3 : 2) : (open ? 1 : 0) }
                setLook(index,look)
            }
            lights = decoded.lights;wheels = decoded.wheels
        }
        self.health = min(1000,max(0,health.isFinite ? health : 1000))
        if self.health < 250 && self.health > 0 { warmFire() }
    }
    func text() -> String {
        let parts = looks.indices.map { looks[$0] != 2 && isOpen($0) ? 3+looks[$0] : looks[$0] }
        return (parts+lights+wheels.map {$0 >= 2 ? 2 : $0 == 1 ? 1 : 0}).map(String.init).joined()
    }
}
