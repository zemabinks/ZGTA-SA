import Foundation
import simd

@main enum VehicleAuxiliariesIntegration {
    static func main() throws {
        let root=CommandLine.arguments[1]
        func v(_ raw:Any)->SIMD3<Double> { let a=raw as! [Double];return SIMD3(a[0],a[1],a[2]) }
        func n(_ values:[String:Any],_ key:String)->Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
        var rows:[[String:Any]]=[]
        for filename in ["flight-dynamics","vehicle-buoyancy"] {
            let url=URL(fileURLWithPath:root).appendingPathComponent("local-only/physics-fixtures/\(filename).json")
            let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
            for nativeSolver in [false,true] { for scenario in fixture["cases"] as! [[String:Any]] {
                var row=scenario["config"] as! [String:Any];row["solverSupported"]=true
                let definition=NativeGroundVehicle.Definition(row)!,configuration=definition.configuration
                let solver=NativeVehicleDynamics(configuration:configuration,random:{0.37})!
                if let values=definition.flightParameters {
                    solver.flight=NativeFlightDynamics(parameters:values,kind:configuration.kind,rearExtent:definition.rearExtent,jets:configuration.table.model==520,hover:configuration.table.model==539)
                }
                solver.buoyancy=NativeVehicleBuoyancy(table:configuration.table,minimum:definition.buoyancyMinimum,maximum:definition.buoyancyMaximum,parameters:definition.boatParameters)
                let name=scenario["name"] as! String
                var tick=0
                if filename=="vehicle-buoyancy" {
                    solver.buoyancy?.waterLevel={ _ in name=="car-leave-water" && tick>=480 ? nil:0 }
                    if scenario["waves"] as! Bool { solver.buoyancy?.wave={ point in
                        let x=point.x,y = -point.z,time=Double(tick)
                        let height=0.08*sin(x*0.2+time*0.03)+0.04*cos(y*0.3-time*0.02)
                        var normal=SIMD3<Double>(-0.016*cos(x*0.2+time*0.03),1,-0.012*sin(y*0.3-time*0.02))
                        normal *= 1/simd_length(normal)
                        return .init(height:height,normal:normal)
                    } }
                }
                let world=SwiftRapierWorld(gravity:SIMD3(0,-18,0))!
                if filename=="flight-dynamics" { world.addBox(halfExtents:SIMD3(10000,0.1,10000),position:SIMD3(0,-0.1,0)) }
                let body=world.addBody(position:SIMD3(0,filename=="flight-dynamics" ? 10:-0.5,0),mass:.init(value:Float(solver.mass),centre:SIMD3<Float>(solver.centre),turnMass:Float(solver.turnMass)))!
                for shape in definition.chassis {
                    let collider:UInt64?
                    if shape.kind=="sphere" { collider=world.addSphere(radius:shape.radius,body:body,position:shape.centre,friction:shape.friction,restitution:shape.restitution) }
                    else { collider=world.addBox(halfExtents:shape.halfExtents,body:body,position:shape.centre,friction:shape.friction,restitution:shape.restitution) }
                    precondition(collider != nil);world.setColliderGroups(collider!,collision:shape.collisionGroups,solver:shape.solverGroups)
                }
                world.step()
                var positionError=0.0,velocityError=0.0,rotationError=0.0
                let frames=scenario["frames"] as! [[String:Any]]
                for (index,frame) in frames.enumerated() {
                    tick=index
                    let full=frame["full"] as! [String:Any],expected=full["body"] as! [String:Any],actual=world.bodyState(body)!
                    let q=actual.rotation,rotation=simd_quatd(ix:Double(q.imag.x),iy:Double(q.imag.y),iz:Double(q.imag.z),r:Double(q.real))
                    positionError=max(positionError,simd_distance(SIMD3<Double>(actual.position),v(expected["position"]!)))
                    velocityError=max(velocityError,simd_distance(SIMD3<Double>(actual.linearVelocity),v(expected["linearVelocity"]!)))
                    let eq=expected["rotation"] as! [Double],quaternion=SIMD4(eq[0],eq[1],eq[2],eq[3])
                    rotationError=max(rotationError,min(simd_length(rotation.vector-quaternion),simd_length(rotation.vector+quaternion)))
                    let linear:SIMD3<Double>,angular:SIMD3<Double>
                    if nativeSolver {
                        let values=frame["input"] as! [String:Any];var input=NativeVehicleDynamics.Input()
                        input.throttle=n(values,"throttle");input.steer=n(values,"steer");input.pitch=n(values,"pitch");input.roll=n(values,"roll");input.yaw=n(values,"yaw");input.jets=n(values,"jets")
                        input.nobody=values["nobody"] as? Bool ?? false;input.handbrake=values["handbrake"] as? Bool ?? false
                        input.accelerate=(values["accelerate"] as? NSNumber)?.doubleValue;input.brake=(values["brake"] as? NSNumber)?.doubleValue
                        solver.flight?.setGear(frame["gear"] as? Bool ?? false)
                        let output=solver.step(delta:1/60,input:input,body:.init(position:SIMD3<Double>(actual.position),rotation:rotation,linearVelocity:SIMD3<Double>(actual.linearVelocity),angularVelocity:SIMD3<Double>(actual.angularVelocity))) { origin,direction,distance in
                            guard let hit=world.raycast(origin:SIMD3<Float>(origin),direction:SIMD3<Float>(direction),distance:Float(distance),excludingBody:body) else { return nil }
                            return .init(distance:Double(hit.distance),normal:SIMD3<Double>(hit.normal),surface:hit.surface,material:hit.material)
                        }
                        linear=output.linearVelocity;angular=output.angularVelocity
                    } else { linear=v(full["linearVelocity"]!);angular=v(full["angularVelocity"]!) }
                    world.setVelocities(body,linear:SIMD3<Float>(linear),angular:SIMD3<Float>(angular));world.step()
                }
                let final=SIMD3<Double>(world.bodyState(body)!.position),finalError=simd_distance(final,v(scenario["final"]!))
                precondition(positionError.isFinite && finalError.isFinite)
                let mode=nativeSolver ? "native-solver-and-core":"recorded-forces-native-core"
                rows.append(["case":name,"mode":mode,"frames":frames.count,"maxPositionError":positionError,"finalPositionError":finalError,"maxVelocityError":velocityError,"maxQuaternionComponentError":rotationError])
                print("\(mode) \(name): position \(positionError), final \(finalError), velocity \(velocityError)")
            } }
        }
        let output=URL(fileURLWithPath:root).appendingPathComponent("local-only/native-physics/tests/auxiliary-integration.json")
        try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:output)
        let failures=rows.filter { $0["maxPositionError"] as! Double>0.01 || $0["finalPositionError"] as! Double>0.01 || $0["maxVelocityError"] as! Double>0.1 }
        print("\(failures.isEmpty ? "PASS":"FAIL"): aircraft/boat native integration1cm/0.1m/s gates, full metrics saved locally")
        if !failures.isEmpty { exit(1) }
    }
}
