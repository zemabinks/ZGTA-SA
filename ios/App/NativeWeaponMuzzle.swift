import Foundation
import CoreFoundation
import simd

/// Weapon offsets are local to the actual hand-mounted weapon. This retains
/// the archived attachment convention; retail runtime behavior is unverified.
enum NativeWeaponMuzzle {
    typealias V=SIMD3<Float>
    typealias M=simd_float4x4
    struct Definition {
        let weapon:Int
        let skill:Int
        let offset:V
        let twin:Bool
        let kind:String
        let range:Float
    }
    struct Catalog {
        enum Error:Swift.Error {case invalidDocument}
        private var selected:[Int:Definition]=[:]
        private var levels:[Int:[Int:Definition]]=[:]
        init(data:Data) throws {
            guard let doc=try JSONSerialization.jsonObject(with:data) as? [String:Any],
                  let stats=doc["stats"] as? [String:[String:Any]] else{throw Error.invalidDocument}
            func read(_ weapon:Int,_ row:[String:Any])->Definition? {
                guard let n=row["skill"] as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
                      let skill=Int(exactly:n.doubleValue),(0...3).contains(skill),
                      let values=row["offset"] as? [NSNumber],values.count==3,
                      let kind=row["fire"] as? String,let distance=row["range"] as? NSNumber,
                      distance.floatValue.isFinite,distance.floatValue>=0 else{return nil}
                let offset=V(values[0].floatValue,values[1].floatValue,values[2].floatValue)
                guard finite(offset),values.allSatisfy({CFGetTypeID($0) != CFBooleanGetTypeID()}) else{return nil}
                let text=(row["flags"] as? String ?? "0").lowercased().replacingOccurrences(of:"0x",with:"")
                guard let flags=UInt32(text,radix:16) else{return nil}
                return Definition(weapon:weapon,skill:skill,offset:offset,twin:flags&2048 != 0,kind:kind,range:distance.floatValue)
            }
            for (key,row) in stats {
                guard let weapon=Int(key),(0...46).contains(weapon),let base=read(weapon,row) else{continue}
                var variants=[base.skill:base]
                for value in row["levels"] as? [[String:Any]] ?? [] {
                    guard let level=read(weapon,value),variants[level.skill]==nil else{continue}
                    variants[level.skill]=level
                }
                selected[weapon]=base;levels[weapon]=variants
            }
        }
        /// Omitted skill uses the same explicitly selected row as the current
        /// browser/native animation definitions. Unknown skills never guess.
        func definition(weapon:Int,skill:Int?=nil)->Definition? {
            if let skill{return levels[weapon]?[skill]}
            return selected[weapon]
        }
        var weapons:[Int] {selected.keys.sorted()}
    }
    struct Pose {
        let weapon:Int
        let feet:V
        let actorToWorld:M
        let rightHand:M?
        let leftHand:M?
        var visible=true
    }
    struct Sample {
        let weapon:Int
        let skill:Int?
        let origin:V
        let safetyOrigin:V
        let handOrigin:V?
        let requestedLeft:Bool
        let usedLeft:Bool
        let fallbackReason:String?
        var posed:Bool {fallbackReason==nil}
    }
    static func bone(left:Bool)->Int {left ? 34:24}
    static func attachment(left:Bool)->M {
        left ? M(columns:(SIMD4(1,0,0,0),SIMD4(0,-1,0,0),SIMD4(0,0,-1,0),SIMD4(0,0,0,1))):matrix_identity_float4x4
    }
    static func sample(weapon:Int,left:Bool,feet:V,definition:Definition?,pose:Pose?)->Sample? {
        guard finite(feet) else{return nil}
        let safety=NativeShotTargeting.muzzle(feet:feet)
        guard finite(safety) else{return nil}
        func fallback(_ reason:String)->Sample {
            Sample(weapon:weapon,skill:definition?.skill,origin:safety,safetyOrigin:safety,handOrigin:nil,
                   requestedLeft:left,usedLeft:false,fallbackReason:reason)
        }
        if let pose,!pose.visible{return nil}
        guard let definition,definition.weapon==weapon else{return fallback("weapon-data-unavailable")}
        guard let pose else{return fallback("pose-unavailable")}
        guard pose.weapon==weapon else{return fallback("weapon-changed")}
        let tolerance=max(0.001,min(0.01,Float(simd_length(SIMD3<Double>(feet))*Double(Float.ulpOfOne)*4)))
        guard finite(pose.feet),simd_distance(pose.feet,feet)<=tolerance else{return fallback("stale-pose")}
        guard affine(pose.actorToWorld),simd_distance(V(pose.actorToWorld.columns.3.x,pose.actorToWorld.columns.3.y,pose.actorToWorld.columns.3.z),feet)<=tolerance else{return fallback("invalid-actor-transform")}
        guard let right=pose.rightHand,affine(right) else{return fallback("right-hand-unavailable")}
        let useLeft=left && definition.twin && pose.leftHand.map(affine)==true
        let hand=useLeft ? pose.leftHand!:right
        let weaponWorld=pose.actorToWorld*hand*attachment(left:useLeft)
        let point=weaponWorld*SIMD4(definition.offset,1),anchor=pose.actorToWorld*hand.columns.3
        let origin=V(point.x,point.y,point.z),handOrigin=V(anchor.x,anchor.y,anchor.z)
        // Same origin envelope enforced by the existing shot transport; a
        // corrupt rig/offset must not turn into a remote world-space muzzle.
        guard finite(origin),finite(handOrigin),point.w.isFinite,abs(point.w-1)<0.0001,
              simd_distance(SIMD3<Double>(origin),SIMD3<Double>(feet))<=15 else{return fallback("invalid-muzzle")}
        return Sample(weapon:weapon,skill:definition.skill,origin:origin,safetyOrigin:safety,handOrigin:handOrigin,
                      requestedLeft:left,usedLeft:useLeft,fallbackReason:nil)
    }
    private static func finite(_ value:V)->Bool {value.x.isFinite && value.y.isFinite && value.z.isFinite}
    private static func affine(_ value:M)->Bool {
        for c in 0..<4 {for r in 0..<4 where !value[c][r].isFinite{return false}}
        guard abs(value[0].w)<0.0001,abs(value[1].w)<0.0001,abs(value[2].w)<0.0001,abs(value[3].w-1)<0.0001 else{return false}
        let determinant=simd_determinant(simd_float3x3(columns:(V(value[0].x,value[0].y,value[0].z),V(value[1].x,value[1].y,value[1].z),V(value[2].x,value[2].y,value[2].z))))
        return determinant.isFinite && abs(determinant)>0.00000001
    }
}
