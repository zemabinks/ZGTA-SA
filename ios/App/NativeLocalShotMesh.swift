// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Read-only acceleration for the same original vehicle triangles and rigid
/// node matrices used by the renderer. Material visibility and pixel alpha
/// are intentionally distinct from the source bullet mesh-visibility policy.
final class NativeLocalShotMesh {
    typealias V=SIMD3<Double>
    typealias M=simd_double4x4
    struct Surface {
        let node:Int,start:Int,count:Int,side:Int
        let transparent:Bool,opacity:Double,additive:Bool
    }
    struct Hit {let distance:Double,transparent:Bool,surface:Int}
    private struct Node {
        let low:V,high:V,left:Int,right:Int,start:Int,count:Int
    }
    private let positions:[V],indices:[UInt32],surfaces:[Surface]
    private var nodes:[Node]=[],order:[Int]=[],roots:[Int]=[]
    init?(positions:[SIMD3<Float>],indices:[UInt32],surfaces:[Surface]) {
        guard !positions.isEmpty,positions.count<1_000_000,indices.count<3_000_000,
              positions.allSatisfy({$0.x.isFinite && $0.y.isFinite && $0.z.isFinite}),
              indices.allSatisfy({Int($0)<positions.count}),surfaces.count<=50_000,
              surfaces.allSatisfy({$0.node>=0 && $0.start>=0 && $0.count>=0 && $0.start%3==0 && $0.count%3==0 &&
                  $0.start<=indices.count && $0.count<=indices.count-$0.start && (0...2).contains($0.side) &&
                  $0.opacity.isFinite && (0...1).contains($0.opacity)})else{return nil}
        self.positions=positions.map(V.init);self.indices=indices;self.surfaces=surfaces
        // An additive material makes the complete original mesh ineligible,
        // including its other opaque material groups.
        let additiveNodes=Set(surfaces.filter(\.additive).map(\.node))
        for surface in surfaces {
            if additiveNodes.contains(surface.node) || surface.count==0{roots.append(-1);continue}
            roots.append(build(Array(stride(from:surface.start,to:surface.start+surface.count,by:3))))
        }
    }
    private func vertex(_ index:Int)->V {positions[Int(indices[index])]}
    private func build(_ triangles:[Int])->Int {
        var low=V(repeating:.infinity),high=V(repeating:-.infinity)
        for triangle in triangles {for corner in 0..<3 {let p=vertex(triangle+corner);low=simd_min(low,p);high=simd_max(high,p)}}
        let index=nodes.count
        nodes.append(Node(low:low,high:high,left:-1,right:-1,start:0,count:0))
        if triangles.count<=8 {
            let start=order.count;order.append(contentsOf:triangles)
            nodes[index]=Node(low:low,high:high,left:-1,right:-1,start:start,count:triangles.count)
        }else{
            let extent=high-low,axis=extent.x>=extent.y && extent.x>=extent.z ? 0:extent.y>=extent.z ? 1:2
            func center(_ at:Int)->Double {(vertex(at)[axis]+vertex(at+1)[axis]+vertex(at+2)[axis])/3}
            let sorted=triangles.sorted{let a=center($0),b=center($1);return a==b ? $0<$1:a<b}
            let middle=sorted.count/2,left=build(Array(sorted[..<middle])),right=build(Array(sorted[middle...]))
            nodes[index]=Node(low:low,high:high,left:left,right:right,start:0,count:0)
        }
        return index
    }
    private static func box(_ low:V,_ high:V,origin:V,direction:V,maximum:Double)->Bool {
        var near=0.0,far=maximum
        for axis in 0..<3 {
            if direction[axis]==0 {if origin[axis]<low[axis] || origin[axis]>high[axis]{return false};continue}
            let a=(low[axis]-origin[axis])/direction[axis],b=(high[axis]-origin[axis])/direction[axis]
            near=max(near,min(a,b));far=min(far,max(a,b));if near>far{return false}
        }
        return far>=0
    }
    static func triangle(origin:V,direction:V,a:V,b:V,c:V,side:Int)->Double? {
        let edge=b-a,other=c-a,cross=simd_cross(direction,other),determinant=simd_dot(edge,cross)
        guard determinant != 0,(side==2 || (side==0 ? determinant>0:determinant<0))else{return nil}
        let relative=origin-a,u=simd_dot(relative,cross)/determinant
        guard u>=0,u<=1 else{return nil}
        let crossOther=simd_cross(relative,edge),v=simd_dot(direction,crossOther)/determinant
        guard v>=0,u+v<=1 else{return nil}
        let at=simd_dot(other,crossOther)/determinant
        return at.isFinite && at>=0 ? at:nil
    }
    func hit(ray:NativeLocalShots.Ray,body:M,matrices:[M],visible:[Bool])->Hit? {
        var result:Hit?,nearest=ray.range
        for (index,surface)in surfaces.enumerated() {
            guard roots[index]>=0,matrices.indices.contains(surface.node),visible.indices.contains(surface.node),visible[surface.node]else{continue}
            let world=body*matrices[surface.node],determinant=simd_determinant(world)
            guard determinant.isFinite,determinant != 0 else{continue}
            let inverse=world.inverse,p=inverse*SIMD4(ray.origin,1),d=inverse*SIMD4(ray.direction,0)
            let origin=V(p.x,p.y,p.z),direction=V(d.x,d.y,d.z)
            guard NativeLocalShots.finite(origin),NativeLocalShots.finite(direction)else{continue}
            // Keep the inverse-transformed direction unnormalized: its ray
            // parameter remains a distance in the original world units.
            var stack=[roots[index]]
            while let at=stack.popLast() {
                let node=nodes[at]
                guard Self.box(node.low,node.high,origin:origin,direction:direction,maximum:nearest)else{continue}
                if node.count>0 {
                    for entry in node.start..<node.start+node.count {
                        let triangle=order[entry]
                        guard let distance=Self.triangle(origin:origin,direction:direction,a:vertex(triangle),b:vertex(triangle+1),c:vertex(triangle+2),side:surface.side),
                              distance<=ray.range,result == nil || distance<nearest else{continue}
                        nearest=distance;result=Hit(distance:distance,transparent:surface.transparent && surface.opacity<1,surface:index)
                    }
                }else{stack.append(node.right);stack.append(node.left)}
            }
        }
        return result
    }
}
