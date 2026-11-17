import Foundation
import CoreFoundation

/// Catalog geometry and timing come from the ignored archived client data.
/// Inventory and ammunition are owned by the Mac server. Local firing is
/// predicted for immediate input response and reconciled by WebSocket replies.
final class NativeWeaponState {
    enum Policy { case acknowledgedSelfHost, originalWorld, legacySAMP }
    var usesClientOwnedInventory: Bool { policy != .acknowledgedSelfHost }
    let policy: Policy
    private var originalArsenal: NativeOriginalWorldArsenal?
    private enum ClientInventoryEvent {
        case guns(Any,Bool,Double)
        case command(String,Int,Int)
        case rearm([[Int]])
        case revive
        case staff(StaffWeapons,Bool)
    }
    private var pendingClientEvents: [ClientInventoryEvent] = []
    private var clientInventoryGeneration: UInt64 = 0
    private var clientQueueOverflowed = false
    private var originalLastTick: Double?
    private var originalDefinitionsReady = false
    private var legacySessionReady = false
    private var clientZeroAmmoWeapons = Set<Int>()

    struct Weapon {
        let id: Int
        let name: String
        let model: String
        let range: Float
        let capacity: Int
        let interval: Double
        let animation: String
        let fireKind: String
        var damage:Float? = nil
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
    func definition(for weapon:Int)->Weapon?{catalog.first{$0.id==weapon}}
    func damage(for weapon:Int)->Float?{catalog.first{$0.id==weapon}?.damage}
    var current: Weapon { catalog.first { $0.id == selected } ?? catalog[0] }
    var rounds: Int { usesClientOwnedInventory ? originalArsenal?.ammo?.clip ?? 0 : prediction.connection != nil ? prediction.rounds(selected)?.clip ?? 0 : ammunition[String(selected)]?.first ?? 0 }
    var reserve: Int { usesClientOwnedInventory ? originalArsenal?.ammo?.reserve ?? 0 : prediction.connection != nil ? prediction.rounds(selected)?.reserve ?? 0 : ammunition[String(selected)]?.last ?? 0 }
    var reloading: Bool { usesClientOwnedInventory ? reloadUntil > clock() : serverReloading || reloadRequest != nil }

    /// An injected monotonic clock also permits deterministic inventory and
    /// animation-event transition tests without fetching a server catalog.
    init(catalog: [Weapon] = [], allowLegacySnapshots: Bool = false,
         policy: Policy = .acknowledgedSelfHost,
         originalDefinitions: [NativeOriginalWorldArsenal.Definition] = [],
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock; self.allowLegacySnapshots = allowLegacySnapshots; self.policy = policy
        if policy != .acknowledgedSelfHost, !originalDefinitions.isEmpty {
            originalArsenal = NativeOriginalWorldArsenal(definitions: originalDefinitions)
            originalDefinitionsReady = true; originalLastTick = clock()
        }
        self.prediction = NativeInventoryPrediction(clock: clock)
        if !catalog.isEmpty { self.catalog += catalog.filter { $0.id != 0 } }
    }

    convenience init(server: ServerAddress, policy: Policy = .acknowledgedSelfHost) {
        self.init(policy: policy)
        NativeResourceTransport.dataTask(with: server.path("game/native/weapons.json")) { [weak self] data, _, _ in
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
                    fireKind: stat["fire"] as? String ?? "MELEE",damage:(stat["damage"]as?NSNumber).map{max(0,min(1000,$0.floatValue))})
            }
            DispatchQueue.main.async { if !entries.isEmpty { self.catalog = entries }; self.onChange?() }
        }.resume()
        if policy != .acknowledgedSelfHost {
            NativeResourceTransport.dataTask(with: server.path("game/native/original-weapons.json")) { [weak self] data, _, _ in
                guard let data, let document=try? JSONSerialization.jsonObject(with:data) as? [String:Any] else{return}
                DispatchQueue.main.async {_=self?.installClientWeaponCatalog(document)}
            }.resume()
        }
    }

    /// The real asynchronous sidecar completion enters through this method.
    /// Replay one bounded arrival FIFO so a staff command cannot move across
    /// an earlier/later guns baseline merely because metadata loads slowly.
    @discardableResult func installClientWeaponCatalog(_ document:[String:Any])->Bool {
        guard usesClientOwnedInventory,!originalDefinitionsReady,
              Self.integer(document["schema"])==1,Self.integer(document["protocol"])==38,
              let rows=document["definitions"] as? [[String:Any]],rows.count<=47 else{return false}
        let definitions=Self.originalDefinitions(rows)
        guard !definitions.isEmpty,definitions.count==rows.count else{return false}
        originalArsenal=NativeOriginalWorldArsenal(definitions:definitions)
        originalDefinitionsReady=true;originalLastTick=clock()
        let events=pendingClientEvents,epoch=clientInventoryGeneration;pendingClientEvents.removeAll()
        for event in events {
            guard epoch==clientInventoryGeneration else{break}
            switch event {
            case .guns(let value,let back,let time):
                _=originalArsenal?.receive(value,back:back,now:time);synchronizeOriginalPresentation()
            case .command(let operation,let id,let amount):_=applyClientWeaponOperation(operation,id:id,amount:amount)
            case .rearm(let rows):_=rearmOriginalWeapons(rows)
            case .revive:reviveOriginalWeapons()
            case .staff(let operation,let alive):_=applyOriginalStaffWeapons(operation,alive:alive)
            }
        }
        synchronizeOriginalPresentation();return true
    }
    private func enqueueClientEvent(_ event:ClientInventoryEvent)->Bool {
        guard pendingClientEvents.count<128 else{
            if !clientQueueOverflowed {clientQueueOverflowed=true;onNeedsResync?()};return false
        }
        pendingClientEvents.append(event);return true
    }

    private static func originalDefinitions(_ rows: [[String: Any]]) -> [NativeOriginalWorldArsenal.Definition] {
        var seen = Set<Int>()
        return rows.compactMap { row in
            guard let id=integer(row["id"]), id<=46, seen.insert(id).inserted,
                  let slot=integer(row["slot"]), slot<13, let capacity=integer(row["capacity"]), capacity<=9999,
                  let kind=row["kind"] as? String, ["MELEE","INSTANT_HIT","PROJECTILE","AREA_EFFECT","USE","CAMERA"].contains(kind),
                  let wait=(row["wait"] as? NSNumber)?.doubleValue, wait.isFinite, (0...60).contains(wait),
                  let reload=(row["reload"] as? NSNumber)?.doubleValue, reload.isFinite, (0...60).contains(reload) else { return nil }
            return .init(id:id,slot:slot,capacity:capacity,kind:kind,wait:wait,reload:reload)
        }
    }

    /// A fresh socket must announce its own nonce before snapshots can enable
    /// firing. HTTP or delayed old-socket state cannot negotiate this boundary.
    func setConnection(_ nonce: String?) {
        if usesClientOwnedInventory { if nonce == nil { beginOriginalSession() }; return }
        guard nonce != prediction.connection else { return }
        if let nonce, !nonce.isEmpty { prediction.connected(nonce) } else { prediction.disconnected() }
        selected = 0; owned = [0]; ammunition = [:]; revision = -1
        reloadUntil = 0; serverReloading = false; serverReloadEnd = nil; reloadRequest = nil; reloadRequestStarted = nil
        resyncNotified = false; reloadRefreshKey = nil; lastShot = -.infinity
        onChange?()
    }

    var pendingShotCount: Int { prediction.pending.count }
    var synchronized: Bool {
        if policy == .legacySAMP {return originalDefinitionsReady && legacySessionReady && originalArsenal != nil}
        if policy == .originalWorld {return originalDefinitionsReady && originalArsenal?.synchronized == true}
        return prediction.connection != nil ? prediction.synchronized && !prediction.needsResync : allowLegacySnapshots
    }
    var canFire: Bool { synchronized && !reloading && (!usesClientOwnedInventory || originalArsenal?.ready == true) && current.id == selected && (current.isMelee || current.isGun && rounds > 0) }

    /// Unacknowledged snapshots are ignored unless an explicit offline legacy
    /// mode was selected by a test. They never overwrite sequenced truth.
    @discardableResult func apply(_ inventory: [String: Any]) -> Bool {
        guard policy == .acknowledgedSelfHost else { return false }
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
        if usesClientOwnedInventory {
            guard let arsenal=originalArsenal, synchronized, arsenal.selectedID==weapon, arsenal.ready else { return false }
            if current.isMelee { return true }
            guard current.isGun, (arsenal.ammo?.clip ?? 0)>0 else { return false }
            arsenal.spend()
            if policy == .legacySAMP,!arsenal.has(weapon) {clientZeroAmmoWeapons.insert(weapon)}
            synchronizeOriginalPresentation(); return true
        }
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
        if usesClientOwnedInventory {
            let now=clock()
            if now.isFinite {
                if let previous=originalLastTick, now>=previous { originalArsenal?.tick(now-previous) }
                originalLastTick=now
            }
            if reloadUntil>0, reloadUntil<=now { reloadUntil=0; onChange?() }
            return
        }
        if let began = reloadRequestStarted, clock() - began > 2 { prediction.markUncertain() }
        if prediction.connection != nil, prediction.needsResync {
            if !resyncNotified { resyncNotified = true; onNeedsResync?() }
        } else { resyncNotified = false }
        guard serverReloading, reloadUntil <= clock() else { return }
        let key = "\(revision):\(prediction.processedShot)"
        guard reloadRefreshKey != key else { return }
        reloadRefreshKey = key; onNeedsRefresh?()
    }

    private func synchronizeOriginalPresentation() {
        guard usesClientOwnedInventory else { return }
        selected=originalArsenal?.selectedID ?? 0
        owned=Set(originalArsenal?.items.map(\.id) ?? []); owned.insert(0)
        onChange?()
    }
    /// Original sessions have no acknowledged nonce. Clear the distinct owner
    /// at every connection boundary rather than manufacturing a self-host ACK.
    func beginOriginalSession() {
        guard usesClientOwnedInventory else { return }
        originalArsenal?.disconnect();pendingClientEvents.removeAll();originalLastTick=clock()
        clientInventoryGeneration &+= 1;clientQueueOverflowed=false
        legacySessionReady=false;clientZeroAmmoWeapons.removeAll()
        reloadUntil=0; lastShot = -.infinity; synchronizeOriginalPresentation()
    }
    @discardableResult func applyOriginalGuns(_ value: Any?, back: Bool = false) -> Bool {
        guard policy == .originalWorld, let rows=value as? [[Any]], rows.count<=128 else { return false }
        tick()
        guard let arsenal=originalArsenal, originalDefinitionsReady else {
            return enqueueClientEvent(.guns(rows,back,clock()*1000))
        }
        let accepted=arsenal.receive(rows,back:back,now:clock()*1000)
        if accepted { synchronizeOriginalPresentation() }; return accepted
    }
    @discardableResult func selectOriginalWeapon(_ id: Int) -> Bool {
        guard usesClientOwnedInventory,(0...46).contains(id) else{return false}
        guard let arsenal=originalArsenal,originalDefinitionsReady else{return enqueueClientEvent(.command("select",id,0))}
        tick(); guard arsenal.take(id) else { return false }
        reloadUntil=0; synchronizeOriginalPresentation(); return true
    }
    @discardableResult func cycleOriginalWeapon(_ direction: Int) -> Int? {
        guard usesClientOwnedInventory, let arsenal=originalArsenal else { return nil }
        tick(); arsenal.next(direction); reloadUntil=0; synchronizeOriginalPresentation(); return selected
    }
    @discardableResult func reloadOriginal() -> Bool {
        guard usesClientOwnedInventory, let arsenal=originalArsenal else { return false }
        tick(); guard arsenal.loadable, !reloading else { return false }
        arsenal.reload(held:true); reloadUntil=clock()+arsenal.cooldownRemaining
        synchronizeOriginalPresentation(); return true
    }
    func outgoingOriginalGuns(flush: Bool = false) -> [[Int]]? {
        guard policy == .originalWorld else { return nil }
        tick()
        let rows=originalArsenal?.outgoingInventory(now:clock()*1000,flush:flush)
        if selected != originalArsenal?.selectedID || owned != Set((originalArsenal?.items.map(\.id) ?? []) + [0]) { synchronizeOriginalPresentation() }
        return rows
    }
    func originalGunsSent(_ rows: [[Int]]) {
        guard policy == .originalWorld else { return }
        originalArsenal?.inventorySent(rows,now:clock()*1000)
    }
    func reviveOriginalWeapons() {
        guard policy == .originalWorld else { return }
        guard originalDefinitionsReady else{_=enqueueClientEvent(.revive);return}
        tick(); originalArsenal?.revived(); reloadUntil=0; synchronizeOriginalPresentation()
    }
    /// Server reward/equipment commands explicitly replace inventory in the
    /// original client; a periodic carried-total message does not do that.
    @discardableResult func rearmOriginalWeapons(_ rows: [[Int]]) -> Bool {
        guard policy == .originalWorld,rows.count<=128,rows.allSatisfy({$0.count>=2 && (0...46).contains($0[0])}) else{return false}
        guard let arsenal=originalArsenal,originalDefinitionsReady else{return enqueueClientEvent(.rearm(rows))}
        tick(); arsenal.rearm(rows);clientZeroAmmoWeapons.removeAll(); _=arsenal.receive(rows,back:false,now:clock()*1000)
        reloadUntil=0; synchronizeOriginalPresentation(); return true
    }

    /// Legacy RPC inventory authority is explicit. A server acceptance/world
    /// baseline opens local input; it does not become an original-service guns
    /// message or an independent-server inventory nonce.
    func setClientWeaponReady(_ ready: Bool) {
        guard policy == .legacySAMP else{return}
        if !ready {beginOriginalSession();return}
        legacySessionReady=true;synchronizeOriginalPresentation()
    }
    @discardableResult private func applyClientWeaponOperation(_ operation:String,id:Int,amount:Int)->Bool {
        guard usesClientOwnedInventory else{return false}
        guard let arsenal=originalArsenal,originalDefinitionsReady else{
            return enqueueClientEvent(.command(operation,id,amount))
        }
        tick()
        let accepted:Bool
        switch operation {
        case "reset":arsenal.clear();clientZeroAmmoWeapons.removeAll();accepted=true
        case "select":accepted=arsenal.take(id)
        case "remove":
            accepted=arsenal.has(id) || clientZeroAmmoWeapons.contains(id)
            if accepted {
                if policy == .originalWorld {_=originalDrop(id,arsenal:arsenal)}else{arsenal.drop(id)}
                clientZeroAmmoWeapons.remove(id)
            }
        case "give":
            if policy == .legacySAMP,amount<=0 {arsenal.drop(id);clientZeroAmmoWeapons.insert(id);accepted=true}
            else {
                if policy == .originalWorld {accepted=originalGive(id,amount:Double(amount),arsenal:arsenal)}
                else {accepted=arsenal.give(id,amount:Double(max(0,min(9999,amount))))}
                if accepted{clientZeroAmmoWeapons.remove(id)}}
        case "ammo":
            if amount<=0 {
                accepted=arsenal.has(id) || clientZeroAmmoWeapons.contains(id)
                if accepted {arsenal.drop(id);clientZeroAmmoWeapons.insert(id)}
            }
            else if arsenal.has(id) {accepted=arsenal.setAmmo(id,total:amount)}
            else if clientZeroAmmoWeapons.contains(id) {
                let selected=arsenal.selectedID;accepted=arsenal.give(id,amount:Double(min(9999,amount)))
                _=arsenal.take(selected);if accepted{clientZeroAmmoWeapons.remove(id)}
            }else{accepted=false}
        default:accepted=false
        }
        if accepted {reloadUntil=0;synchronizeOriginalPresentation()};return accepted
    }
    @discardableResult func giveClientWeapon(_ id:Int,amount:Int)->Bool {
        guard (1...46).contains(id) else{return false}
        return applyClientWeaponOperation("give",id:id,amount:amount)
    }
    @discardableResult func resetClientWeapons()->Bool {applyClientWeaponOperation("reset",id:0,amount:0)}
    @discardableResult func removeClientWeapon(_ id:Int)->Bool {
        guard (1...46).contains(id) else{return false}
        return applyClientWeaponOperation("remove",id:id,amount:0)
    }
    @discardableResult func setClientAmmo(_ id:Int,amount:Int)->Bool {
        guard (1...46).contains(id) else{return false}
        return applyClientWeaponOperation("ammo",id:id,amount:amount)
    }

    private struct StaffWeapons {
        var give:(Int,Int)?,take:Int?,back:(Int,Int)?,fill:(Int,Int)?,arm:[(Int,Double)]?
        var disarm=false
        var hasCommands:Bool {give != nil || take != nil || fill != nil || arm != nil || disarm}
    }
    private static func staffInteger(_ value:Any?)->Int? {
        guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite,abs(n.doubleValue)<=9_007_199_254_740_991 else{return nil}
        return Int(exactly:n.doubleValue)
    }
    private static func staffPair(_ value:Any?)->(Int,Int)? {
        guard let row=value as? [Any],row.count>=2,let id=staffInteger(row[0]),let amount=staffInteger(row[1]) else{return nil}
        return (id,amount)
    }
    private static func staffTruthy(_ value:Any?)->Bool {
        guard let value,!(value is NSNull) else{return false}
        if let n=value as? NSNumber{return n.doubleValue != 0 && !n.doubleValue.isNaN}
        if let text=value as? String{return !text.isEmpty}
        return true
    }
    private func originalGive(_ id:Int,amount:Double,arsenal:NativeOriginalWorldArsenal)->Bool {
        // Original c6.give wraps tx.give: granting satchels also grants the
        // detonator first. Legacy CPed/RPC pairing has a separate contract.
        if id==39,!arsenal.give(40,amount:1){return false}
        return arsenal.give(id,amount:amount)
    }
    private func originalDrop(_ id:Int,arsenal:NativeOriginalWorldArsenal)->Bool {
        guard arsenal.has(id) else{return false}
        arsenal.drop(id);if id==39{arsenal.drop(40)};return true
    }
    /// Applies only the weapon portion of one original staff packet. Preserve
    /// its actual give→take/back→fill→arm→disarm order and alive-at-arrival
    /// guard. Health, freezing, skin and UI fields belong to their own owners.
    @discardableResult func applyOriginalStaffWeapons(_ packet:[String:Any],alive:Bool=true)->Bool {
        guard policy == .originalWorld,packet["t"]==nil || packet["t"] as? String=="staff" else{return false}
        var operation=StaffWeapons(give:Self.staffPair(packet["give"]),take:Self.staffInteger(packet["take"]),
            back:Self.staffPair(packet["back"]),fill:Self.staffPair(packet["fill"]),arm:nil,
            disarm:Self.staffTruthy(packet["disarm"]))
        if let rows=packet["arm"] as? [Any] {
            operation.arm=rows.prefix(128).compactMap {value in
                guard let row=value as? [Any],row.count>=2,let id=Self.staffInteger(row[0]),
                      let amount=row[1] as? NSNumber,CFGetTypeID(amount) != CFBooleanGetTypeID(),amount.doubleValue.isFinite,
                      abs(amount.doubleValue)<9_007_199_254_740_991 else{return nil}
                // Retain the reported amount for the carried-state signature:
                // tx.give bounds local ammo, while pU.heard does not clamp9999.
                return (id,amount.doubleValue)
            }
        }
        guard operation.hasCommands else{return true}
        guard originalDefinitionsReady else{return enqueueClientEvent(.staff(operation,alive))}
        return applyOriginalStaffWeapons(operation,alive:alive)
    }
    @discardableResult private func applyOriginalStaffWeapons(_ operation:StaffWeapons,alive:Bool)->Bool {
        guard policy == .originalWorld,let arsenal=originalArsenal else{return false}
        tick()
        if let (id,amount)=operation.give,alive {_=originalGive(id,amount:Double(amount),arsenal:arsenal)}
        if let id=operation.take,originalDrop(id,arsenal:arsenal),let (back,amount)=operation.back,alive {
            _=originalGive(back,amount:Double(amount),arsenal:arsenal)
        }
        if let (id,desired)=operation.fill,let definition=arsenal.definition(for:id),alive {
            let item=arsenal.items.first{$0.id==id},total=item.map{$0.clip+$0.reserve} ?? 0
            let empty=item==nil && !arsenal.items.contains{$0.slot==definition.slot}
            if (item != nil || empty),total<desired {_=originalGive(id,amount:Double(desired-total),arsenal:arsenal)}
        }
        if let rows=operation.arm {
            arsenal.clear();for (id,amount)in rows{_=arsenal.give(id,amount:amount)};arsenal.holster()
            clientZeroAmmoWeapons.removeAll();_=arsenal.receive(rows.map{[$0.0,$0.1] as [Any]},back:false,now:clock()*1000)
        }
        if operation.disarm {arsenal.rearm([]);clientZeroAmmoWeapons.removeAll();_=arsenal.receive([],back:false,now:clock()*1000)}
        reloadUntil=0;synchronizeOriginalPresentation();return true
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
