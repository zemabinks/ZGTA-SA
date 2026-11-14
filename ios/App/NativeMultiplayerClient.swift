import Foundation
import simd

struct RemotePlayer {
    let id: String
    let name: String
    let position: SIMD3<Float>
    let code: String
    let heading: Float
    let animation: String
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
    private var positionPackets = 0
    var onStatus: ((String) -> Void)?
    var onPlayers: (([RemotePlayer]) -> Void)?
    var onPresence: ((Int, [String]) -> Void)?
    var onVehicles: (([RemoteVehicle]) -> Void)?
    var onEnter: ((String, Bool) -> Void)?
    var onTeleport: ((SIMD3<Float>) -> Void)?

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
                      airborne: Bool = false) {
        if let vehicle {
            send(["t": "me", "driving": true, "car": vehicle.code,
                  "vehicle": vehicle.id, "skin": 7,
                  "x": Double(position.x), "y": Double(position.y), "z": Double(position.z),
                  "heading": Double(heading), "speed": Double(speed), "steer": 0,
                  "health": 1000, "life": 100, "armour": 0])
            return
        }
        send(["t": "me", "walking": true, "skin": 7,
              "x": Double(position.x), "y": Double(position.y), "z": Double(position.z),
              "heading": Double(heading), "health": 100, "armour": 0,
              "air": airborne,
              "anim": airborne ? "ped/jump_launch/l/1" :
                  moving ? (running ? "ped/run/l/1" : "ped/walk/l/1") : "ped/idle/l/1"])
        positionPackets += 1
        if positionPackets % 10 == 0 { send(["t": "board"]) }
    }

    func requestEnter(_ vehicle: RemoteVehicle) { send(["t": "enter", "v": vehicle.id]) }

    func sendExit(_ position: SIMD3<Float>, heading: Float, vehicle: RemoteVehicle) {
        send(["t": "me", "walking": true, "skin": 7,
              "vehicle": vehicle.id, "car": vehicle.code,
              "x": Double(position.x + cos(heading) * 2.5),
              "y": Double(position.y - sin(heading) * 2.5), "z": Double(position.z),
              "heading": Double(heading), "health": 100, "armour": 0,
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
            onStatus?("CONNECTED TO LOCAL WORLD")
            send(["t": "board"])
        case "all":
            localName = (message["you"] as? String) ?? localName
            cash = (message["cash"] as? Int) ?? cash
            updateRows(message["cars"])
            if let rows = message["vehicles"] as? [[Any]] {
                vehicles = Dictionary(uniqueKeysWithValues: rows.compactMap(RemoteVehicle.init(row:)).map { ($0.id, $0) })
                onVehicles?(Array(vehicles.values))
            }
            onStatus?("ONLINE AS \(localName.uppercased())")
        case "cars": updateRows(message["c"])
        case "board":
            let rows = (message["rows"] as? [[Any]]) ?? []
            let names = rows.compactMap { row -> String? in
                guard row.count > 1 else { return nil }
                return row[1] as? String
            }
            onPresence?((message["players"] as? Int) ?? rows.count, names)
        case "note":
            if let note = message["text"] as? String { onStatus?(note.uppercased()) }
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
            let wireAnimation = row.count > 41 ? row[41] as? String ?? "" : ""
            let animation = wireAnimation.contains("jump") ? "jump_launch" :
                wireAnimation.contains("run") ? "run_player" :
                wireAnimation.contains("walk") ? "walk_player" : "idle_stance"
            updated[id] = RemotePlayer(id: id, name: name, position: SIMD3(x, y, z),
                                       code: row[2] as? String ?? "s7",
                                       heading: row.count > 6 ? (row[6] as? NSNumber)?.floatValue ?? 0 : 0,
                                       animation: animation)
        }
        players = updated
        onPlayers?(Array(updated.values))
    }
}
