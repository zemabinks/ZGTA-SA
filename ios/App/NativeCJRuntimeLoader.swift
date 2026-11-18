// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// One bounded optional player-family owner. Main-queue calls/completions,
/// worker preparation, exact prepared/HTTP bytes, no GPU or skin publication.
final class NativeCJRuntimeLoader {
    struct Prepared {
        let generation: UInt64
        let sourceIdentity: String
        let profile: NativeCJProfile
        let resources: NativeCJResources.Prepared
        let plan: NativeRenderWarePedModel.Plan
    }
    enum Failure: Error { case cancelled, stale, source, limit, unavailable(Int) }
    typealias Completion = (Result<Prepared, Error>) -> Void
    private final class Context {
        let generation: UInt64, source: String, completion: Completion
        var profile: NativeCJProfile?, bytes: [String: Data] = [:], requests = Set<UUID>()
        var next = 0, preparing = false, completed = false
        private let lock = NSLock(); private var stopped = false
        init(generation: UInt64, source: String, completion: @escaping Completion) {
            self.generation=generation;self.source=source;self.completion=completion
        }
        func cancel(){lock.lock();stopped=true;lock.unlock()}
        var cancelled: Bool { lock.lock();defer{lock.unlock()};return stopped }
    }
    private let base: URL, sourceIdentity: () -> String
    private let accessProvider: (() -> NativeStockAssetAccess?)?
    private let assets: NativeSAMPStockAssetLoader
    private let worker=DispatchQueue(label:"org.zgtasa.fixed-player-prepare",qos:.utility)
    private var metadata: NativeCJMetadataTransfer?, active: Context?
    private(set) var generation: UInt64 = 1
    var isLoading: Bool { main();return active != nil }
    init(assetBaseURL: URL, sourceIdentity: @escaping () -> String,
         accessProvider: (() -> NativeStockAssetAccess?)? = nil) throws {
        dispatchPrecondition(condition:.onQueue(.main))
        guard let scheme=assetBaseURL.scheme?.lowercased(),["http","https"].contains(scheme),
              assetBaseURL.host != nil,assetBaseURL.user==nil,assetBaseURL.password==nil,
              assetBaseURL.query==nil,assetBaseURL.fragment==nil,
              assetBaseURL.path.isEmpty || assetBaseURL.path=="/" else{throw Failure.source}
        base=assetBaseURL;self.sourceIdentity=sourceIdentity;self.accessProvider=accessProvider
        var limits=NativeSAMPStockAssetLoader.Limits()
        limits.concurrentLoads=2;limits.pendingLoads=16;limits.fileBytes=4*1024*1024
        assets=try .init(assetBaseURL:assetBaseURL,limits:limits,accessProvider:accessProvider)
    }
    deinit{metadata?.cancel();active?.cancel()}
    private func main(){dispatchPrecondition(condition:.onQueue(.main))}
    @discardableResult func reset() -> UInt64 {
        main();generation &+= 1;metadata?.cancel();metadata=nil;_=assets.reset()
        if let context=active {
            active=nil;context.cancel();context.bytes.removeAll()
            if !context.completed {context.completed=true;DispatchQueue.main.async{context.completion(.failure(Failure.cancelled))}}
        }
        return generation
    }
    func isCurrent(_ value: Prepared) -> Bool {
        main();return value.generation==generation && value.sourceIdentity==sourceIdentity()
    }
    func load(completion: @escaping Completion) {
        main();_=reset()
        let source=sourceIdentity()
        guard !source.isEmpty,source.utf8.count<=4096 else{DispatchQueue.main.async{completion(.failure(Failure.source))};return}
        let context=Context(generation:generation,source:source,completion:completion);active=context
        let url=base.appendingPathComponent(NativeCJProfile.descriptorPath)
        let transfer=NativeCJMetadataTransfer(url:url,access:accessProvider?()) {[weak self,weak context] result in
            DispatchQueue.main.async {
                guard let self,let context,self.active === context else{return}
                self.metadata=nil
                do {
                    try self.check(context)
                    context.profile=try NativeCJProfile.decode(result.get())
                    self.pump(context)
                }catch{self.finish(context,.failure(error))}
            }
        }
        metadata=transfer;transfer.start()
    }
    private func check(_ context: Context) throws {
        main()
        guard !context.cancelled,context.generation==generation,active === context else{throw Failure.cancelled}
        guard context.source==sourceIdentity() else{throw Failure.stale}
    }
    private func pump(_ context: Context) {
        main()
        do {
            try check(context)
            guard let profile=context.profile,!context.preparing else{return}
            while context.requests.count<2,context.next<profile.files.count {
                let file=profile.files[context.next];context.next+=1
                let asset=NativeSAMPStockModels.Asset(path:file.path,bytes:file.bytes,crc32:file.crc32,sha256:file.sha256)
                var requestID: UUID!
                requestID=assets.loadFile(.init(metadata:asset,url:base.appendingPathComponent(file.path))) {[weak self,weak context] result in
                    guard let self,let context,self.active === context else{return}
                    context.requests.remove(requestID)
                    do {try self.check(context);context.bytes[file.role]=try result.get().data;self.pump(context)}
                    catch{self.finish(context,.failure(error))}
                }
                context.requests.insert(requestID)
            }
            guard context.next==profile.files.count,context.requests.isEmpty else{return}
            context.preparing=true
            let data=context.bytes;context.bytes.removeAll()
            worker.async {[weak self,weak context] in
                guard let self,let context,!context.cancelled else{return}
                let result=Result{()throws->Prepared in
                    guard !context.cancelled else{throw Failure.cancelled}
                    let resources=try profile.prepare(data)
                    guard !context.cancelled else{throw Failure.cancelled}
                    let plan=try NativeRenderWarePedModel.prepareCJ(resources)
                    guard !context.cancelled else{throw Failure.cancelled}
                    return .init(generation:context.generation,sourceIdentity:context.source,profile:profile,resources:resources,plan:plan)
                }
                DispatchQueue.main.async {
                    guard self.active === context else{return}
                    do {try self.check(context);self.finish(context,result)}catch{self.finish(context,.failure(error))}
                }
            }
        }catch{finish(context,.failure(error))}
    }
    private func finish(_ context: Context, _ result: Result<Prepared, Error>) {
        main();guard active === context,!context.completed else{return}
        active=nil;context.completed=true;context.bytes.removeAll()
        if case .failure=result {context.cancel();metadata?.cancel();metadata=nil;_=assets.reset()}
        context.completion(result)
    }
}

/// Metadata has no advertised digest until decoded. Bound every block before
/// append, reject redirects and use only the app's explicit first-party token.
private final class NativeCJMetadataTransfer: NSObject, URLSessionDataDelegate {
    private let url: URL, access: NativeStockAssetAccess?, completion: (Result<Data,Error>) -> Void
    private let queue: OperationQueue = {let q=OperationQueue();q.maxConcurrentOperationCount=1;return q}()
    private var session: URLSession?, task: URLSessionDataTask?, data=Data(), done=false
    init(url: URL, access: NativeStockAssetAccess?, completion: @escaping(Result<Data,Error>)->Void) {
        self.url=url;self.access=access;self.completion=completion
    }
    func start(){queue.addOperation {
        guard !self.done else{return}
        do {
            if let local=try NativeStockAssetAccess.preparedData(for:self.url,maximumBytes:NativeCJProfile.maximumDescriptorBytes){
                guard local.count<=NativeCJProfile.maximumDescriptorBytes else{throw NativeCJRuntimeLoader.Failure.limit}
                self.finish(.success(local));return
            }
            let config=URLSessionConfiguration.ephemeral
            config.httpCookieStorage=nil;config.httpShouldSetCookies=false;config.urlCredentialStorage=nil;config.urlCache=nil
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest=20;config.timeoutIntervalForResource=90
            self.session=URLSession(configuration:config,delegate:self,delegateQueue:self.queue)
            var request=URLRequest(url:self.url);request.httpShouldHandleCookies=false
            request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
            if let header=self.access?.cookieHeader(for:self.url){request.setValue(header,forHTTPHeaderField:"Cookie")}
            self.task=self.session!.dataTask(with:request);self.task?.resume()
        }catch{self.finish(.failure(error))}
    }}
    func cancel(){queue.addOperation{self.finish(.failure(NativeCJRuntimeLoader.Failure.cancelled))}}
    private func finish(_ result: Result<Data,Error>){
        guard !done else{return};done=true;task?.cancel();task=nil;session?.invalidateAndCancel();session=nil
        data.removeAll();completion(result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping(URLSession.ResponseDisposition)->Void){
        guard !done else{completionHandler(.cancel);return}
        guard let http=response as? HTTPURLResponse,http.url==url,http.statusCode==200 else{
            completionHandler(.cancel);finish(.failure(NativeCJRuntimeLoader.Failure.unavailable((response as?HTTPURLResponse)?.statusCode ?? -1)));return
        }
        guard response.expectedContentLength<=NativeCJProfile.maximumDescriptorBytes,
              http.value(forHTTPHeaderField:"Content-Encoding").map({$0.lowercased()=="identity"}) ?? true else{
            completionHandler(.cancel);finish(.failure(NativeCJRuntimeLoader.Failure.limit));return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive bytes: Data){
        guard !done else{return}
        guard bytes.count<=NativeCJProfile.maximumDescriptorBytes-data.count else{finish(.failure(NativeCJRuntimeLoader.Failure.limit));return}
        data.append(bytes)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?){
        guard !done else{return};if let error{finish(.failure(error))}else{finish(.success(data))}
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping(URLRequest?)->Void){
        completionHandler(nil);finish(.failure(NativeCJRuntimeLoader.Failure.source))
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping(URLSession.AuthChallengeDisposition,URLCredential?)->Void){
        if challenge.protectionSpace.authenticationMethod==NSURLAuthenticationMethodServerTrust{completionHandler(.performDefaultHandling,nil)}
        else{completionHandler(.cancelAuthenticationChallenge,nil)}
    }
}
