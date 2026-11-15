import Foundation
import simd

/// Hierarchical original jetpack object nodes and draw ranges. Exported local
/// data retains the public model builder's matrices and material visibility.
struct NativeFlightAssets: Decodable {
    struct Node:Decodable {var name:String;var parent:Int;var matrix:[Float]}
    struct Draw:Decodable {var node:Int;var start:Int;var count:Int;var visible:Bool;var alphaTest:Float}
    var vertices:Int
    var indices:Int
    var nodes:[Node]
    var draws:[Draw]
    var skinned:Bool
    func jetPose(_ jet:NativeFlightAnimation.Jet)->[simd_float4x4] {
        var result:[simd_float4x4]=[]
        for (index,node)in nodes.enumerated() {
            guard node.matrix.count==16,node.parent<index,node.parent>=(-1) else{return []}
            let m=node.matrix
            var local=simd_float4x4(columns:(SIMD4(m[0],m[1],m[2],m[3]),SIMD4(m[4],m[5],m[6],m[7]),SIMD4(m[8],m[9],m[10],m[11]),SIMD4(m[12],m[13],m[14],m[15])))
            if node.parent<0 {
                local=simd_float4x4(simd_quatf(angle:Float.pi/2,axis:SIMD3(0,1,0)))
                local.columns.3=SIMD4(0.1,0.08,0,1)
            } else if node.name=="jetball1" || node.name=="jetball2" {
                // Object3D.rotation.set resets all Euler angles while retaining
                // the original node position and scale (XYZ Euler order).
                let scale=SIMD3(simd_length(local.columns.0),simd_length(local.columns.1),simd_length(local.columns.2)),position=local.columns.3
                local=simd_float4x4(simd_quatf(angle:Float(jet.pitch),axis:SIMD3(1,0,0)))*simd_float4x4(simd_quatf(angle:Float(node.name=="jetball1" ? jet.leftRoll:jet.rightRoll),axis:SIMD3(0,1,0)))
                local.columns.0 *= scale.x;local.columns.1 *= scale.y;local.columns.2 *= scale.z;local.columns.3=position
            }
            result.append(node.parent>=0 ? result[node.parent]*local:local)
        }
        return result
    }
}
