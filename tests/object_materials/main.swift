// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal
import simd
typealias M=NativeSAMPObjectMaterials
var checks=0
func check(_ value:@autoclosure()->Bool,_ message:String){checks+=1;if !value(){fatalError("object material: \(message)")}}
func fails(_ message:String,_ body:()throws->Void){do{try body();fatalError("expected failure: \(message)")}catch is M.Failure{checks+=1}catch{fatalError("wrong failure \(message): \(error)")}}
func text(_ string:String="TEST",size:UInt8=90,fontSize:UInt8=28,bold:Bool=false,fg:UInt32=0xffffffff,bg:UInt32=0,align:UInt8=0,font:String="Arial")->M.Text{
 M.Text(size:size,font:font,fontSize:fontSize,bold:bold,foregroundARGB:fg,backgroundARGB:bg,alignment:align,text:string)
}
func material(_ t:M.Text)->NativeSAMPObjects.Material{.text(size:t.size,font:t.font,fontSize:t.fontSize,bold:t.bold,foregroundARGB:t.foregroundARGB,backgroundARGB:t.backgroundARGB,alignment:t.alignment,text:t.text)}
func bounds(_ image:M.Image)->(Int,Int,Int,Int){
 let pixels=[UInt8](image.rgba8);var left=image.width,right = -1,top=image.height,bottom = -1
 for y in 0..<image.height{for x in 0..<image.width where pixels[(y*image.width+x)*4+3]>0{left=min(left,x);right=max(right,x);top=min(top,y);bottom=max(bottom,y)}}
 return(left,top,right,bottom)
}
let dimensions=[(32,32),(64,32),(64,64),(128,32),(128,64),(128,128),(256,32),(256,64),(256,128),(256,256),(512,64),(512,128),(512,256),(512,512)]
for (index,expected) in dimensions.enumerated(){
 let size=UInt8((index+1)*10),d=try M.dimensions(size),image=try M.rasterize(text("",size:size,bg:0xffff0000))
 check(d.width==expected.0 && d.height==expected.1,"published material size\(size)")
 check(image.width==d.width && image.height==d.height && image.rgba8.count==d.width*d.height*4,"original pixel dimensions")
 check(stride(from:0,to:image.rgba8.count,by:4).allSatisfy{image.rgba8[$0]==255 && image.rgba8[$0+1]==0 && image.rgba8[$0+2]==0 && image.rgba8[$0+3]==255},"sRGB red background is exact; no device-color-space shift")
}
check(M.argb(0x80402010)==SIMD4<Float>(64,32,16,128)/255,"ARGB text channel order")
check(M.abgr(0x80402010)==SIMD4<Float>(16,32,64,128)/255,"ABGR wire tint channel order")
let half=try M.rasterize(text("",size:10,bg:0x80302010))
check(Array(half.rgba8.prefix(4))==[48,32,16,128],"CoreGraphics premultiplication converted back to straight alpha")
let clear=try M.rasterize(text("",size:10));check(clear.rgba8.allSatisfy{$0==0} && clear.containsTransparency,"transparent background")
let left=try M.rasterize(text()),center=try M.rasterize(text(align:1)),right=try M.rasterize(text(align:2))
let a=bounds(left),b=bounds(center),c=bounds(right)
check(a.1>=0 && a.1<32 && a.3<60,"top-down native CoreText orientation")
check(a.0<b.0 && b.0<c.0 && abs((b.0+b.2)/2-128)<4 && c.2>=251,"left/center/right alignment")
let wrapped=try M.rasterize(text("ONE TWO THREE FOUR FIVE SIX SEVEN",size:60,fontSize:22))
check(wrapped.lineCount>1 && bounds(wrapped).3>30,"word wrapping")
let newline=try M.rasterize(text("A\nB"));check(newline.lineCount==2,"explicit newline")
let bold=try M.rasterize(text(bold:true));check(bold.actualFont != left.actualFont && bold.rgba8 != left.rgba8,"native bold font face")
let alpha=try M.rasterize(text("H",fg:0x80204080))
check(alpha.rgba8.enumerated().filter{$0.offset%4==3}.map(\.element).max()!<=128,"requested font alpha")
let colored=try M.rasterize(text("{FF0000}I {0000FF}I",fontSize:36))
var red=0,blue=0
let pixels=[UInt8](colored.rgba8)
for i in stride(from:0,to:pixels.count,by:4) where pixels[i+3]>32{if pixels[i]>200 && pixels[i+2]<10{red+=1};if pixels[i+2]>200 && pixels[i]<10{blue+=1}}
check(red>0 && blue>0,"embedded RGB colors")
fails("invalid size"){_ = try M.dimensions(15)}
fails("invalid alignment"){_ = try M.rasterize(text(align:3))}
fails("zero font size"){_ = try M.rasterize(text(fontSize:0))}
fails("unavailable font isn't silently substituted"){_ = try M.rasterize(text(font:"ZGTA_Font_That_Does_Not_Exist_0123"))}
var small=M.Limits();small.cacheBytes=1;fails("pixel budget"){_ = try M.rasterize(text(),limits:small)}
small=M.Limits();small.textUTF8Bytes=4;fails("UTF8 text budget"){_ = try M.rasterize(text("12345"),limits:small)}
let preview=try M.rasterize(text("ZGTA SA\n{FF8200}Native object materials\n{FFFFFF}Text, wrapping, ARGB alpha and exact named textures.",size:130,fontSize:28,bold:true,bg:0xff102030))
try preview.rgba8.write(to:URL(fileURLWithPath:CommandLine.arguments[2]).appendingPathComponent("text-preview.rgba"))

guard let device=MTLCreateSystemDefaultDevice() else{fatalError("physical Metal device required for material integration tests")}
let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:2,height:2,mipmapped:false)
descriptor.storageMode = .shared;descriptor.usage = .shaderRead
let checker=device.makeTexture(descriptor:descriptor)!
let colors:[UInt8]=[255,0,0,255,0,255,0,255,0,0,255,255,255,255,255,255]
colors.withUnsafeBytes{checker.replace(region:MTLRegionMake2D(0,0,2,2),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:8)}
let samplerDescriptor=MTLSamplerDescriptor();samplerDescriptor.minFilter = .nearest;samplerDescriptor.magFilter = .nearest;samplerDescriptor.sAddressMode = .clampToEdge;samplerDescriptor.tAddressMode = .clampToEdge
let nearest=device.makeSamplerState(descriptor:samplerDescriptor)!
var lookups:[M.TextureRequest]=[]
let owner=try M.Owner(device:device,textureResolver:{request in
 lookups.append(request)
 guard request.model==19379,request.dictionary=="known",request.texture=="checker" else{return nil}
 return M.Texture(image:checker,sampler:nearest,containsTransparency:false)
})
let named=try owner.resolve(.texture(model:19379,dictionary:"known",texture:"checker",abgr:0))
check(named.texture===checker && named.sampler===nearest && named.materialColor==nil && !named.ignoreVertexColor,"exact texture + color0 inheritance")
fails("no unrelated-dictionary guessing"){_ = try owner.resolve(.texture(model:19379,dictionary:"other",texture:"checker",abgr:0))}
let colorOnly=try owner.resolve(.texture(model:.max,dictionary:"none",texture:"none",abgr:0xff0000ff))
check(colorOnly.texture==nil && colorOnly.materialColor==SIMD4<Float>(1,0,0,1) && colorOnly.ignoreVertexColor,"color-only sentinel and wire ABGR")
let count=lookups.count;_ = try owner.resolve(.texture(model:0,dictionary:"none",texture:"none",abgr:0x800000ff))
check(lookups.count==count,"alpha special case doesn't guess a texture")
let textValue=text("",size:10,bg:0x800000ff)
let resolvedText=try owner.resolve(material(textValue)),again=try owner.resolve(material(textValue))
check(resolvedText.texture===again.texture && resolvedText.blend==true && resolvedText.ignoreVertexColor,"bounded text texture cache")
var uploaded=[UInt8](repeating:0,count:32*32*4)
resolvedText.texture!.getBytes(&uploaded,bytesPerRow:32*4,from:MTLRegionMake2D(0,0,32,32),mipmapLevel:0)
let cpu=try M.rasterize(textValue);check(Data(uploaded)==cpu.rgba8,"native text upload preserves straight RGBA")
var bounded=M.Limits();bounded.cacheEntries=2;bounded.fontEntries=2
let lru=try M.Owner(device:device,limits:bounded,textureResolver:{_ in nil})
for size:UInt8 in [12,13,14]{_ = try lru.resolve(material(text("A",size:30,fontSize:size)))}
check(lru.cachedCount==2 && lru.cachedFontCount==2 && lru.cachedBytes<=bounded.cacheBytes,"image/font LRU budgets")
lru.reset();check(lru.cachedCount==0 && lru.cachedFontCount==0 && lru.cachedBytes==0,"reset releases owned material resources")

typealias D=NativeRenderWareDFF
typealias RW=NativeRenderWareModel
let sourceMaterial=D.Material(flags:0,color:SIMD4(0,0,255,255),textureName:nil,maskName:nil,textureFilterAndAddressing:0x1102,surface:nil)
let positions:[SIMD3<Float>]=[SIMD3(-1,-1,0),SIMD3(1,-1,0),SIMD3(-1,1,0),SIMD3(1,1,0)]
let target=D.MorphTarget(boundingSphere:SIMD4(0,0,0,2),positions:positions,normals:[SIMD3<Float>](repeating:SIMD3(0,0,1),count:4))
let geometry=D.Geometry(flags:0,vertexCount:4,textureCoordinates:[[SIMD2(0,0),SIMD2(1,0),SIMD2(0,1),SIMD2(1,1)]],
 prelitColors:[SIMD4<UInt8>](repeating:SIMD4(0,255,0,255),count:4),triangles:[D.Triangle(a:0,b:1,c:2,material:0),D.Triangle(a:2,b:1,c:3,material:0)],materials:[sourceMaterial],morphTargets:[target],skin:nil)
let frame=D.Frame(name:nil,parent:-1,flags:0,localTransform:matrix_identity_float4x4,worldTransform:matrix_identity_float4x4,hierarchy:nil)
let dff=D(version:0,frames:[frame],geometries:[geometry],atomics:[D.Atomic(frame:0,geometry:0,flags:4,unused:0)])
let plan=try RW.prepare(dff:dff,txd:nil),model=try RW.Uploaded(plan:plan,device:device)
let library=try device.makeLibrary(source:String(contentsOfFile:CommandLine.arguments[1],encoding:.utf8),options:nil)
let pipelines=try RW.Pipelines(device:device,library:library,color:.rgba8Unorm)
func render(_ overrides:RW.DrawOverrides)throws->[UInt8]{
 let c=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:4,height:4,mipmapped:false);c.storageMode = .shared;c.usage = .renderTarget
 let z=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:4,height:4,mipmapped:false);z.storageMode = .private;z.usage = .renderTarget
 let color=device.makeTexture(descriptor:c)!,depth=device.makeTexture(descriptor:z)!
 let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=color;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
 pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
 pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.clearDepth=1
 let command=device.makeCommandQueue()!.makeCommandBuffer()!,encoder=command.makeRenderCommandEncoder(descriptor:pass)!
 encoder.setViewport(MTLViewport(originX:0,originY:0,width:4,height:4,znear:0,zfar:1))
 try model.encode(drawIndex:0,encoder:encoder,pipelines:pipelines,viewProjection:matrix_identity_float4x4,modelTransform:matrix_identity_float4x4,overrides:overrides)
 encoder.endEncoding()
 // Copy actual GPU output before CPU assertions; getBytes on a GPU-written
 // discrete-GPU texture can expose its stale CPU-side mapping.
 let readback=device.makeBuffer(length:1024,options:.storageModeShared)!,blit=command.makeBlitCommandEncoder()!
 blit.copy(from:color,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:4,height:4,depth:1),
           to:readback,destinationOffset:0,destinationBytesPerRow:256,destinationBytesPerImage:1024)
 blit.endEncoding();command.commit();command.waitUntilCompleted();check(command.status == .completed,"GPU override command")
 let pointer=readback.contents().assumingMemoryBound(to:UInt8.self);var bytes:[UInt8]=[]
 for row in 0..<4{bytes.append(contentsOf:UnsafeBufferPointer(start:pointer+row*256,count:16))};return bytes
}
let baseline=try render(RW.DrawOverrides())
check(stride(from:0,to:64,by:4).allSatisfy{Array(baseline[$0..<$0+4])==[0,0,0,255]},"default source color/prelit behavior unchanged")
var tint=RW.DrawOverrides();colorOnly.apply(to:&tint)
let tinted=try render(tint)
check(stride(from:0,to:64,by:4).allSatisfy{Array(tinted[$0..<$0+4])==[255,0,0,255]},"ABGR color overrides material and removes baked vertex lighting")
let replacement=try owner.resolve(.texture(model:19379,dictionary:"known",texture:"checker",abgr:0xffffffff))
var draw=RW.DrawOverrides();replacement.apply(to:&draw)
let replaced=try render(draw)
var expected:[UInt8]=[]
for y in 0..<4{for x in 0..<4{let index=((y<2 ? 1:0)*2+x/2)*4;expected.append(contentsOf:colors[index..<index+4])}}
check(replaced==expected,"actual texture and nearest-sampler override bound per draw")
var glyph=RW.DrawOverrides();resolvedText.apply(to:&glyph)
let blended=try render(glyph)
check(stride(from:0,to:64,by:4).allSatisfy{abs(Int(blended[$0+2])-128)<=1 && blended[$0]==0 && blended[$0+1]==0 && abs(Int(blended[$0+3])-128)<=1},"text alpha blends once, with no premultiplied double-darkening")
glyph.blendOverride=false
let unblended=try render(glyph)
check(stride(from:0,to:64,by:4).allSatisfy{Array(unblended[$0..<$0+4])==[0,0,255,128]},"explicit blend override")
print("{\"status\":\"PASS\",\"checks\":\(checks),\"publishedSizes\":14,\"metal\":\"actual offscreen texture/sampler/material/prelit/blend override readback passed\",\"device\":\"\(device.name)\",\"gpuReadback\":\"texture-to-shared-buffer blit; discrete GPU texture CPU mapping may be stale\",\"font\":\"\(left.actualFont)\"}")
