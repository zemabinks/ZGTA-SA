// SPDX-License-Identifier: AGPL-3.0-only
// Independently authored hull/window/rider geometry; no original recording or mesh.
import Foundation
import Metal
import simd

private enum Failure:Error {case assertion(String),unavailable(String)}
private var checks=0
private func require(_ value:Bool,_ name:String)throws {checks+=1;if !value{throw Failure.assertion(name)}}
private let root=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue()else{throw Failure.unavailable("Actual host Metal GPU unavailable")}
let library=try device.makeLibrary(URL:output.appendingPathComponent("production.metallib"))
// ACTUAL_UNIFORMS
private struct NativeVertex {var position:SIMD4<Float>,uvLayer:SIMD4<Float>,tint:SIMD4<Float>,dusk:SIMD4<Float>}
private struct SkinVertex {var point:SIMD4<Float>,bones:SIMD4<UInt32>,weights:SIMD4<Float>}
private struct Formats {let colorPixelFormat:MTLPixelFormat = .bgra8Unorm,depthStencilPixelFormat:MTLPixelFormat = .depth32Float}
private func productionPipeline(_ vertex:MTLFunction,_ fragment:MTLFunction)->MTLRenderPipelineState? {
    let view=Formats()
    // ACTUAL_PIPELINE
    return pipeline
}
private func productionDepth()->(MTLDepthStencilState,MTLDepthStencilState,MTLDepthStencilState)? {
    // ACTUAL_DEPTH
    return(depth,markerDepth,skyDepth)
}
guard let states=productionDepth(),let world=library.makeFunction(name:"worldVertex"),let skin=library.makeFunction(name:"skeletalActorVertex"),let pedFragment=library.makeFunction(name:"worldFragment"),let legacyFragment=library.makeFunction(name:"vehicleFragment"),let paintFragment=library.makeFunction(name:"vehiclePaintFragment"),
      let legacy=productionPipeline(world,legacyFragment),let painted=productionPipeline(world,paintFragment),let skeletal=productionPipeline(skin,pedFragment)else{throw Failure.unavailable("Actual production pipeline unavailable")}
let size=128,height=96,row=128*4
let colorDescription=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:size,height:height,mipmapped:false)
colorDescription.storageMode = .private;colorDescription.usage=[.renderTarget,.shaderRead]
let depthDescription=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:size,height:height,mipmapped:false)
depthDescription.storageMode = .private;depthDescription.usage=[.renderTarget,.shaderRead]
guard let color=device.makeTexture(descriptor:colorDescription),let depth=device.makeTexture(descriptor:depthDescription),let colorOut=device.makeBuffer(length:row*height,options:.storageModeShared),let depthOut=device.makeBuffer(length:row*height,options:.storageModeShared)else{throw Failure.unavailable("Offscreen targets unavailable")}
var palette=matrix_identity_float4x4
let paletteBuffer=device.makeBuffer(bytes:&palette,length:64,options:.storageModeShared)!
private struct Mesh {let vertices:MTLBuffer,skin:MTLBuffer,indices:MTLBuffer,count:Int}
private func mesh(_ rectangles:[SIMD4<Float>],z:Float,tint:SIMD3<Float>,alpha:Float)->Mesh {
    var vertices:[NativeVertex]=[],skins:[SkinVertex]=[],indices:[UInt32]=[]
    for r in rectangles {
        let start=UInt32(vertices.count)
        for point in [SIMD2(r.x,r.y),SIMD2(r.z,r.y),SIMD2(r.z,r.w),SIMD2(r.x,r.w)] {
            let p=SIMD4(point.x,point.y,z,Float(1)),c=SIMD4(tint,alpha)
            vertices.append(.init(position:p,uvLayer:SIMD4(0.4,0.4,0,0),tint:c,dusk:c))
            skins.append(.init(point:p,bones:.zero,weights:SIMD4(1,0,0,0)))
        }
        indices += [0,1,2,0,2,3].map{start+UInt32($0)}
    }
    return .init(vertices:device.makeBuffer(bytes:vertices,length:vertices.count*MemoryLayout<NativeVertex>.stride,options:.storageModeShared)!,skin:device.makeBuffer(bytes:skins,length:skins.count*MemoryLayout<SkinVertex>.stride,options:.storageModeShared)!,indices:device.makeBuffer(bytes:indices,length:indices.count*4,options:.storageModeShared)!,count:indices.count)
}
private let hull=mesh([SIMD4(-1,-1,-0.78,1),SIMD4(0.78,-1,1,1),SIMD4(-0.78,-1,0.78,-0.45),SIMD4(-0.78,0.55,0.78,1)],z:0.25,tint:SIMD3(0,0,1),alpha:1)
private let own=mesh([SIMD4(-0.92,-0.8,-0.1,0.4)],z:0.6,tint:SIMD3(1,0,0),alpha:1)
private let driver=mesh([SIMD4(0.1,-0.8,0.92,0.4)],z:0.6,tint:SIMD3(0,1,0),alpha:1)
private var textureCache:[UInt8:MTLTexture]=[:]
private func atlas(_ alpha:UInt8)->MTLTexture {
    if let value=textureCache[alpha]{return value}
    let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:128,height:128,mipmapped:false)
    d.usage = .shaderRead;d.storageMode=device.hasUnifiedMemory ? .shared:.managed
    let value=device.makeTexture(descriptor:d)!
    let pixel:[UInt8]=[255,255,255,alpha]
    let bytes:[UInt8]=Array(repeating:pixel,count:128*128).flatMap{$0}
    value.replace(region:MTLRegionMake2D(0,0,128,128),mipmapLevel:0,withBytes:bytes,bytesPerRow:512)
    textureCache[alpha]=value;return value
}
private enum Mode {case write,readOnly,always}
private struct Draw {let name:String,mode:Mode;var alphaTest:Float=0}
private struct Image {
    let bgra:[UInt8],depth:[Float]
    func at(_ x:Float,_ y:Float)->[Int] {
        let i=(min(height-1,max(0,Int((1-y)*Float(height)/2)))*size+min(size-1,max(0,Int((x+1)*Float(size)/2))))*4
        return[Int(bgra[i+2]),Int(bgra[i+1]),Int(bgra[i]),Int(bgra[i+3])]
    }
    func z(_ x:Float,_ y:Float)->Float{depth[min(height-1,max(0,Int((1-y)*Float(height)/2)))*size+min(size-1,max(0,Int((x+1)*Float(size)/2)))]}
}
private final class ProductionDeferredCarrier {
    struct Mesh {let vertices:MTLBuffer,indices:MTLBuffer,indexCount:Int,atlas:MTLTexture}
    struct TransparentVehicleDraw {let mesh:Mesh,part:NativeVehicleRig.Draw,uniforms:Uniforms,pipeline:MTLRenderPipelineState;let painted:Bool,depth:Float}
    let depth:MTLDepthStencilState,pipeline:MTLRenderPipelineState
    init(depth:MTLDepthStencilState,pipeline:MTLRenderPipelineState){self.depth=depth;self.pipeline=pipeline}
    // ACTUAL_DEFERRED_ENCODER
    func encode(_ packets:[TransparentVehicleDraw],encoder:MTLRenderCommandEncoder){encodeTransparentVehicles(packets,encoder:encoder)}
}
private func render(_ draws:[Draw],alpha:Float,textureAlpha:UInt8=255,paint:Bool=false,production:Bool=false)->Image {
    let window=mesh([SIMD4(-0.78,-0.45,0.78,0.55)],z:0.25,tint:SIMD3(0.12,0.3,0.45),alpha:alpha)
    let farWindow=mesh([SIMD4(-0.78,-0.45,0.78,0.55)],z:0.4,tint:SIMD3(0.45,0.3,0.12),alpha:alpha)
    let meshes=["own":own,"driver":driver,"hull":hull,"glass":window,"glassFar":farWindow]
    let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=color;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor=MTLClearColorMake(12/255.0,18/255.0,25/255.0,1)
    pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .store;pass.depthAttachment.clearDepth=1
    let command=queue.makeCommandBuffer()!,encoder=command.makeRenderCommandEncoder(descriptor:pass)!
    encoder.setCullMode(.none);encoder.setViewport(MTLViewport(originX:0,originY:0,width:Double(size),height:Double(height),znear:0,zfar:1))
    for draw in draws where !production || !draw.name.hasPrefix("glass") {
        let m=meshes[draw.name]!,rider=draw.name=="own" || draw.name=="driver"
        encoder.setRenderPipelineState(rider ? skeletal:paint ? painted:legacy)
        encoder.setDepthStencilState(draw.mode == .write ? states.0:draw.mode == .readOnly ? states.1:states.2)
        var u=Uniforms(viewProjection:matrix_identity_float4x4,settings:SIMD4(128,128,0,128))
        u.fogSettings.z=0
        encoder.setVertexBuffer(m.vertices,offset:0,index:0);encoder.setVertexBytes(&u,length:MemoryLayout<Uniforms>.stride,index:1);encoder.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:1)
        encoder.setFragmentTexture(atlas(draw.name.hasPrefix("glass") ? textureAlpha:255),index:0)
        if rider {encoder.setVertexBuffer(m.skin,offset:0,index:2);encoder.setVertexBuffer(paletteBuffer,offset:0,index:3)}
        else {
            var material=SIMD4<Float>(-1,0,1,draw.alphaTest),paint=SIMD4<Float>(1,1,1,0)
            encoder.setFragmentBytes(&material,length:16,index:2);encoder.setFragmentBytes(&paint,length:16,index:3)
        }
        encoder.drawIndexedPrimitives(type:.triangle,indexCount:m.count,indexType:.uint32,indexBuffer:m.indices,indexBufferOffset:0)
    }
    if production {
        let carrier=ProductionDeferredCarrier(depth:states.0,pipeline:legacy)
        let packets=draws.filter{$0.name.hasPrefix("glass")}.map{draw->ProductionDeferredCarrier.TransparentVehicleDraw in
            let m=meshes[draw.name]!,center=SIMD3<Float>(0,0.05,draw.name=="glassFar" ? 0.4:0.25)
            let part=NativeVehicleRig.Draw(start:0,count:m.count,node:0,transform:matrix_identity_float4x4,
                layerOverride:-1,emissive:false,scorched:false,alphaTest:draw.alphaTest,transparent:true,sortCenter:center)
            let u=Uniforms(viewProjection:matrix_identity_float4x4,settings:SIMD4(128,128,0,128))
            return .init(mesh:.init(vertices:m.vertices,indices:m.indices,indexCount:m.count,atlas:atlas(textureAlpha)),
                part:part,uniforms:u,pipeline:paint ? painted:legacy,painted:paint,
                depth:NativeVehicleRig.projectedDepth(center,matrix:u.viewProjection))
        }
        carrier.encode(packets,encoder:encoder)
    }
    encoder.endEncoding();let blit=command.makeBlitCommandEncoder()!
    for (texture,buffer) in [(color,colorOut),(depth,depthOut)] {
        blit.copy(from:texture,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:size,height:height,depth:1),to:buffer,destinationOffset:0,destinationBytesPerRow:row,destinationBytesPerImage:row*height)
    }
    blit.endEncoding();command.commit();command.waitUntilCompleted()
    precondition(command.status == .completed && command.error==nil,"Actual Metal command failed")
    return Image(bgra:Array(UnsafeBufferPointer(start:colorOut.contents().assumingMemoryBound(to:UInt8.self),count:row*height)),depth:Array(UnsafeBufferPointer(start:depthOut.contents().assumingMemoryBound(to:Float.self),count:size*height)))
}
private func d(_ name:String,_ mode:Mode = .write,_ test:Float=0)->Draw{Draw(name:name,mode:mode,alphaTest:test)}
private func close(_ a:[Int],_ b:[Int],_ tolerance:Int=2)->Bool{zip(a,b).allSatisfy{abs($0-$1)<=tolerance}}
private func save(_ image:Image,_ name:String)throws{try Data(image.bgra).write(to:output.appendingPathComponent(name+".bgra"))}
var records:[[String:Any]]=[]
for (label,a) in [("alpha128",Float(128)/255),("alpha102",Float(102)/255),("alpha242",Float(242)/255)] {
    for paint in [false,true] {
        let tag=label+(paint ? "-paint":"-legacy")
        let old=render([d("own"),d("hull"),d("glass"),d("driver")],alpha:a,paint:paint)
        let reversed=render([d("driver"),d("hull"),d("glass"),d("own")],alpha:a,paint:paint)
        let noDriver=render([d("own"),d("hull"),d("glass")],alpha:a,paint:paint)
        let corrected=render([d("own"),d("driver"),d("hull"),d("glass",.readOnly)],alpha:a,paint:paint)
        let phasedWrite=render([d("own"),d("driver"),d("hull"),d("glass")],alpha:a,paint:paint)
        let correctedReversed=render([d("hull"),d("driver"),d("own"),d("glass",.readOnly)],alpha:a,paint:paint)
        let actual=render([d("own"),d("hull"),d("glass"),d("driver")],alpha:a,paint:paint,production:true)
        let markerOnly=render([d("own"),d("hull"),d("glass",.readOnly),d("driver")],alpha:a,paint:paint)
        let blanket=render([d("own"),d("hull",.readOnly),d("glass",.readOnly),d("driver")],alpha:a,paint:paint)
        let opaqueControl=render([d("hull"),d("glass"),d("own"),d("driver")],alpha:1,paint:paint)
        try require(old.bgra==noDriver.bgra,"Legacy vehicle-first driver draw contributes no pixels at all")
        try require(old.at(-0.4,0) != reversed.at(-0.4,0) && old.at(0.4,0) != reversed.at(0.4,0),"Actual source-alpha/depth path depends on rider draw order")
        try require(actual.bgra==phasedWrite.bgra,"Actual production deferred encoder restores both riders without changing depth writes")
        try require(corrected.bgra==phasedWrite.bgra,"Opaque-then-transparent phase also fixes riders with original transparent depth writes retained")
        try require(corrected.bgra==correctedReversed.bgra,"Opaque-then-translucent phases preserve draw-order independence")
        try require(corrected.at(0.4,0) != old.at(0.4,0),"Deferred alpha allows the previously hidden driver sentinel")
        try require(corrected.at(-0.4,0)==old.at(-0.4,0),"Already visible own passenger blend remains unchanged")
        try require(markerOnly.at(0.4,0) != corrected.at(0.4,0),"Depth-write-off alone misses correct window compositing")
        try require(blanket.at(0.85,0) != corrected.at(0.85,0),"Blanket depth disable leaks driver through opaque hull")
        try require(corrected.at(0.85,0)==old.at(0.85,0) && abs(corrected.z(0.85,0)-0.25)<1e-6,"Opaque hull color and near depth preserved")
        try require(abs(old.z(0,0)-0.25)<1e-6 && corrected.z(0,0)==1,"Only translucent depth writes removed")
        try require(opaqueControl.at(-0.4,0)==opaqueControl.at(0.4,0),"Opaque windows legitimately hide both sentinels")
        for (name,image) in [("old-order",old),("reversed-order",reversed),("deferred",corrected),("deferred-depthwrite",phasedWrite),("actual-production",actual),("marker-only",markerOnly),("blanket-depth-off",blanket),("opaque-control",opaqueControl)]{try save(image,tag+"-"+name)}
        records.append(["tag":tag,"vertexAlpha":a,"oldOwn":old.at(-0.4,0),"oldDriver":old.at(0.4,0),"reversedOwn":reversed.at(-0.4,0),"reversedDriver":reversed.at(0.4,0),"deferredOwn":corrected.at(-0.4,0),"deferredDriver":corrected.at(0.4,0),"markerOnlyDriver":markerOnly.at(0.4,0),"opaqueHull":corrected.at(0.85,0),"blanketHullLeak":blanket.at(0.85,0),"oldWindowDepth":old.z(0,0),"deferredWindowDepth":corrected.z(0,0),"phasedOriginalWriteDepth":phasedWrite.z(0,0)])
    }
}
private let cutout=render([d("hull"),d("glass",.write,0.5),d("own"),d("driver")],alpha:0.4)
private let naked=render([d("hull"),d("own"),d("driver")],alpha:0)
try require(cutout.bgra==naked.bgra && cutout.z(0,0)==1,"Discarded alpha-test texels do not write depth")
private let zero=render([d("own"),d("hull"),d("glass"),d("driver")],alpha:0)
try require(zero.bgra != naked.bgra && zero.z(0,0)==0.25,"Zero alpha without discard still occludes later geometry")
private let texel=render([d("own"),d("hull"),d("glass"),d("driver")],alpha:1,textureAlpha:128)
private let vertex=render([d("own"),d("hull"),d("glass"),d("driver")],alpha:Float(128)/255)
try require(texel.bgra==vertex.bgra,"Actual texture alpha multiplies vertex alpha in production path")
private let base=[d("own"),d("driver"),d("hull")]
private let sortedWrite=render(base+[d("glassFar"),d("glass")],alpha:Float(128)/255)
private let sortedRead=render(base+[d("glassFar",.readOnly),d("glass",.readOnly)],alpha:Float(128)/255)
private let wrongWrite=render(base+[d("glass"),d("glassFar")],alpha:Float(128)/255)
private let wrongRead=render(base+[d("glass",.readOnly),d("glassFar",.readOnly)],alpha:Float(128)/255)
private let actualSorted=render(base+[d("glass"),d("glassFar")],alpha:Float(128)/255,production:true)
try require(actualSorted.bgra==sortedWrite.bgra,"Actual production encoder sorts near-first input into correct far-to-near compositing")
try require(sortedWrite.bgra==sortedRead.bgra,"Back-to-front translucent order works with either explicit depth-write policy")
try require(wrongWrite.bgra != sortedWrite.bgra,"Near-first translucent depth writes wrongly hide farther transparent surface")
try require(wrongRead.bgra != sortedRead.bgra,"No-depth-write does not replace correct translucent compositing order")
try require(sortedWrite.at(0.85,0)==wrongRead.at(0.85,0) && sortedWrite.z(0.85,0)==0.25,"Multiple transparent surfaces preserve opaque hull occlusion")
for (name,image)in [("two-glass-sorted-write",sortedWrite),("two-glass-sorted-readonly",sortedRead),("two-glass-wrong-write",wrongWrite),("two-glass-wrong-readonly",wrongRead)]{try save(image,name)}
let report:[String:Any]=["status":"ACTUAL_METAL_ORDER_DEPENDENCE_REPRODUCED","checks":checks,"device":device.name,"width":size,"height":height,"records":records,"sourceBlendAndDepthDescriptorsExtracted":true,"actualDeferredEncoderExtracted":true,"productionShadersUnmodified":true,"authoredGeometryOnly":true,"retailRuntimeVerified":false,"simulatorOrPhoneUsed":false]
try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("gpu-report.json"))
print("ACTUAL_METAL_ALPHA_REPRODUCED \(checks) checks, \(records.count) opacity/shader cases; no App/UI/owner geometry")
