import Foundation
import simd

/// A vehicle's separate pedestrian support mesh. These triangles answer
/// support rays; they are not additional global rigid-body colliders.
final class NativeVehicleTread {
    typealias V=SIMD3<Double>
    struct Definition {
        struct Moving {let index:Int,at:V}
        let positions:[SIMD3<Float>],indices:[Int],moving:[Moving]
        init?(_ row:[String:Any]) {
            guard let raw=row["positions"] as? [Double],!raw.isEmpty,raw.count%3==0,raw.count<=3_000_000,
                  raw.allSatisfy({$0.isFinite && Float($0).isFinite}),
                  let indices=row["indices"] as? [Int],indices.count%3==0,indices.count<=3_000_000,
                  indices.allSatisfy({$0>=0 && $0<raw.count/3}),
                  let moves=row["moving"] as? [[String:Any]],moves.count<=raw.count/3 else{return nil}
            var seen:Set<Int>=[],moving:[Moving]=[]
            for value in moves {
                guard let index=value["index"] as? Int,index>=0,index<raw.count/3,seen.insert(index).inserted,
                      let at=value["at"] as? [Double],at.count==3,at.allSatisfy(\.isFinite) else{return nil}
                moving.append(.init(index:index,at:V(at[0],at[1],at[2])))
            }
            self.positions=stride(from:0,to:raw.count,by:3).map{SIMD3(Float(raw[$0]),Float(raw[$0+1]),Float(raw[$0+2]))}
            self.indices=indices;self.moving=moving
        }
    }
    let definition:Definition
    private(set) var positions:[SIMD3<Float>]
    private var lastWork:Double?
    init(_ definition:Definition){self.definition=definition;positions=definition.positions}
    /// Moving vertices start from unrounded imported body coordinates, then
    /// return to the original Float32 query-buffer boundary after posing.
    func pose(work:Double,transform:(V,Double)->V) {
        guard work.isFinite else{return}
        let value=min(2500,max(0,work));guard lastWork != value else{return}
        var changed:[(Int,SIMD3<Float>)]=[];changed.reserveCapacity(definition.moving.count)
        for moving in definition.moving {
            let point=transform(moving.at,value),cast=SIMD3<Float>(point)
            guard point.x.isFinite,point.y.isFinite,point.z.isFinite,cast.x.isFinite,cast.y.isFinite,cast.z.isFinite else{return}
            changed.append((moving.index,cast))
        }
        for (index,point) in changed{positions[index]=point};lastWork=value
    }
    /// Body rotations from Rapier are unit quaternions. Conjugation preserves
    /// the archived query's exact inverse boundary without renormalizing it.
    func ray(origin:V,distance:Double,bodyPosition:V,bodyRotation:simd_quatd)->Double? {
        guard distance.isFinite,distance>=0,
              [origin.x,origin.y,origin.z,bodyPosition.x,bodyPosition.y,bodyPosition.z].allSatisfy(\.isFinite),
              bodyRotation.vector.x.isFinite,bodyRotation.vector.y.isFinite,bodyRotation.vector.z.isFinite,bodyRotation.vector.w.isFinite else{return nil}
        let inverse=bodyRotation.conjugate,local=inverse.act(origin-bodyPosition),direction=inverse.act(V(0,-1,0))
        var nearest:Double?
        for index in stride(from:0,to:definition.indices.count,by:3) {
            let a=V(positions[definition.indices[index]]),b=V(positions[definition.indices[index+1]]),c=V(positions[definition.indices[index+2]])
            let edge=b-a,other=c-a,cross=simd_cross(direction,other),determinant=simd_dot(edge,cross)
            if abs(determinant)<1e-9{continue}
            let offset=local-a,u=simd_dot(offset,cross)/determinant
            if u<0 || u>1{continue}
            let side=simd_cross(offset,edge),v=simd_dot(direction,side)/determinant
            if v<0 || u+v>1{continue}
            let hit=simd_dot(other,side)/determinant
            if hit>=0 && hit<=distance && (nearest==nil || hit<nearest!){nearest=hit}
        }
        return nearest
    }
}
