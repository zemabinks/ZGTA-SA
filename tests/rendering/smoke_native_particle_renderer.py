#!/usr/bin/env python3
"""Exercise exact FX texture arrays and the full 1120-instance Metal batch."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess
ROOT=Path(__file__).resolve().parents[2]
SWIFT=r'''
let root=URL(fileURLWithPath:CommandLine.arguments[1]),folder=root.appendingPathComponent("local-only/site/game/native/effects")
guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else{fatalError("Mac Metal unavailable")}
let options=MTLCompileOptions();options.fastMathEnabled=false
var shader=try String(contentsOf:root.appendingPathComponent("ios/App/NativeParticleShaders.metal"),encoding:.utf8)
shader+="""
 kernel void nativeFXDebug(device const NativeFXInstance* particles [[buffer(0)]],constant NativeFXUniforms& u [[buffer(1)]],device float4* out [[buffer(2)]],uint id [[thread_position_in_grid]]){out[id]=nativeFXPlace(id,particles[0],u).position;}
 """
let library=try device.makeLibrary(source:shader,options:options)
guard let renderer=NativeParticleRenderer(device:device,queue:queue,library:library,metadata:try Data(contentsOf:folder.appendingPathComponent("fx-textures.json")))else{fatalError("Original FX pipeline metadata invalid")}
for(index,sheet)in renderer.document.sheets.enumerated(){let data=try Data(contentsOf:folder.appendingPathComponent(sheet.file));assert(renderer.install(sheet:index,data:data))}
assert(renderer.ready);let effects=try NativeParticleEffects(data:Data(contentsOf:root.appendingPathComponent("local-only/site/game/world/fx.json")),textures:Set(renderer.document.sprites.keys),random:{0.37})
effects.spawn("prt_gunshell",at:SIMD3(0,0,2),velocity:.zero,count:1024,options:.init(mult:.init(size:20)))
effects.spawn("water_ripples",at:SIMD3(0,0,2),velocity:.zero,count:96,options:.init(water:2))
effects.update(delta:0.01)
assert(effects.shown.count==1120,"Both original particle rings must be full")
let eye=SIMD3<Float>(0,-8,2),view=simd_float4x4(columns:(SIMD4(1,0,0,0),SIMD4(0,0,-1,0),SIMD4(0,1,0,0),SIMD4(0,0,0,1)))
let scale:Float=1/tan(Float.pi/6),near:Float=0.1,far:Float=100,projection=simd_float4x4(columns:(SIMD4(scale/1.5,0,0,0),SIMD4(0,scale,0,0),SIMD4(0,0,far/(near-far),-1),SIMD4(0,0,far*near/(near-far),0)))
let instances=renderer.instances(effects.particles,eye:SIMD3<Double>(eye),view:view,projection:projection)
assert(instances.count==1120 && MemoryLayout<NativeParticleRenderer.Instance>.stride==80)
assert(instances.first!.kind.z==1 && instances.last!.kind.z==0,"Original rank sorts first flat emitter before normal particles")
var last=instances.last!,debugUniforms=NativeParticleRenderer.Uniforms(projection:projection,viewRotation:view,fogColor:.zero,fog:.zero)
let debug=device.makeBuffer(length:96,options:.storageModeShared)!,compute=try device.makeComputePipelineState(function:library.makeFunction(name:"nativeFXDebug")!),debugCommand=queue.makeCommandBuffer()!,debugEncoder=debugCommand.makeComputeCommandEncoder()!
debugEncoder.setComputePipelineState(compute);debugEncoder.setBytes(&last,length:80,index:0);debugEncoder.setBytes(&debugUniforms,length:MemoryLayout<NativeParticleRenderer.Uniforms>.stride,index:1);debugEncoder.setBuffer(debug,offset:0,index:2);debugEncoder.dispatchThreads(MTLSize(width:6,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:6,height:1,depth:1));debugEncoder.endEncoding();debugCommand.commit();debugCommand.waitUntilCompleted()
let clips=Array(UnsafeBufferPointer(start:debug.contents().assumingMemoryBound(to:SIMD4<Float>.self),count:6))
let corners:[SIMD2<Float>]=[SIMD2(-1,-1),SIMD2(1,-1),SIMD2(1,1),SIMD2(-1,-1),SIMD2(1,1),SIMD2(-1,1)]
for(index,corner)in corners.enumerated(){let expected=SIMD4(corner.x*scale/1.5,(corner.y-0.002)*scale,(-8*far+far*near)/(near-far),8);assert(simd_distance(clips[index],expected)<0.00001,"Original FX vertex camera/projection contract")}
let colorD=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:192,height:128,mipmapped:false);colorD.usage=[.renderTarget,.shaderRead];colorD.storageMode = .private
let depthD=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:192,height:128,mipmapped:false);depthD.usage = .renderTarget;depthD.storageMode = .private
let color=device.makeTexture(descriptor:colorD)!,depth=device.makeTexture(descriptor:depthD)!,pass=MTLRenderPassDescriptor()
pass.colorAttachments[0].texture=color;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store;pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
let command=queue.makeCommandBuffer()!,encoder=command.makeRenderCommandEncoder(descriptor:pass)!
encoder.setCullMode(.none);encoder.setViewport(MTLViewport(originX:0,originY:0,width:192,height:128,znear:0,zfar:1))
renderer.draw(effects.particles,eye:eye,view:view,projection:projection,fogColor:.zero,fogNear:20,fogFar:80,fogAmount:0,encoder:encoder)
encoder.endEncoding()
let readback=device.makeBuffer(length:192*128*4,options:.storageModeShared)!,blit=command.makeBlitCommandEncoder()!
blit.copy(from:color,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:192,height:128,depth:1),to:readback,destinationOffset:0,destinationBytesPerRow:192*4,destinationBytesPerImage:192*128*4);blit.endEncoding();command.commit();command.waitUntilCompleted();if let error=command.error{fatalError("Original FX GPU execution failed: \(error)")}
let bytes=Array(UnsafeBufferPointer(start:readback.contents().assumingMemoryBound(to:UInt8.self),count:192*128*4))
var painted=0
for index in stride(from:0,to:bytes.count,by:4){if bytes[index]>0 || bytes[index+1]>0 || bytes[index+2]>0{painted+=1}}
assert(painted>0,"Original texture arrays and shader must draw visible particles")
print("PASS: \(renderer.document.sheets.count) exact original FX texture arrays, 1120 instances/89,600 attribute bytes, original rank packing and Metal draw; \(painted) lit pixels")
'''
def main():
 work=Path('/private/tmp/zgta-particle-renderer-debug');work.mkdir(exist_ok=True)
 (work/'verify.swift').write_text((ROOT/'ios/App/NativeParticleEffects.swift').read_text()+(ROOT/'ios/App/NativeParticleRenderer.swift').read_text()+SWIFT)
 subprocess.run(['swiftc','-Onone','-whole-module-optimization','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'verify.swift'),'-o',str(work/'verify')],check=True)
 subprocess.run([str(work/'verify'),str(ROOT)],check=True)
if __name__=='__main__':main()
