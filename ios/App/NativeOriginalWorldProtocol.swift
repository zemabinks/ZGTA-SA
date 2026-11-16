import Foundation
import CoreFoundation

/// Original browser service protocol. This is deliberately separate from our
/// acknowledged self-host protocol: it neither negotiates fake capabilities
/// nor grants an unauthenticated guest access to the original service.
enum NativeOriginalWorldProtocol {
    static let supportedProtocol = 38
    static let referenceBuild = "202611100434"

    enum Error: Swift.Error { case invalidOrigin, invalidBuild, invalidIdentifier }

    static func origin(_ url: URL) throws -> URL {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == "https", let host = c.host?.lowercased(),
              host == "play.samp.directory", c.user == nil, c.password == nil,
              c.port == nil || c.port == 443,
              let result = URL(string: "https://play.samp.directory/") else { throw Error.invalidOrigin }
        return result
    }

    static func hello(build: String = referenceBuild, supportsAIDriving: Bool = false) throws -> [String: Any] {
        guard build.utf8.count == 12, build.utf8.allSatisfy({ (48...57).contains($0) }) else { throw Error.invalidBuild }
        return ["t": "hi", "b": build, "c": supportsAIDriving ? ["aidrive": 1] : [String:Int]()]
    }

    static func liveURL(deviceID: String, tabs: Bool = false) throws -> URL {
        guard deviceID.utf8.count == 32, deviceID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw Error.invalidIdentifier }
        var c = URLComponents(string: "wss://play.samp.directory/api/world/live")!
        c.queryItems = (tabs ? [URLQueryItem(name: "tabs", value: "1")] : []) + [URLQueryItem(name: "device", value: deviceID)]
        return c.url!
    }

    static var accountURL: URL { URL(string: "https://play.samp.directory/api/auth/me")! }
    static var presenceURL: URL { URL(string: "https://play.samp.directory/api/world/presence")! }
    static var buildURL: URL { URL(string: "https://play.samp.directory/game/build")! }
    static var loginURL: URL {
        var c = URLComponents(string: "https://play.samp.directory/api/auth/discord/login")!
        // Complete OAuth on an original-site JSON page. Loading the browser
        // game here would start its separate WebGL/WASM engine during sign-in.
        c.queryItems = [URLQueryItem(name: "next", value: accountURL.path)]
        return c.url!
    }

    /// Copy only cookies obtained by this app's explicit original-site sign-in.
    /// Never load a Chrome profile or export another site's OAuth cookies.
    static func sessionCookies(_ cookies: [HTTPCookie], now: Date = Date()) -> [HTTPCookie] {
        cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return ["play.samp.directory", "samp.directory"].contains(domain) && cookie.isSecure &&
                (cookie.expiresDate == nil || cookie.expiresDate! > now)
        }
    }

    static func validGuns(_ value: Any?) -> Bool {
        guard let rows=value as? [[Any]], rows.count<=128 else { return false }
        return rows.allSatisfy { row in
            guard row.count>=2, let id=row[0] as? NSNumber, CFGetTypeID(id) != CFBooleanGetTypeID(),
                  id.doubleValue.isFinite, id.doubleValue.rounded(.down)==id.doubleValue, (0...46).contains(id.doubleValue),
                  let amount=row[1] as? NSNumber, CFGetTypeID(amount) != CFBooleanGetTypeID(),
                  amount.doubleValue.isFinite, (1...19998).contains(amount.doubleValue) else { return false }
            return true
        }
    }

    static func acceptsProtocol(_ value: Any?) -> Bool {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue.rounded(.down) == n.doubleValue else { return false }
        return n.intValue >= 1 && n.intValue <= supportedProtocol
    }
}

/// Framed binary player/shot stream used by original protocol38. Decoding
/// produces a retained full player snapshot because the existing native scene
/// owns remote entities by snapshot. Other server subsystems retain their own
/// typed record tag and bytes for explicit adapters; they are not called done.
final class NativeOriginalWorldStream {
    enum Event {
        case players([[Any]])
        case shot([String: Any])
        case extensionRecord(tag: UInt8, payload: Data)
    }
    private struct Entry { var stamp: Int; var row: [Any] }
    private struct Missing { var since: Double; var asked: Double; var clock: Double }
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var activeIDs: Set<String>?
    private var missing: [String: Missing] = [:]
    private var missingOrder: [String] = []
    private var serverClock: Double?
    private var localClock = 0.0
    private let maximumFrameBytes = 1_048_576
    private let maximumRecords = 4096

    var rows: [[Any]] { order.filter { activeIDs?.contains($0) ?? true }.compactMap { entries[$0]?.row } }
    func clock(serverMilliseconds: Double, localMilliseconds: Double) {
        guard serverMilliseconds.isFinite, localMilliseconds.isFinite else { return }
        serverClock = serverMilliseconds; localClock = localMilliseconds
    }
    func clear() {
        entries.removeAll(); order.removeAll(); missing.removeAll(); missingOrder.removeAll()
        serverClock = nil; localClock = 0; activeIDs = nil
    }
    func gone(_ id: String) {
        entries.removeValue(forKey: id); order.removeAll { $0 == id }; activeIDs?.remove(id)
        missing.removeValue(forKey: id); missingOrder.removeAll { $0 == id }
    }
    private func need(_ id: String, now: Double, clock: Double = 0) {
        if var entry = missing[id] { entry.clock = max(entry.clock, clock); missing[id] = entry }
        else { missing[id] = Missing(since: now, asked: -.infinity, clock: clock); missingOrder.append(id) }
    }
    private func resolved(_ id: String, clock: Double) {
        if let entry = missing[id], clock >= entry.clock {
            missing.removeValue(forKey: id); missingOrder.removeAll { $0 == id }
        }
    }
    private func cache(_ id: String, entry: Entry) {
        order.removeAll { $0 == id }; order.append(id); entries[id] = entry; activeIDs?.insert(id)
        if order.count > 256 { entries.removeValue(forKey: order.removeFirst()) }
    }
    func wanted(now: Double) -> [String] {
        guard now.isFinite else { return [] }
        var result: [String] = []
        for id in missingOrder {
            guard var entry = missing[id] else { continue }
            if now - entry.since > 10_000 { missing.removeValue(forKey: id); continue }
            if now - entry.since >= 250, now - entry.asked >= 1000, result.count < 32 {
                entry.asked = now; missing[id] = entry; result.append(id)
            }
        }
        missingOrder.removeAll { missing[$0] == nil }
        return result
    }
    /// Original `all.near` advertises [id, stamp, sampleAge]. Return only the
    /// matching retained baselines; ask `who` for missing or stale baselines.
    func near(_ descriptors: [[Any]], serverTime: Double?, now: Double) -> [[Any]] {
        var result: [[Any]] = []
        activeIDs = Set(descriptors.filter { $0.count >= 2 }.prefix(4096).map { Self.identifier($0[0]) })
        for descriptor in descriptors.prefix(4096) where descriptor.count >= 2 {
            let id = Self.identifier(descriptor[0])
            let age = descriptor.count > 2 ? Self.number(descriptor[2]) : nil
            let required = serverTime.flatMap { time in age.map { time - $0 } } ?? 0
            if let entry = entries[id], Self.integer(descriptor[1]) == entry.stamp {
                if (entry.row.count > 16 ? Self.number(entry.row[16]) ?? 0 : 0) >= required { resolved(id, clock: required) }
                else { need(id, now: now, clock: required) }
                result.append(entry.row)
            } else { need(id, now: now) }
        }
        return result
    }
    private static func identifier(_ value: Any) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return String(describing: value)
    }
    private static func number(_ value: Any) -> Double? {
        guard let n = value as? NSNumber, n.doubleValue.isFinite else { return nil }; return n.doubleValue
    }
    private static func integer(_ value: Any) -> Int? {
        guard let n = number(value), n.rounded(.down) == n, abs(n) < 9_007_199_254_740_992 else { return nil }; return Int(n)
    }
    private func unwrap(_ value: UInt32, now: Double) -> Double {
        let estimate = (serverClock.map { $0 + now - localClock } ?? Date().timeIntervalSince1970 * 1000).rounded()
        let modulus: Int64 = 4_294_967_296
        var difference = (Int64(value) - Int64(estimate)) % modulus
        if difference < 0 { difference += modulus }
        if difference >= modulus / 2 { difference -= modulus }
        return estimate + Double(difference)
    }
    private struct Reader {
        let bytes: [UInt8]; var offset: Int; let end: Int
        enum Error: Swift.Error { case truncated, invalid }
        mutating func unsigned(_ count: Int) throws -> UInt64 {
            guard count >= 1, count <= 4, offset >= 0, offset <= end, count <= end-offset else { throw Error.truncated }
            var value: UInt64 = 0
            for _ in 0..<count { value = value << 8 | UInt64(bytes[offset]); offset += 1 }
            return value
        }
        mutating func signed(_ count: Int) throws -> Double {
            let raw = try unsigned(count); let sign = UInt64(1) << (count*8-1)
            return raw & sign == 0 ? Double(raw) : Double(Int64(raw)-Int64(UInt64(1) << (count*8)))
        }
        mutating func byte() throws -> Int { Int(try unsigned(1)) }
        mutating func text(_ count: Int) throws -> String {
            guard count >= 0, count <= end-offset else { throw Error.truncated }
            let value = String(decoding: bytes[offset..<(offset+count)], as: UTF8.self); offset += count; return value
        }
    }
    private func delta(_ input: Entry, reader: inout Reader, flags: Int, now: Double) throws -> Entry {
        var output = input; var row = input.row
        while row.count < 44 { row.append(NSNull()) }
        row[16] = unwrap(UInt32(try reader.unsigned(4)), now: now)
        for index in 3...5 { row[index] = try reader.signed(4)/1000 }
        let angular = flags & 4096 != 0 ? 4 : 2
        row[6] = try reader.signed(angular)/1000
        for index in 7...8 { row[index] = flags & 64 != 0 ? try reader.signed(angular)/1000 : 0 }
        let speedBytes = flags & 256 != 0 ? 3 : 2
        for index in 13...15 { row[index] = try reader.signed(speedBytes)/1000 }
        row[18] = Int(try reader.unsigned(2)); row[30] = try reader.byte()
        if flags & 128 != 0 {
            row[9] = try reader.signed(3)/1000
            for index in [10,20,21,22] { row[index] = try reader.signed(2)/1000 }
            row[43] = try reader.byte()
        } else { for index in [9,10,20,21,22,43] { row[index] = 0 } }
        row[24] = flags & 32 != 0 ? Double(try reader.unsigned(2))/1000 : 0
        row[28] = flags & 512 != 0 ? try reader.signed(2)/1000 : NSNull()
        var shots = 0, multiplier = 1
        if flags & 1024 != 0 {
            for index in 0..<8 {
                let byte = try reader.byte(); shots += (byte & 127)*multiplier
                guard shots <= 9_007_199_254_740_991 else { throw Reader.Error.invalid }
                if byte < 128 { break }
                guard index < 7 else { throw Reader.Error.invalid }; multiplier *= 128
            }
        }
        row[29] = shots
        if flags & 2048 != 0 { row[32] = try reader.byte(); row[38] = try reader.byte() }
        else { row[32] = 0; row[38] = 0 }
        row[40] = flags & 8192 != 0 ? Double(try reader.unsigned(2))/1000 : NSNull()
        if flags & 16384 != 0 {
            let name = try reader.text(try reader.byte())
            row[39] = [name,try reader.signed(4)/1000,try reader.signed(4)/1000,try reader.signed(4)/1000] as [Any]
        } else { row[39] = NSNull() }
        if flags & 32768 != 0 {
            let count = try reader.byte(); var kit: [Double] = []
            for _ in 0..<count { kit.append(try reader.signed(4)/1000) }; row[42] = kit
        } else { row[42] = NSNull() }
        row[11] = flags & 1 != 0 ? 1 : 0; row[25] = flags & 2 != 0 ? 1 : 0
        row[26] = flags & 4 != 0 ? 1 : 0; row[17] = (flags >> 3) & 3
        output.row = row; return output
    }
    /// Invalid records are discarded at their frame boundary without partially
    /// updating a cached actor. Limits bound peer-controlled work and memory.
    func read(_ data: Data, now: Double) -> [Event] {
        guard data.count <= maximumFrameBytes, now.isFinite else { return [] }
        let bytes = [UInt8](data); var cursor = 0; var records = 0
        var events: [Event] = [], dirty = false
        func flush() { if dirty { events.append(.players(rows)); dirty = false } }
        while cursor+2 <= bytes.count, records < maximumRecords {
            let tag = bytes[cursor]; var length = Int(bytes[cursor+1]); cursor += 2
            if length >= 128 {
                guard cursor < bytes.count else { break }
                length = length & 127 | Int(bytes[cursor]) << 7; cursor += 1
            }
            guard length <= bytes.count-cursor else { break }
            let end = cursor+length; var reader = Reader(bytes: bytes, offset: cursor, end: end)
            defer { cursor = end; records += 1 }
            do {
                switch tag {
                case 1:
                    let stamp = Int(try reader.unsigned(2))
                    let payload = Data(bytes[reader.offset..<end])
                    guard let row = try JSONSerialization.jsonObject(with: payload) as? [Any], !row.isEmpty, row.count <= 128 else { continue }
                    let id = Self.identifier(row[0]); cache(id, entry: Entry(stamp: stamp, row: row))
                    resolved(id, clock: row.count > 16 ? Self.number(row[16]) ?? 0 : 0); dirty = true
                case 2:
                    let id = String(try reader.unsigned(2)), stamp = Int(try reader.unsigned(2)), flags = Int(try reader.unsigned(2))
                    guard let old = entries[id] else { need(id, now: now); continue }
                    let updated = try delta(old, reader: &reader, flags: flags, now: now)
                    if old.stamp != stamp { need(id, now: now) }
                    entries[id] = updated; activeIDs?.insert(id)
                    if old.stamp == stamp { resolved(id, clock: Self.number(updated.row[16]) ?? 0) }
                    dirty = true
                case 3:
                    var shot: [String: Any] = ["from": String(try reader.unsigned(2)), "w": try reader.byte()]
                    var origin: [Double] = [], target: [Double] = []
                    for _ in 0..<3 { origin.append(try reader.signed(4)/1000) }
                    for _ in 0..<3 { target.append(try reader.signed(4)/1000) }
                    shot["o"] = origin; shot["h"] = target; shot["ht"] = try reader.byte()
                    if length >= 31 { shot["id"] = String(try reader.unsigned(2)); let bone = try reader.byte(); if bone != 0 { shot["bp"] = bone } }
                    flush(); events.append(.shot(shot))
                default:
                    events.append(.extensionRecord(tag: tag, payload: Data(bytes[cursor..<end])))
                }
            } catch { continue }
        }
        flush(); return events
    }
}
