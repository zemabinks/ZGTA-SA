// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Atomic optional model registration boundary, independently testable with
/// the actual Metal upload factory. It owns no ordinary/DL model catalogue.
final class NativeCJRuntimeModel {
    struct GPU {
        let uploaded: NativeRenderWarePedModel.Uploaded
        let pipelines: NativeRenderWarePedModel.Pipelines
    }
    struct Ready {
        let gpu: GPU
        let profile: NativeCJProfile
        let sourceIdentity: String
        let generation: UInt64
    }
    typealias Upload = (NativeRenderWarePedModel.Plan) throws -> GPU
    private let loader: NativeCJRuntimeLoader, sourceIdentity: () -> String, upload: Upload
    private(set) var ready: Ready?
    private var prepared: NativeCJRuntimeLoader.Prepared?
    private var loading = false, observedSource: String, retryAfter = -Double.infinity
    private var requestSerial: UInt64 = 0
    var onReady: ((Ready) -> Void)?
    var onInvalidated: (() -> Void)?
    var onUnavailable: ((Error) -> Void)?
    init(assetBaseURL: URL, sourceIdentity: @escaping () -> String,
         accessProvider: (() -> NativeStockAssetAccess?)? = nil, upload: @escaping Upload) throws {
        dispatchPrecondition(condition:.onQueue(.main))
        self.sourceIdentity=sourceIdentity;self.upload=upload;observedSource=sourceIdentity()
        loader=try .init(assetBaseURL:assetBaseURL,sourceIdentity:sourceIdentity,accessProvider:accessProvider)
    }
    var isReady: Bool {
        main();guard let ready,let prepared else{return false}
        return ready.sourceIdentity==sourceIdentity() && loader.isCurrent(prepared)
    }
    private func main(){dispatchPrecondition(condition:.onQueue(.main))}
    func reset() {
        main();requestSerial &+= 1;_=loader.reset();loading=false;ready=nil;prepared=nil;retryAfter = -Double.infinity
        observedSource=sourceIdentity();onInvalidated?()
    }
    /// A same-content repair is a new admission, even if all hashes match.
    @discardableResult func invalidateIfSourceChanged() -> Bool {
        main();guard observedSource != sourceIdentity() else{return false};reset();return true
    }
    @discardableResult func ensure(force: Bool = false) -> Bool {
        main();_=invalidateIfSourceChanged()
        if isReady{return true}
        guard !loading,force || ProcessInfo.processInfo.systemUptime>=retryAfter else{return false}
        loading=true;requestSerial &+= 1;let serial=requestSerial
        loader.load {[weak self] result in
            guard let self,self.requestSerial==serial else{return}
            // Reset cancelled an old request; it cannot clear a newer load.
            if case .success(let value)=result,value.generation != self.loader.generation{return}
            do {
                let value=try result.get()
                guard self.requestSerial==serial,self.loader.isCurrent(value),value.sourceIdentity==self.sourceIdentity() else{throw NativeCJRuntimeLoader.Failure.stale}
                guard value.plan.model.meshByteCount+value.plan.model.textureByteCount+value.plan.skeleton.encodedSKN1().count<=64*1024*1024 else{
                    throw NativeCJRuntimeLoader.Failure.limit
                }
                let gpu=try self.upload(value.plan)
                // GPU upload can overlap a repair/reconnect or reentrant caller.
                // The final fence precedes every visible catalogue publication.
                guard self.requestSerial==serial,self.loader.isCurrent(value),value.sourceIdentity==self.sourceIdentity() else{throw NativeCJRuntimeLoader.Failure.stale}
                let ready=Ready(gpu:gpu,profile:value.profile,sourceIdentity:value.sourceIdentity,generation:value.generation)
                self.prepared=value;self.ready=ready;self.loading=false;self.retryAfter = -Double.infinity
                self.onReady?(ready)
            }catch{
                // A stale completion never revokes a newer ready generation.
                guard self.requestSerial==serial,self.observedSource==self.sourceIdentity() else{return}
                self.loading=false;self.retryAfter=ProcessInfo.processInfo.systemUptime+30
                self.onUnavailable?(error)
            }
        }
        return false
    }
}
