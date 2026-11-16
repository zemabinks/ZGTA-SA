// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit

/// Acquires exact owner-supplied stock files and prepares static CPU resources.
/// Public calls and completions belong to the main queue. A Prepared value is
/// neither a GPU registration nor a collision-world registration.
final class NativeSAMPStockAssetLoader {
    struct Limits {
        var concurrentLoads = 2
        var pendingLoads = 32
        var filesPerModel = 33
        var fileBytes = 32 * 1024 * 1024
        var encodedBytesPerModel = 96 * 1024 * 1024
        /// Counts every decoded dictionary, including duplicate parent textures.
        var decodedTextureBytes = 64 * 1024 * 1024
        var textures = 2_048
        var preparedBytes = 96 * 1024 * 1024
        var vertices = 100_000
        var triangles = 200_000
        var requestTimeout: TimeInterval = 20
        var resourceTimeout: TimeInterval = 90
    }
    enum Failure: Error, CustomStringConvertible {
        case invalidURL, invalidResolution(String), limit(String), unsupportedKind(NativeSAMPStockModels.Kind)
        case missingAssets([String]), http(Int), size(expected: Int, received: Int), checksum, sha256
        case redirect, encoding, io, cancelled, unresolvedTextures([String]), noRenderableGeometry
        var description: String {
            switch self {
            case .invalidURL: return "Invalid stock asset origin or manifest URL"
            case .invalidResolution(let s): return "Invalid stock asset resolution: \(s)"
            case .limit(let s): return "Stock asset limit: \(s)"
            case .unsupportedKind(let k): return "Stock \(k.rawValue) requires its own importer"
            case .missingAssets(let names): return "Missing stock assets: \(names.joined(separator: ", "))"
            case .http(let status): return "Stock asset HTTP \(status)"
            case .size(let expected,let received): return "Stock asset size \(received), expected \(expected)"
            case .checksum: return "Stock asset CRC32 mismatch"
            case .sha256: return "Stock asset SHA-256 mismatch"
            case .redirect: return "Stock asset redirects are not permitted"
            case .encoding: return "Stock asset content encoding must be identity"
            case .io: return "Stock asset file I/O failed"
            case .cancelled: return "Stock asset load cancelled"
            case .unresolvedTextures(let names): return "Unresolved stock textures: \(names.joined(separator: ", "))"
            case .noRenderableGeometry: return "Stock model has no supported renderable geometry"
            }
        }
    }
    struct Prepared {
        let requestID: UUID
        let generation: UInt64
        let model: NativeSAMPStockModels.Model
        let dff: NativeRenderWareDFF
        let textures: NativeRenderWareTXD.TextureDictionary
        let plan: NativeRenderWareModel.Plan
        /// Fully decoded authored plugins only. Empty means no embedded COL;
        /// external COL association remains a separate exact-name operation.
        let embeddedCollision: [NativeRenderWareCollision.Model]
    }
    /// Verified file bytes only. The caller must run the relevant bounded
    /// format/identity parser (for example StockCollisionCatalog.prepare).
    struct BlobData {
        let requestID: UUID
        let generation: UInt64
        let file: NativeSAMPStockModels.File
        let data: Data
    }
    typealias Completion = (Result<Prepared, Error>) -> Void
    typealias FileCompletion = (Result<BlobData, Error>) -> Void
    private struct Pending {
        let id: UUID, generation: UInt64
        let resolution: NativeSAMPStockModels.Resolution?
        let files: [NativeSAMPStockModels.File]
        let access: NativeStockAssetAccess?
        let completion: (Result<StockAssetJob.Output,Error>) -> Void
    }
    private struct Running { let pending: Pending; let job: StockAssetJob }
    private let base: URL, limits: Limits, allowLocalFiles: Bool
    private let accessProvider: (() -> NativeStockAssetAccess?)?
    private var pending: [Pending] = []
    private var running: [UUID: Running] = [:]
    private(set) var generation: UInt64 = 1
    var activeCount: Int { main(); return running.count }
    var pendingCount: Int { main(); return pending.count }

    init(assetBaseURL: URL, limits: Limits = .init(), allowLocalFiles: Bool = false,
         accessProvider: (() -> NativeStockAssetAccess?)? = nil) throws {
        guard (1...4).contains(limits.concurrentLoads),(1...256).contains(limits.pendingLoads),
              (1...129).contains(limits.filesPerModel),(12...64*1024*1024).contains(limits.fileBytes),
              limits.encodedBytesPerModel > 0,limits.encodedBytesPerModel <= 256*1024*1024,
              limits.decodedTextureBytes > 0,limits.decodedTextureBytes <= 256*1024*1024,
              (1...8_192).contains(limits.textures),limits.preparedBytes > 0,limits.preparedBytes <= 256*1024*1024,
              (1...1_000_000).contains(limits.vertices),(1...2_000_000).contains(limits.triangles),
              limits.requestTimeout.isFinite,limits.requestTimeout > 0,limits.requestTimeout <= 300,
              limits.resourceTimeout.isFinite,limits.resourceTimeout > 0,limits.resourceTimeout <= 300 else { throw Failure.limit("configuration") }
        guard Self.validBase(assetBaseURL, allowLocalFiles: allowLocalFiles) else { throw Failure.invalidURL }
        self.base=assetBaseURL;self.limits=limits;self.allowLocalFiles=allowLocalFiles
        self.accessProvider=accessProvider
    }
    deinit { for value in running.values { value.job.cancel() } }

    @discardableResult
    func load(_ resolution: NativeSAMPStockModels.Resolution, completion: @escaping Completion) -> UUID {
        main();let id=UUID()
        do {
            let files=try validate(resolution)
            try submit(id:id,resolution:resolution,files:files) { result in
                completion(result.flatMap { output in
                    if case .model(let prepared)=output { return .success(prepared) }
                    return .failure(Failure.invalidResolution("internal result kind"))
                })
            }
        } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        return id
    }
    /// Uses the same streaming verifier, queue budgets and generation/cancel
    /// owner as model loading; no format decoder or placeholder is implied.
    @discardableResult
    func loadFile(_ file: NativeSAMPStockModels.File, completion: @escaping FileCompletion) -> UUID {
        main();let id=UUID()
        do {
            try validateFiles([file])
            try submit(id:id,resolution:nil,files:[file]) { result in
                completion(result.flatMap { output in
                    if case .blob(let data)=output { return .success(data) }
                    return .failure(Failure.invalidResolution("internal result kind"))
                })
            }
        } catch { DispatchQueue.main.async { completion(.failure(error)) } }
        return id
    }
    private func submit(id:UUID,resolution:NativeSAMPStockModels.Resolution?,files:[NativeSAMPStockModels.File],
                        completion:@escaping(Result<StockAssetJob.Output,Error>)->Void) throws {
        guard pending.count < limits.pendingLoads else { throw Failure.limit("pending loads") }
        pending.append(Pending(id:id,generation:generation,resolution:resolution,files:files,access:accessProvider?(),completion:completion));pump()
    }
    func cancel(_ id: UUID) {
        main()
        if let index=pending.firstIndex(where:{$0.id == id}) {
            let item=pending.remove(at:index)
            DispatchQueue.main.async { item.completion(.failure(Failure.cancelled)) }
        }
        running[id]?.job.cancel()
    }
    /// Old CPU work keeps its concurrency slot until it actually exits. Reset
    /// cannot accidentally multiply concurrent decoders while cancelling them.
    @discardableResult func reset() -> UInt64 {
        main();generation &+= 1
        let cancelled=pending;pending.removeAll()
        for value in running.values { value.job.cancel() }
        for item in cancelled { DispatchQueue.main.async { item.completion(.failure(Failure.cancelled)) } }
        return generation
    }
    private func main() { dispatchPrecondition(condition:.onQueue(.main)) }
    private func pump() {
        main()
        while running.count < limits.concurrentLoads,!pending.isEmpty {
            let item=pending.removeFirst()
            let job=StockAssetJob(requestID:item.id,generation:item.generation,resolution:item.resolution,files:item.files,
                                  limits:limits,allowLocalFiles:allowLocalFiles,access:item.access) { [weak self] result in
                DispatchQueue.main.async { self?.finished(item.id,result:result) }
            }
            running[item.id]=Running(pending:item,job:job);job.start()
        }
    }
    private func finished(_ id: UUID,result: Result<StockAssetJob.Output,Error>) {
        main();guard let value=running.removeValue(forKey:id) else { return }
        let valid=value.pending.generation == generation && !value.job.isCancelled
        value.pending.completion(valid ? result : .failure(Failure.cancelled))
        pump()
    }
    private func validate(_ value: NativeSAMPStockModels.Resolution) throws -> [NativeSAMPStockModels.File] {
        switch value.model.kind { case .object,.timed,.weapon: break; default: throw Failure.unsupportedKind(value.model.kind) }
        guard value.dictionaries.count < limits.filesPerModel,value.textureSearch.count == value.dictionaries.count else { throw Failure.limit("dictionary files") }
        let missing=([value.missingDFF].compactMap{$0})+value.missingTXDs
        guard missing.isEmpty else { throw Failure.missingAssets(missing) }
        guard let dff=value.dff else { throw Failure.missingAssets([value.model.model+".dff"]) }
        let names=value.dictionaries.map{$0.name},search=value.textureSearch.map{$0.name}
        guard !names.isEmpty,Set(names).count == names.count,Set(names) == Set(search),search.count == names.count,
              names.first == value.model.txd else { throw Failure.invalidResolution("dictionary chain") }
        var files=[dff]
        for dictionary in value.textureSearch {
            guard let file=dictionary.file,let original=value.dictionaries.first(where:{$0.name == dictionary.name})?.file,
                  file.url == original.url,file.metadata.path == original.metadata.path,
                  file.metadata.sha256 == original.metadata.sha256,file.metadata.crc32 == original.metadata.crc32,
                  file.metadata.bytes == original.metadata.bytes else { throw Failure.invalidResolution("dictionary file identity") }
            files.append(file)
        }
        guard files.count <= limits.filesPerModel else { throw Failure.limit("files per model") }
        try validateFiles(files)
        return files
    }
    private func validateFiles(_ files:[NativeSAMPStockModels.File]) throws {
        guard !files.isEmpty,files.count <= limits.filesPerModel else { throw Failure.limit("files per model") }
        var total=0
        for file in files {
            let asset=file.metadata
            guard (12...limits.fileBytes).contains(asset.bytes),asset.bytes <= limits.encodedBytesPerModel-total else { throw Failure.limit("advertised file/model bytes") }
            total+=asset.bytes
            guard asset.sha256.utf8.count == 64,asset.sha256.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}),
                  Self.validPath(asset.path) else { throw Failure.invalidResolution("manifest path/hash") }
            var expected=base
            for part in asset.path.split(separator:"/") { expected.appendPathComponent(String(part)) }
            guard file.url.absoluteURL == expected.absoluteURL else { throw Failure.invalidURL }
            if file.url.isFileURL {
                guard allowLocalFiles else { throw Failure.invalidURL }
                let root=base.resolvingSymlinksInPath().standardizedFileURL.path
                let path=file.url.resolvingSymlinksInPath().standardizedFileURL.path
                guard path.hasPrefix(root.hasSuffix("/") ? root : root+"/") else { throw Failure.invalidURL }
            } else {
                guard Self.origin(file.url) == Self.origin(base),file.url.query == nil,file.url.fragment == nil,
                      file.url.user == nil,file.url.password == nil else { throw Failure.invalidURL }
            }
        }
    }
    private static func validBase(_ url: URL,allowLocalFiles: Bool) -> Bool {
        guard url.user == nil,url.password == nil,url.query == nil,url.fragment == nil else { return false }
        if url.isFileURL { return allowLocalFiles && url.host.map{$0.isEmpty || $0 == "localhost"} ?? allowLocalFiles }
        guard ["http","https"].contains(url.scheme?.lowercased() ?? ""),let host=url.host,!host.isEmpty else { return false }
        return url.port.map{(1...65535).contains($0)} ?? true
    }
    private static func origin(_ url: URL) -> String {
        let scheme=url.scheme?.lowercased() ?? ""
        return "\(scheme)://\(url.host?.lowercased() ?? ""):\(url.port ?? (scheme == "https" ? 443 : 80))"
    }
    private static func validPath(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 1_024 && value.split(separator:"/",omittingEmptySubsequences:false).allSatisfy { part in
            !part.isEmpty && part != "." && part != ".." && part.utf8.allSatisfy{(65...90).contains($0)||(97...122).contains($0)||(48...57).contains($0)||[95,35,40,41,43,45,46].contains($0)}
        }
    }
}

private final class StockAssetJob {
    typealias Loader=NativeSAMPStockAssetLoader
    enum Output { case model(Loader.Prepared),blob(Loader.BlobData) }
    private let queue=DispatchQueue(label:"ZGTA.StockAssets.import",qos:.utility)
    private let lock=NSLock()
    private var cancelled=false,transfer: StockAssetTransfer?
    var isCancelled: Bool { lock.lock();defer{lock.unlock()};return cancelled }
    private let requestID: UUID,generation: UInt64,resolution: NativeSAMPStockModels.Resolution?
    private let files: [NativeSAMPStockModels.File],limits: Loader.Limits,allowLocalFiles: Bool
    private let access: NativeStockAssetAccess?
    private let completion: (Result<Output,Error>)->Void
    private var next=0,finished=false,dff: NativeRenderWareDFF?,collision:[NativeRenderWareCollision.Model]=[]
    private var textures:[NativeRenderWareTXD.Texture]=[],names=Set<String>(),decodedBytes=0,decodedTextures=0,version:UInt32=0,deviceID:UInt16=2
    init(requestID:UUID,generation:UInt64,resolution:NativeSAMPStockModels.Resolution?,files:[NativeSAMPStockModels.File],
         limits:Loader.Limits,allowLocalFiles:Bool,access:NativeStockAssetAccess?,completion:@escaping(Result<Output,Error>)->Void) {
        self.requestID=requestID;self.generation=generation;self.resolution=resolution;self.files=files
        self.limits=limits;self.allowLocalFiles=allowLocalFiles;self.completion=completion
        self.access=access
    }
    func start() { queue.async { self.advance() } }
    func cancel() { lock.lock();cancelled=true;let current=transfer;lock.unlock();current?.cancel() }
    private func finish(_ result:Result<Output,Error>) {
        guard !finished else{return};finished=true;completion(isCancelled ? .failure(Loader.Failure.cancelled):result)
    }
    private func advance() {
        guard !isCancelled else { finish(.failure(Loader.Failure.cancelled));return }
        guard next < files.count else {
            do {
                guard let dff,let resolution else { throw Loader.Failure.noRenderableGeometry }
                let merged=NativeRenderWareTXD.TextureDictionary(version:version,deviceID:deviceID,textures:textures,
                    decodedByteCount:textures.reduce(0){$0+$1.mipLevels.reduce(0){$0+($1.rgba8?.count ?? 0)}})
                var budget=NativeRenderWareModel.Limits()
                budget.vertices=limits.vertices;budget.indices=limits.triangles*3;budget.meshBytes=limits.preparedBytes
                budget.textureBytes=limits.preparedBytes;budget.instances=1_024;budget.draws=8_192;budget.materials=4_096
                let plan=try NativeRenderWareModel.prepare(dff:dff,txd:merged,limits:budget)
                let missing=plan.diagnostics.compactMap { diagnostic -> String? in
                    if case .missingTexture(_,_,let name)=diagnostic { return name };return nil
                }
                guard missing.isEmpty else { throw Loader.Failure.unresolvedTextures(Array(Set(missing)).sorted()) }
                guard !plan.draws.isEmpty else { throw Loader.Failure.noRenderableGeometry }
                guard plan.meshByteCount <= limits.preparedBytes-plan.textureByteCount else { throw Loader.Failure.limit("prepared mesh + textures") }
                finish(.success(.model(.init(requestID:requestID,generation:generation,model:resolution.model,dff:dff,textures:merged,plan:plan,embeddedCollision:collision))))
            } catch { finish(.failure(error)) }
            return
        }
        let index=next,file=files[index]
        if file.url.isFileURL {
            do { try consume(readLocal(file),index:index) } catch { finish(.failure(error)) };return
        }
        let current=StockAssetTransfer(file:file,limits:limits,access:access) { [weak self] result in
            guard let self else{return}
            self.queue.async {
                self.lock.lock();self.transfer=nil;self.lock.unlock()
                do { try self.consume(result.get(),index:index) } catch { self.finish(.failure(error)) }
            }
        }
        lock.lock();transfer=current;let stop=cancelled;lock.unlock()
        if stop { finish(.failure(Loader.Failure.cancelled)) } else { current.start() }
    }
    private func readLocal(_ file:NativeSAMPStockModels.File) throws -> Data {
        guard allowLocalFiles else { throw Loader.Failure.invalidURL }
        let handle:FileHandle
        do { handle=try FileHandle(forReadingFrom:file.url) } catch { throw Loader.Failure.io }
        defer { try? handle.close() }
        var sink=StockAssetSink(metadata:file.metadata)
        while true {
            guard !isCancelled else { throw Loader.Failure.cancelled }
            guard let part=try handle.read(upToCount:64*1024),!part.isEmpty else { break }
            try sink.append(part)
        }
        return try sink.finish()
    }
    private func consume(_ data:Data,index:Int) throws {
        guard !isCancelled else { throw Loader.Failure.cancelled }
        if resolution == nil {
            finish(.success(.blob(.init(requestID:requestID,generation:generation,file:files[index],data:data))))
            return
        }
        if index == 0 {
            var budget=NativeRenderWareDFF.Limits();budget.fileBytes=limits.fileBytes
            budget.totalVertices=limits.vertices;budget.verticesPerGeometry=limits.vertices
            budget.totalTriangles=limits.triangles;budget.trianglesPerGeometry=limits.triangles
            budget.geometries=256;budget.frames=1_024;budget.atomics=1_024;budget.materialsPerGeometry=256
            budget.morphTargets=1 // Static import must not allocate animated targets first.
            let value=try NativeRenderWareDFF.decode(data,limits:budget)
            guard !value.geometries.contains(where:{$0.skin != nil || $0.morphTargets.count > 1}) else { throw Loader.Failure.invalidResolution("skinned or animated geometry requires another importer") }
            var colBudget=NativeRenderWareCollision.Limits();colBudget.dffBytes=limits.fileBytes
            colBudget.totalPrimitives=limits.triangles;colBudget.totalVertices=limits.vertices;colBudget.models=64
            collision=try NativeRenderWareCollision.embedded(inDFF:data,limits:colBudget).flatMap{$0.models}
            dff=value
        } else {
            var budget=NativeRenderWareTXD.Limits();budget.maximumFileBytes=limits.fileBytes
            budget.maximumDecodedBytes=limits.decodedTextureBytes-decodedBytes
            budget.maximumTextureCount=limits.textures-decodedTextures
            guard budget.maximumDecodedBytes > 0,budget.maximumTextureCount > 0 else { throw Loader.Failure.limit("decoded dictionaries") }
            let value=try NativeRenderWareTXD.decode(data,limits:budget)
            decodedBytes+=value.decodedByteCount;decodedTextures+=value.textures.count
            if index == 1 { version=value.version;deviceID=value.deviceID }
            for texture in value.textures where names.insert(texture.lookupName).inserted { textures.append(texture) }
        }
        next+=1
        // Release this encoded file before scheduling the next transfer/decode.
        queue.async { self.advance() }
    }
}

/// No dataTask completion buffer: every received block is checked before append.
/// The sink's maximum capacity is the already bounded, advertised manifest size.
private struct StockAssetSink {
    let metadata:NativeSAMPStockModels.Asset
    private var bytes=Data(),hash=SHA256(),crc:UInt32=0xffffffff
    private static let table:[UInt32]=(0..<256).map { n in var value=UInt32(n);for _ in 0..<8 { value=(value>>1) ^ (value & 1 == 1 ? 0xedb88320:0) };return value }
    init(metadata:NativeSAMPStockModels.Asset) { self.metadata=metadata }
    mutating func append(_ data:Data) throws {
        guard data.count <= metadata.bytes-bytes.count else { throw NativeSAMPStockAssetLoader.Failure.size(expected:metadata.bytes,received:bytes.count+data.count) }
        bytes.append(data);hash.update(data:data)
        for byte in data { crc=Self.table[Int((crc ^ UInt32(byte)) & 255)] ^ (crc>>8) }
    }
    mutating func finish() throws -> Data {
        guard bytes.count == metadata.bytes else { throw NativeSAMPStockAssetLoader.Failure.size(expected:metadata.bytes,received:bytes.count) }
        guard crc ^ 0xffffffff == metadata.crc32 else { throw NativeSAMPStockAssetLoader.Failure.checksum }
        guard hash.finalize().map({String(format:"%02x",$0)}).joined() == metadata.sha256 else { throw NativeSAMPStockAssetLoader.Failure.sha256 }
        return bytes
    }
}

private final class StockAssetTransfer:NSObject,URLSessionDataDelegate {
    typealias Loader=NativeSAMPStockAssetLoader
    private let file:NativeSAMPStockModels.File,limits:Loader.Limits,completion:(Result<Data,Error>)->Void
    private let access: NativeStockAssetAccess?
    private let delegateQueue:OperationQueue={let value=OperationQueue();value.maxConcurrentOperationCount=1;return value}()
    private var session:URLSession?,task:URLSessionDataTask?,finished=false,sink:StockAssetSink
    init(file:NativeSAMPStockModels.File,limits:Loader.Limits,access:NativeStockAssetAccess?,completion:@escaping(Result<Data,Error>)->Void) {
        self.file=file;self.limits=limits;self.completion=completion;self.sink=StockAssetSink(metadata:file.metadata)
        self.access=access
    }
    func start() { delegateQueue.addOperation {
        guard !self.finished else { return }
        let config=URLSessionConfiguration.ephemeral
        config.httpCookieStorage=nil;config.httpShouldSetCookies=false;config.urlCredentialStorage=nil;config.urlCache=nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest=self.limits.requestTimeout;config.timeoutIntervalForResource=self.limits.resourceTimeout
        self.session=URLSession(configuration:config,delegate:self,delegateQueue:self.delegateQueue)
        var request=URLRequest(url:self.file.url);request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
        request.setValue("ZGTA-SA-Stock/1",forHTTPHeaderField:"User-Agent")
        request.httpShouldHandleCookies=false
        if let header=self.access?.cookieHeader(for:self.file.url) {request.setValue(header,forHTTPHeaderField:"Cookie")}
        self.task=self.session!.dataTask(with:request);self.task?.resume()
    } }
    func cancel() { delegateQueue.addOperation { self.finish(.failure(Loader.Failure.cancelled)) } }
    private func finish(_ result:Result<Data,Error>) {
        guard !finished else{return};finished=true;task?.cancel();task=nil;session?.invalidateAndCancel();session=nil
        // URLSession may retain its delegate after cancellation. Release the
        // verified/partial body before the owning job releases its active slot.
        sink=StockAssetSink(metadata:file.metadata)
        completion(result)
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,completionHandler:@escaping(URLSession.ResponseDisposition)->Void) {
        guard !finished else{completionHandler(.cancel);return}
        do {
            guard let value=response as? HTTPURLResponse,value.url == file.url else { throw Loader.Failure.invalidURL }
            guard value.statusCode == 200 else { throw Loader.Failure.http(value.statusCode) }
            if let encoding=value.value(forHTTPHeaderField:"Content-Encoding"),encoding.lowercased() != "identity" { throw Loader.Failure.encoding }
            guard value.expectedContentLength < 0 || value.expectedContentLength == Int64(file.metadata.bytes) else { throw Loader.Failure.size(expected:file.metadata.bytes,received:Int(clamping:value.expectedContentLength)) }
            completionHandler(.allow)
        } catch { completionHandler(.cancel);finish(.failure(error)) }
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data) {
        guard !finished else{return}
        do { try sink.append(data) } catch { finish(.failure(error)) }
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
        guard !finished else{return}
        do { if let error { throw error };finish(.success(try sink.finish())) } catch { finish(.failure(error)) }
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void) {
        completionHandler(nil);finish(.failure(Loader.Failure.redirect))
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didReceive challenge:URLAuthenticationChallenge,completionHandler:@escaping(URLSession.AuthChallengeDisposition,URLCredential?)->Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust { completionHandler(.performDefaultHandling,nil) }
        else { completionHandler(.cancelAuthenticationChallenge,nil) }
    }
}
