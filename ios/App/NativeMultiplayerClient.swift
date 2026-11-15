import Foundation
import simd
import CoreFoundation

struct RemotePlayer {
    let id: String
    let name: String
    let position: SIMD3<Float>
    let code: String
    let heading: Float
    let pitch: Float
    let roll: Float
    let speed: Float
    let steer: Float
    let skin: Int
    let animation: String
    let animationStarted: Double
    let weapon: Int
    let vehicleID: String?
    var vehicleHealth = 1000
    var vehicleDamage = ""
    var lights = false
    var horn = 0
    var movementRatio:Float = 0
    var airborne = false
    var crouching = false
    var aim:Float?
    var action = 0
    var velocity = SIMD3<Float>.zero
    var angularVelocity = SIMD3<Float>.zero
    var shotCount = 0
    var paused = false
    var down = 0
    var scriptAnimation:String?
    var ridingVehicleID:String?
    var ridingSeat = 0
    var supportVehicleID:String?
    var supportOffset = SIMD3<Float>.zero
    var kit:[Float]?
    var packetReceivedAt:Double = 0
    var packetClockMilliseconds:Double = 0
    var latencyMilliseconds:Float = 0
    var life = 100
    var armour = 0
    var swimState:Int { let base=action&63;return (10...16).contains(base) ? base-9:0 }
    var burning:Bool {action&64 != 0}
}

struct RemoteVehicle {
    let id: String
    let name: String
    let code: String
    var position: SIMD3<Float>
    var heading: Float
    var pitch: Float = 0
    var roll: Float = 0
    var health: Int
    var damage = ""
    var work = 0

    init?(row: [Any]) {
        guard row.count >= 7, let id = row[0] as? String,
              let name = row[1] as? String, let code = row[2] as? String,
              let x = (row[3] as? NSNumber)?.floatValue,
              let y = (row[4] as? NSNumber)?.floatValue,
              let z = (row[5] as? NSNumber)?.floatValue else { return nil }
        self.id = id
        self.name = name
        self.code = code
        position = SIMD3(x, y, z)
        heading = -((row[6] as? NSNumber)?.floatValue ?? 0)
        pitch = row.count > 7 ? (row[7] as? NSNumber)?.floatValue ?? 0 : 0
        roll = row.count > 8 ? -((row[8] as? NSNumber)?.floatValue ?? 0) : 0
        health = max(0, min(1000, (row.count > 9 ? row[9] as? NSNumber : nil)?.intValue ?? 1000))
        damage = row.count > 10 ? row[10] as? String ?? "" : ""
        work = row.count > 16 ? (row[16] as? NSNumber)?.intValue ?? 0 : 0
    }
}

/// Sequence local environmental damage separately from authoritative damage.
/// A delayed server hit/HTTP snapshot rebases pending losses instead of
/// restoring lost health or applying the same fall twice.
struct NativeHealthPrediction {
    struct Request {let sequence:Int;let connection:String;let kind:String;let damage:Int}
    private(set) var connection:String?
    private(set) var issued=0,processed=0,revision=0
    private var baseHealth=100,baseArmour=0
    private var losses:[Int:Int]=[:]
    private var respawnSequence:Int?
    var health:Int {max(0,baseHealth-losses.values.reduce(0,+))}
    var armour:Int {baseArmour}
    var active:Bool {connection != nil}
    var pendingRespawn:Int? {respawnSequence}
    mutating func disconnect(){self=NativeHealthPrediction()}
    mutating func begin(connection:String,health:Int,armour:Int,revision:Int,processed:Int){
        disconnect();self.connection=connection;baseHealth=health;baseArmour=armour
        self.revision=revision;self.processed=processed;issued=processed
    }
    mutating func hurt(to value:Int)->Request? {
        guard let connection,issued<9_007_199_254_740_991,losses.count<128 else{return nil}
        let damage=health-max(0,min(health,value))
        guard damage>0 else{return nil}
        issued+=1;losses[issued]=damage
        return Request(sequence:issued,connection:connection,kind:"hurt",damage:damage)
    }
    mutating func respawn()->Request? {
        guard let connection,health==0,respawnSequence==nil,issued<9_007_199_254_740_991 else{return nil}
        issued+=1;respawnSequence=issued
        return Request(sequence:issued,connection:connection,kind:"respawn",damage:0)
    }
    mutating func apply(health:Int,armour:Int,connection:String,processed:Int,revision:Int)->Bool {
        guard self.connection==connection,(0...100).contains(health),(0...100).contains(armour),
              processed>=self.processed,processed<=issued,revision>=self.revision,
              revision != self.revision || (processed==self.processed && health==baseHealth && armour==baseArmour) else{return false}
        self.processed=processed;self.revision=revision;baseHealth=health;baseArmour=armour
        losses=losses.filter{$0.key>processed}
        if let sequence=respawnSequence,sequence<=processed {respawnSequence=nil}
        return true
    }
    static func integer(_ value:Any?)->Int? {
        guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite,
              n.doubleValue>=0,n.doubleValue<=9_007_199_254_740_991,n.doubleValue.rounded(.down)==n.doubleValue else{return nil}
        return n.intValue
    }
}

/// Speaks the existing local server's WebSocket protocol without Discord.
/// Browser heading/roll are Three Y-yaw/Z-roll. GTA native controls use the
/// opposite signs for those two angles; convert once at this wire boundary.
final class NativeMultiplayerClient {
    typealias ConnectionState = NativeConnectionRecovery.State
    private let server: ServerAddress
    private let session: URLSession
    private let clock: () -> Double
    private let automaticRecoveryTimer: Bool
    private var recovery = NativeConnectionRecovery()
    private var recoveryTimer: DispatchSourceTimer?
    private var transportGeneration: UInt64 = 0
    private var lastPing: Double = -.infinity
    private(set) var state: ConnectionState = .stopped
    var isReady: Bool { recovery.state == .ready && socket != nil }
    var onConnectionState: ((ConnectionState) -> Void)?
    private var socket: URLSessionWebSocketTask?
    private(set) var players: [String: RemotePlayer] = [:]
    private(set) var vehicles: [String: RemoteVehicle] = [:]
    private var playerOrder:[String]=[],vehicleOrder:[String]=[]
    var orderedPlayers:[RemotePlayer] {playerOrder.compactMap{players[$0]}}
    var orderedVehicles:[RemoteVehicle] {vehicleOrder.compactMap{vehicles[$0]}}
    private var remoteAnimationTimes: [String: (String, Double)] = [:]
    private var shots = 0
    private let shotSequence = NativeShotSequence()
    private let streamShotClaims = NativeStreamShotClaims()
    private var healthPrediction=NativeHealthPrediction()
    private var deliveredRespawnSequence=0
    private var resynchronizingInventory = false
    private var announcedInventoryConnection: String?
    var inventoryConnection: String? { shotSequence.connection }
    var onInventoryConnection: ((String?) -> Void)?
    private(set) var localName = "LOCAL PLAYER"
    private(set) var cash = 0
    private(set) var health = 100
    private(set) var armour = 0
    private(set) var passive = false
    private(set) var serverTimeOffsetMilliseconds:Double = 0
    private var positionPackets = 0
    private var pendingSays: [String] = []
    private var lastChatSequence = 0
    private(set) var chatMessages: [String] = []
    var onStatus: ((String) -> Void)?
    var onPlayers: (([RemotePlayer]) -> Void)?
    var onPresence: ((Int, [String]) -> Void)?
    var onVehicles: (([RemoteVehicle]) -> Void)?
    /// Explicit despawn differs from omission in a streamed vehicle list.
    var onVehicleRemoved: ((String) -> Void)?
    var onEnter: ((String, Bool) -> Void)?
    var onTeleport: ((SIMD3<Float>, Float?) -> Void)?
    var onEnvironment: ((Int?, Double?, Double?) -> Void)?
    var onInventory: (([String: Any]) -> Void)?
    var onProjectiles: (([[String: Any]]) -> Void)?
    var onBlast: ((Int, SIMD3<Float>) -> Void)?
    var onWeaponSound: ((Int) -> Void)?
    var onVitals: ((Int, Int) -> Void)?
    var onRespawn: (() -> Void)?
    var onFlightGear: ((Bool,Bool) -> Void)?
    var onChat: (([String]) -> Void)?

    init(server: ServerAddress, session: URLSession = .shared,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         automaticRecoveryTimer: Bool = true) {
        self.server = server; self.session = session; self.clock = clock
        self.automaticRecoveryTimer = automaticRecoveryTimer
    }
    deinit { recoveryTimer?.cancel(); socket?.cancel(with: .normalClosure, reason: nil) }

    func connect() {
        resynchronizingInventory = false
        startRecoveryTimer()
        run(recovery.start(now: clock()))
    }
    func disconnect() {
        recovery.stop(); resynchronizingInventory = false
        recoveryTimer?.cancel(); recoveryTimer = nil
        closeSocket(); publishState()
    }
    func setApplicationActive(_ active: Bool) {
        recovery.setActive(active, now: clock())
        if active { lastPing = -.infinity; tickConnection(now: clock()) }
    }
    func tickConnection(now: Double) {
        run(recovery.tick(now: now))
        if recovery.active, socket != nil, now.isFinite, now-lastPing >= 2 {
            lastPing = now
            send(["t": "ping", "c": now * 1000], allowBeforeReady: true)
        }
    }
    private func startRecoveryTimer() {
        guard automaticRecoveryTimer, recoveryTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            guard let self else { return }; self.tickConnection(now: self.clock())
        }
        recoveryTimer = timer; timer.resume()
    }
    private func publishState() {
        guard state != recovery.state else { return }
        state = recovery.state; onConnectionState?(state)
        if state == .ready { onStatus?("ONLINE AS \(localName.uppercased())") }
    }
    private func run(_ action: NativeConnectionRecovery.Action?) {
        publishState()
        switch action {
        case .open(let generation): openSocket(generation: generation)
        case .timeout(let generation): failTransport(generation: generation, reason: "CONNECTION TIMED OUT — RECONNECTING")
        case nil: break
        }
    }
    private func openSocket(generation: UInt64) {
        guard recovery.desired, recovery.hasTransport, recovery.generation == generation else { return }
        closeSocket()
        guard recovery.desired, recovery.hasTransport, recovery.generation == generation else { return }
        transportGeneration = generation; lastPing = -.infinity
        guard var parts = URLComponents(url: server.path("api/world/live"), resolvingAgainstBaseURL: false) else {
            failTransport(generation: generation, reason: "INVALID MULTIPLAYER ADDRESS"); return
        }
        parts.scheme = server.url.scheme == "https" ? "wss" : "ws"
        guard let url = parts.url else { failTransport(generation: generation, reason: "INVALID MULTIPLAYER ADDRESS"); return }
        let task = session.webSocketTask(with: url)
        socket = task; task.resume()
        send(["t": "hi", "nativeInventory": true, "inventoryAck": 1,"healthAck":1], allowBeforeReady: true)
        receive()
    }
    private func closeSocket() {
        let old = socket; socket = nil
        old?.cancel(with: .normalClosure, reason: nil)
        shotSequence.reset(); streamShotClaims.reset(); announcedInventoryConnection = nil
        healthPrediction.disconnect()
        deliveredRespawnSequence=0
        onInventoryConnection?(nil)
        // A fresh peer has a fresh row/clock/shot namespace. Never carry a
        // previous driver, remote actor, projectile or queued command into it.
        players.removeAll(); vehicles.removeAll(); playerOrder.removeAll(); vehicleOrder.removeAll()
        remoteAnimationTimes.removeAll(); pendingSays.removeAll(); shots = 0; positionPackets = 0
        lastChatSequence = 0; chatMessages.removeAll(); serverTimeOffsetMilliseconds = 0
        onPlayers?([]); onVehicles?([]); onProjectiles?([]); onPresence?(0, []); onChat?([])
    }
    private func failTransport(generation: UInt64, reason: String) {
        guard recovery.failed(generation: generation, now: clock()) else { return }
        resynchronizingInventory = false
        closeSocket(); publishState(); onStatus?("MULTIPLAYER: \(reason)")
    }

    /// Uncertain writes are settled by a new authoritative peer, never replayed.
    func requestInventoryResync() {
        guard recovery.desired, !resynchronizingInventory else { return }
        resynchronizingInventory = true
        let action = recovery.restart(now: clock())
        closeSocket(); run(action)
    }
    func reserveShot() -> NativeShotTicket? {
        guard isReady, socket != nil, health > 0, !passive else { return nil }
        return shotSequence.reserve()
    }

    func sendPosition(_ position: SIMD3<Float>, heading: Float, moving: Bool, running: Bool,
                      vehicle: RemoteVehicle? = nil, speed: Float = 0,
                      steer: Float = 0, pitch: Float = 0, roll: Float = 0,
                      vehicleHealth: Int = 1000,
                      vehicleDamage: String = "",lights: Bool = false,horn: Bool = false,siren:Bool=false,
                      airborne: Bool = false, weapon: Int = 0, firing: Bool = false,
                      animation: String? = nil, crouching: Bool = false,
                      swimState: Int = 0,swimPitch: Float = 0,swimRatio: Float = 0,
                      movement:Double? = nil,aim:Double? = nil,action:Int = 0,
                      velocity:SIMD3<Float> = .zero,angularVelocity:SIMD3<Float> = .zero,
                      kit:[Double]? = nil,paused:Bool = false) {
        guard isReady else { return }
        func rounded(_ value:Double)->Double {value.isFinite ? floor(value*100+0.5)/100:0}
        let motion:[String:Any] = ["vx":rounded(Double(velocity.x)),"vy":rounded(Double(velocity.y)),"vz":rounded(Double(velocity.z)),
            "wx":rounded(Double(angularVelocity.x)),"wy":rounded(Double(angularVelocity.y)),"wz":rounded(Double(angularVelocity.z)),
            "clock":Date().timeIntervalSince1970*1000,"paused":paused]
        if let vehicle {
            var packet: [String: Any] = ["t": "me", "driving": true, "car": vehicle.code,
                  "vehicle": vehicle.id, "skin": 7,
                  "x": Double(position.x), "y": Double(position.y), "z": Double(position.z),
                  "heading": -Double(heading), "pitch": Double(pitch), "roll": -Double(roll),
                  "speed": Double(speed), "steer": -Double(steer),
                  "health": vehicleHealth, "life": health, "armour": armour]
            packet["damage"] = vehicleDamage;packet["lights"] = lights;packet["horn"] = horn
            packet["act"]=action
            if siren {packet["horn"]=(horn ? 1:0)+2}
            packet.merge(motion){_,new in new};if let kit {packet["kit"]=kit}
            addPendingChat(to: &packet)
            send(packet)
            return
        }
        var packet: [String: Any] = ["t": "me", "walking": true, "skin": 7,
              "x": Double(position.x), "y": Double(position.y), "z": Double(position.z),
              "heading": -Double(heading), "health": health, "armour": armour,
              "weapon": weapon,
              "shots": shots,
              "crouch": crouching,
              "air": airborne,"act":action,
              "move":rounded(movement ?? (moving ? running ? 3:2:0)),
              "aim":aim.map{rounded($0)} ?? NSNull(),
              "anim":animation.flatMap{$0.isEmpty ? nil:NativePedestrianMotion.wireAnimation(for:$0)} ?? NSNull()]
        packet.merge(motion){_,new in new}
        if (50...62).contains(action&63),health>0 {
            packet["pitch"]=rounded(Double(pitch));packet["roll"]=rounded(Double(roll))
            if (50...58).contains(action&63) || (61...62).contains(action&63) {
                packet["move"]=0;packet["air"]=false;packet["crouch"]=false
            }
            if (50...58).contains(action&63) {packet["aim"]=NSNull()}
        }
        if (1...7).contains(swimState),health > 0 {
            packet["act"] = 9+swimState;packet["move"] = rounded(Double(swimRatio))
            packet["air"] = false;packet["crouch"] = false;packet["weapon"] = 0
            packet["aim"] = NSNull();packet["pitch"] = rounded(Double(swimPitch))
        }
        addPendingChat(to: &packet)
        send(packet)
        positionPackets += 1
        if positionPackets % 10 == 0 { send(["t": "board"]) }
    }

    func sendChat(_ line: String) {
        guard isReady else { onStatus?("OFFLINE — MESSAGE NOT SENT"); return }
        let trimmed = String(line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        guard !trimmed.isEmpty else { return }
        pendingSays.append(trimmed)
    }

    private func addPendingChat(to packet: inout [String: Any]) {
        if !pendingSays.isEmpty { packet["say"] = pendingSays.removeFirst() }
    }

    private func receiveChat(_ rows: [[Any]]) {
        var changed = false
        for row in rows {
            guard row.count >= 3,
                  let sequence = row[0] as? Int, sequence > lastChatSequence,
                  let name = row[1] as? String,
                  let line = row[2] as? String else { continue }
            lastChatSequence = sequence
            chatMessages.append("\(name): \(line)")
            changed = true
        }
        if changed {
            chatMessages = Array(chatMessages.suffix(50))
            onChat?(chatMessages)
        }
    }

    func requestEnter(_ vehicle: RemoteVehicle) { send(["t": "enter", "v": vehicle.id]) }
    func sendVehicleMove(_ id:String, state:[String:Any]) {
        var packet=state
        packet["t"]="vmove";packet["v"]=id
        send(packet)
    }
    func usedParachute() {send(["t":"usedParachute"])}
    func detonateSatchels() { send(["t":"detonate"]) }

    /// Public strike counter animates remote misses as well as damaging hits.
    /// It is independent of gun ammunition sequences and victim selection.
    @discardableResult func recordMeleeStrike(weapon: Int) -> Bool {
        guard isReady,socket != nil,health>0,!passive,(0...15).contains(weapon),inventoryConnection != nil else{return false}
        shots += 1
        return true
    }

    @discardableResult func sendMeleeHit(to player: String, weapon: Int = 0) -> Bool {
        guard isReady,socket != nil, health > 0, !passive, (0...15).contains(weapon),
              let connection = inventoryConnection else { return false }
        send(["t": "hit", "to": player, "w": weapon, "c": connection])
        return true
    }

    @discardableResult func sendPistolShot(from origin: SIMD3<Float>, to hit: SIMD3<Float>,
                        player: String?, ticket: NativeShotTicket? = nil) -> Bool {
        sendWeaponShot(weapon: 22, from: origin, to: hit, player: player, ticket: ticket)
    }

    @discardableResult func sendWeaponShot(weapon: Int, from origin: SIMD3<Float>, to hit: SIMD3<Float>,
                        player: String?, ticket: NativeShotTicket? = nil,streamPlayers:[String]=[]) -> Bool {
        guard isReady,let task = socket, health > 0, !passive, let ticket,
              ticket.connection == inventoryConnection, shotSequence.claim(ticket) else { return false }
        let effectTargets=NativeStreamShotClaims.normalized(streamPlayers)
        shots += 1
        let shot: [String: Any] = ["t": "shot", "w": weapon, "s": ticket.sequence, "c": ticket.connection,
                                   "o": [Double(origin.x), Double(origin.y), Double(origin.z)],
                                   "h": [Double(hit.x), Double(hit.y), Double(hit.z)]]
        guard let data = try? JSONSerialization.data(withJSONObject: shot), let text = String(data: data, encoding: .utf8) else {
            requestInventoryResync(); return false
        }
        task.send(.string(text)) { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.socket === task, self.inventoryConnection == ticket.connection else { return }
                if let error { self.failTransport(generation: self.transportGeneration, reason: error.localizedDescription); return }
                if NativeStreamShotTargets.weapons.contains(weapon) {
                    let targets=self.streamShotClaims.take(weapon:weapon,connection:ticket.connection,players:effectTargets,
                        milliseconds:ProcessInfo.processInfo.systemUptime*1000)
                    for target in targets {self.send(["t":"hit","to":target,"w":weapon,"s":ticket.sequence,"c":ticket.connection])}
                } else if let player { self.send(["t": "hit", "to": player, "w": weapon, "s": ticket.sequence, "c": ticket.connection]) }
            }
        }
        return true
    }

    func respawn() {
        guard health == 0 else { return }
        if healthPrediction.active {
            guard isReady,let request=healthPrediction.respawn() else{return}
            sendHealthRequest(request);return
        }
        health = 100
        armour = 0
        onVitals?(health, armour)
        onRespawn?()
    }

    func syncVitals(from state: [String: Any]) {
        if healthPrediction.active {_=applyAcknowledgedVitals(state);return}
        guard let current = state["health"] as? NSNumber,
              let protected = state["armour"] as? NSNumber else { return }
        let nextHealth = max(0, min(100, current.intValue))
        let nextArmour = max(0, min(100, protected.intValue))
        guard health != nextHealth || armour != nextArmour else { return }
        health = nextHealth
        armour = nextArmour
        onVitals?(health, armour)
    }

    func reportLocalHealth(_ value:Int) {
        if healthPrediction.active {
            guard isReady,let request=healthPrediction.hurt(to:value) else{return}
            health=healthPrediction.health;armour=healthPrediction.armour;onVitals?(health,armour)
            sendHealthRequest(request);return
        }
        health=max(0,min(health,value));onVitals?(health,armour)
    }

    private func sendHealthRequest(_ request:NativeHealthPrediction.Request) {
        send(["t":"selfHealth","c":request.connection,"s":request.sequence,
              "kind":request.kind,"damage":request.damage])
    }
    @discardableResult private func applyAcknowledgedVitals(_ state:[String:Any])->Bool {
        let pendingRespawn=healthPrediction.pendingRespawn
        let epoch=transportGeneration
        guard let ack=state["healthAck"] as? [String:Any],let connection=ack["connection"] as? String,
              let processed=NativeHealthPrediction.integer(ack["processed"]),
              let revision=NativeHealthPrediction.integer(ack["revision"]),
              let hp=NativeHealthPrediction.integer(state["health"]),let armour=NativeHealthPrediction.integer(state["armour"]),
              healthPrediction.apply(health:hp,armour:armour,connection:connection,processed:processed,revision:revision) else{return false}
        health=healthPrediction.health;self.armour=healthPrediction.armour;onVitals?(health,self.armour)
        if let sequence=pendingRespawn,processed>=sequence,health>0,isReady,transportGeneration==epoch,
           healthPrediction.connection==connection,
           NativeHealthPrediction.integer(ack["respawned"])==sequence,sequence>deliveredRespawnSequence {
            deliveredRespawnSequence=sequence;onRespawn?()
        }
        return true
    }

    func sendExit(_ feet: SIMD3<Float>, parked position: SIMD3<Float>, heading: Float, pitch: Float, roll: Float,
                  vehicle: RemoteVehicle, vehicleHealth: Int,vehicleDamage: String = "") {
        guard isReady else { return }
        var parked=vehicle;parked.position=position;parked.heading=heading;parked.pitch=pitch;parked.roll=roll
        if vehicles[vehicle.id]==nil {vehicleOrder.append(vehicle.id)}
        parked.health=vehicleHealth;parked.damage=vehicleDamage;vehicles[vehicle.id]=parked
        onVehicles?(orderedVehicles)
        send(["t": "me", "walking": true, "skin": 7,
              "vehicle": vehicle.id, "car": vehicle.code,
              "x": Double(feet.x), "y": Double(feet.y), "z": Double(feet.z),
              "heading": -Double(heading), "health": health, "armour": armour,
              "parked": ["x": Double(position.x), "y": Double(position.y),
                         "z": Double(position.z), "heading": -Double(heading),
                         "pitch": Double(pitch), "roll": -Double(roll), "health": vehicleHealth,"damage":vehicleDamage]])
    }

    private func send(_ object: [String: Any], allowBeforeReady: Bool = false) {
        guard isReady || allowBeforeReady else { return }
        guard let task = socket, let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            DispatchQueue.main.async {
                guard let self, self.socket === task else { return }
                self.failTransport(generation: self.transportGeneration, reason: error.localizedDescription)
            }
        }
    }

    private func receive() {
        guard let task = socket else { return }
        let generation = transportGeneration
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.socket === task, self.transportGeneration == generation else { return }
                switch result {
                case .failure(let error):
                    self.failTransport(generation: self.transportGeneration, reason: error.localizedDescription)
                case .success(let message):
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: return
                    }
                    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { self.handle(object, generation: generation) }
                    guard self.socket === task, self.transportGeneration == generation else { return }
                    self.receive()
                }
            }
        }
    }

    private func handle(_ message: [String: Any], generation: UInt64) {
        switch message["t"] as? String {
        case "pong":
            if let echoed = (message["c"] as? NSNumber)?.doubleValue, echoed.isFinite,
               let time = (message["s"] as? NSNumber)?.doubleValue, time.isFinite {
                recovery.received(generation: generation, now: clock())
            }
        case "projectiles":
            if let rows = message["rows"] as? [[String: Any]] { onProjectiles?(rows) }
        case "projectile":
            if let event = message["event"] as? [String:Any], event["type"] as? String == "blast",
               let weapon = event["weapon"] as? Int, let position = event["position"] as? [NSNumber], position.count == 3 {
                onBlast?(weapon,SIMD3(position[0].floatValue,position[1].floatValue,position[2].floatValue))
            }
        case "shot":
            if let weapon = message["w"] as? Int { onWeaponSound?(weapon) }
        case "inventory":
            if let state = message["state"] as? [String: Any], let ack = NativeInventoryAcknowledgement(state),
               ack.connection == inventoryConnection, NativeConnectionRecovery.validInventory(state) {
                shotSequence.observeAcknowledgement(ack.processedShot)
                resynchronizingInventory = false; onInventory?(state)
                recovery.received(.inventory, generation: generation, now: clock()); publishState()
            }
        case "hello":
            guard message["inventoryAck"] as? Int == 1, let nonce = message["inventoryConnection"] as? String,
                  shotSequence.negotiate(nonce) else {
                onStatus?("THIS SERVER NEEDS NATIVE INVENTORY ACKNOWLEDGEMENTS TO ENABLE FIRING"); return
            }
            let freshHello=announcedInventoryConnection != nonce
            if freshHello { announcedInventoryConnection = nonce; onInventoryConnection?(nonce) }
            guard transportGeneration==generation,socket != nil else{return}
            if let time=(message["time"] as? NSNumber)?.doubleValue,time.isFinite {serverTimeOffsetMilliseconds=time-Date().timeIntervalSince1970*1000}
            if freshHello,let spot = message["spot"] as? [NSNumber], spot.count >= 3 {
                onTeleport?(SIMD3(spot[0].floatValue,spot[1].floatValue,spot[2].floatValue),
                            spot.count > 3 ? -spot[3].floatValue : nil)
            }
            guard transportGeneration==generation,socket != nil else{return}
            let day = message["day"] as? [String: Any]
            onEnvironment?((message["weather"] as? NSNumber)?.intValue,
                           (day?["shift"] as? NSNumber)?.doubleValue,
                           (day?["hold"] as? NSNumber)?.doubleValue)
            guard transportGeneration==generation,socket != nil else{return}
            if let life = message["life"] as? [NSNumber], life.count >= 2 {
                let hp=max(0,min(100,life[0].intValue)),protected=max(0,min(100,life[1].intValue))
                var published=false
                if let ack=message["healthAck"] as? [String:Any],
                   let connection=ack["connection"] as? String,connection==inventoryConnection,
                   let processed=NativeHealthPrediction.integer(ack["processed"]),
                   let revision=NativeHealthPrediction.integer(ack["revision"]) {
                    if healthPrediction.connection==connection {
                        published=applyAcknowledgedVitals(["health":hp,"armour":protected,"healthAck":ack])
                        guard transportGeneration==generation,socket != nil else{return}
                    } else {
                        healthPrediction.begin(connection:connection,health:hp,armour:protected,revision:revision,processed:processed)
                        deliveredRespawnSequence=processed
                    }
                    health=healthPrediction.health;armour=healthPrediction.armour
                } else if healthPrediction.connection != nonce {
                    healthPrediction.disconnect();health=hp;armour=protected
                }
                if !published {onVitals?(health, armour)}
            }
            guard transportGeneration==generation,socket != nil else{return}
            recovery.received(.hello, generation: generation, now: clock()); publishState()
            send(["t": "board"], allowBeforeReady: true)
        case "weather":
            onEnvironment?((message["weather"] as? NSNumber)?.intValue ?? (message["w"] as? NSNumber)?.intValue, nil, nil)
        case "day":
            onEnvironment?(nil, (message["shift"] as? NSNumber)?.doubleValue,
                           (message["hold"] as? NSNumber)?.doubleValue)
        case "all":
            guard let name = message["you"] as? String, !name.isEmpty,
                  message["cars"] is [[Any]], message["vehicles"] is [[Any]],
                  message["chat"] is [[Any]], let amount = (message["cash"] as? NSNumber)?.doubleValue,
                  amount.isFinite else { return }
            localName = (message["you"] as? String) ?? localName
            cash = (message["cash"] as? Int) ?? cash
            if let rows = message["chat"] as? [[Any]] { receiveChat(rows) }
            updateRows(message["cars"])
            if let rows = message["vehicles"] as? [[Any]] {
                vehicles.removeAll();vehicleOrder.removeAll()
                for row in rows {
                    guard let vehicle=RemoteVehicle(row:row) else{continue}
                    if vehicles[vehicle.id]==nil {vehicleOrder.append(vehicle.id)}
                    vehicles[vehicle.id]=vehicle
                }
                onVehicles?(orderedVehicles)
            }
            recovery.received(.world, generation: generation, now: clock()); publishState()
        case "cars": updateRows(message["c"])
        case "gone":
            if let id = message["id"] as? String {
                players.removeValue(forKey:id); remoteAnimationTimes.removeValue(forKey:id)
                playerOrder.removeAll{$0==id};onPlayers?(orderedPlayers)
            }
        case "chat":
            if let rows = message["lines"] as? [[Any]] { receiveChat(rows) }
        case "board":
            let rows = (message["rows"] as? [[Any]]) ?? []
            let names = rows.compactMap { row -> String? in
                guard row.count > 1 else { return nil }
                return row[1] as? String
            }
            onPresence?((message["players"] as? Int) ?? rows.count, names)
        case "note":
            if let note = message["text"] as? String {
                onStatus?(note.uppercased())
                if note.hasPrefix("[Group]") {
                    chatMessages.append(note)
                    chatMessages = Array(chatMessages.suffix(50))
                    onChat?(chatMessages)
                }
            }
        case "passive":
            passive = message["on"] as? Bool == true
        case "flightgear":
            onFlightGear?(message["parachute"] as? Bool == true,message["jetpack"] as? Bool == true)
        case "vitals":
            if healthPrediction.active {_=applyAcknowledgedVitals(message);break}
            if let value = message["health"] as? Int { health = max(0, min(100,value)) }
            if let value = message["armour"] as? Int { armour = max(0,min(100,value)) }
            onVitals?(health, armour)
        case "hit":
            if healthPrediction.active {
                if applyAcknowledgedVitals(message),isReady {
                    onStatus?(health == 0 ? "DEFEATED — RESPAWN TO CONTINUE":"HIT — \(health) HEALTH REMAINING")
                }
                break
            }
            let damage = max(0, (message["d"] as? NSNumber)?.intValue ?? 0)
            let absorbed = min(armour, damage)
            armour -= absorbed
            health = max(0, health - (damage - absorbed))
            onVitals?(health, armour)
            onStatus?(health == 0 ? "DEFEATED — RESPAWN TO CONTINUE" :
                         "HIT — \(health) HEALTH REMAINING")
        case "veh", "spawned":
            if let row = message["v"] as? [Any], let vehicle = RemoteVehicle(row: row) {
                if vehicles[vehicle.id]==nil {vehicleOrder.append(vehicle.id)}
                vehicles[vehicle.id] = vehicle
                onVehicles?(orderedVehicles)
            }
        case "vgone":
            if let id = message["id"] as? String {
                vehicles.removeValue(forKey: id)
                vehicleOrder.removeAll{$0==id}
                onVehicleRemoved?(id)
                onVehicles?(orderedVehicles)
            }
        case "enter":
            if let id = message["v"] as? String { onEnter?(id, message["ok"] as? Bool == true) }
        case "tp":
            if let x = (message["x"] as? NSNumber)?.floatValue,
               let y = (message["y"] as? NSNumber)?.floatValue,
               let z = (message["z"] as? NSNumber)?.floatValue {
                onTeleport?(SIMD3(x, y, z), (message["h"] as? NSNumber).map { -$0.floatValue })
            }
        default: break
        }
    }

    private func updateRows(_ value: Any?) {
        guard let rows = value as? [[Any]] else { return }
        var updated: [String: RemotePlayer] = [:]
        var incomingOrder:[String]=[]
        for row in rows where row.count >= 6 {
            guard let id = row[0] as? String,
                  let name = row[1] as? String,
                  let x = (row[3] as? NSNumber)?.floatValue,
                  let y = (row[4] as? NSNumber)?.floatValue,
                  let z = (row[5] as? NSNumber)?.floatValue else { continue }
            if updated[id]==nil {incomingOrder.append(id)}
            let code = row[2] as? String ?? "s7"
            let driving = !code.hasPrefix("s")
            let vehicleID = driving && row.count > 35 ? row[35] as? String : nil
            let wireAnimation = row.count > 41 ? row[41] as? String ?? "" : ""
            let mappedAnimation = NativePedestrianMotion.clip(forWire: wireAnimation,
                weapon: row.count > 27 ? (row[27] as? NSNumber)?.intValue ?? 0 : 0,
                health: row.count > 18 && !driving ? (row[18] as? NSNumber)?.intValue ?? 100 : 100)
            let animation = !wireAnimation.isEmpty && ["idle_stance","gun_stand"].contains(mappedAnimation) ? wireAnimation : mappedAnimation
            let action = row.count > 32 ? ((row[32] as? NSNumber)?.intValue ?? 0) & 63 : 0
            let swimClips = ["swim_tread","swim_breast","swim_crawl","swim_dive_under","swim_under","swim_glide","swim_jumpout"]
            let visibleAnimation = (10...16).contains(action) ? "swim/"+swimClips[action-10]+([13,16].contains(action) ? "/n/1" : "/l/1") : animation
            let signature = visibleAnimation + ":" + (row.count > 29 ? String(describing: row[29]) : "0")
            if remoteAnimationTimes[id]?.0 != signature {
                remoteAnimationTimes[id] = (signature, ProcessInfo.processInfo.systemUptime)
            }
            updated[id] = RemotePlayer(id: id, name: name, position: SIMD3(x, y, z),
                                       code: code,
                                       heading: row.count > 6 ? -((row[6] as? NSNumber)?.floatValue ?? 0) : 0,
                                       pitch: row.count > 7 ? (row[7] as? NSNumber)?.floatValue ?? 0 : 0,
                                       roll: row.count > 8 ? -((row[8] as? NSNumber)?.floatValue ?? 0) : 0,
                                       speed: row.count > 9 ? (row[9] as? NSNumber)?.floatValue ?? 0 : 0,
                                       steer: row.count > 10 ? (row[10] as? NSNumber)?.floatValue ?? 0 : 0,
                                       skin: driving && row.count > 31 ? (row[31] as? NSNumber)?.intValue ?? 7 : Int(code.dropFirst()) ?? 7,
                                       animation: visibleAnimation,
                                       animationStarted: remoteAnimationTimes[id]?.1 ?? ProcessInfo.processInfo.systemUptime,
                                       weapon: row.count > 27 ? (row[27] as? NSNumber)?.intValue ?? 0 : 0,
                                       vehicleID: vehicleID,
                                       vehicleHealth: driving && row.count > 18 ? (row[18] as? NSNumber)?.intValue ?? 1000 : 1000,
                                       vehicleDamage: driving && row.count > 19 ? row[19] as? String ?? "" : "",
                                       lights: driving && row.count > 12 && (row[12] as? NSNumber)?.boolValue == true,
                                       horn: driving && row.count > 17 ? (row[17] as? NSNumber)?.intValue ?? 0 : 0,
                                       movementRatio:row.count>24 ? (row[24] as? NSNumber)?.floatValue ?? 0:0,
                                       airborne:row.count>25 && (row[25] as? NSNumber)?.boolValue == true,
                                       crouching:row.count>26 && (row[26] as? NSNumber)?.boolValue == true,
                                       aim:row.count>28 ? (row[28] as? NSNumber)?.floatValue:nil,
                                       action:row.count>32 ? (row[32] as? NSNumber)?.intValue ?? 0:0,
                                       velocity:SIMD3((row.count>13 ? (row[13] as? NSNumber)?.floatValue:nil) ?? 0,(row.count>14 ? (row[14] as? NSNumber)?.floatValue:nil) ?? 0,(row.count>15 ? (row[15] as? NSNumber)?.floatValue:nil) ?? 0),
                                       angularVelocity:SIMD3((row.count>20 ? (row[20] as? NSNumber)?.floatValue:nil) ?? 0,(row.count>21 ? (row[21] as? NSNumber)?.floatValue:nil) ?? 0,(row.count>22 ? (row[22] as? NSNumber)?.floatValue:nil) ?? 0),
                                       shotCount:row.count>29 ? (row[29] as? NSNumber)?.intValue ?? 0:0,
                                       paused:row.count>36 && (row[36] as? NSNumber)?.boolValue == true,
                                       down:row.count>38 ? (row[38] as? NSNumber)?.intValue ?? 0:0,
                                       scriptAnimation:wireAnimation.isEmpty ? nil:wireAnimation,
                                       ridingVehicleID:row.count>34 ? (row[34] as? [Any])?.first as? String:nil,
                                       ridingSeat:row.count>34 ? (row[34] as? [Any]).flatMap{$0.count>1 ? ($0[1] as? NSNumber)?.intValue:nil} ?? 0:0,
                                       supportVehicleID:row.count>39 ? (row[39] as? [Any])?.first as? String:nil,
                                       supportOffset:row.count>39 ? (row[39] as? [Any]).flatMap {v in guard v.count>=4,let x=(v[1] as? NSNumber)?.floatValue,let y=(v[2] as? NSNumber)?.floatValue,let z=(v[3] as? NSNumber)?.floatValue else{return nil};return SIMD3(x,y,z)} ?? .zero:.zero,
                                       kit:row.count>42 ? (row[42] as? [NSNumber])?.map(\.floatValue):nil,
                                       packetReceivedAt:ProcessInfo.processInfo.systemUptime,
                                       packetClockMilliseconds:row.count>16 ? (row[16] as? NSNumber)?.doubleValue ?? 0:0,
                                       latencyMilliseconds:row.count>23 ? (row[23] as? NSNumber)?.floatValue ?? 0:0,
                                       life:driving ? (row.count>43 ? (row[43] as? NSNumber)?.intValue ?? 100:100):(row.count>18 ? (row[18] as? NSNumber)?.intValue ?? 100:100),
                                       armour:row.count>30 ? (row[30] as? NSNumber)?.intValue ?? 0:0)
            if let vehicleID, var vehicle = vehicles[vehicleID] {
                vehicle.position = SIMD3(x, y, z)
                vehicle.heading = row.count > 6 ? -((row[6] as? NSNumber)?.floatValue ?? 0) : 0
                vehicle.pitch = row.count > 7 ? (row[7] as? NSNumber)?.floatValue ?? 0 : 0
                vehicle.roll = row.count > 8 ? -((row[8] as? NSNumber)?.floatValue ?? 0) : 0
                vehicle.health = row.count > 18 ? (row[18] as? NSNumber)?.intValue ?? vehicle.health : vehicle.health
                vehicle.damage = row.count > 19 ? row[19] as? String ?? vehicle.damage : vehicle.damage
                vehicles[vehicleID] = vehicle
            } else if !driving, row.count > 35,
                      let parkedID = row[35] as? String,
                      let parked = row[33] as? [Any], parked.count >= 5,
                      var vehicle = vehicles[parkedID],
                      let parkedX = (parked[1] as? NSNumber)?.floatValue,
                      let parkedY = (parked[2] as? NSNumber)?.floatValue,
                      let parkedZ = (parked[3] as? NSNumber)?.floatValue {
                vehicle.position = SIMD3(parkedX, parkedY, parkedZ)
                vehicle.heading = (parked[4] as? NSNumber).map { -$0.floatValue } ?? vehicle.heading
                if parked.count > 6 {
                    vehicle.pitch = (parked[5] as? NSNumber)?.floatValue ?? 0
                    vehicle.roll = -((parked[6] as? NSNumber)?.floatValue ?? 0)
                }
                if parked.count > 7 { vehicle.health = (parked[7] as? NSNumber)?.intValue ?? vehicle.health }
                if parked.count > 8 { vehicle.damage = parked[8] as? String ?? vehicle.damage }
                vehicles[parkedID] = vehicle
            }
        }
        players = updated
        playerOrder.removeAll{updated[$0]==nil}
        let retained=Set(playerOrder)
        playerOrder += incomingOrder.filter{!retained.contains($0)}
        remoteAnimationTimes = remoteAnimationTimes.filter { updated[$0.key] != nil }
        onPlayers?(orderedPlayers)
        onVehicles?(orderedVehicles)
    }
}
