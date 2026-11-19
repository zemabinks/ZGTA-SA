import Foundation
import CryptoKit

private var checks=0
private func check(_ condition:Bool,_ message:String){checks+=1;precondition(condition,message)}
private func wait(_ condition:()->Bool){let deadline=Date().addingTimeInterval(8);while !condition() && Date()<deadline{RunLoop.main.run(until:Date().addingTimeInterval(0.002))};check(condition(),"Asynchronous fixture timed out")}
private func makeSnapshot(_ installed:Bool=false,_ count:Int=0,_ mode:NativeResourceStore.Mode = .development)->NativeResourceStore.Snapshot{
    .init(mode:mode,installedContentID:installed ? String(repeating:"a",count:64):nil,installedFiles:installed ? 10:0,installedBytes:installed ? 100:0,cachedFiles:count,cachedBytes:Int64(count*10),hasPlayableInstallation:installed,developmentOrigin:nil,issues:[])
}
private enum FixtureFailure:LocalizedError {case rejected;var errorDescription:String?{"Synthetic operation refused"}}
private let syntheticGameFilesValidationIdentity="synthetic-game-files-coordinator-v1"
// Only the authored coordinator fixture is validated here, never game playability.
private func validateSyntheticGameFiles(_ manifest:NativeResourceManifest,_ resolve:@escaping(String)throws->URL)throws {
    for item in manifest.resources {
        let data=try Data(contentsOf:resolve(item.path))
        if item.path.hasSuffix(".json") {
            let object=try JSONSerialization.jsonObject(with:data) as? [String:Any]
            guard object?["fixture"] as? Bool == true else{throw FixtureFailure.rejected}
        }else{guard data==Data("synthetic-resource".utf8) else{throw FixtureFailure.rejected}}
    }
}
private final class FixtureService:NativeGameFilesService {
    struct Job {let progress:(NativeResourceStore.Progress)->Void;let completion:(Result<NativeResourceStore.Snapshot,Error>)->Void;var cancels=0}
    var snapshot=makeSnapshot(),jobs:[Job]=[],modeCalls=0,observers:[UUID:(NativeResourceStore.Snapshot)->Void]=[:]
    var synchronous=false
    func observe(_ update:@escaping(NativeResourceStore.Snapshot)->Void)->UUID{let id=UUID();observers[id]=update;update(snapshot);return id}
    func removeObserver(_ id:UUID){observers.removeValue(forKey:id)}
    func begin(_ progress:@escaping(NativeResourceStore.Progress)->Void,_ completion:@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->()->Void{
        let index=jobs.count;jobs.append(.init(progress:progress,completion:completion))
        if synchronous {completion(.success(snapshot))}
        return {[weak self] in self?.jobs[index].cancels+=1}
    }
    func importFolder(_ folder:URL,progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->()->Void{begin(progress,completion)}
    func verify(progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->()->Void{begin(progress,completion)}
    func cache(origin:URL,progress:@escaping(NativeResourceStore.Progress)->Void,completion:@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->()->Void{begin(progress,completion)}
    func setMode(_ mode:NativeResourceStore.Mode)throws{modeCalls+=1;if mode == .installed && !snapshot.hasPlayableInstallation{throw FixtureFailure.rejected}}
}
@main struct GameFilesSmoke {
    static func main()throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),service=FixtureService()
        var acquired=0,released=0
        let coordinator=NativeGameFilesCoordinator(service:service,scope:.init(begin:{_ in acquired+=1;return true},end:{_ in released+=1}))
        var notifications=0,allMain=true
        let observer=coordinator.observe{_ in notifications+=1;allMain = allMain && Thread.isMainThread}
        check(coordinator.importPreparedFolder(root),"Initial import rejected")
        check(acquired==1 && released==0 && coordinator.state.busy,"Picker scope not retained through work")
        check(!coordinator.verifyInstalled() && service.jobs.count==1,"Concurrent operation started")
        coordinator.setMode(.installed);check(service.modeCalls==0,"Busy source switch escaped coordinator")
        let first=service.jobs[0]
        let progress=NativeResourceStore.Progress(phase:"Fixture read",completedFiles:1,totalFiles:2,completedBytes:4,totalBytes:8,currentPath:"game/test")
        first.progress(progress);check(coordinator.state.activity?.progress?.completedFiles==1,"Progress not delivered")
        coordinator.cancel();coordinator.cancel()
        check(service.jobs[0].cancels==1 && coordinator.state.activity?.cancelling==true,"Cancel not idempotent")
        check(released==0,"Cancel request prematurely released provider access")
        first.progress(.init(phase:"Late",completedFiles:2,totalFiles:2,completedBytes:8,totalBytes:8,currentPath:nil))
        check(coordinator.state.activity?.progress?.completedFiles==1,"Progress after cancellation overwrote cancelling state")
        first.completion(.failure(FixtureFailure.rejected))
        check(!coordinator.state.busy && released==1 && !coordinator.state.failed,"Cancellation did not finish/release safely")
        check(coordinator.state.message?.hasPrefix("Cancelled.")==true,"Cancellation presented as install failure")
        for address in ["http://a.example/path","http://user:secret@a.example","https://a.example/?token=x","https://a.example/#part","file:///tmp/root","server"] {
            check(!coordinator.cacheDevelopment(address),"Invalid origin was accepted: \(address)")
        }
        check(service.jobs.count==1,"Rejected origin dispatched work")
        check(coordinator.cacheDevelopment("http://127.0.0.1:8766"),"Valid Mac origin rejected")
        let currentID=coordinator.state.activity?.id
        first.completion(.success(makeSnapshot(true,999)));first.progress(progress)
        check(coordinator.state.activity?.id==currentID && coordinator.state.resources.cachedFiles==0,"Old completion/progress crossed generation")
        service.snapshot=makeSnapshot(false,2);service.jobs[1].completion(.success(service.snapshot))
        check(!coordinator.state.busy && coordinator.state.resources.cachedFiles==2,"Current completion lost")
        let after=notifications;service.jobs[1].completion(.failure(FixtureFailure.rejected))
        check(notifications==after && !coordinator.state.failed,"Duplicate completion changed presentation")
        coordinator.setMode(.installed);check(coordinator.state.failed && coordinator.state.message=="Synthetic operation refused","Mode failure lost actionable message")
        coordinator.removeObserver(observer);let removed=notifications
        check(coordinator.verifyInstalled(),"Verify did not start")
        DispatchQueue.global().async{service.jobs[2].progress(progress);service.jobs[2].completion(.failure(FixtureFailure.rejected))}
        wait{!coordinator.state.busy};check(notifications==removed && allMain,"Observer removal or main callback contract failed")

        // Cancellation can be requested reentrantly from initial activity
        // publication, before the service returns its cancellation handle.
        let reentrant=FixtureService();var starts=0,ends=0
        let duringStart=NativeGameFilesCoordinator(service:reentrant,scope:.init(begin:{_ in starts+=1;return true},end:{_ in ends+=1}))
        let reentrantObserver=duringStart.observe{state in if state.busy && state.activity?.cancelling==false {duringStart.cancel()}}
        check(duringStart.importPreparedFolder(root),"Reentrant import failed")
        check(reentrant.jobs[0].cancels==1 && ends==0,"Cancel before handle attachment was lost or scope ended early")
        reentrant.jobs[0].completion(.failure(FixtureFailure.rejected));check(starts==1 && ends==1,"Reentrant scope imbalance")
        duringStart.removeObserver(reentrantObserver)
        reentrant.synchronous=true
        check(duringStart.verifyInstalled() && !duringStart.state.busy,"Synchronous completion left a phantom activity")

        // Whichever observer runs first starts a new operation from completion.
        // Remaining observers must not subsequently receive the older idle state.
        let chainService=FixtureService(),chain=NativeGameFilesCoordinator(service:chainService)
        var armed=false,restarted=false,stale=0
        let receive:(NativeGameFilesCoordinator.State)->Void={state in
            if armed && !state.busy && state.message=="Resource verification completed." {
                if !restarted {restarted=true;_ = chain.verifyInstalled()}else{stale+=1}
            }
        }
        let a=chain.observe(receive),b=chain.observe(receive)
        _ = chain.verifyInstalled();armed=true;chainService.jobs[0].completion(.success(makeSnapshot()))
        check(restarted && chain.state.busy && stale==0,"Reentrant publication delivered stale idle state after newer activity")
        chain.removeObserver(a);chain.removeObserver(b);chainService.jobs[1].completion(.success(makeSnapshot()))

        // Dismissing the last injected screen must not end provider access or
        // abandon its app-owned job before the worker reports completion.
        let lifetimeService=FixtureService();var lifetimeEnds=0
        var temporary:NativeGameFilesCoordinator?=NativeGameFilesCoordinator(service:lifetimeService,scope:.init(begin:{_ in true},end:{_ in lifetimeEnds+=1}))
        weak var retained=temporary
        _ = temporary!.importPreparedFolder(root);temporary=nil
        check(retained != nil && lifetimeEnds==0,"Screen release abandoned job/provider scope")
        lifetimeService.jobs[0].completion(.failure(FixtureFailure.rejected))
        check(retained==nil && lifetimeEnds==1,"Completed injected coordinator leaked or did not release scope")

        let cancelService=FixtureService(),cancelHandoff=NativeGameFilesCoordinator(service:cancelService)
        var didHandoff=false
        let cancelObserver=cancelHandoff.observe{state in
            if state.activity?.cancelling==true && !didHandoff {
                didHandoff=true;cancelService.jobs[0].completion(.failure(FixtureFailure.rejected));_ = cancelHandoff.verifyInstalled()
            }
        }
        _ = cancelHandoff.verifyInstalled();cancelHandoff.cancel()
        check(didHandoff && cancelHandoff.state.busy && cancelService.jobs.count==2,"Cancellation completion did not hand off to next operation")
        check(cancelService.jobs[1].cancels==0,"Old cancellation cancelled reentrantly started replacement")
        cancelHandoff.removeObserver(cancelObserver);cancelService.jobs[1].completion(.success(makeSnapshot()))

        // A requested address is a UI draft, not the installed catalogue's
        // trusted resource origin. It must survive BACK/reopen, cancellation
        // and an App-style coordinator recreation before the first commit.
        var savedOrigin:String?,preferenceWrites=0
        let preference=NativeGameFilesCoordinator.OriginPreference(read:{savedOrigin},write:{savedOrigin=$0;preferenceWrites+=1})
        let originService=FixtureService()
        let originCoordinator=NativeGameFilesCoordinator(service:originService,originPreference:preference)
        check(originCoordinator.cacheDevelopment("  HTTP://Assets-B.invalid:8807/  "),"Normalized origin request was rejected")
        check(originCoordinator.state.suggestedOrigin=="http://assets-b.invalid:8807" && savedOrigin=="http://assets-b.invalid:8807","Requested origin was not normalized/persisted as a separate UI draft")
        check(originCoordinator.state.resources.developmentOrigin==nil,"Requested origin impersonated an uncommitted native resource source")
        var reopenedField:String?
        let fieldObserver=originCoordinator.observe{reopenedField=$0.suggestedOrigin}
        check(reopenedField==savedOrigin,"A newly opened screen lost the active request address")
        originCoordinator.removeObserver(fieldObserver)
        check(!originCoordinator.cacheDevelopment("http://other.invalid") && preferenceWrites==1,"Busy request overwrote the active address draft")
        originCoordinator.cancel();originService.jobs[0].completion(.failure(FixtureFailure.rejected))
        check(originCoordinator.state.suggestedOrigin==savedOrigin && originCoordinator.state.resources.developmentOrigin==nil,"Cancellation lost the draft or committed its origin")
        let recreated=NativeGameFilesCoordinator(service:FixtureService(),originPreference:preference)
        check(recreated.state.suggestedOrigin=="http://assets-b.invalid:8807","App-style recreation lost the valid requested origin")
        let writes=preferenceWrites
        for address in ["https://user:secret@invalid.example","http://invalid.example/path","http://invalid.example?token=x","http://invalid.example:0"]{
            check(!recreated.cacheDevelopment(address),"An invalid origin draft was accepted")
        }
        check(preferenceWrites==writes && recreated.state.suggestedOrigin==savedOrigin,"Rejected address overwrote the saved origin draft")
        let rejectedSaved=NativeGameFilesCoordinator(service:FixtureService(),originPreference:.init(read:{"http://user:password@invalid.example"},write:{_ in preconditionFailure("Initializer must not publish invalid saved preferences")}))
        check(rejectedSaved.state.suggestedOrigin.isEmpty,"A credential-bearing saved preference was exposed as an origin")
        let committed=FixtureService()
        committed.snapshot = .init(mode:.installed,installedContentID:String(repeating:"a",count:64),installedFiles:10,installedBytes:100,cachedFiles:10,cachedBytes:100,hasPlayableInstallation:true,developmentOrigin:"http://committed-a.invalid",issues:[])
        let replacementDraft=NativeGameFilesCoordinator(service:committed,originPreference:preference)
        check(replacementDraft.state.suggestedOrigin==savedOrigin && replacementDraft.state.resources.developmentOrigin=="http://committed-a.invalid","Requested UI address replaced the committed server binding")
        check(replacementDraft.cacheDevelopment("http://requested-c.invalid"),"Replacement address did not start")
        replacementDraft.cancel();committed.jobs[0].completion(.failure(FixtureFailure.rejected))
        check(replacementDraft.state.suggestedOrigin=="http://requested-c.invalid" && replacementDraft.state.resources.mode == .installed && replacementDraft.state.resources.developmentOrigin=="http://committed-a.invalid","Cancelled replacement rewrote installed mode/catalogue origin")

        // Real production store and adapter, with invented resource bytes and a
        // disposable directory. This proves installation plumbing, not game assets.
        let prepared=root.appendingPathComponent("prepared"),blobs=prepared.appendingPathComponent("blobs")
        try FileManager.default.createDirectory(at:blobs,withIntermediateDirectories:true)
        var resources:[NativeResourceManifest.Resource]=[]
        let paths=NativeResourceManifest.requiredPaths.union(["game/world/fixture.bin","game/world/fixture.png"])
        for path in paths.sorted(){
            let bytes=Data((path.hasSuffix(".json") ? "{\"fixture\":true}":"synthetic-resource").utf8)
            let hash=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
            try bytes.write(to:blobs.appendingPathComponent(hash))
            resources.append(.init(path:path,bytes:Int64(bytes.count),sha256:hash,required:true))
        }
        let draft=NativeResourceManifest(schema:1,profile:NativeResourceManifest.profileName,contentID:String(repeating:"0",count:64),resources:resources)
        let manifest=NativeResourceManifest(schema:1,profile:NativeResourceManifest.profileName,contentID:draft.identity,resources:resources)
        try JSONEncoder().encode(manifest).write(to:prepared.appendingPathComponent(NativeResourceManifest.filename))
        var deniedWithoutValidator=false,deniedFinished=false
        let unconfigured=NativeResourceStore(root:root.appendingPathComponent("unconfigured-resources"))
        _ = unconfigured.importPreparedFolder(prepared,progress:{_ in}){result in if case .failure=result{deniedWithoutValidator=true};deniedFinished=true}
        wait{deniedFinished};check(deniedWithoutValidator && !unconfigured.snapshot.hasPlayableInstallation,"Integrity-only setup became playable without native runtime validation")
        let storeRoot=root.appendingPathComponent("resources"),store=NativeResourceStore(root:storeRoot,validationIdentity:syntheticGameFilesValidationIdentity,runtimeValidator:validateSyntheticGameFiles)
        var realBegin=0,realEnd=0
        let real=NativeGameFilesCoordinator(store:store,scope:.init(begin:{_ in realBegin+=1;return true},end:{_ in realEnd+=1}))
        check(real.importPreparedFolder(prepared),"Production store import did not start")
        wait{!real.state.busy}
        check(!real.state.failed && real.state.resources.installedContentID==manifest.contentID,"Real store adapter failed prepared import")
        check(realBegin==1 && realEnd==1,"Real asynchronous import scope imbalance")
        real.setMode(.installed);check(real.state.resources.mode == .installed,"Real verified mode switch failed")
        let reopened=NativeResourceStore(root:storeRoot,validationIdentity:syntheticGameFilesValidationIdentity,runtimeValidator:validateSyntheticGameFiles)
        check(reopened.snapshot.installedContentID==manifest.contentID && reopened.snapshot.mode == .installed,"Update/restart-style reopen lost installation/mode")
        check(real.verifyInstalled(),"Real verification not started");wait{!real.state.busy};check(!real.state.failed,"Real verification failed")
        let original=resources.first!;try Data("corrupt".utf8).write(to:storeRoot.appendingPathComponent("blobs/"+original.sha256))
        _ = real.verifyInstalled();wait{!real.state.busy}
        check(real.state.failed,"Corrupt installed bytes reported verified")
        check(real.importPreparedFolder(prepared),"Repair reimport not started");wait{!real.state.busy}
        check(!real.state.failed && real.state.resources.hasPlayableInstallation,"Prepared repair did not restore verified store state")
        check(FileManager.default.fileExists(atPath:prepared.appendingPathComponent(NativeResourceManifest.filename).path),"Import deleted original source")
        print("PASS game-files coordinator/store: \(checks) checks; cancellation scopes, stale/reentrant callbacks, real synthetic prepared import/reopen/corruption/repair")
    }
}
