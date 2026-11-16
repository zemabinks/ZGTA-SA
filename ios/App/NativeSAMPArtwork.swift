import Foundation
import CryptoKit

/// Independently authored 0.3.DL artwork wire/cache owner. Wire fields are
/// documented by open.mp Shared/NetCode/custommodels.hpp and its CustomModels
/// component. Download verification is CRC32, not MD5. A downloaded DFF/TXD
/// still needs a native importer before a custom model can be rendered.
final class NativeSAMPArtwork {
    enum Failure: Error, Equatable {
        case malformed, unsupported, limit, conflictingCatalog, unsolicitedURL
        case invalidURL, incomplete, http(Int), size, checksum, io, cancelled, cacheFull
    }
    enum Kind: UInt8, Hashable { case dff = 1, txd = 2
        var requestRPC: UInt8 { self == .dff ? 181:182 }
        var fileExtension: String { self == .dff ? "dff":"txd" }
    }
    struct File: Hashable { let kind: Kind; let checksum: UInt32; let size: UInt32 }
    struct Model: Equatable {
        let pool: UInt32, count: UInt32
        let type: UInt8
        let world, baseID, customID: Int32
        let dff, txd: File
        let timeOn, timeOff: UInt8
        func applies(to world: Int32) -> Bool { type == 1 || self.world == -1 || self.world == world }
        static func decode(_ data: Data, maximumFileBytes: UInt32 = 64 << 20) throws -> Model {
            guard data.count == 39 else { throw Failure.malformed }
            var r = Reader(data)
            let pool=r.u32(), count=r.u32(), type=r.u8(), world=r.i32(), base=r.i32(), custom=r.i32()
            let dffCRC=r.u32(), txdCRC=r.u32(), dffSize=r.u32(), txdSize=r.u32(), on=r.u8(), off=r.u8()
            guard (1...4096).contains(count), pool < count else { throw Failure.limit }
            guard type == 1 || type == 2 else { throw Failure.unsupported }
            guard type == 1 ? (20001...30000).contains(custom):(-30000 ... -1000).contains(custom) else { throw Failure.malformed }
            guard dffSize > 0, txdSize > 0, dffSize <= maximumFileBytes, txdSize <= maximumFileBytes else { throw Failure.limit }
            return Model(pool:pool,count:count,type:type,world:world,baseID:base,customID:custom,
                dff:File(kind:.dff,checksum:dffCRC,size:dffSize),txd:File(kind:.txd,checksum:txdCRC,size:txdSize),timeOn:on,timeOff:off)
        }
    }
    struct RPC { let id: UInt8; let payload: Data }
    struct Download { let file: File; let url: URL }
    struct Receipt { let file: File; let url: URL; let md5: String; let fromCache: Bool }
    private struct Reader {
        let bytes: [UInt8]; var offset=0
        init(_ data:Data) { bytes=Array(data) }
        mutating func u8()->UInt8 { defer{offset+=1};return bytes[offset] }
        mutating func u32()->UInt32 { var v:UInt32=0;for n in 0..<4{v |= UInt32(u8()) << (n*8)};return v }
        mutating func i32()->Int32 { Int32(bitPattern:u32()) }
    }
    private(set) var models: [UInt32: Model] = [:]
    private(set) var acknowledged = false
    private(set) var world: Int32?
    private var total: UInt32?
    private var requested=Set<File>(), downloading=Set<File>(), verified=Set<File>()
    private var finishSent=false
    var catalogComplete: Bool { total.map { models.count == Int($0) } ?? true }
    var requiredFiles: Set<File> {
        guard let world else { return [] }
        return Set(models.values.filter{$0.applies(to:world)}.flatMap{[$0.dff,$0.txd]})
    }
    func reset() { models.removeAll();total=nil;world=nil;requested.removeAll();downloading.removeAll();verified.removeAll();finishSent=false;acknowledged=false }
    func receiveModel(_ data:Data) throws {
        let model=try Model.decode(data)
        if let total, total != model.count { throw Failure.conflictingCatalog }
        if let previous=models[model.pool], previous != model { throw Failure.conflictingCatalog }
        if models.values.contains(where:{$0.pool != model.pool && $0.customID == model.customID}) { throw Failure.conflictingCatalog }
        let files=models.values.flatMap{[$0.dff,$0.txd]}
        for file in [model.dff,model.txd] where files.contains(where:{$0.kind == file.kind && $0.checksum == file.checksum && $0.size != file.size}) { throw Failure.conflictingCatalog }
        total=model.count;models[model.pool]=model
    }
    /// Invoke at the server's virtual-world download boundary, including an
    /// empty catalog. An empty-world transition still has a real184/185 pair.
    func begin(world:Int32) { self.world=world;requested.removeAll();downloading.removeAll();finishSent=false;acknowledged=false }
    func requests(limit:Int=16,isCached:(File)->Bool={_ in false})->[RPC] {
        guard world != nil,catalogComplete,!finishSent else{return []}
        let files=requiredFiles.sorted { $0.kind.rawValue == $1.kind.rawValue ? $0.checksum < $1.checksum:$0.kind.rawValue < $1.kind.rawValue }
        var out:[RPC]=[]
        for file in files {
            if isCached(file) {verified.insert(file)}
            guard !verified.contains(file),!requested.contains(file),out.count < max(0,min(64,limit)) else{continue}
            var value=file.checksum.littleEndian
            out.append(RPC(id:file.kind.requestRPC,payload:withUnsafeBytes(of:&value){Data($0)}));requested.insert(file)
        }
        return out
    }
    func receiveURL(_ data:Data) throws -> Download {
        guard data.count>=7,data.count<=262 else{throw Failure.malformed}
        var r=Reader(data)
        guard r.u8()==6,let kind=Kind(rawValue:r.u8()) else{throw Failure.unsupported}
        let checksum=r.u32(), length=Int(r.u8())
        guard data.count == 7+length,let text=String(bytes:r.bytes[7...],encoding:.utf8),let url=URL(string:text),Self.permitted(url) else{throw Failure.invalidURL}
        guard let file=requested.first(where:{$0.kind == kind && $0.checksum == checksum}),!downloading.contains(file),requiredFiles.contains(file) else{throw Failure.unsolicitedURL}
        downloading.insert(file);return Download(file:file,url:url)
    }
    func completed(_ receipt:Receipt) throws {
        guard requiredFiles.contains(receipt.file),requested.contains(receipt.file) else{throw Failure.unsolicitedURL}
        verified.insert(receipt.file);requested.remove(receipt.file);downloading.remove(receipt.file)
    }
    func retry(_ file:File) { requested.remove(file);downloading.remove(file) }
    func finishRequest() throws -> RPC? {
        guard world != nil,catalogComplete,requiredFiles.isSubset(of:verified),requested.isEmpty,downloading.isEmpty else{throw Failure.incomplete}
        guard !finishSent else{return nil};finishSent=true;return RPC(id:184,payload:Data())
    }
    func receiveCompleted(_ data:Data) throws {
        guard finishSent,data.isEmpty else{throw Failure.unsolicitedURL};acknowledged=true
    }
    static func permitted(_ url:URL)->Bool {
        guard let scheme=url.scheme?.lowercased(),["http","https"].contains(scheme),let host=url.host,!host.isEmpty,
              url.user==nil,url.password==nil,url.fragment==nil else{return false}
        return url.port.map{(1...65535).contains($0)} ?? true
    }
    struct CRC32 {
        private static let table:[UInt32]=(0..<256).map{value in var x=UInt32(value);for _ in 0..<8{x = (x >> 1) ^ (x & 1 == 1 ? 0xedb88320:0)};return x}
        private var raw:UInt32=0xffffffff
        mutating func update(_ data:Data){for byte in data{raw=Self.table[Int((raw ^ UInt32(byte)) & 255)] ^ (raw >> 8)}}
        var value:UInt32{raw ^ 0xffffffff}
        static func checksum(_ data:Data)->UInt32{var crc=CRC32();crc.update(data);return crc.value}
    }
}

/// Bounded, cookie-free native HTTP transfer. Cache hits are revalidated;
/// Content-Length is advisory and the streamed byte limit remains enforced.
final class NativeSAMPArtworkCache {
    typealias Artwork=NativeSAMPArtwork
    typealias Completion=(Result<Artwork.Receipt,Error>)->Void
    private struct Pending {let file:Artwork.File,url:URL;let completion:Completion;let epoch:UInt64}
    private let queue=DispatchQueue(label:"ZGTA.SAMPArtwork.cache")
    private let folder:URL,maximumFileBytes:UInt32,maximumCacheBytes:UInt64
    private var jobs:[UUID:Transfer]=[:],pending:[Pending]=[],epoch:UInt64=0
    init(root:URL,namespace:String,maximumFileBytes:UInt32=64 << 20,maximumCacheBytes:UInt64=512 << 20)throws {
        self.maximumFileBytes=maximumFileBytes;self.maximumCacheBytes=maximumCacheBytes
        let name=SHA256.hash(data:Data(namespace.utf8)).map{String(format:"%02x",$0)}.joined()
        folder=root.appendingPathComponent(name,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        guard !((try folder.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink ?? false) else{throw Artwork.Failure.io}
    }
    private func destination(_ file:Artwork.File)->URL {folder.appendingPathComponent(String(format:"%08x-%u.%@",file.checksum,file.size,file.kind.fileExtension))}
    private func verified(_ file:Artwork.File)->Artwork.Receipt? {
        let url=destination(file)
        guard let values=try? url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey]),values.isRegularFile==true,values.isSymbolicLink != true,values.fileSize==Int(file.size),
              let input=try? FileHandle(forReadingFrom:url) else{return nil}
        defer{try? input.close()};var crc=Artwork.CRC32(),md5=Insecure.MD5(),count=0
        do {while let part=try input.read(upToCount:65536),!part.isEmpty {count+=part.count;if count>Int(file.size){return nil};crc.update(part);md5.update(data:part)}}catch{return nil}
        guard count==Int(file.size),crc.value==file.checksum else{return nil}
        return Artwork.Receipt(file:file,url:url,md5:md5.finalize().map{String(format:"%02x",$0)}.joined(),fromCache:true)
    }
    func fetch(_ download:Artwork.Download,completion:@escaping Completion) {
        queue.async {
            guard download.file.size>0,download.file.size<=self.maximumFileBytes else{self.deliver(completion,.failure(Artwork.Failure.limit));return}
            guard Artwork.permitted(download.url) else{self.deliver(completion,.failure(Artwork.Failure.invalidURL));return}
            if let receipt=self.verified(download.file){self.deliver(completion,.success(receipt));return}
            guard self.pending.count<64 else{self.deliver(completion,.failure(Artwork.Failure.limit));return}
            self.pending.append(Pending(file:download.file,url:download.url,completion:completion,epoch:self.epoch));self.startNext()
        }
    }
    func cancelAll(){queue.async {
        self.epoch &+= 1
        let pending=self.pending;self.pending.removeAll();for task in pending{self.deliver(task.completion,.failure(Artwork.Failure.cancelled))}
        for transfer in self.jobs.values{transfer.cancel()}
    }}
    private func deliver(_ completion:@escaping Completion,_ result:Result<Artwork.Receipt,Error>){DispatchQueue.main.async{completion(result)}}
    private func cacheBytes()->UInt64 {
        let files=(try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.isRegularFileKey,.fileSizeKey,.isSymbolicLinkKey])) ?? []
        return files.reduce(0){sum,url in guard let value=try? url.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey,.isSymbolicLinkKey]),value.isRegularFile==true,value.isSymbolicLink != true,!url.lastPathComponent.hasPrefix("transfer-")else{return sum};return sum+UInt64(max(0,value.fileSize ?? 0))}
    }
    private func bytesAfterReplacing(_ file:Artwork.File)->UInt64 {
        let values=try? destination(file).resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        let replaced=values?.isRegularFile==true && values?.isSymbolicLink != true ? UInt64(max(0,values?.fileSize ?? 0)):0
        return cacheBytes()-min(cacheBytes(),replaced)+UInt64(file.size)
    }
    private func startNext(){
        while jobs.count<2,!pending.isEmpty {
            let next=pending.removeFirst()
            guard next.epoch==epoch else{deliver(next.completion,.failure(Artwork.Failure.cancelled));continue}
            if let receipt=verified(next.file){deliver(next.completion,.success(receipt));continue}
            guard bytesAfterReplacing(next.file)<=maximumCacheBytes else{deliver(next.completion,.failure(Artwork.Failure.cacheFull));continue}
            let id=UUID(),temporary=folder.appendingPathComponent("transfer-"+UUID().uuidString)
            let transfer=Transfer(file:next.file,url:next.url,temporary:temporary){result in self.queue.async {
                self.jobs.removeValue(forKey:id)
                if next.epoch != self.epoch {try? FileManager.default.removeItem(at:temporary);self.deliver(next.completion,.failure(Artwork.Failure.cancelled))}
                else {switch result {
                case .failure(let error):self.deliver(next.completion,.failure(error))
                case .success(let md5):
                    do {
                        guard self.bytesAfterReplacing(next.file)<=self.maximumCacheBytes else{throw Artwork.Failure.cacheFull}
                        let destination=self.destination(next.file)
                        if FileManager.default.fileExists(atPath:destination.path){try FileManager.default.removeItem(at:destination)}
                        try FileManager.default.moveItem(at:temporary,to:destination)
                        self.deliver(next.completion,.success(Artwork.Receipt(file:next.file,url:destination,md5:md5,fromCache:false)))
                    } catch {try? FileManager.default.removeItem(at:temporary);self.deliver(next.completion,.failure(error))}
                }}
                self.startNext()
            }}
            jobs[id]=transfer;transfer.start()
        }
    }
    private final class Transfer:NSObject,URLSessionDataDelegate {
        let file:Artwork.File,url:URL,temporary:URL
        let completion:(Result<String,Error>)->Void
        private let delegateQueue:OperationQueue={let q=OperationQueue();q.maxConcurrentOperationCount=1;return q}()
        private var session:URLSession?,task:URLSessionDataTask?,output:FileHandle?,received:UInt64=0,redirects=0,finished=false
        private var crc=Artwork.CRC32(),md5=Insecure.MD5()
        init(file:Artwork.File,url:URL,temporary:URL,completion:@escaping(Result<String,Error>)->Void){self.file=file;self.url=url;self.temporary=temporary;self.completion=completion}
        func start(){
            guard FileManager.default.createFile(atPath:temporary.path,contents:nil),let output=try? FileHandle(forWritingTo:temporary) else{finish(.failure(Artwork.Failure.io));return};self.output=output
            let config=URLSessionConfiguration.ephemeral;config.httpCookieStorage=nil;config.httpShouldSetCookies=false;config.urlCredentialStorage=nil;config.urlCache=nil;config.timeoutIntervalForRequest=20;config.timeoutIntervalForResource=90
            session=URLSession(configuration:config,delegate:self,delegateQueue:delegateQueue)
            var request=URLRequest(url:url);request.setValue("SAMP/0.3",forHTTPHeaderField:"User-Agent");request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
            task=session!.dataTask(with:request);task?.resume()
        }
        func cancel(){delegateQueue.addOperation{self.task?.cancel();self.finish(.failure(Artwork.Failure.cancelled))}}
        private func finish(_ result:Result<String,Error>){
            guard !finished else{return};finished=true;try? output?.close();output=nil
            if case .failure=result{try? FileManager.default.removeItem(at:temporary)}
            task?.cancel();task=nil;session?.invalidateAndCancel();session=nil;completion(result)
        }
        func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,completionHandler:@escaping(URLSession.ResponseDisposition)->Void){
            guard let response=response as? HTTPURLResponse else{completionHandler(.cancel);finish(.failure(Artwork.Failure.http(0)));return}
            guard response.statusCode==200 else{completionHandler(.cancel);finish(.failure(Artwork.Failure.http(response.statusCode)));return}
            guard response.expectedContentLength<0 || response.expectedContentLength==Int64(file.size) else{completionHandler(.cancel);finish(.failure(Artwork.Failure.size));return}
            completionHandler(.allow)
        }
        func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data){
            guard !finished else{return};received+=UInt64(data.count)
            guard received<=UInt64(file.size) else{finish(.failure(Artwork.Failure.size));return}
            do{try output?.write(contentsOf:data);crc.update(data);md5.update(data:data)}catch{finish(.failure(Artwork.Failure.io))}
        }
        func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){
            guard !finished else{return}
            if let error{finish(.failure(error));return}
            guard received==UInt64(file.size) else{finish(.failure(Artwork.Failure.size));return}
            guard crc.value==file.checksum else{finish(.failure(Artwork.Failure.checksum));return}
            finish(.success(md5.finalize().map{String(format:"%02x",$0)}.joined()))
        }
        func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){
            redirects+=1
            guard redirects<=4,let url=request.url,Artwork.permitted(url),!(response.url?.scheme=="https" && url.scheme=="http") else{completionHandler(nil);finish(.failure(Artwork.Failure.invalidURL));return}
            var next=request;next.setValue("SAMP/0.3",forHTTPHeaderField:"User-Agent");next.setValue("identity",forHTTPHeaderField:"Accept-Encoding");completionHandler(next)
        }
    }
}
