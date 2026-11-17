// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Static resource requests use the same resolver for persistent local assets
/// and legacy development streaming. Gameplay/auth URLSessions are unchanged.
final class NativeResourceDataTask:NativeResourceTask {
    private let lock=NSLock()
    private var started=false,finished=false,cancelled=false
    private var remote:URLSessionTask?
    private let body:(NativeResourceDataTask)->Void
    private let completion:(Data?,URLResponse?,Error?)->Void
    fileprivate init(body:@escaping(NativeResourceDataTask)->Void,
                     completion:@escaping(Data?,URLResponse?,Error?)->Void){self.body=body;self.completion=completion}
    func resume(){
        lock.lock();guard !started,!finished else{lock.unlock();return};started=true;lock.unlock()
        DispatchQueue.global(qos:.utility).async{self.body(self)}
    }
    func cancel(){
        lock.lock();cancelled=true;let task=remote;lock.unlock();task?.cancel()
        DispatchQueue.global(qos:.utility).async{self.finish(nil,nil,URLError(.cancelled))}
    }
    fileprivate var isCancelled:Bool{lock.lock();defer{lock.unlock()};return cancelled}
    fileprivate func attach(_ task:URLSessionTask){lock.lock();remote=task;let stop=cancelled;lock.unlock();if stop{task.cancel()}}
    fileprivate func finish(_ data:Data?,_ response:URLResponse?,_ error:Error?){
        lock.lock();guard !finished else{lock.unlock();return};finished=true;remote=nil;let stop=cancelled;lock.unlock()
        completion(stop ? nil:data,stop ? nil:response,stop ? URLError(.cancelled):error)
    }
}

final class NativeResourceSession {
    static let shared=NativeResourceSession(store:.shared)
    private let store:NativeResourceStore,network:URLSession
    init(store:NativeResourceStore,network:URLSession = .shared){self.store=store;self.network=network}
    static func activate(){
        do {
            try shared.store.configureRuntimeValidation(identity:NativePreparedRuntimeVerifier.identity,validator:NativePreparedRuntimeVerifier.validate)
        }catch{
            // Integrity-only receipts cannot activate installed mode when the
            // native format verifier is unavailable. Development can continue.
            NSLog("Native resource verifier unavailable: %@",error.localizedDescription)
        }
        NativeResourceTransport.install({request,completion in shared.dataTask(with:request,completionHandler:completion)},localFile:{try shared.store.installedURL(for:$0)})
        NativeStockAssetAccess.installPreparedReader{url,maximum in try shared.store.localResource(for:url,maximumBytes:Int64(maximum))?.0}
    }
    func dataTask(with url:URL,completionHandler:@escaping(Data?,URLResponse?,Error?)->Void)->NativeResourceDataTask {
        dataTask(with:URLRequest(url:url),completionHandler:completionHandler)
    }
    func dataTask(with request:URLRequest,completionHandler:@escaping(Data?,URLResponse?,Error?)->Void)->NativeResourceDataTask {
        NativeResourceDataTask(body:{[store,network] task in
            guard !task.isCancelled else{return}
            guard let url=request.url else{task.finish(nil,nil,URLError(.badURL));return}
            let path=url.path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
            let resource=NativeResourceManifest.isResourceNamespace(path)
            let method=request.httpMethod ?? "GET"
            guard ["GET","HEAD"].contains(method),resource else{
                let remote=network.dataTask(with:request){task.finish($0,$1,$2)};task.attach(remote);remote.resume();return
            }
            do {
                if method=="HEAD",let file=try store.installedURL(for:url){
                    let size=(try file.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
                    let response=HTTPURLResponse(url:url,statusCode:200,httpVersion:"HTTP/1.1",headerFields:["Content-Length":String(size),"Content-Type":Self.contentType(path),"X-ZGTA-Resource-Source":"installed"])
                    task.finish(nil,response,nil);return
                }
                if method=="HEAD" {
                    if store.snapshot.mode == .installed{throw NativeResourceStore.Failure.missing(path)}
                    let remote=network.dataTask(with:request){task.finish($0,$1,$2)};task.attach(remote);remote.resume();return
                }
                if let (bytes,item)=try store.localResource(for:url){
                    let response=HTTPURLResponse(url:url,statusCode:200,httpVersion:"HTTP/1.1",headerFields:[
                        "Content-Length":String(item.bytes),"X-ZGTA-Resource-SHA256":item.sha256,
                        "Content-Type":Self.contentType(item.path),"X-ZGTA-Resource-Source":"installed"])
                    task.finish(bytes,response,nil);return
                }
                if store.snapshot.mode == .installed{throw NativeResourceStore.Failure.missing(path)}
                let remote=network.dataTask(with:request){task.finish($0,$1,$2)};task.attach(remote);remote.resume()
            }catch{task.finish(nil,nil,error)}
        },completion:completionHandler)
    }
    func installedURL(for url:URL)throws->URL?{try store.installedURL(for:url)}
    private static func contentType(_ path:String)->String {
        if path.hasSuffix(".json"){return "application/json"}
        if path.hasSuffix(".png"){return "image/png"}
        if path.hasSuffix(".jpg"){return "image/jpeg"}
        if path.hasSuffix(".webp"){return "image/webp"}
        if path.hasSuffix(".wav"){return "audio/wav"}
        return "application/octet-stream"
    }
}
