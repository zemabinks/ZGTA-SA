// SPDX-License-Identifier: AGPL-3.0-only
// Link the actual RawStore/RawLease/ISO-selection support, parser and loader;
// these tests use an authored extractor and never open the real app container.
import Foundation
import CryptoKit
import Darwin

private typealias Loader = NativeOriginalNavigationLoader
private typealias Store = NativeRawResourceStore
private typealias Lease = NativeRawResourceLease
private enum AdapterCheckError: Error { case failed(String) }

@main
private struct NativeOriginalNavigationLoaderTests {
    private static var checks = 0
    private static func check(_ value: Bool, _ label: String) throws {
        checks += 1; if !value { throw AdapterCheckError.failed(label) }
    }
    private static func awaitResult<Value>(_ begin: (@escaping (Result<Value, Error>) -> Void) -> Void) throws -> Value {
        var result: Result<Value, Error>?
        begin { result = $0 }
        try wait { result != nil }
        return try result!.get()
    }
    private static func wait(_ condition: () -> Bool) throws {
        let end = Date().addingTimeInterval(30)
        while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.003)) }
        try check(condition(), "bounded main-queue completion")
    }
    private static func failure(_ expected: (Loader.Failure) -> Bool,
                                _ begin: (@escaping (Result<Loader.Snapshot, Error>) -> Void) -> Void) throws {
        do { let _: Loader.Snapshot = try awaitResult(begin); throw AdapterCheckError.failed("expected loader failure") }
        catch let actual as Loader.Failure { try check(expected(actual), "expected typed failure: \(actual)") }
    }
    private static func put16(_ data: inout Data, _ at: Int, _ value: UInt16) {
        data[at] = UInt8(truncatingIfNeeded: value); data[at + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }
    private static func put32(_ data: inout Data, _ at: Int, _ value: UInt32) {
        for byte in 0..<4 { data[at + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8)) }
    }
    private enum Scenario: Equatable { case valid, exterior, missing, unsupported, oversized, wrongSelection, badReference, linkedArea }
    private static func bytes(area: Int, scenario: Scenario) -> Data {
        guard area == 13 else { return Data(count: 20) }
        if scenario == .oversized { return Data(count: NativeOriginalPathArea.maximumBytes + 1) }
        if scenario == .unsupported { var data = Data(count: 20); put32(&data, 0, UInt32.max); return data }
        let naviOffset = 20 + 4 * 28, addressesOffset = naviOffset + 14
        let packedOffset = addressesOffset + (4 + 192) * 4, lengthsOffset = packedOffset + 4 * 2
        let crossingsOffset = lengthsOffset + 4 + 192
        var data = Data(count: crossingsOffset + 4 + 192)
        for (index, count) in [UInt32(4), 2, 2, 1, 4].enumerated() { put32(&data, index * 4, count) }
        for index in 0..<4 {
            let at = 20 + index * 28
            put16(&data, at + 8, UInt16((index % 2) * 8)); put16(&data, at + 10, index < 2 ? 0 : 8)
            if scenario == .exterior {
                put16(&data, at + 8, UInt16((1480 + (index % 2) * 45) * 8))
                put16(&data, at + 10, UInt16(bitPattern: Int16((-1738 + (index % 2) * 63 + (index < 2 ? 0 : 1)) * 8)))
                put16(&data, at + 12, 104)
            }
            put16(&data, at + 14, 32766); put16(&data, at + 16, UInt16(index))
            put16(&data, at + 18, 13); put16(&data, at + 20, UInt16(index)); put32(&data, at + 24, 1)
            put16(&data, addressesOffset + index * 4, 13)
            put16(&data, addressesOffset + index * 4 + 2, UInt16(index ^ 1))
            put16(&data, packedOffset + index * 2, index < 2 ? UInt16(13 << 10) : 0)
            data[lengthsOffset + index] = 1
        }
        put16(&data, naviOffset + 4, 13); data[naviOffset + 8] = 100
        put32(&data, naviOffset + 10, (2 << 8) | (1 << 11)); data[crossingsOffset + 2] = 1; data[crossingsOffset + 3] = 3
        if scenario == .badReference { put16(&data, addressesOffset + 2, 99) }
        if scenario == .linkedArea { put16(&data, addressesOffset, 14) }
        return data
    }
    private static func extractor(_ scenario: Scenario) -> Store.Extractor {
        .init(identity: scenario == .wrongSelection ? "authored-unsupported-navigation-v1" : "zgta-original-raw-selection-v1") { _, token in
            let areas = (0..<64).filter { scenario != .missing || $0 != 63 }
            let entries = areas.enumerated().map { pair in
                NativeISOExtraction.Entry(index: pair.offset, path: "data/Paths/NODES\(pair.element).DAT", group: "data",
                                          bytes: UInt64(bytes(area: pair.element, scenario: scenario).count), source: .cabinet)
            }
            return .init(members: entries, extract: { destination, progress in
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                for (offset, entry) in entries.enumerated() {
                    if token.isCancelled { throw NativeISOExtraction.Failure.cancelled }
                    let path = destination.appendingPathComponent(entry.path)
                    try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try bytes(area: areas[offset], scenario: scenario).write(to: path)
                    progress(.init(path: entry.path, completedBytes: UInt64(offset + 1), totalBytes: UInt64(entries.count),
                                   completedFiles: UInt32(offset + 1), totalFiles: UInt32(entries.count)))
                }
            })
        }
    }
    private struct Fixture {
        let folder: URL, root: URL, source: URL, store: Store
    }
    private static func fixture(_ parent: URL, _ name: String, _ scenario: Scenario = .valid) throws -> Fixture {
        let folder = parent.appendingPathComponent(name), root = folder.appendingPathComponent("store"), source = folder.appendingPathComponent("authored.iso")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([17, 31, 47]).write(to: source)
        let initial = Store(root: root, extractor: extractor(scenario))
        let _: Store.Snapshot = try awaitResult { initial.extractISO(source, progress: { _ in }, completion: $0) }
        // Relaunch-style store starts with metadata retained, verified=false.
        let reopened = Store(root: root, extractor: extractor(scenario))
        return Fixture(folder: folder, root: root, source: source, store: reopened)
    }
    private static var probes: [Loader.Probe] {
        [.init(kind: .ped, start: SIMD3(0, 1, 0), goal: SIMD3(1, 1, 0), maximumDistance: 2),
         .init(kind: .vehicle, start: SIMD3(0, 0, 0), goal: SIMD3(1, 0, 0), maximumDistance: 2)]
    }
    private static var all: Loader.Request { .init(areas: Array(UInt16(0)...UInt16(63)), probes: probes) }
    private static var local: Loader.Request { .init(areas: [13], probes: probes) }

    /// Delegates to real RawStore. Its optional single held acquisition models
    /// a source change/cancel after verification but before the adapter reads.
    /// Receipt callbacks retain the real delivery fence without any delay.
    private final class RecordingSource: NativeOriginalNavigationSource, @unchecked Sendable {
        let store: Store, gatePath: String?
        private let lock = NSLock()
        private var acquired = 0, usedGate = false, leases: [Lease] = []
        private var held: (Result<Lease, Error>, (Result<Lease, Error>) -> Void)?
        init(_ store: Store, gatePath: String? = nil) { self.store = store; self.gatePath = gatePath }
        var hasHeldLease: Bool { lock.lock(); defer { lock.unlock() }; return held != nil }
        var acquisitions: Int { lock.lock(); defer { lock.unlock() }; return acquired }
        var deliveredLeases: [Lease] { lock.lock(); defer { lock.unlock() }; return leases }
        func release() {
            precondition(Thread.isMainThread); lock.lock(); let value = held; held = nil; lock.unlock()
            if let value { value.1(value.0) }
        }
        func readReceiptDescriptor(expectedSourceID: String?, expectedContentID: String?,
            completion: @escaping (Result<Store.ReceiptDescriptor, Error>) -> Void) -> Lease.Request {
            store.readReceiptDescriptor(expectedSourceID: expectedSourceID, expectedContentID: expectedContentID, completion: completion)
        }
        func acquireLocalFile(path: String, matching: Store.ReceiptDescriptor, maximumBytes: Int64,
            verificationProgress: ((Lease.VerificationProgress) -> Void)?, completion: @escaping (Result<Lease, Error>) -> Void) -> Lease.Request {
            lock.lock(); acquired += 1
            let gate = !usedGate && gatePath?.lowercased() == path.lowercased(); if gate { usedGate = true }; lock.unlock()
            return store.acquireLocalFile(path: path, matching: matching, maximumBytes: maximumBytes, verificationProgress: verificationProgress) { result in
                self.lock.lock(); if case .success(let lease) = result { self.leases.append(lease) }
                if gate { self.held = (result, completion) }; self.lock.unlock()
                if !gate { completion(result) }
            }
        }
    }
    private static func checkClosed(_ leases: [Lease]) throws {
        for lease in leases {
            do { _ = try lease.read(atOffset: 0, maximumBytes: 1); throw AdapterCheckError.failed("lease retained past copy") }
            catch Lease.Failure.closed { try check(true, "delivered lease closed") }
        }
    }
    private static func descriptor(_ store: Store) throws -> Store.ReceiptDescriptor {
        try awaitResult { store.readReceiptDescriptor(completion: $0) }
    }
    private static func actualPath(_ fixture: Fixture, _ descriptor: Store.ReceiptDescriptor, area: Int) -> URL {
        fixture.root.appendingPathComponent("generations/\(descriptor.generationID)/files/data/Paths/NODES\(area).DAT")
    }
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock(); private var value: TimeInterval = 0
        func read() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return value }
        func advance(_ seconds: TimeInterval) { lock.lock(); value += seconds; lock.unlock() }
    }
    private final class PreparedFixture: NativeGameFilesService {
        var snapshot = NativeResourceStore.Snapshot(mode: .development, installedContentID: nil, installedFiles: 0, installedBytes: 0, cachedFiles: 0, cachedBytes: 0, hasPlayableInstallation: false, developmentOrigin: nil, issues: [])
        var writes = 0
        func observe(_ update: @escaping (NativeResourceStore.Snapshot) -> Void) -> UUID { update(snapshot); return UUID() }
        func removeObserver(_ id: UUID) {}
        func importFolder(_ folder: URL, progress: @escaping (NativeResourceStore.Progress) -> Void,
                          completion: @escaping (Result<NativeResourceStore.Snapshot, Error>) -> Void) -> () -> Void { writes += 1; return {} }
        func verify(progress: @escaping (NativeResourceStore.Progress) -> Void,
                    completion: @escaping (Result<NativeResourceStore.Snapshot, Error>) -> Void) -> () -> Void { writes += 1; return {} }
        func cache(origin: URL, progress: @escaping (NativeResourceStore.Progress) -> Void,
                   completion: @escaping (Result<NativeResourceStore.Snapshot, Error>) -> Void) -> () -> Void { writes += 1; return {} }
        func setMode(_ mode: NativeResourceStore.Mode) throws { writes += 1 }
    }
    private static func coordinatorLifecycle(_ root: URL) throws {
        let original = try fixture(root, "menu-exterior", .exterior), prepared = PreparedFixture()
        let reader = Loader(source: original.store), menu = NativeGameFilesCoordinator(service: prepared, navigationLoader: reader)
        let mode = menu.state.resources.mode
        try check(menu.validateOriginalNavigation() && menu.state.activity?.kind == .validatingNavigation, "normal menu dispatches actual loader")
        try check(!menu.verifyInstalled() && !menu.validateOriginalNavigation(), "menu prevents concurrent resource operations")
        try wait { !menu.state.busy }
        try check(!menu.state.failed && menu.state.message?.contains("route queries passed") == true, "menu completes actual exterior pedestrian and vehicle routes")
        try check(menu.state.resources.mode == mode && !menu.state.resources.hasPlayableInstallation && prepared.writes == 0,
                  "navigation action preserves installed admission and does not write prepared resources")
        let gate = RecordingSource(original.store, gatePath: "data/Paths/NODES13.DAT")
        let cancelled = NativeGameFilesCoordinator(service: prepared, navigationLoader: Loader(source: gate))
        try check(cancelled.validateOriginalNavigation(), "menu cancellation starts")
        try wait { gate.hasHeldLease }; cancelled.cancel(); cancelled.cancel(); gate.release()
        try wait { !cancelled.state.busy }
        try check(!cancelled.state.failed && cancelled.state.message?.contains("cancelled") == true, "menu cancellation completes without stale success")
        try checkClosed(gate.deliveredLeases)
        let reentrant = NativeGameFilesCoordinator(service: prepared, navigationLoader: reader)
        let observer = reentrant.observe { state in if state.busy && state.activity?.cancelling == false { reentrant.cancel() } }
        try check(reentrant.validateOriginalNavigation(), "menu reentrant cancellation starts")
        try wait { !reentrant.state.busy }; reentrant.removeObserver(observer)
        try check(!reentrant.state.failed && reentrant.state.message?.contains("cancelled") == true, "cancellation before loader handle attachment is preserved")
        let held = RecordingSource(original.store, gatePath: "data/Paths/NODES13.DAT")
        var dismissed: NativeGameFilesCoordinator? = NativeGameFilesCoordinator(service: prepared, navigationLoader: Loader(source: held))
        weak var retained = dismissed
        var notifications = 0
        let token = dismissed!.observe { _ in notifications += 1 }
        try check(dismissed!.validateOriginalNavigation(), "navigation survives screen dismissal")
        try wait { held.hasHeldLease }; dismissed!.removeObserver(token)
        let before = notifications; dismissed = nil
        try check(retained != nil, "app-owned operation retained after view dismissal")
        held.release(); try wait { retained == nil }
        try check(notifications == before, "dismissed screen receives no late callbacks")
        try checkClosed(held.deliveredLeases)
        let unavailable = NativeGameFilesCoordinator(service: prepared)
        try check(!unavailable.validateOriginalNavigation() && unavailable.state.failed && !unavailable.state.busy,
                  "unsupported menu configuration has an actionable failure")
    }
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw AdapterCheckError.failed("authored fixture output folder required") }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true).standardizedFileURL
        try check(root.lastPathComponent == "fixture", "isolated authored fixture directory required")
        let valid = try fixture(root, "valid"), source = RecordingSource(valid.store), loader = Loader(source: source)
        var callbacksOnMain = true
        let snapshot: Loader.Snapshot = try awaitResult { completion in
            loader.validate(all, progress: { _ in callbacksOnMain = callbacksOnMain && Thread.isMainThread }) { result in
                callbacksOnMain = callbacksOnMain && Thread.isMainThread; completion(result)
            }
        }
        try check(callbacksOnMain, "main-queue callbacks")
        try check(snapshot.files.count == 64 && source.acquisitions == 64, "all original areas actually acquired")
        try check(snapshot.summary.pedNodes == 2 && snapshot.summary.vehicleNodes == 2 && snapshot.probes.count == 2, "authored graph decoded and both actual queries run")
        try check(snapshot.probes.allSatisfy { $0.route.addresses.count == 2 }, "successful routes contain actual nodes")
        try check(!valid.store.snapshot.verified, "navigation checks do not verify the entire raw source")
        try checkClosed(source.deliveredLeases) // 64 successes also exceed RawStore's 16-live-lease quota if leaked.
        let current = try descriptor(valid.store)
        try check(snapshot.identity.generationID == current.generationID && snapshot.identity.contentID == current.contentID, "returned source-generation binding")

        let gated = RecordingSource(valid.store, gatePath: "data/Paths/NODES13.DAT"), cancellable = Loader(source: gated)
        var cancelled: Result<Loader.Snapshot, Error>?, completionCount = 0
        let operation = cancellable.validate(local) { cancelled = $0; completionCount += 1 }
        try wait { gated.hasHeldLease }
        try failure({ $0 == .busy }) { cancellable.validate(local, completion: $0) }
        operation.cancel(); gated.release(); try wait { cancelled != nil }
        switch cancelled! { case .failure(let error): try check((error as? Loader.Failure) == .cancelled, "cancelled operation rejects late lease"); case .success: throw AdapterCheckError.failed("cancel produced graph") }
        try check(completionCount == 1, "one cancellation completion"); try checkClosed(gated.deliveredLeases)

        let clock = TestClock(), timedSource = RecordingSource(valid.store, gatePath: "data/Paths/NODES13.DAT")
        let timedLoader = Loader(source: timedSource, now: { clock.read() })
        var timedResult: Result<Loader.Snapshot, Error>?
        timedLoader.validate(local) { timedResult = $0 }; try wait { timedSource.hasHeldLease }
        clock.advance(31); timedSource.release(); try wait { timedResult != nil }
        switch timedResult! { case .failure(let error): try check((error as? Loader.Failure) == .timeLimit, "cooperative time budget rejects late read"); case .success: throw AdapterCheckError.failed("timed-out graph published") }
        try checkClosed(timedSource.deliveredLeases)

        var limited = Loader.Limits(); limited.maximumTotalBytes = 100
        let limitedSource = RecordingSource(valid.store), limitedLoader = Loader(source: limitedSource, limits: limited)
        try failure({ if case .limit = $0 { return true }; return false }) { limitedLoader.validate(all, completion: $0) }
        try check(limitedSource.acquisitions == 0, "aggregate byte limit enforced before file acquisitions")
        var nodeLimit = Loader.Limits(); nodeLimit.maximumNodes = 3
        let nodeSource = RecordingSource(valid.store), nodeLoader = Loader(source: nodeSource, limits: nodeLimit)
        try failure({ if case .limit = $0 { return true }; return false }) { nodeLoader.validate(local, completion: $0) }
        try checkClosed(nodeSource.deliveredLeases)
        var queryLimit = Loader.Limits(); queryLimit.maximumNearestScans = 1
        let queryLoader = Loader(source: valid.store, limits: queryLimit)
        try failure({ $0 == .queryBudget }) { queryLoader.validate(local, completion: $0) }
        try failure({ $0 == .invalidRequest }) { loader.validate(.init(areas: [13], probes: []), completion: $0) }
        try failure({ $0 == .invalidRequest }) { loader.validate(.init(areas: [13, 13], probes: probes), completion: $0) }

        for (name, scenario) in [("missing", Scenario.missing), ("unsupported", .unsupported), ("oversized", .oversized), ("wrong-selection", .wrongSelection),
                                  ("bad-reference", .badReference), ("linked-area", .linkedArea)] {
            let data = try fixture(root, name, scenario), recorded = RecordingSource(data.store), reader = Loader(source: recorded)
            let request = scenario == .missing ? all : local
            try failure({ error in
                switch (scenario, error) {
                case (.missing, .missingAreas(let areas)): return areas == [63]
                case (.unsupported, .unsupportedArea(let area, _)): return area == 13
                case (.oversized, .unsupportedArea(let area, _)): return area == 13
                case (.wrongSelection, .unsupportedSelection): return true
                case (.badReference, .invalidReference(let area, let node)): return area == 13 && node == 99
                case (.linkedArea, .missingLinkedArea(let area)): return area == 14
                default: return false
                }
            }) { reader.validate(request, completion: $0) }
            try checkClosed(recorded.deliveredLeases)
            if scenario == .missing || scenario == .oversized || scenario == .wrongSelection { try check(recorded.acquisitions == 0, "metadata rejection is explicit, never a success") }
        }

        // Same source and content, NEW generation: final identity fence must reject it.
        let repair = try fixture(root, "same-content-repair"), before = try descriptor(repair.store)
        let repairSource = RecordingSource(repair.store, gatePath: "data/Paths/NODES13.DAT"), repairLoader = Loader(source: repairSource)
        var repairResult: Result<Loader.Snapshot, Error>?
        repairLoader.validate(local) { repairResult = $0 }; try wait { repairSource.hasHeldLease }
        try Data(repeating: 1, count: 20).write(to: actualPath(repair, before, area: 0))
        let _: Store.Snapshot = try awaitResult { repair.store.extractISO(repair.source, progress: { _ in }, completion: $0) }
        let after = try descriptor(repair.store)
        try check(before.sourceID == after.sourceID && before.contentID == after.contentID && before.generationID != after.generationID, "actual same-content repair replaced generation")
        repairSource.release(); try wait { repairResult != nil }
        switch repairResult! { case .failure(let error): try check((error as? Loader.Failure) == .sourceChanged, "same-content generation change rejected"); case .success: throw AdapterCheckError.failed("stale repair graph published") }
        try checkClosed(repairSource.deliveredLeases)

        let switched = try fixture(root, "source-switch"), switchedBefore = try descriptor(switched.store)
        let switchedSource = RecordingSource(switched.store, gatePath: "data/Paths/NODES13.DAT"), switchedLoader = Loader(source: switchedSource)
        var switchedResult: Result<Loader.Snapshot, Error>?
        switchedLoader.validate(local) { switchedResult = $0 }; try wait { switchedSource.hasHeldLease }
        let otherISO = switched.folder.appendingPathComponent("other-authored.iso"); try Data([19, 37, 53]).write(to: otherISO)
        let _: Store.Snapshot = try awaitResult { switched.store.extractISO(otherISO, progress: { _ in }, completion: $0) }
        let switchedAfter = try descriptor(switched.store)
        try check(switchedBefore.sourceID != switchedAfter.sourceID, "actual source switch")
        switchedSource.release(); try wait { switchedResult != nil }
        switch switchedResult! { case .failure(let error): try check((error as? Loader.Failure) == .sourceChanged, "source switch rejected"); case .success: throw AdapterCheckError.failed("obsolete source graph published") }
        try checkClosed(switchedSource.deliveredLeases)

        // Mutation after verified acquisition, before bounded copy: no graph may escape.
        let changed = try fixture(root, "verify-read-mutation"), changedIndex = try descriptor(changed.store)
        let changedSource = RecordingSource(changed.store, gatePath: "data/Paths/NODES13.DAT"), changedLoader = Loader(source: changedSource)
        var changedResult: Result<Loader.Snapshot, Error>?
        changedLoader.validate(local) { changedResult = $0 }; try wait { changedSource.hasHeldLease }
        let changedPath = actualPath(changed, changedIndex, area: 13)
        var damaged = try Data(contentsOf: changedPath); damaged[24] ^= 1; try damaged.write(to: changedPath)
        changedSource.release(); try wait { changedResult != nil }
        switch changedResult! { case .failure: try check(true, "verify/read mutation rejected"); case .success: throw AdapterCheckError.failed("mutated graph published") }
        try checkClosed(changedSource.deliveredLeases)

        // Wrong leaf types are rejected by the real lease API, not opened here.
        let linked = try fixture(root, "symlink"), linkedIndex = try descriptor(linked.store)
        let leaf = actualPath(linked, linkedIndex, area: 13), external = linked.folder.appendingPathComponent("authored-outside.dat")
        try bytes(area: 13, scenario: .valid).write(to: external); try FileManager.default.removeItem(at: leaf)
        try FileManager.default.createSymbolicLink(at: leaf, withDestinationURL: external)
        let linkLoader = Loader(source: linked.store)
        do { let _: Loader.Snapshot = try awaitResult { linkLoader.validate(local, completion: $0) }; throw AdapterCheckError.failed("symlink graph published") }
        catch is AdapterCheckError { throw AdapterCheckError.failed("symlink graph published") }
        catch { try check(true, "actual lease API rejects linked leaf") }
        try check(FileManager.default.fileExists(atPath: external.path), "external authored symlink target preserved")

        let fifo = try fixture(root, "fifo"), fifoIndex = try descriptor(fifo.store)
        let fifoLeaf = actualPath(fifo, fifoIndex, area: 13); try FileManager.default.removeItem(at: fifoLeaf)
        try check(mkfifo(fifoLeaf.path, 0o600) == 0, "authored FIFO fixture created")
        let fifoLoader = Loader(source: fifo.store)
        do { let _: Loader.Snapshot = try awaitResult { fifoLoader.validate(local, completion: $0) }; throw AdapterCheckError.failed("FIFO graph published") }
        catch is AdapterCheckError { throw AdapterCheckError.failed("FIFO graph published") }
        catch { try check(true, "actual lease API rejects FIFO without blocking") }
        try coordinatorLifecycle(root)
        let report: [String: Any] = ["checks": checks, "status": "PASS", "fixtures": "Independently authored synthetic DATs through actual RawStore/RawLease APIs; no original game data",
                                     "scope": "Adapter host tests only; no UI/native runtime acceptance or NPC/traffic behavior"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: root.appendingPathComponent("report.json"))
        print("ORIGINAL_NAVIGATION_ADAPTER_PASS checks=\(checks)")
    }
}
