import Foundation
import CoreFoundation

/// Out-of-game account pages use the existing self-hosted guest, with no
/// inventory-connection header or WebSocket. Call on the main thread.
final class NativeMenuProfileClient {
    struct Profile: Equatable {
        let name: String
        let number: Int
    }
    struct Statistic: Equatable {
        let title: String
        let value: String
    }
    struct Statistics: Equatable {
        let name: String
        let rows: [Statistic]
    }
    struct ServerInfo: Equatable {
        let players: Int
        let discordLoginAvailable: Bool
        let joinCodeRequired: Bool
        let lanAccessible: Bool
        let features: [String]
    }
    enum Failure: Error, Equatable {
        case offline(String)
        case rejected(Int, String)
        case invalidResponse
        case invalidName

        var message: String {
            switch self {
            case .offline(let detail): return "SERVER UNAVAILABLE. \(detail)"
            case .rejected(401, _): return "THIS SERVER NEEDS A JOIN CODE. CONNECT FROM MULTIPLAYER FIRST."
            case .rejected(let status, let detail): return "SERVER ERROR \(status). \(detail)"
            case .invalidResponse: return "THIS SERVER DID NOT RETURN A VALID LOCAL PROFILE RESPONSE."
            case .invalidName: return "ENTER A NAME."
            }
        }
    }

    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            // A menu API must not forward a saved guest token to a redirect.
            completionHandler(nil)
        }
    }
    private let server: ServerAddress
    private let session: URLSession
    private var tasks: [UUID: URLSessionDataTask] = [:]
    private var generation: UInt64 = 0
    private var cookies: [HTTPCookie] = []
    private var restored = false

    init(server: ServerAddress, configuration: URLSessionConfiguration = .ephemeral) {
        self.server = server
        let config = configuration.copy() as! URLSessionConfiguration
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        session = URLSession(configuration: config, delegate: RedirectPolicy(), delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    /// Invalidate both network work and already queued main-thread callbacks.
    /// Cancellation cannot undo a PUT already accepted by the server.
    func cancelPendingRequests() {
        generation &+= 1
        let pending = Array(tasks.values)
        tasks.removeAll()
        for task in pending { task.cancel() }
    }

    func loadProfile(_ completion: @escaping (Result<Profile, Failure>) -> Void) {
        accountRequest(path: "api/local/profile") { result in
            completion(result.flatMap(Self.profile))
        }
    }

    func rename(_ name: String, completion: @escaping (Result<Profile, Failure>) -> Void) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            cancelPendingRequests()
            completion(.failure(.invalidName))
            return
        }
        accountRequest(path: "api/local/profile", method: "PUT", body: ["name": name]) { result in
            completion(result.flatMap(Self.profile))
        }
    }

    func loadStatistics(_ completion: @escaping (Result<Statistics, Failure>) -> Void) {
        accountRequest(path: "api/local/state") { result in
            completion(result.flatMap(Self.statistics))
        }
    }

    /// Status is public; opening this page never authenticates or creates a guest.
    func loadServerInfo(_ completion: @escaping (Result<ServerInfo, Failure>) -> Void) {
        cancelPendingRequests()
        let token = generation
        let publicCookies = (HTTPCookieStorage.shared.cookies(for: server.url) ?? []).filter { $0.name != "zgta_local" }
        request(path: "api/local/status", cookies: publicCookies, generation: token) { result in
            completion(result.flatMap(Self.serverInfo))
        }
    }

    /// The title-screen connection uses the same pinned guest as management.
    /// Cancelling this client suppresses delayed auth/connection completions.
    func connect(joinCode:String,completion:@escaping(Result<Void,Failure>)->Void) {
        cancelPendingRequests();restoreCookies();let token=generation
        func authenticate() {
            request(path:"api/auth/me",cookies:cookies,generation:token,rememberIdentity:true) { result in
                completion(result.map{_ in ()})
            }
        }
        request(path:"api/local/status",cookies:cookies,generation:token) { [weak self] result in
            guard let self else{return}
            switch result {
            case .success(let status):
                guard case .success = Self.serverInfo(status) else{completion(.failure(.invalidResponse));return}
                authenticate()
            case .failure(.rejected(401,_)) where !joinCode.isEmpty:
                self.request(path:"api/local/join",method:"POST",body:["code":joinCode],cookies:self.cookies,
                             generation:token,acceptAccessCookie:true) { joined in
                    switch joined {case .success:authenticate();case .failure(let error):completion(.failure(error))}
                }
            case .failure(let error):completion(.failure(error))
            }
        }
    }

    private func restoreCookies() {
        if !restored {
            LocalGuestSession.restore(for:server)
            cookies=HTTPCookieStorage.shared.cookies(for:server.url) ?? []
            restored=true
        }
    }

    private func accountRequest(path: String, method: String = "GET", body: [String: Any]? = nil,
                                completion: @escaping (Result<[String: Any], Failure>) -> Void) {
        cancelPendingRequests()
        let token = generation
        restoreCookies()
        // Validate the server-selected identity each time a data page or name
        // change is explicitly requested, including after a server restart.
        request(path: "api/auth/me", cookies: cookies, generation: token, rememberIdentity: true) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error): completion(.failure(error))
            case .success:
                self.request(path: path, method: method, body: body, cookies: self.cookies,
                             generation: token, completion: completion)
            }
        }
    }

    private func request(path: String, method: String = "GET", body: [String: Any]? = nil,
                         cookies: [HTTPCookie], generation token: UInt64,
                         rememberIdentity: Bool = false, acceptAccessCookie:Bool = false,
                         completion: @escaping (Result<[String: Any], Failure>) -> Void) {
        guard token == generation else { return }
        var request = URLRequest(url: server.path(path))
        request.httpMethod = method
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !cookies.isEmpty {
            for (key, value) in HTTPCookie.requestHeaderFields(with: cookies) { request.setValue(value, forHTTPHeaderField: key) }
        }
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let id = UUID()
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.tasks.removeValue(forKey: id)
                guard let http = response as? HTTPURLResponse else {
                    completion(.failure(.offline(error?.localizedDescription ?? "No HTTP response.")))
                    return
                }
                let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                guard http.statusCode == 200 else {
                    completion(.failure(.rejected(http.statusCode, (json?["error"] as? String) ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))))
                    return
                }
                guard error == nil, let json else { completion(.failure(.invalidResponse)); return }
                if acceptAccessCookie {
                    let fields=http.allHeaderFields.reduce(into:[String:String]()){result,field in
                        result[String(describing:field.key)]=String(describing:field.value)
                    }
                    let received=HTTPCookie.cookies(withResponseHeaderFields:fields,for:self.server.url)
                    guard let access=received.first(where:{$0.name=="zgta_access"}) else{completion(.failure(.invalidResponse));return}
                    self.cookies.removeAll{$0.name=="zgta_access"};self.cookies.append(access)
                    HTTPCookieStorage.shared.setCookie(access)
                }
                if rememberIdentity {
                    guard json["local"] as? Bool == true, json["loggedIn"] as? Bool == true,
                          let identity = json["id"] as? String,
                          identity.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil else {
                        completion(.failure(.invalidResponse)); return
                    }
                    let fields = http.allHeaderFields.reduce(into: [String: String]()) { result, field in
                        result[String(describing: field.key)] = String(describing: field.value)
                    }
                    let received = HTTPCookie.cookies(withResponseHeaderFields: fields, for: self.server.url)
                    guard let guest = received.first(where: { $0.name == "zgta_local" && $0.value == identity }) ??
                            self.cookies.first(where: { $0.name == "zgta_local" && $0.value == identity }) else {
                        completion(.failure(.invalidResponse)); return
                    }
                    self.cookies.removeAll { $0.name == "zgta_local" }
                    self.cookies.append(guest)
                    HTTPCookieStorage.shared.setCookie(guest)
                    LocalGuestSession.remember(http, for: self.server)
                }
                completion(.success(json))
            }
        }
        tasks[id] = task
        task.resume()
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue.rounded() == n.doubleValue,
              n.doubleValue >= Double(Int.min), n.doubleValue < Double(Int.max) else { return nil }
        return n.intValue
    }

    private static func serverInfo(_ body:[String:Any])->Result<ServerInfo,Failure> {
        guard body["selfhost"] as? Bool == true,
              let count=integer(body["players"]),count>=0,
              let discord=body["discordLoginAvailable"] as? Bool,
              let join=body["joinCodeRequired"] as? Bool,
              let lan=body["lanAccessible"] as? Bool,
              let features=body["features"] as? [String] else{return .failure(.invalidResponse)}
        return .success(ServerInfo(players:count,discordLoginAvailable:discord,joinCodeRequired:join,lanAccessible:lan,features:features))
    }

    private static func profile(_ body: [String: Any]) -> Result<Profile, Failure> {
        guard let name = body["name"] as? String, !name.isEmpty,
              let number = integer(body["number"]), number >= 0 else { return .failure(.invalidResponse) }
        return .success(Profile(name: name, number: number))
    }

    private static func statistics(_ body: [String: Any]) -> Result<Statistics, Failure> {
        guard let name = body["name"] as? String, !name.isEmpty else { return .failure(.invalidResponse) }
        let fields = [("cash", "CASH"), ("xp", "EXPERIENCE"), ("jobsDone", "JOBS COMPLETED"),
                      ("racesFinished", "RACES FINISHED"), ("racesWon", "RACES WON"),
                      ("kills", "KILLS"), ("deaths", "DEATHS"), ("arrests", "ARRESTS"),
                      ("turfCaptures", "TERRITORY CAPTURES")]
        var rows = fields.compactMap { key, title -> Statistic? in
            guard let number = integer(body[key]) else { return nil }
            return Statistic(title: title, value: key == "cash" ? "$\(number)" : String(number))
        }
        guard !rows.isEmpty else { return .failure(.invalidResponse) }
        for (key, title) in [("cars", "OWNED VEHICLES"), ("homes", "OWNED HOMES")] {
            if let items = body[key] as? [Any] { rows.append(Statistic(title: title, value: String(items.count))) }
        }
        for (key, counter, title) in [("pilot", "flights", "PILOT FLIGHTS"), ("taxi", "fares", "TAXI FARES")] {
            if let item = body[key] as? [String: Any], let count = integer(item[counter]) {
                rows.append(Statistic(title: title, value: String(count)))
            }
        }
        if let exploration = body["exploration"] as? [String: Any],
           let found = integer(exploration["found"]), let total = integer(exploration["total"]) {
            rows.append(Statistic(title: "LOCATIONS DISCOVERED", value: "\(found) / \(total)"))
        }
        return .success(Statistics(name: name, rows: rows))
    }
}
