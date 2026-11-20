// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

// Explicit controller seam for comparing policy calls with an offline archived
// replay. This does not execute animation, rendering, voice or world physics.
final class NativeSkeletalAnimationLibrary {}
struct NativeFootAnimationStyle {}
struct NativeFootWeaponAnimation {}
final class NPCFootSpy {
    struct GunAim {var pitch=0.0}
    struct Input {var position=SIMD3<Double>.zero;var heading=0.0,ratio=0.0;var crouch=false,guarding=false;var gun:GunAim?}
    struct Frame {var travel=SIMD2<Double>.zero;var steps:[String]=[],shots:[Bool]=[],shot=false,canopySamples:[Bool]=[]}
    var calls:[[String:Any]]=[]
    var walkSpeed=1.0,runSpeed=2.0
    init(library:NativeSkeletalAnimationLibrary,style:NativeFootAnimationStyle,random:()->Double){}
    func flinch(_ kind:String,stun:Bool=false){calls.append(["method":"flinch","kind":kind,"stun":stun])}
    func loseHead(){calls.append(["method":"loseHead"])}
    func rest(cut:Bool=false){calls.append(["method":"rest","cut":cut])}
    func die(_ kind:String,fallen:Bool=false){calls.append(["method":"die","kind":kind,"fallen":fallen])}
    func revive(){calls.append(["method":"revive"])}
    @discardableResult func act(_ clip:String,cut:Bool=false,once:Bool=false)->Bool {
        calls.append(["method":"act","kind":clip.replacingOccurrences(of:"ped/",with:""),"cut":cut,"once":once]);return true
    }
    func arm(_ weapon:NativeFootWeaponAnimation?){}
    func update(delta:Double,input:Input)->Frame{Frame()}
}

@main enum NPCReferenceTest {
    static var checks=0
    static func check(_ value:Bool,_ message:String){checks+=1;if !value{FileHandle.standardError.write(Data(("FAIL: "+message+"\n").utf8));exit(1)}}
    static func number(_ row:[String:Any],_ name:String)->Double{(row[name] as! NSNumber).doubleValue}
    static func integer(_ row:[String:Any],_ name:String)->Int{(row[name] as! NSNumber).intValue}
    static func expected(_ raw:[String:Any])->[String:Any] {
        let method=raw["method"] as! String
        var value:[String:Any]=["method":method]
        if let kind=raw["kind"] as? String{value["kind"]=kind}
        switch method {
        case "flinch":value["stun"]=false
        case "rest":value["cut"]=raw["restEnabled"] as! Bool
        case "die":value["fallen"]=raw["arriveLying"] as! Bool
        case "act":value["cut"]=raw["actCut"] as! Bool;value["once"]=raw["actOnce"] as! Bool
        default:break
        }
        return value
    }
    static func main()throws {
        let root=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))as! [String:Any]
        var cases=0,steps=0,excluded:[String]=[]
        for test in root["cases"] as! [[String:Any]] {
            let name=test["name"] as! String,rows=test["steps"] as! [[String:Any]]
            if rows.contains(where:{($0["mine"] as? Bool)==true || ($0["arriveLyingBefore"] as? Bool)==true || ($0["dispatch"] as? String)=="directQ" || number($0,"thrown")>0}) {
                excluded.append(name);continue
            }
            let npc=NativeAmbientPedestrianAnimation(library:.init(),style:.init(),weapons:[:],random:{0.25})
            for row in rows {
                let kind=row["dispatch"] as! String
                let heading=number(row,"nativeHeading"),from=number(row,"wireFrom")
                check(NativeAmbientPedestrianAnimation.incomingSide(wireFrom:from,nativeHeading:heading)==integer(row,"expectedSide"),name+" converted side")
                if kind=="direction"{steps+=1;continue}
                // Seed the explicit preexisting task state supplied by the
                // archived fixture. Only access control changes in this
                // policy carrier; no production app state is injected.
                npc.hits=(row["hitsSeenBefore"] as? NSNumber).map{UInt8($0.intValue)}
                npc.wasDown=row["fellBefore"] as! Bool;npc.faceDown=row["faceDownBefore"] as! Bool
                npc.hitUntil=(row["hitUntilBeforeMS"] as? NSNumber)?.doubleValue ?? -.infinity
                let state=NativeAmbientPedestrianProtocol.State(id:1,mood:0,burning:row["burning"] as! Bool,phone:false,
                    crouching:row["crouch"] as! Bool,cpr:false,weapon:0,hitWeapon:UInt8(integer(row,"hitWeapon")),
                    hitCounter:UInt8(integer(row,"hitCounter")),hitPiece:UInt8(integer(row,"piece")),hitFromWire:from,faceWire:0,foe:65535,thrown:0)
                let snapshot=NativeAmbientPedestrianAnimation.Snapshot(heading:heading,speed:number(row,"speed"),flags:UInt8(integer(row,"flags")),state:state)
                npc.animator.calls=[]
                _=npc.advance(delta:0,now:number(row,"timestampMS"),snapshot:snapshot)
                let included:Set<String> = kind=="down" ? ["rest","die","revive","act"]:["flinch","loseHead"]
                let actual=npc.animator.calls.filter{included.contains($0["method"] as! String)}
                let reference=(row["expectedControllerCalls"] as! [[String:Any]]).filter{included.contains($0["method"] as! String)}.map(expected)
                check(NSArray(array:actual).isEqual(to:reference),name+" actual policy calls \(actual) != \(reference)")
                if kind=="down" {
                    check(npc.wasDown==row["expectedFellAfter"] as! Bool,name+" persistent fall owner")
                    check(npc.faceDown==row["expectedFaceDownAfter"] as! Bool,name+" causal getup orientation")
                }else {
                    check(npc.hits==(row["expectedHitsSeenAfter"] as? NSNumber).map{UInt8($0.intValue)},name+" hit baseline")
                    let until=(row["expectedHitUntilAfterMS"] as? NSNumber)?.doubleValue ?? -.infinity
                    check(npc.hitUntil==until,name+" hit cooldown")
                }
                steps+=1
            }
            cases+=1
        }
        let report:[String:Any]=["status":"PASS","checks":checks,"cases":cases,"steps":steps,"excluded":excluded,
            "scope":"Actual independent policy source with renamed/mock common-controller type and test-accessible task fields; compared to captured archived dispatch/J/Q/X calls. Excludes voice/effects, thrown/runover/arrive-lying, direct unguarded Q, animation/rendered/retail acceptance."]
        print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
    }
}
