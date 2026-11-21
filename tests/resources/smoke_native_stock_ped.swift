// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal

var checks=0
func require(_ value:@autoclosure()->Bool,_ message:String){checks+=1;if !value(){fatalError(message)}}
final class StockPedTests {
    struct OwnerCase:Decodable {let id:Int32,name:String,skeleton:String}
    let out:URL,base:URL,catalog:NativeSAMPStockModels,device:MTLDevice?
    var source="authored-source-1",owner:NativeStockPedLoader?,files:NativeSAMPStockAssetLoader?
    var index=0,callbacks:[String:Int]=[:],latest:NativeStockPedLoader.Prepared?
    var gpuLevels=0,maximumActive=0,maximumPending=0,maximumFiles=0
    var ownerCases:[OwnerCase]=[],ownerIndex=0,ownerGPUBytes=0
    let cases:[(Int32,Bool)]=[(100,true),(101,true),(102,false),(103,false),(104,false),(105,false)]
    init()throws{
        out=URL(fileURLWithPath:CommandLine.arguments[1]);base=URL(string:CommandLine.arguments[2])!
        catalog=try NativeSAMPStockModels.decode(Data(contentsOf:out.appendingPathComponent("manifest.json")))
        device=MTLCreateSystemDefaultDevice()
        ownerCases=try JSONDecoder().decode([OwnerCase].self,from:Data(contentsOf:out.appendingPathComponent("owner-cases.json")))
        if CommandLine.arguments[3]=="required"{require(device != nil,"Required actual Metal device unavailable")}
    }
    func mark(_ label:String){callbacks[label,default:0]+=1;require(callbacks[label]==1,"Duplicate completion: \(label)")}
    func loader(_ url:URL,local:Bool=false,limits:NativeStockPedLoader.Limits = .init())throws->NativeStockPedLoader {
        let file=try NativeSAMPStockAssetLoader(assetBaseURL:url,allowLocalFiles:local);files=file
        return try NativeStockPedLoader(fileLoader:file,sourceIdentity:{[weak self]in self?.source ?? "retired"},limits:limits)
    }
    func next(){do{
        guard index<cases.count else{localAndLimits();return}
        let (id,ready)=cases[index];index+=1
        let loader=try self.loader(base);owner=loader
        let resolution=try catalog.resolve(id:id,assetBaseURL:base)
        let expectedGeneration=loader.generation
        let request=loader.load(resolution){result in
            self.mark("case-\(id)")
            switch result {
            case .success(let value):
                require(ready,"unsupported rig/model published a prepared pedestrian")
                require(value.model.id==id && value.generation==expectedGeneration && loader.isCurrent(value),"Prepared identity/source generation mismatch")
                require(value.plan.skeleton.frames.count==3 && value.plan.skeleton.bones.count==2,"Actual skeletal plan was replaced by static geometry")
                require(value.plan.skeleton.indices.count==6 && !value.plan.model.draws.isEmpty,"Missing real material/rig topology")
                require(value.plan.model.textures.count==1,"Wrong child-first dictionary material selection")
                let texture=value.plan.model.textures[0]
                require(texture.filterAddressing==0x1106,"Original sampler declaration changed")
                require(texture.mipLevels.map{$0.width}==[4,2,1] && texture.mipLevels.map{$0.height}==[2,1,1],"Original texture dimensions/mips were resampled")
                let colors:[[UInt8]]=[[255,0,0,255],[0,255,0,255],[0,0,255,255]]
                for (level,color)in zip(texture.mipLevels,colors){require(Array(level.rgba8!.prefix(4))==color,"Parent texture overrode child pixels or stored mip was replaced")}
                require(value.resourceBytes<=64*1024*1024,"Prepared aggregate bound lost")
                self.latest=value
                if let device=self.device{self.checkUpload(value,device:device)}
            case .failure:
                require(!ready,"Valid authored rig failed verified acquisition/preparation")
            }
            DispatchQueue.main.async{self.next()}
        }
        require(!request.uuidString.isEmpty,"Missing request identity")
    }catch{fatalError("case setup: \(error)")}}
    func checkUpload(_ value:NativeStockPedLoader.Prepared,device:MTLDevice){do{
        let uploaded=try NativeRenderWarePedModel.Uploaded(plan:value.plan,device:device)
        require(uploaded.actor.vertexCount==value.plan.skeleton.vertices.count,"Actual native skeletal actor rejected prepared rig")
        let image=uploaded.resources.textures[0],queue=device.makeCommandQueue()!,command=queue.makeCommandBuffer()!,blit=command.makeBlitCommandEncoder()!
        require(image.width==4 && image.height==2 && image.mipmapLevelCount==3,"Actual native texture changed dimensions or stored mip count")
        var buffers:[MTLBuffer]=[]
        for (level,size)in [(4,2),(2,1),(1,1)].enumerated(){
            let buffer=device.makeBuffer(length:256*size.1,options:.storageModeShared)!
            blit.copy(from:image,sourceSlice:0,sourceLevel:level,sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:size.0,height:size.1,depth:1),to:buffer,destinationOffset:0,destinationBytesPerRow:256,destinationBytesPerImage:256*size.1)
            buffers.append(buffer)
        }
        blit.endEncoding();command.commit();command.waitUntilCompleted();require(command.status == .completed,"GPU mip readback command failed")
        let colors:[[UInt8]]=[[255,0,0,255],[0,255,0,255],[0,0,255,255]]
        for (level,buffer)in buffers.enumerated(){
            let bytes=buffer.contents().assumingMemoryBound(to:UInt8.self),w=max(1,4>>level),h=max(1,2>>level)
            for y in 0..<h {for x in 0..<w {for c in 0..<4{require(bytes[y*256+x*4+c]==colors[level][c],"GPU image pixels differ from authored stored mip")}}}
            gpuLevels+=1
        }
    }catch{fatalError("Actual GPU upload: \(error)")}}
    func localAndLimits(){do{
        let local=try loader(out,local:true);owner=local
        let resolution=try catalog.resolve(id:100,assetBaseURL:out)
        local.load(resolution){result in
            self.mark("local")
            guard case .success(let value)=result else{fatalError("Verified local stock files did not prepare")}
            require(local.isCurrent(value),"Local prepared identity stale")
            self.source="new-resource-binding"
            require(!local.isCurrent(value),"Same-content resource-generation change kept old prepared receipt current")
            require(local.invalidateIfSourceChanged(),"Resource generation did not invalidate loader")
            self.limits()
        }
    }catch{fatalError("local setup: \(error)")}}
    func limits(){do{
        let file=try NativeSAMPStockAssetLoader(assetBaseURL:base)
        let original=try catalog.resolve(id:100,assetBaseURL:base)
        let reversed=NativeSAMPStockModels.Resolution(model:original.model,dff:original.dff,dictionaries:original.dictionaries,textureSearch:Array(original.textureSearch.reversed()))
        var precedenceRejected=false;do{_=try file.pedestrianFiles(reversed)}catch{precedenceRejected=true}
        require(precedenceRejected,"Caller reordered parent dictionary before child")
        for mutation in 0..<5 {
            var limits=NativeStockPedLoader.Limits()
            switch mutation{case 0:limits.pending=0;case 1:limits.vertices=100_000;case 2:limits.bones=65;case 3:limits.frames=513;default:limits.preparedBytes=64*1024*1024+1}
            var rejected=false;do{_=try NativeStockPedLoader(fileLoader:file,sourceIdentity:{"test"},limits:limits)}catch{rejected=true}
            require(rejected,"Invalid pedestrian memory/rig configuration accepted")
        }
        var budget=NativeStockPedLoader.Limits();budget.preparedBytes=1
        owner=try NativeStockPedLoader(fileLoader:file,sourceIdentity:{self.source},limits:budget)
        owner!.load(try catalog.resolve(id:100,assetBaseURL:base)){result in
            self.mark("prepared-budget");if case .success=result{fatalError("Aggregate prepared byte limit bypassed")};self.queueAndReset()
        }
    }catch{fatalError("limit setup: \(error)")}}
    func wait(_ label:String,_ condition:@escaping()->Bool,_ then:@escaping()->Void){
        let deadline=ProcessInfo.processInfo.systemUptime+15
        func poll(){
            maximumActive=max(maximumActive,owner?.activeCount ?? 0);maximumPending=max(maximumPending,owner?.pendingCount ?? 0)
            maximumFiles=max(maximumFiles,files?.activeCount ?? 0)
            require((owner?.activeCount ?? 0)<=1 && (files?.activeCount ?? 0)<=2,"Decode/verification admission exceeded bounded concurrency")
            if condition(){then();return}
            require(ProcessInfo.processInfo.systemUptime<deadline,"Timeout: \(label)")
            DispatchQueue.main.asyncAfter(deadline:.now()+0.01,execute:poll)
        }
        poll()
    }
    func queueAndReset(){do{
        var limits=NativeStockPedLoader.Limits();limits.pending=1
        let loader=try self.loader(base,limits:limits);owner=loader
        let resolution=try catalog.resolve(id:101,assetBaseURL:base),file=files!,fileGeneration=file.generation
        file.loadFile(resolution.dff!){result in
            self.mark("unrelated-file")
            guard case .success(let value)=result else{fatalError("Pedestrian reset cancelled another verified file owner")}
            require(value.generation==fileGeneration,"Shared verifier generation changed")
        }
        loader.load(resolution){result in
            self.mark("active-cancel");if case .success=result{fatalError("Retired active rig published")}
        }
        loader.load(resolution){result in
            self.mark("pending-cancel");if case .success=result{fatalError("Retired pending rig published")}
        }
        loader.load(resolution){result in
            self.mark("pending-limit");if case .success=result{fatalError("Pending admission limit bypassed")}
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.05){
            require(loader.activeCount==1,"Slow authored active request did not exercise cancellation")
            self.source="resource-after-cancel";_=loader.reset()
            require(loader.activeCount==1 && loader.pendingCount==0,"Cancelled active work released admission before finishing")
            require(file.generation==fileGeneration,"Ped reset reset the shared object/file verifier")
            loader.load(try!self.catalog.resolve(id:100,assetBaseURL:self.base)){result in
                self.mark("after-reset")
                guard case .success(let value)=result else{fatalError("Fresh source could not prepare after reset")}
                require(loader.isCurrent(value) && value.sourceIdentity==self.source,"Retired source attributed to new generation")
                self.latest=value
            }
            self.wait("all replacement/cancellation callbacks",{
                ["unrelated-file","active-cancel","pending-cancel","pending-limit","after-reset"].allSatisfy{self.callbacks[$0]==1}
            },self.ownerNext)
        }
    }catch{fatalError("queue setup: \(error)")}}
    func ownerNext(){do{
        guard ownerIndex<ownerCases.count else{finish();return}
        let item=ownerCases[ownerIndex];ownerIndex+=1
        let catalog=try NativeSAMPStockModels.decode(Data(contentsOf:out.appendingPathComponent("owner-manifest.json")))
        let game=URL(string:CommandLine.arguments[4])!,loader=try self.loader(game,local:true);owner=loader
        loader.load(try catalog.resolve(id:item.id,assetBaseURL:game)){result in
            self.mark("original-"+item.name)
            guard case .success(let value)=result else{fatalError("Original model preparation failed for \(item.name): \(result)")}
            require(loader.isCurrent(value) && value.model.model==item.name && value.model.id==item.id,"Original model identity changed")
            require(!value.plan.model.draws.isEmpty && !value.plan.skeleton.bones.isEmpty,"Original model lacks a real skeletal/material plan")
            require(value.resourceBytes<=64*1024*1024,"Original model exceeds prepared-family bound")
            do{try value.plan.skeleton.encodedSKN1().write(to:self.out.appendingPathComponent("owner-"+item.name+".skn.bin"))}catch{fatalError("Private skeleton evidence write: \(error)")}
            if let device=self.device{self.checkOwnerUpload(value,device:device,referenceSkeleton:URL(fileURLWithPath:item.skeleton))}
            self.latest=value;DispatchQueue.main.async{self.ownerNext()}
        }
    }catch{fatalError("Original owner setup: \(error)")}}
    func checkOwnerUpload(_ value:NativeStockPedLoader.Prepared,device:MTLDevice,referenceSkeleton:URL){do{
        guard let expected=NativeSkeletalActor(data:try Data(contentsOf:referenceSkeleton),vertexCount:value.plan.skeleton.vertices.count,device:device)else{
            fatalError("Original prepared-family reference skeleton is invalid")
        }
        let uploaded=try NativeRenderWarePedModel.Uploaded(plan:value.plan,device:device,validateActor:{actor in
            require(actor.matchesRig(expected),"Original full rig/skin order differs from its prepared actor family")
        })
        require(uploaded.actor.vertexCount==value.plan.skeleton.vertices.count,"Original actor GPU skin vertex count mismatch")
        require(uploaded.resources.textures.count==value.plan.model.textures.count,"Original material GPU image count mismatch")
        for (source,image)in zip(value.plan.model.textures,uploaded.resources.textures){
            require(image.width==source.mipLevels[0].width && image.height==source.mipLevels[0].height,"Original image dimensions changed")
            require(image.mipmapLevelCount==source.mipLevels.count,"Original available stored mip count changed")
            let command=device.makeCommandQueue()!.makeCommandBuffer()!,blit=command.makeBlitCommandEncoder()!
            var buffers:[(MTLBuffer,Int)]=[]
            for (index,level)in source.mipLevels.enumerated(){
                let pitch=((level.width*4+255)/256)*256,buffer=device.makeBuffer(length:pitch*level.height,options:.storageModeShared)!
                blit.copy(from:image,sourceSlice:0,sourceLevel:index,sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:level.width,height:level.height,depth:1),to:buffer,destinationOffset:0,destinationBytesPerRow:pitch,destinationBytesPerImage:pitch*level.height)
                buffers.append((buffer,pitch))
            }
            blit.endEncoding();command.commit();command.waitUntilCompleted();require(command.status == .completed,"Original image GPU readback failed")
            for (level,pair)in zip(source.mipLevels,buffers){
                var actual=Data();actual.reserveCapacity(level.width*level.height*4)
                for y in 0..<level.height{actual.append(Data(bytes:pair.0.contents().advanced(by:y*pair.1),count:level.width*4))}
                require(actual==level.rgba8,"Original stored texture pixels changed during native upload")
                ownerGPUBytes+=actual.count;gpuLevels+=1
            }
        }
    }catch{fatalError("Original GPU upload: \(error)")}}
    func finish(){
        require(owner?.activeCount==0 && owner?.pendingCount==0,"Final decode work not drained")
        require(latest.map{owner!.isCurrent($0)}==true,"Final prepared receipt is not current")
        print("PASS stock pedestrian CPU pipeline: \(checks) checks; \(callbacks.count) distinct callbacks; \(gpuLevels) actual GPU stored-mip readbacks; originalModels=\(ownerCases.count) originalGPUBytes=\(ownerGPUBytes); maximum active/pending/file=\(maximumActive)/\(maximumPending)/\(maximumFiles)")
        exit(0)
    }
}
@main struct Main {
    static func main(){DispatchQueue.main.async{do{let tests=try StockPedTests();tests.next()}catch{fatalError("Setup: \(error)")}};dispatchMain()}
}
