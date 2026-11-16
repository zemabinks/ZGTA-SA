import Foundation
import CoreFoundation

/// Explicit inventory owner for the original browser service. That service
/// synchronizes carried totals, while its client owns slots, clips and reload
/// timing. It does not issue our self-host shot acknowledgements.
final class NativeOriginalWorldArsenal {
    struct Definition {
        let id: Int, slot: Int, capacity: Int
        let kind: String
        let wait: Double, reload: Double
        var usesAmmo: Bool { kind != "MELEE" && capacity > 0 }
    }
    struct Item {
        let id: Int, slot: Int
        var clip: Int, reserve: Int
        var until = 0.0, again = 0.0
    }
    private let definitions: [Int: Definition]
    private var slots: [Item?]
    private var selectedSlot = 0
    private var time = 0.0, globalAgain = 0.0
    private(set) var synchronized = false
    private var acknowledgedSignature = ""
    private var lastSent = -Double.infinity, lastCheck = -Double.infinity
    private var stagedReturn: [[Int]]?, stagedAt = 0.0
    private var selected: Item? { slots[selectedSlot] }
    private var selectedDefinition: Definition? { selected.flatMap { definitions[$0.id] } }
    var selectedID: Int { selected?.id ?? 0 }
    var slot: Int { selectedSlot }
    var items: [Item] { slots.compactMap { $0 } }
    func definition(for id:Int)->Definition? {definitions[id]}
    var ammo: (clip: Int, reserve: Int)? {
        guard let selected, selectedDefinition?.usesAmmo == true else { return nil }
        return (selected.clip, selected.reserve)
    }
    var ready: Bool {
        guard let selected, selectedDefinition?.usesAmmo == true else { return true }
        return selected.clip > 0 && time >= selected.until
    }
    var poised: Bool {
        ready && time >= (selected?.again ?? 0) && (selectedDefinition?.usesAmmo != true || time >= globalAgain)
    }
    var cooldownRemaining: Double { max(0,(selected?.until ?? 0)-time) }
    var dry: Bool { selectedDefinition?.usesAmmo == true && (selected?.clip ?? 0) <= 0 && (selected?.reserve ?? 0) > 0 }
    var loadable: Bool {
        guard let selected, let definition = selectedDefinition, definition.usesAmmo else { return false }
        return selected.clip < definition.capacity && selected.reserve > 0
    }
    var carriedRows: [[Int]] { items.filter { $0.id != 46 }.map { [$0.id, max(1,$0.clip+$0.reserve)] } }

    init(definitions: [Definition], slotCount: Int = 13) {
        let count = max(1,min(64,slotCount))
        self.definitions = Dictionary(definitions.filter { (0..<count).contains($0.slot) && (0...46).contains($0.id) }.map { ($0.id,$0) }, uniquingKeysWith: { _,new in new })
        slots = Array(repeating: nil, count: count)
    }
    func tick(_ elapsed: Double) { if elapsed.isFinite, elapsed >= 0 { time += elapsed } }
    func clear() { slots = Array(repeating: nil,count: slots.count); selectedSlot = 0; globalAgain = 0 }
    func disconnect() {
        clear(); time = 0; synchronized = false; acknowledgedSignature = ""
        lastSent = -.infinity; lastCheck = -.infinity; stagedReturn = nil; stagedAt = 0
    }
    @discardableResult func give(_ id: Int, amount: Double = 500) -> Bool {
        guard id != 0, let definition = definitions[id] else { return false }
        let amount = definition.usesAmmo ? max(1,min(9999,Int(max(1,min(9999,(amount.isFinite ? amount : 0).rounded(.toNearestOrAwayFromZero)))))) : 1
        if var existing = slots[definition.slot], existing.id == id, definition.usesAmmo {
            existing.reserve = min(9999,existing.reserve+amount); slots[definition.slot] = existing
        } else {
            let clip = definition.usesAmmo ? min(definition.capacity,amount) : 0
            slots[definition.slot] = Item(id:id,slot:definition.slot,clip:clip,reserve:amount-clip)
        }
        selectedSlot = definition.slot; return true
    }
    @discardableResult func setAmmo(_ id: Int, total: Int) -> Bool {
        guard let index=slots.firstIndex(where:{$0?.id==id}),var item=slots[index],
              let definition=definitions[id],definition.usesAmmo else{return false}
        let total=max(0,min(9999,total))
        if total==0 {drop(id);return true}
        item.clip=min(item.clip,total);item.reserve=total-item.clip;slots[index]=item;return true
    }
    func holster() { selectedSlot = 0 }
    func has(_ id: Int) -> Bool { items.contains { $0.id == id } }
    func drop(_ id: Int) {
        guard let index = slots.firstIndex(where: { $0?.id == id }) else { return }
        slots[index] = nil; if selectedSlot == index { selectedSlot = 0 }
    }
    @discardableResult func take(_ id: Int) -> Bool {
        if id == 0 { selectedSlot = 0; return true }
        guard let index = slots.firstIndex(where: { $0?.id == id }) else { return false }
        selectedSlot = index; return true
    }
    func next(_ direction: Int, allowed: Set<Int>? = nil) {
        let direction = direction % slots.count
        guard direction != 0 else { return }
        var target: Int?
        for step in 1..<slots.count {
            let index = ((selectedSlot+direction*step)%slots.count+slots.count)%slots.count
            let id = index == 0 ? 0 : slots[index]?.id
            if let id, allowed == nil || allowed!.contains(id) { target = index; break }
        }
        guard let target else { return }
        // The browser tops up a non-empty outgoing clip when cycling slots.
        // Direct selection deliberately retains its separate source behavior.
        if var outgoing = selected, let definition = selectedDefinition, definition.usesAmmo, outgoing.clip > 0 {
            let fill = min(definition.capacity-outgoing.clip,outgoing.reserve)
            outgoing.clip += fill; outgoing.reserve -= fill; slots[selectedSlot] = outgoing
        }
        selectedSlot = target
    }
    func spend(after delay: Double = 0) {
        guard var item = selected, let definition = selectedDefinition, definition.usesAmmo, item.clip > 0 else { return }
        item.clip -= 1; item.until = time + (item.clip <= 0 ? definition.reload : definition.wait)
        item.again = time + max(0,delay.isFinite ? delay : 0); globalAgain = max(globalAgain,item.again)
        if item.clip <= 0, item.reserve <= 0 { slots[selectedSlot] = nil; selectedSlot = 0 }
        else { slots[selectedSlot] = item }
    }
    func reload(held: Bool = false) {
        guard var item = selected, let definition = selectedDefinition, definition.usesAmmo else { return }
        if held, item.clip < definition.capacity, item.reserve > 0 { item.until = max(item.until,time+definition.reload) }
        let fill = min(definition.capacity-item.clip,item.reserve)
        item.clip += fill; item.reserve -= fill; slots[selectedSlot] = item
    }
    func rearm(_ rows: [[Int]]) {
        clear(); for row in rows where row.count >= 2 { _ = give(row[0],amount:Double(row[1])) }; holster()
    }
    private static func signature(_ rows: [[Int]]) -> String { rows.map { "\($0[0]):\($0[1])" }.joined(separator:",") }
    private static func ownership(_ signature: String) -> String {
        signature.split(separator:",").map { $0.split(separator:":",maxSplits:1).first.map(String.init) ?? "" }.joined(separator:",")
    }
    /// Rows are server-carried totals, not a forged acknowledged snapshot.
    /// `back` is held until the original revive boundary (or20s fallback).
    @discardableResult func receive(_ value: Any?, back: Bool, now: Double) -> Bool {
        guard let rows = value as? [[Any]], rows.count <= 128, now.isFinite else { return false }
        var parsed: [[Int]] = []
        for row in rows where row.count >= 2 {
            guard let id = row[0] as? NSNumber, CFGetTypeID(id) != CFBooleanGetTypeID(),
                  id.doubleValue.isFinite, id.doubleValue.rounded(.down) == id.doubleValue, abs(id.doubleValue)<9_007_199_254_740_991,
                  let ammo = row[1] as? NSNumber, CFGetTypeID(ammo) != CFBooleanGetTypeID(), ammo.doubleValue.isFinite,
                  abs(ammo.doubleValue) < 9_007_199_254_740_991 else { continue }
            // The original carried-state signature keeps unknown integer IDs.
            // They cannot grant an undefined weapon, but omitting them from
            // this baseline would suppress the client's corrective inventory.
            parsed.append([id.intValue,max(1,Int(ammo.doubleValue.rounded(.toNearestOrAwayFromZero)))])
        }
        if back { stagedReturn = parsed; stagedAt = now; return true }
        if !synchronized { synchronized = true; if !parsed.isEmpty { rearm(parsed) } }
        acknowledgedSignature = Self.signature(parsed); lastSent = -.infinity; lastCheck = -.infinity
        return true
    }
    func revived() {
        guard let rows = stagedReturn else { return }
        stagedReturn = nil; if !rows.isEmpty { rearm(rows) }
        acknowledgedSignature = Self.signature(rows); lastSent = -.infinity; lastCheck = -.infinity
    }
    /// Only commit after the actual WebSocket send was accepted. A closed
    /// socket must not suppress retry by advancing the last-sent baseline.
    func inventorySent(_ rows: [[Int]], now: Double) {
        guard now.isFinite else { return }; acknowledgedSignature = Self.signature(rows); lastSent = now
    }
    func outgoingInventory(now: Double, flush: Bool = false) -> [[Int]]? {
        guard now.isFinite else { return nil }
        if !flush, let _ = stagedReturn, now-stagedAt >= 20_000 { revived() }
        guard synchronized, stagedReturn == nil else { return nil }
        if !flush {
            guard now-lastCheck >= 250 else { return nil }; lastCheck = now
        }
        let rows = carriedRows, signature = Self.signature(rows)
        guard signature != acknowledgedSignature else { return nil }
        if !flush {
            let interval = Self.ownership(signature) == Self.ownership(acknowledgedSignature) ? 5000.0 : 600.0
            guard now-lastSent >= interval else { return nil }
        }
        return rows
    }
}
