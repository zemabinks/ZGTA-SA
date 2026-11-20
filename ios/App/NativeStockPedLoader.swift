// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Verified stock DFF/dictionary acquisition followed by the existing native
/// skeletal/material preparation. This owns CPU admission, never a drawn actor.
/// A renderer must still validate the source and publish a real GPU resource.
final class NativeStockPedLoader {
    struct Limits {
        var pending=8,decodedTextureBytes=64*1024*1024,textures=2_048,preparedBytes=64*1024*1024
        var vertices=99_999,triangles=200_000,frames=512,bones=64
    }
    enum Failure:Error {case configuration,cancelled,pendingLimit,noGeometry,diagnostic(String),preparedLimit}
    struct Prepared {
        let requestID:UUID,generation:UInt64,sourceIdentity:String
        let model:NativeSAMPStockModels.Model
        let plan:NativeRenderWarePedModel.Plan
        var resourceBytes:Int {plan.model.meshByteCount+plan.model.textureByteCount+plan.skeleton.encodedByteCount}
    }
    typealias Completion=(Result<Prepared,Error>)->Void
    private struct Pending {
        let id:UUID,generation:UInt64,source:String,resolution:NativeSAMPStockModels.Resolution
        let files:[NativeSAMPStockModels.File],completion:Completion
    }
    private struct Running {let item:Pending,job:StockPedJob}
    private let fileLoader:NativeSAMPStockAssetLoader,sourceIdentity:()->String,limits:Limits
    private var pending:[Pending]=[],running:Running?,observedSource:String
    private(set) var generation:UInt64=1
    var activeCount:Int{main();return running == nil ? 0:1}
    var pendingCount:Int{main();return pending.count}
    init(fileLoader:NativeSAMPStockAssetLoader,sourceIdentity:@escaping()->String,limits:Limits = .init())throws {
        dispatchPrecondition(condition:.onQueue(.main))
        guard (1...32).contains(limits.pending),(1...64*1024*1024).contains(limits.decodedTextureBytes),
              (1...8_192).contains(limits.textures),(1...64*1024*1024).contains(limits.preparedBytes),
              (1...99_999).contains(limits.vertices),(1...200_000).contains(limits.triangles),
              (1...512).contains(limits.frames),(1...64).contains(limits.bones)else{throw Failure.configuration}
        self.fileLoader=fileLoader;self.sourceIdentity=sourceIdentity;self.limits=limits;observedSource=sourceIdentity()
    }
    deinit {if let job=running?.job{DispatchQueue.main.async{job.cancel()}}}
    private func main(){dispatchPrecondition(condition:.onQueue(.main))}
    @discardableResult func load(_ resolution:NativeSAMPStockModels.Resolution,completion:@escaping Completion)->UUID {
        main();_=invalidateIfSourceChanged();let id=UUID()
        do {
            guard pending.count<limits.pending else{throw Failure.pendingLimit}
            let files=try fileLoader.pedestrianFiles(resolution)
            pending.append(.init(id:id,generation:generation,source:observedSource,resolution:resolution,files:files,completion:completion))
            pump()
        }catch{DispatchQueue.main.async{completion(.failure(error))}}
        return id
    }
    func cancel(_ id:UUID) {
        main()
        if let index=pending.firstIndex(where:{$0.id==id}) {
            let item=pending.remove(at:index);DispatchQueue.main.async{item.completion(.failure(Failure.cancelled))}
        }
        if running?.item.id==id{running?.job.cancel()}
    }
    /// A cancelled decoder keeps the one active slot until it actually exits.
    /// The shared verifier is never reset: object/COL loads have other owners.
    @discardableResult func reset()->UInt64 {
        main();generation &+= 1;observedSource=sourceIdentity()
        let retired=pending;pending.removeAll();running?.job.cancel()
        for item in retired{DispatchQueue.main.async{item.completion(.failure(Failure.cancelled))}}
        return generation
    }
    @discardableResult func invalidateIfSourceChanged()->Bool {
        main();guard observedSource != sourceIdentity()else{return false};_=reset();return true
    }
    func isCurrent(_ value:Prepared)->Bool {
        main();return value.generation==generation && value.sourceIdentity==observedSource && observedSource==sourceIdentity()
    }
    private func pump() {
        main();guard running==nil,!pending.isEmpty else{return}
        let item=pending.removeFirst()
        guard item.source==sourceIdentity(),item.generation==generation else {
            DispatchQueue.main.async{item.completion(.failure(Failure.cancelled));self.pump()};return
        }
        let job=StockPedJob(loader:fileLoader,files:item.files,limits:limits){[weak self] result in
            guard let self,self.running?.item.id==item.id else{return}
            let cancelled=self.running?.job.isCancelled != false
            self.running=nil
            let valid = !cancelled && item.generation==self.generation && item.source==self.sourceIdentity() && item.source==self.observedSource
            let reply:Result<Prepared,Error>=valid ? result.map{.init(requestID:item.id,generation:item.generation,sourceIdentity:item.source,model:item.resolution.model,plan:$0)}:.failure(Failure.cancelled)
            item.completion(reply);self.pump()
        }
        running = .init(item:item,job:job);job.start()
    }
}

/// All mutable parse state stays on one process-wide serial utility queue.
/// Main-thread cancellation changes only the ticket and active file request.
private final class StockPedJob {
    typealias Loader=NativeStockPedLoader
    private static let cpu=DispatchQueue(label:"ZGTA.StockPed.prepare",qos:.utility)
    private let loader:NativeSAMPStockAssetLoader,files:[NativeSAMPStockModels.File],limits:Loader.Limits
    private let completion:(Result<NativeRenderWarePedModel.Plan,Error>)->Void
    private let lock=NSLock()
    private var cancelled=false
    var isCancelled:Bool{lock.lock();defer{lock.unlock()};return cancelled}
    private var request:UUID?,next=0,finished=false
    // CPU queue only:
    private var dff:NativeRenderWareDFF?,textures:[NativeRenderWareTXD.Texture]=[],names=Set<String>()
    private var decodedBytes=0,decodedCount=0,version:UInt32=0,device:UInt16=2
    init(loader:NativeSAMPStockAssetLoader,files:[NativeSAMPStockModels.File],limits:Loader.Limits,
         completion:@escaping(Result<NativeRenderWarePedModel.Plan,Error>)->Void) {
        self.loader=loader;self.files=files;self.limits=limits;self.completion=completion
    }
    func start(){advance()}
    func cancel(){
        dispatchPrecondition(condition:.onQueue(.main));lock.lock();cancelled=true;lock.unlock()
        if let request{loader.cancel(request)}
    }
    private func finish(_ result:Result<NativeRenderWarePedModel.Plan,Error>) {
        dispatchPrecondition(condition:.onQueue(.main));guard !finished else{return};finished=true;request=nil
        completion(isCancelled ? .failure(Loader.Failure.cancelled):result)
    }
    private func advance() {
        dispatchPrecondition(condition:.onQueue(.main))
        guard !isCancelled else{finish(.failure(Loader.Failure.cancelled));return}
        guard next<files.count else{finish(.failure(Loader.Failure.noGeometry));return}
        let index=next
        request=loader.loadFile(files[index]){[weak self] result in
            guard let self,!self.finished else{return};self.request=nil
            guard !self.isCancelled else{self.finish(.failure(Loader.Failure.cancelled));return}
            do {
                let data=try result.get().data
                Self.cpu.async {
                    let parsed:Result<NativeRenderWarePedModel.Plan?,Error>=Result {
                        guard !self.isCancelled else{throw Loader.Failure.cancelled}
                        try self.consume(data,index:index)
                        guard !self.isCancelled else{throw Loader.Failure.cancelled}
                        return index+1==self.files.count ? try self.prepare():nil
                    }
                    DispatchQueue.main.async {
                        guard !self.finished else{return}
                        do {
                            guard !self.isCancelled else{throw Loader.Failure.cancelled}
                            if let plan=try parsed.get(){self.finish(.success(plan))}
                            else{self.next+=1;self.advance()}
                        }catch{self.finish(.failure(error))}
                    }
                }
            }catch{self.finish(.failure(error))}
        }
    }
    private func consume(_ data:Data,index:Int)throws {
        if index==0 {
            var budget=NativeRenderWareDFF.Limits()
            budget.fileBytes=32*1024*1024;budget.totalVertices=limits.vertices;budget.verticesPerGeometry=limits.vertices
            budget.totalTriangles=limits.triangles;budget.trianglesPerGeometry=limits.triangles
            budget.frames=limits.frames;budget.geometries=1;budget.atomics=1;budget.morphTargets=1;budget.materialsPerGeometry=256
            budget.bones=limits.bones
            let value=try NativeRenderWareDFF.decode(data,limits:budget)
            guard value.geometries.first?.skin != nil else{throw Loader.Failure.noGeometry}
            dff=value
        }else{
            var budget=NativeRenderWareTXD.Limits();budget.maximumFileBytes=32*1024*1024
            budget.maximumDecodedBytes=limits.decodedTextureBytes-decodedBytes;budget.maximumTextureCount=limits.textures-decodedCount
            guard budget.maximumDecodedBytes>0,budget.maximumTextureCount>0 else{throw Loader.Failure.preparedLimit}
            let value=try NativeRenderWareTXD.decode(data,limits:budget)
            decodedBytes+=value.decodedByteCount;decodedCount+=value.textures.count
            if index==1{version=value.version;device=value.deviceID}
            for texture in value.textures where names.insert(texture.lookupName).inserted{textures.append(texture)}
        }
    }
    private func prepare()throws->NativeRenderWarePedModel.Plan {
        guard let dff else{throw Loader.Failure.noGeometry}
        let txd=NativeRenderWareTXD.TextureDictionary(version:version,deviceID:device,textures:textures,
            decodedByteCount:textures.reduce(0){$0+$1.mipLevels.reduce(0){$0+($1.rgba8?.count ?? 0)}})
        var rig=NativeRenderWareSkeleton.Limits();rig.vertices=limits.vertices;rig.frames=limits.frames;rig.bones=limits.bones;rig.indices=limits.triangles*3
        var model=NativeRenderWareModel.Limits();model.vertices=limits.vertices;model.indices=limits.triangles*3
        model.meshBytes=limits.preparedBytes;model.textureBytes=limits.preparedBytes
        let plan=try NativeRenderWarePedModel.prepare(dff:dff,txd:txd,rigLimits:rig,modelLimits:model)
        for diagnostic in plan.model.diagnostics {
            if case .omittedMipTail=diagnostic{continue}
            throw Loader.Failure.diagnostic(String(describing:diagnostic))
        }
        let mesh=plan.model.meshByteCount,texture=plan.model.textureByteCount,skin=plan.skeleton.encodedByteCount
        guard mesh<=limits.preparedBytes,texture<=limits.preparedBytes-mesh,skin<=limits.preparedBytes-mesh-texture else{throw Loader.Failure.preparedLimit}
        return plan
    }
}
