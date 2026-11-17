// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit

/// Persistent content-addressed resource storage shared by installation and
/// development streaming. App updates do not change the Application Support root.
final class NativeResourceStore {
    enum Mode: String, Codable { case development, installed }
    struct Snapshot {
        let mode: Mode
        let installedContentID: String?
        let installedFiles: Int
        let installedBytes: Int64
        let cachedFiles: Int
        let cachedBytes: Int64
        let hasPlayableInstallation: Bool
        let developmentOrigin: String?
        let issues: [String]
    }
    struct Progress {
        let phase: String
        let completedFiles: Int
        let totalFiles: Int
        let completedBytes: Int64
        let totalBytes: Int64
        let currentPath: String?
    }
    enum Failure: Error, CustomStringConvertible, LocalizedError {
        case invalid(String), cancelled, http(Int), checksum(String), missing(String)
        var description: String {
            switch self {
            case .invalid(let s): return s
            case .cancelled: return "Resource operation cancelled; verified files are retained"
            case .http(let status): return "Resource server returned HTTP \(status)"
            case .checksum(let path): return "Resource identity verification failed: \(path)"
            case .missing(let path): return "Resource unavailable: \(path)"
            }
        }
        var errorDescription:String? { description }
    }
    final class Operation {
        private let lock = NSLock()
        private var cancelled = false
        private var task: URLSessionTask?
        func cancel() { lock.lock(); cancelled = true; let current = task; lock.unlock(); current?.cancel() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
        fileprivate func attach(_ value: URLSessionTask?) {
            lock.lock(); task = value; let stop = cancelled; lock.unlock()
            if stop { value?.cancel() }
        }
        fileprivate func check() throws { if isCancelled { throw Failure.cancelled } }
    }
    private struct Settings: Codable { var mode: Mode = .development; var developmentOrigin: String? }
    typealias RuntimeValidator = (NativeResourceManifest,@escaping(String)throws->URL)throws->Void
    private struct Receipt: Codable { let manifest: NativeResourceManifest; let developmentOrigin: String?; let validationIdentity:String? }
    static let shared: NativeResourceStore = {
        let parent = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return NativeResourceStore(root: parent.appendingPathComponent("ZGTA-SA/Resources-v1", isDirectory: true))
    }()
    let root: URL
    private let files = FileManager.default
    private let lock = NSLock()
    private let worker = DispatchQueue(label: "org.zgtasa.resources.install", qos: .utility)
    private var observers: [UUID: (Snapshot) -> Void] = [:]
    private var settings = Settings()
    private var catalogue: NativeResourceManifest?
    private var entries: [String: NativeResourceManifest.Resource] = [:]
    private var cacheSizes: [String: Int64] = [:]
    private var issues: [String] = []
    private var usable = false
    private var busy = false
    private var runtimeValidator:RuntimeValidator?
    private var validationIdentity:String?
    private var receiptValidationIdentity:String?
    private let session: URLSession

    init(root: URL, session: URLSession = .shared,validationIdentity:String?=nil,runtimeValidator:RuntimeValidator?=nil) {
        self.root = root; self.session = session;self.validationIdentity=validationIdentity;self.runtimeValidator=runtimeValidator
        do {
            try files.createDirectory(at: root.appendingPathComponent("blobs"), withIntermediateDirectories: true)
            try files.createDirectory(at: root.appendingPathComponent("staging"), withIntermediateDirectories: true)
            var location = root; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? location.setResourceValues(values)
            if let bytes = try? Data(contentsOf: root.appendingPathComponent("settings.json")),
               let saved = try? JSONDecoder().decode(Settings.self, from: bytes) { settings = saved }
            if let bytes = try? Data(contentsOf: root.appendingPathComponent("active.json")) {
                let receipt = try JSONDecoder().decode(Receipt.self, from: bytes)
                let saved = receipt.manifest; try saved.validate()
                settings.developmentOrigin = receipt.developmentOrigin
                receiptValidationIdentity=receipt.validationIdentity
                catalogue = saved; entries = Dictionary(uniqueKeysWithValues: saved.resources.map { ($0.path, $0) })
                // Import/verify commits this receipt only after complete validation.
                // Reads still revalidate actual bytes before returning them.
                usable = Self.validValidationIdentity(validationIdentity) && runtimeValidator != nil && receipt.validationIdentity==validationIdentity && saved.resources.allSatisfy { Self.size(blobURL($0.sha256)) == $0.bytes }
                if !usable { issues = ["Installation is incomplete. Verify or repair it from the existing resource source."] }
            }
            if let data = try? Data(contentsOf: root.appendingPathComponent("cache-index.json")),
               let index = try? JSONDecoder().decode([String: Int64].self, from: data) {
                cacheSizes = index.filter { NativeResourceManifest.validDigest($0.key) && Self.size(blobURL($0.key)) == $0.value }
            }
        } catch { issues = [String(describing: error)] }
    }
    var snapshot: Snapshot { lock.lock(); defer { lock.unlock() }; return state() }
    private static func validValidationIdentity(_ value:String?)->Bool {
        guard let value else{return false}
        return !value.isEmpty && value.utf8.count<=128
    }
    /// The App supplies its actual native decoders. File integrity alone does
    /// not certify a playable native resource graph. The identity is a format
    /// contract version, not the app build number, so normal updates reuse it.
    func configureRuntimeValidation(identity:String,validator:@escaping RuntimeValidator)throws {
        lock.lock();defer{lock.unlock()}
        guard !busy,Self.validValidationIdentity(identity) else{throw Failure.invalid("Cannot change resource validation during installation or use an invalid validation identity")}
        validationIdentity=identity;runtimeValidator=validator
        usable = receiptValidationIdentity==identity && catalogue?.resources.allSatisfy{Self.size(blobURL($0.sha256))==$0.bytes} == true
        if usable{issues=[]}
        else if catalogue != nil{issues=["Verify the existing resources with the current native runtime before playing. Reimporting the ISO is not required."]}
        DispatchQueue.main.async{self.publish()}
    }
    private func state() -> Snapshot {
        Snapshot(mode: settings.mode, installedContentID: catalogue?.contentID,
                 installedFiles: catalogue?.resources.count ?? 0, installedBytes: catalogue?.totalBytes ?? 0,
                 cachedFiles: cacheSizes.count, cachedBytes: cacheSizes.values.reduce(0,+),
                 hasPlayableInstallation: usable, developmentOrigin: settings.developmentOrigin, issues: issues)
    }
    @discardableResult func observe(_ callback: @escaping (Snapshot) -> Void) -> UUID {
        let id = UUID(); lock.lock(); observers[id] = callback; let value = state(); lock.unlock()
        DispatchQueue.main.async { callback(value) }; return id
    }
    func removeObserver(_ id: UUID) { lock.lock(); observers.removeValue(forKey: id); lock.unlock() }
    private func publish() {
        lock.lock(); let value = state(), callbacks = Array(observers.values); lock.unlock()
        DispatchQueue.main.async { callbacks.forEach { $0(value) } }
    }
    func setMode(_ mode: Mode) throws {
        lock.lock(); defer { lock.unlock() }
        guard !busy else { throw Failure.invalid("Wait for the current resource operation to finish") }
        guard mode != .installed || usable else { throw Failure.invalid("Verify a complete prepared installation before selecting local resources") }
        let old = settings; settings.mode = mode
        do { try JSONEncoder().encode(settings).write(to: root.appendingPathComponent("settings.json"), options: .atomic) }
        catch { settings = old; throw error }
        DispatchQueue.main.async { self.publish() }
    }
    private func blobURL(_ digest: String) -> URL { root.appendingPathComponent("blobs").appendingPathComponent(digest) }
    private static func size(_ url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true, let n = values.fileSize else { return nil }
        return Int64(n)
    }
    private func digest(_ url: URL, operation: Operation? = nil) throws -> (Int64,String) {
        guard Self.size(url) != nil else { throw Failure.missing(url.lastPathComponent) }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256(), bytes: Int64 = 0
        while let data = try file.read(upToCount: 1_024 * 1_024), !data.isEmpty {
            try operation?.check(); bytes += Int64(data.count); hash.update(data: data)
        }
        return (bytes,hash.finalize().map { String(format: "%02x",$0) }.joined())
    }
    private func matches(_ item: NativeResourceManifest.Resource, at url: URL, operation: Operation?) throws -> Bool {
        guard Self.size(url) == item.bytes else { return false }
        let actual = try digest(url, operation: operation)
        return actual.0 == item.bytes && actual.1 == item.sha256
    }
    /// Runtime lookup never accepts a file merely because it has a hash-shaped name.
    func localResource(for request: URL,maximumBytes:Int64=128*1_024*1_024) throws -> (Data,NativeResourceManifest.Resource)? {
        let path = request.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        lock.lock(); let mode = settings.mode, item = entries[path], origin = settings.developmentOrigin,verified=usable; lock.unlock()
        if mode == .installed,!verified{throw Failure.invalid("Installed resources need native runtime verification")}
        guard NativeResourceManifest.validPath(path) else {
            if mode == .installed,NativeResourceManifest.isResourceNamespace(path){throw Failure.invalid("Invalid installed resource path")};return nil
        }
        guard NativeResourceManifest.validRequestQuery(request) else {
            if mode == .installed{throw Failure.invalid("Unsupported resource query: \(path)")};return nil
        }
        if mode == .development {
            guard let origin, Self.origin(request)?.absoluteString == origin else { return nil }
        }
        guard let item else {
            if mode == .installed { throw Failure.missing(path) }; return nil
        }
        guard item.bytes<=maximumBytes else{throw Failure.invalid("Resource exceeds this runtime reader's byte budget: \(path)")}
        let location = blobURL(item.sha256)
        guard Self.size(location) == item.bytes else {
            if mode == .installed { throw Failure.missing(path) }; return nil
        }
        let data = try Data(contentsOf: location, options: .mappedIfSafe)
        guard Int64(data.count) == item.bytes,
              SHA256.hash(data: data).map({ String(format: "%02x",$0) }).joined() == item.sha256 else {
            throw Failure.checksum(path)
        }
        return (data,item)
    }
    func installedURL(for request: URL) throws -> URL? {
        let path=request.path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        lock.lock();let mode=settings.mode,item=entries[path],origin=settings.developmentOrigin,verified=usable;lock.unlock()
        if mode == .installed,!verified{throw Failure.invalid("Installed resources need native runtime verification")}
        guard NativeResourceManifest.validPath(path) else{
            if mode == .installed,NativeResourceManifest.isResourceNamespace(path){throw Failure.invalid("Invalid installed resource path")};return nil
        }
        guard NativeResourceManifest.validRequestQuery(request) else{
            if mode == .installed{throw Failure.invalid("Unsupported resource query: \(path)")};return nil
        }
        if mode == .development {
            guard let origin,Self.origin(request)?.absoluteString==origin else{return nil}
        }
        guard let item else{if mode == .installed{throw Failure.missing(path)};return nil}
        let url=blobURL(item.sha256)
        guard try matches(item,at:url,operation:nil) else{throw Failure.checksum(path)}
        return url
    }
    static func origin(_ url: URL) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http","https"].contains(parts.scheme?.lowercased() ?? ""), parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil, parts.fragment == nil else { return nil }
        parts.path = ""; parts.query = nil; return parts.url
    }
    private func perform(progress: @escaping (Progress) -> Void,
                         completion: @escaping (Result<Snapshot,Error>) -> Void,
                         body: @escaping (Operation,@escaping(Progress)->Void) throws -> Void) -> Operation {
        let operation = Operation()
        worker.async {
            self.lock.lock(); self.busy = true; self.issues = []; self.lock.unlock(); self.publish()
            let update: (Progress) -> Void = { value in DispatchQueue.main.async { progress(value) } }
            let result: Result<Snapshot,Error>
            do { try operation.check(); try body(operation,update); result = .success(self.snapshot) }
            catch {
                self.lock.lock(); self.issues.insert(String(describing:error),at:0); self.lock.unlock(); result = .failure(error)
            }
            self.lock.lock(); self.busy = false; self.lock.unlock(); self.publish()
            DispatchQueue.main.async { completion(result) }
        }
        return operation
    }
    @discardableResult
    func importPreparedFolder(_ folder: URL, progress: @escaping(Progress)->Void,
                              completion: @escaping(Result<Snapshot,Error>)->Void) -> Operation {
        perform(progress:progress,completion:completion) { operation,update in
            let manifestURL = folder.appendingPathComponent(NativeResourceManifest.filename)
            guard Self.size(manifestURL) != nil else { throw Failure.missing(NativeResourceManifest.filename) }
            let manifest = try NativeResourceManifest.decode(Data(contentsOf: manifestURL))
            try self.install(manifest,origin:nil,operation:operation,update:update) { item in
                let source = folder.appendingPathComponent("blobs").appendingPathComponent(item.sha256)
                guard try self.matches(item,at:source,operation:operation) else { throw Failure.checksum(item.path) }
                return source
            }
        }
    }
    @discardableResult
    func cacheDevelopment(origin: URL, progress: @escaping(Progress)->Void,
                          completion: @escaping(Result<Snapshot,Error>)->Void) -> Operation {
        perform(progress:progress,completion:completion) { operation,update in
            guard let base = Self.origin(origin), base == origin || base.absoluteString+"/" == origin.absoluteString else {
                throw Failure.invalid("Choose an HTTP or HTTPS Mac asset-server origin")
            }
            let temporary = try self.download(base.appendingPathComponent("game/native/resource-manifest.json"),maximum:64*1_024*1_024,operation:operation)
            defer { try? self.files.removeItem(at:temporary) }
            let manifest = try NativeResourceManifest.decode(Data(contentsOf:temporary))
            try self.install(manifest,origin:base.absoluteString,operation:operation,update:update) { item in
                try self.download(base.appendingPathComponent("game/native/resource-blobs/\(item.sha256)"),maximum:item.bytes,operation:operation)
            }
        }
    }
    private func install(_ manifest: NativeResourceManifest, origin:String?, operation: Operation,
                         update: @escaping(Progress)->Void,
                         acquire: (NativeResourceManifest.Resource)throws->URL) throws {
        var completed: Int64 = 0
        let staging = root.appendingPathComponent("staging")
        for (index,item) in manifest.resources.enumerated() {
            try operation.check()
            update(Progress(phase:"Verifying resources",completedFiles:index,totalFiles:manifest.resources.count,
                            completedBytes:completed,totalBytes:manifest.totalBytes,currentPath:item.path))
            let target = blobURL(item.sha256)
            if !(try matches(item,at:target,operation:operation)) {
                let source = try acquire(item)
                let copy = staging.appendingPathComponent(UUID().uuidString+".partial")
                defer { try? files.removeItem(at:copy) }
                // Streaming downloads already live under this app-owned staging root.
                let downloaded = source.deletingLastPathComponent().standardizedFileURL == staging.standardizedFileURL
                defer { if downloaded { try? files.removeItem(at:source) } }
                try copyResource(from:source,to:copy,operation:operation)
                guard try matches(item,at:copy,operation:operation) else { throw Failure.checksum(item.path) }
                try operation.check()
                if files.fileExists(atPath:target.path) { try files.removeItem(at:target) }
                try files.moveItem(at:copy,to:target)
            }
            lock.lock(); cacheSizes[item.sha256] = item.bytes; let sizes = cacheSizes; lock.unlock()
            if index % 32 == 0 || index == manifest.resources.count-1 {
                try JSONEncoder().encode(sizes).write(to:root.appendingPathComponent("cache-index.json"),options:.atomic)
                try JSONSerialization.data(withJSONObject:["contentID":manifest.contentID,"verifiedFiles":index+1,"totalFiles":manifest.resources.count]).write(to:root.appendingPathComponent("checkpoint.json"),options:.atomic)
            }
            completed += item.bytes
        }
        try operation.check()
        try validateBootstrap(manifest)
        update(Progress(phase:"Validating native resource graph",completedFiles:manifest.resources.count,totalFiles:manifest.resources.count,
                        completedBytes:completed,totalBytes:manifest.totalBytes,currentPath:nil))
        let validatedBy=try validateRuntime(manifest,operation:operation)
        try operation.check()
        // Catalogue and origin change at one commit point. A failed/cancelled
        // import cannot make an older host use a different package's entries.
        try JSONEncoder().encode(Receipt(manifest:manifest,developmentOrigin:origin,validationIdentity:validatedBy)).write(to:root.appendingPathComponent("active.json"),options:.atomic)
        lock.lock(); catalogue = manifest; entries = Dictionary(uniqueKeysWithValues:manifest.resources.map { ($0.path,$0) }); usable = true; receiptValidationIdentity=validatedBy; settings.developmentOrigin=origin; lock.unlock()
        update(Progress(phase:"Prepared installation verified",completedFiles:manifest.resources.count,totalFiles:manifest.resources.count,
                        completedBytes:completed,totalBytes:manifest.totalBytes,currentPath:nil))
    }
    private func validateRuntime(_ manifest:NativeResourceManifest,operation:Operation)throws->String {
        lock.lock();let validator=runtimeValidator,identity=validationIdentity;lock.unlock()
        guard let validator,let identity,Self.validValidationIdentity(identity) else{throw Failure.invalid("Native runtime validation is unavailable; extracted files alone are not a playable installation")}
        let indexed=Dictionary(uniqueKeysWithValues:manifest.resources.map{($0.path,$0)})
        try validator(manifest,{path in
            try operation.check()
            guard let item=indexed[path] else{throw Failure.missing(path)}
            return self.blobURL(item.sha256)
        })
        return identity
    }
    private func copyResource(from source:URL,to target:URL,operation:Operation) throws {
        let input=try FileHandle(forReadingFrom:source);defer{try? input.close()}
        guard files.createFile(atPath:target.path,contents:nil) else {throw Failure.invalid("Cannot create staged resource")}
        let output=try FileHandle(forWritingTo:target);defer{try? output.close()}
        while let data=try input.read(upToCount:1_024*1_024),!data.isEmpty {
            try operation.check();try output.write(contentsOf:data)
        }
        try output.synchronize()
    }
    private func validateBootstrap(_ manifest: NativeResourceManifest) throws {
        for item in manifest.resources where NativeResourceManifest.requiredPaths.contains(item.path) && item.path.hasSuffix(".json") {
            let object = try JSONSerialization.jsonObject(with:Data(contentsOf:blobURL(item.sha256)))
            guard let dictionary = object as? [String:Any], !dictionary.isEmpty else {
                throw Failure.invalid("Native bootstrap metadata is not an object: \(item.path)")
            }
        }
        guard manifest.resources.contains(where: { $0.path.hasPrefix("game/world/") && $0.path.hasSuffix(".bin") && !$0.path.hasSuffix(".col.bin") }),
              manifest.resources.contains(where: { $0.path.hasPrefix("game/world/") && $0.path.hasSuffix(".png") }) else {
            throw Failure.invalid("Prepared installation contains no native world geometry/atlas pair")
        }
    }
    @discardableResult
    func verifyInstalled(progress: @escaping(Progress)->Void,
                         completion: @escaping(Result<Snapshot,Error>)->Void) -> Operation {
        perform(progress:progress,completion:completion) { operation,update in
            self.lock.lock(); let manifest = self.catalogue; self.lock.unlock()
            guard let manifest else { throw Failure.invalid("No prepared installation has been committed") }
            var bytes: Int64 = 0, failures: [String] = []
            for (index,item) in manifest.resources.enumerated() {
                try operation.check()
                if !(try self.matches(item,at:self.blobURL(item.sha256),operation:operation)) { failures.append(item.path) }
                bytes += item.bytes
                update(Progress(phase:"Checking installed resources",completedFiles:index+1,totalFiles:manifest.resources.count,
                                completedBytes:bytes,totalBytes:manifest.totalBytes,currentPath:item.path))
            }
            self.lock.lock(); self.usable = false; self.issues = failures; self.lock.unlock()
            guard failures.isEmpty else { throw Failure.invalid("Repair required: "+failures.prefix(12).joined(separator:", ")) }
            try self.validateBootstrap(manifest)
            update(Progress(phase:"Validating native resource graph",completedFiles:manifest.resources.count,totalFiles:manifest.resources.count,
                            completedBytes:bytes,totalBytes:manifest.totalBytes,currentPath:nil))
            let validatedBy=try self.validateRuntime(manifest,operation:operation)
            try operation.check()
            self.lock.lock();let origin=self.settings.developmentOrigin;self.lock.unlock()
            try JSONEncoder().encode(Receipt(manifest:manifest,developmentOrigin:origin,validationIdentity:validatedBy)).write(to:self.root.appendingPathComponent("active.json"),options:.atomic)
            self.lock.lock(); self.usable = true;self.receiptValidationIdentity=validatedBy; self.lock.unlock()
        }
    }
    private func download(_ url: URL, maximum: Int64, operation: Operation) throws -> URL {
        try operation.check()
        let completed = DispatchSemaphore(value:0), resultLock = NSLock()
        var output: Result<URL,Error>?
        var request = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:60)
        request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
        let task = session.downloadTask(with:request) { temporary,response,error in
            let result: Result<URL,Error>
            do {
                try operation.check()
                if let error { throw error }
                guard let response = response as? HTTPURLResponse else { throw Failure.invalid("Missing resource response") }
                guard response.statusCode == 200 else { throw Failure.http(response.statusCode) }
                guard Self.origin(response.url ?? url) == Self.origin(url) else { throw Failure.invalid("Resource server redirected to another origin") }
                guard let temporary,let length = Self.size(temporary), length > 0,length <= maximum else { throw Failure.invalid("Resource transfer exceeds its declared size") }
                let location = self.root.appendingPathComponent("staging/\(UUID().uuidString).download")
                try self.files.moveItem(at:temporary,to:location); result = .success(location)
            } catch { result = .failure(error) }
            resultLock.lock(); output = result; resultLock.unlock(); completed.signal()
        }
        operation.attach(task); task.resume(); completed.wait(); operation.attach(nil)
        resultLock.lock(); let value = output; resultLock.unlock()
        guard let value else { throw Failure.invalid("Resource transfer ended without a result") }
        return try value.get()
    }
}
