import Foundation
import Security

var checks=0
var connectionChecks=0
func connectionCheck(_ value: @autoclosure () -> Bool, _ description: String) {
    connectionChecks += 1
    precondition(value(), description)
}
func check(_ value: @autoclosure () -> Bool, _ description: String) {
    checks += 1
    precondition(value(), description)
}
func pump(_ seconds: Double) {
    let until=Date().addingTimeInterval(seconds)
    while Date()<until { RunLoop.main.run(until: min(until,Date().addingTimeInterval(0.01))) }
}
func result<T>(_ begin: (@escaping (T)->Void)->Void) -> T {
    var value:T?
    begin { value=$0 }
    let deadline=Date().addingTimeInterval(8)
    while value == nil && Date()<deadline { pump(0.01) }
    precondition(value != nil,"HTTP completion did not arrive")
    return value!
}
func success<T>(_ value: Result<T,NativeMenuProfileClient.Failure>) -> T {
    switch value {case .success(let v):return v;case .failure(let e):fatalError(e.message)}
}
let a=ServerAddress(CommandLine.arguments[1])!,b=ServerAddress(CommandLine.arguments[2])!
func control(_ mode:String)->[String:Any] {
    let value:(Data?,URLResponse?,Error?)=result { done in
        URLSession.shared.dataTask(with:a.path("test/control").appending(queryItems:[URLQueryItem(name:"mode",value:mode)])) {
            done(($0,$1,$2))
        }.resume()
    }
    precondition((value.1 as? HTTPURLResponse)?.statusCode==200)
    return try! JSONSerialization.jsonObject(with:value.0!) as! [String:Any]
}
func clean(_ address:ServerAddress) {
    let account=address.url.absoluteString.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
    SecItemDelete([kSecClass as String:kSecClassGenericPassword,
                   kSecAttrService as String:"com.zema.zgtasa.localGuest",
                   kSecAttrAccount as String:account] as CFDictionary)
    UserDefaults.standard.removeObject(forKey:"localGuest.\(account)")
}
clean(a);clean(b)
defer {clean(a);clean(b)}
let first=NativeMenuProfileClient(server:a)
check(control("")["players"] as? Int==0,"Constructing menu created an account")
let info=success(result { first.loadServerInfo($0) })
check(info.players==0,"Status player count fabricated")
check(control("")["players"] as? Int==0,"Status page created a guest")
let firstConnection:Result<Void,NativeMenuProfileClient.Failure>=result {first.connect(joinCode:"",completion:$0)}
if case .success=firstConnection {connectionChecks += 1}else {fatalError("Fresh guest connection failed")}
connectionCheck(control("")["players"] as? Int==1,"Fresh connection did not create exactly one guest")
let profile=success(result { first.loadProfile($0) })
check(profile.name.hasPrefix("Local "),"Actual guest profile missing")
_ = control("seed-existing")
let renamed=success(result { first.rename("Menu Alice",completion:$0) })
check(renamed.name=="Menu Alice" && renamed.number==profile.number,"Rename replaced guest identity")
let statistics=success(result { first.loadStatistics($0) })
check(statistics.name=="Menu Alice","Stats selected another account")
check(statistics.rows.contains(.init(title:"CASH",value:"$12345")),"Existing saved cash was reset or absent")
check(statistics.rows.contains(.init(title:"EXPERIENCE",value:"2700")),"Existing progress was reset or absent")
check(statistics.rows.contains(.init(title:"OWNED VEHICLES",value:"1")),"Actual owned vehicle count absent")
check(statistics.rows.contains(.init(title:"OWNED HOMES",value:"1")),"Actual owned home count absent")

let other=NativeMenuProfileClient(server:b)
let second=success(result { other.loadProfile($0) })
check(second.number != profile.number,"Per-port local guest was borrowed from another server")
check(success(result { other.rename("Menu Bob",completion:$0) }).name=="Menu Bob","Second profile failed")
let recreated=NativeMenuProfileClient(server:a)
check(success(result { recreated.loadProfile($0) })==renamed,"Saved per-server guest was not restored")
// Even after the shared cookie has changed, the existing client stays pinned.
check(success(result { other.loadProfile($0) }).name=="Menu Bob","Shared cookies replaced the validated menu identity")

_ = control("stats-error")
let statsError:Result<NativeMenuProfileClient.Statistics,NativeMenuProfileClient.Failure>=result { recreated.loadStatistics($0) }
check(statsError == .failure(.rejected(409,"Synthetic unavailable state")),"Stats failure was hidden as zero counters")
_ = control("")
check(success(result { recreated.loadStatistics($0) }).name=="Menu Alice","Stats did not recover after an HTTP error")
_ = control("name-error")
let renameError:Result<NativeMenuProfileClient.Profile,NativeMenuProfileClient.Failure>=result { recreated.rename("Rejected",completion:$0) }
check(renameError == .failure(.rejected(400,"Synthetic name rejection")),"Rejected rename appeared successful")
let empty:Result<NativeMenuProfileClient.Profile,NativeMenuProfileClient.Failure>=result { recreated.rename("   ",completion:$0) }
check(empty == .failure(.invalidName),"Empty name sent to server")

let before=control("slow-auth")
let putsBefore=(before["calls"] as! [[String:Any]]).filter{$0["method"] as? String=="PUT"}.count
var cancelledRename=false
recreated.rename("Must Not Save") { _ in cancelledRename=true }
pump(0.08);recreated.cancelPendingRequests();pump(0.8)
let after=control("")
let putsAfter=(after["calls"] as! [[String:Any]]).filter{$0["method"] as? String=="PUT"}.count
check(!cancelledRename && putsBefore==putsAfter,"Leaving during auth queued a late profile mutation")

_ = control("slow-profile")
var staleCallback=false
recreated.loadProfile { _ in staleCallback=true }
pump(0.1);recreated.cancelPendingRequests()
_ = control("")
let fresh=success(result { recreated.loadProfile($0) })
pump(0.7)
check(fresh==renamed && !staleCallback,"Cancelled profile completion reopened or overwrote the current page")

_ = control("invalid-status")
let malformed:Result<NativeMenuProfileClient.ServerInfo,NativeMenuProfileClient.Failure>=result { recreated.loadServerInfo($0) }
check(malformed == .failure(.invalidResponse),"Malformed status accepted")
_ = control("redirect-status")
let redirected:Result<NativeMenuProfileClient.ServerInfo,NativeMenuProfileClient.Failure>=result { recreated.loadServerInfo($0) }
if case .failure(.rejected(302,_))=redirected {checks += 1}else {fatalError("Redirect followed or hidden")}
_ = control("")
let offline=NativeMenuProfileClient(server:ServerAddress("http://127.0.0.1:1")!)
let disconnected:Result<NativeMenuProfileClient.ServerInfo,NativeMenuProfileClient.Failure>=result { offline.loadServerInfo($0) }
if case .failure(.offline)=disconnected {checks += 1}else {fatalError("Offline server was reported online")}
let final=control("")
check(final["players"] as? Int==2,"Repeated management pages created extra guests")
check((final["names"] as! [String]).sorted()==["Menu Alice","Menu Bob"],"Cancellation or rejected rename modified the account")
print("PASS menu profile client: \(checks) checks with actual LocalGuestSession and disposable backend")

func report()->[String:Any] {
    let reply:(Data?,URLResponse?,Error?)=result {done in
        URLSession.shared.dataTask(with:a.path("test/report")){done(($0,$1,$2))}.resume()
    }
    precondition((reply.1 as? HTTPURLResponse)?.statusCode==200)
    return try! JSONSerialization.jsonObject(with:reply.0!) as! [String:Any]
}
func requestCount()->Int {(report()["calls"] as! [[String:Any]]).count}
func requests(after count:Int)->[[String:Any]] {Array((report()["calls"] as! [[String:Any]]).dropFirst(count))}
func connect(_ client:NativeMenuProfileClient,code:String="")->Result<Void,NativeMenuProfileClient.Failure> {
    result {client.connect(joinCode:code,completion:$0)}
}
func connected(_ outcome:Result<Void,NativeMenuProfileClient.Failure>,_ message:String) {
    if case .success=outcome {connectionChecks += 1}else {fatalError(message)}
}
func failed(_ outcome:Result<Void,NativeMenuProfileClient.Failure>,_ expected:NativeMenuProfileClient.Failure,_ message:String) {
    if case .failure(let error)=outcome {connectionCheck(error==expected,message)}else {fatalError(message)}
}
func clearAccess() {
    for cookie in HTTPCookieStorage.shared.cookies(for:a.url) ?? [] where cookie.name=="zgta_access" {
        HTTPCookieStorage.shared.deleteCookie(cookie)
    }
}
func waitForRequest(_ path:String,after count:Int) {
    let deadline=Date().addingTimeInterval(3)
    while Date()<deadline {
        if requests(after:count).contains(where:{$0["path"] as? String==path}) {return}
        pump(0.01)
    }
    fatalError("Fixture did not receive \(path)")
}
let saved=NativeMenuProfileClient(server:a)
let savedStart=requestCount()
connected(connect(saved),"Restored guest connection failed")
connectionCheck(requests(after:savedStart).map{$0["path"] as! String}==["/api/local/status","/api/auth/me"],"Reconnect sent unexpected requests")
connectionCheck(success(result {saved.loadProfile($0)})==renamed,"Connect restored the wrong saved guest")
connectionCheck(report()["players"] as? Int==2,"Connect created another account")

for mode in ["invalid-status","not-selfhost","missing-selfhost","invalid-json-status"] {
    _=control(mode);let start=requestCount()
    failed(connect(saved),.invalidResponse,"Invalid/nonselfhost status connected: \(mode)")
    connectionCheck(requests(after:start).map{$0["path"] as! String}==["/api/local/status"],"Invalid status reached auth")
}
_=control("invalid-auth")
failed(connect(saved),.invalidResponse,"Nonlocal authentication accepted")
_=control("")
connectionCheck(success(result {saved.loadProfile($0)})==renamed,"Invalid auth replaced saved identity")

clearAccess();_=control("join-gate")
let gated=NativeMenuProfileClient(server:a),missingStart=requestCount()
failed(connect(gated),.rejected(401,"Fixture join code required"),"Missing join code appeared connected")
connectionCheck(requests(after:missingStart).map{$0["path"] as! String}==["/api/local/status"],"Missing code tried auth or join")
let wrongStart=requestCount()
failed(connect(gated,code:"incorrect-fixture-code"),.rejected(403,"Access code incorrect"),"Rejected join appeared connected")
connectionCheck(requests(after:wrongStart).map{$0["path"] as! String}==["/api/local/status","/api/local/join"],"Rejected code reached auth")
let acceptedStart=requestCount()
connected(connect(gated,code:"native83-fixture-join-code"),"Real accepted join did not authenticate")
let accepted=requests(after:acceptedStart)
connectionCheck(accepted.map{$0["path"] as! String}==["/api/local/status","/api/local/join","/api/auth/me"],"Accepted join sequence wrong")
connectionCheck(accepted[1]["method"] as? String=="POST","Join did not use POST")
connectionCheck((accepted[2]["cookie"] as? String)?.contains("zgta_access=")==true,"Access cookie not forwarded to auth")
connectionCheck(success(result {gated.loadProfile($0)})==renamed,"Join changed saved guest")
let againStart=requestCount()
connected(connect(gated),"Reconnect lost access cookie")
connectionCheck(requests(after:againStart).map{$0["path"] as! String}==["/api/local/status","/api/auth/me"],"Authorized reconnect unnecessarily joined")
connectionCheck(report()["players"] as? Int==2,"Accepted join/reconnect created another account")

clearAccess();_=control("join-no-cookie")
let missingCookie=NativeMenuProfileClient(server:a),missingCookieStart=requestCount()
failed(connect(missingCookie,code:"native83-fixture-join-code"),.invalidResponse,"Join without access cookie accepted")
connectionCheck(!requests(after:missingCookieStart).contains{$0["path"] as? String=="/api/auth/me"},"Missing access cookie still tried auth")

for mode in ["redirect-status","redirect-auth","redirect-join"] {
    clearAccess();_=control(mode)
    let client=NativeMenuProfileClient(server:a),start=requestCount()
    let outcome=connect(client,code:mode=="redirect-join" ? "native83-fixture-join-code":"")
    if case .failure(.rejected(302,_))=outcome {connectionChecks += 1}else {fatalError("Connection followed \(mode)")}
    connectionCheck(!requests(after:start).contains{$0["path"] as? String=="/test/redirect-leak"},"Saved token forwarded to redirect destination")
    if mode != "redirect-auth" {connectionCheck(!requests(after:start).contains{$0["path"] as? String=="/api/auth/me"},"Redirect still advanced to auth")}
}

for (mode,path) in [("slow-status","/api/local/status"),("slow-auth","/api/auth/me")] {
    _=control(mode);let client=NativeMenuProfileClient(server:a),start=requestCount()
    var callback=false
    client.connect(joinCode:""){_ in callback=true}
    waitForRequest(path,after:start);client.cancelPendingRequests();pump(0.8)
    connectionCheck(!callback,"Leaving during \(mode) delivered a connection callback")
    if mode=="slow-status" {connectionCheck(!requests(after:start).contains{$0["path"] as? String=="/api/auth/me"},"Cancelled status started authentication")}
}
_=control("slow-status")
let superseded=NativeMenuProfileClient(server:a),supersededStart=requestCount()
var staleConnection=false
superseded.connect(joinCode:""){_ in staleConnection=true}
waitForRequest("/api/local/status",after:supersededStart)
_=control("")
connected(connect(superseded),"New connection did not supersede old request")
pump(0.8)
connectionCheck(!staleConnection,"Old connection completion reopened game after reconnect")
connectionCheck(success(result {superseded.loadProfile($0)})==renamed,"Reconnect lost existing saved account")
connectionCheck(report()["players"] as? Int==2,"Connection regressions created extra accounts")
clearAccess();_=control("")
print("PASS native connect: \(connectionChecks) real HTTP checks; original management checks preserved: \(checks)")
