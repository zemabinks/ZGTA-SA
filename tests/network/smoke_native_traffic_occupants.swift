// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

@main enum TrafficOccupantTests {
    typealias O=NativeTrafficOccupants
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws {
        checks+=1;if !value{throw NSError(domain:message,code:1)}
    }
    // These are independently authored tables and vehicle/seat records.
    // Original skin lists, observations and game resources are not embedded.
    static let catalogData=Data(#"{"schema":1,"fallback":[5,6,7],"overrides":{"400":8},"hiddenModels":[401]}"#.utf8)
    static func vehicle(_ id:UInt16=2,model:UInt16=402,flags:UInt8=0,count:UInt8?=nil,dead:UInt8=0,
                        distance:Double=10,built:Bool=true,thrown:Bool=false,sides:[Int]=[-1,1,-1])->O.Vehicle {
        .init(id:id,generation:9,model:model,flags:flags,count:count,deadSeats:dead,
            distance:distance,built:built,thrown:thrown,seatSides:sides)
    }
    static func main(){do{try run()}catch{print("FAIL \(error)");exit(1)}}
    static func run()throws {
        let catalog=try O.Catalog(data:catalogData)
        let first=O.Gang(skins:[0,10],cars:[400,402])!,second=O.Gang(skins:[11],cars:[402])!
        func seats(_ values:[O.Vehicle],_ gangs:[O.Gang]=[])->[O.Seat]{O.seats(vehicles:values,catalog:catalog,gangs:gangs)}
        let fallback=seats([vehicle()])
        try check(fallback.count==1 && fallback[0].skin==7,"Deterministic fallback selection")
        try check(fallback[0].targetID=="c2.0" && fallback[0].generation==9 && fallback[0].model==402,"Typed occupant identity/lifetime")
        try check(seats([vehicle(model:400)])[0].skin==8,"Model override selection")
        try check(seats([vehicle(flags:0)], [second])[0].skin==7,"Crew configuration bypassed flag128")
        let configured=seats([vehicle(3,flags:128)],[first,second])
        try check(configured.map(\.skin)==[10,0,10],"Ordered crew lookup and per-seat ID seed")
        try check(configured.map(\.index)==[0,1,2],"Truthy crew default count")
        let zero=seats([vehicle(2,flags:128)],[first,second])
        try check(zero.count==1 && zero[0].skin==0,"Skin0 lost nullish selection or became truthy default crew")
        try check(seats([vehicle(2,flags:128,count:3)],[first]).map(\.skin)==[0,0,0],"Falsy primary must reuse driver skin")
        try check(seats([vehicle(count:0)]).map(\.index)==[0],"Explicit count0 removed driver")
        try check(seats([vehicle(count:2)]).map(\.index)==[0,1],"Explicit passenger count")
        try check(seats([vehicle(count:255)]).map(\.index)==[0,1,2],"Compact generated a fourth seat")
        try check(seats([vehicle(count:3,sides:[-1,1,1])]).map(\.index)==[0,1],"Rear seat side guard")
        try check(seats([vehicle(count:3,sides:[-1])]).map(\.index)==[0],"Unavailable seat metadata")
        try check(seats([vehicle(count:3,sides:[])]).isEmpty,"Missing vehicle seat layout")
        let dead=seats([vehicle(count:3,dead:5)])
        try check(dead.map(\.dead)==[true,false,true],"Per-seat dead flags changed count or wrong bits")
        try check(seats([vehicle(model:401,count:3)]).isEmpty,"Hidden rider model produced occupants")
        try check(seats([vehicle(flags:32,count:3)]).isEmpty,"Suppressed compact occupants")
        try check(seats([vehicle(thrown:true)]).isEmpty,"Thrown compact controllers retained")
        try check(seats([vehicle(built:false)]).isEmpty,"Unbuilt vehicle produced riders")
        for value in [45.0,-1,.nan,.infinity] {
            try check(seats([vehicle(distance:value)]).isEmpty,"Invalid/exact-boundary occupant distance")
        }
        let ranked=(0..<7).map{vehicle(UInt16($0),flags:$0<6 ? 32:0,distance:Double($0))}
        try check(seats(ranked).isEmpty,"Flag suppression incorrectly freed an earlier rank")
        let tied=(0..<7).reversed().map{vehicle(UInt16($0),distance:10)}
        try check(seats(tied).map(\.id)==[6,5,4,3,2,1],"Equal-distance input order changed")
        try check(O.Gang(skins:[],cars:[402])==nil && O.Gang(skins:[-1],cars:[402])==nil,"Malformed configured skin admission")
        let rows:[[Any]]=[["authored",0,[0,10],[400,402]],["later",0,[11],[402]]]
        let decoded=O.gangs(rows:rows)
        try check(decoded?.count==2 && decoded?[0].skins==[0,10] && decoded?[1].cars==[402],"Negotiated crew row order/identity")
        try check(O.gangs(rows:[[Any]]())?.isEmpty==true,"Empty crew update")
        try check(O.gangs(rows:[["empty",0,[],[400]]])?.isEmpty==true,"Empty skin row should supply no crew choice")
        for rows:Any in [NSNull(),[["short",0]],[["bad",0,[true],[400]]],[["bad",0,[-1],[400]]],[["bad",0,[65536],[400]]]] {
            try check(O.gangs(rows:rows)==nil,"Malformed negotiated crew update")
        }
        let nullable=O.gangs(rows:[["nullable",0,[10,NSNull(),12],[402]]])
        try check(nullable != nil,"Nullable crew metadata rejected")
        try check(seats([vehicle(0,flags:128)],nullable ?? []).map(\.skin)==[10,10,12],"Null passenger did not fall back to driver skin")
        let mixed=O.gangs(rows:[["mixed",0,[11],["402",true,402.5,402,65536]]])
        try check(mixed?.first?.cars==[402],"Strict numeric model matching accepted a non-model value")
        let emptyPrimary=O.gangs(rows:[["nullable",0,[NSNull(),12],[400]]])
        try check(seats([vehicle(0,model:400,flags:128)],emptyPrimary ?? []).map(\.skin)==[8],"Null primary did not use model override")
        try check(O.Gang(skins:[65535],cars:[400]) != nil,"Native16bit skin identity was narrowed")
        for text in [#"{"schema":2,"fallback":[5],"overrides":{},"hiddenModels":[]}"#,
                     #"{"schema":1,"fallback":[],"overrides":{},"hiddenModels":[]}"#,
                     #"{"schema":1,"fallback":[true],"overrides":{},"hiddenModels":[]}"#,
                     #"{"schema":1,"fallback":[5],"overrides":{"0400":8},"hiddenModels":[]}"#,
                     #"{"schema":1,"fallback":[5],"overrides":{"400":-1},"hiddenModels":[]}"#] {
            var rejected=false;do{_=try O.Catalog(data:Data(text.utf8))}catch{rejected=true}
            try check(rejected,"Malformed catalog admitted")
        }
        print("PASS compact traffic occupant policy: \(checks) checks; authored tables and seats, no models/animation/rendering/server or retail acceptance")
    }
}
