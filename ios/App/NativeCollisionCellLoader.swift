// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Main-thread request ownership; one active transfer/preparation and a bounded
/// queue of small descriptors. Only immutable CPU products cross from the worker.
/// Native physics-world installation remains the renderer/ground owner's job.
final class NativeCollisionCellLoader {
    enum Failure:Error {case pendingLimit,unavailable,cancelled}
    struct Prepared {
        let data:Data,collision:WorldCollision
        let ground:NativeGroundVehicle.PreparedCell?
    }
    typealias Completion=(Result<Prepared,Error>)->Void
    private struct Pending {
        let id:UUID,url:URL,configuration:NativeGroundVehicle.CellConfiguration?
        let completion:Completion
    }
    private struct Running {let item:Pending,job:Job}
    private var pending:[Pending]=[],running:Running?
    private static let cpu=DispatchQueue(label:"org.zgtasa.city-collision.prepare",qos:.utility)
    private let maximumPending:Int,maximumBytes:Int
    private let worker:DispatchQueue
    var pendingCount:Int{main();return pending.count}
    var activeCount:Int{main();return running == nil ? 0:1}
    init(maximumPending:Int=32,maximumBytes:Int=16*1024*1024,worker:DispatchQueue?=nil) {
        precondition((1...64).contains(maximumPending) && (16...64*1024*1024).contains(maximumBytes))
        self.maximumPending=maximumPending;self.maximumBytes=maximumBytes;self.worker=worker ?? Self.cpu
    }
    deinit{running?.job.cancel()}
    private func main(){dispatchPrecondition(condition:.onQueue(.main))}
    @discardableResult func load(url:URL,configuration:NativeGroundVehicle.CellConfiguration?,completion:@escaping Completion)->UUID {
        main();let id=UUID()
        guard pending.count<maximumPending else{DispatchQueue.main.async{completion(.failure(Failure.pendingLimit))};return id}
        pending.append(.init(id:id,url:url,configuration:configuration,completion:completion));pump();return id
    }
    func cancel(_ id:UUID) {
        main()
        if let index=pending.firstIndex(where:{$0.id==id}) {
            let item=pending.remove(at:index);DispatchQueue.main.async{item.completion(.failure(Failure.cancelled))}
        }
        if running?.item.id==id{running?.job.cancel()}
    }
    /// Running CPU work keeps its serial slot until it actually exits. Clearing
    /// pending descriptors never leaves queued closures retaining old payloads.
    func reset() {
        main();let retired=pending;pending.removeAll();running?.job.cancel()
        for item in retired{DispatchQueue.main.async{item.completion(.failure(Failure.cancelled))}}
    }
    private func pump() {
        main();guard running==nil,!pending.isEmpty else{return}
        let item=pending.removeFirst()
        let job=Job(url:item.url,configuration:item.configuration,maximumBytes:maximumBytes,worker:worker){[weak self] result in
            guard let self,self.running?.item.id==item.id else{return}
            self.running=nil
            // Release this active slot before a callback can enqueue/reenter.
            item.completion(result);self.pump()
        }
        running = .init(item:item,job:job);job.start()
    }
    private final class Job {
        private let url:URL,configuration:NativeGroundVehicle.CellConfiguration?,maximumBytes:Int
        private let completion:Completion,lock=NSLock()
        private let worker:DispatchQueue
        private var cancelled=false,finished=false,request:NativeResourceTask?
        init(url:URL,configuration:NativeGroundVehicle.CellConfiguration?,maximumBytes:Int,worker:DispatchQueue,completion:@escaping Completion) {
            self.url=url;self.configuration=configuration;self.maximumBytes=maximumBytes;self.worker=worker;self.completion=completion
        }
        private var isCancelled:Bool{lock.lock();defer{lock.unlock()};return cancelled}
        func cancel(){lock.lock();cancelled=true;let task=request;request=nil;lock.unlock();task?.cancel()}
        func start() {
            var request=URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:30)
            request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
            let task=NativeResourceTransport.boundedDataTask(with:request,maximumBytes:maximumBytes){[self] data,response,error in
                lock.lock();self.request=nil;lock.unlock()
                guard !isCancelled else{finish(.failure(Failure.cancelled));return}
                guard error==nil,let http=response as?HTTPURLResponse,http.statusCode==200,http.url==url,
                      let data,data.count<=maximumBytes else{finish(.failure(error ?? Failure.unavailable));return}
                worker.async{[self]in autoreleasepool {
                    let result:Result<Prepared,Error>=Result {
                        guard !isCancelled else{throw Failure.cancelled}
                        let collision=try WorldCollision(data:data)
                        guard !isCancelled else{throw Failure.cancelled}
                        let ground=try configuration.flatMap{$0.ready ? try NativeGroundVehicle.prepareCell(data,configuration:$0):nil}
                        guard !isCancelled else{throw Failure.cancelled}
                        return .init(data:data,collision:collision,ground:ground)
                    }
                    finish(result)
                }}
            }
            lock.lock();let cancelled=self.cancelled;if !cancelled{self.request=task};lock.unlock()
            if cancelled{task.cancel();finish(.failure(Failure.cancelled))}else{task.resume()}
        }
        private func finish(_ result:Result<Prepared,Error>) {
            DispatchQueue.main.async{[self]in
                guard !finished else{return};finished=true
                completion(isCancelled ? .failure(Failure.cancelled):result)
            }
        }
    }
}
