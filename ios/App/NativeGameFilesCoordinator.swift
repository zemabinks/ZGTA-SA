import Foundation

/// Narrow dependency boundary also used by deterministic coordinator tests.
/// The resource store owns files, verification, atomic activation and persistence.
protocol NativeGameFilesService:AnyObject {
    var snapshot:NativeResourceStore.Snapshot {get}
    func observe(_ update:@escaping(NativeResourceStore.Snapshot)->Void)->UUID
    func removeObserver(_ id:UUID)
    func importFolder(_ folder:URL,progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->()->Void
    func verify(progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->()->Void
    func cache(origin:URL,progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->()->Void
    func setMode(_ mode:NativeResourceStore.Mode)throws
}
private final class NativeGameFilesStoreService:NativeGameFilesService {
    let store:NativeResourceStore
    init(_ store:NativeResourceStore){self.store=store}
    var snapshot:NativeResourceStore.Snapshot {store.snapshot}
    func observe(_ update:@escaping(NativeResourceStore.Snapshot)->Void)->UUID{store.observe(update)}
    func removeObserver(_ id:UUID){store.removeObserver(id)}
    func importFolder(_ folder:URL,progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->()->Void{
        let operation=store.importPreparedFolder(folder,progress:progress,completion:completion);return {operation.cancel()}
    }
    func verify(progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->()->Void{
        let operation=store.verifyInstalled(progress:progress,completion:completion);return {operation.cancel()}
    }
    func cache(origin:URL,progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->()->Void{
        let operation=store.cacheDevelopment(origin:origin,progress:progress,completion:completion);return {operation.cancel()}
    }
    func setMode(_ mode:NativeResourceStore.Mode)throws{try store.setMode(mode)}
}

protocol NativeGameFilesRawService:AnyObject {
    var snapshot:NativeRawResourceStore.Snapshot {get}
    func extractISO(_ source:URL,progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeRawResourceStore.Snapshot,Error>)->Void)->()->Void
    func verifyRaw(progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeRawResourceStore.Snapshot,Error>)->Void)->()->Void
}
private final class NativeGameFilesRawStoreService:NativeGameFilesRawService {
    let store:NativeRawResourceStore
    init(_ store:NativeRawResourceStore){self.store=store}
    var snapshot:NativeRawResourceStore.Snapshot{store.snapshot}
    func extractISO(_ source:URL,progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeRawResourceStore.Snapshot,Error>)->Void)->()->Void{
        let operation=store.extractISO(source,progress:progress,completion:completion);return{operation.cancel()}
    }
    func verifyRaw(progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeRawResourceStore.Snapshot,Error>)->Void)->()->Void{
        let operation=store.verifyRaw(progress:progress,completion:completion);return{operation.cancel()}
    }
}

/// App-owned presentation state survives navigation away from Game Files.
/// All public calls and callbacks use the main thread; installation work does not.
final class NativeGameFilesCoordinator {
    static let shared=NativeGameFilesCoordinator(service:NativeGameFilesStoreService(.shared),rawService:NativeGameFilesRawStoreService(.shared),originPreference:.userDefaults)
    enum Kind:String {case importing="Importing prepared resources",verifying="Verifying installed resources",caching="Caching development resources",inspecting="Inspecting ISO source",extracting="Extracting original raw resources",verifyingRaw="Verifying saved raw resources"}
    struct Activity {let id:UUID;let kind:Kind;var progress:NativeResourceStore.Progress?;var cancelling=false}
    struct State {
        var resources:NativeResourceStore.Snapshot
        var raw=NativeRawResourceStore.Snapshot.empty
        // UI draft only: never substitutes for the store's committed origin.
        var requestedOrigin:String?
        var suggestedOrigin:String{requestedOrigin ?? resources.developmentOrigin ?? ""}
        var activity:Activity?
        var message:String?
        var failed=false
        var inspection:NativeGameSourceInspector.Report?
        var busy:Bool {activity != nil}
    }
    struct SecurityScope {
        var begin:(URL)->Bool={$0.startAccessingSecurityScopedResource()}
        var end:(URL)->Void={$0.stopAccessingSecurityScopedResource()}
    }
    struct OriginPreference {
        var read:()->String?
        var write:(String)->Void
        static var userDefaults:OriginPreference{
            let key="gameFiles.lastRequestedOrigin.v1"
            return .init(read:{UserDefaults.standard.string(forKey:key)},write:{UserDefaults.standard.set($0,forKey:key)})
        }
    }
    private let service:NativeGameFilesService,scope:SecurityScope,rawService:NativeGameFilesRawService?,originPreference:OriginPreference?
    private var serviceObserver:UUID?
    private var observers:[UUID:(State)->Void]=[:]
    // An injected coordinator also keeps its asynchronous job and provider
    // grant alive until completion, even if its last screen is dismissed.
    private var activeLifetime:NativeGameFilesCoordinator?
    private var publication:UInt64=0
    private var cancellation:(()->Void)?
    private var releaseSource:(()->Void)?
    private let inspectionQueue=DispatchQueue(label:"org.zgtasa.source-inspection",qos:.userInitiated)
    private(set) var state:State

    convenience init(store:NativeResourceStore,scope:SecurityScope=SecurityScope()){self.init(service:NativeGameFilesStoreService(store),scope:scope)}
    init(service:NativeGameFilesService,scope:SecurityScope=SecurityScope(),rawService:NativeGameFilesRawService?=nil,originPreference:OriginPreference?=nil){
        self.service=service;self.scope=scope;self.rawService=rawService;self.originPreference=originPreference;state=State(resources:service.snapshot)
        state.raw=rawService?.snapshot ?? .empty
        state.requestedOrigin=originPreference?.read().flatMap(Self.normalizedOrigin)?.absoluteString
        serviceObserver=service.observe{[weak self] snapshot in
            guard let self else{return};self.onMain{self.state.resources=snapshot;self.publish()}
        }
    }
    deinit {if let serviceObserver{service.removeObserver(serviceObserver)}}
    @discardableResult func observe(_ update:@escaping(State)->Void)->UUID {
        precondition(Thread.isMainThread);let id=UUID();observers[id]=update;update(state);return id
    }
    func removeObserver(_ id:UUID){precondition(Thread.isMainThread);observers.removeValue(forKey:id)}
    private func onMain(_ action:@escaping()->Void){if Thread.isMainThread{action()}else{DispatchQueue.main.async(execute:action)}}
    private func publish(){precondition(Thread.isMainThread);publication &+= 1;let generation=publication,snapshot=state;for update in Array(observers.values){guard generation==publication else{return};update(snapshot)}}
    private func start(_ kind:Kind,source:URL?=nil)->UUID?{
        precondition(Thread.isMainThread);guard !state.busy else{return nil}
        let id=UUID();activeLifetime=self;state.activity=Activity(id:id,kind:kind);state.message=nil;state.failed=false;state.inspection=nil
        if let source,scope.begin(source){releaseSource={ [scope] in scope.end(source)}}
        publish();return id
    }
    private func attach(_ cancel:@escaping()->Void,to id:UUID){
        // Service implementations may synchronously complete or observers may
        // reentrantly request cancellation before the operation is returned.
        guard state.activity?.id==id else{return};cancellation=cancel
        if state.activity?.cancelling==true {cancel()}
    }
    private func progress(_ value:NativeResourceStore.Progress,id:UUID){onMain{[weak self] in
        guard let self,self.state.activity?.id==id,self.state.activity?.cancelling==false else{return}
        self.state.activity?.progress=value;self.publish()
    }}
    private func finish(_ result:Result<NativeResourceStore.Snapshot,Error>,id:UUID){onMain{[weak self] in
        guard let self,self.state.activity?.id==id else{return}
        let cancelling=self.state.activity?.cancelling==true
        self.cancellation=nil;self.releaseSource?();self.releaseSource=nil;self.state.activity=nil;self.activeLifetime=nil
        switch result {
        case .success(let snapshot):
            self.state.resources=snapshot
            self.state.message=cancelling ? "The operation finished before cancellation took effect. Resources were verified by the store." : "Resource verification completed."
            self.state.failed=false
        case .failure(let error):
            self.state.resources=self.service.snapshot
            self.state.message=cancelling ? "Cancelled. Previously active resources are preserved; retry to reuse verified files." : error.localizedDescription
            self.state.failed = !cancelling
        }
        self.publish()
    }}
    @discardableResult func importPreparedFolder(_ folder:URL)->Bool{
        guard let id=start(.importing,source:folder)else{return false}
        let cancel=service.importFolder(folder,progress:{[weak self] in self?.progress($0,id:id)},completion:{[weak self] in self?.finish($0,id:id)})
        attach(cancel,to:id);return true
    }
    @discardableResult func verifyInstalled()->Bool{
        guard let id=start(.verifying)else{return false}
        let cancel=service.verify(progress:{[weak self] in self?.progress($0,id:id)},completion:{[weak self] in self?.finish($0,id:id)})
        attach(cancel,to:id);return true
    }
    @discardableResult func extractRawISO(_ source:URL)->Bool{
        precondition(Thread.isMainThread)
        guard let rawService else{return rawUnavailable()}
        guard let id=start(.extracting,source:source)else{return false}
        let cancel=rawService.extractISO(source,progress:{[weak self] in self?.progress($0,id:id)},completion:{[weak self] in self?.finishRaw($0,id:id)})
        attach(cancel,to:id);return true
    }
    @discardableResult func verifyRawResources()->Bool{
        precondition(Thread.isMainThread)
        guard let rawService else{return rawUnavailable()}
        guard let id=start(.verifyingRaw)else{return false}
        let cancel=rawService.verifyRaw(progress:{[weak self] in self?.progress($0,id:id)},completion:{[weak self] in self?.finishRaw($0,id:id)})
        attach(cancel,to:id);return true
    }
    private func rawUnavailable()->Bool{
        guard !state.busy else{return false}
        state.message="Raw ISO extraction is unavailable in this configuration.";state.failed=true;publish();return false
    }
    private func finishRaw(_ result:Result<NativeRawResourceStore.Snapshot,Error>,id:UUID){onMain{[weak self] in
        guard let self,self.state.activity?.id==id else{return}
        let cancelling=self.state.activity?.cancelling==true
        self.cancellation=nil;self.releaseSource?();self.releaseSource=nil;self.state.activity=nil;self.activeLifetime=nil
        switch result {
        case .success(let snapshot):
            self.state.raw=snapshot;self.state.failed=false
            self.state.message=(cancelling ? "The raw operation completed before cancellation took effect. ":"")+"Raw resources prepared and checked. Supported original radio can be used with prepared native resources. Native conversion is still required for the remaining raw resources; no playable installation was activated."
        case .failure(let error):
            self.state.raw=self.rawService?.snapshot ?? .empty;self.state.failed = !cancelling
            self.state.message=cancelling ? "Raw operation cancelled. Previously saved raw and installed resources are preserved.":error.localizedDescription
        }
        self.publish()
    }}
    @discardableResult func cacheDevelopment(_ text:String)->Bool{
        precondition(Thread.isMainThread);guard !state.busy else{return false}
        guard let origin=Self.normalizedOrigin(text) else{
            state.message="Enter the Mac resource server origin, such as http://192.168.1.10:8766. Keep account credentials and join codes out of this address.";state.failed=true;publish();return false
        }
        state.requestedOrigin=origin.absoluteString
        guard let id=start(.caching)else{return false}
        originPreference?.write(origin.absoluteString)
        let cancel=service.cache(origin:origin,progress:{[weak self] in self?.progress($0,id:id)},completion:{[weak self] in self?.finish($0,id:id)})
        attach(cancel,to:id);return true
    }
    private static func normalizedOrigin(_ text:String)->URL?{
        guard var parts=URLComponents(string:text.trimmingCharacters(in:.whitespacesAndNewlines)),
              let scheme=parts.scheme?.lowercased(),["http","https"].contains(scheme),
              let host=parts.host,!host.isEmpty,parts.user==nil,parts.password==nil,parts.query==nil,parts.fragment==nil,
              parts.path.isEmpty || parts.path=="/",parts.port.map({(1...65535).contains($0)}) ?? true else{return nil}
        parts.scheme=scheme;parts.host=host.lowercased();parts.path=""
        return parts.url
    }
    func setMode(_ mode:NativeResourceStore.Mode){
        precondition(Thread.isMainThread);guard !state.busy else{return}
        do {try service.setMode(mode);state.resources=service.snapshot;state.message=nil;state.failed=false}
        catch {state.message=error.localizedDescription;state.failed=true}
        publish()
    }
    func cancel(){
        precondition(Thread.isMainThread);guard let activity=state.activity,!activity.cancelling else{return}
        let cancel=cancellation
        state.activity?.cancelling=true;publish()
        // An observer may finish this job and start another during publication.
        // A cancellation request belongs only to the captured activity.
        guard state.activity?.id==activity.id else{return}
        cancel?()
        // Retain security scope until the worker's completion, never merely
        // until its cancel request. It may still be closing/reading a file.
    }
    @discardableResult func inspectISO(_ url:URL)->Bool{
        guard let id=start(.inspecting,source:url)else{return false}
        let token=InspectionCancellation();attach({token.cancel()},to:id)
        inspectionQueue.async{[weak self] in
            let result=Result{try NativeGameSourceInspector.inspectISO(url,cancelled:{token.isCancelled})}
            DispatchQueue.main.async{[weak self] in
                guard let self,self.state.activity?.id==id else{return}
                self.cancellation=nil;self.releaseSource?();self.releaseSource=nil
                let cancelling=self.state.activity?.cancelling==true;self.state.activity=nil;self.activeLifetime=nil
                switch result {
                case .success(let report) where !cancelling:
                    self.state.inspection=report;self.state.message="\(report.summary). Preparation is still required.";self.state.failed=false
                case .success: self.state.message="Source inspection cancelled.";self.state.failed=false
                case .failure(let error):self.state.message=cancelling ? "Source inspection cancelled.":error.localizedDescription;self.state.failed = !cancelling
                }
                self.publish()
            }
        };return true
    }
    private final class InspectionCancellation {
        private let lock=NSLock();private var cancelled=false
        var isCancelled:Bool {lock.lock();defer{lock.unlock()};return cancelled}
        func cancel(){lock.lock();cancelled=true;lock.unlock()}
    }
}
