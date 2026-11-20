// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal

private var checks=0
private func require(_ value:@autoclosure()->Bool,_ message:String){checks+=1;if !value(){fatalError(message)}}
private enum TestFailure:Error {case timeout,unexpected}
private final class CountedResource {let id:Int32;init(_ id:Int32){self.id=id}}

@MainActor private func wait<R:AnyObject>(_ owner:NativeStockPedRuntime<R>,ids:Set<Int32>,failure:Bool=false,start:()->Void)async throws {
    try await withCheckedThrowingContinuation{(c:CheckedContinuation<Void,Error>)in
        var finished=false,seen=Set<Int32>()
        owner.onReady={value in
            guard !finished else{return}
            guard !failure,ids.contains(value.model.id),seen.insert(value.model.id).inserted else{finished=true;c.resume(throwing:TestFailure.unexpected);return}
            if seen==ids{finished=true;c.resume()}
        }
        owner.onUnavailable={id,error in
            guard !finished else{return};finished=true
            if failure && ids.contains(id){c.resume()}else{c.resume(throwing:error)}
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+8){if !finished{finished=true;c.resume(throwing:TestFailure.timeout)}}
        start()
    }
}

@main struct Main {
 @MainActor static func main()async throws {
    let out=URL(fileURLWithPath:CommandLine.arguments[1]),base=out.appendingPathComponent("fixture",isDirectory:true)
    let catalog=try NativeSAMPStockModels.decode(Data(contentsOf:out.appendingPathComponent("manifest.json")))
    let resolutions=try [100,101,102].map{try catalog.resolve(id:Int32($0),assetBaseURL:base)}
    var source="source-A",now=10.0,uploads=0,retired:[Int32]=[]
    let files=try NativeSAMPStockAssetLoader(assetBaseURL:base,allowLocalFiles:true)
    let cpu=try NativeStockPedLoader(fileLoader:files,sourceIdentity:{source})
    var limits=NativeStockPedRuntime<CountedResource>.Limits();limits.residentBytes=20;limits.entries=2;limits.pending=2
    let owner=try NativeStockPedRuntime(loader:cpu,sourceIdentity:{source},limits:limits,now:{now},estimate:{_ in 10},upload:{value,allowance in
        require(allowance>=10,"Owner ignored preflight allowance");uploads+=1;return(CountedResource(value.model.id),10)
    })
    owner.onRetired={retired.append($0.model.id)}
    owner.setDemand([100,101])
    try await wait(owner,ids:[100,101]) {
        owner.ensure(resolutions[0],at:now);owner.ensure(resolutions[0],at:now);owner.ensure(resolutions[1],at:now)
        require(owner.pendingCount==2,"Duplicate work or missing two-family admission")
    }
    require(uploads==2 && owner.count==2 && owner.residentBytes==20,"Initial bounded resident publication")
    now=11;require(owner.ready(100,at:now)?.resource.id==100,"Wrong ready resource identity")
    owner.setDemand([100,102])
    try await wait(owner,ids:[102]){owner.ensure(resolutions[2],at:now)}
    require(retired==[101] && owner.ready(100,at:now) != nil && owner.ready(102,at:now) != nil,"Unneeded family retirement evicted a demanded identity")
    require(owner.residentBytes==20 && uploads==3,"Retirement accounting drift")
    owner.setDemand([100,101,102]);now=20
    try await wait(owner,ids:[101],failure:true){owner.ensure(resolutions[1],at:now)}
    require(uploads==3 && owner.count==2 && owner.pendingCount==0,"Pinned cache overflow allocated/published another family")
    owner.setDemand([101,102]);now=24;owner.ensure(resolutions[1],at:now)
    require(owner.pendingCount==0,"Failure backoff expired before completion-time deadline")
    now=25;try await wait(owner,ids:[101]){owner.ensure(resolutions[1],at:now)}
    require(uploads==4 && owner.ready(100,at:now)==nil && owner.ready(101,at:now) != nil,"Retry/retirement did not preserve exact requested identity")
    source="source-B";require(owner.synchronizeSource(),"Source replacement not observed")
    require(owner.count==0 && owner.residentBytes==0 && owner.pendingCount==0,"Old-source resident resources survived")

    // Reenter with a fresh lifetime from the real upload callback. The old
    // resource must never publish over the replacement's same canonical ID.
    var reentrant:NativeStockPedRuntime<CountedResource>!,uploadSwitched=false,reentrantUploads=0
    let cpu2=try NativeStockPedLoader(fileLoader:files,sourceIdentity:{source})
    reentrant=try NativeStockPedRuntime(loader:cpu2,sourceIdentity:{source},limits:limits,now:{now},estimate:{_ in 10},upload:{value,_ in
        reentrantUploads+=1
        if !uploadSwitched {
            uploadSwitched=true;source="source-C";reentrant.reset();reentrant.setDemand([100]);reentrant.ensure(resolutions[0],at:now)
        }
        return(CountedResource(value.model.id),10)
    })
    reentrant.setDemand([100]);try await wait(reentrant,ids:[100]){reentrant.ensure(resolutions[0],at:now)}
    require(reentrantUploads==2 && reentrant.count==1 && reentrant.residentBytes==10,"Reentrant old upload published or double-charged")
    require(reentrant.ready(100,at:now)?.sourceIdentity=="source-C","Old source overwrote replacement")

    // Source replacement during LRU retirement must also stop the old loop
    // before it can remove resources owned by the replacement lifetime.
    var retirementSwitched=false;reentrant.setDemand([100,101])
    try await wait(reentrant,ids:[101]){reentrant.ensure(resolutions[1],at:now)}
    reentrant.onRetired={_ in
        if !retirementSwitched{retirementSwitched=true;source="source-D";reentrant.reset();reentrant.setDemand([102]);reentrant.ensure(resolutions[2],at:now)}
    }
    reentrant.setDemand([102]);try await wait(reentrant,ids:[102]){reentrant.ensure(resolutions[2],at:now)}
    require(reentrant.count==1 && reentrant.residentBytes==10 && reentrant.ready(102,at:now)?.sourceIdentity=="source-D","Retirement reentry crossed the replacement lifetime")
    reentrant.reset();owner.reset()

    var levels=0
    if let device=MTLCreateSystemDefaultDevice() {
        let cpu3=try NativeStockPedLoader(fileLoader:files,sourceIdentity:{source})
        let gpu=try NativeStockPedRuntime(loader:cpu3,sourceIdentity:{source},estimate:{try NativeStockPedAllocation.reservation($0,device:device)},upload:{try NativeStockPedAllocation.upload($0,device:device,allowance:$1)})
        gpu.setDemand([100]);try await wait(gpu,ids:[100]){gpu.ensure(resolutions[0],at:now)}
        guard let ready=gpu.ready(100,at:now)else{throw TestFailure.unexpected}
        let resource=ready.resource,plan=resource.plan
        require(plan.skeleton.encodedByteCount==plan.skeleton.encodedSKN1().count,"Analytic SKN1 admission changed serialized byte count")
        require(ready.chargedBytes==gpu.residentBytes && ready.chargedBytes>plan.model.meshByteCount+plan.model.textureByteCount,"Real Metal buffers/textures absent from cache charge")
        let image=resource.resources.textures[0]
        require(image.width==4 && image.height==2 && image.mipmapLevelCount==3,"Original authored dimensions/stored mips changed")
        let command=device.makeCommandQueue()!.makeCommandBuffer()!,blit=command.makeBlitCommandEncoder()!
        var buffers:[MTLBuffer]=[]
        for (level,size)in [(4,2),(2,1),(1,1)].enumerated(){
            let b=device.makeBuffer(length:256*size.1,options:.storageModeShared)!
            blit.copy(from:image,sourceSlice:0,sourceLevel:level,sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:size.0,height:size.1,depth:1),to:b,destinationOffset:0,destinationBytesPerRow:256,destinationBytesPerImage:256*size.1);buffers.append(b)
        }
        blit.endEncoding();command.commit();command.waitUntilCompleted();require(command.status == .completed,"Actual mip readback failed")
        let colors:[[UInt8]]=[[255,0,0,255],[0,255,0,255],[0,0,255,255]]
        for (level,b)in buffers.enumerated(){let p=b.contents().assumingMemoryBound(to:UInt8.self);require(Array(UnsafeBufferPointer(start:p,count:4))==colors[level],"Stored mip pixels changed");levels+=1}
        gpu.reset();require(gpu.residentBytes==0 && gpu.count==0,"GPU retirement retained charged resource")
    }else{require(!CommandLine.arguments.contains("--require-gpu"),"Required actual Metal device unavailable")}
    print("PASS \(checks) actual acquisition/cache/lifetime checks, \(levels) Metal stored-mip readbacks; no renderer/UI/retail claim")
 }
}
