import Foundation

protocol NativeResourceTask: AnyObject { func resume(); func cancel() }
extension URLSessionDataTask: NativeResourceTask {}

/// A static-file transport boundary. Non-app/old-host callers retain normal
/// URLSession behavior; the native App installs its persistent resolver once.
enum NativeResourceTransport {
    typealias Completion = (Data?,URLResponse?,Error?)->Void
    typealias Factory = (URLRequest,@escaping Completion)->NativeResourceTask
    typealias BoundedFactory = (URLRequest,Int,@escaping Completion)->NativeResourceTask
    typealias LocalFile = (URL)throws->URL?
    private static let lock=NSLock()
    private static var factory:Factory?
    private static var boundedFactory:BoundedFactory?
    private static var fileResolver:LocalFile?
    static func install(_ value:@escaping Factory,localFile:LocalFile?=nil,bounded:BoundedFactory?=nil){lock.lock();factory=value;fileResolver=localFile;boundedFactory=bounded;lock.unlock()}
    static func localFile(for url:URL)throws->URL?{lock.lock();let resolver=fileResolver;lock.unlock();return try resolver?(url)}
    static func dataTask(with url:URL,completionHandler:@escaping Completion)->NativeResourceTask {
        dataTask(with:URLRequest(url:url),completionHandler:completionHandler)
    }
    static func dataTask(with request:URLRequest,completionHandler:@escaping Completion)->NativeResourceTask {
        lock.lock();let current=factory;lock.unlock()
        return current?(request,completionHandler) ?? URLSession.shared.dataTask(with:request,completionHandler:completionHandler)
    }
    /// Suspended task. Its completion runs once on a background queue, including
    /// cancellation before resume. The cap bounds retained payload bytes, not
    /// Foundation's delegate chunks, allocator capacity or kernel buffers.
    static func boundedDataTask(with url:URL,maximumBytes:Int,completionHandler:@escaping Completion)->NativeResourceTask {
        boundedDataTask(with:URLRequest(url:url),maximumBytes:maximumBytes,completionHandler:completionHandler)
    }
    static func boundedDataTask(with request:URLRequest,maximumBytes:Int,completionHandler:@escaping Completion)->NativeResourceTask {
        lock.lock();let current=boundedFactory;lock.unlock()
        return current?(request,maximumBytes,completionHandler) ?? NativeBoundedResourceTask(request:request,maximumBytes:maximumBytes,completion:completionHandler)
    }
}

/// Foundation-only fallback, also used by the App's development resolver. It
/// copies only the supplied session configuration; it discovers no credentials
/// or browser cookies. Redirects and compressed bodies are deliberately refused.
final class NativeBoundedResourceTask:NSObject,NativeResourceTask,URLSessionDataDelegate {
    static let maximumSupportedBytes=2_147_483_648
    enum Failure:Error,Equatable {
        case invalidMaximum,invalidURL,invalidResponse,http(Int),encoding,contentLength,limit,redirect,sizeMismatch
    }
    private let lock=NSLock()
    private let request:URLRequest,maximumBytes:Int,configuration:URLSessionConfiguration
    private let completion:NativeResourceTransport.Completion
    private var started=false,finished=false,cancelled=false
    private var session:URLSession?,remote:URLSessionDataTask?,response:HTTPURLResponse?
    private var bytes=Data(),declaredLength:Int64?
    init(request:URLRequest,maximumBytes:Int,configuration:URLSessionConfiguration=URLSession.shared.configuration,
         completion:@escaping NativeResourceTransport.Completion){
        self.request=request;self.maximumBytes=maximumBytes
        self.configuration=configuration.copy() as! URLSessionConfiguration;self.completion=completion
    }
    static func validMaximum(_ value:Int)->Bool{value>0 && value<=maximumSupportedBytes}
    func resume(){
        lock.lock();guard !started,!finished else{lock.unlock();return};started=true
        guard Self.validMaximum(maximumBytes) else{lock.unlock();finish(nil,Failure.invalidMaximum);return}
        guard let url=request.url,let parts=URLComponents(url:url,resolvingAgainstBaseURL:false),
              ["http","https"].contains(parts.scheme?.lowercased() ?? ""),parts.host?.isEmpty==false,
              parts.user==nil,parts.password==nil else{lock.unlock();finish(nil,Failure.invalidURL);return}
        var value=request;value.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
        // A cache cannot turn an oversized historical cached body into an
        // unbounded read. Foundation still owns its network/delegate buffers.
        value.cachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache=nil
        let queue=OperationQueue();queue.maxConcurrentOperationCount=1;queue.qualityOfService = .utility
        let connection=URLSession(configuration:configuration,delegate:self,delegateQueue:queue)
        let task=connection.dataTask(with:value);session=connection;remote=task;lock.unlock();task.resume()
    }
    func cancel(){lock.lock();cancelled=true;lock.unlock();finish(nil,URLError(.cancelled))}
    private func finish(_ data:Data?,_ error:Error?){
        lock.lock();guard !finished else{lock.unlock();return};finished=true
        let stop=cancelled,result=stop ? nil:data,reply=stop ? nil:response,connection=session
        let failure:Error?=stop ? URLError(.cancelled):error
        remote=nil;session=nil;bytes=Data();lock.unlock()
        connection?.invalidateAndCancel()
        DispatchQueue.global(qos:.utility).async{self.completion(result,reply,failure)}
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,
                    completionHandler:@escaping(URLSession.ResponseDisposition)->Void){
        lock.lock();guard !finished,!cancelled else{lock.unlock();completionHandler(.cancel);return}
        guard let http=response as? HTTPURLResponse else{lock.unlock();completionHandler(.cancel);finish(nil,Failure.invalidResponse);return}
        self.response=http
        var failure:Failure?
        if !(200...299).contains(http.statusCode){failure = .http(http.statusCode)}
        if let encoding=http.value(forHTTPHeaderField:"Content-Encoding"),encoding.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() != "identity"{failure = .encoding}
        if let rawLength=http.value(forHTTPHeaderField:"Content-Length"){
            let length=rawLength.trimmingCharacters(in:CharacterSet(charactersIn:" \t"))
            // Duplicate/comma/signed/overflowing lengths are never trusted.
            if length.isEmpty || !length.utf8.allSatisfy({(48...57).contains($0)}) || Int64(length)==nil{failure = .contentLength}
            else{declaredLength=Int64(length);if declaredLength!>Int64(maximumBytes){failure = .limit}}
            if http.value(forHTTPHeaderField:"Transfer-Encoding") != nil{failure = .contentLength}
        }else if http.expectedContentLength>=0{
            declaredLength=http.expectedContentLength
            if http.expectedContentLength>Int64(maximumBytes){failure = .limit}
        }
        lock.unlock()
        if let failure{completionHandler(.cancel);finish(nil,failure)}else{completionHandler(.allow)}
    }
    func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive data:Data){
        lock.lock();guard !finished,!cancelled else{lock.unlock();return}
        guard data.count<=maximumBytes-bytes.count else{lock.unlock();finish(nil,Failure.limit);return}
        bytes.append(data);lock.unlock()
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,
                    newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){
        completionHandler(nil);finish(nil,Failure.redirect)
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){
        lock.lock();guard !finished else{lock.unlock();return}
        let data=bytes,isHead=request.httpMethod?.uppercased()=="HEAD",reply=response
        var failure=error
        if failure==nil,reply==nil{failure=Failure.invalidResponse}
        if failure==nil,!isHead,let expected=declaredLength,Int64(data.count) != expected{failure=Failure.sizeMismatch}
        lock.unlock();finish(failure==nil && !isHead ? data:nil,failure)
    }
}

struct ServerAddress: Equatable {
    let url: URL

    init?(_ raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = "http://" + value }
        guard let parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/",
              let url = parts.url else { return nil }
        self.url = url
    }

    var display: String { url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    func path(_ path: String) -> URL {
        url.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
