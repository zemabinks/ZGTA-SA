// SPDX-License-Identifier: AGPL-3.0-only
// Prepended to the authored physics fixture's helpers and actual renderer method.
private final class LiveGravityPeer {
    let wire:NativeSAMPClient,adapter:NativeSAMPWorldConnection,network:NativeMultiplayerClient
    let renderer:RendererOwner
    let motor:NativeCharacterController
    let profile:String
    var ready=false,events=[[String:Any]](),sent=[[String:Any]](),errors=[String](),notes=[String]()
    private var lastSend=0.0
    init(_ address:String,_ version:NativeSAMPProtocol.Version)throws {
        let label=version == .dl ? "DL":"037";profile=label
        let identity=try NativeSAMPProtocol.installationID(source:Data("0123456789ABCDEFGHIJ".utf8))
        let client=NativeSAMPClient(address:address,nickname:"ZGTA_Gravity"+label,version:version,installationID:identity)
        let connection=NativeSAMPWorldConnection(client:client),native=RendererOwner()
        wire=client;adapter=connection;renderer=native
        network=NativeMultiplayerClient(server:ServerAddress("http://127.0.0.1:1")!,automaticRecoveryTimer:false,legacy:connection)
        motor=NativeCharacterController(world:native.groundVehicle!.world)!
        network.onStatus={[weak self] in self?.notes.append($0)}
        network.onLegacyEvent={[weak self] in self?.receive($0)}
    }
    private func receive(_ message:[String:Any]) {
        if let event=message["event"]as?NativeSAMPGameplayCommands.Event {
            let point=motor.state.feet,speed=motor.state.rising
            renderer.receiveLegacyGameplay(event)
            if case .gravity(let value)=event.command {
                if renderer.groundVehicle!.world.legacyGravity != value || renderer.legacyGravity != value {errors.append("gravity did not reach actual renderer/world")}
                if motor.state.feet != point || motor.state.rising != speed {errors.append("gravity changed pose/momentum immediately")}
                events.append(["gravity":Double(value),"generation":event.generation,"sequence":event.sequence,"at":ProcessInfo.processInfo.systemUptime])
            }
        }
        if message["t"]as?String=="class" {_=adapter.send(["t":"spawn"])}
        if message["t"]as?String=="spawn",let point=message["point"]as?SIMD3<Float> {
            motor.reset(feet:point);ready=true
        }
    }
    func tick(_ delta:Double,_ now:Double) {
        wire.poll();network.tickConnection(now:now)
        guard ready,network.isReady else{return}
        motor.update(delta:delta,displacement:.zero,geometryReady:true)
        if now-lastSend>=0.06 {
            let state=motor.state,velocity=SwiftRapierWorld.rapierToGTA(SIMD3<Float>(motor.stepVelocity))
            network.sendPosition(state.feet,heading:0,moving:false,running:false,airborne:!state.grounded,weapon:0,velocity:velocity)
            sent.append(["z":Double(NativeSAMPPedCoordinates.root(state.feet).z),"vz":Double(velocity.z),"at":now])
            lastSend=now
        }
    }
    var gravity:Float?{renderer.groundVehicle!.world.legacyGravity}
    func receipt()->[String:Any] {["profile":profile,"name":wire.nickname,"events":events,"sent":sent,"errors":errors,"notes":notes,"wireState":wire.state.rawValue]}
}
@main private struct LiveGravityGate {
    static func main() {
        let url=URL(fileURLWithPath:CommandLine.arguments[2])
        var peers=[LiveGravityPeer](),phases=[[String:Any]](),failure:String?
        do {
            peers=try [.init(CommandLine.arguments[1],.v037),.init(CommandLine.arguments[1],.dl)]
            for peer in peers{peer.network.connect()}
            var last=ProcessInfo.processInfo.systemUptime
            func tick() {
                let now=ProcessInfo.processInfo.systemUptime,delta=now-last;last=now
                for peer in peers{peer.tick(delta,now)}
                RunLoop.current.run(until:Date().addingTimeInterval(0.005))
            }
            func wait(_ seconds:Double,_ condition:()->Bool)throws {
                let end=ProcessInfo.processInfo.systemUptime+seconds
                while ProcessInfo.processInfo.systemUptime<end && !condition(){tick()}
                try check(condition(),"Live condition timeout: \(peers.map{$0.notes.suffix(3)})")
                try check(peers.allSatisfy{$0.errors.isEmpty},"Live renderer/physics ownership failure")
            }
            func run(_ phase:String,_ expected:[Float],command:String?=nil)throws {
                if let command{peers[0].network.sendChat(command)}
                try wait(8){zip(peers,expected).allSatisfy{$0.0.gravity==$0.1}}
                if command != nil {try wait(4){peers.allSatisfy{$0.network.chatMessages.contains{$0.contains("GRAVITY:"+phase)}}}}
                let end=ProcessInfo.processInfo.systemUptime+0.8
                while ProcessInfo.processInfo.systemUptime<end{tick()}
                try check(zip(peers,expected).allSatisfy{$0.0.gravity==$0.1},"Per-player/global force leaked across peers")
                phases.append(["phase":phase,"expected":expected.map(Double.init),"observed":peers.map{Double($0.gravity!)},"at":ProcessInfo.processInfo.systemUptime])
            }
            try wait(20){peers.allSatisfy{$0.ready && $0.network.isReady}}
            try run("initial",[0.004,0.004])
            try run("one",[0.016,0.004],command:"/gravity_one")
            try run("global",[0.008,0.008],command:"/gravity_global")
            try run("zero",[0,0.008],command:"/gravity_zero")
            try run("invert",[0,-0.008],command:"/gravity_invert")
            try run("restore",[0.008,0.008],command:"/gravity_restore")
            for peer in peers {peer.network.disconnect();try check(peer.gravity==nil && peer.renderer.legacyGravity==nil,"Disconnect retained live force context")}
        }catch{failure=String(describing:error)}
        for peer in peers{peer.network.disconnect()}
        let report:[String:Any]=["status":failure==nil ? "PASS":"FAIL","checks":checks,"failure":failure.map{$0 as Any} ?? NSNull(),"peers":peers.map{$0.receipt()},"phases":phases,
            "scope":"Actual native clients/NMP/adapters/UDP and literal renderer force consumer with actual Rapier motor in authored space. Follow-camera is an explicit boundary; no GPU/iPhone/retail claim."]
        do{try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:url)}catch{print("Report failed: \(error)");exit(3)}
        print(failure==nil ? "PASS actual two-client legacy gravity live phases":"FAIL \(failure!)")
        if failure != nil{exit(2)}
    }
}
