import Foundation

/// CPed network positions are model roots, while the native motor publishes
/// feet. The original CPedPlacement ground placement adds1m and its standard
/// collision box extends to−1m: gta-reversed/gta-reversed943c2a37,
/// source/game_sa/PedPlacement.cpp:22 and Collision/TempColModels.cpp:41.
/// The official SimpleTDM class root10.8203 sits above imported ground9.8203125.
/// This coordinate convention does not claim retail animation/contact parity.
enum NativeSAMPPedCoordinates {
    static let rootAboveFeet:Float=1
    static func feet(_ root:SIMD3<Float>)->SIMD3<Float>{root-SIMD3(0,0,rootAboveFeet)}
    static func root(_ feet:SIMD3<Float>)->SIMD3<Float>{feet+SIMD3(0,0,rootAboveFeet)}
}

/// Maps semantic native controls to a real legacy client. This adapter never
/// uses our self-host HTTP APIs or pretends that SA-MP sends inventory ACKs.
final class NativeSAMPWorldConnection:NativeLegacyWorldConnection {
    let client:NativeSAMPClient
    private(set) var state:NativeConnectionRecovery.State = .stopped
    var onState:((NativeConnectionRecovery.State)->Void)?
    var onStatus:((String)->Void)?
    var onPlayers:(([RemotePlayer])->Void)?
    var onVehicles:(([RemoteVehicle])->Void)?
    var onEvent:(([String:Any])->Void)?
    private var desired=false,active=true
    private var retryAt:Double?,failures=0
    private var point=SIMD3<Float>.zero
    private var lastDeath=false
    private var skinCatalog:NativeSAMPSkinCatalog?
    private var vehicleCoordinates:NativeSAMPVehicleCoordinates?
    private let requiresVehicleCoordinates:Bool
    private var unavailableVehicleModels=Set<Int>()
    private var pendingServerEnter:(id:UInt16,seat:UInt8,generation:UInt64)?
    private var lastPlayers:[NativeSAMPClient.Player]=[]
    private var unsupportedSkins=Set<Int>()
    private var clockMinute=720.0,clockEpoch=0.0,clockRunning=false
    private var worldWeather:Int?
    var weaponDamage:((Int)->Float?)?
    /// Without an asset origin/catalog this is a raw-coordinate protocol probe.
    /// Native gameplay always supplies an origin and waits for exact metadata.
    init(client:NativeSAMPClient,assetServer:ServerAddress?=nil,vehicleCoordinates:NativeSAMPVehicleCoordinates?=nil){
        self.client=client;self.vehicleCoordinates=vehicleCoordinates
        requiresVehicleCoordinates=assetServer != nil || vehicleCoordinates != nil
        install()
        if let assetServer {URLSession.shared.dataTask(with:assetServer.path("game/native/samp-skins.json")){[weak self] data,response,_ in
            DispatchQueue.main.async {
                guard let self,let data,(response as?HTTPURLResponse)?.statusCode==200,let catalog=try?NativeSAMPSkinCatalog(data:data)else{return}
                self.skinCatalog=catalog;self.client.onPlayers?(self.client.players.values.sorted{$0.id<$1.id})
            }
        }.resume()}
        if let assetServer{URLSession.shared.dataTask(with:assetServer.path("game/native/vehicles.physics.json")){[weak self]data,response,_ in
            DispatchQueue.main.async {
                guard let self,let data,(response as?HTTPURLResponse)?.statusCode==200,
                      let catalog=try?NativeSAMPVehicleCoordinates(metadata:data)else{self?.onStatus?("NATIVE VEHICLE ORIGIN METADATA IS UNAVAILABLE");return}
                self.vehicleCoordinates=catalog;self.unavailableVehicleModels.removeAll()
                self.client.onVehicles?(self.client.vehicles.values.sorted{$0.id<$1.id})
            }
        }.resume()}
    }
    deinit{client.disconnect()}
    private func setState(_ next:NativeConnectionRecovery.State){guard state != next else{return};state=next;onState?(next)}
    func connect(){desired=true;retryAt=nil;failures=0;client.connect()}
    func disconnect(){desired=false;retryAt=nil;client.disconnect();setState(.stopped)}
    func setActive(_ value:Bool){active=value;if value{tick(now:ProcessInfo.processInfo.systemUptime)}}
    func tick(now:Double){guard desired,active,now.isFinite,let retryAt,now>=retryAt else{return};self.retryAt=nil;client.connect()}
    private func install(){
        client.onGameplayCommand = { [weak self] event in
            if event.command == .reset{self?.pendingServerEnter=nil}
            self?.onEvent?(["t":"sampGameplay","event":event])
        }
        client.onRoster = { [weak self] names in
            guard let names else{self?.onEvent?(["t":"rosterReset"]);return}
            self?.onEvent?(["t":"roster","players":Dictionary(uniqueKeysWithValues:names.map{(String($0.key),$0.value)})])
        }
        client.onState = { [weak self] next in
            guard let self else{return}
            switch next {
            case .spawned,.wasted:self.failures=0;self.setState(.ready)
            case .failed:
                self.setState(self.desired ? .reconnecting:.stopped)
                if self.desired{self.failures+=1;self.retryAt=ProcessInfo.processInfo.systemUptime+min(60,pow(2,Double(min(5,self.failures))))}
            case .stopped:self.setState(self.desired ? .connecting:.stopped)
            default:self.setState(.connecting)
            }
        }
        client.onStatus = { [weak self]in self?.onStatus?($0) }
        func effectiveSkin(_ info:NativeSAMPProtocol.Spawn)->Int{info.customSkin.map(Int.init).flatMap{(20001...30000).contains($0) ? $0:nil} ?? Int(info.skin)}
        client.onClass = { [weak self] info in self?.onEvent?(["t":"class","skin":effectiveSkin(info),"point":NativeSAMPPedCoordinates.feet(info.position),"heading":info.heading]) }
        client.onSpawn = { [weak self] info in
            guard let self else{return};self.point=NativeSAMPPedCoordinates.feet(info.position);self.lastDeath=false
            let generation=self.client.gameplayGeneration
            self.onEvent?(["t":"spawn","skin":effectiveSkin(info),"point":self.point,"heading":info.heading])
            guard self.client.gameplayGeneration==generation else{return}
            self.onEvent?(["t":"position","point":self.point,"heading":info.heading])
            guard self.client.gameplayGeneration==generation,self.client.state == .spawned else{return}
            // Class selection clears NMP's old actor/controller ownership.
            // The server may retain unchanged stream membership across spawn,
            // so republish only the actual current Client streamed snapshots.
            self.client.onRoster?(self.client.roster)
            guard self.client.gameplayGeneration==generation,self.client.state == .spawned else{return}
            self.client.onVehicles?(self.client.vehicles.values.sorted{$0.id<$1.id})
            guard self.client.gameplayGeneration==generation,self.client.state == .spawned else{return}
            self.client.onPlayers?(self.client.players.values.sorted{$0.id<$1.id})
        }
        client.onPosition = { [weak self] point,heading in guard let self else{return};self.point=NativeSAMPPedCoordinates.feet(point);var event:[String:Any]=["t":"position","point":self.point];if let heading{event["heading"]=heading};self.onEvent?(event) }
        client.onHeading = { [weak self] heading in guard let self else{return};self.onEvent?(["t":"position","point":self.point,"heading":heading]) }
        client.onEnvironment = { [weak self] hour,minute,weather,running in
            guard let self else{return};let now=Date().timeIntervalSince1970*1000
            if self.clockRunning{self.clockMinute += max(0,now-self.clockEpoch)/1000}
            if let hour{self.clockMinute=Double(hour*60+(minute ?? 0))}
            if let running{self.clockRunning=running};self.clockEpoch=now
            if let weather{self.worldWeather=weather}
            var packet:[String:Any]=["t":"environment","shift":self.clockMinute*1000-now,"hold":self.clockRunning ? NSNull():self.clockMinute*1000]
            if let weather=self.worldWeather{packet["weather"]=weather};self.onEvent?(packet)
        }
        client.onInterior = { [weak self]in self?.onEvent?(["t":"interior","id":Int($0)]) }
        client.onSpecialAction = { [weak self]in self?.onEvent?(["t":"specialAction","id":Int($0)]) }
        client.onSkin = { [weak self]in self?.onEvent?(["t":"skin","id":$0]) }
        client.onPreciseVitals = { [weak self] hp,ap in var event:[String:Any]=["t":"vitals"];if let hp{event["health"]=hp};if let ap{event["armour"]=ap};self?.onEvent?(event) }
        client.onChat = { [weak self]in self?.onEvent?(["t":"chat","text":$0]) }
        client.onEnter = { [weak self] id,seat in
            guard let self else{return}
            self.pendingServerEnter=(id,seat,self.client.gameplayGeneration);self.flushServerEnter()
        }
        client.onExit = { [weak self]in self?.onEvent?(["t":"exitForced"]) }
        client.onWeaponCommand = { [weak self] command in
            var event:[String:Any]=["t":"weapon"]
            switch command{case .give(let id,let amount):event.merge(["action":"give","id":id,"amount":amount]){_,new in new}
            case .ammo(let id,let amount):event.merge(["action":"ammo","id":id,"amount":amount]){_,new in new}
            case .reset:event["action"]="reset"
            case .select(let id):event.merge(["action":"select","id":id]){_,new in new}}
            self?.onEvent?(event)
        }
        client.onRawRPC = { [weak self]in self?.onEvent?(["t":"rpc","id":Int($0.id),"data":$0.data,"bits":$0.bits]) }
        client.onPlayers = { [weak self] values in
            guard let self else{return}
            self.lastPlayers=values
            let rows=values.filter{$0.id != self.client.localID}.compactMap {p->RemotePlayer? in
                guard let skin=p.customSkin.flatMap({(20001...30000).contains($0) ? $0:nil}) ?? self.skinCatalog?.nativeSkin(forLegacy:p.skin)else{
                    if self.skinCatalog != nil,self.unsupportedSkins.insert(p.skin).inserted{self.onStatus?("SKIN \(p.skin) NEEDS ITS ORIGINAL MODEL ASSETS")};return nil
                }
                let vehicle=p.vehicle.flatMap{self.client.vehicles[$0]}
                if p.vehicle != nil,vehicle==nil{return nil}
                let code=vehicle.map{"\($0.model).\($0.colors[0]).\($0.colors[1]).0."} ?? "s\(skin)"
                let speed=sqrt(p.velocity.x*p.velocity.x+p.velocity.y*p.velocity.y)
                let position:SIMD3<Float>
                if let vehicle {
                    guard let body=self.nativeVehiclePosition(p.position,model:vehicle.model,heading:p.heading,pitch:p.pitch,roll:p.roll)else{return nil};position=body
                }else{position=NativeSAMPPedCoordinates.feet(p.position)}
                return RemotePlayer(id:String(p.id),name:p.name,position:position,code:code,heading:p.heading,pitch:p.pitch,roll:p.roll,speed:speed,steer:0,skin:skin,animation:speed>0.15 ? "run_player/l/1":"idle_stance/l/1",animationStarted:ProcessInfo.processInfo.systemUptime,weapon:p.weapon,vehicleID:p.vehicle.map(String.init),vehicleHealth:vehicle.map{Int(max(0,min(1000,$0.health)))} ?? 1000,movementRatio:min(3,speed/2),velocity:p.velocity,life:p.health,armour:p.armour)
            };self.onPlayers?(rows)
        }
        client.onVehicles = { [weak self] values in
            guard let self else{return}
            self.onVehicles?(values.compactMap{v in
                guard let p=self.nativeVehiclePosition(v.position,model:v.model,heading:v.heading,pitch:v.pitch,roll:v.roll)else{return nil}
                return RemoteVehicle(row:[String(v.id),"Vehicle \(v.model)","\(v.model).\(v.colors[0]).\(v.colors[1]).0.",p.x,p.y,p.z,-v.heading,v.pitch,-v.roll,Int(max(0,min(1000,v.health)))])
            })
            self.client.onPlayers?(self.client.players.values.sorted{$0.id<$1.id});self.flushServerEnter()
        }
    }
    private func nativeVehiclePosition(_ root:SIMD3<Float>,model:Int,heading:Float,pitch:Float,roll:Float)->SIMD3<Float>? {
        guard let coordinates=vehicleCoordinates else {
            if !requiresVehicleCoordinates{return root}
            if unavailableVehicleModels.insert(model).inserted{onStatus?("WAITING FOR NATIVE VEHICLE \(model) ORIGIN METADATA")};return nil
        }
        guard let q=try?NativeSAMPVehicleCoordinates.rotation(heading:heading,pitch:pitch,roll:roll),
              let body=try?coordinates.body(root,model:model,rotation:q)else {
            if unavailableVehicleModels.insert(model).inserted{onStatus?("VEHICLE \(model) HAS NO VERIFIED NATIVE ORIGIN")};return nil
        }
        return body
    }
    private func networkVehiclePosition(_ body:SIMD3<Float>,id:UInt16,rotation:SIMD4<Float>)->SIMD3<Float>? {
        guard let coordinates=vehicleCoordinates else{return requiresVehicleCoordinates ? nil:body}
        guard let model=client.vehicles[id]?.model else{return nil}
        return try?coordinates.root(body,model:model,rotation:rotation)
    }
    private func flushServerEnter(){
        guard let pending=pendingServerEnter else{return}
        guard pending.generation==client.gameplayGeneration else{pendingServerEnter=nil;return}
        guard let vehicle=client.vehicles[pending.id],nativeVehiclePosition(vehicle.position,model:vehicle.model,heading:vehicle.heading,pitch:vehicle.pitch,roll:vehicle.roll) != nil else{return}
        pendingServerEnter=nil;onEvent?(["t":"enter","id":String(pending.id),"seat":Int(pending.seat)])
    }
    @discardableResult func send(_ message:[String:Any])->Bool {
        func number(_ key:String)->Float{(message[key]as?NSNumber)?.floatValue ?? 0}
        func byte(_ key:String)->UInt8{UInt8(max(0,min(255,number(key))))}
        func vector(_ key:String)->SIMD3<Float>?{guard let a=message[key]as?[NSNumber],a.count==3 else{return nil};let p=SIMD3(a[0].floatValue,a[1].floatValue,a[2].floatValue);return p.x.isFinite && p.y.isFinite && p.z.isFinite ? p:nil}
        func deathAfterSync(_ sent:Bool,health:UInt8){
            guard sent,health==0,!lastDeath else{return}
            let reason=UInt8(max(0,min(255,(message["deathReason"]as?Int) ?? 255)))
            let killer=UInt16(max(0,min(65535,(message["deathKiller"]as?Int) ?? 65535)))
            lastDeath=client.reportDeath(reason:reason,killer:killer)
        }
        switch message["t"]as?String {
        case "class":client.requestClass((message["index"]as?Int) ?? 0);return true
        case "classStep":guard let delta=message["delta"]as?Int,delta == -1 || delta==1 else{return false};client.requestClass(client.classIndex+delta);return true
        case "spawn":client.requestSpawn();return true
        case "chat":guard let line=message["text"]as?String else{return false};client.sendChat(line);return state == .ready || client.state == .selecting
        case "rpc":guard let data=message["data"]as?Data else{return false};return client.send(data)
        case "spectator":
            guard let point=vector("point")else{return false}
            let keys=UInt16(max(0,min(65535,number("keys"))))
            let axes=SIMD2<Int16>(Int16(max(-128,min(128,number("lr")))),Int16(max(-128,min(128,number("ud")))))
            return client.sendSpectatorPosition(point,keys:keys,axes:axes)
        case "enter":
            guard let text=message["v"]as?String,let id=UInt16(text)else{return false}
            guard !client.players.values.contains(where:{$0.id != client.localID && $0.vehicle==id})else{
                onStatus?("VEHICLE OCCUPIED — NATIVE JACKING IS NOT AVAILABLE YET");return false
            }
            // Legacy EnterVehicle is a notification. NMP.requestEnter owns
            // exactly one local boarding callback after this send succeeds.
            return client.enterVehicle(id)
        case "exit":
            guard let text=message["v"]as?String,let id=UInt16(text)else{return false}
            let generation=client.gameplayGeneration
            if let parked=message["parked"]as?[String:Any]{
                func field(_ name:String)->Float?{guard let value=(parked[name]as?NSNumber)?.floatValue,value.isFinite else{return nil};return value}
                guard let x=field("x"),let y=field("y"),let z=field("z"),let hp=field("health")else{return false}
                let previous=client.lastQueuedCar.flatMap{$0.id==id ? $0:nil}
                let explicit=(message["rotation"]as?[NSNumber]).flatMap{values->SIMD4<Float>? in
                    guard values.count==4 else{return nil};return SIMD4(values[0].floatValue,values[1].floatValue,values[2].floatValue,values[3].floatValue)
                }
                guard let rotation=explicit ?? previous?.quaternion else{onStatus?("FINAL VEHICLE SNAPSHOT NEEDS ITS ACTUAL ROTATION");return false}
                var final=previous ?? NativeSAMPProtocol.Car(id:id,position:SIMD3(x,y,z),quaternion:rotation)
                guard let position=networkVehiclePosition(SIMD3(x,y,z),id:id,rotation:rotation)else{return false}
                final.position=position;final.quaternion=rotation;final.health=hp
                final.playerHealth=byte("life");final.armour=byte("armour");final.keys=0;final.lr=0;final.ud=0;final.specialKeys=0
                guard client.sendCar(final),client.gameplayGeneration==generation,client.state == .spawned else{return false}
            }
            return client.exitVehicle(id)
        case "respawn":client.requestRespawn();return true
        case "takingDamage":
            guard state == .ready,!client.spectating,let amount=(message["amount"]as?NSNumber)?.floatValue,
                  let weapon=message["weapon"]as?Int,let source=message["source"]as?Int,(0...65535).contains(source),
                  let body=message["body"]as?Int,
                  let packet=try?NativeSAMPProtocol.damage(taking:true,player:UInt16(source),amount:amount,weapon:weapon,body:body)else{return false}
            return client.send(packet)
        case "me":
            guard state == .ready else{return false}
            let position=SIMD3(number("x"),number("y"),number("z"));point=position
            let velocity=SIMD3(number("vx"),number("vy"),number("vz"))/50
            let keys=UInt16(max(0,min(65535,number("keys")))),lr=Int16(max(-128,min(128,number("lr")))),ud=Int16(max(-128,min(128,number("ud"))))
            let special=UInt8(max(0,min(3,number("specialKeys"))))
            if message["driving"]as?Bool==true {
                guard let text=message["vehicle"]as?String,let id=UInt16(text),let rotation=message["rotation"]as?[NSNumber],rotation.count==4 else{return false}
                var car=NativeSAMPProtocol.Car(id:id,position:position,quaternion:SIMD4(rotation[0].floatValue,rotation[1].floatValue,rotation[2].floatValue,rotation[3].floatValue))
                guard let root=networkVehiclePosition(position,id:id,rotation:car.quaternion)else{return false};car.position=root
                car.velocity=velocity;car.health=number("health");car.playerHealth=byte("life");car.armour=byte("armour");car.weapon=byte("weapon");car.siren=number("horn")>=2 ? 1:0
                car.keys=keys;car.lr=lr;car.ud=ud;car.specialKeys=special
                let sent=client.sendCar(car);deathAfterSync(sent,health:car.playerHealth);return sent
            }
            var foot=NativeSAMPProtocol.Foot(position:NativeSAMPPedCoordinates.root(position),heading:-number("heading"));foot.velocity=velocity;foot.health=byte("health");foot.armour=byte("armour");foot.weapon=byte("weapon");foot.keys=keys;foot.lr=lr;foot.ud=ud;foot.specialKeys=special
            if message["crouch"]as?Bool==true{foot.action=1}
            if (60...62).contains((message["act"]as?Int ?? 0)&63){foot.action=2}
            let sent=client.sendFoot(foot)
            deathAfterSync(sent,health:foot.health)
            return sent
        case "shot":
            guard state == .ready,client.controllable,!client.spectating,let origin=vector("o"),let hit=vector("h"),let weapon=message["w"]as?Int else{return false}
            let target=(message["target"]as?String).flatMap(UInt16.init),victim=target.flatMap{client.players[$0]}
            // Hit/origin are physical world points. Victim positions here are
            // still raw CPed roots; SA-MP offsets are relative to that root,
            // so converting the victim to renderer feet would add a false1m.
            guard let bullet=try?NativeSAMPProtocol.bullet(weapon:weapon,origin:origin,hit:hit,target:target,offset:victim.map{hit-$0.position} ?? .zero),client.send(bullet,reliability:7)else{return false}
            if let target,let damage=weaponDamage?(weapon),let packet=try?NativeSAMPProtocol.damage(taking:false,player:target,amount:damage,weapon:weapon){_=client.send(packet)}
            return true
        case "melee":
            guard state == .ready,client.controllable,!client.spectating,let text=message["to"]as?String,let target=UInt16(text),let weapon=message["weapon"]as?Int,let damage=weaponDamage?(weapon),let packet=try?NativeSAMPProtocol.damage(taking:false,player:target,amount:damage,weapon:weapon)else{return false};return client.send(packet)
        default:return false
        }
    }
}
