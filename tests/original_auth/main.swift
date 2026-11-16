// SPDX-License-Identifier: AGPL-3.0-only
// Owned loopback HTTP tests. No requests are made to the original service.
import Foundation
import Dispatch

private typealias Auth = NativeOriginalWorldAuthentication
private var checks=0
private let mainQueueKey=DispatchSpecificKey<Bool>()
private func check(_ value:Bool,_ message:String){checks+=1;if !value{fputs("FAIL: \(message)\n",stderr);exit(1)}}
private final class Box<T> {
    private let lock=NSLock();private var storage:T?
    func set(_ value:T){lock.lock();storage=value;lock.unlock()}
    func get()->T?{lock.lock();defer{lock.unlock()};return storage}
}
private let base=URL(string:CommandLine.arguments[1])!
private func owner(_ scenario:String)->(Auth,URLSession){
    let config=URLSessionConfiguration.ephemeral
    config.httpAdditionalHeaders=["X-ZGTA-Test":scenario]
    let session=URLSession(configuration:config)
    return (try!Auth(session:session,loopbackTestOrigin:base),session)
}
private func wait<T>(_ start:(@escaping(Result<T,Auth.Failure>)->Void)->Void)->Result<T,Auth.Failure>{
    let event=DispatchSemaphore(value:0),box=Box<Result<T,Auth.Failure>>()
    start{result in check(DispatchQueue.getSpecific(key:mainQueueKey)==true,"completion is on main queue");box.set(result);event.signal()}
    check(event.wait(timeout:.now()+8) == .success,"bounded completion")
    return box.get()!
}
private func success<T>(_ result:Result<T,Auth.Failure>,_ message:String)->T{
    switch result{case .success(let value):return value;case .failure(let error):check(false,"\(message): \(error)");fatalError()}
}
private func failed<T>(_ result:Result<T,Auth.Failure>,_ expected:Auth.Failure,_ message:String){
    switch result{case .success:check(false,message);case .failure(let error):check(error==expected,"\(message): \(error)")}
}
private func pause(_ seconds:Double){Thread.sleep(forTimeInterval:seconds)}
private func plainGET(_ session:URLSession,_ path:String)->(Data,HTTPURLResponse){
    let event=DispatchSemaphore(value:0),box=Box<(Data,HTTPURLResponse)>()
    session.dataTask(with:URL(string:path,relativeTo:base)!.absoluteURL){data,response,error in
        if let data,let response=response as?HTTPURLResponse,error==nil{box.set((data,response))};event.signal()
    }.resume()
    check(event.wait(timeout:.now()+5) == .success,"plain owner session request completes")
    guard let result=box.get()else{check(false,"owner session remains usable");fatalError()};return result
}

private func run(){
    for url in ["https://example.com/","http://127.0.0.1.evil.test/","http://user@localhost/","http://localhost/?x=1","http://localhost/path","file:///tmp/","http://localhost/#fragment"]{
        do{_ = try Auth(session:URLSession(configuration:.ephemeral),loopbackTestOrigin:URL(string:url)!);check(false,"reject invalid test origin \(url)")}
        catch{check((error as?Auth.Failure) == .invalidOrigin,"explicit loopback-only origin")}
    }
    let (guest,guestSession)=owner("guest-success")
    let connection=success(wait{guest.createGuest(name:"  QA Guest  ",completion:$0)},"guest create/verify/build")
    check(connection.session===guestSession,"connection preserves app-owned session identity")
    check(connection.guest && connection.username=="QA Guest","server-confirmed guest identity")
    check(connection.build=="202611161501","asset build is authoritative and distinct from browser build")
    let (_,health)=plainGET(guestSession,"/__health")
    check(health.statusCode==200,"helper does not invalidate owner's session")

    let (account,_)=owner("account-public")
    let available=success(wait{account.account(completion:$0)},"public account")
    check(available==Auth.Account(available:true,guests:true,loggedIn:false,guest:false,username:""),"guest availability is not an authenticated account")
    let (discord,discordSession)=owner("discord")
    let signed=success(wait{discord.bootstrap(completion:$0)},"Discord-like fixture bootstrap")
    check(!signed.guest && signed.username=="Fixture Account" && signed.session===discordSession,"regular account preserved")
    let (fallback,_)=owner("account-fallback")
    check(success(wait{fallback.account(completion:$0)},"discordName fallback").username=="Legacy Account","legacy name fallback")
    let (optional,_)=owner("account-optional")
    check(success(wait{optional.account(completion:$0)},"optional account flags")==Auth.Account(available:true,guests:false,loggedIn:true,guest:false,username:""),"optional flags default explicitly")
    let (anonymous,_)=owner("anonymous")
    failed(wait{anonymous.bootstrap(completion:$0)},.notSignedIn,"bootstrap requires actual authentication")

    for field in ["loggedIn","available","guests","guest","username","discordName"]{
        let (bad,_)=owner("bad-field-"+field)
        failed(wait{bad.account(completion:$0)},.invalidResponse,"strict field \(field)")
    }
    for scenario in ["array","invalid-json","wrong-mime","oversize-name"]{
        let (bad,_)=owner(scenario)
        failed(wait{bad.account(completion:$0)},.invalidResponse,"reject malformed \(scenario)")
    }
    for scenario in ["bad-build-short","bad-build-ascii","bad-build-number"]{
        let (bad,_)=owner(scenario)
        failed(wait{bad.bootstrap(completion:$0)},.invalidResponse,"validate exact build \(scenario)")
    }
    for status in [403,500]{
        let (bad,_)=owner("http-\(status)")
        failed(wait{bad.account(completion:$0)},.httpStatus(status),"preserve HTTP \(status)")
    }
    for code in ["closed","vpn","lookalike","many"]{
        let (blocked,_)=owner("blocked-"+code)
        let result=wait{blocked.createGuest(name:"Normal Name",completion:$0)}
        failed(result,.guestRejected(code:code,message:"Fixture says "+code),"server guest block \(code)")
        if case .failure(let error)=result{check(error.guestBlock?.rawValue==code && error.message=="Fixture says "+code,"typed block and user text \(code)")}
    }
    let (denied,_)=owner("logical-reject")
    failed(wait{denied.createGuest(name:"Normal",completion:$0)},.guestRejected(code:"lookalike",message:"Pick another name"),"logical 2xx rejection is not a session")
    let (verify,_)=owner("verify-denied")
    failed(wait{verify.createGuest(name:"Normal",completion:$0)},.notSignedIn,"POST success still requires confirmed account")
    let (sanitized,_)=owner("sanitized-message")
    let sanitizedResult=wait{sanitized.createGuest(name:"Normal",completion:$0)}
    if case .failure(.guestRejected(let code,let message))=sanitizedResult{check(code=="many" && message=="Please wait","bounded display text strips control characters")}else{check(false,"reject sanitized message fixture")}

    let invalid=["","  \n\t  ",String(repeating:"a",count:25),"A\u{0000}B",String(repeating:"😀",count:13)]
    for (index,name) in invalid.enumerated(){
        let (bad,_)=owner("invalid-name-\(index)")
        failed(wait{bad.createGuest(name:name,completion:$0)},.invalidName,"invalid name cannot issue HTTP")
    }
    let (boundary,_)=owner("guest-boundary")
    check(success(wait{boundary.createGuest(name:String(repeating:"😀",count:12),completion:$0)},"24 UTF16 boundary").guest,"exact frontend UTF16 name boundary accepted")
    for scenario in ["length-limit","chunk-limit"]{
        let (large,_)=owner(scenario)
        failed(wait{large.account(completion:$0)},.responseTooLarge,"bounded streamed response \(scenario)")
    }
    for scenario in ["redirect-account","redirect-post"]{
        let (redirect,_)=owner(scenario)
        if scenario=="redirect-account"{failed(wait{redirect.account(completion:$0)},.redirectDisallowed,"account redirects denied before follow")}
        else{failed(wait{redirect.createGuest(name:"Normal",completion:$0)},.redirectDisallowed,"POST redirect never resubmits body")}
    }
    let (cancelled,cancelSession)=owner("cancelled")
    let cancelledCalls=Box<Int>();cancelledCalls.set(0)
    cancelled.account{_ in cancelledCalls.set(1)}
    pause(0.05);cancelled.cancel();pause(0.6)
    check(cancelledCalls.get()==0,"cancellation suppresses stale callback")
    check(plainGET(cancelSession,"/__health").1.statusCode==200,"cancellation preserves owner session")
    let (superseded,_)=owner("superseded")
    let oldCalls=Box<Int>();oldCalls.set(0)
    superseded.account{_ in oldCalls.set(1)}
    pause(0.05)
    check(success(wait{superseded.account(completion:$0)},"new generation").username=="Current generation","new generation receives current response")
    pause(0.6);check(oldCalls.get()==0,"superseded in-flight callback cannot escape")
    let deinitCalls=Box<Int>();deinitCalls.set(0)
    var released:Auth?=owner("released").0
    released!.account{_ in deinitCalls.set(1)};pause(0.05);released=nil;pause(0.6)
    check(deinitCalls.get()==0,"deinit cancels owned task without callback")
    let report:[String:Any]=["checks":checks,"passed":true,"scope":"owned loopback HTTP only; no original service POST"]
    let data=try!JSONSerialization.data(withJSONObject:report,options:[.sortedKeys])
    print(String(data:data,encoding:.utf8)!);exit(0)
}
DispatchQueue.main.setSpecific(key:mainQueueKey,value:true)
DispatchQueue.global(qos:.userInitiated).async{run()}
dispatchMain()
