import Foundation
import simd

@main enum VehicleRigSmoke {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let document=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("local-only/physics-fixtures/vehicle-rigs.json"))) as! [String:Any]
        var failures=0,frames=0,samples=0,largest=0.0,worst=""
        func number(_ row:[String:Any],_ key:String)->Double{(row[key] as? NSNumber)?.doubleValue ?? 0}
        func check(_ actual:Double,_ expected:Double,_ label:String){let error=abs(actual-expected);if error>largest{largest=error;worst=label};if !actual.isFinite||error>1e-8{if failures<12{print("FAIL \(label): \(actual) expected \(expected)")};failures+=1}}
        for scenario in document["cases"] as! [[String:Any]] {
            let name=scenario["model"] as! String,data=try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/models/\(name).rig.json"))
            guard let rig=NativeVehicleRig(data:data) else{print("FAIL malformed \(name)");failures+=1;continue}
            var state=NativeVehicleRig.State()
            for (index,reference) in (scenario["frames"] as! [[String:Any]]).enumerated(){
                let row=reference["input"] as! [String:Any];var input=NativeVehicleRig.Input()
                input.steering=number(row,"steering");input.rearSteering=number(row,"rearSteering");input.frontSpin=number(row,"frontSpin");input.rearSpin=number(row,"rearSpin")
                input.offsets=row["offsets"] as! [Double];input.drop=row["drop"] as! [Double];input.lean=number(row,"lean");input.crank=number(row,"crank")
                input.rotor=number(row,"rotor");input.rotorSpin=number(row,"rotorSpin");input.nozzle=number(row,"nozzle");input.gearUp=row["gearUp"] as! Bool
                input.looks=row["looks"] as! [Int];input.tyres=row["tyres"] as! [Int];input.doorAngles=row["doorAngles"] as! [Double];input.doorAxes=row["doorAxes"] as! [Int]
                input.lights=row["lights"] as! Bool;input.braking=row["braking"] as! Bool;input.scorched=row["scorched"] as! Bool
                let actual=rig.pose(input,state:&state,delta:number(reference,"delta")),matrices=reference["matrices"] as! [[Double]],visible=reference["visible"] as! [Bool]
                for node in actual.matrices.indices {
                    let matrix=actual.matrices[node]
                    for column in 0..<4{for axis in 0..<4{check(matrix[column][axis],matrices[node][column*4+axis],"\(name)/\(index)/\(node)/matrix")}}
                    // Ancestor visibility is propagated natively, so compare
                    // the original local flags only while its parent is shown.
                    let parent=rig.document.nodes[node].parent
                    if parent<0 || actual.visible[parent]{if actual.visible[node] != visible[node]{if failures<12{print("FAIL \(name)/\(index)/\(node)/visibility")};failures+=1}}
                }
                for sample in reference["samples"] as! [[String:Any]]{
                    let node=sample["node"] as! Int,local=sample["local"] as! [Double],expected=sample["world"] as! [Double]
                    let point=actual.matrices[node]*SIMD4(local[0],local[1],local[2],1)
                    for axis in 0..<3{check(point[axis],expected[axis],"\(name)/\(index)/\(node)/vertex")};samples+=1
                };frames+=1
            }
        }
        print("\(failures==0 ? "PASS":"FAIL"): \(frames) original complete-rig poses, \(samples) transformed vertices, max error \(largest) at \(worst), \(failures) mismatches")
        let report:[String:Any]=["models":(document["cases"] as! [[String:Any]]).count,"frames":frames,"transformedVertices":samples,"maximumError":largest,"worst":worst,"mismatches":failures]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("local-only/native-physics/tests/vehicle-rigs.json"))
        if failures>0{exit(1)}
    }
}
