// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CoreFoundation

/// The service's normal account/guest API. The caller owns its URLSession and
/// cookie storage; this helper never reads a browser profile or exports cookies.
final class NativeOriginalWorldAuthentication {
    struct Account:Equatable {
        let available:Bool,guests:Bool,loggedIn:Bool,guest:Bool
        let username:String
    }
    struct Connection {
        let session:URLSession
        let build:String,username:String
        let guest:Bool
    }
    enum GuestBlock:String,Equatable {case closed,vpn,lookalike,many}
    enum Failure:Error,Equatable {
        case invalidOrigin,invalidName,invalidResponse,responseTooLarge,redirectDisallowed,notSignedIn
        case transport(Int),httpStatus(Int),guestRejected(code:String,message:String)
        var guestBlock:GuestBlock?{if case .guestRejected(let code,_) = self{return GuestBlock(rawValue:code)};return nil}
        var message:String {
            switch self {
            case .invalidOrigin:return "INVALID ORIGINAL SERVICE ADDRESS"
            case .invalidName:return "ENTER A NAME OF 1 TO 24 CHARACTERS"
            case .invalidResponse:return "THE ORIGINAL SERVICE RETURNED AN INVALID RESPONSE"
            case .responseTooLarge:return "THE ORIGINAL SERVICE RESPONSE WAS TOO LARGE"
            case .redirectDisallowed:return "THE ORIGINAL SERVICE REDIRECTED THIS REQUEST. TRY SIGNING IN AGAIN."
            case .notSignedIn:return "THE ORIGINAL SERVICE HAS NOT CONFIRMED THIS SESSION"
            case .transport(let code):return "COULD NOT CONNECT TO THE ORIGINAL SERVICE (\(code))"
            case .httpStatus(let code):return "THE ORIGINAL SERVICE RETURNED HTTP \(code)"
            case .guestRejected(let code,let text):
                if !text.isEmpty{return text}
                switch GuestBlock(rawValue:code){
                case .closed:return "GUEST PLAY IS CURRENTLY CLOSED"
                case .vpn:return "THE ORIGINAL SERVICE DOES NOT ALLOW GUEST PLAY ON THIS CONNECTION"
                case .lookalike:return "THE ORIGINAL SERVICE REQUIRES A DIFFERENT NAME"
                case .many:return "THE ORIGINAL SERVICE'S GUEST SESSION LIMIT HAS BEEN REACHED"
                case nil:return "THE ORIGINAL SERVICE DID NOT ACCEPT THIS GUEST NAME"
                }
            }
        }
    }
    static let maximumResponseBytes=65_536
    let session:URLSession
    private let origin:URL
    private let lock=NSLock()
    private var generation:UInt64=0
    private var pending:URLSessionDataTask?
    private var receiver:Receiver?

    init(session:URLSession,loopbackTestOrigin:URL?=nil)throws {
        self.session=session
        if let test=loopbackTestOrigin {
            guard let parts=URLComponents(url:test,resolvingAgainstBaseURL:false),
                  ["http","https"].contains(parts.scheme?.lowercased() ?? ""),
                  ["127.0.0.1","localhost","::1","[::1]"].contains(parts.host?.lowercased() ?? ""),
                  parts.user==nil,parts.password==nil,parts.query==nil,parts.fragment==nil,
                  parts.path.isEmpty || parts.path=="/" else{throw Failure.invalidOrigin}
            origin=test
        }else{origin=URL(string:"https://play.samp.directory/")!}
    }
    deinit{pending?.cancel()}
    func cancel(){_=begin()}
    private func begin()->UInt64 {
        lock.lock();generation &+= 1;let value=generation,task=pending;pending=nil;receiver=nil;lock.unlock();task?.cancel();return value
    }
    private func current(_ value:UInt64)->Bool{lock.lock();defer{lock.unlock()};return generation==value}
    private func finish<T>(_ value:UInt64,_ result:Result<T,Failure>,_ completion:@escaping(Result<T,Failure>)->Void){
        lock.lock();guard generation==value else{lock.unlock();return};pending=nil;receiver=nil;lock.unlock()
        DispatchQueue.main.async{[weak self]in guard self?.current(value)==true else{return};completion(result)}
    }
    func account(completion:@escaping(Result<Account,Failure>)->Void){
        let value=begin();readAccount(value){[weak self] result in self?.finish(value,result,completion)}
    }
    func bootstrap(completion:@escaping(Result<Connection,Failure>)->Void){bootstrap(begin(),completion)}
    func createGuest(name:String,completion:@escaping(Result<Connection,Failure>)->Void){
        let value=begin(),name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty,name.utf16.count<=24,!name.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)})else{
            finish(value,.failure(.invalidName),completion);return
        }
        let body=try!JSONSerialization.data(withJSONObject:["name":name])
        request("/api/auth/guest",method:"POST",body:body,generation:value){[weak self] result in
            guard let self,self.current(value)else{return}
            switch result {
            case .failure(let error):self.finish(value,.failure(error),completion)
            case .success(let reply):
                if Self.boolean(reply["ok"])==false{self.finish(value,.failure(Self.rejection(reply)),completion);return}
                self.bootstrap(value,completion)
            }
        }
    }
    private func bootstrap(_ value:UInt64,_ completion:@escaping(Result<Connection,Failure>)->Void){
        readAccount(value){[weak self] result in
            guard let self,self.current(value)else{return}
            switch result {
            case .failure(let error):self.finish(value,.failure(error),completion)
            case .success(let account):
                guard account.loggedIn else{self.finish(value,.failure(.notSignedIn),completion);return}
                self.request("/game/build",generation:value){[weak self] result in
                    guard let self,self.current(value)else{return}
                    switch result {
                    case .failure(let error):self.finish(value,.failure(error),completion)
                    case .success(let object):
                        guard let build=object["build"]as?String,build.utf8.count==12,build.utf8.allSatisfy({(48...57).contains($0)})else{self.finish(value,.failure(.invalidResponse),completion);return}
                        self.finish(value,.success(Connection(session:self.session,build:build,username:account.username.isEmpty ? "PLAYER":account.username,guest:account.guest)),completion)
                    }
                }
            }
        }
    }
    private func readAccount(_ value:UInt64,_ completion:@escaping(Result<Account,Failure>)->Void){
        request("/api/auth/me",generation:value){result in
            completion(result.flatMap{object in
                guard let logged=Self.boolean(object["loggedIn"]),
                      let available=Self.optionalBoolean(object,"available",default:true),
                      let guests=Self.optionalBoolean(object,"guests",default:false),
                      let guest=Self.optionalBoolean(object,"guest",default:false)else{return .failure(.invalidResponse)}
                for key in ["username","discordName"]{if let raw=object[key],!(raw is NSNull){guard let text=raw as?String,text.utf8.count<=256 else{return .failure(.invalidResponse)}}}
                let name=object["username"]as?String ?? object["discordName"]as?String ?? ""
                return .success(Account(available:available,guests:guests,loggedIn:logged,guest:guest,username:name))
            })
        }
    }
    private static func boolean(_ value:Any?)->Bool?{guard let n=value as?NSNumber,CFGetTypeID(n)==CFBooleanGetTypeID()else{return nil};return n.boolValue}
    private static func optionalBoolean(_ object:[String:Any],_ key:String,default fallback:Bool)->Bool?{object[key]==nil ? fallback:boolean(object[key])}
    private static func rejection(_ object:[String:Any])->Failure{
        func text(_ key:String,_ maximum:Int)->String{String((object[key]as?String ?? "").unicodeScalars.filter{!CharacterSet.controlCharacters.contains($0)}.prefix(maximum).map(String.init).joined())}
        return .guestRejected(code:text("error",64),message:text("message",256))
    }
    private func request(_ path:String,method:String="GET",body:Data?=nil,generation value:UInt64,completion:@escaping(Result<[String:Any],Failure>)->Void){
        guard current(value),let url=URL(string:path,relativeTo:origin)?.absoluteURL else{return}
        var request=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:15)
        request.httpMethod=method;request.httpBody=body;request.httpShouldHandleCookies=true
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        if body != nil{request.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let observer=Receiver{[weak self] result in
            guard let self,self.current(value)else{return}
            switch result {
            case .failure(let error):completion(.failure(error))
            case .success(let (response,data)):
                let object=(try?JSONSerialization.jsonObject(with:data))as?[String:Any]
                guard (200...299).contains(response.statusCode)else{
                    if path=="/api/auth/guest",let object{completion(.failure(Self.rejection(object)))}else{completion(.failure(.httpStatus(response.statusCode)))};return
                }
                guard response.mimeType?.lowercased()=="application/json" || response.mimeType?.lowercased().hasSuffix("+json")==true,let object else{completion(.failure(.invalidResponse));return}
                completion(.success(object))
            }
        }
        let task=session.dataTask(with:request);task.delegate=observer
        lock.lock();guard generation==value else{lock.unlock();task.cancel();return};pending=task;receiver=observer;lock.unlock();task.resume()
    }
    /// Task-specific delegate keeps streaming JSON bounded and rejects redirects
    /// before another host/path can receive or automatically resubmit a request.
    private final class Receiver:NSObject,URLSessionDataDelegate,@unchecked Sendable {
        private var data=Data(),response:HTTPURLResponse?,failure:Failure?
        private let completion:(Result<(HTTPURLResponse,Data),Failure>)->Void
        init(_ completion:@escaping(Result<(HTTPURLResponse,Data),Failure>)->Void){self.completion=completion}
        func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping(URLRequest?)->Void){failure = .redirectDisallowed;completionHandler(nil)}
        func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive response:URLResponse,completionHandler:@escaping(URLSession.ResponseDisposition)->Void){
            guard let response=response as?HTTPURLResponse else{failure = .invalidResponse;completionHandler(.cancel);return}
            guard response.expectedContentLength<=Int64(NativeOriginalWorldAuthentication.maximumResponseBytes)else{failure = .responseTooLarge;completionHandler(.cancel);return}
            self.response=response;completionHandler(.allow)
        }
        func urlSession(_ session:URLSession,dataTask:URLSessionDataTask,didReceive chunk:Data){
            guard failure==nil else{return}
            guard chunk.count<=NativeOriginalWorldAuthentication.maximumResponseBytes-data.count else{failure = .responseTooLarge;dataTask.cancel();return}
            data.append(chunk)
        }
        func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){
            if let failure{completion(.failure(failure))}
            else if let error{completion(.failure(.transport((error as NSError).code)))}
            else if let response{completion(.success((response,data)))}
            else{completion(.failure(.invalidResponse))}
        }
    }
}
