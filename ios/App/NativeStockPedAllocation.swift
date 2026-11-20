// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal

/// Accounted CPU payload plus device-reported shared buffer/texture allocation.
/// Driver/allocator overhead and transient decode/upload work are separate;
/// this is a bounded resident-cache charge, not a whole-process RAM guarantee.
enum NativeStockPedAllocation {
    enum Failure:Error {case budget,geometry,texture,accounting(bytes:Int,remaining:Int,reserved:Int)}
    /// Heap sizing describes suballocation, not dedicated-resource overhead.
    /// Reserve whole blocks plus one block of slack, then still validate the
    /// reported standalone allocation before admitting a resident resource.
    /// This is deliberately conservative and is not a universal RAM estimate.
    private static func standalone(_ allocation:MTLSizeAndAlign)throws->Int {
        let maximum=256*1024*1024,alignment=max(65_536,allocation.align)
        guard allocation.size>0,allocation.size<=maximum,alignment>0,alignment<=maximum else{throw Failure.budget}
        let rounded=((allocation.size+alignment-1)/alignment)*alignment
        guard rounded<=maximum-alignment else{throw Failure.budget}
        return rounded+alignment
    }
    static func reservation(_ value:NativeStockPedLoader.Prepared,device:MTLDevice)throws->Int {
        let plan=value.plan
        var bytes=value.resourceBytes
        func add(_ count:Int)throws {
            guard count>0,count<=256*1024*1024,bytes<=256*1024*1024-count else{throw Failure.budget}
            bytes+=count
        }
        func buffer(_ length:Int)throws {
            guard length>0 else{throw Failure.geometry}
            let allocation=device.heapBufferSizeAndAlign(length:length,options:.storageModeShared)
            guard allocation.size>=length else{throw Failure.geometry};try add(standalone(allocation))
        }
        for geometry in plan.model.geometries {
            try buffer(geometry.vertices.count*MemoryLayout<NativeRenderWareModel.Vertex>.stride)
            try buffer(max(4,geometry.indices.count*MemoryLayout<UInt32>.stride))
        }
        try buffer(plan.skeleton.vertices.count*MemoryLayout<NativeSkinVertex>.stride)
        func image(width:Int,height:Int,mips:Int)throws {
            guard width>0,height>0,mips>0 else{throw Failure.texture}
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:width,height:height,mipmapped:mips>1)
            d.mipmapLevelCount=mips;d.storageMode = .shared;d.usage = .shaderRead
            let allocation=device.heapTextureSizeAndAlign(descriptor:d)
            guard allocation.size>0 else{throw Failure.texture};try add(standalone(allocation))
        }
        for texture in plan.model.textures {
            let mips=texture.mipLevels.prefix{$0.rgba8 != nil}
            guard let base=mips.first else{throw Failure.texture}
            try image(width:base.width,height:base.height,mips:mips.count)
        }
        try image(width:1,height:1,mips:1)
        return bytes
    }
    static func upload(_ value:NativeStockPedLoader.Prepared,device:MTLDevice,allowance:Int,validateActor:((NativeSkeletalActor)throws->Void)?=nil)throws->(resource:NativeRenderWarePedModel.Uploaded,chargedBytes:Int) {
        let reserved=try reservation(value,device:device)
        guard reserved<=allowance else{throw Failure.budget}
        let resource=try NativeRenderWarePedModel.Uploaded(plan:value.plan,device:device,validateActor:validateActor)
        var actual=value.resourceBytes
        func add(_ bytes:Int)throws {
            guard bytes>0 else{throw Failure.budget}
            guard bytes<=reserved,actual<=reserved-bytes else{throw Failure.accounting(bytes:bytes,remaining:reserved-actual,reserved:reserved)}
            actual+=bytes
        }
        func buffer(_ value:MTLBuffer)throws {
            let count=value.allocatedSize>0 ? max(value.length,value.allocatedSize):try standalone(device.heapBufferSizeAndAlign(length:value.length,options:.storageModeShared))
            try add(count)
        }
        for geometry in resource.resources.geometries {
            try buffer(geometry.vertices);try buffer(geometry.indices)
        }
        try buffer(resource.actor.skinVertices)
        for texture in resource.resources.textures+[resource.resources.whiteTexture] {
            // Some drivers report zero for a shared texture. Match the exact
            // constructor descriptor and retain its device allocation estimate.
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:texture.pixelFormat,width:texture.width,height:texture.height,mipmapped:texture.mipmapLevelCount>1)
            d.mipmapLevelCount=texture.mipmapLevelCount;d.storageMode = .shared;d.usage = .shaderRead
            let count=texture.allocatedSize>0 ? texture.allocatedSize:try standalone(device.heapTextureSizeAndAlign(descriptor:d))
            try add(count)
        }
        return (resource,actual)
    }
}
