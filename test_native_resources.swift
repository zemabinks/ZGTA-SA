// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit

private struct ResourceTestFailure: Error, CustomStringConvertible { let description:String }
private struct ResourceTestResponse { let data:Data?;let response:HTTPURLResponse?;let error:Error? }
// Operation.cancel is lock-protected; publish only this immutable handle.
private final class ResourceCancelHandle:@unchecked Sendable {let operation:NativeResourceStore.Operation;init(_ value:NativeResourceStore.Operation){operation=value}}
private final class ResourceIOGate:@unchecked Sendable {
    let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
    private let lock=NSLock();private var armed=false
    func arm(){lock.lock();armed=true;lock.unlock()}
    func pauseIfArmed()throws->Bool {
        lock.lock();let pause=armed;armed=false;lock.unlock()
        guard pause else{return false};entered.signal()
        guard release.wait(timeout:.now()+15) == .success else{throw ResourceTestFailure(description:"Controlled resource I/O gate timed out")}
        return true
    }
}
private final class ResourceReadHandle:@unchecked Sendable {
    let store:NativeResourceStore,url:URL
    init(_ store:NativeResourceStore,_ url:URL){self.store=store;self.url=url}
}
private final class ResourceChecks {
    var count=0,failures:[String]=[],notes:[String]=[]
    func check(_ value:Bool,_ label:String){count+=1;if !value{failures.append(label);print("RESOURCE_CHECK_FAILED \(label)")}}
    func rejects(_ label:String,_ body:()throws->Void){do{try body();check(false,label)}catch{check(true,label)}}
    func success(_ result:Result<NativeResourceStore.Snapshot,Error>,_ label:String)throws {
        switch result{case .success:check(true,label);case .failure(let error):throw ResourceTestFailure(description:"\(label): \(error)")}
    }
}

// Only this production activation dependency is absent from this transaction
// target. It deliberately fails closed; it never substitutes for Store/Session
// behavior or claims to be the App's actual format/Metal runtime verifier.
enum NativePreparedRuntimeVerifier {
    static let identity="unavailable-production-engine-verifier-in-transaction-target"
    static func validate(_ manifest:NativeResourceManifest,_ resolve:@escaping(String)throws->URL)throws {
        throw ResourceTestFailure(description:"Production engine verifier intentionally unavailable in synthetic transaction target")
    }
}

@main private struct NativeResourceRegression {
    static let syntheticIdentity="synthetic-resource-transactions-v1"
    // This validates only our authored fixture schema. It is deliberately a
    // different receipt identity from the App's actual native-engine verifier.
    static func validateSynthetic(_ manifest:NativeResourceManifest,_ resolve:@escaping(String)throws->URL)throws {
        for path in NativeResourceManifest.requiredPaths where path.hasSuffix(".json") {
            let object=try JSONSerialization.jsonObject(with:Data(contentsOf:resolve(path))) as? [String:Any]
            guard object?["syntheticFixture"] as? String == path else{throw ResourceTestFailure(description:"Malformed synthetic runtime metadata: \(path)")}
        }
        guard try Data(contentsOf:resolve("game/native/models/animations.clips.bin")).prefix(4)==Data("CLP1".utf8),
              try Data(contentsOf:resolve("game/world/synthetic.bin")).prefix(4)==Data("WRL2".utf8),
              try Data(contentsOf:resolve("game/world/synthetic.png")).prefix(8)==Data([137,80,78,71,13,10,26,10]) else {
            throw ResourceTestFailure(description:"Malformed synthetic runtime carrier")
        }
    }
    static func operation(cancelAfter:Double?=nil,_ begin:(@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->NativeResourceStore.Operation) async ->Result<NativeResourceStore.Snapshot,Error>{
        await withCheckedContinuation{continuation in
            let op=begin{continuation.resume(returning:$0)}
            if let delay=cancelAfter{let handle=ResourceCancelHandle(op);DispatchQueue.global().asyncAfter(deadline:.now()+delay){handle.operation.cancel()}}
        }
    }
    /// Cancel only after the real fixture observes the intended inflight blob.
    /// A fixed wall delay can fire while Store is still checking cached files.
    static func operation(cancelWhen observed:@escaping()async throws->Bool,
                          _ begin:(@escaping(Result<NativeResourceStore.Snapshot,Error>)->Void)->NativeResourceStore.Operation)async->Result<NativeResourceStore.Snapshot,Error>{
        await withCheckedContinuation{continuation in
            let handle=ResourceCancelHandle(begin{continuation.resume(returning:$0)})
            Task {
                let deadline=ProcessInfo.processInfo.systemUptime+5
                do {
                    while ProcessInfo.processInfo.systemUptime<deadline {
                        if try await observed(){handle.operation.cancel();return}
                        try await Task.sleep(nanoseconds:25_000_000)
                    }
                }catch{}
                handle.operation.cancel() // bounded failure path, never a pass.
            }
        }
    }
    static func response(_ session:NativeResourceSession,_ url:URL,_ method:String="GET")async->ResourceTestResponse {
        await withCheckedContinuation{continuation in
            var request=URLRequest(url:url);request.httpMethod=method
            session.dataTask(with:request){continuation.resume(returning:ResourceTestResponse(data:$0,response:$1 as? HTTPURLResponse,error:$2))}.resume()
        }
    }
    static func cancelledRequest(_ session:NativeResourceSession,_ url:URL)async->ResourceTestResponse {
        await withCheckedContinuation{continuation in
            let task=session.dataTask(with:url){continuation.resume(returning:ResourceTestResponse(data:$0,response:$1 as? HTTPURLResponse,error:$2))}
            task.cancel();task.resume()
        }
    }
    static func transport(_ url:URL)async->ResourceTestResponse {
        await withCheckedContinuation{continuation in NativeResourceTransport.dataTask(with:url){continuation.resume(returning:ResourceTestResponse(data:$0,response:$1 as? HTTPURLResponse,error:$2))}.resume()}
    }
    static func control(_ base:URL,_ value:[String:Any])async throws->[String:Any]{
        var request=URLRequest(url:base.appendingPathComponent("__qa"));request.httpMethod="POST";request.httpBody=try JSONSerialization.data(withJSONObject:value);request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let (bytes,response)=try await URLSession.shared.data(for:request)
        guard (response as? HTTPURLResponse)?.statusCode==200,let result=try JSONSerialization.jsonObject(with:bytes) as? [String:Any] else{throw ResourceTestFailure(description:"Private resource fixture control failed")};return result
    }
    static func blobs(_ stats:[String:Any],_ label:String)->Int{((stats["counts"] as? [String:Any])?[label] as? [String:Any])?["blobs"] as? Int ?? -1}
    static func counter(_ stats:[String:Any],_ label:String,_ name:String)->Int{((stats["counts"] as? [String:Any])?[label] as? [String:Any])?[name] as? Int ?? -1}
    static func hash(_ data:Data)->String{SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func expected(_ package:URL,_ manifest:NativeResourceManifest,_ path:String)throws->Data{
        guard let item=manifest.resources.first(where:{$0.path==path})else{throw ResourceTestFailure(description:"Synthetic fixture path missing")}
        return try Data(contentsOf:package.appendingPathComponent("blobs/\(item.sha256)"))
    }
    static func main()async{
        let checks=ResourceChecks();var summary:[String:Any]=[:]
        do {
            let args=CommandLine.arguments;guard args.count==3 else{throw ResourceTestFailure(description:"Expected config path and suite|reopen")}
            if args[2]=="admission" {
                let folder=URL(fileURLWithPath:args[1]);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                try await admissionRegression(folder,checks)
                let result:[String:Any]=["passed":checks.failures.isEmpty,"checks":checks.count,"failures":checks.failures,
                    "scope":"Actual Store with authored folder-only resources and explicit synthetic validator; controlled runtime-reader/validator gates test concurrency, no network or native-game playability claim"]
                try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("admission-report.json"),options:.atomic)
                print("RESOURCE_ADMISSION_RESULT \(checks.failures.isEmpty ? "PASS":"FAIL") \(checks.count) checks")
                if !checks.failures.isEmpty{exit(1)};return
            }
            let config=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:args[1]))) as! [String:Any]
            let output=URL(fileURLWithPath:config["output"] as! String),work=URL(fileURLWithPath:config["work"] as! String),a=URL(string:config["a"] as! String)!,b=URL(string:config["b"] as! String)!
            let packageA=URL(fileURLWithPath:config["packageA"] as! String),packageB=URL(fileURLWithPath:config["packageB"] as! String)
            let mA=try NativeResourceManifest.decode(Data(contentsOf:packageA.appendingPathComponent(NativeResourceManifest.filename))),mB=try NativeResourceManifest.decode(Data(contentsOf:packageB.appendingPathComponent(NativeResourceManifest.filename)))
            let payload="game/native/test-payload.bin",bytesA=try expected(packageA,mA,payload),bytesB=try expected(packageB,mB,payload)
            let configuration=URLSessionConfiguration.ephemeral;configuration.urlCache=nil;configuration.httpCookieStorage=nil;configuration.urlCredentialStorage=nil;configuration.httpShouldSetCookies=false
            let network=URLSession(configuration:configuration);defer{network.invalidateAndCancel()}
            let installRoot=work.appendingPathComponent("installed"),cacheRoot=work.appendingPathComponent("development")
            if args[2]=="reopen" {
                let reopened=NativeResourceStore(root:installRoot,session:network,validationIdentity:syntheticIdentity,runtimeValidator:validateSynthetic),reader=NativeResourceSession(store:reopened,network:network)
                checks.check(reopened.snapshot.mode == .installed,"installed mode persists across a new process")
                checks.check(reopened.snapshot.installedContentID==mA.contentID,"installed catalogue persists across a new process")
                let unconfigured=NativeResourceStore(root:installRoot,session:network)
                checks.check(!unconfigured.snapshot.hasPlayableInstallation,"reopened receipt needs matching explicit runtime validator")
                checks.rejects("unverified installed receipt cannot admit a direct data read"){_ = try unconfigured.localResource(for:a.appendingPathComponent(payload))}
                checks.rejects("unverified installed receipt cannot admit a direct file read"){_ = try unconfigured.installedURL(for:a.appendingPathComponent(payload))}
                try unconfigured.configureRuntimeValidation(identity:syntheticIdentity,validator:validateSynthetic)
                checks.check(unconfigured.snapshot.hasPlayableInstallation,"matching synthetic validation identity restores prior verified admission")
                let incompatible=NativeResourceStore(root:installRoot,session:network,validationIdentity:"synthetic-other-format-v1",runtimeValidator:validateSynthetic)
                checks.check(!incompatible.snapshot.hasPlayableInstallation,"different validator identity cannot inherit playable admission")
                let get=await response(reader,a.appendingPathComponent(payload));checks.check(get.error==nil&&get.data==bytesA,"reopened installed GET works with asset listener unavailable")
                let head=await response(reader,a.appendingPathComponent(payload),"HEAD");checks.check(head.error==nil&&head.data==nil&&head.response?.statusCode==200,"reopened installed HEAD works with asset listener unavailable")
                let unknown=await response(reader,b.appendingPathComponent("game/native/never-installed.bin"));checks.check(unknown.error != nil&&unknown.response==nil,"reopened missing resource never falls back to Mac")
            } else {
                checks.check(mA.contentID != mB.contentID,"one changed payload changes canonical manifest identity")
                checks.check(mA.resources.count==mB.resources.count,"changed snapshot preserves resource inventory")
                checks.check(zip(mA.resources,mB.resources).filter{$0.sha256 != $1.sha256}.count==1,"changed snapshot has exactly one changed resource")
                checks.check(mA.identity==mA.contentID,"Swift canonical identity matches actual Python producer")
                for p in ["game/../private.json","game//a.bin","game/a\\b.bin","game/%2e%2e/x","game/é.bin","/game/a.bin","https://example/game/a.bin","api/local/state","game/a b.bin"]{checks.check(!NativeResourceManifest.validPath(p),"manifest rejects unsafe path \(p)")}
                let make:([NativeResourceManifest.Resource])->NativeResourceManifest={items in
                    let provisional=NativeResourceManifest(schema:1,profile:NativeResourceManifest.profileName,contentID:String(repeating:"0",count:64),resources:items)
                    return NativeResourceManifest(schema:1,profile:provisional.profile,contentID:provisional.identity,resources:items)
                }
                checks.rejects("manifest rejects wrong content identity"){try NativeResourceManifest(schema:1,profile:mA.profile,contentID:String(repeating:"0",count:64),resources:mA.resources).validate()}
                checks.rejects("manifest rejects duplicate logical paths"){try make(mA.resources+[mA.resources[0]]).validate()}
                checks.rejects("manifest rejects missing mandatory native bootstrap"){try make(Array(mA.resources.dropFirst())).validate()}
                for size:Int64 in [0,-1,2_147_483_649] {
                    let item=NativeResourceManifest.Resource(path:payload,bytes:size,sha256:String(repeating:"a",count:64),required:true)
                    checks.rejects("manifest rejects per-resource byte budget \(size)"){try make([item]).validate()}
                }
                let excessive=(0..<129).map{NativeResourceManifest.Resource(path:"game/budget-\($0).bin",bytes:2_147_483_648,sha256:String(repeating:"a",count:64),required:true)}
                checks.rejects("manifest rejects aggregate installation budget"){try make(mA.resources+excessive).validate()}
                let wrongCase=NativeResourceManifest.Resource(path:payload,bytes:1,sha256:String(repeating:"A",count:64),required:true)
                checks.rejects("manifest rejects noncanonical digest"){try make([wrongCase]).validate()}
                checks.rejects("manifest rejects resource count budget"){try NativeResourceManifest(schema:1,profile:mA.profile,contentID:mA.contentID,resources:Array(repeating:mA.resources[0],count:200001)).validate()}
                checks.rejects("manifest decoder rejects byte budget"){_ = try NativeResourceManifest.decode(Data(repeating:32,count:64*1024*1024+1))}
                let unconfigured=NativeResourceStore(root:work.appendingPathComponent("unconfigured"),session:network)
                let unconfiguredResult=await operation{unconfigured.importPreparedFolder(packageA,progress:{_ in},completion:$0)}
                if case .failure=unconfiguredResult{checks.check(true,"unconfigured native setup cannot activate from integrity alone")}else{checks.check(false,"unconfigured native setup cannot activate from integrity alone")}
                checks.check(!unconfigured.snapshot.hasPlayableInstallation&&unconfigured.snapshot.installedContentID==nil,"unconfigured setup commits no playable receipt")
                checks.rejects("unconfigured setup cannot select installed mode"){try unconfigured.setMode(.installed)}
                for (label,identity) in [("empty",""),("oversize",String(repeating:"v",count:129))] {
                    let invalidPolicy=NativeResourceStore(root:work.appendingPathComponent("invalid-policy-"+label),session:network,validationIdentity:identity,runtimeValidator:validateSynthetic)
                    let result=await operation{invalidPolicy.importPreparedFolder(packageA,progress:{_ in},completion:$0)}
                    if case .failure=result{checks.check(true,"invalid runtime identity cannot activate \(label)")}else{checks.check(false,"invalid runtime identity cannot activate \(label)")}
                    checks.check(!invalidPolicy.snapshot.hasPlayableInstallation,"invalid runtime identity leaves playable admission disabled \(label)")
                }
                let malformedStore=NativeResourceStore(root:work.appendingPathComponent("malformed"),session:network,validationIdentity:syntheticIdentity,runtimeValidator:validateSynthetic)
                let malformedPackage=URL(fileURLWithPath:config["packageMalformed"] as! String)
                let malformedResult=await operation{malformedStore.importPreparedFolder(malformedPackage,progress:{_ in},completion:$0)}
                if case .failure=malformedResult{checks.check(true,"runtime validator rejects hash-valid malformed setup")}else{checks.check(false,"runtime validator rejects hash-valid malformed setup")}
                checks.check(!malformedStore.snapshot.hasPlayableInstallation&&malformedStore.snapshot.installedContentID==nil,"malformed runtime setup commits no playable receipt")
                let cache=NativeResourceStore(root:cacheRoot,session:network,validationIdentity:syntheticIdentity,runtimeValidator:validateSynthetic)
                var start=try await control(b,["action":"stats"])
                try checks.success(await operation{cache.cacheDevelopment(origin:a,progress:{_ in},completion:$0)},"initial actual HTTP development cache")
                var end=try await control(b,["action":"stats"])
                checks.check(blobs(end,"a")-blobs(start,"a")==Set(mA.resources.map(\.sha256)).count,"initial cache transfers exactly each unique verified blob")
                start=end
                try checks.success(await operation{cache.cacheDevelopment(origin:a,progress:{_ in},completion:$0)},"repeat actual HTTP development cache")
                end=try await control(b,["action":"stats"]);checks.check(blobs(end,"a")==blobs(start,"a"),"repeat cache transfers zero blobs")
                let restarted=NativeResourceStore(root:cacheRoot,session:network,validationIdentity:syntheticIdentity,runtimeValidator:validateSynthetic);start=end
                try checks.success(await operation{restarted.cacheDevelopment(origin:a,progress:{_ in},completion:$0)},"reopened cache uses persisted content hashes")
                end=try await control(b,["action":"stats"]);checks.check(blobs(end,"a")==blobs(start,"a"),"restart reuse transfers zero blobs")
                _=try await control(b,["action":"phase","phase":"B"]);start=try await control(b,["action":"stats"])
                try checks.success(await operation{cache.cacheDevelopment(origin:a,progress:{_ in},completion:$0)},"changed snapshot cache")
                end=try await control(b,["action":"stats"]);checks.check(blobs(end,"a")-blobs(start,"a")==1,"one changed snapshot transfers exactly one blob")
                checks.check(cache.snapshot.installedContentID==mB.contentID,"changed catalogue commits after verification")
                let receipt=try Data(contentsOf:cacheRoot.appendingPathComponent("active.json"))
                _=try await control(b,["action":"phase","phase":"corruptC"])
                let failed=await operation{cache.cacheDevelopment(origin:a,progress:{_ in},completion:$0)}
                if case .failure=failed{checks.check(true,"bad downloaded checksum fails")}else{checks.check(false,"bad downloaded checksum fails")}
                checks.check(try Data(contentsOf:cacheRoot.appendingPathComponent("active.json"))==receipt,"failure preserves active receipt bytes")
                checks.check(cache.snapshot.installedContentID==mB.contentID,"failure preserves active content identity")
                _=try await control(b,["action":"phase","phase":"delayC"]);start=try await control(b,["action":"stats"])
                let beforeCancellationBlobs=blobs(start,"a")
                let cancelled=await operation(cancelWhen:{
                    let observed=try await control(b,["action":"stats"])
                    return blobs(observed,"a")==beforeCancellationBlobs+1
                }){cache.cacheDevelopment(origin:a,progress:{_ in},completion:$0)}
                if case .failure=cancelled{checks.check(true,"inflight cancellation completes as failure")}else{checks.check(false,"inflight cancellation completes as failure")}
                end=try await control(b,["action":"stats"]);checks.check(blobs(end,"a")-blobs(start,"a")==1,"cancellation exercised actual delayed blob request")
                checks.check(try Data(contentsOf:cacheRoot.appendingPathComponent("active.json"))==receipt,"cancellation preserves active receipt bytes")
                _=try await control(b,["action":"phase","phase":"B"])
                let reader=NativeResourceSession(store:cache,network:network);start=try await control(b,["action":"stats"])
                let cancelledRead=await cancelledRequest(reader,b.appendingPathComponent(payload));let cancelledStats=try await control(b,["action":"stats"])
                checks.check((cancelledRead.error as? URLError)?.code == .cancelled&&counter(cancelledStats,"b","static")==counter(start,"b","static"),"cancel-before-resume completes once without network transfer")
                let foreign=await response(reader,b.appendingPathComponent(payload));end=try await control(b,["action":"stats"])
                checks.check(foreign.error==nil&&foreign.data==bytesB&&counter(end,"b","static")==counter(start,"b","static")+1,"development cache never impersonates a different origin")
                try checks.success(await operation{cache.cacheDevelopment(origin:b,progress:{_ in},completion:$0)},"different development origin explicitly committed")
                _=try await control(b,["action":"phase","phase":"A"]);start=try await control(b,["action":"stats"])
                let previous=await response(reader,a.appendingPathComponent(payload));end=try await control(b,["action":"stats"])
                checks.check(previous.data==bytesA&&previous.data != bytesB&&counter(end,"a","static")==counter(start,"a","static")+1,"old origin cannot read a new host catalogue from cache")
                _=try await control(b,["action":"phase","phase":"B"])
                try cache.setMode(.installed)
                let resource=mB.resources.first{$0.path==payload}!,blob=cacheRoot.appendingPathComponent("blobs/\(resource.sha256)")
                var corrupt=bytesB;corrupt[0]^=255;try corrupt.write(to:blob,options:.atomic)
                let verified=await operation{cache.verifyInstalled(progress:{_ in},completion:$0)}
                if case .failure=verified{checks.check(true,"installed corruption fails verification")}else{checks.check(false,"installed corruption fails verification")}
                checks.check(!cache.snapshot.hasPlayableInstallation,"corrupt installation is marked unusable")
                start=try await control(b,["action":"stats"]);let corruptRead=await response(reader,b.appendingPathComponent(payload));end=try await control(b,["action":"stats"])
                checks.check(corruptRead.error != nil&&counter(end,"b","static")==counter(start,"b","static"),"corrupt installed read fails without network fallback")
                start=end;try checks.success(await operation{cache.cacheDevelopment(origin:a,progress:{_ in},completion:$0)},"repair corrupt installed blob from existing source");end=try await control(b,["action":"stats"])
                checks.check(blobs(end,"a")-blobs(start,"a")==1,"corrupt repair transfers only one blob")
                try FileManager.default.removeItem(at:blob);checks.rejects("missing installed blob fails reader"){_ = try cache.localResource(for:a.appendingPathComponent(payload))}
                start=end;try checks.success(await operation{cache.cacheDevelopment(origin:a,progress:{_ in},completion:$0)},"repair missing installed blob");end=try await control(b,["action":"stats"])
                checks.check(blobs(end,"a")-blobs(start,"a")==1,"missing repair transfers only one blob")
                checks.rejects("actual local reader enforces caller byte budget"){_ = try cache.localResource(for:a.appendingPathComponent(payload),maximumBytes:1)}
                let installed=NativeResourceStore(root:installRoot,session:network,validationIdentity:syntheticIdentity,runtimeValidator:validateSynthetic)
                try checks.success(await operation{installed.importPreparedFolder(packageA,progress:{_ in},completion:$0)},"actual prepared folder import")
                try installed.setMode(.installed);let local=NativeResourceSession(store:installed,network:network)
                _=try await control(b,["action":"stopA"]);checks.notes.append("Asset listenerA closed before installed GET/HEAD; API listenerB remains reachable")
                let localGet=await response(local,a.appendingPathComponent(payload));checks.check(localGet.error==nil&&localGet.data==bytesA&&localGet.response?.value(forHTTPHeaderField:"X-ZGTA-Resource-Source")=="installed","installed GET succeeds without asset listener")
                let localHead=await response(local,a.appendingPathComponent(payload),"HEAD");checks.check(localHead.error==nil&&localHead.data==nil&&localHead.response?.value(forHTTPHeaderField:"Content-Length")==String(bytesA.count),"installed HEAD returns exact local metadata without asset listener")
                let badInstalledURL=URL(string:b.absoluteString+"/game/native/space%20asset.bin")!
                checks.rejects("direct installed data reader rejects invalid static path"){_ = try installed.localResource(for:badInstalledURL)}
                checks.rejects("direct installed file reader rejects invalid static path"){_ = try installed.installedURL(for:badInstalledURL)}
                start=try await control(b,["action":"stats"])
                let missing=await response(local,b.appendingPathComponent("game/native/not-installed.bin"));end=try await control(b,["action":"stats"])
                checks.check(missing.error != nil&&missing.response==nil&&counter(end,"b","static")==counter(start,"b","static"),"unknown installed resource never falls back to Mac")
                let malformed=await response(local,URL(string:b.absoluteString+"/game/native/space%20asset.bin")!);let afterMalformed=try await control(b,["action":"stats"])
                checks.check(malformed.error != nil&&counter(afterMalformed,"b","static")==counter(end,"b","static"),"invalid installed resource path also fails closed without Mac fallback")
                NativeResourceTransport.install{request,completion in local.dataTask(with:request,completionHandler:completion)}
                let ordinary=await transport(b.appendingPathComponent("api/local/status"));let apiEnd=try await control(b,["action":"stats"])
                checks.check(ordinary.error==nil&&ordinary.response?.statusCode==200&&counter(apiEnd,"b","api")==counter(afterMalformed,"b","api")+1,"ordinary API stays on actual network through resource transport")
                summary["finalHTTPStats"]=apiEnd
            }
            summary["runtimeValidationBoundary"]=["identity":syntheticIdentity,"scope":"Authored fixture schema only; not the App native-engine verifier and not engine playability"];summary["contentA"]=mA.contentID;summary["contentB"]=mB.contentID;summary["scope"]="Actual producer/HTTP module plus actual immutable Swift Manifest/Store/Session/Transport; synthetic prepared bytes only, no rendered or playable-game claim"
            summary["checks"]=checks.count;summary["failures"]=checks.failures;summary["notes"]=checks.notes;summary["passed"]=checks.failures.isEmpty
            try JSONSerialization.data(withJSONObject:summary,options:[.sortedKeys,.prettyPrinted]).write(to:output,options:.atomic)
            print("RESOURCE_TEST_RESULT \(checks.failures.isEmpty ? "PASS":"FAIL") \(checks.count) checks")
            if !checks.failures.isEmpty{exit(1)}
        }catch{print("RESOURCE_TEST_FATAL \(error)");exit(2)}
    }
}

private extension NativeResourceRegression {
    static func gateEntered(_ gate:ResourceIOGate)async->Bool {
        await withCheckedContinuation{continuation in DispatchQueue.global().async{continuation.resume(returning:gate.entered.wait(timeout:.now()+15) == .success)}}
    }
    static func rejectedRead(_ store:NativeResourceStore,_ url:URL)async->Bool {
        let handle=ResourceReadHandle(store,url)
        return await withCheckedContinuation{continuation in DispatchQueue.global().async{
            do{_=try handle.store.localResource(for:handle.url);continuation.resume(returning:false)}catch{continuation.resume(returning:true)}
        }}
    }
    static func admissionRegression(_ output:URL,_ checks:ResourceChecks)async throws {
        let files=FileManager.default,work=output.appendingPathComponent(UUID().uuidString),package=work.appendingPathComponent("authored-package")
        try files.createDirectory(at:package.appendingPathComponent("blobs"),withIntermediateDirectories:true)
        let payload="game/native/admission-payload.bin",url=URL(string:"https://authored.invalid/"+payload)!
        var rows=[NativeResourceManifest.Resource]()
        for path in Array(NativeResourceManifest.requiredPaths).sorted()+["game/world/synthetic.bin","game/world/synthetic.png",payload] {
            let bytes:Data
            if path.hasSuffix(".json"){bytes=try JSONSerialization.data(withJSONObject:["syntheticFixture":path])}
            else if path.hasSuffix(".png"){bytes=Data([137,80,78,71,13,10,26,10])+Data("authored image carrier".utf8)}
            else if path.hasSuffix("clips.bin"){bytes=Data("CLP1 authored transaction carrier".utf8)}
            else if path.hasSuffix("synthetic.bin"){bytes=Data("WRL2 authored transaction carrier".utf8)}
            else{bytes=Data("authored immutable payload bytes".utf8)}
            let digest=hash(bytes);try bytes.write(to:package.appendingPathComponent("blobs/"+digest))
            rows.append(.init(path:path,bytes:Int64(bytes.count),sha256:digest,required:true))
        }
        let unsigned=NativeResourceManifest(schema:1,profile:NativeResourceManifest.profileName,contentID:"",resources:rows)
        let manifest=NativeResourceManifest(schema:1,profile:unsigned.profile,contentID:unsigned.identity,resources:rows)
        try JSONEncoder().encode(manifest).write(to:package.appendingPathComponent(NativeResourceManifest.filename))
        let item=rows.first{$0.path==payload}!,good=try Data(contentsOf:package.appendingPathComponent("blobs/"+item.sha256))
        var bad=good;bad[0]^=1
        let other=rows.first{$0.path != payload}!,otherGood=try Data(contentsOf:package.appendingPathComponent("blobs/"+other.sha256))
        func blob(_ root:URL)->URL{root.appendingPathComponent("blobs/"+item.sha256)}
        func receipt(_ root:URL)throws->[String:Any]{try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("active.json")))as![String:Any]}
        func make(_ name:String,reader:NativeResourceStore.RuntimeDataReader?=nil,validator:NativeResourceStore.RuntimeValidator?=nil)async throws->(NativeResourceStore,URL) {
            let root=work.appendingPathComponent(name),store=NativeResourceStore(root:root,validationIdentity:syntheticIdentity,runtimeValidator:validator ?? validateSynthetic,runtimeDataReader:reader)
            try checks.success(await operation{store.importPreparedFolder(package,progress:{_ in},completion:$0)},name+" folder import")
            try store.setMode(.installed);return(store,root)
        }
        func reopened(_ root:URL)->NativeResourceStore{NativeResourceStore(root:root,validationIdentity:syntheticIdentity,runtimeValidator:validateSynthetic)}
        let (store,root)=try await make("checksum")
        let originalID=try receipt(root)["admissionID"]as!String
        try bad.write(to:blob(root),options:.atomic)
        checks.rejects("runtime data checksum is rejected"){_=try store.localResource(for:url)}
        checks.check(!store.snapshot.hasPlayableInstallation,"runtime checksum immediately revokes admission")
        checks.check(store.snapshot.mode == .installed,"runtime fault never silently selects development")
        checks.check(store.snapshot.cachedFiles==rows.count-1,"bad blob removed from cache accounting")
        checks.check(store.snapshot.installedContentID==manifest.contentID,"fault retains active catalogue identity")
        checks.check(try Data(contentsOf:root.appendingPathComponent("blobs/"+other.sha256))==otherGood,"unrelated good blob retained")
        checks.check(try (receipt(root)["manifest"]as![String:Any])["contentID"]as?String==manifest.contentID,"fault retains receipt manifest")
        try store.configureRuntimeValidation(identity:syntheticIdentity,validator:validateSynthetic)
        checks.check(!store.snapshot.hasPlayableInstallation,"configure cannot erase observed corruption")
        checks.check(!reopened(root).snapshot.hasPlayableInstallation,"same-sized corruption remains blocked after relaunch")
        checks.check(reopened(root).snapshot.cachedFiles==rows.count-1,"corrupt cache accounting stays removed after relaunch")
        try good.write(to:blob(root),options:.atomic)
        try store.configureRuntimeValidation(identity:syntheticIdentity,validator:validateSynthetic)
        checks.check(!store.snapshot.hasPlayableInstallation,"manual same-sized restoration still needs actual verification")
        try checks.success(await operation{store.verifyInstalled(progress:{_ in},completion:$0)},"full verification restores admission")
        checks.check(store.snapshot.hasPlayableInstallation && reopened(root).snapshot.hasPlayableInstallation,"verified repair persists admitted state")
        checks.check(store.snapshot.cachedFiles==rows.count,"successful verification restores verified accounting")
        checks.check(try receipt(root)["admissionID"]as?String != originalID,"successful verification publishes fresh admission generation")
        try bad.write(to:blob(root),options:.atomic)
        checks.rejects("file lookup detects checksum failure"){_=try store.installedURL(for:url)}
        checks.check(!store.snapshot.hasPlayableInstallation && !reopened(root).snapshot.hasPlayableInstallation,"file checksum also persistently revokes admission")
        try checks.success(await operation{store.importPreparedFolder(package,progress:{_ in},completion:$0)},"explicit folder repair")
        try files.removeItem(at:blob(root))
        checks.rejects("known missing data blob fails reader"){_=try store.localResource(for:url)}
        checks.check(!store.snapshot.hasPlayableInstallation && !reopened(root).snapshot.hasPlayableInstallation,"known missing blob persistently revokes admission")
        try checks.success(await operation{store.importPreparedFolder(package,progress:{_ in},completion:$0)},"repair missing known blob")
        let (failedRepair,failedRoot)=try await make("failed-explicit-repair")
        let badSource=work.appendingPathComponent("authored-bad-source");try files.copyItem(at:package,to:badSource)
        try bad.write(to:blob(failedRoot),options:.atomic)
        try bad.write(to:badSource.appendingPathComponent("blobs/"+item.sha256),options:.atomic)
        if case .failure=await operation({failedRepair.importPreparedFolder(badSource,progress:{_ in},completion:$0)}){checks.check(true,"bad explicit repair source fails")}else{checks.check(false,"bad explicit repair source fails")}
        checks.check(!failedRepair.snapshot.hasPlayableInstallation && !reopened(failedRoot).snapshot.hasPlayableInstallation,"repair's own observation cannot leave known bad old installation admitted")
        let (policy,policyRoot)=try await make("request-policy");try bad.write(to:blob(policyRoot),options:.atomic)
        for invalid in [URL(string:url.absoluteString+"?unsupported=1")!,URL(string:url.absoluteString+"#fragment")!,URL(string:"ftp://authored.invalid/"+payload)!,URL(string:"https://authored.invalid/game/native/space%20asset.bin")!] {
            checks.rejects("invalid data request rejected without corruption observation"){_=try policy.localResource(for:invalid)}
            checks.rejects("invalid file request rejected without corruption observation"){_=try policy.installedURL(for:invalid)}
            checks.check(policy.snapshot.hasPlayableInstallation,"invalid URL/query is not blob corruption")
        }
        checks.rejects("reader byte budget rejected"){_=try policy.localResource(for:url,maximumBytes:1)}
        checks.rejects("unknown installed path rejected"){_=try policy.localResource(for:URL(string:"https://authored.invalid/game/native/not-indexed.bin")!)}
        checks.check(policy.snapshot.hasPlayableInstallation && policy.snapshot.cachedFiles==rows.count,"budget/unknown path cannot poison known blobs")
        checks.rejects("valid request then observes real corruption"){_=try policy.localResource(for:url)}
        checks.check(!policy.snapshot.hasPlayableInstallation,"only real known-blob observation invalidates")
        let (development,devRoot)=try await make("development")
        try development.setMode(.development)
        // Authored persisted origin fixture, equivalent to an explicitly chosen
        // development cache source. No network request or downloader is faked.
        var devReceipt=try receipt(devRoot);devReceipt["developmentOrigin"]="https://authored.invalid"
        try JSONSerialization.data(withJSONObject:devReceipt).write(to:devRoot.appendingPathComponent("active.json"),options:.atomic)
        let dev=reopened(devRoot);try bad.write(to:blob(devRoot),options:.atomic)
        checks.check(try dev.localResource(for:URL(string:"https://foreign.invalid/"+payload)!)==nil,"foreign development origin bypasses cache")
        checks.check(dev.snapshot.hasPlayableInstallation,"foreign-origin miss did not observe local corruption")
        checks.check(try dev.localResource(for:url)==nil,"corrupt development data becomes explicit source cache miss")
        checks.check(!dev.snapshot.hasPlayableInstallation,"development corruption still revokes installed admission")
        checks.check(try dev.installedURL(for:url)==nil,"corrupt development file becomes explicit source cache miss")
        try checks.success(await operation{dev.importPreparedFolder(package,progress:{_ in},completion:$0)},"development cache explicit source repair")
        checks.check(dev.snapshot.hasPlayableInstallation,"explicit development repair is verified")
        let (legacy,legacyRoot)=try await make("legacy-v1");var legacyReceipt=try receipt(legacyRoot)
        for key in ["admissionID","invalidAdmission","invalidDigests"]{legacyReceipt.removeValue(forKey:key)}
        try JSONSerialization.data(withJSONObject:legacyReceipt).write(to:legacyRoot.appendingPathComponent("active.json"),options:.atomic)
        let old=reopened(legacyRoot)
        checks.check(old.snapshot.hasPlayableInstallation,"compatible v1 receipt requires no ISO reimport")
        try bad.write(to:blob(legacyRoot),options:.atomic);checks.rejects("legacy fault detected"){_=try old.localResource(for:url)}
        checks.check(!reopened(legacyRoot).snapshot.hasPlayableInstallation,"legacy invalidation survives relaunch")
        _=legacy
        for variant in ["malformed","unreadable","dangling-link","write-failure"] {
            let (broken,brokenRoot)=try await make("marker-"+variant)
            if variant=="write-failure"{
                try files.removeItem(at:brokenRoot.appendingPathComponent("invalid-admissions"))
                try Data("authored malformed metadata parent".utf8).write(to:brokenRoot.appendingPathComponent("invalid-admissions"))
            }
            try bad.write(to:blob(brokenRoot),options:.atomic);checks.rejects("marker case observes blob fault"){_=try broken.localResource(for:url)}
            if variant != "write-failure" {
                let marker=try files.contentsOfDirectory(at:brokenRoot.appendingPathComponent("invalid-admissions"),includingPropertiesForKeys:nil).first!
                if variant=="malformed"{try Data("not-json".utf8).write(to:marker,options:.atomic)}
                else if variant=="dangling-link"{try files.removeItem(at:marker);try files.createSymbolicLink(at:marker,withDestinationURL:brokenRoot.appendingPathComponent("authored-missing-target"))}
                else{try files.removeItem(at:marker);try files.createDirectory(at:marker,withIntermediateDirectories:true)}
            }
            try good.write(to:blob(brokenRoot),options:.atomic)
            let restart=reopened(brokenRoot)
            checks.check(!restart.snapshot.hasPlayableInstallation,"\(variant) marker fails closed on restart")
            try restart.configureRuntimeValidation(identity:syntheticIdentity,validator:validateSynthetic)
            checks.check(!restart.snapshot.hasPlayableInstallation,"\(variant) marker cannot be cleared by configure")
            checks.check(restart.snapshot.installedContentID==manifest.contentID,"\(variant) marker retains catalogue")
            try checks.success(await operation{restart.verifyInstalled(progress:{_ in},completion:$0)},"\(variant) actual verify repairs admission metadata")
            checks.check(reopened(brokenRoot).snapshot.hasPlayableInstallation,"\(variant) verified new receipt survives restart")
        }
        let readGate=ResourceIOGate()
        let reader:NativeResourceStore.RuntimeDataReader={location in
            var data=try Data(contentsOf:location)
            if location.lastPathComponent==item.sha256,try readGate.pauseIfArmed(){data[0]^=1}
            return data
        }
        let (stale,staleRoot)=try await make("stale-runtime-read",reader:reader)
        let prior=try receipt(staleRoot)["admissionID"]as!String
        readGate.arm();async let staleRead=rejectedRead(stale,url)
        checks.check(await gateEntered(readGate),"controlled old runtime read reached I/O boundary")
        try checks.success(await operation{stale.verifyInstalled(progress:{_ in},completion:$0)},"same-content replacement fully verifies while old read waits")
        readGate.release.signal();checks.check(await staleRead,"old checksum read still reports failure to its own caller")
        checks.check(stale.snapshot.hasPlayableInstallation && stale.snapshot.cachedFiles==rows.count,"stale failure cannot invalidate replacement or evict its cache")
        checks.check(try receipt(staleRoot)["admissionID"]as?String != prior,"replacement really has a new persisted generation")
        checks.check(reopened(staleRoot).snapshot.hasPlayableInstallation,"stale failure cannot poison replacement restart")
        let replacement=reopened(staleRoot)
        readGate.arm();async let otherStoreRead=rejectedRead(stale,url)
        checks.check(await gateEntered(readGate),"old Store runtime I/O waits before another Store commits")
        try checks.success(await operation{replacement.verifyInstalled(progress:{_ in},completion:$0)},"separate Store commits verified replacement generation")
        readGate.release.signal();checks.check(await otherStoreRead,"old Store caller still sees its checksum error")
        checks.check(replacement.snapshot.hasPlayableInstallation && reopened(staleRoot).snapshot.hasPlayableInstallation,"old Store cannot invalidate another Store's verified generation")
        checks.check(reopened(staleRoot).snapshot.cachedFiles==rows.count,"old Store cannot evict replacement persistent accounting")
        let sameReadGate=ResourceIOGate(),validationGate=ResourceIOGate()
        let sameReader:NativeResourceStore.RuntimeDataReader={location in var data=try Data(contentsOf:location);if location.lastPathComponent==item.sha256,try sameReadGate.pauseIfArmed(){data[0]^=1};return data}
        let validator:NativeResourceStore.RuntimeValidator={manifest,resolve in try validateSynthetic(manifest,resolve);_=try validationGate.pauseIfArmed()}
        let (same,sameRoot)=try await make("same-generation",reader:sameReader,validator:validator)
        sameReadGate.arm();async let pendingRead=rejectedRead(same,url)
        checks.check(await gateEntered(sameReadGate),"same-generation read waits after reading actual bytes")
        validationGate.arm();async let verifying=operation{same.verifyInstalled(progress:{_ in},completion:$0)}
        checks.check(await gateEntered(validationGate),"verification waits after actual integrity/native-policy checks")
        sameReadGate.release.signal();checks.check(await pendingRead,"same-generation corruption is observed during verification")
        validationGate.release.signal()
        if case .failure=await verifying{checks.check(true,"concurrent same-generation fault prevents verification commit")}else{checks.check(false,"concurrent same-generation fault prevents verification commit")}
        checks.check(!same.snapshot.hasPlayableInstallation && !reopened(sameRoot).snapshot.hasPlayableInstallation,"concurrent fault cannot be revived by pending verification")
        try checks.success(await operation{same.verifyInstalled(progress:{_ in},completion:$0)},"later complete verification restores admission")
        checks.check(reopened(sameRoot).snapshot.hasPlayableInstallation,"later verified admission is durable")
    }
}
