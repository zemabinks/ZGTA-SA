// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
enum VitalsFailure:Error{case failed(String)}
var checks=0
func check(_ value:@autoclosure()->Bool,_ label:String)throws{checks+=1;if !value(){throw VitalsFailure.failed(label)}}
func close(_ a:Double,_ b:Double)->Bool{abs(a-b)<0.00000001}
func math()throws{
    for fps in [15,20,24,30,50,60,75,90,120,144]{
        var v=NativeSAMPLocalVitals();try check(v.seed(health:80.75,armour:25.5),"fractional seed")
        for _ in 0..<(12*fps){try check(v.hurt(3.125/Double(fps),weapon:53) != nil,"fractional drowning at \(fps)fps")}
        try check(close(v.health,43.25) && v.armour==25.5 && v.displayHealth==44 && v.wireHealth==43,"frame-rate damage/HUD/wire drift at \(fps)fps: \(v)")
        try check(v.hurt(30.25,weapon:0)?.absorbed==25.5 && close(v.health,38.5) && v.armour==0,"ordinary armour split")
        try check(v.seed(health:1.125,armour:12.5),"fatal seed")
        try check(v.hurt(0.25,weapon:53)?.killed==true && v.dead && v.health==0 && v.displayHealth==0 && v.wireHealth==0 && v.armour==12.5 && v.fatalCause == .init(weapon:53,source:65535),"fatal drowning lost fraction/cause")
        try check(v.hurt(1,weapon:54)==nil && v.fatalCause?.weapon==53,"dead repeated hit changed cause")
        v.reset();try check(v.health==100 && v.armour==0 && !v.dead && v.fatalCause==nil,"spawn resets exact vital owner")
    }
    var v=NativeSAMPLocalVitals()
    for amount in [Double.nan,.infinity,-.infinity,-1,0,10001,Double.leastNonzeroMagnitude]{try check(v.hurt(amount,weapon:53)==nil,"invalid damage")}
    for weapon in [-1,55,255]{try check(v.hurt(1,weapon:weapon)==nil,"invalid weapon")}
    for body in [-1,0,2,10]{try check(v.hurt(1,weapon:53,body:body)==nil,"invalid body")}
    try check(!v.seed(health:.nan) && v.health==100 && v.armour==0,"invalid server seed poisoned state")
    try check(v.seed(health:8.875,armour:9.25) && v.seed(armour:3.5) && v.health==8.875,"partial server setter erased other fraction")
    try check(v.hurt(8,weapon:54,source:123)?.killed==true && v.armour==3.5 && v.fatalCause == .init(weapon:54,source:123),"fall bypass/cause")
    try check(v.seed(health:25.75) && !v.dead && v.fatalCause==nil && v.armour==3.5,"server health setter did not clear old fatal cause")
    try check(v.seed(health:1000.5,armour:1000.25) && v.displayHealth==1001 && v.displayArmour==1001 && v.wireHealth==255 && v.wireArmour==255,"high server vital values were silently capped")
    try check(v.hurt(100.125,weapon:54) != nil && v.health==900.375 && v.armour==1000.25,"fractional damage with high server vitals")
    for value in [Double.nan,.infinity,-.infinity,-0.00001,1_000_000.25]{
        try check(!v.seed(health:value) && !v.seed(armour:value) && v.health==900.375 && v.armour==1000.25,"invalid bounded server vital seed")
    }
    try check(v.seed(health:1_000_000,armour:1_000_000) && v.wireHealth==255 && v.displayHealth==1_000_000,"bounded maximum seed")
    try check(v.kill(weapon:51) && v.health==0 && v.armour==1_000_000 && v.fatalCause?.weapon==51,"Explicit vehicle fatal lost cause/armour")
    try check(!v.kill(weapon:54) && v.fatalCause?.weapon==51,"Repeated fatal overwrote firstcause")
    v.reset();try check(!v.kill(weapon:55) && !v.dead,"Invalid fatal cause accepted")
    try check(v.kill(weapon:255) && v.dead && v.fatalCause?.weapon==255,"Untypedfatal inventedfallcause")
}
func network(_ profile:NativeSAMPProtocol.Version,_ address:String)throws->[String:Any]{
    let label=profile == .dl ? "dl":"037",nickname="ZGTA_Vitals_"+label
    let id=try NativeSAMPProtocol.installationID(source:Data("0123456789ABCDEFGHIJ".utf8))
    let wire=NativeSAMPClient(address:address,nickname:nickname,version:profile,installationID:id)
    let adapter=NativeSAMPWorldConnection(client:wire)
    let n=NativeMultiplayerClient(server:ServerAddress("http://127.0.0.1:8801")!,automaticRecoveryTimer:false,legacy:adapter)
    var notes=[String](),events=[String](),presence=[Int](),point=SIMD3<Float>(1510,-1720,12.5),phase="join"
    n.onStatus={notes.append($0)}
    n.onPresence={count,_ in presence.append(count)}
    n.onLegacyEvent={event in
        let tag=event["t"]as?String ?? "?";events.append(tag)
        if tag=="class"{_=adapter.send(["t":"spawn"])}
        if let p=event["point"]as?SIMD3<Float>{point=p}
    }
    defer{n.disconnect()}
    func tick(){wire.poll();n.tickConnection(now:ProcessInfo.processInfo.systemUptime);RunLoop.current.run(until:Date().addingTimeInterval(0.005))}
    func wait(_ seconds:Double=4,until condition:()->Bool)throws{
        let end=Date().addingTimeInterval(seconds);while Date()<end && !condition(){tick()}
        try check(condition(),"\(label) \(phase) timeout: \(notes.suffix(6))")
    }
    func begin(_ name:String)throws{phase=name;n.sendChat("/qa "+name);try wait(until:{n.chatMessages.contains{$0.contains("VITALS:"+name)}})}
    func seed(_ command:String,_ hp:Double,_ ap:Double)throws{
        n.sendChat(command);try wait(until:{n.legacyHealth==hp && n.legacyArmour==ap})
    }
    func sync(_ vehicle:RemoteVehicle?=nil){
        let end=Date().addingTimeInterval(0.25);var last=Date.distantPast
        while Date()<end{
            if Date().timeIntervalSince(last)>0.04{n.sendPosition(point,heading:0,moving:false,running:false,vehicle:vehicle,weapon:24,legacyRotation:SIMD4(1,0,0,0));last=Date()};tick()
        }
    }
    n.connect();try wait(18,until:{n.isReady && wire.state == .spawned && n.legacyArmour==25});sync()
    try check(n.inventoryConnection==nil,"legacy health acquired selfhostACK namespace")
    try begin("high");try seed("/qa_high",1000.5,1000.25)
    try check(n.health==1001 && n.armour==1001 && wire.preciseHealth==1000.5 && wire.preciseArmour==1000.25,"high FloatRPC14/66 silently capped")
    try check(n.reportLegacyDamage(0.125,weapon:53) && n.legacyHealth==1000.375 && n.legacyArmour==1000.25,"high fractional local damage")
    sync();try check(wire.health==255 && n.legacyHealth==1000.375,"high byte saturation fed back into local state")
    try begin("fraction");try seed("/qa_seed",35.75,12.5)
    try check(n.health==36 && n.armour==13 && wire.preciseHealth==35.75 && wire.preciseArmour==12.5,"RPC14/66 truncated exact/HUD values")
    for _ in 0..<10{try check(n.reportLegacyDamage(0.125,weapon:53),"local fractional drowning rejected")}
    try check(n.legacyHealth==34.5 && n.legacyArmour==12.5 && n.health==35 && n.armour==13,"fractional hits rounded each frame")
    sync();try check(wire.health==34 && wire.armour==12 && n.legacyHealth==34.5,"outgoing sync quantization fed back into local values")
    try begin("armour");try seed("/qa_armour",80.75,25.5)
    try check(n.reportLegacyDamage(26.25,weapon:0) && n.legacyHealth==80 && n.legacyArmour==0,"armour absorption")
    sync()
    try begin("fall");try seed("/qa_seed",35.75,12.5)
    n.reportImpactDamage(2);n.reportLocalHealth(32)
    try check(n.legacyHealth==32 && n.legacyArmour==12.5,"impact/local health consumed armour or fractional amount")
    sync()
    try begin("fatal_drown");try seed("/qa_fatal",1.125,12.5)
    try check(n.reportLegacyDamage(0.25,weapon:53) && n.health==0 && n.legacyArmour==12.5 && n.legacyDeathReason==53,"fatal drown did not preserve exact threshold/cause")
    sync();try wait(until:{wire.state == .wasted});sync()
    try check(!n.reportLegacyDamage(1,weapon:54) && n.legacyDeathReason==53,"repeated fatal damage overwrote original cause")
    n.respawn();try wait(until:{wire.state == .spawned && n.legacyHealth==100 && n.legacyArmour==25})
    try check(n.legacyDeathReason==255,"real spawn retained previous fatal reason")
    try check(presence.last==1,"real respawn lost unchanged full-server roster presence")
    sync();try wait(until:{!n.orderedVehicles.isEmpty})
    let car=n.orderedVehicles[0]
    try begin("fatal_driver");try seed("/qa_fatal",1.125,12.5)
    n.requestEnter(car);sync(car)
    try check(n.reportLegacyDamage(0.25,weapon:54),"driver fall damage rejected");sync(car)
    try wait(until:{wire.state == .wasted})
    n.respawn();try wait(until:{wire.state == .spawned && n.legacyHealth==100 && n.legacyArmour==25});sync()
    try begin("fatal_wreck")
    try check(n.reportLegacyFatal(weapon:51) && n.legacyArmour==25 && n.legacyDeathReason==51,"Explicit wreck kill lost its exactcause")
    try check(!n.reportLegacyFatal(weapon:54) && n.legacyDeathReason==51,"Repeatedfatal overwrotewreck")
    sync();try wait(until:{wire.state == .wasted})
    n.respawn();try wait(until:{wire.state == .spawned && n.legacyHealth==100 && n.legacyArmour==25});sync()
    try begin("fatal_unknown")
    n.reportLocalHealth(0)
    try check(n.health==0 && n.legacyArmour==25 && n.legacyDeathReason==255,"Absolutecompatibilityzero inventedfall54")
    sync();try wait(until:{wire.state == .wasted})
    return ["status":"PASS","profile":label,"nickname":nickname,"notes":notes,"events":events]
}
do{
    try math()
    var cases=[[String:Any]]()
    if CommandLine.arguments.count>2{for profile in [NativeSAMPProtocol.Version.v037,.dl]{cases.append(try network(profile,CommandLine.arguments[1]));RunLoop.current.run(until:Date().addingTimeInterval(1))}}
    let report:[String:Any]=["status":"PASS","checks":checks,"cases":cases]
    if CommandLine.arguments.count>2{try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))}
    print("PASS \(checks) fractional legacy vital checks; actual profiles \(cases.count)")
}catch{
    let report:[String:Any]=["status":"FAIL","checks":checks,"error":String(describing:error),"cases":[[String:Any]]()]
    if CommandLine.arguments.count>2{try?JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))}
    FileHandle.standardError.write(Data("FAIL: \(error)\n".utf8));exit(1)
}
