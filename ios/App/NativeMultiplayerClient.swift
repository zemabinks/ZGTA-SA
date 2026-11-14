import Foundation
import simd

struct RemotePlayer {
    let id: String
    let name: String
    let position: SIMD3<Float>
}

/// Speaks the existing local server's WebSocket protocol without Discord.
final class NativeMultiplayerClient {
    private let server: ServerAddress
    private var socket: URLSessionWebSocketTask?
    private(set) var players: [String: RemotePlayer] = [:]
    private(set) var localName = "LOCAL PLAYER"
    private(set) var cash = 0
    private var positionPackets = 0
    var onStatus: ((String) -> Void)?
    var onPlayers: (([RemotePlayer]) -> Void)?
    var onPresence: ((Int, [String]) -> Void)?

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

    func sendPosition(_ position: SIMD3<Float>, heading: Float, moving: Bool) {
        send(["t": "me", "walking": true, "skin": 7,
              "x": Double(position.x), "y": Double(position.y), "z": Double(position.z),
              "heading": Double(heading), "health": 100, "armour": 0,
              "anim": moving ? "ped/walk/l/1" : "ped/idle/l/1"])
        positionPackets += 1
        if positionPackets % 10 == 0 { send(["t": "board"]) }
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
            updated[id] = RemotePlayer(id: id, name: name, position: SIMD3(x, y, z))
        }
        players = updated
        onPlayers?(Array(updated.values))
    }
}
