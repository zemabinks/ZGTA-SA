// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Original-world grouping is a transport policy, separate from inventory.
/// A batch represents one firing marker even when it contains several targets.
enum NativeLocalShotPackets {
    static func original(weapon:Int,claims:[NativeLocalShots.Claim])->[[String:Any]]? {
        guard NativeLocalShots.weapons.contains(weapon),!claims.isEmpty,claims.count<=100 else{return nil}
        var packets:[[String:Any]]=[]
        for claim in claims {
            guard NativeLocalShots.finite(claim.origin),NativeLocalShots.finite(claim.end),
                  (0...4).contains(claim.kind),(1...100).contains(claim.pellets),
                  claim.kind==claim.target?.kind || (claim.target==nil && (claim.kind==0 || claim.kind==4))else{return nil}
            func point(_ value:SIMD3<Double>)->[Double]? {
                let scaled=[value.x*100,value.y*100,value.z*100]
                guard scaled.allSatisfy(\.isFinite)else{return nil}
                // JavaScript's rounding chooses +infinity at negative halves.
                return scaled.map{floor($0+0.5)/100}
            }
            guard let origin=point(claim.origin),let end=point(claim.end)else{return nil}
            var row:[String:Any]=["t":"shot","w":weapon,"o":origin,"h":end,"ht":claim.kind]
            if let target=claim.target {
                guard !target.id.isEmpty,target.id.utf8.count<=64,(1...3).contains(target.kind)else{return nil}
                row["id"]=target.id
                if let piece=target.piece {guard (1...9).contains(piece)else{return nil};row["bp"]=piece}
                if let wheel=target.wheel {guard target.kind != 1,(0...3).contains(wheel)else{return nil};row["wh"]=wheel}
            }
            if claim.pellets>1{row["n"]=claim.pellets}
            packets.append(row)
        }
        guard claims.reduce(0,{$0+$1.pellets})<=100 else{return nil}
        return packets
    }
}
