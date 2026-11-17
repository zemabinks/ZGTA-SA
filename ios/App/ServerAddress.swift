import Foundation

protocol NativeResourceTask: AnyObject { func resume(); func cancel() }
extension URLSessionDataTask: NativeResourceTask {}

/// A static-file transport boundary. Non-app/old-host callers retain normal
/// URLSession behavior; the native App installs its persistent resolver once.
enum NativeResourceTransport {
    typealias Completion = (Data?,URLResponse?,Error?)->Void
    typealias Factory = (URLRequest,@escaping Completion)->NativeResourceTask
    typealias LocalFile = (URL)throws->URL?
    private static let lock=NSLock()
    private static var factory:Factory?
    private static var fileResolver:LocalFile?
    static func install(_ value:@escaping Factory,localFile:LocalFile?=nil){lock.lock();factory=value;fileResolver=localFile;lock.unlock()}
    static func localFile(for url:URL)throws->URL?{lock.lock();let resolver=fileResolver;lock.unlock();return try resolver?(url)}
    static func dataTask(with url:URL,completionHandler:@escaping Completion)->NativeResourceTask {
        dataTask(with:URLRequest(url:url),completionHandler:completionHandler)
    }
    static func dataTask(with request:URLRequest,completionHandler:@escaping Completion)->NativeResourceTask {
        lock.lock();let current=factory;lock.unlock()
        return current?(request,completionHandler) ?? URLSession.shared.dataTask(with:request,completionHandler:completionHandler)
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
