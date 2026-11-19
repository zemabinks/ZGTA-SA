import Foundation
import simd

private typealias Row = [String:Any]
private func vector(_ raw: Any) -> SIMD3<Double> {
    let row = raw as! [Double]; return SIMD3(row[0],row[1],row[2])
}
private final class Replay: NativeCharacterQueries {
    let walker: UInt64
    let probe: UInt64
    var rows: [String:[Row]] = [:]
    var cursors: [String:Int] = [:]
    var label = ""
    var comparisons = 0
    var maximumError = 0.0
    init(_ scenario: Row) { walker = UInt64(scenario["walker"] as! Int); probe = UInt64(scenario["probe"] as! Int) }
    func begin(_ frame: Row,_ label: String) {
        rows = frame["queries"] as! [String:[Row]]; cursors = [:]; self.label = label
    }
    func finish() { for (key,value) in rows { precondition(cursors[key,default:0] == value.count,"\(label) unconsumed \(key)") } }
    func next(_ name: String) -> Row {
        let index = cursors[name,default:0],values = rows[name] ?? []
        precondition(index < values.count,"\(label) extra \(name) #\(index)")
        cursors[name] = index+1;return values[index]
    }
    func check(_ actual: Double,_ expected: Double,_ detail: String,tolerance: Double = 2e-9) {
        comparisons += 1; maximumError = max(maximumError,abs(actual-expected))
        precondition(actual.isFinite && abs(actual-expected) <= tolerance,
                     "\(label) \(detail): \(actual) expected \(expected)")
    }
    func check(_ actual: V,_ raw: Any,_ detail: String,tolerance: Double = 2e-9) {
        let expected = vector(raw)
        for axis in 0..<3 { check(actual[axis],expected[axis],detail+"[\(axis)]",tolerance:tolerance) }
    }
    func collider(_ row: Row) -> NativeCharacterCollider {
        .init(id: UInt64(row["id"] as! Int),body:(row["body"] as? Int).map(UInt64.init),
              dynamic:row["dynamic"] as! Bool,translation:vector(row["translation"]!),material:row["material"] as! Int)
    }
    func hit(_ raw: Any?) -> NativeCharacterHit? {
        guard let row = raw as? Row else { return nil }
        return .init(collider:collider(row["collider"] as! Row),distance:row["distance"] as! Double,normal:vector(row["normal"]!))
    }
    func setEnabled(_ collider: UInt64,_ enabled: Bool) {}
    func setTranslation(_ collider: UInt64,_ position: V) {}
    func intersections(center: V,halfHeight: Double,radius: Double,excludingCollider: UInt64?,excludingBody: UInt64?) -> [NativeCharacterCollider] {
        let row = next("intersections")
        check(center,row["center"]!,"intersection center")
        check(halfHeight,row["halfHeight"] as! Double,"capsule height");check(radius,row["radius"] as! Double,"capsule radius")
        return (row["hits"] as! [Row]).map(collider)
    }
    func contact(_ first: UInt64,_ second: UInt64,prediction: Double) -> NativeCharacterContact? {
        let row = next("contacts")
        precondition(first == UInt64(row["first"] as! Int) && second == UInt64(row["second"] as! Int))
        check(prediction,row["prediction"] as! Double,"contact prediction")
        guard let value = row["hit"] as? Row else { return nil }
        return .init(distance:value["distance"] as! Double,normal2:vector(value["normal2"]!),
                     point1:vector(value["point1"]!),point2:vector(value["point2"]!))
    }
    func movement(center: V,desired: V,excludingColliders: Set<UInt64>,excludingBodies: Set<UInt64>) -> NativeCharacterMovement {
        let row = next("moves")
        check(SIMD3<Double>(SIMD3<Float>(center)),row["center"]!,"KCC center",tolerance:2e-7)
        check(desired,row["desired"]!,"KCC requested")
        return .init(translation:vector(row["translation"]!),normals:(row["normals"] as! [[Double]]).map(vector))
    }
    func ray(origin: V,distance: Double,groups: UInt32,excludingBodies: Set<UInt64>) -> NativeCharacterHit? {
        let row = next("rays");check(origin,row["origin"]!,"ray origin");check(distance,row["distance"] as! Double,"ray length")
        precondition(groups == UInt32(row["groups"] as! UInt64));return hit(row["hit"])
    }
    func castBall(origin: V,radius: Double,distance: Double,groups: UInt32,excludingColliders: Set<UInt64>,excludingBodies: Set<UInt64>,requireBody: Bool) -> NativeCharacterHit? {
        let row = next("casts");check(origin,row["origin"]!,"cast origin");check(radius,row["radius"] as! Double,"cast radius")
        check(distance,row["distance"] as! Double,"cast length");precondition(groups == UInt32(row["groups"] as! UInt64));return hit(row["hit"])
    }
    func project(_ collider: UInt64,point: V) -> V? {
        let row = next("projects");precondition(collider == UInt64(row["collider"] as! Int));check(point,row["point"]!,"project point")
        return row["hit"] is NSNull ? nil : vector(row["hit"]!)
    }
}

@main enum CharacterMotorSmoke {
    static func main() throws {
        let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
        let data = try Data(contentsOf: URL(fileURLWithPath:root).appendingPathComponent("local-only/physics-fixtures/character-motor.json"))
        let fixture = try JSONSerialization.jsonObject(with:data) as! Row
        var frames = 0,comparisons = 0,largest = 0.0
        for scenario in fixture["cases"] as! [Row] {
            let replay = Replay(scenario),motor = NativeCharacterMotor(world:replay)
            motor.otherColliders = Set((scenario["others"] as! [Int]).map(UInt64.init));motor.setActive(true)
            var position = vector((scenario["frames"] as! [Row])[0]["before"]!)
            for (index,frame) in (scenario["frames"] as! [Row]).enumerated() {
                let input = frame["input"] as! Row,expected = frame["expected"] as! Row
                replay.begin(frame,"\(scenario["name"]!)/\(index)")
                motor.step(position:&position,displacement:vector(input["travel"]!),jump:input["jump"] as? Double ?? 0,
                           delta:fixture["delta"] as! Double,held:input["held"] as? Bool ?? false,
                           verticalOverride:input["vertical"] as? Double)
                replay.check(position,expected["position"]!,"position")
                replay.check(motor.rising,expected["rising"] as! Double,"rising")
                replay.check(motor.eased(),expected["easing"] as! Double,"easing")
                precondition(motor.grounded == expected["grounded"] as! Bool,"grounded")
                precondition(motor.propped == expected["propped"] as! Bool,"propped")
                for (angle,barred) in zip([0,Double.pi/2,Double.pi,Double.pi*1.5],expected["barred"] as! [Bool]) {
                    precondition(motor.barred(angle) == barred,"barrier")
                }
                let pressed = expected["pressed"] as! [Row];precondition(motor.pressed.count == pressed.count,"press count")
                for (actual,value) in zip(motor.pressed,pressed) {
                    precondition(actual.body == UInt64(value["body"] as! Int));replay.check(actual.point,value["point"]!,"press point")
                    let direction = value["direction"] as! [Double]
                    replay.check(actual.direction.x,direction[0],"press x");replay.check(actual.direction.y,direction[1],"press z")
                    replay.check(actual.speed,value["speed"] as! Double,"press speed")
                }
                replay.finish();frames += 1
            }
            comparisons += replay.comparisons;largest = max(largest,replay.maximumError)
            print("Replayed \(scenario["name"]!)")
        }
        print("PASS: \(frames) original on-foot frames, \(comparisons) comparisons, maximum error \(largest)")
    }
}
