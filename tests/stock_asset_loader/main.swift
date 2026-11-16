// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

typealias Loader=NativeSAMPStockAssetLoader
struct Case:Decodable {
    let label,manifest,base,expect:String
    let id:Int32
    let local:Bool?
    let mutation:String?
    let limits:[String:Double]?
    let access:String?
}
struct RawCase:Decodable {
    let label,base,expect:String
    let metadata:NativeSAMPStockModels.Asset?
    let catalog:String?
    let id:Int32?
    let local:Bool?
}
var checks=0
func require(_ condition:@autoclosure()->Bool,_ label:String) {
    checks+=1;if !condition() { fatalError("stock asset loader: \(label)") }
}
func category(_ error:Error)->String {
    guard let value=error as? Loader.Failure else {
        if error is NativeRenderWareDFF.Failure { return "dff" }
        if error is NativeRenderWareTXD.DecodeError { return "txd" }
        if error is NativeRenderWareCollision.Failure { return "col" }
        if error is NativeRenderWareModel.Failure { return "plan" }
        if (error as NSError).code == NSURLErrorTimedOut { return "timeout" }
        return "other"
    }
    switch value {
    case .invalidURL:return "url"
    case .invalidResolution:return "resolution"
    case .limit:return "limit"
    case .unsupportedKind:return "kind"
    case .missingAssets:return "missing"
    case .http:return "http"
    case .size:return "size"
    case .checksum:return "crc"
    case .sha256:return "sha"
    case .redirect:return "redirect"
    case .encoding:return "encoding"
    case .io:return "io"
    case .cancelled:return "cancelled"
    case .unresolvedTextures:return "textures"
    case .noRenderableGeometry:return "geometry"
    }
}
final class Tests {
    let cases:[Case],rawCases:[RawCase],specialManifest:String,base:URL
    var index=0,rawIndex=0,rows:[[String:Any]]=[]
    var loader:Loader?
    init() throws {
        cases=try JSONDecoder().decode([Case].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        specialManifest=CommandLine.arguments[2];base=URL(string:CommandLine.arguments[3])!
        rawCases=try JSONDecoder().decode([RawCase].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[4])))
    }
    func resolution(_ manifest:String,_ id:Int32,_ base:URL)throws->NativeSAMPStockModels.Resolution {
        try NativeSAMPStockModels.decode(Data(contentsOf:URL(fileURLWithPath:manifest))).resolve(id:id,assetBaseURL:base)
    }
    func next() {
        guard index < cases.count else { rawNext();return }
        let item=cases[index];index+=1
        do {
            let url=URL(string:item.base)!
            var limits=Loader.Limits()
            for (key,value) in item.limits ?? [:] {
                switch key {
                case "files":limits.filesPerModel=Int(value)
                case "file":limits.fileBytes=Int(value)
                case "encoded":limits.encodedBytesPerModel=Int(value)
                case "decoded":limits.decodedTextureBytes=Int(value)
                case "textures":limits.textures=Int(value)
                case "prepared":limits.preparedBytes=Int(value)
                case "timeout":limits.requestTimeout=value;limits.resourceTimeout=value
                default:fatalError("unknown test limit")
                }
            }
            let owner=try Loader(assetBaseURL:url,limits:limits,allowLocalFiles:item.local ?? false,accessProvider:item.access.map { policy in
                return {
                    dispatchPrecondition(condition:.onQueue(.main))
                    let domain=url.host!,expires=Date().addingTimeInterval(policy == "expired" ? -60:600)
                    func cookie(_ name:String,_ token:String,_ host:String)->HTTPCookie {
                        var fields:[HTTPCookiePropertyKey:Any]=[.name:name,.value:token,.domain:host,.path:"/",.expires:expires]
                        if policy == "secure" {fields[.secure]="TRUE"}
                        return HTTPCookie(properties:fields)!
                    }
                    let cookies=[cookie("zgta_access",String(repeating:"a",count:64),domain),
                                 cookie("zgta_local","never-forward-profile",domain),cookie("discord_session","never-forward-discord",domain),
                                 cookie("zgta_access",String(repeating:"b",count:64),"play.samp.directory")]
                    let selected=policy == "wrong-origin" ? URL(string:"http://127.0.0.1:\((url.port ?? 80)+1)")!:url
                    return NativeStockAssetAccess(assetOrigin:selected,sessionCookies:cookies)
                }
            });loader=owner
            var value=try resolution(item.manifest,item.id,url)
            if let mutation=item.mutation {
                guard let dff=value.dff else { fatalError("fixture missing dff") }
                let replacement:NativeSAMPStockModels.File
                if mutation == "origin" { replacement = .init(metadata:dff.metadata,url:URL(string:"http://127.0.0.1:1/evil.dff")!) }
                else if mutation == "path" { replacement = .init(metadata:.init(path:"../escape.dff",bytes:dff.metadata.bytes,crc32:dff.metadata.crc32,sha256:dff.metadata.sha256),url:dff.url) }
                else { fatalError("bad mutation") }
                value = .init(model:value.model,dff:replacement,dictionaries:value.dictionaries,textureSearch:value.textureSearch)
            }
            let epoch=owner.generation
            owner.load(value) { result in
                switch result {
                case .success(let prepared):
                    require(item.expect == "ok", "\(item.label) unexpectedly succeeded")
                    require(prepared.generation == epoch && prepared.model.id == item.id,"\(item.label) request identity")
                    require(!prepared.plan.draws.isEmpty,"\(item.label) actual indexed plan")
                    require(!prepared.plan.diagnostics.contains{if case .missingTexture=$0{return true};return false},"\(item.label) no unresolved materials")
                    if item.id == 1000 {
                        require(prepared.textures.textures.map{$0.lookupName} == ["session_texture","parent_only"],"exact child-first dictionary merge")
                        require(Array(prepared.textures.textures[0].mipLevels[0].rgba8!.prefix(4)) == [255,0,0,255],"parent duplicate cannot replace child pixels")
                        if item.label == "embedded-authored-COL" {
                            require(prepared.embeddedCollision.count == 1 && prepared.embeddedCollision[0].boxes.count == 1,"authored collision actually decoded")
                            require(prepared.embeddedCollision[0].name == "panel" && prepared.embeddedCollision[0].modelID == 1000,"authored collision header identity")
                        } else { require(prepared.embeddedCollision.isEmpty,"no fabricated collision from render geometry") }
                    }
                    self.rows.append(["label":item.label,"result":"ok","draws":prepared.plan.draws.count,"textures":prepared.textures.textures.count])
                case .failure(let error):
                    require(category(error) == item.expect,"\(item.label): expected \(item.expect), got \(category(error)): \(error)")
                    if case Loader.Failure.missingAssets(let names)=error { require(!names.isEmpty,"explicit missing names") }
                    self.rows.append(["label":item.label,"result":category(error),"detail":String(describing:error)])
                }
                DispatchQueue.main.async { self.next() }
            }
        } catch {
            require(category(error) == item.expect,"\(item.label) init: \(error)")
            rows.append(["label":item.label,"result":category(error)])
            DispatchQueue.main.async { self.next() }
        }
    }
    func rawNext() {
        guard rawIndex < rawCases.count else { special();return }
        let item=rawCases[rawIndex];rawIndex+=1
        do {
            let url=URL(string:item.base)!
            let owner=try Loader(assetBaseURL:url,allowLocalFiles:item.local ?? false);loader=owner
            var catalog:NativeSAMPStockCollisionCatalog?,colFile:NativeSAMPStockCollisionCatalog.File?
            let file:NativeSAMPStockModels.File
            if let path=item.catalog {
                let value=try NativeSAMPStockCollisionCatalog.decode(Data(contentsOf:URL(fileURLWithPath:path)))
                let names:[Int32:String]=[966:"bar_gatebar01",980:"airportgate",1225:"barrel4",1231:"streetlamp2"]
                guard let id=item.id,let name=names[id],case .unique(let found)=try value.resolve(modelID:id,modelName:name,assetBaseURL:url,allowLocalFiles:true) else { fatalError("exact COL fixture unavailable") }
                catalog=value;colFile=found
                let m=found.metadata
                file = .init(metadata:.init(path:m.path,bytes:m.bytes,crc32:m.crc32,sha256:m.sha256),url:found.url)
            } else {
                let m=item.metadata!;var target=url
                for part in m.path.split(separator:"/") { target.appendPathComponent(String(part)) }
                file = .init(metadata:m,url:target)
            }
            let epoch=owner.generation
            owner.loadFile(file) { result in
                switch result {
                case .success(let blob):
                    require(item.expect == "ok","\(item.label) raw unexpected success")
                    require(blob.generation == epoch && blob.file.url == file.url && blob.data.count == file.metadata.bytes,"raw file/generation identity")
                    do {
                        let model:NativeRenderWareCollision.Model
                        if let catalog,let colFile { model=try catalog.prepare(blob.data,for:colFile) }
                        else {
                            let models=try NativeRenderWareCollision.decode(blob.data)
                            require(models.count == 1,"raw generated COL parsed")
                            model=models[0];require(model.boxes.count == 1 && model.name == "panel","raw authored COL box/name")
                        }
                        require(model.modelID == UInt16(item.id ?? 1000),"external COL header ID verified")
                    } catch { fatalError("raw verified bytes failed COL identity decode: \(error)") }
                    self.rows.append(["label":item.label,"result":"ok","rawBytes":blob.data.count])
                case .failure(let error):
                    require(category(error) == item.expect,"\(item.label) raw error: \(error)")
                    self.rows.append(["label":item.label,"result":category(error)])
                }
                self.rawNext()
            }
        } catch { fatalError("raw fixture: \(error)") }
    }
    func special() {
        do {
            var limits=Loader.Limits();limits.concurrentLoads=1;limits.pendingLoads=1
            let owner=try Loader(assetBaseURL:base,limits:limits);loader=owner
            let value=try resolution(specialManifest,1000,base)
            let old=owner.generation
            var completions=0
            var finalStarted=false
            func completed() {
                completions+=1
                if completions == 3 && !finalStarted {
                    finalStarted=true
                    require(owner.activeCount == 0 && owner.pendingCount == 0,"cancelled workers actually exit before slot release")
                    owner.load(value) { result in
                        switch result {
                        case .success(let prepared):require(prepared.generation == owner.generation && prepared.generation != old,"new generation can prepare exact assets")
                        case .failure(let error):fatalError("post-reset load: \(error)")
                        }
                        self.rows.append(["label":"reset-cancel-queue-generation","result":"ok","callbacks":completions+1])
                        self.concurrent()
                    }
                }
            }
            owner.load(value) { result in
                if case .failure(let error)=result { require(category(error) == "cancelled","active old-generation cancellation") }
                else { fatalError("reset delivered stale prepared resources") }
                completed()
            }
            let pending=owner.load(value) { result in
                if case .failure(let error)=result { require(category(error) == "cancelled","pending cancellation") }
                else { fatalError("cancelled pending job prepared") }
                completed()
            }
            owner.load(value) { result in
                if case .failure(let error)=result { require(category(error) == "limit","bounded pending queue") }
                else { fatalError("queue overflow prepared") }
                completed()
            }
            require(owner.activeCount == 1 && owner.pendingCount == 1,"bounded active/pending jobs")
            owner.cancel(pending)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.05) {
                require(owner.reset() == old+1,"monotonic reset generation")
                require(owner.activeCount <= 1,"reset retains decoder concurrency slot")
            }
        } catch { fatalError("special fixture: \(error)") }
    }
    func concurrent() {
        do {
            var limits=Loader.Limits();limits.concurrentLoads=2
            let owner=try Loader(assetBaseURL:base,limits:limits);loader=owner
            let value=try resolution(specialManifest,1000,base)
            var count=0
            for _ in 0..<5 {
                owner.load(value) { result in
                    if case .failure(let error)=result { fatalError("concurrency: \(error)") }
                    count+=1;require(owner.activeCount <= 2,"concurrent job bound")
                    if count == 5 {
                        self.rows.append(["label":"concurrent-real-transfers","result":"ok","models":count])
                        self.rawReset()
                    }
                }
            }
            require(owner.activeCount == 2 && owner.pendingCount == 3,"bounded queued real loads")
        } catch { fatalError("concurrent fixture: \(error)") }
    }
    func rawReset() {
        do {
            var limits=Loader.Limits();limits.concurrentLoads=1
            let owner=try Loader(assetBaseURL:base,limits:limits);loader=owner
            let original=rawCases.first(where:{$0.label == "raw-http-COL"})!.metadata!
            let slow=NativeSAMPStockModels.Asset(path:"slow/fixture.col",bytes:original.bytes,crc32:original.crc32,sha256:original.sha256)
            let file=NativeSAMPStockModels.File(metadata:slow,url:base.appendingPathComponent(slow.path))
            let old=owner.generation;var callbacks=0
            func cancelled(_ result:Result<Loader.BlobData,Error>) {
                if case .failure(let error)=result { require(category(error) == "cancelled","raw reset cancellation") }
                else { fatalError("stale raw blob escaped reset") }
                callbacks+=1
                if callbacks == 2 {
                    let fresh=NativeSAMPStockModels.File(metadata:original,url:base.appendingPathComponent(original.path))
                    owner.loadFile(fresh) { result in
                        guard case .success(let blob)=result else { fatalError("raw fresh generation failed") }
                        require(blob.generation == old+1 && blob.generation == owner.generation,"raw fresh generation")
                        require((try? NativeRenderWareCollision.decode(blob.data).count) == 1,"fresh raw bytes actually parse")
                        self.rows.append(["label":"raw-reset-and-pending-cancel","result":"ok","callbacks":callbacks+1])
                        self.done()
                    }
                }
            }
            owner.loadFile(file,completion:cancelled)
            let pending=owner.loadFile(file,completion:cancelled)
            require(owner.activeCount == 1 && owner.pendingCount == 1,"raw uses same bounded owner queue")
            owner.cancel(pending)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.05) { _=owner.reset() }
        } catch { fatalError("raw reset fixture: \(error)") }
    }
    func done() {
        let report:[String:Any]=["status":"PASS","checks":checks,"cases":rows,"scope":"Verified streaming transfer and CPU preparation only; no Metal upload or collision-world registration claimed"]
        print(String(data:try! JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),encoding:.utf8)!)
        exit(0)
    }
}
let tests=try Tests()
DispatchQueue.main.async { tests.next() }
dispatchMain()
