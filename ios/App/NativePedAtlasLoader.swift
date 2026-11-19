// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Bounded ownership of encoded ordinary-ped families. CPU validation precedes
/// upload; payload consumption releases its byte reservation after admission.
final class NativePedAtlasLoader {
    struct Limits {
        var activeFamilies=2,activeTransfers=4,requests=32
        var encodedBytes=24*1024*1024,manifestBytes=64*1024
    }
    struct Snapshot {let families:Int,transfers:Int,requests:Int,encodedBytes:Int,payloads:Int}
    enum Failure:Error,LocalizedError,Equatable {
        case cancelled,unavailable,invalidFamily,invalidResource,queueFull,budget
        var errorDescription:String? {
            switch self {
            case .cancelled:return "Pedestrian atlas loading cancelled"
            case .unavailable:return "Pedestrian atlas family unavailable"
            case .invalidFamily:return "Invalid pedestrian atlas family"
            case .invalidResource:return "Pedestrian atlas member validation failed"
            case .queueFull:return "Pedestrian atlas load queue is full"
            case .budget:return "Pedestrian atlas exceeds the encoded resource budget"
            }
        }
    }
    final class Request {
        let id=UUID()
        private let lock=NSLock()
        private var cancelled=false
        fileprivate var cancellation:(()->Void)?
        var isCancelled:Bool{lock.lock();defer{lock.unlock()};return cancelled}
        func cancel(){lock.lock();guard !cancelled else{lock.unlock();return};cancelled=true;let body=cancellation;lock.unlock();body?()}
    }
    final class Payload {
        let manifest:NativePedAtlasFamily
        let source,familyPath:String
        let world:WorldBinary
        let layout:NativePedAtlasLayout.Validated
        private let lock=NSLock()
        private var files:[String:Data]?
        private var consuming=false,closed=false
        private let release:()->Void
        fileprivate init(manifest:NativePedAtlasFamily,source:String,familyPath:String,world:WorldBinary,layout:NativePedAtlasLayout.Validated,
                         files:[String:Data],release:@escaping()->Void) {
            self.manifest=manifest;self.source=source;self.familyPath=familyPath;self.world=world;self.layout=layout;self.files=files;self.release=release
        }
        /// Encoded data cannot queue indefinitely after the owner abandons it.
        /// The consumer must not retain these byte carriers after the closure.
        func consume<T>(_ body:(NativePedAtlasFamily,[String:Data])throws->T)rethrows->T? {
            lock.lock();guard !closed,!consuming,let values=files else{lock.unlock();return nil}
            files=nil;consuming=true;lock.unlock()
            defer{lock.lock();consuming=false;closed=true;lock.unlock();release()}
            return try body(manifest,values)
        }
        func close(){
            lock.lock();guard !closed,!consuming else{lock.unlock();return}
            closed=true;files=nil;lock.unlock();release()
        }
        deinit{close()}
    }
    typealias Transfer=(URL,Int,@escaping NativeResourceTransport.Completion)->NativeResourceTask
    typealias Completion=(Result<Payload,Error>)->Void
    private enum Phase {case queued,metadata,reserving,members,delivered}
    private struct Flight {let role:String;var task:NativeResourceTask?}
    private final class State {
        let request:Request,source:String,path:String,model:String,priority:Int,order:UInt64,completion:Completion
        var phase=Phase.queued,manifest:NativePedAtlasFamily?,files:[String:Data]=[:],remaining:[String]=[]
        var inFlight:[UUID:Flight]=[:],reserved=0,completed=false
        weak var payload:Payload?
        init(request:Request,source:String,path:String,model:String,priority:Int,order:UInt64,completion:@escaping Completion) {
            self.request=request;self.source=source;self.path=path;self.model=model;self.priority=priority;self.order=order;self.completion=completion
        }
    }
    private let queue=DispatchQueue(label:"com.zema.zgtasa.ped-atlas",qos:.utility)
    private let queueKey=DispatchSpecificKey<UInt8>()
    private let callbackQueue:DispatchQueue
    private let limits:Limits,transfer:Transfer
    private var states:[UUID:State]=[:],order:UInt64=0,transfers=0,reserved=0,pumpPending=false
    init(limits:Limits=Limits(),callbackQueue:DispatchQueue = .main,transfer:@escaping Transfer = {url,maximum,completion in
        NativeResourceTransport.boundedDataTask(with:url,maximumBytes:maximum,completionHandler:completion)
    }) {
        precondition(limits.activeFamilies>0 && limits.activeTransfers>0 && limits.requests>=limits.activeFamilies &&
                     limits.encodedBytes>=limits.manifestBytes && limits.manifestBytes>0)
        self.limits=limits;self.callbackQueue=callbackQueue;self.transfer=transfer
        queue.setSpecific(key:queueKey,value:1)
    }
    @discardableResult func load(model:String,path:String,source:String,server:ServerAddress,priority:Int=0,completion:@escaping Completion)->Request {
        let request=Request()
        request.cancellation={[weak self,weak request] in guard let self,let request else{return};self.queue.async{self.cancel(request.id)}}
        queue.async{[weak self] in
            guard let self else{return}
            if request.isCancelled {self.deliver(request,completion,.failure(Failure.cancelled));return}
            guard NativePedAtlasFamily.digest(in:path,model:model) != nil else{self.deliver(request,completion,.failure(Failure.invalidFamily));return}
            guard self.states.count<self.limits.requests else{self.deliver(request,completion,.failure(Failure.queueFull));return}
            self.order &+= 1
            self.states[request.id]=State(request:request,source:source,path:path,model:model,priority:priority,order:self.order,completion:completion)
            self.origins[request.id]=server
            self.schedulePump()
        }
        return request
    }
    private var origins:[UUID:ServerAddress]=[:]
    func cancelAll(){queue.async{[weak self] in guard let self else{return};for state in Array(self.states.values){state.request.cancel();self.cancel(state.request.id)}}}
    func snapshot(_ completion:@escaping(Snapshot)->Void){queue.async{completion(self.currentSnapshot())}}
    private func currentSnapshot()->Snapshot {
        Snapshot(families:states.values.filter{$0.phase != .queued}.count,transfers:transfers,requests:states.count,
                 encodedBytes:reserved,payloads:states.values.filter{$0.phase == .delivered}.count)
    }
    private func sortedStates()->[State]{states.values.sorted{a,b in a.priority==b.priority ? a.order<b.order:a.priority>b.priority}}
    private func schedulePump(){guard !pumpPending else{return};pumpPending=true;queue.async{[weak self] in self?.pump()}}
    private func pump(){
        pumpPending=false
        for state in sortedStates() where state.request.isCancelled{cancel(state.request.id)}
        var active=states.values.filter{$0.phase != .queued}.count
        for state in sortedStates() where state.phase == .queued && active<limits.activeFamilies {
            guard transfers<limits.activeTransfers,reserved<=limits.encodedBytes-limits.manifestBytes else{break}
            state.phase = .metadata;state.reserved=limits.manifestBytes;reserved+=limits.manifestBytes;active+=1
            start(state,role:"$manifest",path:state.path,maximum:limits.manifestBytes)
        }
        for state in sortedStates() where state.phase == .reserving {
            guard let manifest=state.manifest else{fail(state,Failure.invalidFamily);continue}
            let bytes=manifest.resources.all.values.reduce(0){$0+$1.bytes}
            guard bytes<=limits.encodedBytes else{fail(state,Failure.budget);continue}
            guard reserved<=limits.encodedBytes-bytes else{continue}
            reserved+=bytes;state.reserved=bytes;state.remaining=manifest.resources.all.keys.sorted();state.phase = .members
        }
        var progress=true
        while transfers<limits.activeTransfers && progress {
            progress=false
            for state in sortedStates() where state.phase == .members && !state.remaining.isEmpty {
                guard transfers<limits.activeTransfers else{break}
                let role=state.remaining.removeFirst()
                guard let resource=state.manifest?.resources.all[role] else{fail(state,Failure.invalidFamily);continue}
                start(state,role:role,path:resource.path,maximum:resource.bytes);progress=true
            }
        }
    }
    private func start(_ state:State,role:String,path:String,maximum:Int){
        guard states[state.request.id] === state,!state.request.isCancelled else{cancel(state.request.id);return}
        guard let server=origins[state.request.id] else{fail(state,Failure.unavailable);return}
        let taskID=UUID(),requestID=state.request.id,url=server.path(path)
        // Reserve ownership before the factory: even an inline completion or
        // reentrant cancellation cannot leave an untracked transfer alive.
        state.inFlight[taskID]=Flight(role:role,task:nil);transfers+=1
        let task=transfer(url,maximum){[weak self] data,response,error in
            self?.queue.async{[weak self] in self?.received(requestID,task:taskID,url:url,data:data,response:response,error:error)}
        }
        guard states[requestID] === state,state.inFlight[taskID] != nil,!state.request.isCancelled else{task.cancel();return}
        state.inFlight[taskID]?.task=task;task.resume()
    }
    private func received(_ id:UUID,task:UUID,url:URL,data:Data?,response:URLResponse?,error:Error?){
        guard let state=states[id],let flight=state.inFlight.removeValue(forKey:task) else{return}
        transfers-=1
        guard !state.request.isCancelled else{cancel(id);return}
        guard error==nil,let http=response as?HTTPURLResponse,http.statusCode==200,http.url==url,let data else{fail(state,error ?? Failure.unavailable);return}
        if flight.role=="$manifest" {
            guard data.count<=limits.manifestBytes,let expected=NativePedAtlasFamily.digest(in:state.path,model:state.model),
                  NativePedAtlasLayout.digest(data)==expected,
                  let manifest=try? JSONDecoder().decode(NativePedAtlasFamily.self,from:data),
                  (try? manifest.validate(expectedModel:state.model)) != nil else{fail(state,Failure.invalidFamily);return}
            reserved-=state.reserved;state.reserved=0;state.manifest=manifest;state.phase = .reserving
        }else{
            guard let resource=state.manifest?.resources.all[flight.role],(try? resource.validate(data)) != nil else{fail(state,Failure.invalidResource);return}
            state.files[flight.role]=data
            if state.remaining.isEmpty && state.inFlight.isEmpty {ready(state)}
        }
        schedulePump()
    }
    private func ready(_ state:State){
        guard let manifest=state.manifest,state.files.count==manifest.resources.all.count else{fail(state,Failure.invalidResource);return}
        guard let binary=state.files["mesh"],let image=state.files["atlas"],let layoutData=state.files["layout"],
              let world=try? WorldBinary(data:binary),let layout=try? JSONDecoder().decode(NativePedAtlasLayout.self,from:layoutData),
              let validated=try? layout.validate(mesh:binary,png:image,world:world),
              (try? manifest.validateSource(layout:layout)) != nil else{fail(state,Failure.invalidResource);return}
        guard !state.request.isCancelled else{cancel(state.request.id);return}
        let id=state.request.id
        let payload=Payload(manifest:manifest,source:state.source,familyPath:state.path,world:world,layout:validated,files:state.files){[weak self] in
            self?.queue.async{[weak self] in self?.released(id)}
        }
        state.files.removeAll();state.phase = .delivered;state.payload=payload;state.completed=true
        deliver(state.request,state.completion,.success(payload))
    }
    private func deliver(_ request:Request,_ completion:@escaping Completion,_ result:Result<Payload,Error>){
        callbackQueue.async{
            if request.isCancelled {if case .success(let payload)=result{payload.close()};completion(.failure(Failure.cancelled))}
            else{completion(result)}
        }
    }
    private func clear(_ state:State){
        for flight in state.inFlight.values{flight.task?.cancel()}
        transfers-=state.inFlight.count;state.inFlight.removeAll();state.remaining.removeAll();state.files.removeAll()
        reserved-=state.reserved;state.reserved=0
        states.removeValue(forKey:state.request.id);origins.removeValue(forKey:state.request.id)
        precondition(transfers>=0 && reserved>=0)
    }
    private func fail(_ state:State,_ error:Error){
        let complete=state.completed;state.completed=true;clear(state)
        if !complete{deliver(state.request,state.completion,.failure(error))}
        schedulePump()
    }
    private func cancel(_ id:UUID){
        guard let state=states[id] else{return}
        if state.phase == .delivered {
            // A consuming payload keeps its reservation until its body returns.
            // Rendering still fences publication by Request.isCancelled.
            state.payload?.close()
            if state.payload==nil{released(id)}
        }else{fail(state,Failure.cancelled)}
    }
    private func released(_ id:UUID){guard let state=states[id] else{return};clear(state);schedulePump()}
    deinit {
        let stop={for state in self.states.values{for flight in state.inFlight.values{flight.task?.cancel()};state.payload?.close()}}
        if DispatchQueue.getSpecific(key:queueKey) != nil{stop()}else{queue.sync(execute:stop)}
    }
}
