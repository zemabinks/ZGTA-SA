// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
typealias A = NativeSAMPArtwork
typealias S = NativeSAMPArtworkSession
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ reason: String) {
    checks += 1; if !value() { fatalError("ArtworkSession: \(reason)") }
}
func u32(_ value: UInt32) -> Data { var v = value.littleEndian; return withUnsafeBytes(of: &v) { Data($0) } }
func wire(_ pool: UInt32 = 0, count: UInt32 = 1, id: Int32 = -1000, world: Int32 = -1, dff: A.File, txd: A.File) -> Data {
    var data=u32(pool);data+=u32(count);data.append(2)
    for n in [UInt32(bitPattern:world),19379,UInt32(bitPattern:id),dff.checksum,txd.checksum,dff.size,txd.size]{data+=u32(n)}
    data.append(contentsOf:[0,0]);return data
}
func url(_ file: A.File, _ url: URL) -> Data { Data([6,file.kind.rawValue]) + u32(file.checksum) + Data([UInt8(url.absoluteString.utf8.count)]) + Data(url.absoluteString.utf8) }
@MainActor func wait(_ condition: @escaping () -> Bool, _ reason: String) async {
    let until = ProcessInfo.processInfo.systemUptime + 10
    while !condition() {
        check(ProcessInfo.processInfo.systemUptime < until,"timeout \(reason)")
        try! await Task.sleep(nanoseconds: 5_000_000)
    }
}
@MainActor final class Harness {
    struct Imported { let id: Int32; let completion: S.ImportCompletion }
    var session: S!
    let dff: A.File, txd: A.File
    let base: URL
    var sent: [A.RPC] = [], imports: [Imported] = []
    var now: TimeInterval = 0, resets = 0, worlds: [Int32] = [], ready: [(UInt64,Int32)] = []
    var autoURLs = true, refused: UInt8?, forcedURL: String?, dffEndpoint = "dff"
    var cpuImports = 0
    init(root: URL, base: URL, dffData: Data, txdData: Data, limits: S.Limits = S.Limits()) throws {
        self.base = base
        dff = A.File(kind:.dff,checksum:A.CRC32.checksum(dffData),size:UInt32(dffData.count))
        txd = A.File(kind:.txd,checksum:A.CRC32.checksum(txdData),size:UInt32(txdData.count))
        let cache = try NativeSAMPArtworkCache(root:root,namespace:UUID().uuidString)
        session = try S(cache:cache,limits:limits,clock:{ [weak self] in self?.now ?? 0 },automaticallyCheckTimeouts:false,sendRPC:{ [weak self] rpc in
            guard let self else { return false }; self.sent.append(rpc)
            if self.refused == rpc.id { return false }
            if self.autoURLs && [181,182].contains(rpc.id) {
                let file = rpc.id == 181 ? self.dff:self.txd
                let path = self.forcedURL ?? (rpc.id == 181 ? self.dffEndpoint:"txd")
                let packet = url(file,self.base.appendingPathComponent(path))
                DispatchQueue.main.async { self.session.receive(id:183,data:packet) }
            }
            return true
        },importer:{ [weak self] model,dffURL,txdURL,completion in
            guard let self else { return }
            DispatchQueue.global().async {
                do {
                    let dff = try NativeRenderWareDFF.decode(Data(contentsOf:dffURL))
                    let txd = try NativeRenderWareTXD.decode(Data(contentsOf:txdURL))
                    let plan = try NativeRenderWareModel.prepare(dff:dff,txd:txd)
                    guard plan.isComplete,plan.draws.count == 1,plan.textures.count == 1 else { throw S.Failure.importer(model.customID,"actual generated fixture did not load completely") }
                    DispatchQueue.main.async { self.cpuImports += 1; self.imports.append(Imported(id:model.customID,completion:completion)) }
                } catch { completion(.failure(error)) }
            }
        })
        session.onReset = { [weak self] in self?.resets += 1 }
        session.onWorld = { [weak self] in self?.worlds.append($0) }
        session.onReady = { [weak self] in self?.ready.append(($0,$1)) }
    }
    func catalog(_ pool: UInt32 = 0,count: UInt32 = 1,id: Int32 = -1000,world: Int32 = -1) { session.receive(id:179,data:wire(pool,count:count,id:id,world:world,dff:dff,txd:txd)) }
    func world(_ value: Int32) { session.receive(id:48,data:u32(UInt32(bitPattern:value))) }
    var finishes: Int { sent.filter{$0.id==184}.count }
    func release(_ index: Int) { imports[index].completion(.success(())) }
}
@MainActor func tests() async throws {
    let folder = URL(fileURLWithPath:CommandLine.arguments[1]),base = URL(string:CommandLine.arguments[2])!
    let dff = try Data(contentsOf:folder.appendingPathComponent("fixture.dff")),txd = try Data(contentsOf:folder.appendingPathComponent("fixture.txd"))
    func h(_ limits: S.Limits = S.Limits()) throws -> Harness { try Harness(root:folder.appendingPathComponent("cache"),base:base,dffData:dff,txdData:txd,limits:limits) }
    let primary = try h(); primary.catalog(); primary.world(1); primary.world(0)
    await wait({primary.imports.count==1},"real HTTP, CRC and CPU native import")
    check(primary.cpuImports==1 && primary.session.status.verifiedFiles==2,"verified real pair before importer completion")
    check(primary.finishes==0,"no184 before actual asynchronous importer callback")
    primary.release(0); primary.release(0)
    await wait({primary.finishes==1},"import callback gate")
    check(primary.session.status.phase == .acknowledgement && primary.ready.isEmpty,"185 acknowledgement gate")
    primary.session.receive(id:185,data:Data());primary.session.receive(id:185,data:Data())
    check(primary.ready.count==1 && primary.session.status.phase == .ready && primary.session.world==0,"one ready event after185")
    check(primary.worlds == [1,0] && primary.resets==0,"world events preserve renderer/cache")

    let empty = try h(); empty.world(1);empty.world(0)
    await wait({empty.finishes==1},"empty catalog boundary")
    check(empty.sent.map(\.id)==[184] && empty.imports.isEmpty,"zero catalog needs no invented179 or importer")
    empty.world(2);empty.session.advance();check(empty.finishes==1,"old184 serialized acrossworlds")
    empty.session.receive(id:185,data:Data());check(empty.ready.isEmpty,"retired185 cannot ready newworld")
    await wait({empty.finishes==2},"newworld finish after retired ack")
    empty.session.receive(id:185,data:Data());check(empty.ready.count==1 && empty.ready[0].1==2,"current185 assignedcorrectly")

    let partial = try h();partial.catalog(count:2);partial.world(0);partial.session.advance()
    check(partial.sent.isEmpty,"partialcatalog blocks downloads/finish")
    partial.catalog(1,count:2,id:-1001);partial.catalog(1,count:2,id:-1001)
    await wait({partial.imports.count==2},"shared files and two importer jobs")
    check(partial.sent.filter{[181,182].contains($0.id)}.count==2,"shared pair deduplicated")
    partial.release(0);await Task.yield();check(partial.finishes==0,"every model callback required")
    partial.release(1);await wait({partial.finishes==1},"both models imported")

    let stale = try h();stale.catalog();stale.world(0)
    await wait({stale.imports.count==1},"first world import held")
    let retired = stale.session.generation;stale.world(9)
    await wait({stale.imports.count==2},"newworld cache hit/import")
    stale.release(0);await Task.yield();check(stale.finishes==0 && stale.session.generation != retired,"stale import callback ignored")
    stale.release(1);await wait({stale.finishes==1},"fresh generation importer")
    check(stale.resets==0,"world change does not reset resident resources")
    let oldConnection=stale.session.connectionGeneration;stale.session.reset()
    stale.session.receive(id:179,data:wire(dff:stale.dff,txd:stale.txd),connection:oldConnection)
    check(stale.session.status.catalogModels==0 && stale.resets==1,"reconnect rejects stale transport epoch")
    stale.release(1);await Task.yield();check(stale.session.status.phase == .idle,"postreset import callback ignored")

    let growth = try h();growth.catalog();growth.world(0)
    await wait({growth.imports.count==1},"pregrowth import")
    growth.catalog(1,count:2,id:-1001)
    await wait({growth.imports.count==3},"growth retains prior catalog with normalized Count")
    growth.release(0);await Task.yield();check(growth.finishes==0,"pregrowth importer retired")
    growth.release(1);growth.release(2);await wait({growth.finishes==1},"growth complete")
    check(growth.resets==0 && growth.session.status.catalogModels==2,"growth is not replacement reset")
    growth.session.receive(id:185,data:Data());growth.catalog(count:1,id:-2000)
    await wait({growth.imports.count==4},"replacement import")
    check(growth.resets==1 && growth.session.status.catalogModels==1,"pool0 replacement resets registry")
    growth.release(3);await wait({growth.finishes==2},"replacement actual import")

    var bounded = S.Limits();bounded.maximumPendingFiles=1;bounded.maximumImports=1
    let serial = try h(bounded);serial.catalog();serial.world(0)
    await wait({serial.imports.count==1},"bounded sequential files")
    check(serial.session.status.failure==nil,"one pending-file limit progresses")
    serial.release(0);await wait({serial.finishes==1},"boundedimportcompletion")
    var tiny = S.Limits();tiny.maximumRequiredBytes=1
    let quota = try h(tiny);quota.catalog();quota.world(0);quota.session.advance()
    check(quota.session.status.phase == .failed && quota.sent.isEmpty,"requiredbyte budget before requests")
    let urlTimeout = try h();urlTimeout.autoURLs=false;urlTimeout.catalog();urlTimeout.world(0);urlTimeout.session.advance();urlTimeout.now=21;urlTimeout.session.tick()
    check(urlTimeout.session.status.phase == .failed && urlTimeout.finishes==0,"URLtimeout")
    let importTimeout = try h();importTimeout.catalog();importTimeout.world(0)
    await wait({importTimeout.imports.count==1},"importtimeout gate")
    importTimeout.now=61;importTimeout.session.tick();importTimeout.release(0);await Task.yield()
    check(importTimeout.session.status.phase == .failed && importTimeout.finishes==0,"late importer cannot undo timeout")
    let ackTimeout = try h();ackTimeout.world(0);ackTimeout.session.advance();ackTimeout.now=16;ackTimeout.session.tick();ackTimeout.session.receive(id:185,data:Data())
    check(ackTimeout.session.status.phase == .failed && ackTimeout.ready.isEmpty,"acktimeout")
    let catalogTimeout = try h();catalogTimeout.catalog(count:2);catalogTimeout.world(0);catalogTimeout.now=31;catalogTimeout.session.tick()
    check(catalogTimeout.session.status.phase == .failed,"partialcatalogtimeout")
    let refused = try h();refused.refused=184;refused.world(0);refused.session.advance()
    check(refused.session.status.phase == .failed && refused.ready.isEmpty,"send failure never ready")
    let bad = try h();bad.forcedURL="bad";bad.catalog();bad.world(0)
    await wait({bad.session.status.phase == .failed},"actualCRCfailure")
    check(bad.imports.isEmpty && bad.finishes==0,"failed real transfer never imports/finishes")
    let skinnedData=try Data(contentsOf:folder.appendingPathComponent("skinned.dff"))
    let unsupported=try Harness(root:folder.appendingPathComponent("cache"),base:base,dffData:skinnedData,txdData:txd)
    unsupported.dffEndpoint="skinned";unsupported.catalog();unsupported.world(0)
    await wait({unsupported.session.status.phase == .failed},"real native importer rejection")
    check(unsupported.session.status.verifiedFiles==2 && unsupported.finishes==0,"verified pair alone never bypasses actual importer failure")
    check(unsupported.session.status.failure?.description.contains("import failed")==true,"native importer failure reported")
    let downloadTimeout=try h();downloadTimeout.autoURLs=false;downloadTimeout.catalog();downloadTimeout.world(0);downloadTimeout.session.advance()
    downloadTimeout.session.receive(id:183,data:url(downloadTimeout.dff,base.appendingPathComponent("dff")))
    downloadTimeout.now=101;downloadTimeout.session.tick()
    check(downloadTimeout.session.status.failure?.description.contains("download")==true && downloadTimeout.finishes==0,"active cache transfer timeout")
    let freshCatalogDeadline=try h();freshCatalogDeadline.catalog();freshCatalogDeadline.world(0)
    await wait({freshCatalogDeadline.imports.count==1},"catalog deadline initial phase")
    freshCatalogDeadline.now=100;freshCatalogDeadline.catalog(1,count:3,id:-1001);freshCatalogDeadline.now=101;freshCatalogDeadline.session.tick()
    check(freshCatalogDeadline.session.status.failure==nil,"catalog growth gets a fresh deadline")
    freshCatalogDeadline.now=131;freshCatalogDeadline.session.tick()
    check(freshCatalogDeadline.session.status.phase == .failed,"new partial catalog eventually times out")
    let cancelled = try h();cancelled.catalog();cancelled.world(0);cancelled.session.cancel();cancelled.session.advance()
    check(cancelled.session.status.phase == .cancelled && cancelled.sent.isEmpty,"cancel stops queuedadvance")
    check(!cancelled.session.receive(id:99,data:Data()),"unrelatedRPC notconsumed")
    print("{\"status\":\"PASS\",\"checks\":\(checks),\"realNativeCPUImports\":\(primary.cpuImports+partial.cpuImports+stale.cpuImports+growth.cpuImports+serial.cpuImports+importTimeout.cpuImports),\"scope\":\"real HTTP/cache plus generated valid RW native CPU importer; official server handled separately\"}")
}
Task { @MainActor in do { try await tests();exit(0) } catch { fatalError("\(error)") } }
dispatchMain()
