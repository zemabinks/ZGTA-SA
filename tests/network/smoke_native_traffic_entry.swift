// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

@main enum TrafficEntryTests {
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws{checks+=1;if !value{throw NSError(domain:message,code:1)}}
    static func main()throws {
        var owner=NativeTrafficVehicleEntry()
        try check(!owner.request(17,at:.nan),"Invalid request clock")
        try check(owner.request(17,at:100),"First materialization request")
        try check(!owner.request(18,at:100.1) && owner.pending?.trafficID==17,"Second request replaced pending identity")
        let lookalike=NativeTrafficVehicleEntry.Vehicle(id:"t17",trafficID:nil)
        try check(owner.poll(at:100.1,vehicles:[lookalike],ready:{_ in true}) == .waiting,"Prefix became a binding")
        let other=NativeTrafficVehicleEntry.Vehicle(id:"other",trafficID:18)
        try check(owner.poll(at:100.2,vehicles:[other],ready:{_ in true}) == .waiting,"Unrelated registered row satisfied entry")
        let matching=NativeTrafficVehicleEntry.Vehicle(id:"arbitrary/registered",trafficID:17)
        try check(owner.poll(at:100.3,vehicles:[matching],ready:{_ in false}) == .waiting,"Unbuilt vehicle granted entry")
        try check(owner.poll(at:102.499,vehicles:[matching],ready:{$0==matching.id}) == .ready(matching.id),"Numeric binding did not preserve arbitrary registered ID")
        try check(owner.pending==nil && owner.poll(at:102.499,vehicles:[matching],ready:{_ in true}) == .waiting,"Ready request delivered twice")
        _=owner.request(17,at:200)
        try check(owner.poll(at:202.5,vehicles:[matching],ready:{_ in true}) == .expired && owner.pending==nil,"Exact request deadline accepted late model")
        _=owner.request(17,at:300);owner.cancel()
        try check(owner.poll(at:300.1,vehicles:[matching],ready:{_ in true}) == .waiting,"Cancelled/source-retired request admitted old row")
        _=owner.request(17,at:400)
        try check(owner.poll(at:399,vehicles:[],ready:{_ in true}) == .expired,"Clock rollback retained old request")
        for time in [Double.nan,Double.infinity,-Double.infinity] {
            _=owner.request(17,at:500);try check(owner.poll(at:time,vehicles:[matching],ready:{_ in true}) == .expired,"Invalid poll clock")
        }
        print("PASS native traffic entry: \(checks) checks; authored materialization identity/deadline/readiness/cancellation only, no server/drive or retail claim")
    }
}
