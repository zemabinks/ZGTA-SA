// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal
import simd

/// Ordinary one-pixel lines with the archived linear vertex color and alpha
/// ramp. Original scene fog/tone mapping still needs its separate comparison.
final class NativeShotTracerRenderer {
    struct Vertex {var position:SIMD4<Float>,color:SIMD4<Float>}
    private let device:MTLDevice,pipeline:MTLRenderPipelineState,depth:MTLDepthStencilState
    static var color:SIMD3<Float> {
        let blue=Double(128)/255
        return SIMD3(1,1,Float(pow((blue+0.055)/1.055,2.4)))
    }
    static let alpha=Float(70)/255
    init?(device:MTLDevice,library:MTLLibrary,colorFormat:MTLPixelFormat,depthFormat:MTLPixelFormat) {
        let descriptor=MTLRenderPipelineDescriptor()
        descriptor.vertexFunction=library.makeFunction(name:"nativeShotTracerVertex")
        descriptor.fragmentFunction=library.makeFunction(name:"nativeShotTracerFragment")
        descriptor.colorAttachments[0].pixelFormat=colorFormat;descriptor.depthAttachmentPixelFormat=depthFormat
        let color=descriptor.colorAttachments[0]!
        color.isBlendingEnabled=true;color.sourceRGBBlendFactor = .sourceAlpha;color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.sourceAlphaBlendFactor = .one;color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let depth=MTLDepthStencilDescriptor();depth.depthCompareFunction = .lessEqual;depth.isDepthWriteEnabled=false
        guard descriptor.vertexFunction != nil,descriptor.fragmentFunction != nil,
              let pipeline=try? device.makeRenderPipelineState(descriptor:descriptor),let state=device.makeDepthStencilState(descriptor:depth)else{return nil}
        self.device=device;self.pipeline=pipeline;self.depth=state
    }
    static func vertices(_ lines:[NativeShotTracers.Line])->[Vertex] {
        let color=Self.color
        return lines.flatMap{line in
            [Vertex(position:SIMD4(SIMD3<Float>(line.back),1),color:SIMD4(color,0)),
             Vertex(position:SIMD4(SIMD3<Float>(line.head),1),color:SIMD4(color,Self.alpha*Float(line.opacity)))]
        }
    }
    @discardableResult func draw(_ lines:[NativeShotTracers.Line],matrix:simd_float4x4,encoder:MTLRenderCommandEncoder)->Int {
        let vertices=Self.vertices(lines)
        guard !vertices.isEmpty,let buffer=device.makeBuffer(bytes:vertices,length:vertices.count*MemoryLayout<Vertex>.stride)else{return 0}
        var matrix=matrix
        encoder.setRenderPipelineState(pipeline);encoder.setDepthStencilState(depth)
        encoder.setVertexBuffer(buffer,offset:0,index:0);encoder.setVertexBytes(&matrix,length:MemoryLayout<simd_float4x4>.stride,index:1)
        encoder.drawPrimitives(type:.line,vertexStart:0,vertexCount:vertices.count)
        return lines.count
    }
}
