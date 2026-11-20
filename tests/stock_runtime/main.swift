// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal
import simd
import CryptoKit

var checks=0
func require(_ value:@autoclosure()->Bool,_ reason:String){checks+=1;if !value(){fatalError(reason)}}
struct View {let colorPixelFormat:MTLPixelFormat = .rgba8Unorm,depthStencilPixelFormat:MTLPixelFormat = .depth32Float}
final class Ground {let world=SwiftRapierWorld()!}
// Only the additional reset boundary is a spy here. The separately compiled
// stock-pedestrian runtime test executes the real resource owner and upload.
final class StockPedResetWitness {var resets=0;func reset(){resets+=1}}
final class HeldDictionaryTask:NativeResourceTask {
    let request:URLRequest,completion:NativeResourceTransport.Completion
    var resumed=false,cancelled=false
    init(_ request:URLRequest,_ completion:@escaping NativeResourceTransport.Completion){self.request=request;self.completion=completion}
    func resume(){resumed=true}
    func cancel(){cancelled=true}
    func reply(_ data:Data){completion(data,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:"HTTP/1.1",headerFields:nil),nil)}
}
final class Carrier {
    let device:MTLDevice,view=View(),groundVehicle:Ground?=Ground()
    let pipeline:MTLRenderPipelineState,depth:MTLDepthStencilState
    var server:ServerAddress?,gameHour=12.0
    var resourceGeneration=0
    var stockPedRuntime:StockPedResetWitness?,stockPedIDs:[String:Int32]=[:],stockPedCatalogueSHA:String?,stockPedErrors=Set<Int32>(),stockPedDrawn=Set<Int32>()
    func fixedCJSourceIdentity()->String { (server?.display ?? "none")+"|generation:\(resourceGeneration)" }
    var statuses:[String]=[]
    var onStatus:((String)->Void)?
    // ACTUAL_PROPERTIES
    init(device:MTLDevice,library:MTLLibrary,server:ServerAddress)throws {
        self.device=device;self.server=server
        let pipelines=try NativeRenderWareModel.Pipelines(device:device,library:library,color:view.colorPixelFormat,depth:view.depthStencilPixelFormat)
        pipeline=pipelines.opaque;depth=pipelines.opaqueDepth;legacyModelPipelines=pipelines
        onStatus={[weak self] message in self?.statuses.append(message)}
    }
    // External vehicle/player parent lookup is outside this carrier. Object
    // storage, movement interpolation, object-parent hierarchy and transforms
    // below are the actual production implementations.
    func legacyObjectSnapshot(at timestamp:Double)->NativeSAMPObjectScene.Snapshot? {
        guard let objects=try?legacyObjects.sampledInstances(at:timestamp)else{return nil}
        return NativeSAMPObjectScene.resolve(objects){_ in nil}
    }
    // ACTUAL_METHODS
}
// ACTUAL_METADATA_TRANSFER

final class Tests {
    let base:URL,otherBase:URL,modelsBase:URL,out:URL,device:MTLDevice,library:MTLLibrary,carrier:Carrier
    var gatedCarrier:Carrier?,testCookies:[HTTPCookie]=[],gatedComplete=false,modelsOnlyComplete=false
    var metadataIndex=0,metadataTransfer:LegacyStockMetadataTransfer?,maximumWholeLoads=0,maximumLoaderActive=0
    var heldDictionaries:[HeldDictionaryTask]=[],sourcePhases:[String]=[]
    var objects:[UInt16:NativeSAMPObjects.Instance]=[:],gpuRows:[[String:Any]]=[]
    let metadataCases:[(String,String)]=[("valid","ok"),("length","limit"),("chunked","limit"),("encoding","encoding"),("redirect","redirect"),("http","http"),("slow","cancelled")]
    init(device:MTLDevice,library:MTLLibrary)throws {
        base=URL(string:CommandLine.arguments[1])!;out=URL(fileURLWithPath:CommandLine.arguments[3]);self.device=device;self.library=library
        otherBase=URL(string:CommandLine.arguments[4])!
        modelsBase=URL(string:CommandLine.arguments[5])!
        carrier=try Carrier(device:device,library:library,server:ServerAddress(base.absoluteString)!)
    }
    func wait(_ label:String,timeout:Double=30,condition:@escaping()->Bool,then:@escaping()->Void) {
        let deadline=ProcessInfo.processInfo.systemUptime+timeout
        func poll(){
            maximumWholeLoads=max(maximumWholeLoads,carrier.legacyStockLoads.count)
            maximumLoaderActive=max(maximumLoaderActive,carrier.legacyStockLoader?.activeCount ?? 0)
            require(carrier.legacyStockLoads.count<=2,"whole model pipeline concurrency exceeded two")
            if condition(){then();return}
            require(ProcessInfo.processInfo.systemUptime<deadline,"timed out: \(label); \(carrier.statuses)")
            DispatchQueue.main.asyncAfter(deadline:.now()+0.01,execute:poll)
        }
        poll()
    }
    func metadataNext(){
        guard metadataIndex<metadataCases.count else{beginObjects();return}
        let (name,expected)=metadataCases[metadataIndex];metadataIndex+=1
        let transfer=LegacyStockMetadataTransfer(url:base.appendingPathComponent("metadata/"+name),maximumBytes:64){ result in
            switch result {
            case .success(let data):require(expected=="ok" && String(data:data,encoding:.utf8)=="0123456789abcdef","metadata exact bounded bytes")
            case .failure(let error):
                guard let error=error as?NativeSAMPStockAssetLoader.Failure else{fatalError("metadata unexpected error: \(error)")}
                let actual:String
                switch error {case .limit:actual="limit";case .encoding:actual="encoding";case .redirect:actual="redirect";case .http:actual="http";case .cancelled:actual="cancelled";default:actual="other"}
                require(actual==expected,"metadata \(name) expected\(expected) got\(actual)")
            }
            DispatchQueue.main.async{self.metadataNext()}
        }
        metadataTransfer=transfer;transfer.start();if expected=="cancelled"{transfer.cancel()}
    }
    func add(_ id:UInt16,_ model:Int32,_ x:Float)throws {
        let object=NativeSAMPObjects.Instance(id:id,model:model,position:SIMD3(x,0,20),rotation:SIMD3(12,-17,23),drawDistance:100_000,cameraCollision:id != 3,attachment:nil,materials:[:])
        objects[id]=object;try carrier.receiveLegacyObject(.create(object))
    }
    func beginObjects(){do {
        for (id,model,x):(UInt16,Int32,Float)in [(1,966,0),(2,980,30),(3,1225,60),(4,1231,90),(10,1000,150),(11,1001,180),(12,1002,210),(13,1003,240),(15,1005,270)] {try add(id,model,x)}
        wait("actual HTTP->DFF/TXD/COL->GPU publication",condition:{
            Set([966,980,1225,1231,1000,1001,1005]).isSubset(of:self.carrier.legacyStockModels) &&
            self.carrier.legacyStockLoads.isEmpty && self.carrier.legacyStockRetries[1002] != nil && self.carrier.legacyStockRetries[1003] != nil
        },then:physicalAndGPU)
    }catch{fatalError("begin objects: \(error)")}}
    func physicalAndGPU(){do {
        let physical:[UInt16]=[1,2,3,4,10]
        for id in physical {require(!carrier.legacyStockObjectReady(objects[id]!),"authored COL was called ready before actual native registration")}
        require(carrier.legacyStockObjectReady(objects[11]!) && carrier.legacyStockCollisionProvenance(for:1001)=="inventoryAbsent","complete-inventory no-COL art remained invisible or invented a body")
        require(carrier.legacyStockObjectReady(objects[15]!) && carrier.legacyStockCollisionProvenance(for:1005)=="authoredEmpty","explicit empty COL classification")
        require(carrier.legacyModels[1002]==nil && carrier.legacyModels[1003]==nil,"incomplete metadata or bad COL integrity published renderable resources")
        carrier.synchronizeLegacyObjectPhysics(at:ProcessInfo.processInfo.systemUptime)
        require(carrier.groundVehicle!.world.step(),"native world step")
        require(carrier.legacyCollisionWorld!.colliderCount==14,"four exact retail props + generated authored shape count")
        for id in physical {
            require(carrier.legacyStockObjectReady(objects[id]!),"actual native COL handles did not release visibility barrier")
            require(carrier.legacyStockCollisionProvenance(for:objects[id]!.model)=="authored","authored COL provenance lost")
        }
        require(carrier.legacyCollisionHandles[11]==nil && carrier.legacyCollisionHandles[15]==nil,"noncolliding art received a guessed shape")
        let snapshot=carrier.legacyObjectSnapshot(at:ProcessInfo.processInfo.systemUptime)!
        var contacts=0
        for draw in snapshot.draws where physical.contains(draw.object.id) {
            let model=carrier.legacyCollisionModels[draw.object.model]!.first!,handle=carrier.legacyCollisionHandles[draw.object.id]!.first!
            let ids=carrier.legacyCollisionWorld!.colliderIDs(for:handle)!
            let centers=model.spheres.map{$0.center}+model.boxes.map{($0.minimum+$0.maximum)*0.5}
            let surfaces=model.spheres.map{$0.surface}+model.boxes.map{$0.surface}
            for (index,center)in centers.enumerated(){
                let p=draw.transform*SIMD4(center,1),point=SIMD3(p.x,p.y,p.z)
                let probe=carrier.groundVehicle!.world.addSphere(radius:0.01,position:SwiftRapierWorld.gtaToRapier(point))!
                require((carrier.groundVehicle!.world.contact(probe,ids[index],prediction:0.01)?.distance ?? 1)<0,"actual full-basis stock volume contact")
                require(carrier.legacyCollisionWorld!.metadata(collider:ids[index])?.surface?.material==surfaces[index].material,"actual authored material tag")
                _=carrier.groundVehicle!.world.removeCollider(probe);contacts+=1
            }
        }
        require(contacts==13,"all actual sphere/box primitives contacted")
        for id:UInt16 in [1,2,3,4,10,11,15]{try render(id)}
        let original=objects[3]!
        try carrier.receiveLegacyObject(.move(3,from:original.position,to:original.position+SIMD3(3,0,0),speed:1,rotation:SIMD3(15,0,60)))
        let timestamp=ProcessInfo.processInfo.systemUptime+0.25
        carrier.synchronizeLegacyObjectPhysics(at:timestamp);require(carrier.groundVehicle!.world.step(),"actual moved stock body step")
        let sampled=carrier.legacyObjectSnapshot(at:timestamp)!.draws.first{$0.object.id==3}!
        let entity=carrier.legacyCollisionHandles[3]!.first!.entityID,motion=carrier.legacyCollisionWorld!.motion(entityID:entity)!
        require(simd_distance(motion.transform.position,SIMD3(sampled.transform[3].x,sampled.transform[3].y,sampled.transform[3].z))<0.0001,"actual object interpolation and native body disagree")
        require(motion.linearVelocity.x>0,"moving authored stock body has native support velocity")
        budgetAndStale()
    }catch{fatalError("physical/render callbacks: \(error)")}}
    func render(_ id:UInt16,owner:Carrier?=nil)throws {
        let current=owner ?? carrier,object=objects[id]!,gpu=current.legacyModels[object.model]!
        let transform=NativeSAMPObjectScene.transform(position:object.position,degrees:object.rotation)
        var low=SIMD3<Float>(repeating:.infinity),high=SIMD3<Float>(repeating:-.infinity)
        for instance in gpu.plan.instances {for vertex in gpu.plan.geometries[instance.geometry].vertices {
            let local=SIMD4<Float>(vertex.position,1)
            let framed=instance.frameTransform*local
            let p=transform*framed,v=SIMD3(p.x,p.y,p.z)
            low=simd_min(low,v);high=simd_max(high,v)
        }}
        let c=(low+high)*0.5,s=1.7/max(0.01,max(high.x-low.x,high.z-low.z)),d=0.8/max(1,high.y-low.y)
        let matrix=simd_float4x4(columns:(SIMD4(s,0,0,0),SIMD4(0,0,d,0),SIMD4(0,s,0,0),SIMD4(-c.x*s,-c.z*s,0.5-c.y*d,1)))
        let colorDesc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:128,height:128,mipmapped:false)
        colorDesc.storageMode = .shared;colorDesc.usage=[.renderTarget,.shaderRead]
        let depthDesc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:128,height:128,mipmapped:false)
        depthDesc.storageMode = .private;depthDesc.usage = .renderTarget
        let color=device.makeTexture(descriptor:colorDesc)!,depth=device.makeTexture(descriptor:depthDesc)!
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=color;pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store;pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
        pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
        let queue=device.makeCommandQueue()!,command=queue.makeCommandBuffer()!,encoder=command.makeRenderCommandEncoder(descriptor:pass)!
        encoder.setViewport(MTLViewport(originX:0,originY:0,width:128,height:128,znear:0,zfar:1))
        current.drawLegacyObjects(encoder:encoder,matrix:matrix,eye:object.position+SIMD3(0,-20,10))
        encoder.endEncoding()
        let readback=device.makeBuffer(length:512*128,options:.storageModeShared)!,blit=command.makeBlitCommandEncoder()!
        blit.copy(from:color,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:128,height:128,depth:1),
                  to:readback,destinationOffset:0,destinationBytesPerRow:512,destinationBytesPerImage:512*128)
        blit.endEncoding();command.commit();command.waitUntilCompleted()
        require(command.status == .completed,"actual Renderer stock Metal encode")
        let pixels=Array(UnsafeBufferPointer(start:readback.contents().assumingMemoryBound(to:UInt8.self),count:128*128*4))
        let visible=stride(from:3,to:pixels.count,by:4).filter{pixels[$0]>0}.count
        if visible<=8 {
            let diagnostic:[String:Any]=["model":object.model,"low":[low.x,low.y,low.z],"high":[high.x,high.y,high.z],
                "clipColumns":(0..<4).map{[matrix[$0].x,matrix[$0].y,matrix[$0].z,matrix[$0].w]},
                "ready":current.legacyStockObjectReady(object),"statuses":current.statuses,
                "alphaNonzero":visible,"rgbNonzero":stride(from:0,to:pixels.count,by:4).filter{pixels[$0]>0 || pixels[$0+1]>0 || pixels[$0+2]>0}.count]
            try JSONSerialization.data(withJSONObject:diagnostic,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("failed-render-diagnostic.json"))
            try Data(pixels).write(to:out.appendingPathComponent("failed-render.rgba"))
        }
        require(visible>8,"actual Renderer model \(object.model) produced no visible fragments")
        gpuRows.append(["model":object.model,"gated":owner != nil,"visiblePixels":visible,"pixelSHA256":SHA256.hash(data:Data(pixels)).map{String(format:"%02x",$0)}.joined()])
    }
    func budgetAndStale(){do {
        let cache=carrier.legacyStockModels,actualBytes=carrier.legacyModelBytes
        let references=carrier.legacyStockReferences,activeExtra=Set((14000..<14130).map(Int32.init))
        carrier.legacyStockModels.formUnion(activeExtra);carrier.legacyStockReferences.formUnion(activeExtra)
        try carrier.reserveLegacyModelBytes(0,replacing:19000)
        require(activeExtra.isSubset(of:carrier.legacyStockModels),"cache slot trimming rejected referenced models despite available shared byte budget")
        carrier.legacyStockModels=cache;carrier.legacyStockReferences=references
        let dictionary=carrier.legacyStockCatalog!.model(966)!.txd,texture=carrier.legacyModels[966]!.plan.textures.first!.lookupName
        let textureKey=NativeSAMPObjectMaterials.TextureRequest(model:966,dictionary:dictionary,texture:texture)
        let actualCRC=carrier.legacyTextureSources[textureKey]!
        carrier.legacyModelCosts[-1000]=192*1024*1024-actualBytes-100;carrier.legacyModelBytes=192*1024*1024-100
        var rejected=false;do{try carrier.reserveLegacyModelBytes(1000,replacing:19000)}catch{rejected=true}
        require(rejected && carrier.legacyStockModels==cache,"budget pressure evicted referenced resources")
        let oldIDs=carrier.legacyCollisionHandles[1]!.flatMap{carrier.legacyCollisionWorld!.colliderIDs(for:$0)!}
        try carrier.receiveLegacyObject(.destroy(1));objects.removeValue(forKey:1)
        try carrier.reserveLegacyModelBytes(1000,replacing:19000)
        require(!carrier.legacyStockModels.contains(966) && carrier.legacyModels[966]==nil,"unreferenced stock cache was not evicted under shared budget")
        require(oldIDs.allSatisfy{carrier.groundVehicle!.world.colliderInfo($0)==nil},"destroy retained actual native stock bodies")
        require(Set([980,1225,1231]).isSubset(of:carrier.legacyStockModels),"unrelated referenced retail model evicted")
        carrier.legacyModelCosts.removeValue(forKey:-1000);carrier.legacyModelBytes=carrier.legacyModelCosts.values.reduce(0,+)
        carrier.legacyTextureSources[textureKey]=actualCRC ^ 0xffffffff
        try add(1,966,0)
        wait("stock reload with conflicting existing texture namespace",condition:{self.carrier.legacyStockModels.contains(966)},then:{
            require(self.carrier.legacyTextureConflicts.contains(textureKey) && self.carrier.legacyExactTextures[textureKey]==nil,"stock reload guessed between conflicting custom/stock texture sources")
            self.beginStale()
        })
    }catch{fatalError("budget: \(error)")}}
    func beginStale(){do {
        try add(20,1004,330)
        let epoch=carrier.legacyAssetEpoch
        DispatchQueue.main.asyncAfter(deadline:.now()+0.02){
            self.carrier.invalidateLegacyImports()
            require(self.carrier.legacyAssetEpoch != epoch,"actual invalidation did not advance epoch")
            DispatchQueue.main.asyncAfter(deadline:.now()+0.6){
                require(self.carrier.legacyModels[1004]==nil && !self.carrier.legacyStockModels.contains(1004),"stale verified download published after actual epoch reset")
                try!self.carrier.receiveLegacyObject(.destroy(20));self.objects.removeValue(forKey:20)
                self.cancelUnreferenced()
            }
        }
    }catch{fatalError("stale: \(error)")}}
    func cancelUnreferenced(){do {
        try add(21,1004,360)
        DispatchQueue.main.asyncAfter(deadline:.now()+0.02){
            try!self.carrier.receiveLegacyObject(.destroy(21));self.objects.removeValue(forKey:21)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.7){
                require(self.carrier.legacyModels[1004]==nil && self.carrier.legacyStockLoads[1004]==nil,"unreferenced cancelled model published old resources")
                for value in 0..<100 {try!self.add(UInt16(100+value),Int32(18000+value),Float(1000+value))}
                require((18000..<18100).allSatisfy{self.carrier.legacyStockRetries[Int32($0)] != nil},"unknown model names were guessed or recursively blocked queue progress")
                self.wait("baseline load cleanup",condition:{self.carrier.legacyStockLoads.isEmpty},then:self.beginSourceTransitions)
            }
        }
    }catch{fatalError("cancel: \(error)")}}
    func beginSourceTransitions(){
        guard // SOURCE_TRANSITION_ENABLED
        else{afterSourcePhases();return}
        do {
            let gpu=carrier.legacyModels[980]!,bytes=carrier.legacyModelCosts[980]!
            carrier.legacyModels[20001]=gpu;carrier.legacyModelCosts[20001]=bytes;carrier.legacyModelBytes+=bytes
            // ARTWORK_BINDING_WITNESS
            let nativeIDs=carrier.legacyCollisionHandles.values.flatMap{$0}.flatMap{carrier.legacyCollisionWorld!.colliderIDs(for:$0)!}
            require(!nativeIDs.isEmpty,"source switch must exercise registered physical objects")
            let oldObjectCount=try carrier.legacyObjects.sampledInstances(at:ProcessInfo.processInfo.systemUptime).count
            let second=ServerAddress(otherBase.absoluteString)!
            carrier.server=second;carrier.refreshLegacyStockReferences()
            require(carrier.legacyStockModels.isEmpty && carrier.legacyModels[980]==nil,"source change retained old stock GPU registration")
            require(carrier.legacyModels[20001] === gpu && carrier.legacyModelCosts[20001]==bytes,"stock source retirement erased independent artwork")
            // ARTWORK_BINDING_RETAINED
            require(nativeIDs.allSatisfy{carrier.groundVehicle!.world.colliderInfo($0)==nil},"source change retained old physical stock collision")
            let retainedObjectCount=try carrier.legacyObjects.sampledInstances(at:ProcessInfo.processInfo.systemUptime).count
            require(retainedObjectCount==oldObjectCount,"asset source retirement erased authoritative object state")
            wait("actual second-origin metadata and model load",condition:{
                self.carrier.legacyStockModels.contains(980) && self.carrier.legacyStockLoads.isEmpty && self.carrier.legacyStockMetadataPending==0
            },then:{
                require(self.carrier.legacyStockLoader != nil,"new source did not create its own loader")
                self.carrier.synchronizeLegacyObjectPhysics(at:ProcessInfo.processInfo.systemUptime)
                require(self.carrier.groundVehicle!.world.step(),"new source physical step")
                require(self.carrier.legacyStockObjectReady(self.objects[2]!),"new source model did not regain authored collision readiness")
                self.sourcePhases.append("origin-change-with-registered-physics")
                self.beginResourceRepair()
            })
        }catch{fatalError("source changes: \(error)")}
    }
    func beginResourceRepair(){
        let loader=carrier.legacyStockLoader,gpu=carrier.legacyModels[980]!
        let digest=carrier.legacyStockManifestSHA256
        carrier.synchronizeLegacyStockSource()
        require(carrier.legacyStockLoader === loader && carrier.legacyModels[980] === gpu,"same source unnecessarily retired ready resources")
        carrier.legacyStockMetadataRetryAfter=ProcessInfo.processInfo.systemUptime+300
        carrier.resourceGeneration+=1;carrier.refreshLegacyStockReferences()
        require(carrier.legacyStockModels.isEmpty && carrier.legacyStockModels.count==0,"same-URL resource repair retained old stock generation")
        require(carrier.legacyStockMetadataRetryAfter==0,"new resource generation inherited old retry suppression")
        wait("same URL new resource generation",condition:{
            self.carrier.legacyStockModels.contains(980) && self.carrier.legacyStockLoads.isEmpty && self.carrier.legacyStockMetadataPending==0
        },then:{
            require(self.carrier.legacyStockLoader !== loader && self.carrier.legacyModels[980] !== gpu,"repair reused obsolete loader/GPU owner")
            require(self.carrier.legacyStockManifestSHA256==digest,"same-content repair fixture unexpectedly changed metadata")
            require(self.carrier.legacyModels[20001] != nil,"same-content repair erased independent custom resource")
            self.sourcePhases.append("same-URL-same-content-new-resource-generation")
            self.beginPendingSourceMetadata()
        })
    }
    func beginPendingSourceMetadata(){
        carrier.legacyImportQueue.suspend()
        carrier.resourceGeneration+=1;carrier.refreshLegacyStockReferences()
        wait("first bootstrap received but CPU parsing held",condition:{
            self.carrier.legacyStockMetadataTasks.isEmpty && self.carrier.legacyStockMetadataPending==2
        },then:{
            let oldEpoch=self.carrier.legacyStockMetadataEpoch
            self.carrier.resourceGeneration+=1;self.carrier.refreshLegacyStockReferences()
            require(self.carrier.legacyStockMetadataEpoch != oldEpoch && self.carrier.legacyStockMetadataPending==2,"new bootstrap did not replace the pending owner")
            self.carrier.legacyImportQueue.resume()
            self.wait("old bootstrap callbacks ignored and new bootstrap completed",condition:{
                require((0...2).contains(self.carrier.legacyStockMetadataPending),"retired metadata decremented the new pending count")
                return self.carrier.legacyStockMetadataPending==0 && self.carrier.legacyStockModels.contains(980) && self.carrier.legacyStockLoads.isEmpty
            },then:{self.sourcePhases.append("retired-bootstrap-CPU-completion");self.beginReentrantSource()})
        })
    }
    func beginReentrantSource(){
        let originalStatus=carrier.onStatus
        var fired=false
        carrier.onStatus={message in
            originalStatus?(message)
            if !fired && message.hasPrefix("STOCK OBJECT 1 UNAVAILABLE:") {
                fired=true;self.carrier.server=ServerAddress(self.base.absoluteString)!
                self.carrier.synchronizeLegacyStockSource()
            }
        }
        carrier.legacyStockReferences=[1,1006];carrier.pumpLegacyStockObjects()
        require(fired,"reentrant source witness did not execute")
        require(carrier.legacyStockLoads.isEmpty,"reentrant source change queued a model from captured old catalogue")
        carrier.onStatus=originalStatus;carrier.refreshLegacyStockReferences()
        wait("post-reentrant source bootstrap",condition:{
            self.carrier.legacyStockModels.contains(980) && self.carrier.legacyStockLoads.isEmpty
        },then:{self.sourcePhases.append("reentrant-status-source-switch");self.beginLateDictionary()})
    }
    func beginLateDictionary(){
        NativeResourceTransport.install({request,completion in
            let task=HeldDictionaryTask(request,completion);self.heldDictionaries.append(task);return task
        },bounded:{request,maximum,completion in
            require(maximum==64*1024*1024,"raw dictionary transfer lost its pre-append byte cap")
            let task=HeldDictionaryTask(request,completion);self.heldDictionaries.append(task);return task
        })
        let key=NativeSAMPObjectMaterials.TextureRequest(model:19000,dictionary:"source_check",texture:"session_texture")
        carrier.loadLegacyDictionary(key)
        require(heldDictionaries.count==1 && heldDictionaries[0].resumed,"old dictionary request not admitted")
        // STOCK_PED_RETIREMENT_WITNESS
        carrier.resourceGeneration+=1;carrier.synchronizeLegacyStockSource()
        // STOCK_PED_RETIREMENT_RETIRED
        require(heldDictionaries[0].cancelled,"source change did not cancel its raw dictionary transfer")
        carrier.loadLegacyDictionary(key)
        require(heldDictionaries.count==2 && heldDictionaries[1].resumed && carrier.legacyTextureLoads.contains(key),"new dictionary request did not replace cancelled work")
        let payload=try!Data(contentsOf:out.appendingPathComponent("source-check.txd"))
        DispatchQueue.global(qos:.utility).async {
            self.heldDictionaries[0].reply(payload)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.08){
                require(self.carrier.legacyExactTextures[key]==nil && self.carrier.legacyTextureLoads.contains(key),"old dictionary callback published or erased a new load")
                self.heldDictionaries[1].reply(payload)
                self.wait("new dictionary verified decoder and actual Metal upload",condition:{!self.carrier.legacyTextureLoads.contains(key)},then:{
                    require(self.carrier.legacyExactTextures[key]?.image.width==2,"current dictionary did not decode/upload its authored texture")
                    require(self.carrier.legacyTextureRetries[key]==nil,"old callback poisoned the new retry policy")
                    NativeResourceTransport.install({URLSession.shared.dataTask(with:$0,completionHandler:$1)},bounded:{NativeBoundedResourceTask(request:$0,maximumBytes:$1,completion:$2)})
                    self.sourcePhases.append("cancelled-raw-dictionary-cannot-publish-or-retire-new-request")
                    self.afterSourcePhases()
                })
            }
        }
    }
    func afterSourcePhases(){
        let requested:Bool = // MODELS_ONLY_ENABLED
        if requested{beginModelsOnly()}else{beginGate()}
    }
    func beginModelsOnly(){do {
        let url=modelsBase
        let partial=try Carrier(device:device,library:library,server:ServerAddress(url.absoluteString)!)
        let object=NativeSAMPObjects.Instance(id:600,model:966,position:SIMD3(0,0,20),rotation:.zero,drawDistance:100_000,cameraCollision:true,attachment:nil,materials:[:])
        try partial.receiveLegacyObject(.create(object))
        wait("models-only actual metadata bootstrap",condition:{partial.legacyStockMetadataPending==0 && partial.legacyStockMetadataTasks.isEmpty},then:{
            require(partial.legacyStockCatalog != nil && partial.legacyStockCollisionCatalog==nil,"models-only fixture did not separate valid model/missing collision metadata")
            guard let loader=partial.legacyStockLoader,let catalog=partial.legacyStockCatalog else{fatalError("valid model metadata did not expose shared verified file acquisition")}
            require(partial.legacyStockReferences.contains(966) && partial.legacyStockLoads.isEmpty && partial.legacyStockModels.isEmpty,"static model published without required collision catalogue")
            do {
                let resolution=try catalog.resolve(id:966,assetBaseURL:url)
                guard let file=resolution.dff else{fatalError("model-only original DFF unavailable")}
                _=loader.loadFile(file){result in do {
                    let verified=try result.get()
                    require(verified.data.count==file.metadata.bytes,"models-only shared verifier lost exact original bytes")
                    partial.pumpLegacyStockObjects()
                    require(partial.legacyStockModels.isEmpty && partial.legacyModels.isEmpty && partial.legacyCollisionWorld!.colliderCount==0,"shared acquisition bypassed static render/physics publication barrier")
                    self.modelsOnlyComplete=true;self.sourcePhases.append("models-only-shared-acquisition-with-static-publication-blocked")
                    self.beginGate()
                }catch{fatalError("models-only verified file acquisition: \(error)")}}
            }catch{fatalError("models-only resolution: \(error)")}
        })
    }catch{fatalError("models-only actual carrier: \(error)")}}
    func beginGate(){
        var request=URLRequest(url:base.appendingPathComponent("control/gate"));request.httpShouldHandleCookies=false
        URLSession.shared.dataTask(with:request){_,response,error in
            DispatchQueue.main.async {
                require(error==nil && (response as?HTTPURLResponse)?.statusCode==200,"enable actual fixture HTTP gate")
                do {
                    let denied=try Carrier(device:self.device,library:self.library,server:ServerAddress(self.base.absoluteString)!)
                    denied.loadLegacyStockCatalogs()
                    self.wait("unauthenticated gated bootstrap",condition:{denied.legacyStockMetadataPending==0 && denied.legacyStockMetadataTasks.isEmpty},then:{
                        require(denied.legacyStockCatalog==nil && denied.legacyStockCollisionCatalog==nil && denied.legacyStockLoader==nil,"missing LAN access bypassed real metadata HTTP gate")
                        self.authorizedGate()
                    })
                }catch{fatalError("denied carrier: \(error)")}
            }
        }.resume()
    }
    func authorizedGate(){do {
        let names=Set(["zgta_access","zgta_local","discord_session","unrelated"])
        let existing=HTTPCookieStorage.shared.cookies(for:base) ?? []
        require(!existing.contains{names.contains($0.name) && $0.domain==base.host && $0.path=="/"},"test refuses to replace an existing app cookie namespace")
        for name in names {
            let cookie=HTTPCookie(properties:[.name:name,.value:name=="zgta_access" ? String(repeating:"a",count:64):"must-never-forward",
                .domain:base.host!,.path:"/",.originURL:base.absoluteString,.expires:Date(timeIntervalSinceNow:120)])!
            testCookies.append(cookie);HTTPCookieStorage.shared.setCookie(cookie)
        }
        let gated=try Carrier(device:device,library:library,server:ServerAddress(base.absoluteString)!);gatedCarrier=gated
        for (id,model,x):(UInt16,Int32,Float)in [(501,966,0),(502,980,30),(503,1225,60),(504,1231,90)] {
            let object=NativeSAMPObjects.Instance(id:id,model:model,position:SIMD3(x,0,20),rotation:SIMD3(12,-17,23),drawDistance:100_000,cameraCollision:true,attachment:nil,materials:[:])
            objects[id]=object;try gated.receiveLegacyObject(.create(object))
        }
        wait("authorized metadata/models/COL actual HTTP gate",condition:{
            require(gated.legacyStockLoads.count<=2,"gated whole-pipeline concurrency")
            return Set([966,980,1225,1231]).isSubset(of:gated.legacyStockModels) && gated.legacyStockLoads.isEmpty
        },then:{
            gated.synchronizeLegacyObjectPhysics(at:ProcessInfo.processInfo.systemUptime)
            require(gated.groundVehicle!.world.step() && gated.legacyCollisionWorld!.colliderCount==11,"gated actual four-model COL registration")
            for id:UInt16 in [501,502,503,504] {
                require(gated.legacyStockObjectReady(self.objects[id]!),"gated physical publication barrier")
                do{try self.render(id,owner:gated)}catch{fatalError("gated render: \(error)")}
            }
            for cookie in self.testCookies{HTTPCookieStorage.shared.deleteCookie(cookie)};self.testCookies=[]
            self.gatedComplete=true;self.finish()
        })
    }catch{fatalError("authorized carrier: \(error)")}}
    func finish(){do {
        let report:[String:Any]=["passed":true,"checks":checks,"metalDevice":device.name,"gpuReadbacks":gpuRows,
            "sourceTransitions":sourcePhases,
            "gatedRBootstrapAndFourRetailModels":gatedComplete,
            "modelsOnlySharedAcquisition":modelsOnlyComplete,
            "readback":"explicit texture-to-shared-buffer GPU blit, 256-byte-aligned rows",
            "maximumWholeModelLoads":maximumWholeLoads,"maximumVerifiedLoaderActive":maximumLoaderActive,
            "limits":["Actual extracted Renderer methods with real HTTP decoder, Metal and Rapier; carrier supplies device/view formats and no external attachment parents",
                      "Native physics callback invoked explicitly; no UIKit, display-link or SA-MP server session claim",
                      "192MiB pressure and >128 active reference policy use controlled accounting entries, without dummy GPU allocations",
                      "Gated pass uses this test process's own short-lived cookie store; existing cookie namespaces are never replaced"]]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("report.json"))
        print("PASS stock Renderer runtime: \(checks) checks, \(gpuRows.count) real Metal readbacks")
        exit(0)
    }catch{fatalError("report: \(error)")}}
}
guard let device=MTLCreateSystemDefaultDevice()else{fputs("Physical Metal device unavailable in this sandbox\n",stderr);exit(77)}
let library=try device.makeLibrary(source:String(contentsOfFile:CommandLine.arguments[2],encoding:.utf8),options:nil)
let tests=try Tests(device:device,library:library)
tests.metadataNext();dispatchMain()
