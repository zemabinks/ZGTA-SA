import Foundation
import ZGTASAMPTransport

/// Actual legacy transport and game handshake. RakNet acceptance alone never
/// sets `spawned`: the server's class/spawn transaction must complete first.
/// Native rendering/input remain outside this client; no bot movement loop.
final class NativeSAMPClient {
    enum State: String { case stopped, connecting, accepted, selecting, spawning, spawned, wasted, failed }
    struct Vehicle {let id:UInt16,model:Int;var position:SIMD3<Float>;var heading:Float;var health:Float;let colors:[Int];var pitch:Float=0,roll:Float=0}
    struct Player {let id:UInt16;var name:String;var skin:Int=7;var customSkin:Int?;var position=SIMD3<Float>.zero;var heading:Float=0,pitch:Float=0,roll:Float=0;var health:Int=100,armour:Int=0,weapon:Int=0;var velocity=SIMD3<Float>.zero;var vehicle:UInt16?;var action:Int=0}
    let address:String,nickname:String,version:NativeSAMPProtocol.Version,installationID:String
    private let password:String
    private var handle:UInt64=0
    private var timer:DispatchSourceTimer?
    private var joined=false
    private var spawnRequested=false
    private var spawnInfo:NativeSAMPProtocol.Spawn?
    private(set) var state:State = .stopped
    private(set) var localID:UInt16?
    private(set) var classCount=0,classIndex=0
    private(set) var footMilliseconds=30,carMilliseconds=30,weaponMilliseconds=30
    var onEnvironment:((Int?,Int?,Int?,Bool?)->Void)?
    private(set) var players:[UInt16:Player]=[:]
    /// ServerJoin membership outlives streamed entities. A nil callback resets
    /// snapshot readiness only when the actual transport/session is reset.
    private(set) var roster:[UInt16:String]=[:]
    private var streamedPlayers=Set<UInt16>()
    var onRoster:(([UInt16:String]?)->Void)?
    private(set) var vehicles:[UInt16:Vehicle]=[:]
    private(set) var receivedRPCs=Set<UInt8>()
    var onState:((State)->Void)?
    var onGameplayCommand:((NativeSAMPGameplayCommands.Event)->Void)?
    private(set) var gameplayGeneration:UInt64=0
    private var gameplaySequence:UInt64=0
    private(set) var controllable=true,spectating=false
    var onStatus:((String)->Void)?
    var onClass:((NativeSAMPProtocol.Spawn)->Void)?
    var onSpawn:((NativeSAMPProtocol.Spawn)->Void)?
    var onPosition:((SIMD3<Float>,Float?)->Void)?
    var onHeading:((Float)->Void)?
    var onPlayers:(([Player])->Void)?
    var onVehicles:(([Vehicle])->Void)?
    var onVitals:((Int?,Int?)->Void)?
    /// Exact server RPC14/66 float values, separate from quantized sync bytes.
    var onPreciseVitals:((Float?,Float?)->Void)?
    private(set) var preciseHealth:Float=100,preciseArmour:Float=0
    private(set) var lastQueuedCar:NativeSAMPProtocol.Car?
    var onChat:((String)->Void)?
    var onRawRPC:((NativeSAMPProtocol.RPC)->Void)?
    var onSkin:((Int)->Void)?
    var onEnter:((UInt16,UInt8)->Void)?
    var onExit:(()->Void)?
    enum WeaponCommand {case give(Int,Int),ammo(Int,Int),reset,select(Int)}
    var onWeaponCommand:((WeaponCommand)->Void)?
    private(set) var health=100,armour=0
    private(set) var interior:UInt8=0
    var onInterior:((UInt8)->Void)?
    var onSpecialAction:((UInt8)->Void)?

    init(address:String,nickname:String,version:NativeSAMPProtocol.Version,installationID:String,password:String="") {
        self.address=address;self.nickname=nickname;self.version=version;self.installationID=installationID;self.password=password
    }
    deinit{timer?.cancel();if handle != 0{zgtasa_samp_close(handle)}}
    private func setState(_ next:State){guard state != next else{return};state=next;onState?(next)}
    func connect(automaticPolling:Bool=true){
        let expected=gameplayGeneration &+ 1
        disconnect();guard gameplayGeneration==expected,handle==0,state == .stopped else{return}
        guard zgtasa_samp_abi_version()==1 else{fail("UNSUPPORTED NATIVE TRANSPORT ABI");return}
        guard (try? NativeSAMPProtocol.join(version:version,nickname:nickname,installationID:installationID,challenge:0)) != nil else{fail("INVALID PLAYER NAME OR INSTALLATION ID");return}
        let pass=Data(password.utf8)
        handle=address.withCString {p in pass.withUnsafeBytes {b in zgtasa_samp_open(p,UInt32(address.utf8.count),b.bindMemory(to:UInt8.self).baseAddress,UInt32(pass.count),15000)}}
        guard handle != 0 else{fail("INVALID LEGACY SERVER ADDRESS");return};setState(.connecting)
        if automaticPolling{let t=DispatchSource.makeTimerSource(queue:.main);t.schedule(deadline:.now(),repeating:.milliseconds(10));t.setEventHandler{[weak self]in self?.poll()};timer=t;t.resume()}
    }
    func disconnect(){
        timer?.cancel();timer=nil;if handle != 0{zgtasa_samp_close(handle);handle=0}
        joined=false;spawnRequested=false;spawnInfo=nil;localID=nil
        players.removeAll();streamedPlayers.removeAll();roster.removeAll();vehicles.removeAll();receivedRPCs.removeAll()
        health=100;armour=0;preciseHealth=100;preciseArmour=0;lastQueuedCar=nil;gameplayGeneration &+= 1;gameplaySequence=0;controllable=true;spectating=false
        let epoch=gameplayGeneration;setState(.stopped)
        guard gameplayGeneration==epoch else{return};onRoster?(nil)
        guard gameplayGeneration==epoch else{return};onGameplayCommand?(.init(generation:epoch,sequence:0,command:.reset))
    }
    private func fail(_ reason:String){let epoch=gameplayGeneration &+ 1;disconnect();guard gameplayGeneration==epoch,state == .stopped else{return};setState(.failed);guard gameplayGeneration==epoch else{return};onStatus?(reason)}
    func poll(){
        guard handle != 0 else{return}
        let epoch=gameplayGeneration
        for _ in 0..<128 {
            var required:UInt32=0
            var kind=zgtasa_samp_poll(handle,nil,0,&required)
            if kind==0{return}
            guard kind == -2,required>0,required<=1_048_576 else{fail("LEGACY TRANSPORT CLOSED");return}
            var buffer=[UInt8](repeating:0,count:Int(required))
            kind=buffer.withUnsafeMutableBufferPointer{zgtasa_samp_poll(handle,$0.baseAddress,UInt32($0.count),&required)}
            guard required<=buffer.count else{fail("INVALID TRANSPORT EVENT");return}
            let packet=Data(buffer.prefix(Int(required)))
            if kind==3{fail(String(decoding:packet,as:UTF8.self));return}
            guard kind==1 || kind==2 else{fail("INVALID TRANSPORT EVENT");return}
            do{try receive(packet)}catch{onStatus?("INVALID LEGACY PACKET: \(error)")}
            guard handle != 0,gameplayGeneration==epoch else{return}
        }
    }
    @discardableResult func send(_ data:Data,reliability:UInt32=8,channel:UInt32=0)->Bool {
        guard handle != 0,!data.isEmpty,data.count<=8191 else{return false}
        let result=data.withUnsafeBytes{zgtasa_samp_send(handle,$0.bindMemory(to:UInt8.self).baseAddress,UInt32($0.count),reliability,channel)}
        if result != 0{onStatus?("LEGACY SEND QUEUE: \(result)")};return result==0
    }
    @discardableResult func sendRPC(_ id:UInt8,_ payload:NativeSAMPProtocol.Writer=NativeSAMPProtocol.Writer())->Bool{send(NativeSAMPProtocol.rpc(id,payload))}
    private func publishGameplay(_ command:NativeSAMPGameplayCommands.Command){gameplaySequence &+= 1;onGameplayCommand?(.init(generation:gameplayGeneration,sequence:gameplaySequence,command:command))}
    @discardableResult private func acceptServerSpawn(_ info:NativeSAMPProtocol.Spawn)->Bool {
        let epoch=gameplayGeneration;guard sendRPC(52)else{return false}
        if spectating{spectating=false;publishGameplay(.spectating(false))}
        guard gameplayGeneration==epoch else{return false}
        if !controllable{controllable=true;publishGameplay(.controllable(true))}
        guard gameplayGeneration==epoch else{return false}
        preciseHealth=100;preciseArmour=0;health=100;armour=0;lastQueuedCar=nil
        spawnRequested=false;setState(.spawned);guard gameplayGeneration==epoch else{return false};onSpawn?(info)
        for (weapon,amount)in info.weapons{guard gameplayGeneration==epoch else{return false};onWeaponCommand?(.give(weapon,min(9999,amount)))}
        return true
    }
    func requestClass(_ index:Int){
        guard joined,state != .spawned,index >= -Int(Int32.max),index<=Int(Int32.max)else{return}
        let count=max(1,classCount),selected=(index%count+count)%count
        var w=NativeSAMPProtocol.Writer();w.integer(UInt32(selected),size:4)
        if sendRPC(128,w){classIndex=selected;setState(.selecting)}
    }
    func requestSpawn(){guard state == .selecting,spawnInfo != nil,!spawnRequested else{return};if sendRPC(129){spawnRequested=true;setState(.spawning)}}
    @discardableResult func sendFoot(_ frame:NativeSAMPProtocol.Foot)->Bool{var frame=frame;if !controllable{frame.keys=0;frame.lr=0;frame.ud=0;frame.specialKeys=0};guard state == .spawned,!spectating,let data=try? NativeSAMPProtocol.onFoot(frame)else{return false};health=Int(frame.health);armour=Int(frame.armour);return send(data,reliability:7,channel:1)}
    @discardableResult func sendCar(_ frame:NativeSAMPProtocol.Car)->Bool{
        var frame=frame;if !controllable{frame.keys=0;frame.lr=0;frame.ud=0;frame.specialKeys=0}
        guard state == .spawned,!spectating,let data=try?NativeSAMPProtocol.car(frame)else{return false}
        let generation=gameplayGeneration
        guard send(data,reliability:7)else{return false}
        if gameplayGeneration==generation,state == .spawned{lastQueuedCar=frame}
        if gameplayGeneration==generation,state == .spawned,var vehicle=vehicles[frame.id]{
            let q=frame.quaternion,n=sqrt(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w)
            if n.isFinite,n>0.000001{
                let angles=NativeSAMPProtocol.nativeAngles(q/n)
                vehicle.position=frame.position;vehicle.heading=angles.heading;vehicle.pitch=angles.pitch;vehicle.roll=angles.roll;vehicle.health=frame.health
                // This is the last successfully queued local driver pose, not
                // a new server ACK. Keep it for the next real spawn snapshot;
                // publishing it every tick would reset the local controller.
                vehicles[frame.id]=vehicle
            }
        }
        return true
    }
    @discardableResult func sendSpectatorPosition(_ point:SIMD3<Float>,keys:UInt16=0,axes:SIMD2<Int16> = .zero)->Bool{guard joined,spectating,let data=try?NativeSAMPGameplayCommands.spectator(position:point,keys:controllable ? keys:0,axes:controllable ? axes:.zero)else{return false};return send(data,reliability:7,channel:1)}
    @discardableResult func reportDeath(reason:UInt8=255,killer:UInt16=65535)->Bool{
        guard state == .spawned else{return false};var w=NativeSAMPProtocol.Writer();w.integer(UInt32(reason),size:1);w.integer(UInt32(killer),size:2)
        guard sendRPC(53,w)else{return false};health=0;setState(.wasted);return true
    }
    func requestRespawn(){guard state == .wasted else{return};spawnInfo=nil;spawnRequested=false;setState(.selecting);requestClass(0)}
    func sendChat(_ text:String){
        guard joined,let bytes=text.data(using:.windowsCP1252),!bytes.isEmpty else{return}
        var w=NativeSAMPProtocol.Writer()
        if text.hasPrefix("/"){guard bytes.count<=1024 else{return};w.integer(UInt32(bytes.count),size:4);w.bytes(bytes);_=sendRPC(50,w)}
        else{guard bytes.count<=144 else{return};w.text8(bytes);_=sendRPC(101,w)}
    }
    @discardableResult func enterVehicle(_ id:UInt16,passenger:Bool=false)->Bool{guard state == .spawned,controllable,!spectating,vehicles[id] != nil else{return false};var w=NativeSAMPProtocol.Writer();w.integer(UInt32(id),size:2);w.integer(passenger ? 1:0,size:1);return sendRPC(26,w)}
    @discardableResult func exitVehicle(_ id:UInt16)->Bool{guard state == .spawned,controllable,!spectating else{return false};var w=NativeSAMPProtocol.Writer();w.integer(UInt32(id),size:2);return sendRPC(154,w)}
    private func publishedPlayers(){onPlayers?(players.keys.sorted().compactMap{players[$0]})}
    private func publishedVehicles(){onVehicles?(vehicles.keys.sorted().compactMap{vehicles[$0]})}
    private func receive(_ data:Data)throws{
        guard let tag=data.first else{return}
        switch tag{
        case 12:
            guard data.count>=2,Int(data[1])+2<=data.count else{throw NativeSAMPProtocol.Error.truncated}
            _=send(NativeSAMPProtocol.auth(data.subdata(in:2..<(2+Int(data[1])))))
        case 34:
            guard !joined,data.count>=13 else{return};var r=try NativeSAMPProtocol.Reader(data.subdata(in:9..<13));let challenge=try r.integer(4)
            if send(try NativeSAMPProtocol.join(version:version,nickname:nickname,installationID:installationID,challenge:challenge)){joined=true;setState(.accepted)}
        case 207:try remoteFoot(data)
        case 200:try remoteCar(data)
        case 20,40:
            let rpc=try NativeSAMPProtocol.rpc(data);receivedRPCs.insert(rpc.id);try handleRPC(rpc)
        case 32,33:fail("SERVER CLOSED THE LEGACY SESSION (\(tag))")
        default:break
        }
    }
    private func handleRPC(_ rpc:NativeSAMPProtocol.RPC)throws{
        if let command=try NativeSAMPGameplayCommands.decode(rpc){
            let epoch=gameplayGeneration,wasSpectating=spectating
            switch command{case .controllable(let enabled):controllable=enabled
            case .spectating(let enabled):spectating=enabled
            default:break}
            publishGameplay(command)
            guard gameplayGeneration==epoch else{return}
            if command == .spectating(false),wasSpectating {
                // Official server setSpectating(false) authorizes the normal
                // PlayerSpawn52 transaction (toSpawn_/leavingSpec_), with no
                // fabricated inventory ACK or client-check response.
                if let info=spawnInfo{_=acceptServerSpawn(info)}
                else{setState(.selecting);onStatus?("SERVER HAS NOT PROVIDED SPAWN DATA AFTER SPECTATING")}
            }
            return
        }
        var r=try NativeSAMPProtocol.Reader(rpc.data,bits:rpc.bits)
        switch rpc.id{
        case 130:fail("SERVER REJECTED THE CLIENT (\(try r.integer(1)))")
        case 139:
            let intro=try NativeSAMPProtocol.introduction(&r);localID=intro.id;classCount=intro.classes;classIndex=0
            footMilliseconds=intro.footMilliseconds;carMilliseconds=intro.carMilliseconds;weaponMilliseconds=intro.weaponMilliseconds
            players.removeAll();streamedPlayers.removeAll();vehicles.removeAll();spawnInfo=nil;spawnRequested=false
            publishedPlayers();publishedVehicles();setState(.selecting)
            roster[intro.id]=nickname;onRoster?(roster)
            onEnvironment?(intro.hour,0,intro.weather,false);requestClass(0)
        case 128:
            guard try r.integer(1) != 0 else{onStatus?("CLASS UNAVAILABLE");if let info=spawnInfo{onClass?(info)};return}
            let info=try NativeSAMPProtocol.spawn(&r,version:version);spawnInfo=info;spawnRequested=false;setState(.selecting);onClass?(info)
        case 68:let info=try NativeSAMPProtocol.spawn(&r,version:version);spawnInfo=info;onClass?(info)
        case 129:
            let result=try r.integer(1)
            if result==0{spawnRequested=false;setState(.selecting);onStatus?("SPAWN DECLINED");return}
            guard result==1 && spawnRequested || result==2,let info=spawnInfo else{return}
            _=acceptServerSpawn(info)
        case 12,13:onPosition?(try r.vector(),nil)
        case 19:onHeading?(-(try r.float()) * .pi/180)
        case 29:onEnvironment?(Int(try r.integer(1)),Int(try r.integer(1)),nil,nil)
        case 30:onEnvironment?(nil,nil,nil,try r.integer(1) != 0)
        case 156:
            interior=UInt8(try r.integer(1));onInterior?(interior)
            var reply=NativeSAMPProtocol.Writer();reply.integer(UInt32(interior),size:1);_=sendRPC(118,reply)
        case 88:onSpecialAction?(UInt8(try r.integer(1)))
        case 14:
            let value=try r.float();guard (0...1_000_000).contains(value)else{throw NativeSAMPProtocol.Error.invalid}
            preciseHealth=value;health=Int(value)
            let epoch=gameplayGeneration;onPreciseVitals?(preciseHealth,nil)
            if gameplayGeneration==epoch{onVitals?(health,nil)}
        case 66:
            let value=try r.float();guard (0...1_000_000).contains(value)else{throw NativeSAMPProtocol.Error.invalid}
            preciseArmour=value;armour=Int(value)
            let epoch=gameplayGeneration;onPreciseVitals?(nil,preciseArmour)
            if gameplayGeneration==epoch{onVitals?(nil,armour)}
        case 22:let id=Int(try r.integer(4)),amount=Int(try r.integer(4));guard id<=46,amount<=9999 else{throw NativeSAMPProtocol.Error.invalid};onWeaponCommand?(.give(id,amount))
        case 21:onWeaponCommand?(.reset)
        case 67:let id=Int(try r.integer(4));guard id<=46 else{throw NativeSAMPProtocol.Error.invalid};onWeaponCommand?(.select(id))
        case 145:let id=Int(try r.integer(1)),amount=Int(try r.integer(2));guard id<=46 else{throw NativeSAMPProtocol.Error.invalid};onWeaponCommand?(.ammo(id,amount))
        case 70:let id=UInt16(try r.integer(2)),seat=UInt8(try r.integer(1));onEnter?(id,seat)
        case 71:onExit?()
        case 137:
            let id=UInt16(try r.integer(2));_=try r.integer(4);_=try r.integer(1);let name=try r.text8()
            roster[id]=name;onRoster?(roster)
            if var player=players[id]{player.name=name;players[id]=player;publishedPlayers()}
        case 138:
            let id=UInt16(try r.integer(2));roster.removeValue(forKey:id);streamedPlayers.remove(id);players.removeValue(forKey:id);onRoster?(roster);publishedPlayers()
        case 32:
            let id=UInt16(try r.integer(2));_=try r.integer(1);let skin=Int(try r.integer(4));let custom=version == .dl ? Int(Int32(bitPattern:try r.integer(4))):nil
            let point=try r.vector(),angle=try r.float();_=try r.integer(4)
            var player=players[id] ?? Player(id:id,name:roster[id] ?? "Player \(id)");player.skin=skin;player.customSkin=custom.flatMap{(20001...30000).contains($0) ? $0:nil};player.position=point;player.heading = -angle * .pi/180;streamedPlayers.insert(id);players[id]=player;publishedPlayers()
        case 163:
            let id=UInt16(try r.integer(2));streamedPlayers.remove(id);players.removeValue(forKey:id);publishedPlayers()
        case 153:
            let id=try r.integer(version == .dl ? 2:4),skin=Int(try r.integer(4));let raw=version == .dl ? Int(Int32(bitPattern:try r.integer(4))):nil
            let custom=raw.flatMap{(20001...30000).contains($0) ? $0:nil}
            if id==localID.map(UInt32.init){onSkin?(custom ?? skin)}else if id<=UInt16.max,var player=players[UInt16(id)]{player.skin=skin;player.customSkin=custom;players[UInt16(id)]=player;publishedPlayers()}
        case 93:
            _=try r.integer(4);let count=Int(try r.integer(4));guard count<=4096 else{throw NativeSAMPProtocol.Error.invalid};onChat?(NativeSAMPProtocol.Reader.text(try r.bytes(count*8)))
        case 101:let id=UInt16(try r.integer(2)),line=try r.text8();onChat?("\(players[id]?.name ?? "Player \(id)"): \(line)")
        case 164:
            let id=UInt16(try r.integer(2)),model=Int(try r.integer(4)),point=try r.vector(),angle=try r.float(),c1=Int(try r.integer(1)),c2=Int(try r.integer(1)),hp=try r.float()
            guard (400...611).contains(model)else{onStatus?("CUSTOM VEHICLE MODEL NEEDS AN IMPORTER");return}
            vehicles[id]=Vehicle(id:id,model:model,position:point,heading:-angle * .pi/180,health:hp,colors:[c1,c2]);publishedVehicles()
        case 165:vehicles.removeValue(forKey:UInt16(try r.integer(2)));publishedVehicles()
        case 147:let id=UInt16(try r.integer(2)),hp=try r.float();vehicles[id]?.health=hp;publishedVehicles()
        default:onRawRPC?(rpc)
        }
    }
    private func remoteFoot(_ data:Data)throws{
        var r=try NativeSAMPProtocol.Reader(data);_=try r.integer(1);let id=UInt16(try r.integer(2))
        guard streamedPlayers.contains(id)else{return}
        for _ in 0..<2{if try r.bit(){_=try r.integer(2)}}
        _=try r.integer(2);let point=try r.vector(),q=try r.quaternion(),hp=try r.integer(1),weapon=Int(try r.integer(1))&63,action=Int(try r.integer(1)),velocity=try r.compressedVector()
        var player=players[id] ?? Player(id:id,name:"Player \(id)");player.position=point
        let angles=NativeSAMPProtocol.nativeAngles(q);player.heading=angles.heading;player.pitch=angles.pitch;player.roll=angles.roll
        func life(_ n:UInt32)->Int{n==15 ? 100:Int(n)*7}
        player.health=life(hp>>4);player.armour=life(hp&15);player.weapon=weapon;player.action=action;player.velocity=velocity*50;player.vehicle=nil
        players[id]=player;publishedPlayers()
    }
    private func remoteCar(_ data:Data)throws{
        var r=try NativeSAMPProtocol.Reader(data);_=try r.integer(1);let playerID=UInt16(try r.integer(2)),vehicleID=UInt16(try r.integer(2))
        guard streamedPlayers.contains(playerID)else{return}
        for _ in 0..<3{_=try r.integer(2)}
        let q=try r.quaternion(),point=try r.vector(),velocity=try r.compressedVector(),hp=try r.integer(2),life=try r.integer(1),weapon=Int(try r.integer(1))&63
        let angles=NativeSAMPProtocol.nativeAngles(q),heading=angles.heading
        var player=players[playerID] ?? Player(id:playerID,name:"Player \(playerID)")
        player.position=point;player.heading=heading;player.pitch=angles.pitch;player.roll=angles.roll;player.vehicle=vehicleID;player.velocity=velocity*50;player.weapon=weapon
        player.health=life>>4==15 ? 100:Int(life>>4)*7;player.armour=life&15==15 ? 100:Int(life&15)*7
        players[playerID]=player
        if var vehicle=vehicles[vehicleID]{vehicle.position=point;vehicle.heading=heading;vehicle.pitch=angles.pitch;vehicle.roll=angles.roll;vehicle.health=Float(hp);vehicles[vehicleID]=vehicle}
        publishedPlayers();publishedVehicles()
    }
}
