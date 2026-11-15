import Foundation
import simd

@main enum BikeIntegrationSmoke {
    static func main() throws {
        let root=CommandLine.arguments[1]
        let url=URL(fileURLWithPath:root).appendingPathComponent("local-only/physics-fixtures/bike-dynamics.json")
        let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
        func v(_ a:Any)->SIMD3<Double> { let a=a as! [Double];return SIMD3(a[0],a[1],a[2]) }
        func n(_ a:[String:Any],_ name:String,_ fallback:Double=0)->Double { (a[name] as? NSNumber)?.doubleValue ?? fallback }
        func b(_ a:[String:Any],_ name:String)->Bool { a[name] as? Bool ?? false }
        var rows:[[String:Any]]=[]
        for nativeSolver in [false,true] { for scenario in fixture["cases"] as! [[String:Any]] {
            let config=scenario["config"] as! [String:Any],table=NativeVehicleDynamics.Table(model:Int(n(config,"id")),values:config["table"] as! [String:Any])
            let hubs=config["hubs"] as! [String:[String:Any]]
            func hub(_ key:String)->NativeBikeDynamics.Hub { .init(at:v(hubs[key]!["at"]!),radius:n(hubs[key]!,"radius")) }
            let solver=NativeBikeDynamics(configuration:.init(table:table,origin:n(config,"origin"),front:hub("front"),rear:hub("rear"),parameters:config["bike"] as! [String:Double],pedalled:b(config,"pedalled")),random:{0.37})!
            solver.setTyres(scenario["tyres"] as! [Int])
            let world=SwiftRapierWorld()!
            world.addBox(halfExtents:SIMD3(1000,0.1,1000),position:SIMD3(0,-0.1,0))
            let body=world.addBody(position:SIMD3(0,Float(n(scenario,"initialHeight",0.02)),0),mass:.init(value:Float(solver.mass),centre:SIMD3<Float>(solver.centre),turnMass:Float(solver.turnMass)))!
            for shape in config["chassis"] as! [[String:Any]] {
                let id:UInt64?
                if shape["kind"] as! String == "sphere" { id=world.addSphere(radius:Float(n(shape,"radius")),body:body,position:SIMD3<Float>(v(shape["centre"]!)),friction:Float(n(shape,"friction")),restitution:Float(n(shape,"restitution"))) }
                else { id=world.addBox(halfExtents:SIMD3<Float>(v(shape["halfExtents"]!)),body:body,position:SIMD3<Float>(v(shape["centre"]!)),friction:Float(n(shape,"friction")),restitution:Float(n(shape,"restitution"))) }
                precondition(id != nil);world.setColliderGroups(id!,collision:UInt32(n(shape,"collisionGroups")),solver:UInt32(n(shape,"solverGroups")))
            }
            world.step()
            var maxPosition=0.0,maxVelocity=0.0,maxRotation=0.0
            let frames=scenario["frames"] as! [[String:Any]]
            for frame in frames {
                let actual=world.bodyState(body)!,expected=frame["body"] as! [String:Any]
                let q=actual.rotation,rotation=simd_quatd(ix:Double(q.imag.x),iy:Double(q.imag.y),iz:Double(q.imag.z),r:Double(q.real))
                maxPosition=max(maxPosition,simd_distance(SIMD3<Double>(actual.position),v(expected["position"]!)))
                maxVelocity=max(maxVelocity,simd_distance(SIMD3<Double>(actual.linearVelocity),v(expected["linearVelocity"]!)))
                let eq=expected["rotation"] as! [Double],quaternion=SIMD4(eq[0],eq[1],eq[2],eq[3])
                maxRotation=max(maxRotation,min(simd_length(rotation.vector-quaternion),simd_length(rotation.vector+quaternion)))
                let linear:SIMD3<Double>,angular:SIMD3<Double>
                if nativeSolver {
                    let values=frame["input"] as! [String:Any];var input=NativeBikeDynamics.Input()
                    input.throttle=n(values,"throttle");input.steer=n(values,"steer");input.lean=n(values,"lean");input.wetness=n(values,"wetness")
                    input.handbrake=b(values,"handbrake");input.hop=b(values,"hop");input.riderless=b(values,"riderless")
                    let output=solver.step(delta:1/60,input:input,body:.init(position:SIMD3<Double>(actual.position),rotation:rotation,
                        linearVelocity:SIMD3<Double>(actual.linearVelocity),angularVelocity:SIMD3<Double>(actual.angularVelocity))) { origin,direction,distance in
                        guard let hit=world.raycast(origin:SIMD3<Float>(origin),direction:SIMD3<Float>(direction),distance:Float(distance),excludingBody:body) else { return nil }
                        return .init(distance:Double(hit.distance),normal:SIMD3<Double>(hit.normal),surface:hit.surface,material:hit.material)
                    }
                    linear=output.linearVelocity;angular=output.angularVelocity
                } else { linear=v(frame["linearVelocity"]!);angular=v(frame["angularVelocity"]!) }
                world.setVelocities(body,linear:SIMD3<Float>(linear),angular:SIMD3<Float>(angular));world.step()
            }
            let final=SIMD3<Double>(world.bodyState(body)!.position),finalError=simd_distance(final,v(scenario["final"]!))
            precondition(finalError.isFinite && maxPosition.isFinite)
            let name=scenario["name"] as! String,mode=nativeSolver ? "native-solver-and-core":"recorded-forces-native-core"
            rows.append(["case":name,"mode":mode,"frames":frames.count,"maxPositionError":maxPosition,"finalPositionError":finalError,"maxVelocityError":maxVelocity,"maxQuaternionComponentError":maxRotation])
            print("\(mode) \(name): max position \(maxPosition), final \(finalError), velocity \(maxVelocity)")
        } }
        let output=URL(fileURLWithPath:root).appendingPathComponent("local-only/native-physics/tests/bike-integration.json")
        try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:output)
        let failed=rows.filter { $0["maxPositionError"] as! Double>1e-9 || $0["finalPositionError"] as! Double>1e-9 || $0["maxVelocityError"] as! Double>1e-9 || $0["maxQuaternionComponentError"] as! Double>1e-9 }
        print("\(failed.isEmpty ? "PASS":"FAIL"): all15 motorcycle/bicycle cases within1e-9 position/velocity/quaternion integration gates; full stress metrics saved locally")
        if !failed.isEmpty { exit(1) }
    }
}
