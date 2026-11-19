// SPDX-License-Identifier: AGPL-3.0-only
// Actual decoder/adapter regressions. Packet fixtures are not a live join.
import Foundation
var checks=0
func check(_ value:@autoclosure()->Bool,_ message:String){checks+=1;precondition(value(),message)}
func payload(_ fill:(inout NativeSAMPProtocol.Writer)->Void)->NativeSAMPProtocol.Writer{var w=NativeSAMPProtocol.Writer();fill(&w);return w}
func rpc(_ client:NativeSAMPClient,_ id:UInt8,_ fill:(inout NativeSAMPProtocol.Writer)->Void)throws{try client.receive(NativeSAMPProtocol.rpc(id,payload(fill)))}
func remoteFoot(_ id:UInt16,_ point:SIMD3<Float>)->Data{
    var w=NativeSAMPProtocol.Writer();w.integer(207,size:1);w.integer(UInt32(id),size:2)
    w.bit(false);w.bit(false);w.integer(0,size:2);w.vector(point)
    for _ in 0..<4{w.bit(false)};for _ in 0..<3{w.integer(0,size:2)}
    w.integer(255,size:1);w.integer(24,size:1);w.integer(0,size:1);w.float(0);return w.data
}
func remoteCar(_ id:UInt16,_ point:SIMD3<Float>)->Data{
    var w=NativeSAMPProtocol.Writer();w.integer(200,size:1);w.integer(UInt32(id),size:2);w.integer(1,size:2)
    for _ in 0..<3{w.integer(0,size:2)};for _ in 0..<4{w.bit(false)};for _ in 0..<3{w.integer(0,size:2)}
    w.vector(point);w.float(0);w.integer(900,size:2);w.integer(255,size:1);w.integer(28,size:1);return w.data
}
for version in [NativeSAMPProtocol.Version.v037,.dl]{
    let client=NativeSAMPClient(address:"127.0.0.1:1",nickname:"Local_QA",version:version,installationID:"A")
    let adapter=NativeSAMPWorldConnection(client:client)
    let multiplayer=NativeMultiplayerClient(server:ServerAddress("http://127.0.0.1:1")!,automaticRecoveryTimer:false,legacy:adapter)
    var actors=[[RemotePlayer]](),presence=[Int](),events=[[String:Any]](),teleports=[SIMD3<Float>]()
    multiplayer.onPlayers={actors.append($0)};multiplayer.onPresence={count,_ in presence.append(count)}
    multiplayer.onLegacyEvent={events.append($0)}
    multiplayer.onTeleport={point,_ in teleports.append(point)}
    var compatibilityVitals=[(Int?,Int?)]()
    client.onVitals={compatibilityVitals.append(($0,$1))}
    try rpc(client,14){$0.float(1000.5)};try rpc(client,66){$0.float(1000.25)}
    check(client.preciseHealth==1000.5 && client.preciseArmour==1000.25 && multiplayer.legacyHealth==1000.5 && multiplayer.legacyArmour==1000.25,"Actual RPC14/66 lost high fractional values")
    check(multiplayer.health==1001 && multiplayer.armour==1001 && compatibilityVitals.last?.1==1000,"HUDceil or existing integer callback changed")
    for id in [UInt8(14),66]{for value in [Float.nan,.infinity,-.infinity,-1,1_000_001]{
        do{try rpc(client,id){$0.integer(value.bitPattern,size:4)};preconditionFailure("Invalid precise vital RPC accepted")}
        catch NativeSAMPProtocol.Error.invalid{}
        check(client.preciseHealth==1000.5 && client.preciseArmour==1000.25 && multiplayer.legacyHealth==1000.5 && multiplayer.legacyArmour==1000.25,"Rejected precise vital RPC mutated state")
    }}
    func join(_ id:UInt16,_ name:String)throws{try rpc(client,137){$0.integer(UInt32(id),size:2);$0.integer(0,size:4);$0.integer(0,size:1);$0.text8(Data(name.utf8))}}
    func stream(_ id:UInt16,base:Int=287,custom:Int=20001)throws{
        try rpc(client,32){w in w.integer(UInt32(id),size:2);w.integer(0,size:1);w.integer(UInt32(base),size:4)
            if version == .dl{w.integer(UInt32(bitPattern:Int32(custom)),size:4)}
            w.vector(SIMD3(100,200,300));w.float(90);w.integer(0,size:4)}
    }
    func skin(_ id:UInt16,base:Int=287,custom:Int)throws{
        try rpc(client,153){w in w.integer(UInt32(id),size:version == .dl ? 2:4);w.integer(UInt32(base),size:4)
            if version == .dl{w.integer(UInt32(bitPattern:Int32(custom)),size:4)}}
    }
    try join(21,"Persistent_Name")
    check(client.roster[21]=="Persistent_Name" && client.players.isEmpty,"137 created a phantom origin actor")
    check(actors.isEmpty,"Roster-only update published a renderer actor callback")
    try client.receive(remoteFoot(21,SIMD3(1,2,3)));try client.receive(remoteCar(21,SIMD3(4,5,6)))
    check(client.players.isEmpty,"Sync before32 created an actor")
    try stream(21)
    check(client.players[21]?.name=="Persistent_Name" && client.players[21]?.position==SIMD3(100,200,300),"Stream32 failed to reuse persistent roster")
    check(client.players[21]?.customSkin==(version == .dl ? 20001:nil),"Stream32 custom skin lost/introduced in wrong version")
    if version == .dl{
        check(actors.last?.first?.skin==20001,"Valid custom skin silently became a stock fallback")
        check(actors.last?.first?.position==SIMD3(100,200,299),"Remote onfoot root was not converted to native feet")
    }
    try client.receive(remoteFoot(21,SIMD3(101,202,303)))
    check(client.players[21]?.position==SIMD3(101,202,303) && client.players[21]?.name=="Persistent_Name","Real decoded foot sync lost actor/identity")
    check(client.players[21]?.customSkin==(version == .dl ? 20001:nil),"Onfoot sync discarded custom skin")
    try rpc(client,164){w in w.integer(1,size:2);w.integer(411,size:4);w.vector(SIMD3(104,205,306));w.float(0);w.integer(1,size:1);w.integer(1,size:1);w.float(900)}
    check(multiplayer.orderedVehicles.first?.position==SIMD3(104,205,306),"Vehicle body received a pedestrian height correction")
    try client.receive(remoteCar(21,SIMD3(104,205,306)))
    check(client.players[21]?.vehicle==1 && client.players[21]?.weapon==28,"Real decoded car sync lost driver/weapon")
    check(client.players[21]?.customSkin==(version == .dl ? 20001:nil),"InCar sync discarded custom skin")
    if version == .dl{check(actors.last?.first?.position==SIMD3(104,205,306),"Remote driver body received pedestrian correction")}
    let countBefore=presence.count
    try rpc(client,163){$0.integer(21,size:2)}
    check(client.players.isEmpty && client.roster[21]=="Persistent_Name","163 removed persistent metadata or retained streamed actor")
    check(presence.count==countBefore,"Stream-out overwrote full-server presence")
    try client.receive(remoteFoot(21,SIMD3(7,8,9)));try client.receive(remoteCar(21,SIMD3(7,8,9)))
    check(client.players.isEmpty,"Offstream delayed sync resurrected an actor")
    try stream(21,base:285,custom:20002)
    check(client.players[21]?.name=="Persistent_Name","Stream-in lost cached name")
    check(client.players[21]?.customSkin==(version == .dl ? 20002:nil),"Stream-in lost new custom skin")
    try skin(21,custom:0);check(client.players[21]?.customSkin==nil && client.players[21]?.skin==287,"Zero custom ID did not preserve stock skin")
    try skin(21,custom:30000);check(client.players[21]?.customSkin==(version == .dl ? 30000:nil),"Remote153 custom boundary lost")
    try join(21,"Renamed_Player");check(client.players[21]?.name=="Renamed_Player","137 update did not rename streamed entity")
    try rpc(client,138){$0.integer(21,size:2)}
    check(client.players.isEmpty && client.roster[21]==nil,"138 retained disconnected metadata/entity")
    try client.receive(remoteFoot(21,SIMD3(1,1,1)));check(client.players.isEmpty,"Disconnected sync created placeholder actor")
    // Minimal complete InitGame establishes real local identity once; no
    // transport is open, so this fixture cannot fabricate a live join.
    try rpc(client,139){w in
        for _ in 0..<4{w.bit(false)};w.float(0);w.bit(false);w.float(0)
        for _ in 0..<3{w.bit(false)};w.integer(1,size:4);w.integer(7,size:2);w.bit(false);w.integer(0,size:4)
        w.integer(12,size:1);w.integer(10,size:1);w.float(0.008)
    }
    check(client.roster==[7:"Local_QA"] && presence.last==1,"Local identity missing/duplicated")
    try rpc(client,12){$0.vector(SIMD3(10,20,30))}
    check(teleports.last==SIMD3(10,20,29),"Server SetPlayerPos root was not converted once")
    try rpc(client,19){$0.float(90)}
    check(teleports.last==SIMD3(10,20,29),"Heading-only update double-converted saved native feet")
    for custom in [0,-1,20000,20001,30000,30001]{
        try skin(7,custom:custom)
        let expected=version == .dl && (20001...30000).contains(custom) ? custom:287
        check(events.last? ["t"]as?String=="skin" && events.last?["id"]as?Int==expected,"Local153 effective skin range/fallback failed")
    }
    for custom in [0,20003]{
        try rpc(client,68){w in w.integer(0,size:1);w.integer(287,size:4)
            if version == .dl{w.integer(UInt32(custom),size:4)}
            w.integer(0,size:1);w.vector(SIMD3(1,2,3));w.float(0)}
        let expected=version == .dl && custom>0 ? custom:287
        check(events.last?["t"]as?String=="spawnInfo" && events.last?["skin"]as?Int==expected,"Next-spawn effective custom skin lost")
        check(events.last?["selection"]as?Bool==true && events.last?["point"]==nil,"Spawn metadata became an actor placement")
        client.onSpawn?(.init(team:0,skin:287,customSkin:version == .dl ? Int32(custom):nil,position:SIMD3(1,2,3),heading:0))
        check(events.contains{$0["t"]as?String=="spawn" && $0["skin"]as?Int==expected},"Spawn callback effective custom skin lost")
        check(teleports.last==SIMD3(1,2,2),"Spawn root conversion was lost or doubled")
    }
    try join(22,"Offstream_Join")
    check(presence.last==2 && client.players.isEmpty,"137-only roster included an origin actor or missed full presence")
    client.disconnect()
    check(client.roster.isEmpty && client.players.isEmpty,"Transport reset retained roster/entities")
}
for z:Float in [-100,0,9.8203125,1006.171875,1051.53125]{
    let feet=SIMD3<Float>(12,34,z),root=NativeSAMPPedCoordinates.root(feet)
    check(root.z==z+1 && NativeSAMPPedCoordinates.feet(root)==feet,"Ped coordinate boundary failed exact roundtrip")
}
print("PASS: \(checks) actual client/adapter roster, stream lifecycle and DL custom-skin regressions")
