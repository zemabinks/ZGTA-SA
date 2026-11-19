import Foundation
import simd

@main enum TrainIntegrationSmoke {
    static func main() throws {
        let root=CommandLine.arguments[1],base=URL(fileURLWithPath:root)
        let tracks=NativeTrainTracks(data:try Data(contentsOf:base.appendingPathComponent("local-only/site/game/native/trains.json")))!
        let document=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("local-only/physics-fixtures/train-dynamics.json"))) as! [String:Any]
        func v(_ raw:Any)->SIMD3<Double> { let a=raw as! [Double];return SIMD3(a[0],a[1],a[2]) }
        func n(_ values:[String:Any],_ key:String)->Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
        var results:[[String:Any]]=[]
        for scenario in document["cases"] as! [[String:Any]] {
            let row=scenario["config"] as! [String:Any],table=row["table"] as! [String:Any],bounds=row["bounds"] as! [String:Any],box=bounds["box"] as! [String:Any]
            let config=NativeTrainDynamics.Configuration(model:Int(n(row,"id")),origin:n(row,"origin"),lower:n(table,"lower"),minimum:v(box["min"]!),maximum:v(box["max"]!),carriages:row["carriages"] as? [Int] ?? [])
            let motor=NativeTrainDynamics(configuration:config,tracks:tracks,position:v(scenario["start"]!),heading:n(scenario,"heading"))!
            let world=SwiftRapierWorld(gravity:SIMD3(0,-18,0))!
            func rotation(_ q:simd_quatd)->simd_quatf { .init(vector:SIMD4<Float>(q.vector)) }
            let body=world.addBody(kind:.kinematicVelocity,position:SIMD3<Float>(motor.initial.position),rotation:rotation(motor.initial.rotation))!
            for shape in row["chassis"] as! [[String:Any]] {
                let collider:UInt64?
                if shape["kind"] as! String == "sphere" { collider=world.addSphere(radius:Float(n(shape,"radius")),body:body,position:SIMD3<Float>(v(shape["centre"]!)),friction:Float(n(shape,"friction")),restitution:Float(n(shape,"restitution"))) }
                else { collider=world.addBox(halfExtents:SIMD3<Float>(v(shape["halfExtents"]!)),body:body,position:SIMD3<Float>(v(shape["centre"]!)),friction:Float(n(shape,"friction")),restitution:Float(n(shape,"restitution"))) }
                precondition(collider != nil);world.setColliderGroups(collider!,collision:UInt32(n(shape,"collisionGroups")),solver:UInt32(n(shape,"solverGroups")))
            }
            world.step()
            var positionError=0.0,velocityError=0.0,rotationError=0.0
            let frames=scenario["frames"] as! [[String:Any]]
            for frame in frames {
                let actual=world.bodyState(body)!,expected=frame["body"] as! [String:Any]
                positionError=max(positionError,simd_distance(SIMD3<Double>(actual.position),v(expected["position"]!)))
                velocityError=max(velocityError,simd_distance(SIMD3<Double>(actual.linearVelocity),v(expected["linearVelocity"]!)))
                let q=SIMD4<Double>(actual.rotation.vector),eq=expected["rotation"] as! [Double],target=SIMD4(eq[0],eq[1],eq[2],eq[3])
                rotationError=max(rotationError,min(simd_length(q-target),simd_length(q+target)))
                let input=frame["input"] as! [String:Any],output=motor.step(delta:1/60,throttle:n(input,"throttle"),handbrake:input["handbrake"] as? Bool ?? false)
                world.setBodyState(.init(position:SIMD3<Float>(output.pose.position),rotation:rotation(output.pose.rotation),linearVelocity:SIMD3<Float>(output.linearVelocity),angularVelocity:SIMD3<Float>(output.angularVelocity)),for:body)
                world.setBrowserRotation(body,rotation:rotation(output.pose.rotation))
                world.step()
            }
            let finalError=simd_distance(SIMD3<Double>(world.bodyState(body)!.position),v(scenario["final"]!))
            let name=scenario["name"] as! String
            results.append(["case":name,"frames":frames.count,"maxPositionError":positionError,"maxVelocityError":velocityError,"maxQuaternionComponentError":rotationError,"finalPositionError":finalError])
            print("\(name): position \(positionError), final \(finalError), velocity \(velocityError)")
        }
        try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:base.appendingPathComponent("local-only/native-physics/tests/train-integration.json"))
        let failed=results.contains { $0["maxPositionError"] as! Double>1e-9 || $0["finalPositionError"] as! Double>1e-9 || $0["maxVelocityError"] as! Double>1e-9 || $0["maxQuaternionComponentError"] as! Double>1e-9 }
        print("\(failed ? "FAIL":"PASS"): all original train native kinematic-core paths within1e-9 position/velocity/quaternion")
        if failed { exit(1) }
    }
}
