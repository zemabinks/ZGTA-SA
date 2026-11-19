// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal

/// One cell's original high-resolution images. Upload is queue-ordered; the
/// render thread never waits for completion or rebuilds image coordinates.
final class NativeWorldSharpTextures {
    enum Failure:Error {case image,budget,allocation,queue,upload}
    let texture:MTLTexture,map:MTLBuffer,sampler:MTLSamplerState,allocatedBytes:Int
    let layout:NativeWorldSharpLayout
    private let ownerQueue:MTLCommandQueue,upload:MTLCommandBuffer

    init(device:MTLDevice,queue:MTLCommandQueue,atlas:MTLTexture,layout:NativeWorldSharpLayout,
         maximumAllocationBytes:Int=NativeWorldSharpLayout.maximumGPUBytes)throws {
        guard atlas.width==layout.width,atlas.height==layout.height,
              atlas.textureType == .type2D,atlas.mipmapLevelCount==1,
              [.rgba8Unorm,.bgra8Unorm].contains(atlas.pixelFormat)else{throw Failure.image}
        guard maximumAllocationBytes>0,maximumAllocationBytes<=NativeWorldSharpLayout.maximumGPUBytes else{throw Failure.budget}
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:atlas.pixelFormat,width:256,height:256,mipmapped:true)
        descriptor.textureType = .type2DArray;descriptor.arrayLength=layout.sharpLayers
        descriptor.storageMode = .private;descriptor.usage = .shaderRead
        let estimate=device.heapTextureSizeAndAlign(descriptor:descriptor).size
        let mapBytes=layout.map.count*MemoryLayout<UInt32>.stride,reserve=max(65536,mapBytes)
        guard estimate>0,reserve<=maximumAllocationBytes,estimate<=maximumAllocationBytes-reserve else{throw Failure.budget}
        let sampling=MTLSamplerDescriptor();sampling.sAddressMode = .repeat;sampling.tAddressMode = .repeat
        sampling.magFilter = .linear;sampling.minFilter = .linear;sampling.mipFilter = .linear;sampling.maxAnisotropy=4
        guard let image=device.makeTexture(descriptor:descriptor),
              let map=device.makeBuffer(bytes:layout.map,length:mapBytes,options:.storageModeShared),
              let sampler=device.makeSamplerState(descriptor:sampling)else{throw Failure.allocation}
        let actual=max(image.allocatedSize,estimate)+max(map.allocatedSize,mapBytes)
        guard actual<=maximumAllocationBytes else{throw Failure.budget}
        guard let command=queue.makeCommandBuffer(),let blit=command.makeBlitCommandEncoder()else{throw Failure.allocation}
        for layer in 0..<layout.sharpLayers {
            guard let r=layout.rectangle(layer:layer)else{blit.endEncoding();throw Failure.image}
            blit.copy(from:atlas,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:r[0],y:r[1],z:0),
                      sourceSize:MTLSize(width:256,height:256,depth:1),to:image,destinationSlice:layer,
                      destinationLevel:0,destinationOrigin:MTLOrigin(x:0,y:0,z:0))
        }
        blit.generateMipmaps(for:image);blit.endEncoding();command.label="ZGTA original world high-resolution images"
        texture=image;self.map=map;self.sampler=sampler;self.layout=layout;allocatedBytes=actual
        ownerQueue=queue;upload=command;command.commit()
    }
    func bind(encoder:MTLRenderCommandEncoder,queue:MTLCommandQueue)throws {
        guard (queue as AnyObject) === (ownerQueue as AnyObject)else{throw Failure.queue}
        guard upload.status != .error else{throw Failure.upload}
        encoder.setFragmentTexture(texture,index:1);encoder.setFragmentBuffer(map,offset:0,index:2)
        encoder.setFragmentSamplerState(sampler,index:0)
    }
    /// The serial decode worker may wait to bound retired GPU uploads. The
    /// renderer never calls this and only sees successfully completed uploads.
    func finishUpload()throws {
        upload.waitUntilCompleted()
        guard upload.status == .completed else{throw Failure.upload}
    }
}
