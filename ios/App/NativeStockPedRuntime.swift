// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Main-thread publication and resident-resource ownership for verified stock
/// pedestrians. The caller supplies real GPU allocation and registration;
/// acquisition/decoding remain with the existing bounded CPU/file owners.
final class NativeStockPedRuntime<Resource:AnyObject> {
    struct Limits {
        var residentBytes=128*1024*1024,entries=16,pending=4,retrySeconds=5.0
    }
    struct Ready {
        let model:NativeSAMPStockModels.Model,sourceIdentity:String
        let resource:Resource,chargedBytes:Int
    }
    enum Failure:Error {case configuration,budget,invalidCharge}
    typealias Estimate=(NativeStockPedLoader.Prepared)throws->Int
    typealias Upload=(NativeStockPedLoader.Prepared,Int)throws->(resource:Resource,chargedBytes:Int)
    private struct Loading {let token:UUID;var request:UUID?}
    private let loader:NativeStockPedLoader,sourceIdentity:()->String,estimate:Estimate,upload:Upload,limits:Limits,now:()->Double
    private var source:String
    private var entries:[Int32:Ready]=[:],use:[Int32:Double]=[:],retry:[Int32:Double]=[:],pending:[Int32:Loading]=[:]
    private var demand=Set<Int32>()
    private(set) var residentBytes=0
    var onReady:((Ready)->Void)?,onRetired:((Ready)->Void)?,onUnavailable:((Int32,Error)->Void)?
    var count:Int{main();return entries.count}
    var pendingCount:Int{main();return pending.count}
    init(loader:NativeStockPedLoader,sourceIdentity:@escaping()->String,limits:Limits = .init(),now:@escaping()->Double={ProcessInfo.processInfo.systemUptime},
         estimate:@escaping Estimate,upload:@escaping Upload)throws {
        dispatchPrecondition(condition:.onQueue(.main))
        guard (1...256*1024*1024).contains(limits.residentBytes),(1...64).contains(limits.entries),
              (1...8).contains(limits.pending),limits.retrySeconds.isFinite,limits.retrySeconds>=0 else{throw Failure.configuration}
        self.loader=loader;self.sourceIdentity=sourceIdentity;self.limits=limits;self.estimate=estimate;self.upload=upload
        source=sourceIdentity();self.now=now
    }
    private func main(){dispatchPrecondition(condition:.onQueue(.main))}
    @discardableResult func synchronizeSource()->Bool {
        main();guard source != sourceIdentity()else{return false};reset();return true
    }
    func reset() {
        main();source=sourceIdentity();demand.removeAll();pending.removeAll();retry.removeAll();use.removeAll()
        let retired=entries.values.sorted{$0.model.id<$1.model.id};entries.removeAll();residentBytes=0
        _=loader.reset()
        for value in retired{onRetired?(value)}
    }
    func setDemand(_ ids:Set<Int32>) {
        main();_=synchronizeSource();demand=ids
        for id in pending.keys.filter({!ids.contains($0)}) {
            if let request=pending.removeValue(forKey:id)?.request{loader.cancel(request)}
        }
    }
    func ready(_ id:Int32,at timestamp:Double)->Ready? {
        main();_=synchronizeSource()
        guard timestamp.isFinite,let value=entries[id],value.sourceIdentity==source else{return nil}
        use[id]=timestamp;return value
    }
    /// Only visible/explicitly demanded original identities may start work.
    /// Existing converted resources can remain a same-model fallback until a
    /// complete original family has been admitted; no substitute ID is emitted.
    func ensure(_ resolution:NativeSAMPStockModels.Resolution,at timestamp:Double) {
        main();_=synchronizeSource();let id=resolution.model.id
        guard timestamp.isFinite,demand.contains(id),resolution.model.kind == .ped,
              entries[id]==nil,pending[id]==nil,pending.count<limits.pending,
              timestamp>=(retry[id] ?? -.infinity) else{return}
        let token=UUID(),expectedSource=source
        pending[id] = .init(token:token,request:nil)
        let request=loader.load(resolution){[weak self] result in
            guard let self,self.pending[id]?.token==token else{return}
            func current()->Bool {
                self.pending[id]?.token==token && self.source==expectedSource &&
                    self.sourceIdentity()==expectedSource && self.demand.contains(id)
            }
            guard current()else{self.pending.removeValue(forKey:id);return}
            do {
                let value=try result.get()
                guard self.loader.isCurrent(value),value.model.id==id,value.model.model==resolution.model.model else{throw Failure.configuration}
                let reserve=try self.estimate(value)
                guard current(),self.loader.isCurrent(value)else{return}
                try self.makeRoom(bytes:reserve,current:current)
                guard current(),self.loader.isCurrent(value)else{return}
                // This allowance bounds live resident charge after retirement.
                // The uploader must preflight actual GPU allocation against it.
                let allowance=self.limits.residentBytes-self.residentBytes
                let gpu=try self.upload(value,allowance)
                guard current(),self.loader.isCurrent(value)else{return}
                guard gpu.chargedBytes>0,gpu.chargedBytes<=reserve,gpu.chargedBytes<=allowance else{throw Failure.invalidCharge}
                let ready=Ready(model:value.model,sourceIdentity:expectedSource,resource:gpu.resource,chargedBytes:gpu.chargedBytes)
                self.entries[id]=ready;self.residentBytes+=ready.chargedBytes
                let completed=self.now()
                self.use[id]=completed.isFinite ? completed:timestamp;self.retry.removeValue(forKey:id);self.pending.removeValue(forKey:id)
                self.onReady?(ready)
            }catch {
                guard current()else{return}
                let completed=self.now()
                self.pending.removeValue(forKey:id);self.retry[id]=(completed.isFinite ? completed:timestamp)+self.limits.retrySeconds
                self.onUnavailable?(id,error)
            }
        }
        if pending[id]?.token==token{pending[id]?.request=request}else{loader.cancel(request)}
    }
    private func makeRoom(bytes:Int,current:()->Bool)throws {
        guard bytes>0,bytes<=limits.residentBytes else{throw Failure.budget}
        while entries.count>=limits.entries || residentBytes>limits.residentBytes-bytes {
            guard current()else{throw Failure.configuration}
            guard let id=entries.keys.filter({!demand.contains($0)}).min(by:{
                let a=use[$0] ?? -.infinity,b=use[$1] ?? -.infinity
                return a==b ? $0<$1:a<b
            }),let retired=entries.removeValue(forKey:id) else{throw Failure.budget}
            residentBytes-=retired.chargedBytes;use.removeValue(forKey:id)
            onRetired?(retired)
        }
    }
}
