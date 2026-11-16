// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Main-queue DL lifecycle. A CRC-verified transfer is not an imported model:
/// FinishDownload(184) is gated on the asynchronous importer for every model.
/// Wire/order reference: open.mp CustomModels/models.cpp onPlayerClientInit and
/// Shared/NetCode/custommodels.hpp, checked 2026-11-16. Catalog179 precedes48 on
/// SyncRPC; init sends world+1 then world, including when the catalog is empty.
/// No delay is used to guess catalog completion. Deferred work coalesces a poll
/// batch; an outstanding184 is drained by185 before a newer phase can finish.
final class NativeSAMPArtworkSession {
    typealias Artwork = NativeSAMPArtwork
    typealias ImportCompletion = (Result<Void, Error>) -> Void
    typealias Importer = (Artwork.Model, URL, URL, @escaping ImportCompletion) -> Void
    typealias Sender = (Artwork.RPC) -> Bool

    struct Limits {
        var maximumModels = 4_096
        var maximumRequiredBytes: UInt64 = 512 << 20
        var maximumPendingFiles = 8
        var maximumImports = 2
        var catalogTimeout: TimeInterval = 30
        var urlTimeout: TimeInterval = 20
        var downloadTimeout: TimeInterval = 100
        var importTimeout: TimeInterval = 60
        var acknowledgementTimeout: TimeInterval = 15
        var overallTimeout: TimeInterval = 300
    }
    enum Phase: String { case idle, catalog, downloading, importing, acknowledgement, ready, failed, cancelled }
    enum Failure: Error, CustomStringConvertible {
        case configuration, catalog, limit, wire(String), transport(UInt8), download(String), importer(Int32, String), timeout(String)
        var description: String {
            switch self {
            case .configuration: return "Invalid artwork session limits"
            case .catalog: return "Conflicting artwork catalog"
            case .limit: return "Artwork session resource limit"
            case .wire(let s): return "Invalid artwork RPC: \(s)"
            case .transport(let rpc): return "Artwork RPC \(rpc) could not be queued"
            case .download(let s): return "Artwork download failed: \(s)"
            case .importer(let id, let s): return "Native model \(id) import failed: \(s)"
            case .timeout(let s): return "Artwork timeout: \(s)"
            }
        }
    }
    struct Status {
        let generation: UInt64
        let world: Int32?
        let phase: Phase
        let catalogModels: Int
        let requiredModels: Int
        let requiredFiles: Int
        let verifiedFiles: Int
        let importedModels: Int
        let waitingFiles: Int
        let activeImports: Int
        let requiredBytes: UInt64
        let failure: Failure?
    }
    private struct FileKey: Hashable { let kind: Artwork.Kind; let checksum: UInt32 }
    private struct PendingFile { var deadline: TimeInterval; var downloading: Bool }
    private struct ImportJob { let token: UUID; let deadline: TimeInterval }
    private struct Finish { let generation: UInt64; let deadline: TimeInterval }

    private let cache: NativeSAMPArtworkCache, sendRPC: Sender, importer: Importer
    private let limits: Limits, clock: () -> TimeInterval
    private var timer: DispatchSourceTimer?
    private var artwork = Artwork()
    private var catalog: [UInt32: Artwork.Model] = [:]
    private var customIDs: [Int32: UInt32] = [:], fileSizes: [FileKey: UInt32] = [:]
    private var count: UInt32?
    private var receipts: [Artwork.File: Artwork.Receipt] = [:]
    private var pending: [Artwork.File: PendingFile] = [:], imports: [UInt32: ImportJob] = [:]
    private var imported = Set<UInt32>()
    private var finish: Finish?
    private var phaseStart: TimeInterval?, catalogStart: TimeInterval?
    private var scheduled = false, needsRebuild = true, acknowledged = false, cancelled = false
    private var failure: Failure?
    private var downloadSources:[Artwork.File:URL]=[:]
    func sourceURL(for file:Artwork.File)->URL?{mainQueue();return downloadSources[file]}
    private(set) var generation: UInt64 = 0
    private(set) var connectionGeneration: UInt64 = 0
    private(set) var world: Int32?
    var onStatus: ((Status) -> Void)?
    var onReady: ((UInt64, Int32) -> Void)?
    var onWorld: ((Int32) -> Void)?
    /// True connection resets/cancellation and catalog replacement, not ordinary
    /// world changes. Verified cache files and the owner's GPU cache may survive worlds.
    var onReset: (() -> Void)?
    /// Import owners can invalidate pending GPU registrations on generation change.
    var onGenerationChanged: ((UInt64) -> Void)?

    init(cache: NativeSAMPArtworkCache, limits: Limits = Limits(),
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         automaticallyCheckTimeouts: Bool = true, sendRPC: @escaping Sender, importer: @escaping Importer) throws {
        let times = [limits.catalogTimeout, limits.urlTimeout, limits.downloadTimeout, limits.importTimeout, limits.acknowledgementTimeout, limits.overallTimeout]
        guard (1...4_096).contains(limits.maximumModels), (1...64).contains(limits.maximumPendingFiles),
              (1...16).contains(limits.maximumImports), limits.maximumRequiredBytes > 0,
              times.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 3_600 }) else { throw Failure.configuration }
        self.cache = cache; self.limits = limits; self.clock = clock; self.sendRPC = sendRPC; self.importer = importer
        if automaticallyCheckTimeouts {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in self?.tick() }; self.timer = timer; timer.resume()
        }
    }
    deinit { timer?.cancel(); cache.cancelAll() }
    private func mainQueue() { dispatchPrecondition(condition: .onQueue(.main)) }
    private var catalogComplete: Bool { count.map { catalog.count == Int($0) } ?? true }
    private var requiredModels: [Artwork.Model] {
        guard let world else { return [] }; return catalog.values.filter { $0.applies(to: world) }.sorted { $0.pool < $1.pool }
    }
    var status: Status {
        mainQueue()
        let models = requiredModels, files = Set(models.flatMap { [$0.dff, $0.txd] })
        let phase: Phase
        if cancelled { phase = .cancelled } else if failure != nil { phase = .failed }
        else if acknowledged { phase = .ready } else if finish?.generation == generation { phase = .acknowledgement }
        else if world == nil || !catalogComplete { phase = catalog.isEmpty && world == nil ? .idle : .catalog }
        else if !pending.isEmpty { phase = .downloading } else if !imports.isEmpty { phase = .importing }
        else { phase = .catalog }
        return Status(generation: generation, world: world, phase: phase, catalogModels: catalog.count,
                      requiredModels: models.count, requiredFiles: files.count, verifiedFiles: receipts.count,
                      importedModels: imported.count, waitingFiles: pending.count, activeImports: imports.count,
                      requiredBytes: files.reduce(0) { $0 + UInt64($1.size) }, failure: failure)
    }
    private func publish() { onStatus?(status) }

    /// Bind this returned token to callbacks from the newly connected transport.
    @discardableResult func reset() -> UInt64 {
        mainQueue(); connectionGeneration &+= 1; count = nil; catalog.removeAll(); customIDs.removeAll(); fileSizes.removeAll()
        world = nil; finish = nil; phaseStart = nil; catalogStart = nil; failure = nil; cancelled = false
        invalidate(); onReset?(); publish(); return connectionGeneration
    }
    func cancel() { mainQueue(); cancelled = true; finish = nil; invalidate(); onReset?(); publish() }
    private func invalidate() {
        generation &+= 1; cache.cancelAll(); pending.removeAll(); imports.removeAll(); receipts.removeAll(); imported.removeAll();downloadSources.removeAll()
        acknowledged = false; needsRebuild = true; artwork = Artwork(); onGenerationChanged?(generation)
    }
    private func fail(_ reason: Failure) {
        guard failure == nil, !cancelled else { return }; failure = reason
        cache.cancelAll(); pending.removeAll(); imports.removeAll(); publish()
    }

    /// Returns false for unrelated RPCs. A stale transport token is consumed but ignored.
    @discardableResult func receive(id: UInt8, data: Data, connection: UInt64? = nil) -> Bool {
        mainQueue(); guard [179, 48, 183, 185].contains(id) else { return false }
        if let connection, connection != connectionGeneration { return true }
        guard !cancelled, failure == nil else { return true }
        do {
            switch id {
            case 179: try receiveModel(data)
            case 48:
                guard data.count == 4 else { throw Failure.wire("world payload") }
                let b = Array(data), value = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
                let next = Int32(bitPattern: value)
                if world != next || acknowledged { world = next; phaseStart = clock(); invalidate(); onWorld?(next) }
                else if phaseStart == nil { phaseStart = clock() }
            case 183:
                guard !needsRebuild else { return true }
                do {
                    let download = try artwork.receiveURL(data)
                    guard var request = pending[download.file], !request.downloading else { return true }
                    request.downloading = true; request.deadline = clock() + limits.downloadTimeout; pending[download.file] = request
                    downloadSources[download.file]=download.url
                    let epoch = generation
                    cache.fetch(download) { [weak self] result in
                        guard let self, epoch == self.generation, self.failure == nil, !self.cancelled else { return }
                        do {
                            let receipt = try result.get(); try self.artwork.completed(receipt)
                            self.receipts[receipt.file] = receipt; self.pending.removeValue(forKey: receipt.file); self.schedule()
                        } catch { self.fail(.download(String(describing: error))) }
                    }
                } catch Artwork.Failure.unsolicitedURL { return true } // Late/duplicate URL from a retired phase.
            case 185:
                guard data.isEmpty else { throw Failure.wire("completion payload") }
                guard let sent = finish else { return true }
                finish = nil
                if sent.generation == generation {
                    try artwork.receiveCompleted(data); acknowledged = true; publish()
                    if let world { onReady?(generation, world) }
                }
            default: break
            }
            schedule()
        } catch let error as Failure { fail(error) }
        catch { fail(.wire(String(describing: error))) }
        return true
    }
    private func receiveModel(_ data: Data) throws {
        let model = try Artwork.Model.decode(data)
        guard model.count <= limits.maximumModels else { throw Failure.limit }
        if let old = catalog[model.pool], canonical(old, count: model.count) == model { return }
        var newCatalog = count == nil
        if let count {
            let growth = model.count > count && model.pool >= count
            newCatalog = growth
            let replacement = model.pool == 0 && (model.count != count || catalog[0] != nil)
            if !growth && model.count != count || catalog[model.pool] != nil {
                guard replacement else { throw Failure.catalog }
                catalog.removeAll(); customIDs.removeAll(); fileSizes.removeAll(); self.count = nil
                newCatalog = true; onReset?()
            }
        }
        if let count, model.count != count, !(model.count > count && model.pool >= count) { throw Failure.catalog }
        if let pool = customIDs[model.customID], pool != model.pool { throw Failure.catalog }
        for file in [model.dff, model.txd] {
            let key = FileKey(kind: file.kind, checksum: file.checksum)
            if let size = fileSizes[key], size != file.size { throw Failure.catalog }; fileSizes[key] = file.size
        }
        if world != nil, !needsRebuild { invalidate(); phaseStart = clock() }
        count = model.count; catalog[model.pool] = model; customIDs[model.customID] = model.pool
        if newCatalog || catalogStart == nil { catalogStart = clock() }
    }
    private func canonical(_ m: Artwork.Model, count: UInt32) -> Artwork.Model {
        Artwork.Model(pool: m.pool, count: count, type: m.type, world: m.world, baseID: m.baseID, customID: m.customID,
                      dff: m.dff, txd: m.txd, timeOn: m.timeOn, timeOff: m.timeOff)
    }
    private func wire(_ m: Artwork.Model) -> Data {
        var out = Data()
        func integer(_ n: UInt32) { var n = n.littleEndian; withUnsafeBytes(of: &n) { out.append(contentsOf: $0) } }
        integer(m.pool); integer(count!); out.append(m.type)
        for n in [m.world, m.baseID, m.customID] { integer(UInt32(bitPattern: n)) }
        for n in [m.dff.checksum, m.txd.checksum, m.dff.size, m.txd.size] { integer(n) }
        out.append(contentsOf: [m.timeOn, m.timeOff]); return out
    }
    private func schedule() {
        guard !scheduled else { return }; scheduled = true
        DispatchQueue.main.async { [weak self] in guard let self else { return }; self.scheduled = false; self.advance() }
    }
    /// May be called after a transport batch. No wall-clock quiet-period assumption.
    func advance() {
        mainQueue(); guard failure == nil, !cancelled, !acknowledged, let world, catalogComplete else { publish(); return }
        do {
            if needsRebuild {
                let files = Set(requiredModels.flatMap { [$0.dff, $0.txd] })
                guard files.reduce(UInt64(0), { $0 + UInt64($1.size) }) <= limits.maximumRequiredBytes else { throw Failure.limit }
                for model in catalog.values.sorted(by: { $0.pool < $1.pool }) { try artwork.receiveModel(wire(model)) }
                artwork.begin(world: world); needsRebuild = false
            }
            let free = limits.maximumPendingFiles - pending.count
            for request in artwork.requests(limit: free) {
                let kind: Artwork.Kind = request.id == 181 ? .dff : .txd
                let b = Array(request.payload), crc = UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
                guard let file = artwork.requiredFiles.first(where: { $0.kind == kind && $0.checksum == crc }) else { throw Failure.catalog }
                pending[file] = PendingFile(deadline: clock() + limits.urlTimeout, downloading: false)
                guard sendRPC(request) else { throw Failure.transport(request.id) }
            }
            for model in requiredModels where imports.count < limits.maximumImports && !imported.contains(model.pool) && imports[model.pool] == nil {
                guard let dff = receipts[model.dff], let txd = receipts[model.txd] else { continue }
                let job = ImportJob(token: UUID(), deadline: clock() + limits.importTimeout), epoch = generation
                imports[model.pool] = job
                importer(model, dff.url, txd.url) { [weak self] result in DispatchQueue.main.async {
                    guard let self, self.generation == epoch, !self.cancelled, self.failure == nil,
                          self.imports[model.pool]?.token == job.token else { return }
                    self.imports.removeValue(forKey: model.pool)
                    switch result {
                    case .success: self.imported.insert(model.pool); self.schedule()
                    case .failure(let error): self.fail(.importer(model.customID, String(describing: error)))
                    }
                } }
            }
            if imported.count == requiredModels.count, pending.isEmpty, imports.isEmpty, finish == nil {
                if let request = try artwork.finishRequest() {
                    finish = Finish(generation: generation, deadline: clock() + limits.acknowledgementTimeout)
                    guard sendRPC(request) else { throw Failure.transport(request.id) }
                }
            }
            publish()
        } catch let error as Failure { fail(error) }
        catch { fail(.wire(String(describing: error))) }
    }
    func tick() {
        mainQueue(); guard failure == nil, !cancelled, !acknowledged else { return }
        let now = clock()
        if let finish, now >= finish.deadline { fail(.timeout("server acknowledgement")); return }
        if let start = phaseStart, now - start >= limits.overallTimeout { fail(.timeout("overall phase")); return }
        if !catalogComplete, let start = catalogStart, now - start >= limits.catalogTimeout { fail(.timeout("catalog")); return }
        if world == nil, let start = catalogStart, now - start >= limits.catalogTimeout { fail(.timeout("world boundary")); return }
        if let file = pending.values.first(where: { now >= $0.deadline }) { fail(.timeout(file.downloading ? "download" : "download URL")); return }
        if imports.values.contains(where: { now >= $0.deadline }) { fail(.timeout("native importer")); return }
    }
}
