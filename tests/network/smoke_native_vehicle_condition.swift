// SPDX-License-Identifier: AGPL-3.0-only
// Actual NativeMultiplayerClient decoder and URLSession transport. No renderer.
let client=NativeMultiplayerClient(server:ServerAddress(CommandLine.arguments[1])!)
let condition="3434012122110101201",vehicleID="authored-condition"
var phase=0,checks=0
func check(_ value:Bool,_ why:String){checks+=1;if !value{print("FAIL \(why)");exit(1)}}
func confirm(_ token:String){
    client.sendChat(token)
    client.sendPosition(SIMD3(100,100,20),heading:0,moving:false,running:false)
}
func drivingCondition(){
    check(client.players.count==1,"Actual received driving roster")
    guard let driver=client.players.values.first,let car=client.vehicles[vehicleID]else{check(false,"Received driver and registered hull");return}
    check(driver.vehicleID==vehicleID && driver.code==car.code,"Shared received identity")
    check(driver.vehicleHealth==645 && car.health==645,"Received authoritative health agrees")
    check(driver.vehicleDamage==condition && car.damage==condition,"Received authoritative damage agrees")
    check(driver.skin==7 && driver.life==100,"Condition reconciliation preserves driver identity and actor life")
}
client.onStatus={text in
    switch text {
    case "CORE184_BASELINE":
        check(phase==0 && client.isReady,"Baseline belongs to one ready connection")
        drivingCondition();phase=1;confirm("CORE184_BASELINE_OK")
    case "CORE184_QUEUED":
        check(phase==1,"Queued driver state ordering")
        drivingCondition();phase=2;confirm("CORE184_QUEUED_OK")
    case "CORE184_PARKED":
        check(phase==2,"Actual parked release ordering")
        check(client.players.count==1 && client.players.values.first?.vehicleID==nil,"Release restores received foot ownership")
        check(client.players.values.first?.life==100 && client.players.values.first?.skin==7,"Foot identity and life remain intact")
        check(client.vehicles[vehicleID]?.health==645 && client.vehicles[vehicleID]?.damage==condition,"Parked actor and hull packets retain authoritative condition")
        phase=3;confirm("CORE184_PARKED_OK")
    case "CORE184_DONE":
        check(phase==6,"All confirmations reached actual server")
        client.disconnect();check(client.vehicles.isEmpty && client.players.isEmpty,"Disconnect clears received lifetimes")
        print("PASS \(checks) actual native URLSession condition checks: baseline, queued driver, parked release and disconnect; no App, rendered browser, hardware or retail claim")
        exit(0)
    case "CORE184_UNATTENDED":
        check(phase==3,"Unattended state follows accepted release")
        check(client.vehicles[vehicleID]?.health==645 && client.vehicles[vehicleID]?.damage==condition,"Unattended motion cannot repair the received hull")
        check(client.players.values.first?.vehicleID==nil,"Unattended motion cannot grant a driving role")
        phase=4;confirm("CORE184_UNATTENDED_OK")
    case "CORE184_BUMPED":
        check(phase==4,"Later collision follows parked publication")
        check(client.vehicles[vehicleID]?.health==500 && client.vehicles[vehicleID]?.damage=="0000000000000000001","Retained parked row cannot reverse a later hull condition")
        check(client.vehicles[vehicleID]?.position==SIMD3(101,100,20),"Retained parked row cannot reverse a later body position")
        phase=5;confirm("CORE184_BUMPED_OK")
    case "CORE184_REPLACED":
        check(phase==5,"Replacement follows the old parked lifetime")
        check(client.vehicles[vehicleID]?.health==1000 && client.vehicles[vehicleID]?.damage=="fresh","Previous parked lifetime cannot overwrite replacement condition")
        check(client.vehicles[vehicleID]?.position==SIMD3(103,100,20),"Previous parked lifetime cannot overwrite replacement pose")
        phase=6;confirm("CORE184_REPLACED_OK")
    default:break
    }
}
client.connect()
DispatchQueue.main.asyncAfter(deadline:.now()+20){print("FAIL condition receiving test phase \(phase), state \(client.state)");exit(1)}
RunLoop.main.run()
