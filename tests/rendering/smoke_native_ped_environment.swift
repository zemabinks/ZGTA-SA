// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal
import simd

private var checks=0,draws=0,passes=0
private func require(_ value:@autoclosure()->Bool,_ message:String) {
    checks+=1;if !value(){fatalError(message)}
}
private func clips()->NativeSkeletalAnimationLibrary {
    var data=Data()
    func u32(_ n:UInt32){data.append(contentsOf:[UInt8(truncatingIfNeeded:n),UInt8(truncatingIfNeeded:n>>8),UInt8(truncatingIfNeeded:n>>16),UInt8(truncatingIfNeeded:n>>24)])}
    let name=Array("ped/idle_stance".utf8)
    u32(0x31504c43);u32(1);u32(0);u32(1);data.append(contentsOf:[UInt8(name.count),0]);data.append(contentsOf:name);u32(Float(1).bitPattern);u32(1)
    u32(0);u32(1);u32(0);u32(0);u32(0);u32(0);u32(0);u32(Float(1).bitPattern)
    return NativeSkeletalAnimationLibrary(data:data)!
}
private struct Scene {
    var color=SIMD4<Float>(0,1,0,0.17)
    var settings=SIMD4<Float>(100,200,1,0)
}
private struct Case {
    let name:String
    var depth:Float=150
    var scene=Scene()
    var overrides=NativeRenderWareModel.DrawOverrides()
    var useDefault=false,empty=false
    var expected=SIMD4<Int>(128,128,0,255)
}

@main struct Main {
 static func main()throws {
    let out=URL(fileURLWithPath:CommandLine.arguments[1])
    guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue()else {
        require(!CommandLine.arguments.contains("--require-gpu"),"Required Metal device unavailable")
        print("SKIP actual Metal unavailable");return
    }
    let dff=try NativeRenderWareDFF.decode(Data(contentsOf:out.appendingPathComponent("authored.dff")))
    let txd=try NativeRenderWareTXD.decode(Data(contentsOf:out.appendingPathComponent("authored.txd")))
    let plan=try NativeRenderWarePedModel.prepare(dff:dff,txd:txd)
    let ped=try NativeRenderWarePedModel.Uploaded(plan:plan,device:device)
    let library=try device.makeLibrary(source:String(contentsOf:out.appendingPathComponent("actual.metal"),encoding:.utf8),options:nil)
    let pipelines=try NativeRenderWarePedModel.Pipelines(device:device,library:library,color:.rgba8Unorm)
    let pose=ped.actor.originalPose(blends:[],library:clips()),positions=ped.actor.positions(pose:pose)
    var low=SIMD3<Float>(repeating:.infinity),high=SIMD3<Float>(repeating:-.infinity)
    for p in positions{low=simd_min(low,p);high=simd_max(high,p)}
    let center=(low+high)*0.5,extent=high-low,scale=1.1/max(0.1,max(extent.x,max(extent.y,extent.z)))
    let base=simd_float4x4(columns:(SIMD4(scale,0,0,0),SIMD4(scale*0.23,scale*0.31,0.01,0),SIMD4(0,scale,0,0),SIMD4(-(center.x+center.y*0.23)*scale,-(center.z+center.y*0.31)*scale,0.5-center.y*0.01,1)))
    func encode(_ c:Case,_ encoder:MTLRenderCommandEncoder)throws {
        let matrix=simd_float4x4(columns:(base.columns.0*c.depth,base.columns.1*c.depth,base.columns.2*c.depth,base.columns.3*c.depth))
        for index in plan.model.draws.indices {
            #if HISTORICAL_PED_SCENE
            // The older production renderer has no scene argument. Bind the
            // same authored scene in the unused slot; its actual encoder and
            // fragment remain untouched and expose the missing fog operation.
            var scene=c.useDefault ? Scene(color:.zero,settings:SIMD4(0,1,0,0)):c.scene
            encoder.setFragmentBytes(&scene,length:MemoryLayout<Scene>.stride,index:4)
            try ped.encode(drawIndex:index,pose:pose,encoder:encoder,pipelines:pipelines,viewProjection:matrix,worldTransform:matrix_identity_float4x4,overrides:c.overrides)
            #else
            if c.useDefault {
                try ped.encode(drawIndex:index,pose:pose,encoder:encoder,pipelines:pipelines,viewProjection:matrix,worldTransform:matrix_identity_float4x4,overrides:c.overrides)
            } else {
                try ped.encode(drawIndex:index,pose:pose,encoder:encoder,pipelines:pipelines,viewProjection:matrix,worldTransform:matrix_identity_float4x4,overrides:c.overrides,
                    environment:.init(fogColor:c.scene.color,fogSettings:c.scene.settings))
            }
            #endif
            draws+=1
        }
    }
    func render(_ cases:[Case])throws {
        let side=96,width=side*cases.count,rowBytes=((width*4+255)/256)*256
        let colorD=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:width,height:side,mipmapped:false)
        colorD.usage=[.renderTarget,.shaderRead];colorD.storageMode = .shared
        let depthD=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:width,height:side,mipmapped:false)
        depthD.usage = .renderTarget;depthD.storageMode = .private
        let color=device.makeTexture(descriptor:colorD)!,depth=device.makeTexture(descriptor:depthD)!,pass=MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture=color;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
        pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
        let command=queue.makeCommandBuffer()!,encoder=command.makeRenderCommandEncoder(descriptor:pass)!
        for (i,c) in cases.enumerated() {
            encoder.setViewport(.init(originX:Double(i*side),originY:0,width:Double(side),height:Double(side),znear:0,zfar:1))
            try encode(c,encoder)
        }
        encoder.endEncoding()
        let bytes=device.makeBuffer(length:rowBytes*side,options:.storageModeShared)!,blit=command.makeBlitCommandEncoder()!
        blit.copy(from:color,sourceSlice:0,sourceLevel:0,sourceOrigin:.init(x:0,y:0,z:0),sourceSize:.init(width:width,height:side,depth:1),
            to:bytes,destinationOffset:0,destinationBytesPerRow:rowBytes,destinationBytesPerImage:rowBytes*side)
        blit.endEncoding();command.commit();command.waitUntilCompleted();passes+=1
        require(command.status == .completed,"Actual Metal scene draw failed")
        let p=bytes.contents().assumingMemoryBound(to:UInt8.self)
        for (i,c) in cases.enumerated() {
            var count=0
            for y in 0..<side {for x in 0..<side {
                let offset=y*rowBytes+(x+i*side)*4
                guard p[offset+3]>0 else{continue};count+=1
                require((0..<4).allSatisfy{abs(Int(p[offset+$0])-c.expected[$0])<=2},"Imported character scene pixel differs: \(c.name), actual \((0..<4).map{p[offset+$0]}), expected \(c.expected)")
            }}
            require(c.empty ? count==0:count>20,"Actual rig coverage/cutout differs: \(c.name)")
        }
    }
    try render([.init(name:"before-fog-start",depth:50,expected:SIMD4(255,0,0,255))])
    try render([.init(name:"half-fog")])
    try render([.init(name:"beyond-fog-end",depth:250,expected:SIMD4(0,255,0,255))])
    try render([.init(name:"default-after-fog",useDefault:true,expected:SIMD4(255,0,0,255))])
    var c=Case(name:"partial-atmosphere");c.scene.settings.z=0.5;c.expected=SIMD4(191,64,0,255);try render([c])
    c = .init(name:"interior-fog-disabled");c.scene.settings.z=0;c.expected=SIMD4(255,0,0,255);try render([c])
    c = .init(name:"collapsed-interval",depth:100.5);c.scene.settings=SIMD4(100,100,1,0);try render([c])
    c = .init(name:"reversed-interval",depth:200.5);c.scene.settings=SIMD4(200,100,1,0);try render([c])
    c = .init(name:"light-before-fog");c.overrides.ambient=0.5;c.expected=SIMD4(64,128,0,255);try render([c])
    c = .init(name:"tint-before-fog");c.overrides.tint.x=0.25;c.expected=SIMD4(32,128,0,255);try render([c])
    c = .init(name:"alpha-not-fogged");c.overrides.tint.w=0.5;c.overrides.blendOverride=false;c.expected.w=128;try render([c])
    c = .init(name:"fog-before-alpha-blending");c.overrides.tint.w=0.5;c.expected=SIMD4(64,64,0,128);try render([c])
    c = .init(name:"cutout-before-fog",depth:250,empty:true);c.overrides.tint.w=0.01;c.overrides.alphaCutoff=0.1;try render([c])
    c = .init(name:"fully-fogged-first",depth:250,expected:SIMD4(0,255,0,255))
    try render([c,.init(name:"same-encoder-default-isolation",useDefault:true,expected:SIMD4(255,0,0,255)),.init(name:"same-encoder-new-scene")])
    #if !HISTORICAL_PED_SCENE
    require(MemoryLayout<NativeRenderWarePedModel.Environment>.stride==32,"Swift/Metal scene ABI")
    let descriptor=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1,height:1,mipmapped:false);descriptor.usage = .renderTarget
    let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=device.makeTexture(descriptor:descriptor)
    let command=queue.makeCommandBuffer()!,encoder=command.makeRenderCommandEncoder(descriptor:pass)!
    for field in 0..<8 {
        var environment=NativeRenderWarePedModel.Environment()
        if field<4{environment.fogColor[field] = .nan}else{environment.fogSettings[field-4] = .infinity}
        var rejected=false
        do{try ped.encode(drawIndex:0,pose:pose,encoder:encoder,pipelines:pipelines,viewProjection:base,worldTransform:matrix_identity_float4x4,environment:environment)}
        catch{rejected=true}
        require(rejected,"Non-finite scene accepted")
    }
    encoder.endEncoding()
    #endif
    print("PASS \(checks) scene/pixel checks, \(draws) actual skinned draws in \(passes) Metal passes; retail/timecycle parity remains separate")
 }
}
