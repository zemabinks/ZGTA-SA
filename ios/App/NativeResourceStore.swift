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
    /// A read-only fence for asynchronous optional resource consumers. A repair
    /// or same-content replacement still changes the admission generation.
    struct RuntimeBinding: Equatable {
        let generation: UUID
        let mode: Mode
        let contentID: String?
        let developmentOrigin: String?
        let playable: Bool
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
    typealias RuntimeDataReader = (URL)throws->Data
    private struct Receipt: Codable {
        let manifest: NativeResourceManifest
        let developmentOrigin: String?
        let validationIdentity:String?
        // Optional additions preserve readable, already-verified v1 receipts.
        let admissionID:String?
        let invalidAdmission:Bool?
        let invalidDigests:[String]?
    }
    private struct InvalidAdmission:Codable {
        let schema:Int
        let key:String
        let digests:[String]
    }
    private struct FileIdentity:Equatable {
        let inode:UInt64,device:UInt64,size:Int64
        let modified:Date
    }
    private struct ReadAdmission {
        let generation:UUID
        let key:String?
        let file:FileIdentity?
    }
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
    private var receiptAdmissionID:String?
    private var admissionGeneration=UUID()
    private var admissionBlocked=false
    private var invalidDigests=Set<String>()
    private var faultRevision:UInt64=0
    private let session: URLSession
    private let runtimeDataReader:RuntimeDataReader

    init(root: URL, session: URLSession = .shared,validationIdentity:String?=nil,runtimeValidator:RuntimeValidator?=nil,
         runtimeDataReader:RuntimeDataReader?=nil) {
        self.root = root; self.session = session;self.validationIdentity=validationIdentity;self.runtimeValidator=runtimeValidator
        self.runtimeDataReader=runtimeDataReader ?? {try Data(contentsOf:$0)}
        do {
            try files.createDirectory(at: root.appendingPathComponent("blobs"), withIntermediateDirectories: true)
            try files.createDirectory(at: root.appendingPathComponent("staging"), withIntermediateDirectories: true)
            var location = root; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? location.setResourceValues(values)
            if let bytes = try? Data(contentsOf: root.appendingPathComponent("settings.json")),
               let saved = try? JSONDecoder().decode(Settings.self, from: bytes) { settings = saved }
            let active=root.appendingPathComponent("active.json"),quarantined=root.appendingPathComponent("active.unverified.json")
            let receiptURL=files.fileExists(atPath:active.path) ? active:quarantined
            if let bytes = try? Data(contentsOf: receiptURL) {
                let receipt = try JSONDecoder().decode(Receipt.self, from: bytes)
                let saved = receipt.manifest; try saved.validate()
                if let id=receipt.admissionID,UUID(uuidString:id)==nil{throw Failure.invalid("Invalid prepared admission identity")}
                if let bad=receipt.invalidDigests, bad.count>200_000 || !bad.allSatisfy(NativeResourceManifest.validDigest){throw Failure.invalid("Invalid prepared admission diagnostics")}
                settings.developmentOrigin = receipt.developmentOrigin
                receiptValidationIdentity=receipt.validationIdentity
                receiptAdmissionID=receipt.admissionID
                admissionBlocked=receipt.invalidAdmission==true || receiptURL==quarantined
                invalidDigests=Set(receipt.invalidDigests ?? [])
                catalogue = saved; entries = Dictionary(uniqueKeysWithValues: saved.resources.map { ($0.path, $0) })
                // Import/verify commits this receipt only after complete validation.
                // Reads still revalidate actual bytes before returning them.
                refreshInvalidAdmission()
                let missing=saved.resources.filter{Self.size(blobURL($0.sha256)) != $0.bytes}
                if !missing.isEmpty{admissionBlocked=true;invalidDigests.formUnion(missing.map(\.sha256));persistInvalidAdmission()}
                usable = !admissionBlocked && admissionStorageWritable() && Self.validValidationIdentity(validationIdentity) && runtimeValidator != nil && receipt.validationIdentity==validationIdentity && missing.isEmpty
                if !usable { issues = ["Installation is incomplete. Verify or repair it from the existing resource source."] }
            }
            if let data = try? Data(contentsOf: root.appendingPathComponent("cache-index.json")),
               let index = try? JSONDecoder().decode([String: Int64].self, from: data) {
                cacheSizes = index.filter { NativeResourceManifest.validDigest($0.key) && Self.size(blobURL($0.key)) == $0.value }
            }
            for digest in invalidDigests{cacheSizes.removeValue(forKey:digest)}
            if !invalidDigests.isEmpty{try? JSONEncoder().encode(cacheSizes).write(to:root.appendingPathComponent("cache-index.json"),options:.atomic)}
        } catch { issues = [String(describing: error)] }
    }
    var snapshot: Snapshot { lock.lock(); defer { lock.unlock() }; return state() }
    var runtimeBinding: RuntimeBinding {
        lock.lock(); defer { lock.unlock() }
        return .init(generation:admissionGeneration,mode:settings.mode,contentID:catalogue?.contentID,
            developmentOrigin:settings.developmentOrigin,playable:usable)
    }
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
        refreshInvalidAdmission()
        let missing=catalogue?.resources.filter{Self.size(blobURL($0.sha256)) != $0.bytes} ?? []
        if !missing.isEmpty {
            admissionBlocked=true;invalidDigests.formUnion(missing.map(\.sha256))
            for digest in invalidDigests{cacheSizes.removeValue(forKey:digest)}
            persistInvalidAdmission()
            try? JSONEncoder().encode(cacheSizes).write(to:root.appendingPathComponent("cache-index.json"),options:.atomic)
        }
        usable = !admissionBlocked && admissionStorageWritable() && receiptValidationIdentity==identity && catalogue != nil && missing.isEmpty
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
        do {
            let actual = try digest(url, operation: operation)
            return actual.0 == item.bytes && actual.1 == item.sha256
        } catch {
            try operation?.check()
            return false
        }
    }
    private static func admissionKey(_ content:String,_ id:String?)->String {
        SHA256.hash(data:Data((content+"\u{0}"+(id ?? "legacy-v1")).utf8)).map{String(format:"%02x",$0)}.joined()
    }
    private var admissionKey:String? {catalogue.map{Self.admissionKey($0.contentID,receiptAdmissionID)}}
    private func markerURL(_ key:String)->URL {root.appendingPathComponent("invalid-admissions/\(key).json")}
    private func emergencyMarkerURL(_ key:String)->URL {root.appendingPathComponent("staging/admission-invalid-\(key).json")}
    private func metadataEntryExists(_ url:URL)->Bool {
        files.fileExists(atPath:url.path) || (try? files.destinationOfSymbolicLink(atPath:url.path)) != nil
    }
    private static func fileIdentity(_ url:URL)->FileIdentity? {
        guard let size=Self.size(url),let a=try? FileManager.default.attributesOfItem(atPath:url.path),
              let inode=a[.systemFileNumber]as?NSNumber,let device=a[.systemNumber]as?NSNumber,
              let modified=a[.modificationDate]as?Date else{return nil}
        return FileIdentity(inode:inode.uint64Value,device:device.uint64Value,size:size,modified:modified)
    }
    private func admissionStorageWritable()->Bool {
        let probe=root.appendingPathComponent("staging/\(UUID().uuidString).admission-probe")
        defer{try? files.removeItem(at:probe)}
        do{try Data([0]).write(to:probe,options:.withoutOverwriting);return true}catch{return false}
    }
    /// Read failures and malformed markers are blocking, never a request to
    /// discard the receipt or trust same-sized files again.
    private func refreshInvalidAdmission() {
        guard let key=admissionKey else{return}
        let directory=root.appendingPathComponent("invalid-admissions")
        if metadataEntryExists(directory) {
            let values=try? directory.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            if values?.isDirectory != true || values?.isSymbolicLink==true || !files.isReadableFile(atPath:directory.path) {
                admissionBlocked=true;invalidDigests.formUnion(entries.values.map(\.sha256))
            }
        }
        for url in [markerURL(key),emergencyMarkerURL(key)] where metadataEntryExists(url) {
            do {
                guard let size=Self.size(url),size<=32*1_024*1_024 else{throw Failure.invalid("Invalid admission marker")}
                let marker=try JSONDecoder().decode(InvalidAdmission.self,from:Data(contentsOf:url))
                guard marker.schema==1,marker.key==key,marker.digests.count<=200_000,
                      marker.digests.allSatisfy(NativeResourceManifest.validDigest) else{throw Failure.invalid("Invalid admission marker")}
                admissionBlocked=true;invalidDigests.formUnion(marker.digests)
            }catch{admissionBlocked=true;invalidDigests.formUnion(entries.values.map(\.sha256))}
        }
        if admissionBlocked{usable=false}
        for digest in invalidDigests{cacheSizes.removeValue(forKey:digest)}
    }
    /// Caller owns the Store lock (or is still constructing the Store).
    /// Emergency staging metadata and a blocked receipt preserve admission if
    /// the normal marker cannot be written. No original/good blob is removed.
    private func persistInvalidAdmission() {
        guard let key=admissionKey,let manifest=catalogue else{return}
        let marker=InvalidAdmission(schema:1,key:key,digests:invalidDigests.sorted())
        do {
            try files.createDirectory(at:root.appendingPathComponent("invalid-admissions"),withIntermediateDirectories:true)
            let directory=root.appendingPathComponent("invalid-admissions")
            let values=try directory.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard values.isDirectory==true,values.isSymbolicLink != true else{throw Failure.invalid("Invalid admission marker directory")}
            try JSONEncoder().encode(marker).write(to:markerURL(key),options:.atomic)
            return
        } catch {
            issues.append("Resource admission is blocked; the normal invalidation marker could not be saved.")
        }
        if let data=try? JSONEncoder().encode(marker) {
            do{try data.write(to:emergencyMarkerURL(key),options:.atomic);return}catch{}
        }
        let active=root.appendingPathComponent("active.json")
        guard let bytes=try? Data(contentsOf:active),let disk=try? JSONDecoder().decode(Receipt.self,from:bytes),
              Self.admissionKey(disk.manifest.contentID,disk.admissionID)==key else{return}
        let blocked=Receipt(manifest:manifest,developmentOrigin:settings.developmentOrigin,validationIdentity:receiptValidationIdentity,
                            admissionID:receiptAdmissionID,invalidAdmission:true,invalidDigests:invalidDigests.sorted())
        do{try JSONEncoder().encode(blocked).write(to:active,options:.atomic)}catch{
            let quarantine=root.appendingPathComponent("active.unverified.json")
            if !files.fileExists(atPath:quarantine.path){try? files.moveItem(at:active,to:quarantine)}
        }
    }
    private func runtimeFault(_ item:NativeResourceManifest.Resource,read:ReadAdmission) {
        lock.lock()
        // A read can finish after a complete replacement/repair, or after its
        // old file was atomically replaced before commit. Neither may poison
        // the new bytes/admission or evict their accounting.
        guard read.generation==admissionGeneration,read.key==admissionKey,entries[item.path]==item,
              read.file==Self.fileIdentity(blobURL(item.sha256)) else{lock.unlock();return}
        // A second Store/process may have committed a replacement receipt.
        // Its persisted generation also owns cache accounting and admission.
        let active=root.appendingPathComponent("active.json")
        if let size=Self.size(active),size<=80*1_024*1_024,
           let bytes=try? Data(contentsOf:active),let receipt=try? JSONDecoder().decode(Receipt.self,from:bytes),
           Self.admissionKey(receipt.manifest.contentID,receipt.admissionID) != read.key {lock.unlock();return}
        admissionBlocked=true;usable=false;faultRevision &+= 1
        invalidDigests.insert(item.sha256);cacheSizes.removeValue(forKey:item.sha256)
        issues=["Resource verification failed: \(item.path). Verify or repair the existing installation."]
        persistInvalidAdmission()
        try? JSONEncoder().encode(cacheSizes).write(to:root.appendingPathComponent("cache-index.json"),options:.atomic)
        lock.unlock();publish()
    }
    /// Runtime lookup never accepts a file merely because it has a hash-shaped name.
    func localResource(for request: URL,maximumBytes:Int64=128*1_024*1_024) throws -> (Data,NativeResourceManifest.Resource)? {
        let path = request.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        lock.lock(); let mode = settings.mode, item = entries[path], origin = settings.developmentOrigin,verified=usable,generation=admissionGeneration,key=admissionKey; lock.unlock()
        if mode == .installed,!verified{throw Failure.invalid("Installed resources need native runtime verification")}
        guard Self.origin(request) != nil else{if mode == .installed{throw Failure.invalid("Unsupported installed resource URL")};return nil}
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
        let read=ReadAdmission(generation:generation,key:key,file:Self.fileIdentity(location))
        guard Self.size(location) == item.bytes else {
            runtimeFault(item,read:read)
            if mode == .installed { throw Failure.missing(path) }; return nil
        }
        let data:Data
        do{data=try runtimeDataReader(location)}catch{
            runtimeFault(item,read:read)
            if mode == .installed{throw Failure.missing(path)};return nil
        }
        guard Int64(data.count) == item.bytes,
              SHA256.hash(data: data).map({ String(format: "%02x",$0) }).joined() == item.sha256 else {
            runtimeFault(item,read:read)
            if mode == .installed{throw Failure.checksum(path)};return nil
        }
        return (data,item)
    }
    func installedURL(for request: URL) throws -> URL? {
        let path=request.path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        lock.lock();let mode=settings.mode,item=entries[path],origin=settings.developmentOrigin,verified=usable,generation=admissionGeneration,key=admissionKey;lock.unlock()
        if mode == .installed,!verified{throw Failure.invalid("Installed resources need native runtime verification")}
        guard Self.origin(request) != nil else{if mode == .installed{throw Failure.invalid("Unsupported installed resource URL")};return nil}
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
        let read=ReadAdmission(generation:generation,key:key,file:Self.fileIdentity(url))
        guard try matches(item,at:url,operation:nil) else{
            runtimeFault(item,read:read)
            if mode == .installed{if Self.size(url) != item.bytes{throw Failure.missing(path)};throw Failure.checksum(path)};return nil
        }
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
            lock.lock()
            let activeRead:(NativeResourceManifest.Resource,ReadAdmission)?
            if let current=entries[item.path],current.sha256==item.sha256,current.bytes==item.bytes {
                activeRead=(current,ReadAdmission(generation:admissionGeneration,key:admissionKey,file:Self.fileIdentity(target)))
            }else{activeRead=nil}
            lock.unlock()
            if !(try matches(item,at:target,operation:operation)) {
                if let activeRead{runtimeFault(activeRead.0,read:activeRead.1)}
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
        try commitAdmission(manifest,origin:origin,validatedBy:validatedBy)
        update(Progress(phase:"Prepared installation verified",completedFiles:manifest.resources.count,totalFiles:manifest.resources.count,
                        completedBytes:completed,totalBytes:manifest.totalBytes,currentPath:nil))
    }
    private func commitAdmission(_ manifest:NativeResourceManifest,origin:String?,validatedBy:String,
                                 expected:(UUID,UInt64)?=nil,verifiedSizes:[String:Int64]=[:])throws {
        lock.lock();defer{lock.unlock()}
        if let expected {
            guard admissionGeneration==expected.0,faultRevision==expected.1 else {
                throw Failure.invalid("Resources changed during verification. Verify the existing installation again.")
            }
        }
        // Repair only app-owned admission metadata after full byte/runtime
        // verification. Malformed storage can never be treated as a clear flag.
        let directory=root.appendingPathComponent("invalid-admissions")
        if metadataEntryExists(directory) {
            let values=try? directory.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            if values?.isDirectory != true || values?.isSymbolicLink==true || !files.isReadableFile(atPath:directory.path) || !files.isWritableFile(atPath:directory.path) {
                // Preserve a durable block for the old receipt BEFORE moving
                // malformed metadata. A failed/crashed commit must not erase
                // its only invalidation evidence.
                if let key=admissionKey {
                    admissionBlocked=true;usable=false
                    let marker=InvalidAdmission(schema:1,key:key,digests:invalidDigests.sorted())
                    try JSONEncoder().encode(marker).write(to:emergencyMarkerURL(key),options:.atomic)
                }
                try files.moveItem(at:directory,to:root.appendingPathComponent("staging/\(UUID().uuidString).invalid-admission-metadata"))
            }
        }
        try files.createDirectory(at:directory,withIntermediateDirectories:true)
        guard admissionStorageWritable() else{throw Failure.invalid("Cannot persist prepared resource admission")}
        let oldKey=admissionKey,newID=UUID().uuidString
        let receipt=Receipt(manifest:manifest,developmentOrigin:origin,validationIdentity:validatedBy,
                            admissionID:newID,invalidAdmission:false,invalidDigests:nil)
        for(digest,size)in verifiedSizes{cacheSizes[digest]=size}
        try JSONEncoder().encode(cacheSizes).write(to:root.appendingPathComponent("cache-index.json"),options:.atomic)
        // New receipt/identity is published first, while runtime fault reports
        // are serialized by the same lock. Old keyed markers cannot poison it.
        try JSONEncoder().encode(receipt).write(to:root.appendingPathComponent("active.json"),options:.atomic)
        catalogue=manifest;entries=Dictionary(uniqueKeysWithValues:manifest.resources.map{($0.path,$0)})
        receiptAdmissionID=newID;receiptValidationIdentity=validatedBy;settings.developmentOrigin=origin
        admissionGeneration=UUID();admissionBlocked=false;invalidDigests=[];usable=true;issues=[]
        if let oldKey {
            for url in [markerURL(oldKey),emergencyMarkerURL(oldKey)] where Self.size(url) != nil {try? files.removeItem(at:url)}
        }
        let quarantine=root.appendingPathComponent("active.unverified.json")
        if Self.size(quarantine) != nil{try? files.removeItem(at:quarantine)}
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
            self.lock.lock(); let manifest = self.catalogue,expected=(self.admissionGeneration,self.faultRevision); self.lock.unlock()
            guard let manifest else { throw Failure.invalid("No prepared installation has been committed") }
            var bytes: Int64 = 0, failures: [String] = []
            var verifiedSizes=[String:Int64]()
            for (index,item) in manifest.resources.enumerated() {
                try operation.check()
                let read=ReadAdmission(generation:expected.0,key:Self.admissionKey(manifest.contentID,self.receiptAdmissionID),file:Self.fileIdentity(self.blobURL(item.sha256)))
                if !(try self.matches(item,at:self.blobURL(item.sha256),operation:operation)) { failures.append(item.path);self.runtimeFault(item,read:read) }
                else{verifiedSizes[item.sha256]=item.bytes}
                bytes += item.bytes
                update(Progress(phase:"Checking installed resources",completedFiles:index+1,totalFiles:manifest.resources.count,
                                completedBytes:bytes,totalBytes:manifest.totalBytes,currentPath:item.path))
            }
            self.lock.lock(); self.usable = false; self.issues = failures; self.lock.unlock()
            guard failures.isEmpty else { throw Failure.invalid("Repair required: "+failures.prefix(12).joined(separator:", ")) }
            let validatedBy:String
            do {
                try self.validateBootstrap(manifest)
                update(Progress(phase:"Validating native resource graph",completedFiles:manifest.resources.count,totalFiles:manifest.resources.count,
                                completedBytes:bytes,totalBytes:manifest.totalBytes,currentPath:nil))
                validatedBy=try self.validateRuntime(manifest,operation:operation)
                try operation.check()
            }catch{
                if !operation.isCancelled {
                    self.lock.lock()
                    if self.admissionGeneration==expected.0{self.admissionBlocked=true;self.usable=false;self.faultRevision &+= 1;self.persistInvalidAdmission()}
                    self.lock.unlock()
                }
                throw error
            }
            self.lock.lock();let origin=self.settings.developmentOrigin;self.lock.unlock()
            try self.commitAdmission(manifest,origin:origin,validatedBy:validatedBy,expected:expected,verifiedSizes:verifiedSizes)
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
