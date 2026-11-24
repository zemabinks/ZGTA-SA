// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

enum ControlsFailure: Error { case failed(String) }
let address=CommandLine.arguments[1],reportURL=URL(fileURLWithPath:CommandLine.arguments[2])
let coordinateData=CommandLine.arguments.count>3 ? try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3])):nil
let coordinates=try coordinateData.map{try NativeSAMPVehicleCoordinates(metadata:$0)}
var checks=0,results=[[String:Any]](),activeCase=[String:Any]()
func require(_ condition:@autoclosure()->Bool,_ message:String)throws {
    checks+=1;if !condition(){throw ControlsFailure.failed(message)}
}
func exercise(_ version:NativeSAMPProtocol.Version)throws->[String:Any] {
    let profile=version == .dl ? "dl":"037",nickname="ZGTA_Controls_"+(version == .dl ? "DL":"037")
    let identity=try NativeSAMPProtocol.installationID(source:Data("0123456789ABCDEFGHIJ".utf8))
    let wire=NativeSAMPClient(address:address,nickname:nickname,version:version,installationID:identity)
    let adapter=NativeSAMPWorldConnection(client:wire,vehicleCoordinates:coordinates)
    let multiplayer=NativeMultiplayerClient(server:ServerAddress("http://127.0.0.1:8801")!,automaticRecoveryTimer:false,legacy:adapter)
    let observer=NativeSAMPClient(address:address,nickname:"ZGTA_Observer_"+profile,version:.v037,installationID:identity)
    let observerAdapter=coordinates.map{NativeSAMPWorldConnection(client:observer,vehicleCoordinates:$0)}
    var nativeVehicleSamples=[[String:Any]]()
    var events=[[String:Any]](),samples=[[String:Any]](),notes=[String](),states=[String](),enters=[String](),presence=[[String:Any]]()
    var passengerEntries = [(id: String, seat: Int, accepted: Bool)]()
    var gameplayEvents=[NativeSAMPGameplayCommands.Event]()
    var observerPoint=SIMD3<Float>(1510,-1720,13.5),subjectPoint=SIMD3<Float>(1510,-1720,13.5),phase="joining",lastObserver=Date.distantPast,lastSubject=Date.distantPast
    observerAdapter?.onVehicles={vehicles in for vehicle in vehicles{nativeVehicleSamples.append(["phase":phase,"id":vehicle.id,"position":[vehicle.position.x,vehicle.position.y,vehicle.position.z],"heading":vehicle.heading,"pitch":vehicle.pitch,"roll":vehicle.roll])}}
    multiplayer.onStatus={notes.append($0)}
    multiplayer.onConnectionState={states.append(String(describing:$0))}
    multiplayer.onEnter={id,accepted in enters.append("\(id):\(accepted)")}
    multiplayer.onPassengerEnter = { passengerEntries.append(($0, $1, $2)) }
    multiplayer.onPresence={count,names in presence.append(["count":count,"names":names,"phase":phase])}
    multiplayer.onLegacyEvent={event in
        let tag=event["t"]as?String ?? "?";events.append(["event":tag,"phase":phase,"at":Date().timeIntervalSince1970])
        if let command=event["event"]as?NativeSAMPGameplayCommands.Event{gameplayEvents.append(command)}
        if tag=="spawn" || tag=="position",let point=event["point"]as?SIMD3<Float>{subjectPoint=point}
        if tag=="class"{_=adapter.send(["t":"spawn"])}
    }
    observer.onClass={_ in observer.requestSpawn()}
    observer.onSpawn={observerPoint=$0.position}
    observer.onPosition={point,_ in observerPoint=point}
    observer.onStatus={notes.append("observer:"+$0)}
    observer.onPlayers={players in
        // Use the subject's actual server-assigned identity. Stream-out/in may
        // currently lose the client's cached global name; do not guess an ID.
        guard let target=wire.localID,let player=players.first(where:{$0.id==target})else{return}
        samples.append(["phase":phase,"at":Date().timeIntervalSince1970,"name":player.name,"vehicle":player.vehicle.map{Int($0)} ?? -1,
            "weapon":player.weapon,"position":[player.position.x,player.position.y,player.position.z],"velocity":[player.velocity.x,player.velocity.y,player.velocity.z]])
    }
    defer{activeCase=["profile":profile,"phase":phase,"states":states,"wireState":wire.state.rawValue,"notes":notes,"events":events,"observerSamples":samples,"nativeVehicleSamples":nativeVehicleSamples,"boardingCallbacks":enters];multiplayer.disconnect();observer.disconnect();withExtendedLifetime(observerAdapter){}}
    func network(_ body:SIMD3<Float>,_ q:SIMD4<Float>)throws->SIMD3<Float>{try coordinates?.root(body,model:411,rotation:q) ?? body}
    func close(_ a:SIMD3<Float>,_ b:SIMD3<Float>,_ tolerance:Float=0.001)->Bool{simd_distance(a,b)<tolerance}
    func tick(){
        wire.poll();observer.poll();multiplayer.tickConnection(now:ProcessInfo.processInfo.systemUptime)
        // A normal game starts its first on-foot sync after spawn. The server
        // cannot stream nearby vehicles until it receives that actual pose.
        if phase=="joining",multiplayer.isReady,Date().timeIntervalSince(lastSubject)>0.08 {
            multiplayer.sendPosition(subjectPoint,heading:0,moving:false,running:false,weapon:24)
            lastSubject=Date()
        }
        if observer.state == .spawned,Date().timeIntervalSince(lastObserver)>0.08 {
            var foot=NativeSAMPProtocol.Foot(position:observerPoint,heading:0);foot.health=100;foot.armour=25;foot.weapon=24
            _=observer.sendFoot(foot);lastObserver=Date()
        }
        RunLoop.current.run(until:Date().addingTimeInterval(0.005))
    }
    func wait(_ seconds:Double,until condition:()->Bool)throws {
        let deadline=Date().addingTimeInterval(seconds)
        while Date()<deadline && !condition(){tick()}
        try require(condition(),"\(profile): timed out during \(phase): \(notes.suffix(5))")
    }
    func begin(_ label:String)throws {
        phase=label;multiplayer.sendChat("/qa "+label)
        try wait(4,until:{multiplayer.chatMessages.contains(where:{$0.contains("QA:"+label)})})
    }
    func transmit(_ duration:Double,_ send:()->Void){
        let end=Date().addingTimeInterval(duration);var previous=Date.distantPast
        while Date()<end {
            if Date().timeIntervalSince(previous)>0.04{send();previous=Date()};tick()
        }
    }
    multiplayer.connect();observer.connect(automaticPolling:false)
    try wait(18,until:{multiplayer.isReady && observer.state == .spawned && !multiplayer.orderedVehicles.isEmpty})
    try require(multiplayer.inventoryConnection==nil && multiplayer.usesClientOwnedWeapons,"Legacy session fabricated independent inventory ownership")
    try require(wire.footMilliseconds==45 && wire.carMilliseconds==55 && wire.weaponMilliseconds==65,"Server-negotiated update rates lost: \(wire.footMilliseconds)/\(wire.carMilliseconds)/\(wire.weaponMilliseconds)")
    let car=try multiplayer.orderedVehicles.first(where:{$0.code.hasPrefix("411.")}).unwrap("Streamed stock411 missing")
    if let coordinates {
        let raw=try wire.vehicles[UInt16(car.id)!].unwrap("Raw streamed411 missing")
        let rotation=try NativeSAMPVehicleCoordinates.rotation(heading:raw.heading,pitch:raw.pitch,roll:raw.roll)
        let expectedBody=try coordinates.body(raw.position,model:411,rotation:rotation)
        try require(coordinates.count==212,"Coordinate-aware integration requires actual complete212-model owner catalog")
        try require(close(car.position,expectedBody),"Actual164 modelroot was not converted to nativebody")
        try require(simd_distance(car.position,raw.position)>0.1,"Coordinate-aware fixture accidentally used rawbody pose")
    }
    var input=NativeSAMPInput.State();input.sideways = -0.5;input.forward=1;input.crouch=true;input.fire=true;input.sprint=true;input.aim=true;input.special=1
    let footKeys=NativeSAMPInput.encode(input)
    func foot(_ keys:NativeSAMPInput.Frame,crouch:Bool=false){
        multiplayer.sendPosition(NativeSAMPPedCoordinates.feet(SIMD3(1513,-1720,13.5)),heading:0,moving:keys != .init(),running:input.sprint,
            weapon:24,crouching:crouch,velocity:.zero,legacyKeys:keys.keys,
            legacyAxes:SIMD2(keys.leftRight,keys.upDown),legacySpecialKeys:keys.special)
    }
    try begin("foot_pressed");transmit(0.7){foot(footKeys,crouch:true)}
    try begin("foot_released");transmit(0.5){foot(.init())}
    try require(samples.contains{$0["phase"]as?String=="foot_pressed" && $0["weapon"]as?Int==24 && $0["vehicle"]as?Int == -1},"Observer did not receive actual on-foot update")
    try begin("frozen");multiplayer.sendChat("/qa_freeze")
    try wait(4,until:{multiplayer.serverInputBlocked})
    try require(multiplayer.originalInputBlocked && !wire.controllable,"Compatibility input gate bypassed server freeze")
    transmit(0.35){foot(footKeys,crouch:true)}
    try require(!wire.enterVehicle(UInt16(car.id)!),"Frozen player queued driver boarding")
    multiplayer.sendChat("/qa_camera_behind")
    try wait(4,until:{gameplayEvents.last?.command == .cameraBehind})
    try require(multiplayer.serverInputBlocked,"Camera behind command released independent control freeze")
    multiplayer.sendChat("/qa_unfreeze");try wait(4,until:{!multiplayer.serverInputBlocked})
    multiplayer.sendChat("/qa_camera")
    try wait(4,until:{gameplayEvents.contains{$0.command == .cameraPosition(SIMD3(1500,-1700,30))} && gameplayEvents.contains{$0.command == .cameraLookAt(SIMD3(1510,-1720,15),.cut)}})
    multiplayer.sendChat("/qa_interpolate")
    try wait(4,until:{gameplayEvents.contains{$0.command == .cameraInterpolation(position:true,from:SIMD3(1500,-1700,30),to:SIMD3(1504,-1704,32),milliseconds:1500,cut:.move)} && gameplayEvents.contains{$0.command == .cameraInterpolation(position:false,from:SIMD3(1510,-1720,15),to:SIMD3(1512,-1722,16),milliseconds:1600,cut:.move)}})
    try begin("enter_request");multiplayer.requestEnter(car)
    try require(enters==[car.id+":true"],"Driver boarding callback must occur once without self-host ACK, got \(enters)")
    // The adapter's driver-enter callback is immediate after a queued realRPC26;
    // the server still confirms DRIVER through the first accepted InCar sync.
    var driver=NativeSAMPInput.State();driver.driving=true;driver.steering=1;driver.pitch=0.5;driver.throttle=1;driver.brake=1;driver.handbrake=true;driver.horn=true;driver.fire=true;driver.special=2
    let carKeys=NativeSAMPInput.encode(driver)
    func drive(_ keys:NativeSAMPInput.Frame){
        multiplayer.sendPosition(SIMD3(1515,-1720,13.5),heading:0,moving:true,running:false,vehicle:car,speed:0,
            vehicleHealth:900,weapon:28,velocity:.zero,legacyRotation:SIMD4(1,0,0,0),legacyKeys:keys.keys,
            legacyAxes:SIMD2(keys.leftRight,keys.upDown),legacySpecialKeys:keys.special)
    }
    try begin("car_pressed");transmit(0.8){drive(carKeys)}
    try require(samples.contains{$0["phase"]as?String=="car_pressed" && $0["vehicle"]as?Int==Int(car.id) && $0["weapon"]as?Int==28},"Observer did not receive driver vehicle/weapon after firstInCar")
    try begin("car_released");transmit(0.5){drive(.init())}
    try begin("exit_request")
    multiplayer.sendExit(NativeSAMPPedCoordinates.feet(SIMD3(1513,-1720,13.5)),parked:SIMD3(1515,-1720,13.5),heading:0,pitch:0,roll:0,vehicle:car,vehicleHealth:900)
    try begin("exit_foot");transmit(0.7){foot(.init())}
    try require(samples.contains{$0["phase"]as?String=="exit_foot" && $0["vehicle"]as?Int == -1 && $0["weapon"]as?Int==24},"Observer retained driver after exit and real on-foot sync")
    try require(enters.count==1,"Driver callback repeated during firstInCar/exit")
    let targetID=try wire.localID.unwrap("Real local player ID missing")
    try begin("passenger_sync")
    phase="forced_passenger";multiplayer.sendChat("/qa_passenger")
    try wait(4, until: { passengerEntries.contains { $0.id == car.id && $0.seat == 1 && $0.accepted } })
    try require(enters.count == 1 && passengerEntries.count == 1,
                "Server passenger assignment must board exactly one passenger and no driver")
    let passengerVehicle = try UInt16(car.id).unwrap("Invalid passenger test vehicle")
    let seatPoint = try wire.vehicles[passengerVehicle].unwrap("Missing passenger test vehicle").position
    let expectedHealth = multiplayer.health, expectedArmour = multiplayer.armour
    transmit(0.7) {
        multiplayer.sendPassengerPosition(NativeSAMPPedCoordinates.feet(seatPoint),
                                          heading: 0, action: 0, velocity: .zero, paused: false)
    }
    try wait(4, until: {
        guard let passenger = observer.players[targetID],
              case .seated(let vehicle, let seat) = passenger.passenger else { return false }
        return vehicle == passengerVehicle && seat == 1 && passenger.vehicle == nil
            && passenger.health == expectedHealth && passenger.armour == expectedArmour && passenger.weapon == 0
    })
    phase="forced_unseat";multiplayer.sendChat("/qa_unseat")
    try wait(4,until:{events.contains{$0["phase"]as?String=="forced_unseat" && $0["event"]as?String=="exitForced"}})
    multiplayer.sendPassengerPosition(NativeSAMPPedCoordinates.feet(seatPoint),
                                      heading: 0, action: 0, velocity: .zero, paused: false)
    transmit(0.25){foot(.init())}
    try wait(4, until: { observer.players[targetID].map { $0.passenger == nil } == true })
    try begin("passenger_request")
    try require(multiplayer.requestEnter(car, seat: 1), "Local passenger notification did not queue")
    try require(!multiplayer.requestEnter(car, seat: 1) && passengerEntries.count == 2,
                "A second local request must not duplicate the active passenger")
    transmit(0.6) {
        multiplayer.sendPassengerPosition(NativeSAMPPedCoordinates.feet(seatPoint),
                                          heading: 0, action: 0, velocity: .zero, paused: false)
    }
    try wait(4, until: {
        guard let player = observer.players[targetID],
              case .seated(let vehicle, let seat) = player.passenger else { return false }
        return vehicle == passengerVehicle && seat == 1 && player.vehicle == nil
    })
    try begin("passenger_leave")
    multiplayer.sendPassengerExit(NativeSAMPPedCoordinates.feet(seatPoint), heading: 0)
    try wait(4, until: { observer.players[targetID].map { $0.passenger == nil } == true })
    try require(presence.last?["count"]as?Int==2,"Full-server roster lost the local or observer player")
    try require((presence.last?["names"]as?[String])?.filter{$0==nickname}.count==1,"Local roster member duplicated")
    phase="stream_far";multiplayer.sendChat("/qa_far")
    try wait(4,until:{subjectPoint.x==2500})
    transmit(0.7){multiplayer.sendPosition(subjectPoint,heading:0,moving:false,running:false,weapon:24)}
    try wait(4,until:{observer.players[targetID]==nil})
    try require(observer.roster[targetID]==nickname,"Stream-out removed persistent137 name")
    try require(presence.last?["count"]as?Int==2,"Stream-out reduced full-server presence")
    phase="stream_home";multiplayer.sendChat("/qa_home")
    try wait(4,until:{subjectPoint.x==1510})
    transmit(0.7){multiplayer.sendPosition(subjectPoint,heading:0,moving:false,running:false,weapon:24)}
    try wait(4,until:{observer.players[targetID]?.name==nickname})
    try require(!samples.contains{($0["position"]as?[Float])==[0,0,0]},"137-only roster became phantom origin actor")
    try begin("spectating");multiplayer.sendChat("/qa_spec_player")
    try wait(4,until:{multiplayer.legacySpectating && gameplayEvents.contains{if case .spectatePlayer(let id,.fixed)=$0.command{return id==observer.localID};return false}})
    try require(multiplayer.serverInputBlocked && !wire.sendFoot(.init(position:SIMD3(1510,-1720,13.5),heading:0)),"Spectating leaked normal on-foot gameplay")
    transmit(0.4){_=multiplayer.sendSpectatorPosition(point:SIMD3(1490,-1720,20),keys:8,axes:SIMD2(-128,128))}
    multiplayer.sendChat("/qa_spec_vehicle")
    try wait(4,until:{gameplayEvents.contains{$0.command == .spectateVehicle(UInt16(car.id)!, .side)}})
    transmit(0.3){_=multiplayer.sendSpectatorPosition(point:SIMD3(1490,-1720,20),keys:0,axes:.zero)}
    let previousSpawns=events.filter{$0["event"]as?String=="spawn"}.count
    try begin("spectator_off");multiplayer.sendChat("/qa_spec_off")
    try wait(4,until:{!multiplayer.legacySpectating && events.filter{$0["event"]as?String=="spawn"}.count==previousSpawns+1})
    try require(!multiplayer.serverInputBlocked,"Server-authorized spectator respawn retained freeze")
    transmit(0.3){foot(.init())}
    // Driver cache must retain actual queued poses, not the original164
    // location. The final parked pose deliberately differs from both.
    try begin("cache_driver")
    multiplayer.requestEnter(car)
    let driven=SIMD3<Float>(1518,-1719,13.75),parked=SIMD3<Float>(1520,-1717,13.875)
    let firstQ=try coordinates == nil ? SIMD4<Float>(cos(0.1),0,0,sin(0.1)):NativeSAMPVehicleCoordinates.rotation(heading:0.6,pitch:0.3,roll:-0.25)
    let finalQ=try coordinates == nil ? (version == .dl ? SIMD4<Float>(cos(0.15),sin(0.15),0,0):firstQ):(version == .dl ? NativeSAMPVehicleCoordinates.rotation(heading:-0.7,pitch:-0.2,roll:0.4):firstQ)
    let drivenRoot=try network(driven,firstQ),parkedRoot=try network(parked,finalQ)
    transmit(0.4){multiplayer.sendPosition(driven,heading:0,moving:false,running:false,vehicle:car,vehicleHealth:875,weapon:28,legacyRotation:firstQ)}
    try require(wire.vehicles[UInt16(car.id)!]?.position==drivenRoot && wire.vehicles[UInt16(car.id)!]?.health==875,"Successful own200 did not cache actual rawnetwork pose/HP")
    if coordinates != nil {
        try wait(4,until:{nativeVehicleSamples.contains{row in guard row["phase"]as?String=="cache_driver",let p=row["position"]as?[Float],p.count==3 else{return false};return close(SIMD3(p[0],p[1],p[2]),driven,0.003)}})
        try require(samples.contains{row in guard row["phase"]as?String=="cache_driver",let p=row["position"]as?[Float],p.count==3 else{return false};return close(SIMD3(p[0],p[1],p[2]),drivenRoot)},"Observer did not receive modelroot across actualUDP200")
    }
    let vitalHP=multiplayer.legacyHealth,vitalAP=multiplayer.legacyArmour
    try begin("cache_exit")
    multiplayer.sendExit(NativeSAMPPedCoordinates.feet(SIMD3(1510,-1720,13.5)),parked:parked,heading:0,pitch:0,roll:0,vehicle:car,vehicleHealth:840,
        legacyRotation:version == .dl ? finalQ:nil)
    transmit(0.4){foot(.init())}
    let finalAngles=NativeSAMPProtocol.nativeAngles(finalQ)
    try require(wire.vehicles[UInt16(car.id)!]?.position==parkedRoot && wire.vehicles[UInt16(car.id)!]?.health==840,"Final queuedparked200 did not replace driver cache")
    try require(abs((wire.vehicles[UInt16(car.id)!]?.heading ?? 100)-finalAngles.heading)<0.0001 && abs((wire.vehicles[UInt16(car.id)!]?.pitch ?? 100)-finalAngles.pitch)<0.0001,"Final actual/fallback quaternion was discarded")
    try require(multiplayer.legacyHealth==vitalHP && multiplayer.legacyArmour==vitalAP,"Vehicle byte snapshot fed quantization into precise player vitals")
    try begin("cache_respawn")
    multiplayer.sendChat("/qa_spec_player");try wait(4,until:{multiplayer.legacySpectating})
    let cachedSpawnCount=events.filter{$0["event"]as?String=="spawn"}.count
    multiplayer.sendChat("/qa_spec_off")
    try wait(4,until:{!multiplayer.legacySpectating && events.filter{$0["event"]as?String=="spawn"}.count==cachedSpawnCount+1})
    let replayed=multiplayer.vehicles[car.id]?.position
    try require((coordinates == nil ? replayed==parked:replayed.map{close($0,parked)}==true) && multiplayer.vehicles[car.id]?.health==840,"Actualrespawn replay restored stale original/driver pose instead of finalpark")
    if coordinates != nil {
        try require(simd_distance(parkedRoot,parked)>0.1 && abs(parkedRoot.x-parked.x)>0.02 && abs(parkedRoot.y-parked.y)>0.02,"Full pitch/roll origin offset was not exercised")
        let replayedRoot=try coordinates!.root(multiplayer.vehicles[car.id]!.position,model:411,rotation:finalQ)
        try require(close(replayedRoot,parkedRoot),"Actualrespawn nativebody no longer maps to finalservermodelroot")
    }
    transmit(0.3){foot(.init())}
    phase="reentrant_spectator";multiplayer.sendChat("/qa_spec_player")
    try wait(4,until:{multiplayer.legacySpectating})
    let ordinaryLegacyEvents=multiplayer.onLegacyEvent
    multiplayer.onLegacyEvent={event in
        ordinaryLegacyEvents?(event)
        if let command=event["event"]as?NativeSAMPGameplayCommands.Event,command.command == .spectating(false){multiplayer.disconnect()}
    }
    multiplayer.sendChat("/qa_spec_off")
    try wait(4,until:{wire.state == .stopped})
    try require(!multiplayer.isReady && !multiplayer.serverInputBlocked && !multiplayer.legacySpectating,"Reentrant spectator callback revived a stopped world")
    phase="subject_disconnect";multiplayer.disconnect()
    try wait(4,until:{observer.roster[targetID]==nil && observer.players[targetID]==nil})
    return ["profile":profile,"nickname":nickname,"status":"PASS","states":states,"notes":notes,"boardingCallbacks":enters,
        "serverRates":[wire.footMilliseconds,wire.carMilliseconds,wire.weaponMilliseconds],"events":events,"observerSamples":samples,"presence":presence,
        "gameplayCommands":gameplayEvents.map{["generation":$0.generation,"sequence":$0.sequence,"command":String(describing:$0.command)]},
        "expectedFoot":["keys":Int(footKeys.keys),"special":Int(footKeys.special),"lr":Int(footKeys.leftRight),"ud":Int(footKeys.upDown),"weapon":24],
        "expectedCar":["keys":Int(carKeys.keys),"special":Int(carKeys.special),"lr":Int(carKeys.leftRight),"ud":Int(carKeys.upDown),"weapon":28],
        "coordinateMode":coordinates == nil ? "raw-protocol-probe":"actual-owner-212-model-catalog",
        "networkCarPressed":try {let p=try network(SIMD3(1515,-1720,13.5),SIMD4(1,0,0,0));return [p.x,p.y,p.z]}(),
        "nativeVehicleSamples":nativeVehicleSamples,
        "cachePoses":["initial":[car.position.x,car.position.y,car.position.z],"driver":[drivenRoot.x,drivenRoot.y,drivenRoot.z],"final":[parkedRoot.x,parkedRoot.y,parkedRoot.z],"driverBody":[driven.x,driven.y,driven.z],"finalBody":[parked.x,parked.y,parked.z]]]
}
extension Optional {func unwrap(_ message:String)throws->Wrapped{guard let value=self else{throw ControlsFailure.failed(message)};return value}}
do {
    for version in [NativeSAMPProtocol.Version.v037,.dl]{results.append(try exercise(version));RunLoop.current.run(until:Date().addingTimeInterval(1))}
    let report:[String:Any]=["status":"PASS","checks":checks,"cases":results]
    try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted]).write(to:reportURL)
    print("PASS: \(checks) actual NMP/adapter control+driver transitions across037 andDL; server callbacks validated separately")
}catch{
    let report:[String:Any]=["status":"FAIL","checks":checks,"cases":results,"activeCase":activeCase,"error":String(describing:error)]
    try?JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted]).write(to:reportURL)
    print("FAIL: \(error)");exit(1)
}
