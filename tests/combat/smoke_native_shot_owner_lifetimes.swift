// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

@main struct Gate {
    static var checks=0
    static func check(_ value:Bool,_ label:String){checks+=1;if !value{print("FAIL: \(label)");exit(1)}}
    static func player(code:String="420",vehicle:String?="car",riding:String?=nil,seat:Int=0,skin:Int=7,alive:Bool=true,vehicleAlive:Bool=true)->NativeShotOwners.Player {
        .init(code:code,vehicle:vehicle,riding:riding,seat:seat,skin:skin,alive:alive,vehicleAlive:vehicleAlive)
    }
    static func main(){
        let owners=NativeShotOwners.Ledger<NativeShotOwners.Player>()
        check(owners.generation("p")==nil,"Unadmitted player acquired an incarnation")
        owners.receive(["p":player(),"other":player(vehicle:"other-car")])
        let first=owners.generation("p")!,other=owners.generation("other")!
        check(first != other,"Distinct player admissions shared an incarnation")
        owners.receive(["other":player(vehicle:"other-car"),"p":player()])
        check(owners.generation("p")==first && owners.generation("other")==other,"Ordinary reordered records retired live owners")
        owners.receive(["other":player(vehicle:"other-car")]);check(owners.generation("p")==nil,"Removed player retained admission")
        owners.receive(["p":player(),"other":player(vehicle:"other-car")]);check(owners.generation("p") != first,"Same-ID return inherited the retired pose")
        var previous=owners.generation("p")!
        for state in [player(skin:8),player(vehicle:"replacement"),player(code:"s7",vehicle:nil,riding:"car",seat:1),player(code:"s7",vehicle:nil,riding:"car",seat:2),player(alive:false),player(alive:true),player(vehicleAlive:false),player(vehicleAlive:true)] {
            owners.receive(["p":state]);let next=owners.generation("p")!
            check(next != previous,"Role, seat, skin or life transition retained an old incarnation")
            previous=next
        }
        owners.receive([:]);owners.receive(["p":player()]);check(owners.generation("p") != previous,"Reset/return reused an earlier admission")
        let vehicles=NativeShotOwners.Ledger<NativeShotOwners.Vehicle>()
        func vehicle(code:String="420",driver:String?=nil,traffic:UInt16?=nil,alive:Bool=true)->NativeShotOwners.Vehicle{.init(code:code,driver:driver,traffic:traffic,alive:alive)}
        vehicles.receive(["car":vehicle()]);let parked=vehicles.generation("car")!
        vehicles.receive(["car":vehicle()]);check(vehicles.generation("car")==parked,"Stable parked owner expired without a lifecycle change")
        var last=parked
        for state in [vehicle(driver:"p"),vehicle(),vehicle(code:"411"),vehicle(traffic:3),vehicle(alive:false),vehicle(alive:true)] {
            vehicles.receive(["car":state]);let next=vehicles.generation("car")!
            check(next != last,"Registered ownership/model/promotion/life change kept old pose")
            last=next
        }
        vehicles.receive([:]);vehicles.receive(["car":vehicle()]);check(vehicles.generation("car") != parked,"Reused registry ID retained retired model admission")
        check(owners.generation("car")==nil,"Vehicle admission leaked into the player namespace")
        print("PASS \(checks) actual shot-owner admission checks; authored records, no clock, geometry, App or retail claim")
    }
}
