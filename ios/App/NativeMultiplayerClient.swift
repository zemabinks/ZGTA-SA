import Foundation
import simd

struct RemotePlayer {
    let id: String
    let name: String
    let position: SIMD3<Float>
    let code: String
    let heading: Float
    let pitch: Float
    let animation: String
    let weapon: Int
    let vehicleID: String?
}

struct RemoteVehicle {
    let id: String
    let name: String
    let code: String
    var position: SIMD3<Float>
    var heading: Float

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
        heading = (row[6] as? NSNumber)?.floatValue ?? 0
    }
}

/// Speaks the existing local server's WebSocket protocol without Discord.
final class NativeMultiplayerClient {
    private let server: ServerAddress
    private var socket: URLSessionWebSocketTask?
    private(set) var players: [String: RemotePlayer] = [:]
    private(set) var vehicles: [String: RemoteVehicle] = [:]
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
    var onTeleport: ((SIMD3<Float>) -> Void)?
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
        send(["t": "hi"])
        receive()
    }

    func disconnect() {
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
    }

    func sendPosition(_ position: SIMD3<Float>, heading: Float, moving: Bool, running: Bool,
                      vehicle: RemoteVehicle? = nil, speed: Float = 0,
                      steer: Float = 0, pitch: Float = 0,
                      airborne: Bool = false, weapon: Int = 0, firing: Bool = false) {
        if let vehicle {
            var packet: [String: Any] = ["t": "me", "driving": true, "car": vehicle.code,
                  "vehicle": vehicle.id, "skin": 7,
                  "x": Double(position.x), "y": Double(position.y), "z": Double(position.z),
                  "heading": Double(heading), "pitch": Double(pitch),
                  "speed": Double(speed), "steer": Double(steer),
                  "health": 1000, "life": health, "armour": armour]
            addPendingChat(to: &packet)
            send(packet)
            return
        }
        var packet: [String: Any] = ["t": "me", "walking": true, "skin": 7,
              "x": Double(position.x), "y": Double(position.y), "z": Double(position.z),
              "heading": Double(heading), "health": health, "armour": armour,
              "weapon": weapon,
              "air": airborne,
              "anim": firing ? "colt45/colt45_fire/l/1" :
                  airborne ? "ped/jump_launch/l/1" :
                  moving ? (running ? "ped/run/l/1" : "ped/walk/l/1") :
                  weapon == 22 ? "ped/gun_stand/l/1" : "ped/idle/l/1"]
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

    func sendMeleeHit(to player: String) {
        guard health > 0, !passive else { return }
        send(["t": "hit", "to": player])
    }

    func sendPistolShot(from origin: SIMD3<Float>, to hit: SIMD3<Float>,
                        player: String?) {
        guard health > 0, !passive else { return }
        let shot: [String: Any] = ["t": "shot", "w": 22,
                                   "o": [Double(origin.x), Double(origin.y), Double(origin.z)],
                                   "h": [Double(hit.x), Double(hit.y), Double(hit.z)]]
        guard let data = try? JSONSerialization.data(withJSONObject: shot),
              let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { [weak self] error in
            guard error == nil, let player else { return }
            self?.send(["t": "hit", "to": player])
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

    func sendExit(_ position: SIMD3<Float>, heading: Float, vehicle: RemoteVehicle) {
        send(["t": "me", "walking": true, "skin": 7,
              "vehicle": vehicle.id, "car": vehicle.code,
              "x": Double(position.x + cos(heading) * 2.5),
              "y": Double(position.y - sin(heading) * 2.5), "z": Double(position.z),
              "heading": Double(heading), "health": health, "armour": armour,
              "parked": ["x": Double(position.x), "y": Double(position.y),
                         "z": Double(position.z), "heading": Double(heading),
                         "pitch": 0, "roll": 0, "health": 1000]])
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
        case "hello":
            if let life = message["life"] as? [NSNumber], life.count >= 2 {
                health = max(0, min(100, life[0].intValue))
                armour = max(0, min(100, life[1].intValue))
                onVitals?(health, armour)
            }
            onStatus?("CONNECTED TO LOCAL WORLD")
            send(["t": "board"])
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
                onTeleport?(SIMD3(x, y, z))
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
            let animation = wireAnimation.contains("colt45_fire") ? "colt45_fire" :
                wireAnimation.contains("gun_stand") ? "gun_stand" :
                wireAnimation.contains("jump") ? "jump_launch" :
                wireAnimation.contains("run") ? "run_player" :
                wireAnimation.contains("walk") ? "walk_player" :
                (row.count > 27 && (row[27] as? NSNumber)?.intValue == 22) ? "gun_stand" : "idle_stance"
            updated[id] = RemotePlayer(id: id, name: name, position: SIMD3(x, y, z),
                                       code: code,
                                       heading: row.count > 6 ? (row[6] as? NSNumber)?.floatValue ?? 0 : 0,
                                       pitch: row.count > 7 ? (row[7] as? NSNumber)?.floatValue ?? 0 : 0,
                                       animation: animation,
                                       weapon: row.count > 27 ? (row[27] as? NSNumber)?.intValue ?? 0 : 0,
                                       vehicleID: vehicleID)
            if let vehicleID, var vehicle = vehicles[vehicleID] {
                vehicle.position = SIMD3(x, y, z)
                vehicle.heading = row.count > 6 ? (row[6] as? NSNumber)?.floatValue ?? 0 : 0
                vehicles[vehicleID] = vehicle
            } else if !driving, row.count > 35,
                      let parkedID = row[35] as? String,
                      let parked = row[33] as? [Any], parked.count >= 5,
                      var vehicle = vehicles[parkedID],
                      let parkedX = (parked[1] as? NSNumber)?.floatValue,
                      let parkedY = (parked[2] as? NSNumber)?.floatValue,
                      let parkedZ = (parked[3] as? NSNumber)?.floatValue {
                vehicle.position = SIMD3(parkedX, parkedY, parkedZ)
                vehicle.heading = (parked[4] as? NSNumber)?.floatValue ?? vehicle.heading
                vehicles[parkedID] = vehicle
            }
        }
        players = updated
        onPlayers?(Array(updated.values))
        onVehicles?(Array(vehicles.values))
    }
}
