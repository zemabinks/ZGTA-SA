import Foundation
import CoreFoundation

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
        var isMelee: Bool { id == 0 || ((1...15).contains(id) && fireKind.uppercased() == "MELEE") }
        // Existing callers use this for ammunition-driven attacks, including
        // throwables/streams. USE/CAMERA and the parachute's legacy MELEE data
        // are utility roles, not a fallback gun or an unarmed attack.
        var isGun: Bool { ["INSTANT_HIT", "PROJECTILE", "AREA_EFFECT"].contains(fireKind.uppercased()) }
        var isUtility: Bool { !isMelee && !isGun }
        var supportsAttack: Bool { isMelee || isGun }
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
    private let clock: () -> Double
    private let allowLegacySnapshots: Bool
    private let prediction: NativeInventoryPrediction
    private var serverReloading = false
    private var serverReloadEnd: Double?
    private var reloadRequest: String?
    private var reloadRequestStarted: Double?
    private var resyncNotified = false
    private var reloadRefreshKey: String?
    var onChange: (() -> Void)?
    var onNeedsRefresh: (() -> Void)?
    var onNeedsResync: (() -> Void)?
    var current: Weapon { catalog.first { $0.id == selected } ?? catalog[0] }
    var rounds: Int { prediction.connection != nil ? prediction.rounds(selected)?.clip ?? 0 : ammunition[String(selected)]?.first ?? 0 }
    var reserve: Int { prediction.connection != nil ? prediction.rounds(selected)?.reserve ?? 0 : ammunition[String(selected)]?.last ?? 0 }
    var reloading: Bool { serverReloading || reloadRequest != nil }

    /// An injected monotonic clock also permits deterministic inventory and
    /// animation-event transition tests without fetching a server catalog.
    init(catalog: [Weapon] = [], allowLegacySnapshots: Bool = false, clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock; self.allowLegacySnapshots = allowLegacySnapshots
        self.prediction = NativeInventoryPrediction(clock: clock)
        if !catalog.isEmpty { self.catalog += catalog.filter { $0.id != 0 } }
    }

    convenience init(server: ServerAddress) {
        self.init()
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

    /// A fresh socket must announce its own nonce before snapshots can enable
    /// firing. HTTP or delayed old-socket state cannot negotiate this boundary.
    func setConnection(_ nonce: String?) {
        guard nonce != prediction.connection else { return }
        if let nonce, !nonce.isEmpty { prediction.connected(nonce) } else { prediction.disconnected() }
        selected = 0; owned = [0]; ammunition = [:]; revision = -1
        reloadUntil = 0; serverReloading = false; serverReloadEnd = nil; reloadRequest = nil; reloadRequestStarted = nil
        resyncNotified = false; reloadRefreshKey = nil; lastShot = -.infinity
        onChange?()
    }

    var pendingShotCount: Int { prediction.pending.count }
    var synchronized: Bool { prediction.connection != nil ? prediction.synchronized && !prediction.needsResync : allowLegacySnapshots }
    var canFire: Bool { synchronized && !reloading && current.id == selected && (current.isMelee || current.isGun && rounds > 0) }

    /// Unacknowledged snapshots are ignored unless an explicit offline legacy
    /// mode was selected by a test. They never overwrite sequenced truth.
    @discardableResult func apply(_ inventory: [String: Any]) -> Bool {
        guard let parsed = Self.parse(inventory) else { return false }
        // The same authoritative reload can arrive through both HTTP and WS,
        // including a later unrelated inventory revision or rejected-shot ACK.
        // Its countdown is not a new reload just because the packet is late.
        let continuingReload: Bool
        if serverReloading, parsed.reloading, selected == parsed.selected {
            if let old = serverReloadEnd, let next = parsed.reloadEnd { continuingReload = old == next }
            else { continuingReload = revision == parsed.revision }
        } else { continuingReload = false }
        if let ack = inventory["ack"] as? [String: Any] {
            guard let connection = ack["connection"] as? String,
                  let processed = Self.integer(ack["processedShot"]), prediction.connection == connection else { return false }
            let snapshot = NativeInventoryPrediction.Snapshot(connection: connection, processedShot: processed,
                revision: parsed.revision, selected: parsed.selected, reloading: parsed.reloading,
                weapons: parsed.weapons.filter { $0.key != 0 })
            guard prediction.apply(snapshot) == .applied else { return false }
            revision = parsed.revision; selected = prediction.selected
            owned = Set(parsed.weapons.keys); owned.insert(0)
        } else {
            guard allowLegacySnapshots, prediction.connection == nil, parsed.revision >= revision else { return false }
            revision = parsed.revision; selected = parsed.selected
            owned = Set(parsed.weapons.keys); owned.insert(0)
            ammunition = Dictionary(uniqueKeysWithValues: parsed.weapons.map { (String($0.key), [$0.value.clip,$0.value.reserve]) })
        }
        serverReloading = parsed.reloading
        let deadline = parsed.reloading ? clock() + parsed.remaining / 1000 : 0
        reloadUntil = continuingReload ? min(reloadUntil, deadline) : deadline
        serverReloadEnd = parsed.reloading ? parsed.reloadEnd ?? (continuingReload ? serverReloadEnd : nil) : nil
        if !serverReloading { reloadRefreshKey = nil }
        onChange?(); tick()
        return true
    }

    func fire(ticket: NativeShotTicket? = nil) -> Bool {
        tick()
        let now = clock()
        guard canFire, now.isFinite, now-lastShot >= current.interval else { return false }
        guard consumeRound(weapon: selected, ticket: ticket) else { return false }
        lastShot = now; return true
    }

    /// Animation timing is authoritative for the local muzzle event. It must
    /// reserve its network sequence before consuming predicted ammunition.
    @discardableResult func consumeAnimationShot(weapon: Int, ticket: NativeShotTicket? = nil) -> Bool {
        tick()
        guard selected == weapon, current.id == weapon, canFire,
              consumeRound(weapon: weapon, ticket: ticket) else { return false }
        lastShot = clock(); return true
    }

    private func consumeRound(weapon: Int, ticket: NativeShotTicket?) -> Bool {
        if current.isMelee { return synchronized } // melee spends no predicted ammunition
        guard current.isGun else { return false }
        if allowLegacySnapshots && prediction.connection == nil {
            if current.isGun { ammunition[String(selected)] = [rounds-1, reserve] }
            return true
        }
        guard let ticket, ticket.connection == prediction.connection else { return false }
        let accepted = prediction.predict(weapon: weapon, sequence: ticket.sequence)
        if !accepted { tick() }
        return accepted
    }

    @discardableResult func beginReloadRequest() -> String {
        if let reloadRequest { return reloadRequest }
        let id = UUID().uuidString; reloadRequest = id; reloadRequestStarted = clock(); onChange?(); return id
    }
    /// nil means the transport outcome is unknown. Do not optimistically clear
    /// a possibly accepted reload; reconnect to authoritative state instead.
    func finishReloadRequest(id: String, succeeded: Bool?) {
        guard reloadRequest == id else { return }
        if succeeded == nil { markTransportUncertain(); return }
        reloadRequest = nil; reloadRequestStarted = nil; onChange?()
    }
    func markTransportUncertain() {
        prediction.markUncertain(); tick()
    }

    func tick() {
        if let began = reloadRequestStarted, clock() - began > 2 { prediction.markUncertain() }
        if prediction.connection != nil, prediction.needsResync {
            if !resyncNotified { resyncNotified = true; onNeedsResync?() }
        } else { resyncNotified = false }
        guard serverReloading, reloadUntil <= clock() else { return }
        let key = "\(revision):\(prediction.processedShot)"
        guard reloadRefreshKey != key else { return }
        reloadRefreshKey = key; onNeedsRefresh?()
    }

    private struct Parsed {
        let revision: Int, selected: Int
        let weapons: [Int: NativeInventoryPrediction.Rounds]
        let reloading: Bool
        let remaining: Double
        let reloadEnd: Double?
    }
    private static func integer(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue >= 0, n.doubleValue <= Double(NativeShotSequence.maximum),
              let integer = Int(exactly: n.doubleValue) else { return nil }
        return integer
    }
    private static func parse(_ inventory: [String: Any]) -> Parsed? {
        guard let revision = integer(inventory["revision"]), let selected = integer(inventory["selected"]),
              let rows = inventory["weapons"] as? [[String: Any]] else { return nil }
        var weapons: [Int: NativeInventoryPrediction.Rounds] = [:]
        for row in rows {
            guard let id = integer(row["id"]), id <= 46, weapons[id] == nil,
                  let clip = integer(row["clip"]), let reserve = integer(row["rest"]),
                  clip <= 9999, reserve <= 9999-clip else { return nil }
            weapons[id] = .init(clip: clip, reserve: reserve)
        }
        guard selected == 0 || weapons[selected] != nil else { return nil }
        let reload = inventory["reload"] as? [String: Any]
        let remaining = (reload?["remainingMs"] as? NSNumber)?.doubleValue ?? 0
        guard remaining.isFinite, remaining >= 0, remaining <= 10000 else { return nil }
        let reloading = remaining > 0 || reload?["weapon"] != nil
        if let reloadWeapon = reload?["weapon"] {
            guard integer(reloadWeapon) == selected, selected != 0 else { return nil }
        }
        // `until` is an existing server identity, not a clock conversion. Older
        // snapshots without it still use the same-revision duplicate rule.
        var reloadEnd: Double?
        if let value = reload?["until"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
           value.doubleValue.isFinite, value.doubleValue > 0 { reloadEnd = value.doubleValue }
        return Parsed(revision: revision, selected: selected, weapons: weapons, reloading: reloading, remaining: remaining, reloadEnd: reloadEnd)
    }
}
