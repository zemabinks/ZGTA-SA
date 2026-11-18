// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit

// Activation's engine dependency is deliberately absent. Synthetic transport
// admission below has its own identity and never certifies engine playability.
enum NativePreparedRuntimeVerifier {
    static let identity="unavailable-engine-in-bounded-transport-target"
    static func validate(_ m:NativeResourceManifest,_ r:@escaping(String)throws->URL)throws{throw CheckFailure.failed("engine unavailable")}
}
enum NativeSAMPStockAssetLoader {enum Failure:Error{case invalidURL,cancelled,encoding,redirect,http(Int),limit(String)}}
private enum CheckFailure:Error{case failed(String)}
private final class Reads {
    private let lock=NSLock();private var total=0
    func read(_ url:URL)throws->Data{lock.lock();total+=1;lock.unlock();return try Data(contentsOf:url)}
    var count:Int{lock.lock();defer{lock.unlock()};return total}
}
private final class Reply {
    private let lock=NSLock()
    private var value:(Data?,URLResponse?,Error?)?,calls=0,onMain=false
    func finish(_ d:Data?,_ r:URLResponse?,_ e:Error?){lock.lock();calls+=1;if calls==1{value=(d,r,e)};onMain = onMain || Thread.isMainThread;lock.unlock()}
    var result:(Data?,URLResponse?,Error?)?{lock.lock();defer{lock.unlock()};return value}
    var count:Int{lock.lock();defer{lock.unlock()};return calls}
    var main:Bool{lock.lock();defer{lock.unlock()};return onMain}
}
@main private struct BoundedResourceRegression {
    static var checks=0
    static func check(_ value:Bool,_ label:String)throws{checks+=1;guard value else{throw CheckFailure.failed(label)}}
    static func wait(_ predicate:()->Bool)throws{
        let end=Date().addingTimeInterval(12)
        while !predicate(),Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.005))}
        try check(predicate(),"bounded completion")
    }
    static func hash(_ d:Data)->String{SHA256.hash(data:d).map{String(format:"%02x",$0)}.joined()}
    static func makeStore(_ root:URL)throws->(NativeResourceStore,Data,NativeResourceManifest,Reads){
        let payload=Data((0..<4096).map{UInt8($0%251)})
        var bodies:[String:Data]=[:]
        for path in NativeResourceManifest.requiredPaths{
            bodies[path]=path.hasSuffix(".json") ? try JSONSerialization.data(withJSONObject:["authoredTransportMarker":path]):Data(("authored transport marker "+path).utf8)
        }
        bodies["game/world/authored.bin"]=Data("authored geometry transport marker".utf8)
        bodies["game/world/authored.png"]=Data("authored atlas transport marker".utf8)
        bodies["game/native/bounded.bin"]=payload
        let rows=bodies.map{NativeResourceManifest.Resource(path:$0.key,bytes:Int64($0.value.count),sha256:hash($0.value),required:true)}
        let first=NativeResourceManifest(schema:1,profile:NativeResourceManifest.profileName,contentID:String(repeating:"0",count:64),resources:rows)
        let manifest=NativeResourceManifest(schema:1,profile:first.profile,contentID:first.identity,resources:rows)
        let package=root.appendingPathComponent("package"),blobs=package.appendingPathComponent("blobs")
        try FileManager.default.createDirectory(at:blobs,withIntermediateDirectories:true)
        for row in rows{try bodies[row.path]!.write(to:blobs.appendingPathComponent(row.sha256))}
        try JSONEncoder().encode(manifest).write(to:package.appendingPathComponent(NativeResourceManifest.filename))
        let reads=Reads()
        let store=NativeResourceStore(root:root.appendingPathComponent("store"),validationIdentity:"synthetic-bounded-transport-v1",runtimeValidator:{m,resolve in
            for row in m.resources{guard try Data(contentsOf:resolve(row.path))==bodies[row.path] else{throw CheckFailure.failed("synthetic bytes")}}
        },runtimeDataReader:reads.read)
        var result:Result<NativeResourceStore.Snapshot,Error>?
        store.importPreparedFolder(package,progress:{_ in},completion:{result=$0})
        try wait{result != nil};_ = try result!.get();try store.setMode(.installed)
        return(store,payload,manifest,reads)
    }
    static func request(_ create:(Reply)->NativeResourceTask,cancel:Bool=false)throws->Reply{
        let reply=Reply(),task=create(reply)
        if cancel{task.cancel();task.cancel()}
        task.resume();task.resume();try wait{reply.result != nil}
        RunLoop.current.run(until:Date().addingTimeInterval(0.04))
        try check(reply.count==1,"completion exactly once");try check(!reply.main,"background completion")
        return reply
    }
    static func main()throws{
        let config=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:String]
        let origin=URL(string:config["origin"]!)!,root=URL(fileURLWithPath:config["work"]!,isDirectory:true)
        func url(_ path:String)->URL{origin.appendingPathComponent(path)}
        func fallback(_ path:String,_ cap:Int)throws->Reply{try request{r in NativeResourceTransport.boundedDataTask(with:url(path),maximumBytes:cap,completionHandler:r.finish)}}
        let exact=try fallback("bytes/4096",4096)
        try check(exact.result!.0==Data((0..<4096).map{UInt8($0%251)}) && exact.result!.2==nil,"fallback URL overload exact cap")
        let chunked=try fallback("chunked/4096",4096)
        try check(chunked.result!.0==exact.result!.0 && chunked.result!.2==nil,"chunked response exact cap and order")
        let undelimited=try fallback("unknown-length",4096)
        try check(undelimited.result!.0==exact.result!.0 && undelimited.result!.2==nil,"close-delimited unknown-length stream")
        for path in ["bytes/4097","chunked/4097","declared","gzip","redirect","short","bad-length","conflicting-length","status"]{
            let r=try fallback(path,4096)
            try check(r.result!.0==nil && r.result!.2 != nil,"reject without partial success "+path)
            if ["bytes/4097","chunked/4097","declared"].contains(path){try check(r.result!.2 as? NativeBoundedResourceTask.Failure == .limit,"actual cap failure "+path+" observed "+String(reflecting:r.result!.2))}
            if path=="gzip"{try check(r.result!.2 as? NativeBoundedResourceTask.Failure == .encoding,"encoding rejected at response")}
            if path=="status"{try check(r.result!.2 as? NativeBoundedResourceTask.Failure == .http(503),"HTTP status rejected at response")}
            if path=="redirect"{try check(r.result!.2 as? NativeBoundedResourceTask.Failure == .redirect,"fallback redirect rejected")}
        }
        for cap in [0,-1,NativeBoundedResourceTask.maximumSupportedBytes+1]{
            let r=try fallback("must-not-request",cap)
            try check(r.result!.2 as? NativeBoundedResourceTask.Failure == .invalidMaximum,"invalid cap before network")
        }
        let cancelled=try request({r in NativeResourceTransport.boundedDataTask(with:url("must-not-request"),maximumBytes:16,completionHandler:r.finish)},cancel:true)
        try check((cancelled.result!.2 as? URLError)?.code == .cancelled,"cancel before resume")
        let invalidURL=try request{r in NativeResourceTransport.boundedDataTask(with:URL(string:"file:///authored-no-read")!,maximumBytes:16,completionHandler:r.finish)}
        try check(invalidURL.result!.2 as? NativeBoundedResourceTask.Failure == .invalidURL,"non-HTTP fallback rejected")
        let inflight=Reply(),slow=NativeResourceTransport.boundedDataTask(with:url("slow"),maximumBytes:4096,completionHandler:inflight.finish)
        slow.resume();DispatchQueue.global().asyncAfter(deadline:.now()+0.08){slow.cancel();slow.cancel()}
        try wait{inflight.result != nil};RunLoop.current.run(until:Date().addingTimeInterval(0.2))
        try check(inflight.count==1 && inflight.result!.0==nil && (inflight.result!.2 as? URLError)?.code == .cancelled,"inflight cancellation exactly once")
        var racers:[Reply]=[]
        for _ in 0..<16{
            let r=Reply(),t=NativeResourceTransport.boundedDataTask(with:url("bytes/64"),maximumBytes:64,completionHandler:r.finish)
            racers.append(r);DispatchQueue.global().async{t.resume()};DispatchQueue.global().async{t.cancel()}
        }
        try wait{racers.allSatisfy{$0.result != nil}}
        RunLoop.current.run(until:Date().addingTimeInterval(0.15))
        try check(racers.allSatisfy{$0.count==1 && !$0.main},"concurrent resume/cancel each completes once")

        let (store,payload,manifest,reads)=try makeStore(root)
        let configuration=URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage?.setCookie(HTTPCookie(properties:[.domain:"127.0.0.1",.path:"/",.name:"authored-bounded",.value:"synthetic-only"])!)
        let network=URLSession(configuration:configuration);defer{network.invalidateAndCancel()}
        let session=NativeResourceSession(store:store,network:network)
        NativeResourceTransport.install({session.dataTask(with:$0,completionHandler:$1)},localFile:{try store.installedURL(for:$0)},bounded:{session.boundedDataTask(with:$0,maximumBytes:$1,completionHandler:$2)})
        func admitted(_ path:String,_ cap:Int=4096,_ method:String="GET")throws->Reply{
            var q=URLRequest(url:url(path));q.httpMethod=method
            return try request{r in NativeResourceTransport.boundedDataTask(with:q,maximumBytes:cap,completionHandler:r.finish)}
        }
        let local=try admitted("game/native/bounded.bin")
        try check(local.result!.0==payload && local.result!.2==nil && (local.result!.1 as? HTTPURLResponse)?.value(forHTTPHeaderField:"X-ZGTA-Resource-Source")=="installed","actual admitted Store bytes")
        let head=try admitted("game/native/bounded.bin",4096,"HEAD")
        try check(head.result!.0==nil && head.result!.2==nil && head.result!.1?.expectedContentLength==4096,"installed HEAD")
        let unverified=NativeResourceStore(root:root.appendingPathComponent("store"))
        let unverifiedSession=NativeResourceSession(store:unverified,network:network)
        let blocked=try request{r in unverifiedSession.boundedDataTask(with:url("game/native/bounded.bin"),maximumBytes:4096,completionHandler:r.finish)}
        try check(!unverified.snapshot.hasPlayableInstallation && blocked.result!.0==nil && blocked.result!.2 != nil,"integrity-only reopened receipt cannot bypass runtime admission")
        for (path,cap,method) in [("game/native/bounded.bin",4095,"GET"),("game/native/bounded.bin",4095,"HEAD"),("game/native/absent.bin",4096,"GET"),("game/native/bounded.bin?invalid=1",4096,"GET")]{
            let before=reads.count
            // URLRequest is built explicitly for query validation below.
            let r:Reply
            if path.contains("?"){
                r=try request{r in session.boundedDataTask(with:URL(string:origin.absoluteString+"/"+path)!,maximumBytes:cap,completionHandler:r.finish)}
            }else{r=try admitted(path,cap,method)}
            try check(r.result!.0==nil && r.result!.2 != nil,"installed rejection never streams "+path+method)
            try check(reads.count==before,"rejected installed request precedes payload allocation "+path+method)
        }
        let api=try admitted("api/echo")
        let echoed=try JSONSerialization.jsonObject(with:api.result!.0!) as! [String:Any]
        try check(api.result!.2==nil && echoed["cookie"] as? Bool == true && echoed["identity"] as? Bool == true,"ordinary API network retains configured cookie and identity encoding")
        try store.setMode(.development)
        let development=try admitted("game/native/bounded.bin")
        try check(development.result!.0==Data("development-network-body".utf8) && development.result!.2==nil,"unbound development origin uses capped HTTP")
        let redirected=try admitted("redirect")
        try check(redirected.result!.2 as? NativeBoundedResourceTask.Failure == .redirect,"configured session rejects redirect")
        let inner=Reply(),outer=session.boundedDataTask(with:url("slow"),maximumBytes:4096,completionHandler:inner.finish)
        outer.resume();DispatchQueue.global().asyncAfter(deadline:.now()+0.08){outer.cancel();outer.cancel()}
        try wait{inner.result != nil};RunLoop.current.run(until:Date().addingTimeInterval(0.2))
        try check(inner.count==1 && inner.result!.0==nil && (inner.result!.2 as? URLError)?.code == .cancelled,"Session cancellation reaches generic inner streaming task")
        let disabled=URLSessionConfiguration.ephemeral;disabled.httpShouldSetCookies=false
        disabled.httpCookieStorage?.setCookie(HTTPCookie(properties:[.domain:"127.0.0.1",.path:"/",.name:"authored-bounded",.value:"synthetic-only"])!)
        let noCookies=URLSession(configuration:disabled);defer{noCookies.invalidateAndCancel()}
        let cookieSession=NativeResourceSession(store:store,network:noCookies)
        let ignored=try request{r in cookieSession.boundedDataTask(with:url("api/echo-disabled"),maximumBytes:4096,completionHandler:r.finish)}
        let noEcho=try JSONSerialization.jsonObject(with:ignored.result!.0!) as! [String:Any]
        try check(ignored.result!.2==nil && noEcho["cookie"] as? Bool == false,"explicit cookie-disabled session remains cookie-disabled")
        try store.setMode(.installed)
        let row=manifest.resources.first{$0.path=="game/native/bounded.bin"}!
        try Data(repeating:0,count:payload.count).write(to:root.appendingPathComponent("store/blobs/"+row.sha256))
        let corrupt=try admitted("game/native/bounded.bin")
        try check(corrupt.result!.0==nil && corrupt.result!.2 != nil,"corrupt installed body never streams")
        try check(!store.snapshot.hasPlayableInstallation,"actual fault revokes exact installed admission")
        // An old-only installer must clear the optional bounded resolver, never
        // invoke a whole-body factory and check its result after allocation.
        var oldCalls=0
        NativeResourceTransport.install({q,c in oldCalls+=1;return network.dataTask(with:q,completionHandler:c)})
        let cleared=try fallback("chunked/4097",4096)
        try check(cleared.result!.2 != nil && oldCalls==0,"atomic old install clears bounded factory; streaming fallback retained")
        let report:[String:Any]=["status":"PASS","checks":checks,"scope":"actual Foundation streaming + actual Store/Session with synthetic admission; no engine or GPU claim"]
        try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys,.prettyPrinted]).write(to:root.appendingPathComponent("report.json"))
        print("NATIVE_BOUNDED_RESOURCES_PASS checks=\(checks)")
    }
}
