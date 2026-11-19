// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal

/// VPC3 staging images retain every original base texel. Individual native-size
/// images provide hardware wrapping and filtering without atlas-edge seams.
final class NativeVehicleTextures {
    enum Failure:Error {case family,geometry,budget,allocation,queue,upload,slot}
    static let maximumAllocationBytes=8*1024*1024
    let textures:[MTLTexture],samplers:[MTLSamplerState],allocatedBytes:Int
    private let ownerQueue:MTLCommandQueue,upload:MTLCommandBuffer

    init(device:MTLDevice,queue:MTLCommandQueue,atlas:MTLTexture,rig:NativeVehicleRig,world:WorldBinary,
         maximumAllocationBytes:Int=NativeVehicleTextures.maximumAllocationBytes)throws {
        guard rig.document.version==3,let layout=rig.document.nativeTextures,
              atlas.width==layout.width,atlas.height==layout.height,atlas.textureType == .type2D,
              atlas.mipmapLevelCount==1,[.rgba8Unorm,.bgra8Unorm].contains(atlas.pixelFormat),
              world.layers==layout.rects.count else{throw Failure.family}
        try layout.validate(draws:rig.document.draws)
        guard rig.validatesNativeTextureMesh(layerCount:world.layers,indexCount:world.indices.count,
            layerAtIndex:{world.vertices[Int(world.indices[$0])].uvLayer.z})else{throw Failure.geometry}
        guard maximumAllocationBytes>0,maximumAllocationBytes<=Self.maximumAllocationBytes else{throw Failure.budget}
        var descriptors:[MTLTextureDescriptor]=[],estimates:[Int]=[],estimated=0
        for (index,r) in layout.rects.enumerated() {
            let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:atlas.pixelFormat,width:r[2],height:r[3],mipmapped:layout.samplers[index].mipmapped)
            d.storageMode = .private;d.usage = .shaderRead
            let size=device.heapTextureSizeAndAlign(descriptor:d).size
            guard size>0,size<=maximumAllocationBytes-estimated else{throw Failure.budget}
            estimated+=size;descriptors.append(d);estimates.append(size)
        }
        var states:[MTLSamplerState]=[],cache:[NativeVehicleRig.TextureLayout.Sampler:MTLSamplerState]=[:]
        func address(_ value:Int)->MTLSamplerAddressMode {value==1000 ? .repeat:value==1001 ? .clampToEdge:.mirrorRepeat}
        for s in layout.samplers {
            if let state=cache[s]{states.append(state);continue}
            let d=MTLSamplerDescriptor()
            d.sAddressMode=address(s.wrapS);d.tAddressMode=address(s.wrapT)
            d.magFilter=s.magFilter==1003 ? .nearest:.linear
            d.minFilter=[1003,1004,1005].contains(s.minFilter) ? .nearest:.linear
            d.mipFilter=[1004,1007].contains(s.minFilter) ? .nearest:[1005,1008].contains(s.minFilter) ? .linear:.notMipmapped
            guard let state=device.makeSamplerState(descriptor:d) else{throw Failure.allocation}
            cache[s]=state;states.append(state)
        }
        guard let command=queue.makeCommandBuffer(),let blit=command.makeBlitCommandEncoder() else{throw Failure.allocation}
        var images:[MTLTexture]=[],actual=0
        for (index,d) in descriptors.enumerated() {
            guard let image=device.makeTexture(descriptor:d) else{blit.endEncoding();throw Failure.allocation}
            let size=max(image.allocatedSize,estimates[index])
            guard size<=maximumAllocationBytes-actual else{blit.endEncoding();throw Failure.budget}
            actual+=size;images.append(image)
            let r=layout.rects[index]
            blit.copy(from:atlas,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:r[0],y:r[1],z:0),
                      sourceSize:MTLSize(width:r[2],height:r[3],depth:1),to:image,destinationSlice:0,destinationLevel:0,destinationOrigin:MTLOrigin(x:0,y:0,z:0))
            // This is an explicit generated chain, not a claim to recover the
            // original TXD's stored mip images or a particular retail GPU.
            if image.mipmapLevelCount>1{blit.generateMipmaps(for:image)}
        }
        blit.endEncoding();command.label="ZGTA native vehicle textures"
        textures=images;samplers=states;allocatedBytes=actual;ownerQueue=queue;upload=command
        command.commit()
    }
    func bind(slot:Int,encoder:MTLRenderCommandEncoder,queue:MTLCommandQueue)throws {
        guard (queue as AnyObject) === (ownerQueue as AnyObject) else{throw Failure.queue}
        guard upload.status != .error else{throw Failure.upload}
        guard textures.indices.contains(slot),samplers.indices.contains(slot) else{throw Failure.slot}
        encoder.setFragmentTexture(textures[slot],index:0)
        encoder.setFragmentSamplerState(samplers[slot],index:0)
    }
}
