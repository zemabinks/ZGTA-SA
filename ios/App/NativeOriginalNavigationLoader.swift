// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit

/// Exact existing RawStore signatures. Implementations must preserve the
/// store's main-queue delivery/fence contract; this is also an actual-store
/// decorator seam for authored cancellation/source-change tests.
protocol NativeOriginalNavigationSource: AnyObject {
    @discardableResult func readReceiptDescriptor(expectedSourceID: String?, expectedContentID: String?,
        completion: @escaping (Result<NativeRawResourceStore.ReceiptDescriptor, Error>) -> Void) -> NativeRawResourceLease.Request
    @discardableResult func acquireLocalFile(path: String, matching: NativeRawResourceStore.ReceiptDescriptor,
        maximumBytes: Int64, verificationProgress: ((NativeRawResourceLease.VerificationProgress) -> Void)?,
        completion: @escaping (Result<NativeRawResourceLease, Error>) -> Void) -> NativeRawResourceLease.Request
}
extension NativeRawResourceStore: NativeOriginalNavigationSource {}

final class NativeOriginalNavigationLoader: @unchecked Sendable {
    typealias Area = NativeOriginalPathArea
    typealias Graph = NativeOriginalPathGraph
    typealias Descriptor = NativeRawResourceStore.ReceiptDescriptor
    typealias Resource = NativeRawResourceStore.Resource

    enum Failure: Error, LocalizedError, Equatable {
        case busy, cancelled, sourceChanged, storageBusy, timeLimit, queryBudget
        case missingAreas([UInt16]), missingLinkedArea(UInt16)
        case unsupportedSelection, unsupportedArea(UInt16, String), invalidReference(UInt16, UInt16)
        case limit(String), invalidRequest, noNearbyNode(String), noRoute(String), resource(String)
        var errorDescription: String? {
            switch self {
            case .busy: return "An original navigation check is already running."
            case .cancelled: return "Original navigation check cancelled."
            case .sourceChanged: return "The selected original source changed. Run the navigation check again."
            case .storageBusy: return "Original resource storage is busy. Retry when its current operation finishes."
            case .timeLimit: return "The original navigation check reached its time limit. Retry when the device is less busy."
            case .queryBudget: return "This navigation query exceeds the supported search limit."
            case .missingAreas(let areas): return "Original navigation areas are missing: " + areas.map(String.init).joined(separator: ", ")
            case .missingLinkedArea(let area): return "The loaded navigation links to missing area \(area)."
            case .unsupportedSelection: return "This original resource selection is not supported by the navigation reader."
            case .unsupportedArea(let area, _): return "Original navigation area \(area) has an unsupported or malformed format."
            case .invalidReference(let area, let node): return "Original navigation references an invalid node \(area):\(node)."
            case .limit: return "The original navigation data exceeds this reader's supported resource limits."
            case .invalidRequest: return "The navigation check request is outside the supported area or query limits."
            case .noNearbyNode(let kind): return "No nearby original \(kind) path was found for the check."
            case .noRoute(let kind): return "Original navigation loaded, but the \(kind) route check could not find a route."
            case .resource(let detail): return detail
            }
        }
    }
    struct Limits: Sendable {
        var maximumTotalBytes: Int64 = 8 * 1_048_576
        var maximumNodes = 100_000
        var maximumLinks = 250_000
        var maximumNaviNodes = 65_536
        var maximumNearestScans = 100_000
        var maximumExpandedNodes = 4096
        var maximumReturnedNodes = 2048
        var maximumSeconds: Double = 30
        fileprivate var valid: Bool {
            (Int64(20)...Int64(16 * 1_048_576)).contains(maximumTotalBytes) && (1...150_000).contains(maximumNodes) &&
            (1...300_000).contains(maximumLinks) && (1...65_536).contains(maximumNaviNodes) &&
            (1...100_000).contains(maximumNearestScans) && (1...50_000).contains(maximumExpandedNodes) &&
            (1...50_000).contains(maximumReturnedNodes) && maximumSeconds.isFinite && maximumSeconds > 0 && maximumSeconds <= 60
        }
    }
    struct Probe: Sendable {
        let kind: Area.Kind
        let start: SIMD3<Double>
        let goal: SIMD3<Double>
        let maximumDistance: Double
        var kindName: String { kind == .ped ? "pedestrian" : "vehicle" }
    }
    struct Request: Sendable {
        let areas: [UInt16]
        let probes: [Probe]
        // Explicit diagnostics around this project's ordinary exterior spawn.
        // No actors, missions, network state, or startup hooks are involved.
        static var exteriorDiagnostic: Request {
            .init(areas: Array(UInt16(0)...UInt16(63)), probes: [
                .init(kind: .ped, start: SIMD3(1480, -1738, 13), goal: SIMD3(1525, -1675, 13), maximumDistance: 100),
                .init(kind: .vehicle, start: SIMD3(1480, -1738, 13), goal: SIMD3(1525, -1675, 13), maximumDistance: 100)
            ])
        }
    }
    struct Identity: Equatable, Sendable {
        let sourceID: String, contentID: String, generationID: String, selectionIdentity: String
        init(_ descriptor: Descriptor) {
            sourceID = descriptor.sourceID; contentID = descriptor.contentID
            generationID = descriptor.generationID; selectionIdentity = descriptor.selectionIdentity
        }
        func matches(_ binding: NativeRawResourceLease.Binding) -> Bool {
            sourceID == binding.sourceID && contentID == binding.contentID && generationID == binding.generationID && selectionIdentity == binding.selectionIdentity
        }
    }
    struct VerifiedArea: Sendable {
        let area: UInt16, path: String, bytes: Int64, sha256: String
    }
    struct Summary: Sendable {
        let areas: Int, bytes: Int64, vehicleNodes: Int, pedNodes: Int, naviNodes: Int, links: Int
    }
    struct ProbeResult: Sendable {
        let kind: Area.Kind
        let nearestStart: Graph.Nearest
        let nearestGoal: Graph.Nearest
        let route: Graph.Route
    }
    struct Snapshot: Sendable {
        let identity: Identity
        let graph: Graph
        let files: [VerifiedArea]
        let summary: Summary
        let probes: [ProbeResult]
        // Immutable queried data only. No file handles, requests or leases are
        // retained. Its identity remains historical after a later source swap;
        // obtaining a current snapshot requires another explicit validation.
    }
    struct Progress: Sendable {
        let phase: String
        let completedAreas: Int, totalAreas: Int
        let completedBytes: Int64, totalBytes: Int64
        let currentPath: String?
    }
    final class Operation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false, delivered = false
        private var sequence: UInt64 = 0, pending: UInt64?
        private var inFlight: NativeRawResourceLease.Request?
        func cancel() {
            lock.lock(); if !delivered { cancelled = true }; let request = inFlight; lock.unlock()
            request?.cancel()
        }
        fileprivate var stopped: Bool { lock.lock(); defer { lock.unlock() }; return cancelled || delivered }
        fileprivate func check() throws {
            lock.lock(); defer { lock.unlock() }
            if cancelled || delivered { throw Failure.cancelled }
        }
        fileprivate func beginRequest() throws -> UInt64 {
            lock.lock(); defer { lock.unlock() }
            guard !cancelled, !delivered else { throw Failure.cancelled }
            guard pending == nil else { throw Failure.busy }
            sequence &+= 1; pending = sequence; return sequence
        }
        fileprivate func attach(_ request: NativeRawResourceLease.Request, ticket: UInt64) {
            lock.lock(); let keep = !cancelled && !delivered && pending == ticket
            if keep { inFlight = request }; lock.unlock()
            if !keep { request.cancel() }
        }
        fileprivate func completed(_ ticket: UInt64) {
            lock.lock(); if pending == ticket { pending = nil; inFlight = nil }; lock.unlock()
        }
        fileprivate func claimDelivery() -> Bool? {
            lock.lock(); defer { lock.unlock() }
            guard !delivered else { return nil }
            delivered = true; inFlight = nil; pending = nil; return cancelled
        }
    }

    private let source: NativeOriginalNavigationSource
    private let limits: Limits
    private let now: @Sendable () -> TimeInterval
    private let worker = DispatchQueue(label: "org.zgtasa.original-navigation", qos: .utility)
    private let lock = NSLock()
    private var active: UUID?
    init(source: NativeOriginalNavigationSource, limits: Limits = Limits(),
         now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.source = source; self.limits = limits; self.now = now
    }

    /// Explicit action only. Main-queue completion/progress, one admitted job,
    /// one outstanding verified-file acquisition and a serial utility decoder.
    @discardableResult func validate(_ request: Request = .exteriorDiagnostic,
        progress: @escaping (Progress) -> Void = { _ in },
        completion: @escaping (Result<Snapshot, Error>) -> Void) -> Operation {
        let operation = Operation(), id = UUID()
        lock.lock(); let admitted = active == nil; if admitted { active = id }; lock.unlock()
        guard admitted else {
            DispatchQueue.main.async { if let cancelled = operation.claimDelivery() { completion(.failure(cancelled ? Failure.cancelled : Failure.busy)) } }
            return operation
        }
        let run = Run(owner: self, id: id, operation: operation, request: request, progress: progress, completion: completion)
        worker.async { run.start() }
        return operation
    }
    private func release(_ id: UUID) { lock.lock(); if active == id { active = nil }; lock.unlock() }
    private final class Transfer<Value>: @unchecked Sendable { let value: Value; init(_ value: Value) { self.value = value } }

    /// All mutable parse state belongs to owner.worker. Only final completion
    /// and the final RawStore delivery fence run on main; Operation has locks.
    private final class Run: @unchecked Sendable {
        let owner: NativeOriginalNavigationLoader, id: UUID, operation: Operation, request: Request
        let progress: (Progress) -> Void, completion: (Result<Snapshot, Error>) -> Void
        let started: TimeInterval
        var descriptor: Descriptor?, selected: [(UInt16, Resource)] = [], areas: [Area] = [], files: [VerifiedArea] = []
        var index = 0, totalBytes: Int64 = 0, decodedBytes: Int64 = 0, nodeCount = 0, linkCount = 0, naviCount = 0
        init(owner: NativeOriginalNavigationLoader, id: UUID, operation: Operation, request: Request,
             progress: @escaping (Progress) -> Void, completion: @escaping (Result<Snapshot, Error>) -> Void) {
            self.owner = owner; self.id = id; self.operation = operation; self.request = request
            self.progress = progress; self.completion = completion; started = owner.now()
        }
        func checkpoint() throws {
            try operation.check()
            guard owner.now() - started <= owner.limits.maximumSeconds else { throw Failure.timeLimit }
        }
        func emit(_ phase: String, path: String? = nil) {
            let value = Progress(phase: phase, completedAreas: index, totalAreas: selected.isEmpty ? request.areas.count : selected.count,
                                 completedBytes: decodedBytes, totalBytes: totalBytes, currentPath: path)
            DispatchQueue.main.async { if !self.operation.stopped { self.progress(value) } }
        }
        func start() {
            do {
                try checkpoint()
                let requested = request.areas
                guard owner.limits.valid, !requested.isEmpty, requested.count <= 64,
                      Set(requested).count == requested.count, requested.allSatisfy({ $0 < 64 }),
                      (1...2).contains(request.probes.count), request.probes.allSatisfy({
                          $0.maximumDistance.isFinite && $0.maximumDistance > 0 && $0.maximumDistance <= 1000 &&
                          $0.start.x.isFinite && $0.start.y.isFinite && $0.start.z.isFinite &&
                          $0.goal.x.isFinite && $0.goal.y.isFinite && $0.goal.z.isFinite
                      }) else { throw Failure.invalidRequest }
                emit("Checking original navigation source")
                let ticket = try operation.beginRequest()
                let pending = owner.source.readReceiptDescriptor(expectedSourceID: nil, expectedContentID: nil) { result in
                    self.operation.completed(ticket)
                    let value = Transfer(result)
                    self.owner.worker.async { self.acceptDescriptor(value.value) }
                }
                operation.attach(pending, ticket: ticket)
            } catch { fail(error) }
        }
        func acceptDescriptor(_ result: Result<Descriptor, Error>) {
            do {
                try checkpoint()
                let descriptor = try result.get()
                guard descriptor.selectionIdentity == "zgta-original-raw-selection-v1" else { throw Failure.unsupportedSelection }
                var missing: [UInt16] = []
                for area in request.areas.sorted() {
                    let path = "data/paths/nodes\(area).dat"
                    guard let resource = descriptor.resourcesByCasefoldedPath[path] else { missing.append(area); continue }
                    guard resource.bytes >= 20, resource.bytes <= Int64(Area.maximumBytes) else { throw Failure.unsupportedArea(area, "byte limit") }
                    totalBytes += resource.bytes
                    guard totalBytes <= owner.limits.maximumTotalBytes else { throw Failure.limit("total bytes") }
                    selected.append((area, resource))
                }
                guard missing.isEmpty else { throw Failure.missingAreas(missing) }
                self.descriptor = descriptor
                acquireNext()
            } catch { fail(error) }
        }
        func acquireNext() {
            do {
                try checkpoint()
                guard let descriptor else { throw Failure.invalidRequest }
                if index == selected.count { try validateGraph(descriptor); return }
                let item = selected[index]
                emit("Reading original navigation", path: item.1.path)
                let ticket = try operation.beginRequest()
                let pending = owner.source.acquireLocalFile(path: item.1.path, matching: descriptor,
                    maximumBytes: Int64(Area.maximumBytes), verificationProgress: nil) { result in
                    self.operation.completed(ticket)
                    let value = Transfer(result)
                    self.owner.worker.async { self.acceptArea(value.value, item: item, descriptor: descriptor) }
                }
                operation.attach(pending, ticket: ticket)
            } catch { fail(error) }
        }
        func copyAndClose(_ lease: NativeRawResourceLease, item: (UInt16, Resource), descriptor: Descriptor) throws -> Data {
            defer { lease.close() }
            try checkpoint()
            let binding = lease.binding
            guard Identity(descriptor).matches(binding), binding.path == item.1.path,
                  binding.bytes == item.1.bytes, binding.sha256 == item.1.sha256 else { throw Failure.sourceChanged }
            let data = try lease.read(atOffset: 0, maximumBytes: Int(binding.bytes))
            lease.close() // The copied Data is independent; release the pin now.
            try checkpoint()
            guard data.count == Int(binding.bytes) else { throw Failure.unsupportedArea(item.0, "short verified read") }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == item.1.sha256 else { throw Failure.resource("The copied original navigation file does not match its saved checksum. Verify or repair the saved raw resources.") }
            return data
        }
        func acceptArea(_ result: Result<NativeRawResourceLease, Error>, item: (UInt16, Resource), descriptor: Descriptor) {
            do {
                // Even cancellation/error takes ownership through the helper,
                // whose defer closes a successfully delivered lease at once.
                let data = try copyAndClose(result.get(), item: item, descriptor: descriptor)
                try checkpoint()
                let area: Area
                do { area = try Area(data: data, expectedArea: item.0) }
                catch { throw Failure.unsupportedArea(item.0, String(describing: error)) }
                try checkpoint()
                let newNodes = nodeCount + area.nodes.count, newLinks = linkCount + area.links.count, newNavi = naviCount + area.naviNodes.count
                guard newNodes <= owner.limits.maximumNodes, newLinks <= owner.limits.maximumLinks,
                      newNavi <= owner.limits.maximumNaviNodes else { throw Failure.limit("decoded records") }
                nodeCount = newNodes; linkCount = newLinks; naviCount = newNavi
                areas.append(area)
                files.append(VerifiedArea(area: item.0, path: item.1.path, bytes: item.1.bytes, sha256: item.1.sha256))
                decodedBytes += item.1.bytes; index += 1
                emit("Decoded original navigation", path: item.1.path)
                acquireNext()
            } catch { fail(error) }
        }
        func validateGraph(_ descriptor: Descriptor) throws {
            try checkpoint(); emit("Checking original navigation links")
            let graph = try Graph(areas: areas)
            var visited = 0
            for area in areas {
                for node in area.nodes {
                    if visited % 128 == 0 { try checkpoint() }; visited += 1
                    for edge in try graph.resolvedLinks(from: node.address) {
                        if let navi = edge.navi {
                            let target = try graph.node(navi.target)
                            guard target.kind == .vehicle else { throw Failure.invalidReference(navi.target.area, navi.target.node) }
                        }
                    }
                }
            }
            emit("Running original navigation queries")
            var queries: [ProbeResult] = []
            for probe in request.probes {
                try checkpoint()
                guard let start = try graph.nearest(to: probe.start, kind: probe.kind, maximumDistance: probe.maximumDistance,
                                                     maximumScannedNodes: owner.limits.maximumNearestScans),
                      let goal = try graph.nearest(to: probe.goal, kind: probe.kind, maximumDistance: probe.maximumDistance,
                                                    maximumScannedNodes: owner.limits.maximumNearestScans) else { throw Failure.noNearbyNode(probe.kindName) }
                guard let route = try graph.route(from: start.address, to: goal.address, kind: probe.kind,
                                                  maximumExpandedNodes: owner.limits.maximumExpandedNodes,
                                                  maximumReturnedNodes: owner.limits.maximumReturnedNodes) else { throw Failure.noRoute(probe.kindName) }
                queries.append(ProbeResult(kind: probe.kind, nearestStart: start, nearestGoal: goal, route: route))
            }
            try checkpoint()
            let snapshot = Snapshot(identity: Identity(descriptor), graph: graph, files: files,
                                    summary: Summary(areas: areas.count, bytes: decodedBytes,
                                                     vehicleNodes: areas.reduce(0) { $0 + $1.vehicleCount },
                                                     pedNodes: areas.reduce(0) { $0 + $1.pedCount }, naviNodes: naviCount, links: linkCount), probes: queries)
            // Parsed graph owns value arrays; no lease has survived a read.
            areas.removeAll(); files.removeAll()
            emit("Confirming original navigation source")
            let value = Transfer(snapshot), ticket = try operation.beginRequest()
            let pending = owner.source.readReceiptDescriptor(expectedSourceID: descriptor.sourceID, expectedContentID: descriptor.contentID) { result in
                self.operation.completed(ticket)
                // Keep this on the store's main-queue delivery fence. Do not
                // bounce back through a worker and open a source-change gap.
                do {
                    try self.checkpoint()
                    let current = try result.get()
                    guard Identity(current) == value.value.identity else { throw Failure.sourceChanged }
                    self.finishOnMain(.success(value.value))
                } catch { self.finishOnMain(.failure(Self.mapped(error))) }
            }
            operation.attach(pending, ticket: ticket)
        }
        static func mapped(_ error: Error) -> Error {
            if let own = error as? Failure { return own }
            if let raw = error as? NativeRawResourceLease.Failure {
                switch raw {
                case .cancelled: return Failure.cancelled
                case .stale: return Failure.sourceChanged
                case .busy: return Failure.storageBusy
                default: return Failure.resource(raw.localizedDescription)
                }
            }
            if let graph = error as? NativeOriginalPathFailure {
                switch graph {
                case .unloadedArea(let area): return Failure.missingLinkedArea(area)
                case .invalidAddress(let area, let node): return Failure.invalidReference(area, node)
                case .queryBudget: return Failure.queryBudget
                case .kindMismatch: return Failure.resource("Original navigation mixes incompatible pedestrian and vehicle links.")
                case .malformed(let detail): return Failure.resource("Original navigation links are malformed: " + detail)
                }
            }
            return error
        }
        func fail(_ error: Error) {
            areas.removeAll(); files.removeAll(); selected.removeAll(); descriptor = nil
            let result = Transfer<Result<Snapshot, Error>>(.failure(Self.mapped(error)))
            DispatchQueue.main.async { self.finishOnMain(result.value) }
        }
        func finishOnMain(_ result: Result<Snapshot, Error>) {
            precondition(Thread.isMainThread)
            guard let cancelled = operation.claimDelivery() else { return }
            owner.release(id)
            completion(cancelled ? .failure(Failure.cancelled) : result)
        }
    }
}
