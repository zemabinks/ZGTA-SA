import Foundation
import Metal
import simd

@main enum VehicleRigGPUSmoke {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),device=MTLCreateSystemDefaultDevice()!
        let references=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("local-only/physics-fixtures/vehicle-rigs.json"))) as! [String:Any]
        var vertices:[SIMD4<Float>]=[],matrices:[simd_float4x4]=[],expected:[SIMD3<Double>]=[]
        func number(_ row:[String:Any],_ key:String)->Double{(row[key] as? NSNumber)?.doubleValue ?? 0}
        func input(_ row:[String:Any])->NativeVehicleRig.Input {
            var value=NativeVehicleRig.Input()
            value.steering=number(row,"steering");value.rearSteering=number(row,"rearSteering");value.frontSpin=number(row,"frontSpin");value.rearSpin=number(row,"rearSpin")
            value.offsets=row["offsets"] as! [Double];value.drop=row["drop"] as! [Double];value.lean=number(row,"lean");value.crank=number(row,"crank")
            value.rotor=number(row,"rotor");value.rotorSpin=number(row,"rotorSpin");value.nozzle=number(row,"nozzle");value.gearUp=row["gearUp"] as! Bool
            value.looks=row["looks"] as! [Int];value.tyres=row["tyres"] as! [Int];value.doorAngles=row["doorAngles"] as! [Double];value.doorAxes=row["doorAxes"] as! [Int]
            return value
        }
        for scenario in references["cases"] as! [[String:Any]] {
            let name=scenario["model"] as! String,base=root.appendingPathComponent("local-only/site/game/native/models/\(name).rig")
            let rig=NativeVehicleRig(data:try Data(contentsOf:base.appendingPathExtension("json")))!
            let world=try WorldBinary(data:rig.meshData(Data(contentsOf:base.appendingPathExtension("bin")))!),frames=scenario["frames"] as! [[String:Any]]
            let target=min(75,frames.count-1);var state=NativeVehicleRig.State(),pose:NativeVehicleRig.Frame?
            for frame in frames[0...target]{pose=rig.pose(input(frame["input"] as! [String:Any]),state:&state,delta:number(frame,"delta"))}
            let original=frames[target]["matrices"] as! [[Double]],offset=matrices.count
            matrices += pose!.matrices.map{m in simd_float4x4(columns:(SIMD4<Float>(m[0]),SIMD4<Float>(m[1]),SIMD4<Float>(m[2]),SIMD4<Float>(m[3])))}
            var nodes=[Int](repeating:-1,count:world.vertices.count)
            for draw in rig.document.draws {for index in world.indices[draw.start..<draw.start+draw.count]{let at=Int(index);precondition(nodes[at]<0||nodes[at]==draw.node);nodes[at]=draw.node}}
            precondition(nodes.allSatisfy{$0>=0})
            for (index,vertex) in world.vertices.enumerated(){
                let node=nodes[index],p=SIMD3<Double>(Double(vertex.position.x),Double(vertex.position.y),Double(vertex.position.z)),m=original[node]
                vertices.append(SIMD4(vertex.position.x,vertex.position.y,vertex.position.z,Float(offset+node)))
                expected.append(SIMD3(m[0]*p.x+m[4]*p.y+m[8]*p.z+m[12],m[1]*p.x+m[5]*p.y+m[9]*p.z+m[13],m[2]*p.x+m[6]*p.y+m[10]*p.z+m[14]))
            }
            for mask in rig.document.waterMasks ?? [] {
                let m=original[mask.node]
                for index in stride(from:0,to:mask.positions.count,by:3) {
                    let p=SIMD3<Double>(Double(mask.positions[index]),Double(mask.positions[index+1]),Double(mask.positions[index+2]))
                    vertices.append(SIMD4(Float(p.x),Float(p.y),Float(p.z),Float(offset+mask.node)))
                    expected.append(SIMD3(m[0]*p.x+m[4]*p.y+m[8]*p.z+m[12],m[1]*p.x+m[5]*p.y+m[9]*p.z+m[13],m[2]*p.x+m[6]*p.y+m[10]*p.z+m[14]))
                }
            }
        }
        let source="""
        #include <metal_stdlib>
        using namespace metal;
        kernel void transformVehicle(uint id[[thread_position_in_grid]],const device float4*vertices[[buffer(0)]],const device float4x4*matrices[[buffer(1)]],device float4*result[[buffer(2)]]){float4 v=vertices[id];result[id]=matrices[uint(v.w)]*float4(v.xyz,1);}
        """
        let library=try device.makeLibrary(source:source,options:nil),pipeline=try device.makeComputePipelineState(function:library.makeFunction(name:"transformVehicle")!)
        let inputBuffer=device.makeBuffer(bytes:vertices,length:vertices.count*MemoryLayout<SIMD4<Float>>.stride)!,matrixBuffer=device.makeBuffer(bytes:matrices,length:matrices.count*MemoryLayout<simd_float4x4>.stride)!
        let result=device.makeBuffer(length:vertices.count*MemoryLayout<SIMD4<Float>>.stride,options:.storageModeShared)!,queue=device.makeCommandQueue()!,command=queue.makeCommandBuffer()!,encoder=command.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(pipeline);encoder.setBuffer(inputBuffer,offset:0,index:0);encoder.setBuffer(matrixBuffer,offset:0,index:1);encoder.setBuffer(result,offset:0,index:2)
        encoder.dispatchThreads(MTLSize(width:vertices.count,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:min(128,pipeline.maxTotalThreadsPerThreadgroup),height:1,depth:1));encoder.endEncoding();command.commit();command.waitUntilCompleted()
        if let error=command.error{throw error}
        let actual=result.contents().bindMemory(to:SIMD4<Float>.self,capacity:vertices.count);var maximum=0.0,worst=0
        for index in vertices.indices{let point=SIMD3<Double>(Double(actual[index].x),Double(actual[index].y),Double(actual[index].z)),error=simd_distance(point,expected[index]);if !error.isFinite{fatalError("Nonfinite GPU vehicle pose")};if error>maximum{maximum=error;worst=index}}
        let report:[String:Any]=["models":(references["cases"] as! [[String:Any]]).count,"vertices":vertices.count,"maximumDistanceError":maximum,"worstVertex":worst,"passed":maximum<0.0001]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("local-only/native-physics/tests/vehicle-rigs-gpu.json"))
        print("\(maximum<0.0001 ? "PASS":"FAIL"): \(vertices.count) complete-rig Metal vertices versus original pose matrices; maximum \(maximum)m")
        if maximum>=0.0001{exit(1)}
    }
}
