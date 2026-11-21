// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal
import simd

@main enum ShotTracerGPUTests {
    static var checks=0
    static func check(_ value:Bool,_ label:String){checks+=1;precondition(value,label)}
    static func main()throws {
        guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue()else{
            if CommandLine.arguments.contains("--require-gpu"){fatalError("Metal device unavailable")}
            print("SKIP actual Metal tracer pixels: no GPU device. Swift compilation only; no pixel acceptance.");return
        }
        let source=try String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8),library=try device.makeLibrary(source:source,options:nil)
        guard let renderer=NativeShotTracerRenderer(device:device,library:library,colorFormat:.rgba8Unorm,depthFormat:.depth32Float)else{fatalError("Actual tracer pipeline unavailable")}
        let width=64,height=32
        func render(_ lines:[NativeShotTracers.Line],depth clearDepth:Double=1)throws->([UInt8],Int) {
            let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:width,height:height,mipmapped:false)
            descriptor.storageMode = .private;descriptor.usage=[.renderTarget,.shaderRead]
            let depthDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:width,height:height,mipmapped:false)
            depthDescriptor.storageMode = .private;depthDescriptor.usage = .renderTarget
            let target=device.makeTexture(descriptor:descriptor)!,depth=device.makeTexture(descriptor:depthDescriptor)!
            let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor=MTLClearColor(red:0,green:0,blue:0,alpha:0)
            pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=clearDepth
            let command=queue.makeCommandBuffer()!,encoder=command.makeRenderCommandEncoder(descriptor:pass)!
            encoder.setCullMode(.none)
            encoder.setViewport(MTLViewport(originX:0,originY:0,width:Double(width),height:Double(height),znear:0,zfar:1))
            let count=renderer.draw(lines,matrix:matrix_identity_float4x4,encoder:encoder)
            encoder.endEncoding()
            let readback=device.makeBuffer(length:width*height*4,options:.storageModeShared)!,blit=command.makeBlitCommandEncoder()!
            blit.copy(from:target,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),
                sourceSize:MTLSize(width:width,height:height,depth:1),to:readback,destinationOffset:0,
                destinationBytesPerRow:width*4,destinationBytesPerImage:width*height*4)
            blit.endEncoding();command.commit();command.waitUntilCompleted()
            check(command.error==nil,"Actual Metal command failed")
            let bytes=Array(UnsafeBufferPointer(start:readback.contents().assumingMemoryBound(to:UInt8.self),count:width*height*4))
            return(bytes,count)
        }
        func pixels(_ bytes:[UInt8])->[[UInt8]]{stride(from:0,to:bytes.count,by:4).map{Array(bytes[$0..<$0+4])}}
        let owner=NativeShotTracers(random:{0});owner.shot(from:SIMD3(-0.75,0,0.5),to:SIMD3(0.75,0,0.5))
        let initial=try render(owner.lines),lit=pixels(initial.0).filter{$0[3]>0}
        try Data(initial.0).write(to:URL(fileURLWithPath:CommandLine.arguments[2]).appendingPathComponent("initial.rgba"))
        let diagnostic="Actual tracer readback: submitted=\(initial.1) litPixels=\(lit.count) peakAlpha=\(lit.map{$0[3]}.max() ?? 0) device=\(device.name)\n"
        FileHandle.standardError.write(Data(diagnostic.utf8))
        check(initial.1==1 && lit.count>20 && lit.count<70,"One-pixel line was absent or expanded into a quad")
        check(lit.allSatisfy{$0[0]==$0[1]},"Tracer red/green source color changed")
        let bright=lit.filter{$0[0]>30}
        check(!bright.isEmpty && bright.allSatisfy{abs(Double($0[2])/Double($0[0])-128.0/255)<0.04},"Actual shader color transfer/blending differs")
        let peak=Double(lit.map{$0[3]}.max()!)/255
        check(peak>0.25 && peak<0.28,"Tracer head alpha changed")
        owner.advance(delta:0.15)
        let faded=try render(owner.lines),fadedLit=pixels(faded.0).filter{$0[3]>0}
        check(fadedLit.count<lit.count && fadedLit.count>lit.count/3,"Tracer tail did not contract")
        let fadedPeak=Double(fadedLit.map{$0[3]}.max()!)/255
        check(fadedPeak>0.11 && fadedPeak<0.145,"Actual tracer alpha did not fade with lifetime")
        let hidden=try render(owner.lines,depth:0.2)
        check(hidden.1==1 && hidden.0.allSatisfy{$0==0},"Tracer ignored solid depth")
        let front=NativeShotTracers.Line(slot:0,back:SIMD3(-0.75,0,0.4),head:SIMD3(0.75,0,0.4),opacity:1)
        let back=NativeShotTracers.Line(slot:1,back:SIMD3(-0.75,0,0.6),head:SIMD3(0.75,0,0.6),opacity:1)
        let stacked=try render([front,back]),stackedPeak=Double(pixels(stacked.0).map{$0[3]}.max()!)/255
        check(stacked.1==2 && stackedPeak>0.4,"Transparent tracers wrote depth or failed normal blending")
        owner.advance(delta:0.15)
        let empty=try render(owner.lines)
        check(empty.1==0 && empty.0.allSatisfy{$0==0},"Expired tracer still submitted geometry")
        print("PASS actual Metal tracer: \(checks) gates; color/alpha, shrinking lifetime, one-pixel geometry, depth testing and no depth writes. Authored geometry; no original scene fog/tone-map, Simulator or retail acceptance")
    }
}
