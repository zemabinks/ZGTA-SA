// SPDX-License-Identifier: AGPL-3.0-only
let address=ServerAddress(CommandLine.arguments[1])!,client=NativeMultiplayerClient(server:address)
let weapon=NativeWeaponState.Weapon(id:25,name:"Authored six-ray fixture",model:"",range:40,capacity:5,interval:0.3,animation:"fixture",fireKind:"INSTANT_HIT",damage:4,pellets:6)
let weapons=NativeWeaponState(catalog:[weapon])
let renderer=StrikeRenderer()
var checks=0,phase=0,settled=false,acceptedTargets:[String]=[],targetIDs:[String]=[]
func check(_ value:Bool,_ why:String){checks+=1;if !value{print("FAIL \(why)");exit(1)}}
client.onInventoryConnection={weapons.setConnection($0)}
client.onInventory={snapshot in
    check(weapons.apply(snapshot),"Actual authoritative inventory snapshot")
    if NativeInventoryAcknowledgement(snapshot)?.processedShot==1 {
        check(weapons.rounds==4 && weapons.pendingShotCount==0,"One accepted marker settles one cartridge")
        settled=true
    }
}
client.onAcceptedStrike={row in
    check(row["w"]as?Int==25 && row["bp"]as?Int==3 && row["s"]as?Int==1,"Accepted strike retains weapon, body piece and sequence")
    check(row["c"]as?String==client.inventoryConnection,"Accepted strike belongs to this connection")
    guard let id=row["id"]as?String else{check(false,"Accepted target identity");return}
    acceptedTargets.append(id)
    check(weapons.rounds==4 && weapons.pendingShotCount==1,"Strike metadata cannot settle ammunition itself")
    renderer.receiveAcceptedStrike(row)
    check(renderer.humanShots.recentStrike(id,at:1)?.weapon==25,"Own shooter receipt failed actual renderer strike admission")
    check(renderer.remotePlayers.allSatisfy{$0.health==100},"Strike metadata applied target damage locally")
    if let from=row["from"]as?String {check(renderer.humanShots.queued(from)==0,"Accepted local hit replayed a remote firing marker")}
}
client.onStatus={text in
    if text.hasPrefix("GROUP_TARGETS ") {
        check(phase==0 && client.isReady && client.ordinaryShotGroupsEnabled,"One negotiated ready connection")
        phase=1;let ids=text.split(separator:" ").dropFirst().map(String.init)
        check(ids.count==2,"Authored target identities")
        renderer.remotePlayers=ids.map{.init(id:$0,code:"s7")}
        renderer.remoteFootAnimations=Dictionary(uniqueKeysWithValues:ids.map{($0,("authored-rig",0))})
        targetIDs=ids
        client.sendPosition(SIMD3(1570,-2460,13.6),heading:0,moving:false,running:false,weapon:25)
    } else if text=="GROUP_POSE" {
        check(phase==1,"Normal native pose must be admitted before shooting")
        phase=2;let ids=targetIDs
        let ticket=client.reserveShot()!
        check(weapons.consumeAnimationShot(weapon:25,ticket:ticket),"Actual local prediction spends one cartridge")
        let origin=SIMD3<Double>(1570,-2460,14.95)
        let claims:[NativeLocalShots.Claim]=[
            .init(origin:origin,end:SIMD3(1574,-2460,14.7),kind:1,target:.init(id:ids[0],kind:1,piece:3),pellets:3),
            .init(origin:origin,end:SIMD3(1574,-2458,14.7),kind:1,target:.init(id:ids[1],kind:1,piece:3),pellets:2),
            .init(origin:origin,end:SIMD3(1576,-2460,14.7),kind:0,target:nil,pellets:1)]
        let invalid=NativeLocalShots.Claim(origin:SIMD3(.nan,0,0),end:.zero,kind:0,target:nil,pellets:1)
        check(!client.sendOrdinaryShotBatch(weapon:25,claims:[claims[0],invalid],ticket:ticket),"Invalid entire batch cannot consume the ticket")
        check(client.sendOrdinaryShotBatch(weapon:25,claims:claims,ticket:ticket),"Actual grouped transport accepted")
        check(!client.sendOrdinaryShotBatch(weapon:25,claims:claims,ticket:ticket),"Ticket cannot be sent twice")
        check(weapons.rounds==4 && weapons.pendingShotCount==1,"All targets retain one pending prediction")
    } else if text=="GROUP_SETTLED" {
        check(phase==2 && settled && Set(acceptedTargets).count==2,"Server settlement follows two accepted target receipts and the actual inventory ACK")
        phase=3;client.sendPosition(SIMD3(1570,-2460,13.6),heading:0,moving:false,running:false,weapon:25)
    } else if text=="GROUP_COUNTER" {
        check(phase==3,"Actual full position receipt")
        client.disconnect();check(!client.ordinaryShotGroupsEnabled,"Disconnect revokes grouped-shot capability")
        print("PASS \(checks) actual native grouped-shot URLSession/prediction checks; authored server world, no App/render/hardware/retail claim")
        exit(0)
    }
}
client.connect()
DispatchQueue.main.asyncAfter(deadline:.now()+20){print("FAIL grouped-shot wire timeout at phase \(phase), state \(client.state)");exit(1)}
RunLoop.main.run()
