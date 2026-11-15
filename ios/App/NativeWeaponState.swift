import Foundation

/// Catalog geometry and timing come from the ignored archived client data.
/// Inventory and ammunition are owned by the Mac server. Local firing is
/// predicted for immediate input response and reconciled by WebSocket replies.
final class NativeWeaponState {
    struct Weapon {
        let id: Int
        let name: String
        let model: String
        let range: Float
        let capacity: Int
        let interval: Double
        let animation: String
        let fireKind: String
        var isGun: Bool { id != 0 }
    }
    private var catalog: [Weapon] = [Weapon(id: 0, name: "Fists", model: "", range: 1.6,
        capacity: 0, interval: 0.35, animation: "unarmed", fireKind: "MELEE")]
    private var owned: Set<Int> = [0]
    var weapons: [Weapon] { catalog.filter { owned.contains($0.id) } }
    private(set) var selected = 0
    private var ammunition: [String: [Int]] = [:]
    private(set) var reloadUntil: Double = 0
    private var lastShot: Double = -.infinity
    private var revision = -1
    var onChange: (() -> Void)?
    var onNeedsRefresh: (() -> Void)?
    var current: Weapon { catalog.first { $0.id == selected } ?? catalog[0] }
    var rounds: Int { ammunition[String(selected)]?.first ?? 0 }
    var reserve: Int { ammunition[String(selected)]?.last ?? 0 }
    var reloading: Bool { reloadUntil > ProcessInfo.processInfo.systemUptime }

    init(server: ServerAddress) {
        URLSession.shared.dataTask(with: server.path("game/native/weapons.json")) { [weak self] data, _, _ in
            guard let self, let data,
                  let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let definitions = doc["definitions"] as? [[String: Any]],
                  let stats = doc["stats"] as? [String: [String: Any]] else { return }
            let entries = definitions.compactMap { entry -> Weapon? in
                guard let id = entry["id"] as? Int, let stat = stats[String(id)],
                      let name = entry["name"] as? String else { return nil }
                let loop = stat["loop"] as? [Double] ?? [0, 10, 0]
                return Weapon(id: id, name: name, model: entry["modelName"] as? String ?? "",
                    range: (stat["range"] as? NSNumber)?.floatValue ?? 1.6,
                    capacity: (stat["clip"] as? NSNumber)?.intValue ?? 0,
                    interval: max(0.08, (loop.count > 1 ? loop[1] - loop[0] : 10) / 30),
                    animation: stat["anim"] as? String ?? "unarmed",
                    fireKind: stat["fire"] as? String ?? "MELEE")
            }
            DispatchQueue.main.async { if !entries.isEmpty { self.catalog = entries }; self.onChange?() }
        }.resume()
    }

    func apply(_ inventory: [String: Any]) {
        let incoming = (inventory["revision"] as? NSNumber)?.intValue ?? 0
        guard incoming >= revision else { return }
        revision = incoming
        let rows = inventory["weapons"] as? [[String: Any]] ?? []
        owned = Set(rows.compactMap { ($0["id"] as? NSNumber)?.intValue }); owned.insert(0)
        ammunition = Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            guard let id = row["id"] as? NSNumber else { return nil }
            return (id.stringValue, [(row["clip"] as? NSNumber)?.intValue ?? 0,
                                    (row["rest"] as? NSNumber)?.intValue ?? 0])
        })
        selected = (inventory["selected"] as? NSNumber)?.intValue ?? 0
        if !owned.contains(selected) { selected = 0 }
        let pending = inventory["reload"] as? [String: Any]
        let remaining = (pending?["remainingMs"] as? NSNumber)?.doubleValue ?? 0
        reloadUntil = remaining > 0 ? ProcessInfo.processInfo.systemUptime + remaining / 1000 : 0
        onChange?()
    }

    func fire() -> Bool {
        tick()
        let now = ProcessInfo.processInfo.systemUptime
        guard !reloading, now-lastShot >= current.interval,
              !current.isGun || rounds > 0 else { return false }
        lastShot = now
        if current.isGun { ammunition[String(selected)] = [rounds-1, reserve] }
        return true
    }

    func tick() {
        guard reloadUntil > 0, !reloading else { return }
        reloadUntil = 0
        onNeedsRefresh?()
    }
}
