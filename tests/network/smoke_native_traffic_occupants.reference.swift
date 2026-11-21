// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CoreFoundation

/// Optional owner-local observations only. The repository contains no original
/// tables or captured reference rows. Readiness/animation/history are not run.
@main private enum TrafficOccupantReference {
    typealias O=NativeTrafficOccupants
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws{checks+=1;if !value{throw NSError(domain:message,code:1)}}
    static func integer(_ value:Any?,maximum:Int=65535)throws->Int {
        guard let n=value as?NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite,
              n.doubleValue.rounded(.towardZero)==n.doubleValue,(0...Double(maximum)).contains(n.doubleValue)else{throw NSError(domain:"Reference integer shape",code:1)}
        return n.intValue
    }
    static func main(){do{try run()}catch{print("FAIL \(error)");exit(1)}}
    static func run()throws {
        try check(CommandLine.arguments.count==4,"Supply owner catalog, private reference and result path")
        let catalog=try O.Catalog(data:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]));try check(data.count<=1_048_576,"Reference byte budget")
        guard let document=try JSONSerialization.jsonObject(with:data)as?[String:Any],
              let cases=document["cases"]as?[[String:Any]],!cases.isEmpty,cases.count<=1024 else{throw NSError(domain:"Reference document shape",code:1)}
        var compared:[String]=[],skipped:[[String:String]]=[],totalSteps=0
        for item in cases {
            let name=item["name"]as?String ?? "unnamed"
            guard let steps=item["steps"]as?[[String:Any]],!steps.isEmpty else{throw NSError(domain:"Reference step shape",code:1)}
            var firstLayout:[String:[Int]]=[:]
            for (index,step) in steps.enumerated() {
                totalSteps+=1;let label="\(name)/\(index+1)"
                guard let cars=step["cars"]as?[[String:Any]],let expected=step["expected"]as?[String:Any],
                      let visible=expected["visibleSeats"]as?[[String:Any]]else{throw NSError(domain:"Reference case shape",code:1)}
                var mutableBuiltLayout=false
                for car in cars {
                    // An unbuilt record has no mock built-object generation
                    // and cannot own the original layout cache.
                    if car["built"]as?Bool != true{continue}
                    let key="\(try integer(car["id"])):\(try integer(car["model"])):\(try integer(car["builtGeneration"]))"
                    guard let sides=car["seatSides"]as?[Int]else{throw NSError(domain:"Reference seat layout shape",code:1)}
                    if let old=firstLayout[key],old != sides{mutableBuiltLayout=true}
                    else{firstLayout[key]=sides}
                }
                if mutableBuiltLayout{skipped.append(["name":label,"reason":"Mutable layout on the same built object requires the original controller layout cache; outside stateless intent"]);continue}
                let externalState=cars.contains{car in
                    (car["readyBoundary"]as?Bool)==false || (car["actorAvailableBoundary"]as?Bool)==false ||
                    !(car["controllerStatesBoundary"]as?[String:String] ?? [:]).isEmpty
                }
                if externalState{skipped.append(["name":label,"reason":"Controller readiness/state is outside the stateless visible-seat intent planner"]);continue}
                guard let gangs=O.gangs(rows:item["gangRows"])else{
                    skipped.append(["name":label,"reason":"Malformed configured skin metadata is rejected by native admission"]);continue
                }
                let inputs=try cars.map{car -> O.Vehicle in
                    let count:Int?=car["count"]is NSNull ? nil:try integer(car["count"],maximum:255)
                    guard let distance=car["distance"]as?NSNumber,let sides=car["seatSides"]as?[Int]else{throw NSError(domain:"Reference seat/distance shape",code:1)}
                    let built=car["built"]as?Bool ?? false
                    // Zero is an unused carrier value only for an unbuilt
                    // record. The policy rejects it before selecting a seat.
                    let generation:UInt64=built ? UInt64(try integer(car["builtGeneration"])):0
                    return .init(id:UInt16(try integer(car["id"])),generation:generation,model:UInt16(try integer(car["model"])),
                        flags:UInt8(try integer(car["flags"],maximum:255)),count:count.map{UInt8($0)},deadSeats:UInt8(try integer(car["dead"],maximum:255)),
                        distance:distance.doubleValue,built:built,thrown:car["thrown"]as?Bool ?? false,seatSides:sides)
                }
                let result=O.seats(vehicles:inputs,catalog:catalog,gangs:gangs)
                let actual=result.map{"\($0.id):\($0.index):\($0.skin):\($0.dead)"}
                let desired=try visible.map{row in "\(try integer(row["carID"])):\(try integer(row["seat"],maximum:3)):\(try integer(row["skin"])):\(row["dead"]as?Bool ?? false)"}
                // The private observation fixture canonicalizes car/seat rows.
                // Compare the complete tuple multiset; neither iterator nor
                // draw order is asserted by this visible-intent-only gate.
                try check(actual.sorted()==desired.sorted(),"Archived visible-seat intent mismatch: \(label), actual=\(actual), expected=\(desired)")
                compared.append(label)
            }
        }
        try check(!compared.isEmpty,"No comparable source observations")
        let report:[String:Any]=["status":"PASS_SCOPED_VISIBLE_INTENT_POLICY","checks":checks,"comparedSteps":compared,"excludedSteps":skipped,
            "sourceTotalSteps":totalSteps,"scope":"Ready/inside visible-seat intent tuple multisets (carID/seat/skin/dead) only; actual archived observations with authored boundaries. Iterator/draw order, combat targets, controller allocation/disposal, stateful layout cache, loading, animation, rendering and retail acceptance remain separate."]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[3]))
        print("PASS scoped archived traffic occupant policy: \(compared.count)/\(totalSteps) steps / \(checks) checks; \(skipped.count) state/cache steps remain outside this gate")
    }
}
