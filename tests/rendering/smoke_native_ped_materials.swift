// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal
import simd
var checks=0,renders=0
func require(_ value:@autoclosure()->Bool,_ message:String){checks+=1;if !value(){fatalError(message)}}
func library()->NativeSkeletalAnimationLibrary {
    var data=Data()
    func u32(_ n:UInt32){data.append(contentsOf:[UInt8(truncatingIfNeeded:n),UInt8(truncatingIfNeeded:n>>8),UInt8(truncatingIfNeeded:n>>16),UInt8(truncatingIfNeeded:n>>24)])}
    let name=Array("ped/idle_stance".utf8)
    u32(0x31504c43);u32(1);u32(0);u32(1);data.append(contentsOf:[UInt8(name.count),0]);data.append(contentsOf:name);u32(Float(1).bitPattern);u32(1)
    u32(0);u32(1);u32(0);u32(0);u32(0);u32(0);u32(0);u32(Float(1).bitPattern)
    return NativeSkeletalAnimationLibrary(data:data)!
}
@main struct Main {
 static func main()throws {
    let out=URL(fileURLWithPath:CommandLine.arguments[1])
    guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue()else{
        require(!CommandLine.arguments.contains("--require-gpu"),"Required Metal device unavailable");print("SKIP actual Metal unavailable");return
    }
    let dff=try NativeRenderWareDFF.decode(Data(contentsOf:out.appendingPathComponent("authored.dff")))
    let dictionary=try NativeRenderWareTXD.decode(Data(contentsOf:out.appendingPathComponent("authored.txd")))
    let shader=try device.makeLibrary(source:String(contentsOf:out.appendingPathComponent("actual.metal"),encoding:.utf8),options:nil)
    let pedPipelines=try NativeRenderWarePedModel.Pipelines(device:device,library:shader,color:.rgba8Unorm)
    let staticPipelines=try NativeRenderWareModel.Pipelines(device:device,library:shader,color:.rgba8Unorm)
    let clips=library(),size=96
    let original=dff.geometries[0]
    func plan(prelit:Bool=false,modulate:Bool=false,materialColor:SIMD4<UInt8>?=nil,texture:Bool=true)throws->NativeRenderWarePedModel.Plan {
        let materials=original.materials.map { source -> NativeRenderWareDFF.Material in
            .init(flags:source.flags,color:materialColor ?? source.color,textureName:texture ? source.textureName:nil,
                  maskName:texture ? source.maskName:nil,textureFilterAndAddressing:source.textureFilterAndAddressing,surface:source.surface)
        }
        let colors=prelit ? Array(repeating:SIMD4<UInt8>(64,128,192,255),count:original.vertexCount):[]
        let geometry=NativeRenderWareDFF.Geometry(flags:original.flags | (prelit ? 8:0) | (modulate ? 0x40:0),vertexCount:original.vertexCount,
            textureCoordinates:original.textureCoordinates,prelitColors:colors,triangles:original.triangles,materials:materials,morphTargets:original.morphTargets,skin:original.skin)
        return try NativeRenderWarePedModel.prepare(dff:.init(version:dff.version,frames:dff.frames,geometries:[geometry],atomics:dff.atomics),txd:dictionary)
    }
    func image(_ rgba:[UInt8])->MTLTexture {
        let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1,height:1,mipmapped:false);descriptor.usage = .shaderRead;descriptor.storageMode = .shared
        let image=device.makeTexture(descriptor:descriptor)!
        rgba.withUnsafeBytes{image.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:4)};return image
    }
    func run(_ name:String,plan:NativeRenderWarePedModel.Plan,overrides:NativeRenderWareModel.DrawOverrides = .init(),expectRed:Bool=false,expectEmpty:Bool=false)throws {
        let ped=try NativeRenderWarePedModel.Uploaded(plan:plan,device:device),pose=ped.actor.originalPose(blends:[],library:clips)
        let positions=ped.actor.positions(pose:pose),geometry=plan.model.geometries[0]
        require(positions.count==geometry.vertices.count,"Actual skin/static control vertex count")
        let vertices=zip(geometry.vertices,positions).map { source,position -> NativeRenderWareModel.Vertex in var v=source;v.position=position;return v }
        let fixed=NativeRenderWareModel.Geometry(sourceIndex:geometry.sourceIndex,vertices:vertices,textureCoordinates:geometry.textureCoordinates,indices:geometry.indices,parts:geometry.parts,materials:geometry.materials)
        let rest=NativeRenderWareModel.Plan(geometries:[fixed],textures:plan.model.textures,instances:plan.model.instances,draws:plan.model.draws,diagnostics:plan.model.diagnostics,meshByteCount:plan.model.meshByteCount,textureByteCount:plan.model.textureByteCount)
        let control=try NativeRenderWareModel.Uploaded(plan:rest,device:device)
        var low=SIMD3<Float>(repeating:.infinity),high=SIMD3<Float>(repeating:-.infinity)
        for p in positions{low=simd_min(low,p);high=simd_max(high,p)}
        let center=(low+high)*0.5,extent=high-low,scale=1.1/max(0.1,max(extent.x,max(extent.y,extent.z)))
        let matrix=simd_float4x4(columns:(SIMD4(scale,0,0,0),SIMD4(scale*0.23,scale*0.31,0.01,0),SIMD4(0,scale,0,0),SIMD4(-(center.x+center.y*0.23)*scale,-(center.z+center.y*0.31)*scale,0.5-center.y*0.01,1)))
        func draw(_ skinned:Bool)throws->[UInt8] {
            let colorD=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:size,height:size,mipmapped:false);colorD.usage=[.renderTarget,.shaderRead];colorD.storageMode = .shared
            let depthD=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:size,height:size,mipmapped:false);depthD.usage = .renderTarget;depthD.storageMode = .private
            let color=device.makeTexture(descriptor:colorD)!,depth=device.makeTexture(descriptor:depthD)!,pass=MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture=color;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store;pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
            pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
            let command=queue.makeCommandBuffer()!,encoder=command.makeRenderCommandEncoder(descriptor:pass)!
            encoder.setViewport(.init(originX:0,originY:0,width:Double(size),height:Double(size),znear:0,zfar:1))
            for index in plan.model.draws.indices {
                if skinned{try ped.encode(drawIndex:index,pose:pose,encoder:encoder,pipelines:pedPipelines,viewProjection:matrix,worldTransform:matrix_identity_float4x4,overrides:overrides)}
                else{try control.encode(drawIndex:index,encoder:encoder,pipelines:staticPipelines,viewProjection:matrix,modelTransform:matrix_identity_float4x4,overrides:overrides)}
            }
            encoder.endEncoding();let readback=device.makeBuffer(length:512*size,options:.storageModeShared)!,blit=command.makeBlitCommandEncoder()!
            blit.copy(from:color,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:size,height:size,depth:1),to:readback,destinationOffset:0,destinationBytesPerRow:512,destinationBytesPerImage:512*size)
            blit.endEncoding();command.commit();command.waitUntilCompleted();require(command.status == .completed,"Actual Metal draw failed")
            let p=readback.contents().assumingMemoryBound(to:UInt8.self);var pixels:[UInt8]=[]
            for y in 0..<size{pixels.append(contentsOf:UnsafeBufferPointer(start:p+y*512,count:size*4))};renders+=1;return pixels
        }
        let expected=try draw(false),actual=try draw(true),visible=stride(from:3,to:actual.count,by:4).filter{actual[$0]>0}
        if overrides.visible && !expectEmpty{require(visible.count>20,"Authored skinned fixture did not draw")}
        if expectEmpty{require(visible.isEmpty,"Alpha-cutout material emitted visible pixels")}
        if expectRed{require(visible.allSatisfy{actual[$0-3]>250 && actual[$0-2]<3 && actual[$0-1]<3},"Skinned character ignored its bound original texture")}
        require(expected==actual,"Skinned/static material contract differs: \(name)")
    }
    let base=try plan();try run("original-texture",plan:base,expectRed:true)
    var o=NativeRenderWareModel.DrawOverrides();o.textureOverride=image([0,255,0,255]);try run("texture-override",plan:base,overrides:o)
    let descriptor=MTLSamplerDescriptor();descriptor.sAddressMode = .clampToZero;descriptor.tAddressMode = .clampToZero;descriptor.minFilter = .linear;descriptor.magFilter = .linear
    let border=device.makeSamplerState(descriptor:descriptor)!
    o.samplerOverride=border;try run("explicit-border-sampler",plan:base,overrides:o)
    o = .init();o.materialColorOverride=SIMD4(0.25,0.5,0.75,0.5);try run("explicit-color",plan:base,overrides:o)
    try run("source-modulation-disabled",plan:plan(materialColor:SIMD4(60,120,180,128)))
    try run("source-modulation-enabled",plan:plan(modulate:true,materialColor:SIMD4(60,120,180,128)))
    let prelit=try plan(prelit:true);try run("prelit-enabled",plan:prelit)
    o = .init();o.ignoreVertexColor=true;try run("prelit-disabled",plan:prelit,overrides:o)
    o = .init();o.tint.w=0.5;o.blendOverride=false;try run("forced-opaque",plan:base,overrides:o)
    o = .init();o.visible=false;try run("hidden",plan:base,overrides:o)
    let noMap=try plan(texture:false);try run("legitimate-no-map",plan:noMap)
    o = .init();o.samplerOverride=border;try run("no-map-skip-border-sample",plan:noMap,overrides:o)
    o = .init();o.textureOverride=image([0,255,0,255]);try run("override-without-source-map",plan:noMap,overrides:o)
    o = .init();o.tint.w=0.5;o.alphaCutoff=0.9;try run("actual-alpha-cutout",plan:base,overrides:o,expectEmpty:true)
    print("PASS \(checks) authored material/texture checks, \(renders) actual static/skinned Metal renders; no retail claim")
 }
}
