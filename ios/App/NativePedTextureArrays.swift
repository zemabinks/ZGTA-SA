// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal

/// Exact native-size images, uploaded before subsequent draws on the same
/// command queue. Array grouping avoids atlas-coordinate sampler differences.
final class NativePedTextureArrays {
    enum Failure:Error,Equatable {case dimensions,budget,allocation,upload,queue,group,indexBuffer}
    static let maximumAllocationBytes=2*1024*1024
    let plan:NativePedAtlasLayout.HardwarePlan
    let textures:[MTLTexture],entries:MTLBuffer,allocatedBytes:Int
    private let ownerQueue:MTLCommandQueue,upload:MTLCommandBuffer

    init(device:MTLDevice,queue:MTLCommandQueue,atlas:MTLTexture,plan:NativePedAtlasLayout.HardwarePlan,
         maximumAllocationBytes:Int=NativePedTextureArrays.maximumAllocationBytes)throws {
        guard maximumAllocationBytes>0,maximumAllocationBytes<=Self.maximumAllocationBytes else{throw Failure.budget}
        guard atlas.textureType == .type2D,atlas.mipmapLevelCount==1,
              [.rgba8Unorm,.bgra8Unorm].contains(atlas.pixelFormat),!plan.groups.isEmpty,
              !plan.entries.isEmpty,plan.entries.count<=4096 else{throw Failure.dimensions}
        let mapBytes=plan.entries.count*MemoryLayout<SIMD2<UInt32>>.stride
        // Reserve a full CPU/GPU page for the small mapping buffer before
        // creating any textures. Query device-specific texture sizes up front.
        let mapReservation=max(65536,mapBytes),limit=maximumAllocationBytes
        var descriptors:[MTLTextureDescriptor]=[],estimates:[Int]=[],estimated=mapReservation
        for group in plan.groups {
            guard group.width>0,group.height>0,!group.copies.isEmpty,group.copies.count<=256 else{throw Failure.dimensions}
            let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:atlas.pixelFormat,width:group.width,height:group.height,mipmapped:false)
            descriptor.textureType = .type2DArray;descriptor.arrayLength=group.copies.count
            descriptor.storageMode = .private;descriptor.usage = .shaderRead
            let size=device.heapTextureSizeAndAlign(descriptor:descriptor).size
            guard size>0,size<=limit-estimated else{throw Failure.budget}
            estimated+=size;estimates.append(size);descriptors.append(descriptor)
            for copy in group.copies {
                let r=copy.rect
                guard r.count==4,r[0]>=0,r[0]<atlas.width,r[1]>=0,r[1]<atlas.height,
                      r[2]==group.width,r[3]==group.height,r[2]<=atlas.width-r[0],r[3]<=atlas.height-r[1] else{throw Failure.dimensions}
            }
        }
        guard let entries=device.makeBuffer(bytes:plan.entries,length:mapBytes,options:.storageModeShared),
              let command=queue.makeCommandBuffer(),let blit=command.makeBlitCommandEncoder() else{throw Failure.allocation}
        var textures:[MTLTexture]=[],actual=max(entries.allocatedSize,mapBytes)
        for (index,descriptor) in descriptors.enumerated() {
            guard let texture=device.makeTexture(descriptor:descriptor) else{blit.endEncoding();throw Failure.allocation}
            let bytes=max(texture.allocatedSize,estimates[index])
            guard bytes<=limit-actual else{blit.endEncoding();throw Failure.budget};actual+=bytes
            textures.append(texture)
            for (slice,copy) in plan.groups[index].copies.enumerated() {
                let r=copy.rect
                blit.copy(from:atlas,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:r[0],y:r[1],z:0),
                          sourceSize:MTLSize(width:r[2],height:r[3],depth:1),to:texture,destinationSlice:slice,
                          destinationLevel:0,destinationOrigin:MTLOrigin(x:0,y:0,z:0))
            }
        }
        blit.endEncoding();command.label="ZGTA native pedestrian textures"
        self.plan=plan;self.textures=textures;self.entries=entries;allocatedBytes=actual;ownerQueue=queue;upload=command
        // Publication follows commit; later render commands on ownerQueue see
        // the complete copy without blocking the main thread for GPU work.
        command.commit()
    }
    private func checkQueue(_ queue:MTLCommandQueue)throws {
        guard (queue as AnyObject) === (ownerQueue as AnyObject) else{throw Failure.queue}
        guard upload.status != .error else{throw Failure.upload}
    }
    func bind(group:Int,encoder:MTLRenderCommandEncoder,queue:MTLCommandQueue)throws {
        try checkQueue(queue)
        guard textures.indices.contains(group),let index=UInt32(exactly:group) else{throw Failure.group}
        var selected=index
        encoder.setFragmentTexture(textures[group],index:0)
        encoder.setFragmentBuffer(entries,offset:0,index:3)
        encoder.setFragmentBytes(&selected,length:MemoryLayout<UInt32>.stride,index:4)
    }
    func encode(indices:MTLBuffer,encoder:MTLRenderCommandEncoder,queue:MTLCommandQueue,range:Range<Int>?=nil)throws {
        try checkQueue(queue)
        guard indices.length>0,indices.length%4==0 else{throw Failure.indexBuffer}
        let count=plan.draws.last.map{$0.indexOffset+$0.indexCount} ?? 0
        let selected=range ?? (0..<count)
        guard selected.lowerBound>=0,selected.upperBound<=count,
              selected.lowerBound%3==0,selected.upperBound%3==0 else{throw Failure.indexBuffer}
        for draw in plan.draws {
            guard textures.indices.contains(draw.group),draw.indexOffset>=0,draw.indexCount>0,draw.indexOffset<=indices.length/4,
                  draw.indexCount<=indices.length/4-draw.indexOffset else{throw Failure.indexBuffer}
        }
        for draw in plan.draws {
            let start=max(draw.indexOffset,selected.lowerBound),end=min(draw.indexOffset+draw.indexCount,selected.upperBound)
            if start>=end{continue}
            try bind(group:draw.group,encoder:encoder,queue:queue)
            encoder.drawIndexedPrimitives(type:.triangle,indexCount:end-start,indexType:.uint32,
                                          indexBuffer:indices,indexBufferOffset:start*4)
        }
    }
}
