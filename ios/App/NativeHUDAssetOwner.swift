// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Main-thread owner for optional static HUD batches. Request epochs survive
/// cancellation callbacks; a repeated key becomes ready only after decoding.
/// Polling uses the existing visible game's HUD tick, never another timer.
final class NativeHUDAssetOwner<Key:Equatable> {
    struct Request {
        let url:URL
        let maximumBytes:Int
    }
    typealias Factory=(URL,Int,@escaping NativeResourceTransport.Completion)->NativeResourceTask
    private enum Phase:Equatable {case idle,loading,delivering,ready,failed}
    private(set) var key:Key?
    private var epoch=UUID(),phase=Phase.idle
    private var tasks:[String:NativeResourceTask]=[:]
    private var pending=Set<String>(),files:[String:Data]=[:]
    private var validSource:(()->Bool)?
    private var publish:(([String:Data])->Bool)?
    private var failedAttempts=0,retryAfter = -Double.infinity
    private let clock:()->Double
    private let factory:Factory

    init(clock:@escaping()->Double={ProcessInfo.processInfo.systemUptime},
         factory:@escaping Factory={url,maximum,completion in
             NativeResourceTransport.boundedDataTask(with:url,maximumBytes:maximum,completionHandler:completion)
         }) {
        self.clock=clock;self.factory=factory
    }
    deinit {for task in tasks.values{task.cancel()}}
    func needsLoad(for key:Key)->Bool {
        precondition(Thread.isMainThread)
        guard clock().isFinite else{return false}
        if self.key != key{return true}
        switch phase {
        case .idle:return true
        case .failed:return clock()>=retryAfter
        case .loading,.delivering,.ready:return false
        }
    }
    func cancel() {
        precondition(Thread.isMainThread)
        // Retire before cancelling: a local task may complete synchronously.
        epoch=UUID();let previous=Array(tasks.values)
        tasks.removeAll();pending.removeAll();files.removeAll();publish=nil;validSource=nil
        key=nil;phase = .idle;failedAttempts=0;retryAfter = -.infinity
        previous.forEach{$0.cancel()}
    }
    @discardableResult func load(key:Key,requests:[String:Request],
        isCurrent:@escaping()->Bool,publish:@escaping([String:Data])->Bool)->Bool {
        precondition(Thread.isMainThread)
        guard isCurrent(),needsLoad(for:key)else{return false}
        let attempts=self.key==key ? failedAttempts:0
        cancel();self.key=key;failedAttempts=attempts
        self.validSource=isCurrent;self.publish=publish
        phase = .loading
        guard !requests.isEmpty,requests.values.allSatisfy({NativeBoundedResourceTask.validMaximum($0.maximumBytes)})else {
            finish(accepted:false);return true
        }
        pending=Set(requests.keys);let token=epoch
        for name in requests.keys.sorted() {
            let request=requests[name]!
            let task=factory(request.url,request.maximumBytes){[weak self]data,response,error in
                DispatchQueue.main.async { [weak self] in
                    self?.receive(name:name,epoch:token,maximum:request.maximumBytes,
                                  data:data,response:response,error:error)
                }
            }
            guard token==epoch,phase == .loading else{task.cancel();return true}
            tasks[name]=task
            task.resume()
            guard token==epoch,phase == .loading else{return true}
        }
        return true
    }
    private func receive(name:String,epoch token:UUID,maximum:Int,
                         data:Data?,response:URLResponse?,error:Error?) {
        precondition(Thread.isMainThread)
        guard token==epoch,phase == .loading,pending.remove(name) != nil else{return}
        tasks[name]=nil
        if error==nil,(response as?HTTPURLResponse)?.statusCode==200,
           let data,data.count<=maximum{files[name]=data}
        guard pending.isEmpty else{return}
        guard validSource?()==true else{finish(accepted:false);return}
        let output=files;files.removeAll();phase = .delivering
        let accepted=publish?(output) ?? false
        // A publish notification may synchronously start another source.
        guard token==epoch,phase == .delivering else{return}
        finish(accepted:accepted)
    }
    private func finish(accepted:Bool) {
        tasks.removeAll();pending.removeAll();files.removeAll();publish=nil;validSource=nil
        if accepted{phase = .ready;failedAttempts=0;retryAfter = -.infinity}
        else {
            phase = .failed;failedAttempts=min(5,failedAttempts+1)
            let now=clock();retryAfter=now.isFinite ? now+min(30,2*pow(2,Double(failedAttempts-1))) : -.infinity
        }
    }
}
