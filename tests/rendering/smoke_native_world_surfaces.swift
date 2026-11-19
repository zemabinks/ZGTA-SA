// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import MetalKit
import simd
private enum Failed:Error{case check(String)}
private var checks=0,renders=0
private func check(_ value:Bool,_ reason:String)throws{checks+=1;if !value{throw Failed.check(reason)}}
private enum NativeVehicleRig {
 struct Draw {
  let start:Int=0,count:Int=3
  let layerOverride:Float=0,emissive=false,scorched=false,alphaTest:Float=0
  let paint:SIMD4<Float>
 }
 // ACTUAL_SORT
 // ACTUAL_DEPTH
}
private struct SurfaceView {let colorPixelFormat:MTLPixelFormat = .bgra8Unorm,depthStencilPixelFormat:MTLPixelFormat = .depth32Float}
private final class Harness {
 // ACTUAL_UNIFORMS
 // ACTUAL_MESH
 // ACTUAL_VEHICLE_PACKET
 // ACTUAL_WORLD_PACKET
 // ACTUAL_BASE
 let device:MTLDevice,queue:MTLCommandQueue
 let pipeline:MTLRenderPipelineState,depth:MTLDepthStencilState,markerDepth:MTLDepthStencilState
 let worldSurfacePipelines:[String:MTLRenderPipelineState]
 private var deferredWorldSurfaces:[TransparentWorldDraw]=[]
 private var worldSharpSource:String?="current",worldSharpName:String?,worldSharpGPU:NativeWorldSharpTextures?
 private var worldSharpBase:[String:WorldSharpBase]=[:],worldSharpManifest:NativeWorldSharpManifest?
 private let night:Float=0
 init?(device:MTLDevice,queue:MTLCommandQueue,library:MTLLibrary) {
  guard let vertex=library.makeFunction(name:"worldVertex"),let fragment=library.makeFunction(name:"ordinaryModelFragment")else{return nil}
  let view=SurfaceView()
  // ACTUAL_DESCRIPTOR
  // ACTUAL_SURFACE_PIPELINES
  // ACTUAL_DEPTH_STATES
  self.device=device;self.queue=queue;self.pipeline=pipeline;self.depth=depth;self.markerDepth=markerDepth
  self.worldSurfacePipelines=worldSurfacePipelines
 }
 private func fixedCJSourceIdentity()->String{"current"}
 private func configureEnvironment(_ uniforms:inout Uniforms){}
 // ACTUAL_STAGE
 // ACTUAL_ENCODE_WORLD
 // ACTUAL_ENCODE_SCENE
 // ACTUAL_ENCODE_VEHICLE
 private func texture(_ width:Int,_ height:Int,_ rgba:[UInt8])throws->MTLTexture {
  let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:width,height:height,mipmapped:false)
  d.storageMode=device.hasUnifiedMemory ? .shared:.managed;d.usage = .shaderRead
  guard let t=device.makeTexture(descriptor:d)else{throw Failed.check("texture allocation")}
  rgba.withUnsafeBytes{t.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:width*4)};return t
 }
 private func atlas(_ first:[UInt8],_ second:[UInt8])throws->MTLTexture {
  var pixels=[UInt8](repeating:255,count:2048*128*4)
  for y in 0..<128{for x in 0..<256{let value=x<128 ? first:second,p=(y*2048+x)*4;for k in 0..<4{pixels[p+k]=value[k]}}}
  return try texture(2048,128,pixels)
 }
 private func mesh(_ texture:MTLTexture,_ z:Float,_ layer:Float=0)throws->Mesh {
  let positions:[SIMD4<Float>]=[SIMD4(-1,-1,z,1),SIMD4(3,-1,z,1),SIMD4(-1,3,z,1)]
  let vertices=positions.map{NativeVertex(position:$0,uvLayer:SIMD4(0.5,0.5,layer,0),tint:SIMD4(repeating:1),dusk:SIMD4(repeating:1))},indices:[UInt32]=[0,1,2]
  guard let v=device.makeBuffer(bytes:vertices,length:vertices.count*MemoryLayout<NativeVertex>.stride),let i=device.makeBuffer(bytes:indices,length:12)else{throw Failed.check("mesh buffers")}
  return Mesh(vertices:v,indices:i,indexCount:3,atlas:texture)
 }
 private func uniforms(_ mesh:Mesh)->Uniforms {
  Uniforms(viewProjection:matrix_identity_float4x4,settings:SIMD4(Float(mesh.atlas.width),Float(mesh.atlas.height),0,128))
 }
 private func render(background:SIMD4<Double>=SIMD4(0,0,0,1),_ body:(MTLRenderCommandEncoder)throws->Void)throws->SIMD4<UInt8> {
  let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:1,height:1,mipmapped:false)
  d.storageMode=device.hasUnifiedMemory ? .shared:.managed;d.usage = .renderTarget
  let z=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:1,height:1,mipmapped:false);z.storageMode = .private;z.usage = .renderTarget
  guard let target=device.makeTexture(descriptor:d),let depthTexture=device.makeTexture(descriptor:z),let command=queue.makeCommandBuffer()else{throw Failed.check("render allocation")}
  let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
  pass.colorAttachments[0].clearColor=MTLClearColorMake(background.x,background.y,background.z,background.w)
  pass.depthAttachment.texture=depthTexture;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
  guard let e=command.makeRenderCommandEncoder(descriptor:pass)else{throw Failed.check("render encoder")}
  e.setCullMode(.none);e.setDepthStencilState(depth);try body(e);e.endEncoding()
  if target.storageMode == .managed{guard let b=command.makeBlitCommandEncoder()else{throw Failed.check("readback encoder")};b.synchronize(resource:target);b.endEncoding()}
  command.commit();command.waitUntilCompleted();try check(command.status == .completed,"GPU completion: \(String(describing:command.error))")
  var bytes=[UInt8](repeating:0,count:4);bytes.withUnsafeMutableBytes{target.getBytes($0.baseAddress!,bytesPerRow:4,from:MTLRegionMake2D(0,0,1,1),mipmapLevel:0)};renders+=1
  return SIMD4(bytes[2],bytes[1],bytes[0],bytes[3])
 }
 private func close(_ actual:SIMD4<UInt8>,_ expected:SIMD4<UInt8>,_ name:String)throws {
  try check((0..<4).allSatisfy{abs(Int(actual[$0])-Int(expected[$0]))<=3},"\(name): actual \(actual), expected \(expected)")
 }
 private func source(_ triangles:Int=1,_ blend:Int=3)throws {
  let document:[String:Any]=["detail":["cell":128,"columns":16,"sharp":256,"sharpColumns":8,"cells":[["cell":0,"layers":2,"sharp":1,"triangles":triangles,"blend":blend]]]]
  worldSharpManifest=try NativeWorldSharpManifest(data:JSONSerialization.data(withJSONObject:document))
  worldSharpBase["c0"] = .init(layers:2,mapping:[1,0],source:"current",indices:3,center:SIMD3(0,0,0.5))
 }
 func exercise(_ library:MTLLibrary)throws->[String:Any] {
  let t=try atlas([255,0,0,128],[0,255,0,64]),solid=try mesh(t,0.8),clear=try mesh(t,0.2,1)
  try source()
  let opaque=try render{e in try check(stageWorldSurface(name:"c0",mesh:solid,matrix:matrix_identity_float4x4,encoder:e),"Actual source/geometry stage admits solid prefix")}
  try close(opaque,SIMD4(255,0,0,255),"Solid phase cuts out source alpha but writes opaque color")
  try check(deferredWorldSurfaces.isEmpty,"Empty clear suffix does not enqueue a draw")
  let oldDescriptor=MTLRenderPipelineDescriptor();oldDescriptor.vertexFunction=library.makeFunction(name:"worldVertex");oldDescriptor.fragmentFunction=library.makeFunction(name:"worldFragment")
  oldDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm;oldDescriptor.depthAttachmentPixelFormat = .depth32Float
  oldDescriptor.colorAttachments[0].isBlendingEnabled=true;oldDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha;oldDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
  let oldPipeline=try device.makeRenderPipelineState(descriptor:oldDescriptor)
  let legacy=try render{e in
   var u=uniforms(solid);e.setRenderPipelineState(oldPipeline);e.setVertexBuffer(solid.vertices,offset:0,index:0);e.setVertexBytes(&u,length:MemoryLayout<Uniforms>.stride,index:1);e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:1);e.setFragmentTexture(t,index:0);e.drawIndexedPrimitives(type:.triangle,indexCount:3,indexType:.uint32,indexBuffer:solid.indices,indexBufferOffset:0)
  }
  try check(abs(Int(legacy.x)-128)<=3 && legacy != opaque,"Preserved legacy shader reproduces incorrectly translucent solid")
  worldSharpSource="retired"
  _=try render{e in try check(!stageWorldSurface(name:"c0",mesh:solid,matrix:matrix_identity_float4x4,encoder:e),"Retired source cannot publish an indexed phase")};worldSharpSource="current"
  try source(2,3)
  _=try render{e in try check(!stageWorldSurface(name:"c0",mesh:solid,matrix:matrix_identity_float4x4,encoder:e),"Different geometry count cannot publish metadata ranges")};try source()
  let combined=try render{e in
   try check(encodeWorldSurface(mesh:solid,range:.init(start:0,count:3),uniforms:uniforms(solid),native:nil,clear:false,encoder:e),"Solid draw")
   try check(encodeWorldSurface(mesh:clear,range:.init(start:0,count:3),uniforms:uniforms(clear),native:nil,clear:true,encoder:e),"Clear draw")
  }
  try close(combined,SIMD4(191,64,0,255),"Clear phase composites over solid color")
  let low=try mesh(atlas([0,255,0,16],[0,0,0,0]),0.2)
  let faint=try render{e in _=encodeWorldSurface(mesh:low,range:.init(start:0,count:3),uniforms:uniforms(low),native:nil,clear:true,encoder:e)}
  try close(faint,SIMD4(0,16,0,255),"Clear opacity between .03 and .1 survives its own threshold")
  let blue=try mesh(atlas([0,0,255,255],[0,0,0,0]),0.4)
  let noDepthWrite=try render{e in
   _=encodeWorldSurface(mesh:clear,range:.init(start:0,count:3),uniforms:uniforms(clear),native:nil,clear:true,encoder:e)
   _=encodeWorldSurface(mesh:blue,range:.init(start:0,count:3),uniforms:uniforms(blue),native:nil,clear:false,encoder:e)
  }
  try close(noDepthWrite,SIMD4(0,0,255,255),"Clear surface did not write depth in front of a later sentinel")
  let probeDescriptor=oldDescriptor.copy() as! MTLRenderPipelineDescriptor;probeDescriptor.fragmentFunction=library.makeFunction(name:"vehiclePaintABIProbe")
  probeDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one;probeDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
  let vehiclePipeline=try device.makeRenderPipelineState(descriptor:probeDescriptor)
  let vt=try texture(1,1,[255,255,255,255]),vm=try mesh(vt,0.5)
  let vehicle=TransparentVehicleDraw(mesh:vm,part:.init(paint:SIMD4(0,0,1,0.5)),uniforms:uniforms(vm),pipeline:vehiclePipeline,painted:false,depth:0.5,bindTextures:{e in e.setFragmentTexture(vt,index:0);return true})
  let far=try mesh(atlas([255,0,0,64],[0,0,0,0]),0.8),near=try mesh(atlas([0,255,0,64],[0,0,0,0]),0.2)
  // Deliberately reverse insertion; actual production ordering interleaves a
  // native-image vehicle, whose float4 paint follows a uint world phase at3.
  deferredWorldSurfaces=[.init(mesh:near,range:.init(start:0,count:3),uniforms:uniforms(near),native:nil,depth:0.2),.init(mesh:far,range:.init(start:0,count:3),uniforms:uniforms(far),native:nil,depth:0.8)]
  let mixed=try render(background:SIMD4(1,1,1,1)){e in encodeWorldAndVehicleSurfaces(vehicles:[vehicle],encoder:e)}
  try close(mixed,SIMD4(96,135,167,255),"World/vehicle back-to-front composition and per-packet paint ABI")
  let image=try texture(2048,256,Array(repeating:[UInt8(0),0,255,128],count:2048*256).flatMap{$0})
  let layout=try NativeWorldSharpLayout(baseLayers:2,mapping:[1,0],sharpLayers:1,width:2048,height:256)
  let native=try NativeWorldSharpTextures(device:device,queue:queue,atlas:image,layout:layout);try native.finishUpload()
  let sharp=try render{e in
   _=encodeWorldSurface(mesh:solid,range:.init(start:0,count:3),uniforms:uniforms(solid),native:native,clear:false,encoder:e)
   _=encodeWorldSurface(mesh:clear,range:.init(start:0,count:3),uniforms:uniforms(clear),native:native,clear:true,encoder:e)
  }
  try close(sharp,SIMD4(0,64,191,255),"HD opaque prefix and unmapped base transparent suffix coexist")
  _=try render{e in for range in [NativeWorldDrawPlan.Range(start:-1,count:3),.init(start:1,count:3),.init(start:0,count:4),.init(start:Int.max,count:3)] {try check(!encodeWorldSurface(mesh:solid,range:range,uniforms:uniforms(solid),native:nil,clear:false,encoder:e),"Invalid GPU range rejected before encoding")}}
  return ["status":"PASS","gpu":"PASS","device":device.name,"checks":checks,"renders":renders,"scope":"Authored surfaces, actual production range/encoder/order/pipeline statements, real Metal; no installed scene, water/particle sorting or retail claim"]
 }
}
@main private enum Probe {
 static func main()throws {
  let folder=URL(fileURLWithPath:CommandLine.arguments[1]);var result:[String:Any]
  do {
   if let device=MTLCopyAllDevices().first(where:{$0.isLowPower}) ?? MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() {
    let library=try device.makeLibrary(source:String(contentsOf:folder.appendingPathComponent("production.metal"),encoding:.utf8),options:nil)
    guard let h=Harness(device:device,queue:queue,library:library)else{throw Failed.check("Actual production pipeline/depth setup")};result=try h.exercise(library)
   }else{try check(!CommandLine.arguments.contains("--require-gpu"),"Metal device required");result=["status":"PASS","gpu":"UNAVAILABLE","scope":"Compiled source only; no GPU claim"]}
  }catch{result=["status":"FAIL","checks":checks,"renders":renders,"error":String(describing:error)]}
  let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]);try data.write(to:folder.appendingPathComponent("report.json"));print(String(data:data,encoding:.utf8)!);if result["status"] as?String != "PASS"{exit(1)}
 }
}
