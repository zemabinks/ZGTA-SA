import Foundation
import simd

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
    }
}

/// Speaks the existing local server's WebSocket protocol without Discord.
/// Browser heading/roll are Three Y-yaw/Z-roll. GTA native controls use the
/// opposite signs for those two angles; convert once at this wire boundary.
final class NativeMultiplayerClient {
    private let server: ServerAddress
    private var socket: URLSessionWebSocketTask?
    private(set) var players: [String: RemotePlayer] = [:]
    private(set) var vehicles: [String: RemoteVehicle] = [:]
    private var remoteAnimationTimes: [String: (String, Double)] = [:]
    private var shots = 0
    private(set) var localName = "LOCAL PLAYER"
    private(set) var cash = 0
    private(set) var health = 100
    private(set) var armour = 0
    private(set) var passive = false
    private var positionPackets = 0
    private var pendingSays: [String] = []
    private var lastChatSequence = 0
    private(set) var chatMessages: [String] = []
    var onStatus: ((String) -> Void)?
    var onPlayers: (([RemotePlayer]) -> Void)?
    var onPresence: ((Int, [String]) -> Void)?
    var onVehicles: (([RemoteVehicle]) -> Void)?
    var onEnter: ((String, Bool) -> Void)?
    var onTeleport: ((SIMD3<Float>, Float?) -> Void)?
    var onEnvironment: ((Int?, Double?, Double?) -> Void)?
    var onInventory: (([String: Any]) -> Void)?
    var onProjectiles: (([[String: Any]]) -> Void)?
    var onBlast: ((Int, SIMD3<Float>) -> Void)?
    var onWeaponSound: ((Int) -> Void)?
    var onVitals: ((Int, Int) -> Void)?
    var onChat: (([String]) -> Void)?

    init(server: ServerAddress) { self.server = server }

    func connect() {
        guard var parts = URLComponents(url: server.path("api/world/live"), resolvingAgainstBaseURL: false) else { return }
        parts.scheme = server.url.scheme == "https" ? "wss" : "ws"
        guard let url = parts.url else { return }
        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        send(["t": "hi", "nativeInventory": true])
        receive()
    }

    func disconnect() {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }

    func sendPosition(_ position: SIMD3<Float>, heading: Float, moving: Bool, running: Bool,
                      vehicle: RemoteVehicle? = nil, speed: Float = 0,
                      steer: Float = 0, pitch: Float = 0, roll: Float = 0,
                      vehicleHealth: Int = 1000,
                      vehicleDamage: String = "",lights: Bool = false,horn: Bool = false,
                      airborne: Bool = false, weapon: Int = 0, firing: Bool = false,
                      animation: String? = nil, crouching: Bool = false,
                      swimState: Int = 0,swimPitch: Float = 0,swimRatio: Float = 0) {
        if let vehicle {
            var packet: [String: Any] = ["t": "me", "driving": true, "car": vehicle.code,
                  "vehicle": vehicle.id, "skin": 7,
                  "x": Double(position.x), "y": Double(position.y), "z": Double(position.z),
                  "heading": -Double(heading), "pitch": Double(pitch), "roll": -Double(roll),
                  "speed": Double(speed), "steer": Double(steer),
                  "health": vehicleHealth, "life": health, "armour": armour]
            packet["damage"] = vehicleDamage;packet["lights"] = lights;packet["horn"] = horn
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
              "air": airborne,
              "anim": animation.map { NativePedestrianMotion.wireAnimation(for: $0) } ?? (firing ? "colt45/colt45_fire/l/1" :
                  airborne ? "ped/jump_launch/l/1" :
                  moving ? (running ? "ped/run/l/1" : "ped/walk/l/1") :
                  weapon == 22 ? "ped/gun_stand/l/1" : "ped/idle/l/1")]
        if (1...7).contains(swimState),health > 0 {
            packet["act"] = 9+swimState;packet["move"] = Double(swimRatio)
            packet["air"] = false;packet["crouch"] = false;packet["weapon"] = 0
            packet["aim"] = NSNull();packet["pitch"] = Double(swimPitch)
        }
        addPendingChat(to: &packet)
        send(packet)
        positionPackets += 1
        if positionPackets % 10 == 0 { send(["t": "board"]) }
    }

    func sendChat(_ line: String) {
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
    func detonateSatchels() { send(["t":"detonate"]) }

    func sendMeleeHit(to player: String) {
        guard health > 0, !passive else { return }
        send(["t": "hit", "to": player, "w": 0])
        shots += 1
    }

    func sendPistolShot(from origin: SIMD3<Float>, to hit: SIMD3<Float>,
                        player: String?) {
        sendWeaponShot(weapon: 22, from: origin, to: hit, player: player)
    }

    func sendWeaponShot(weapon: Int, from origin: SIMD3<Float>, to hit: SIMD3<Float>,
                        player: String?) {
        guard health > 0, !passive else { return }
        shots += 1
        let shot: [String: Any] = ["t": "shot", "w": weapon,
                                   "o": [Double(origin.x), Double(origin.y), Double(origin.z)],
                                   "h": [Double(hit.x), Double(hit.y), Double(hit.z)]]
        guard let data = try? JSONSerialization.data(withJSONObject: shot),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { [weak self] error in
            guard error == nil, let player else { return }
            self?.send(["t": "hit", "to": player, "w": weapon])
        }
    }

    func respawn() {
        guard health == 0 else { return }
        health = 100
        armour = 0
        onVitals?(health, armour)
    }

    func syncVitals(from state: [String: Any]) {
        guard let current = state["health"] as? NSNumber,
              let protected = state["armour"] as? NSNumber else { return }
        let nextHealth = max(0, min(100, current.intValue))
        let nextArmour = max(0, min(100, protected.intValue))
        guard health != nextHealth || armour != nextArmour else { return }
        health = nextHealth
        armour = nextArmour
        onVitals?(health, armour)
    }

    func sendExit(_ feet: SIMD3<Float>, parked position: SIMD3<Float>, heading: Float, pitch: Float, roll: Float,
                  vehicle: RemoteVehicle, vehicleHealth: Int,vehicleDamage: String = "") {
        var parked=vehicle;parked.position=position;parked.heading=heading;parked.pitch=pitch;parked.roll=roll
        parked.health=vehicleHealth;parked.damage=vehicleDamage;vehicles[vehicle.id]=parked
        onVehicles?(Array(vehicles.values))
        send(["t": "me", "walking": true, "skin": 7,
              "vehicle": vehicle.id, "car": vehicle.code,
              "x": Double(feet.x), "y": Double(feet.y), "z": Double(feet.z),
              "heading": -Double(heading), "health": health, "armour": armour,
              "parked": ["x": Double(position.x), "y": Double(position.y),
                         "z": Double(position.z), "heading": -Double(heading),
                         "pitch": Double(pitch), "roll": -Double(roll), "health": vehicleHealth,"damage":vehicleDamage]])
    }

    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { [weak self] error in
            if let error { DispatchQueue.main.async { self?.onStatus?("MULTIPLAYER: \(error.localizedDescription)") } }
        }
    }

    private func receive() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                DispatchQueue.main.async { self.onStatus?("MULTIPLAYER: \(error.localizedDescription)") }
            case .success(let message):
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let bytes): data = bytes
                @unknown default: return
                }
                if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    DispatchQueue.main.async { self.handle(object) }
                }
                self.receive()
            }
        }
    }

    private func handle(_ message: [String: Any]) {
        switch message["t"] as? String {
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
            if let state = message["state"] as? [String: Any] { onInventory?(state) }
        case "hello":
            if let spot = message["spot"] as? [NSNumber], spot.count >= 3 {
                onTeleport?(SIMD3(spot[0].floatValue,spot[1].floatValue,spot[2].floatValue),
                            spot.count > 3 ? -spot[3].floatValue : nil)
            }
            let day = message["day"] as? [String: Any]
            onEnvironment?((message["weather"] as? NSNumber)?.intValue,
                           (day?["shift"] as? NSNumber)?.doubleValue,
                           (day?["hold"] as? NSNumber)?.doubleValue)
            if let life = message["life"] as? [NSNumber], life.count >= 2 {
                health = max(0, min(100, life[0].intValue))
                armour = max(0, min(100, life[1].intValue))
                onVitals?(health, armour)
            }
            onStatus?("CONNECTED TO LOCAL WORLD")
            send(["t": "board"])
        case "weather":
            onEnvironment?((message["weather"] as? NSNumber)?.intValue ?? (message["w"] as? NSNumber)?.intValue, nil, nil)
        case "day":
            onEnvironment?(nil, (message["shift"] as? NSNumber)?.doubleValue,
                           (message["hold"] as? NSNumber)?.doubleValue)
        case "all":
            localName = (message["you"] as? String) ?? localName
            cash = (message["cash"] as? Int) ?? cash
            if let rows = message["chat"] as? [[Any]] { receiveChat(rows) }
            updateRows(message["cars"])
            if let rows = message["vehicles"] as? [[Any]] {
                vehicles = Dictionary(uniqueKeysWithValues: rows.compactMap(RemoteVehicle.init(row:)).map { ($0.id, $0) })
                onVehicles?(Array(vehicles.values))
            }
            onStatus?("ONLINE AS \(localName.uppercased())")
        case "cars": updateRows(message["c"])
        case "gone":
            if let id = message["id"] as? String {
                players.removeValue(forKey:id); remoteAnimationTimes.removeValue(forKey:id)
                onPlayers?(Array(players.values))
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
        case "vitals":
            if let value = message["health"] as? Int { health = max(0, min(100,value)) }
            if let value = message["armour"] as? Int { armour = max(0,min(100,value)) }
            onVitals?(health, armour)
        case "hit":
            let damage = max(0, (message["d"] as? NSNumber)?.intValue ?? 0)
            let absorbed = min(armour, damage)
            armour -= absorbed
            health = max(0, health - (damage - absorbed))
            onVitals?(health, armour)
            onStatus?(health == 0 ? "DEFEATED — RESPAWN TO CONTINUE" :
                         "HIT — \(health) HEALTH REMAINING")
        case "spawned":
            if let row = message["v"] as? [Any], let vehicle = RemoteVehicle(row: row) {
                vehicles[vehicle.id] = vehicle
                onVehicles?(Array(vehicles.values))
            }
        case "vgone":
            if let id = message["id"] as? String {
                vehicles.removeValue(forKey: id)
                onVehicles?(Array(vehicles.values))
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
        for row in rows where row.count >= 6 {
            guard let id = row[0] as? String,
                  let name = row[1] as? String,
                  let x = (row[3] as? NSNumber)?.floatValue,
                  let y = (row[4] as? NSNumber)?.floatValue,
                  let z = (row[5] as? NSNumber)?.floatValue else { continue }
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
                                       horn: driving && row.count > 17 ? (row[17] as? NSNumber)?.intValue ?? 0 : 0)
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
        remoteAnimationTimes = remoteAnimationTimes.filter { updated[$0.key] != nil }
        onPlayers?(Array(updated.values))
        onVehicles?(Array(vehicles.values))
    }
}
