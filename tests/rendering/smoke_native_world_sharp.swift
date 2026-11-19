// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import MetalKit
import simd
private enum Failed:Error {case check(String)}
private var checks=0,renders=0
private func check(_ value:Bool,_ name:String)throws{checks+=1;if !value{throw Failed.check(name)}}
private struct Uniforms {
 var viewProjection=matrix_identity_float4x4,settings=SIMD4<Float>(2048,128,0,128)
 var fogColor=SIMD4<Float>(0,0,0,1),fogSettings=SIMD4<Float>(0,100,0,0),tintColor=SIMD4<Float>(repeating:1)
}
private func image(_ device:MTLDevice,_ width:Int,_ height:Int,_ pixels:[UInt8],mips:Bool=false)throws->MTLTexture {
 let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:width,height:height,mipmapped:mips)
 d.storageMode=device.hasUnifiedMemory ? .shared:.managed;d.usage=[.shaderRead,.renderTarget]
 guard let texture=device.makeTexture(descriptor:d)else{throw Failed.check("texture allocation")}
 pixels.withUnsafeBytes{texture.replace(region:MTLRegionMake2D(0,0,width,height),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:width*4)};return texture
}
private func pipeline(_ device:MTLDevice,_ library:MTLLibrary,_ fragment:String)throws->MTLRenderPipelineState {
 let d=MTLRenderPipelineDescriptor();d.vertexFunction=library.makeFunction(name:"worldVertex");d.fragmentFunction=library.makeFunction(name:fragment);d.colorAttachments[0].pixelFormat = .rgba8Unorm
 return try device.makeRenderPipelineState(descriptor:d)
}
private func draw(device:MTLDevice,queue:MTLCommandQueue,pipeline:MTLRenderPipelineState,base:MTLTexture,
                  images:NativeWorldSharpTextures?,reference:MTLTexture?,layer:Float,uv:SIMD2<Float>,scale:Float)throws->[UInt8] {
 let target=try image(device,16,16,[UInt8](repeating:0,count:16*16*4)),pass=MTLRenderPassDescriptor()
 pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
 guard let command=queue.makeCommandBuffer(),let e=command.makeRenderCommandEncoder(descriptor:pass)else{throw Failed.check("draw encoder")}
 e.setRenderPipelineState(pipeline)
 let positions:[SIMD4<Float>]=[SIMD4(-1,-1,0,1),SIMD4(3,-1,0,1),SIMD4(-1,3,0,1)]
 let uvs=[uv,uv+SIMD2(2*scale,0),uv+SIMD2(0,2*scale)]
 let vertices=(0..<3).map{NativeVertex(position:positions[$0],uvLayer:SIMD4(uvs[$0].x,uvs[$0].y,layer,0),tint:SIMD4(repeating:1),dusk:SIMD4(repeating:1))}
 var u=Uniforms();u.settings.y=Float(base.height)
 vertices.withUnsafeBytes{e.setVertexBytes($0.baseAddress!,length:$0.count,index:0)}
 e.setVertexBytes(&u,length:MemoryLayout<Uniforms>.stride,index:1);e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:1);e.setFragmentTexture(base,index:0)
 if let images{try images.bind(encoder:e,queue:queue)}
 if let reference{e.setFragmentTexture(reference,index:0)}
 e.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:3);e.endEncoding()
 if target.storageMode == .managed {guard let blit=command.makeBlitCommandEncoder()else{throw Failed.check("readback encoder")};blit.synchronize(resource:target);blit.endEncoding()}
 command.commit();command.waitUntilCompleted();try check(command.status == .completed,"Actual GPU render completed")
 var bytes=[UInt8](repeating:0,count:16*16*4);bytes.withUnsafeMutableBytes{target.getBytes($0.baseAddress!,bytesPerRow:64,from:MTLRegionMake2D(0,0,16,16),mipmapLevel:0)};renders+=1;return bytes
}
private final class Task:NativeResourceTask {
 var resumed=0,cancelled=0
 func resume(){resumed+=1};func cancel(){cancelled+=1}
}
@main private enum Probe {
 static func main()throws {
  let folder=URL(fileURLWithPath:CommandLine.arguments[1]);var report:[String:Any]=[:]
  do {
   guard let device=(MTLCopyAllDevices().first(where:{$0.isLowPower}) ?? MTLCreateSystemDefaultDevice()),let queue=device.makeCommandQueue()else{
    try check(!CommandLine.arguments.contains("--require-gpu"),"Metal device required")
    let skipped:[String:Any]=["status":"PASS","gpu":"UNAVAILABLE","checks":checks,"renders":0,"scope":"Compiled native code; no GPU/render claim"]
    try JSONSerialization.data(withJSONObject:skipped,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("report.json"))
    print("SKIP GPU unavailable; no render claim");return
   }
   let layout=try NativeWorldSharpLayout(baseLayers:4,mapping:[0,2,1,3],sharpLayers:3,width:2048,height:256)
   let png=try Data(contentsOf:folder.appendingPathComponent("authored.hd.png"))
   try check(layout.acceptsPNG(png),"Actual independently produced PNG accepted")
   let atlas=try MTKTextureLoader(device:device).newTexture(data:png,options:[.SRGB:false,.generateMipmaps:false])
   let images=try NativeWorldSharpTextures(device:device,queue:queue,atlas:atlas,layout:layout);try images.finishUpload()
   try check(images.allocatedBytes<=NativeWorldSharpLayout.maximumGPUBytes && images.texture.mipmapLevelCount==9,"Actual bounded mipmapped image family")
   let source=try String(contentsOf:folder.appendingPathComponent("production.metal"),encoding:.utf8)
   let library=try device.makeLibrary(source:source,options:nil),sharp=try pipeline(device,library,"worldSharpFragment"),basePipeline=try pipeline(device,library,"worldFragment"),refPipeline=try pipeline(device,library,"independentSharpReference")
   let base=try image(device,2048,128,[UInt8](repeating:127,count:2048*128*4))
   var isolated:[MTLTexture]=[]
   for n in 0..<3 {
    let pixels=[UInt8](try Data(contentsOf:folder.appendingPathComponent("tile-\(n).rgba")))
    let texture=try image(device,256,256,pixels,mips:true);isolated.append(texture)
    let outputDescriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:images.texture.pixelFormat,width:256,height:256,mipmapped:false)
    outputDescriptor.storageMode=device.hasUnifiedMemory ? .shared:.managed
    guard let output=device.makeTexture(descriptor:outputDescriptor),let c=queue.makeCommandBuffer(),let b=c.makeBlitCommandEncoder()else{throw Failed.check("slice readback allocation")}
    b.copy(from:images.texture,sourceSlice:n,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:256,height:256,depth:1),to:output,destinationSlice:0,destinationLevel:0,destinationOrigin:MTLOrigin(x:0,y:0,z:0))
    b.generateMipmaps(for:texture)
    if output.storageMode == .managed{b.synchronize(resource:output)}
    b.endEncoding();c.commit();c.waitUntilCompleted();try check(c.status == .completed,"Slice and independent mip commands complete")
    var actual=[UInt8](repeating:0,count:pixels.count);actual.withUnsafeMutableBytes{output.getBytes($0.baseAddress!,bytesPerRow:1024,from:MTLRegionMake2D(0,0,256,256),mipmapLevel:0)}
    if output.pixelFormat == .bgra8Unorm{for p in stride(from:0,to:actual.count,by:4){actual.swapAt(p,p+2)}}
    try check(actual==pixels,"All original RGBA pixels preserved in mapped slice \(n)")
   }
   for (baseLayer,selected) in [(1,1),(2,0),(3,2)] {
    for scale:Float in [0,1,4,32] {for uv in [SIMD2<Float>(0,0),SIMD2(-1,-0.001),SIMD2(0.999,1),SIMD2(0.375,0.625)] {
     let got=try draw(device:device,queue:queue,pipeline:sharp,base:base,images:images,reference:nil,layer:Float(baseLayer),uv:uv,scale:scale)
     let reference=try draw(device:device,queue:queue,pipeline:refPipeline,base:base,images:nil,reference:isolated[selected],layer:0,uv:uv,scale:scale)
     try check(zip(got,reference).allSatisfy{abs(Int($0)-Int($1))<=2},"Independent hardware image reference, mapped layer \(baseLayer), scale \(scale), UV \(uv)")
    }}
   }
   for uv in [SIMD2<Float>(0,0),SIMD2(-0.2,1.2)] {
    let got=try draw(device:device,queue:queue,pipeline:sharp,base:base,images:images,reference:nil,layer:0,uv:uv,scale:1)
    let reference=try draw(device:device,queue:queue,pipeline:basePipeline,base:base,images:nil,reference:nil,layer:0,uv:uv,scale:1)
    try check(got==reference,"Zero mapping retains exact existing base shader")
   }
   var rejected=false;do{_ = try NativeWorldSharpTextures(device:device,queue:queue,atlas:atlas,layout:layout,maximumAllocationBytes:1)}catch{rejected=true};try check(rejected,"Budget enforced before upload")
   guard let otherQueue=device.makeCommandQueue(),let c=queue.makeCommandBuffer()else{throw Failed.check("queue probe")}
   let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=base
   guard let e=c.makeRenderCommandEncoder(descriptor:pass)else{throw Failed.check("queue encoder")}
   rejected=false;do{try images.bind(encoder:e,queue:otherQueue)}catch{rejected=true};e.endEncoding();try check(rejected,"Different command queue cannot consume this upload")
   let loader=NativeWorldSharpLoader(),url=URL(string:"http://127.0.0.1:1/game/world/c1.hd.png")!
   weak var releasedTask:Task?;var requestedLimit=0
   NativeResourceTransport.install({_,_ in fatalError("unbounded transport used")},bounded:{request,limit,complete in
    requestedLimit=limit;let task=Task();releasedTask=task
    complete(png,HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil),nil)
    return task
   })
   let ticket=NativeWorldSharpTicket();var delivered:Result<NativeWorldSharpTextures,Error>?
   loader.load(url:url,layout:layout,device:device,queue:queue,ticket:ticket){try! check(Thread.isMainThread,"Publication delivered on main thread");delivered=$0}
   let end=Date().addingTimeInterval(20)
   while delivered==nil && Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
   guard case .success?=delivered else{throw Failed.check("Actual loader failed: \(String(describing:delivered))")}
   try check(requestedLimit==64*1024*1024 && releasedTask==nil,"Inline bounded transport completion releases task ownership")
   report=["status":"PASS","gpu":"PASS","device":device.name,"checks":checks,"renders":renders,"allocatedBytes":images.allocatedBytes,"originalGameFilesUsed":false]
  }catch{report=["status":"FAIL","error":String(describing:error),"checks":checks,"renders":renders]}
  let bytes=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]);try bytes.write(to:folder.appendingPathComponent("report.json"));print(String(data:bytes,encoding:.utf8)!)
  if report["status"] as?String != "PASS"{exit(1)}
 }
}
