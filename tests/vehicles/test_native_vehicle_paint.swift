// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal
import MetalKit
import simd

@main enum VehiclePaintTest {
    static var checks=0
    static func check(_ condition:Bool,_ message:String) {
        guard condition else{fatalError(message)};checks+=1
    }
    static func near(_ a:SIMD3<Float>,_ b:[Double],_ message:String) {
        check(zip([a.x,a.y,a.z],b).allSatisfy{abs(Double($0)-$1)<0.000001},message)
    }
    static func json(_ url:URL)throws->[String:Any]{try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]}
    static func data(_ value:[String:Any])throws->Data{try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])}
    struct Uniforms {
        var viewProjection=matrix_identity_float4x4
        var settings=SIMD4<Float>(1,1,0,1),fogColor=SIMD4<Float>(0,0,0,1)
        var fogSettings=SIMD4<Float>(0,100,0,0),tintColor=SIMD4<Float>(repeating:1)
    }
    static func main()throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),research=root.appendingPathComponent("local-only/research/vehicle-paint-105")
        let reference=try json(research.appendingPathComponent("reference.json")),models=reference["models"] as! [[String:Any]]
        var familyCount=0,drawCount=0,caseCount=0
        for model in models {
            let name=model["model"] as! String,id=model["id"] as! Int,base=research.appendingPathComponent("overlay/game/native/models/\(name).rig")
            let document=try Data(contentsOf:base.appendingPathExtension("json")),binary=try Data(contentsOf:base.appendingPathExtension("bin")),atlas=try Data(contentsOf:base.appendingPathExtension("png"))
            guard let rig=NativeVehicleRig(data:document),let paint=rig.document.paint.flatMap(NativeVehiclePaint.init),let mesh=rig.meshData(binary)else{fatalError("Cannot decode complete paint family \(name)")}
            check(rig.hasDynamicPaint&&rig.validatesAssetFamily(binary:binary,atlas:atlas),"Unverified family \(name)")
            let world=try WorldBinary(data:mesh);check(!world.vertices.isEmpty,"Empty world \(name)")
            for scenario in model["cases"] as! [[String:Any]] {
                let code=scenario["code"] as! String,colors=scenario["colors"] as! [Int],slots=scenario["slots"] as! [String:[Double]],scorched=scenario["scorched"] as! Bool
                check(paint.colors(code:code,model:id)==colors,"Browser numeric/code normalizer \(code)")
                for part in rig.document.draws {
                    if let slot=part.paint,slot>=0 {
                        let rgb=paint.color(slot:slot,colors:colors)!
                        near(rgb*(scorched ? 0.14:1),slots[String(slot)]!,"Browser material colour \(code) slot\(slot)")
                    }
                }
                var input=NativeVehicleRig.Input(),state=NativeVehicleRig.State();input.appearanceCode=code;input.scorched=scorched
                let frame=rig.pose(input,state:&state,delta:1/60)
                for draw in frame.draws {
                    let authored=rig.document.draws.filter{$0.start>=draw.start && $0.start+$0.count<=draw.start+draw.count}
                    check(!authored.isEmpty,"Merged draw lost material provenance")
                    for part in authored {
                        if let slot=part.paint,slot>=0 {
                            check(draw.paint.w==1,"Paint flag lost \(name)")
                            near(SIMD3(draw.paint.x,draw.paint.y,draw.paint.z)*(draw.scorched ? 0.14:1),slots[String(slot)]!,"Actual rig draw material \(code)")
                        }else{check(draw.paint==SIMD4(1,1,1,0),"Tinted nonpaint material \(name)")}
                    };drawCount+=1
                };caseCount+=1
            }
            var changed=binary;changed[changed.count-1]^=1
            check(!rig.validatesAssetFamily(binary:changed,atlas:atlas),"Mesh hash mismatch accepted")
            var image=atlas;image[image.count-1]^=1
            check(!rig.validatesAssetFamily(binary:binary,atlas:image),"Atlas hash mismatch accepted")
            let working=root.appendingPathComponent("local-only/native-working/models/\(name).rig")
            let oldBase=FileManager.default.fileExists(atPath:working.appendingPathExtension("json").path) ? working:root.appendingPathComponent("local-only/site/game/native/models/\(name).rig")
            let oldJSON=try Data(contentsOf:oldBase.appendingPathExtension("json")),oldBinary=try Data(contentsOf:oldBase.appendingPathExtension("bin"))
            let before=try JSONSerialization.jsonObject(with:oldJSON) as! [String:Any],after=try JSONSerialization.jsonObject(with:document) as! [String:Any]
            for key in ["id","model","kind","axes","dffSHA256","rigFactorySHA256","origin","nodes","frames","joints","waterMasks","textures","vertices","indices"] {
                check(try data(["value":before[key] ?? NSNull()])==data(["value":after[key] ?? NSNull()]),"Paint altered rest hierarchy/support/geometry metadata \(name) \(key)")
            }
            if let old=NativeVehicleRig(data:oldJSON),old.document.version==1 {
                check(!old.hasDynamicPaint&&old.meshData(binary)==nil && !old.validatesAssetFamily(binary:binary,atlas:atlas),"Legacy JSON accepted neutral RGB")
                check(rig.meshData(oldBinary)==nil && !rig.validatesAssetFamily(binary:oldBinary,atlas:atlas),"Neutral JSON accepted baked RGB")
                var input=NativeVehicleRig.Input(),state=NativeVehicleRig.State();input.appearanceCode="\(id).0.0.0."
                check(old.pose(input,state:&state,delta:1/60).draws.allSatisfy{$0.paint.w==0},"Legacy rig was recoloured")
            };familyCount+=1
        }
        let taxiBase=research.appendingPathComponent("overlay/game/native/models/taxi.rig")
        let taxiData=try Data(contentsOf:taxiBase.appendingPathExtension("json")),taxi=NativeVehicleRig(data:taxiData)!,paint=NativeVehiclePaint(taxi.document.paint!)!
        for row in reference["palette"] as! [[String:Any]] {
            near(paint.color(slot:0,colors:[row["id"] as! Int,1])!,row["rgb"] as! [Double],"Palette transfer \(row["id"]!)")
        }
        check(paint.colors(code:nil,model:420)==[6,1],"Taxi default palette")
        check(paint.colors(code:"411.1.1.0.",model:420)==[6,1],"Wrong model accepted")
        check(paint.colors(code:String(repeating:"1",count:513),model:420)==[6,1],"Unbounded code")
        var malformed=try json(taxiBase.appendingPathExtension("json"));malformed["binaryEncoding"]="WRL2"
        check(NativeVehicleRig(data:try data(malformed))==nil,"Unknown neutral encoding")
        malformed=try json(taxiBase.appendingPathExtension("json"));var meta=malformed["paint"] as! [String:Any];meta["palette"]=[[256,0,0]];malformed["paint"]=meta
        check(NativeVehicleRig(data:try data(malformed))==nil,"Out-of-range palette")
        malformed=try json(taxiBase.appendingPathExtension("json"));var rows=malformed["draws"] as! [[String:Any]];rows[0]["paint"]=4;malformed["draws"]=rows
        check(NativeVehicleRig(data:try data(malformed))==nil,"Unknown paint slot")
        var redInput=NativeVehicleRig.Input(),blackInput=NativeVehicleRig.Input(),a=NativeVehicleRig.State(),b=NativeVehicleRig.State()
        redInput.appearanceCode="420.33488896.1.0.";blackInput.appearanceCode="420.16777216.1.0."
        let red=taxi.pose(redInput,state:&a,delta:1/60),black=taxi.pose(blackInput,state:&b,delta:1/60)
        check(red.draws.contains{$0.paint==SIMD4(1,0,0,1)}&&black.draws.contains{$0.paint==SIMD4(0,0,0,1)},"Per-instance paint shared or black lost")
        rendererSource(taxi)
        let gpu=try gpu(root:root,research:research,reference:reference,paint:paint,taxi:taxi)
        let report:[String:Any]=["status":"PASS","models":familyCount,"cases":caseCount,"actualRigDraws":drawCount,"checks":checks,"gpu":gpu,
            "limits":["Desktop Metal readbacks are not physical iPhone acceptance or FPS evidence","General native lighting, reflections, paintjobs and patterns are separate parity work"]]
        try data(report).write(to:research.appendingPathComponent("runtime-report.json"));print(String(data:try data(report),encoding:.utf8)!)
    }

    static func gpu(root:URL,research:URL,reference:[String:Any],paint:NativeVehiclePaint,taxi:NativeVehicleRig)throws->[String:Any] {
        guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue()else{fatalError("Actual Metal device required")}
        let worldSource=try String(contentsOf:root.appendingPathComponent("ios/App/WorldShaders.metal"),encoding:.utf8)
        let vertex=String(worldSource[worldSource.range(of:"vertex Raster worldVertex")!.lowerBound..<worldSource.range(of:"vertex Raster animatedActorVertex")!.lowerBound])
        let native="struct NativeVertex {float4 position;float4 uvLayer;float4 tint;float4 dusk;};\n"
        let shader=try String(contentsOf:root.appendingPathComponent("ios/App/VehicleShaders.metal"),encoding:.utf8)+"\n"+native+vertex
        let library=try device.makeLibrary(source:shader,options:nil)
        func pipeline(_ fragment:String,depth:Bool=false)throws->MTLRenderPipelineState {
            let d=MTLRenderPipelineDescriptor();d.vertexFunction=library.makeFunction(name:"worldVertex");d.fragmentFunction=library.makeFunction(name:fragment)
            d.colorAttachments[0].pixelFormat = .rgba8Unorm;if depth{d.depthAttachmentPixelFormat = .depth32Float}
            return try device.makeRenderPipelineState(descriptor:d)
        }
        let painted=try pipeline("vehiclePaintFragment"),legacy=try pipeline("vehicleFragment"),carPipeline=try pipeline("vehiclePaintFragment",depth:true)
        let td=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:64,height:64,mipmapped:false);td.usage=[.renderTarget,.shaderRead];td.storageMode = .private
        let target=device.makeTexture(descriptor:td)!,readback=device.makeBuffer(length:64*256,options:.storageModeShared)!
        let textureDesc=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1,height:1,mipmapped:false);textureDesc.usage = .shaderRead
        let white=device.makeTexture(descriptor:textureDesc)!
        let points:[SIMD4<Float>]=[SIMD4(-1,-1,0,1),SIMD4(1,-1,0,1),SIMD4(-1,1,0,1),SIMD4(1,1,0,1)],indices:[UInt32]=[0,1,2,2,1,3]
        let indexBuffer=device.makeBuffer(bytes:indices,length:indices.count*4)!
        func pixels(command:MTLCommandBuffer)->[UInt8] {
            let blit=command.makeBlitCommandEncoder()!;blit.copy(from:target,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:64,height:64,depth:1),to:readback,destinationOffset:0,destinationBytesPerRow:256,destinationBytesPerImage:16384)
            blit.endEncoding();command.commit();command.waitUntilCompleted();check(command.status == .completed && command.error==nil,"Metal command failed")
            return Array(UnsafeBufferPointer(start:readback.contents().assumingMemoryBound(to:UInt8.self),count:16384))
        }
        func patch(pipeline:MTLRenderPipelineState,intrinsic:Float,texture:UInt8,paintValue:SIMD4<Float>,scorch:Float=1,emissive:Float=0,vertexAlpha:Float=1,cameraAlpha:Float=1,alphaTest:Float=0,textureAlpha:UInt8=255)->[UInt8] {
            let vertices=points.map{NativeVertex(position:$0,uvLayer:SIMD4(0,0,0,0),tint:SIMD4(intrinsic,intrinsic,intrinsic,vertexAlpha),dusk:SIMD4(intrinsic,intrinsic,intrinsic,vertexAlpha))}
            let buffer=device.makeBuffer(bytes:vertices,length:vertices.count*MemoryLayout<NativeVertex>.stride)!,texel:[UInt8]=[texture,texture,texture,textureAlpha]
            texel.withUnsafeBytes{white.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:4)}
            var uniforms=Uniforms();uniforms.tintColor.w=cameraAlpha
            var material=SIMD4<Float>(-1,emissive,scorch,alphaTest),color=paintValue
            let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store;pass.colorAttachments[0].clearColor=MTLClearColorMake(0.125,0.25,0.375,0.5)
            let command=queue.makeCommandBuffer()!,e=command.makeRenderCommandEncoder(descriptor:pass)!;e.setRenderPipelineState(pipeline);e.setVertexBuffer(buffer,offset:0,index:0)
            e.setVertexBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1);e.setFragmentBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1)
            e.setFragmentBytes(&material,length:16,index:2);e.setFragmentBytes(&color,length:16,index:3);e.setFragmentTexture(white,index:0)
            e.drawIndexedPrimitives(type:.triangle,indexCount:6,indexType:.uint32,indexBuffer:indexBuffer,indexBufferOffset:0);e.endEncoding()
            return Array(pixels(command:command)[(32*64+32)*4..<(32*64+32)*4+4])
        }
        var shaderCases=0,maxError=0
        for row in reference["shaders"] as! [[String:Any]] {
            let id=row["paint"] as! Int,rgb=paint.color(slot:0,colors:[id,1])!,expected=row["expected"] as! [Int]
            let actual=patch(pipeline:painted,intrinsic:Float(row["intrinsic"] as! Double),texture:UInt8(row["texture"] as! Int),paintValue:SIMD4(rgb,1),scorch:Float(row["scorch"] as! Double))
            for channel in 0..<3{let error=abs(Int(actual[channel])-expected[channel]);maxError=max(maxError,error);check(error<=1,"Actual Metal paint \(id): \(actual) expected\(expected)")};check(actual[3]==255,"Paint changed alpha");shaderCases+=1
        }
        for (id,rgb) in paint.metadata.palette.enumerated() {
            let linear=paint.color(slot:0,colors:[id,1])!,actual=patch(pipeline:painted,intrinsic:5/9,texture:255,paintValue:SIMD4(linear,1))
            check((0..<3).allSatisfy{abs(Int(actual[$0])-rgb[$0])<=1},"Actual palette GPU \(id) \(actual) expected\(rgb)")
        }
        var legacyCases=0
        for intrinsic:Float in [0,0.25,1] {for texture:UInt8 in [128,255] {for scorch:Float in [0.14,1] {for emissive:Float in [0,1] {
            let old=patch(pipeline:legacy,intrinsic:intrinsic,texture:texture,paintValue:SIMD4(1,0,0,1),scorch:scorch,emissive:emissive,vertexAlpha:0.5,cameraAlpha:0.6)
            let new=patch(pipeline:painted,intrinsic:intrinsic,texture:texture,paintValue:SIMD4(0,0,0,0),scorch:scorch,emissive:emissive,vertexAlpha:0.5,cameraAlpha:0.6)
            check(old==new,"Nonpaint material changed \(old) \(new)");check(abs(Int(new[3])-77)<=1,"Camera/window opacity changed");legacyCases+=1
        }}}}
        let alpha=patch(pipeline:painted,intrinsic:1,texture:255,paintValue:SIMD4(1,0,0,1),vertexAlpha:0.5,cameraAlpha:0.6,textureAlpha:128)
        check(abs(Int(alpha[3])-38)<=1,"Paint changed combined texture/material/camera opacity")
        let lamp=patch(pipeline:painted,intrinsic:0,texture:128,paintValue:SIMD4(0,0,0,1),emissive:1)
        check(lamp[0]==128&&lamp[1]==128&&lamp[2]==128,"Paint darkened emissive lamp")
        let clear=patch(pipeline:painted,intrinsic:1,texture:255,paintValue:SIMD4(0,0,0,1),alphaTest:0.5,textureAlpha:1)
        check(zip(clear,[32,64,96,128]).allSatisfy{abs(Int($0)-$1)<=1},"Alpha-test discard changed")

        // Actual complete Taxi geometry, atlas, pose transforms and per-part draws.
        let base=research.appendingPathComponent("overlay/game/native/models/taxi.rig"),mesh=try WorldBinary(data:taxi.meshData(Data(contentsOf:base.appendingPathExtension("bin")))!)
        let vertexBuffer=device.makeBuffer(bytes:mesh.vertices,length:mesh.vertices.count*MemoryLayout<NativeVertex>.stride)!,carIndices=device.makeBuffer(bytes:mesh.indices,length:mesh.indices.count*4)!
        let atlas=try MTKTextureLoader(device:device).newTexture(URL:base.appendingPathExtension("png"),options:[.SRGB:false,.generateMipmaps:false,.textureUsage:MTLTextureUsage.shaderRead.rawValue])
        let dd=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.depth32Float,width:64,height:64,mipmapped:false);dd.usage = .renderTarget;dd.storageMode = .private
        let depth=device.makeTexture(descriptor:dd)!,ds=MTLDepthStencilDescriptor();ds.depthCompareFunction = .less;ds.isDepthWriteEnabled=true;let depthState=device.makeDepthStencilState(descriptor:ds)!
        var camera=matrix_identity_float4x4;camera.columns=(SIMD4(0.27,0,0.06,0),SIMD4(0.15,0.04,-0.06,0),SIMD4(0,0.38,0,0),SIMD4(0,-0.35,0.5,1))
        func car(_ code:String,paintOnly:Bool)throws->[UInt8] {
            var input=NativeVehicleRig.Input(),state=NativeVehicleRig.State();input.appearanceCode=code
            let frame=taxi.pose(input,state:&state,delta:1/60),pass=MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store;pass.colorAttachments[0].clearColor=MTLClearColorMake(0,0,0,0)
            pass.depthAttachment.texture=depth;pass.depthAttachment.loadAction = .clear;pass.depthAttachment.storeAction = .dontCare;pass.depthAttachment.clearDepth=1
            let command=queue.makeCommandBuffer()!,e=command.makeRenderCommandEncoder(descriptor:pass)!;e.setRenderPipelineState(carPipeline);e.setDepthStencilState(depthState);e.setCullMode(.none)
            e.setVertexBuffer(vertexBuffer,offset:0,index:0);e.setFragmentTexture(atlas,index:0)
            for draw in frame.draws where !paintOnly || draw.paint.w>0.5 {
                var u=Uniforms();u.viewProjection=camera*draw.transform;u.settings=SIMD4(Float(atlas.width),Float(atlas.height),0,128)
                var m=SIMD4<Float>(draw.layerOverride,draw.emissive ? 1:0,draw.scorched ? 0.14:1,draw.alphaTest),p=draw.paint
                e.setVertexBytes(&u,length:MemoryLayout<Uniforms>.stride,index:1);e.setFragmentBytes(&u,length:MemoryLayout<Uniforms>.stride,index:1);e.setFragmentBytes(&m,length:16,index:2);e.setFragmentBytes(&p,length:16,index:3)
                e.drawIndexedPrimitives(type:.triangle,indexCount:draw.count,indexType:.uint32,indexBuffer:carIndices,indexBufferOffset:draw.start*4)
            };e.endEncoding();return pixels(command:command)
        }
        let yellow=try car("420.6.1.0.",paintOnly:false),red=try car("420.33488896.1.0.",paintOnly:false),black=try car("420.16777216.1.0.",paintOnly:false),mask=try car("420.33488896.1.0.",paintOnly:true)
        var changed=0,unchanged=0,blackPixels=0,visible=0
        for pixel in 0..<4096 {let at=pixel*4
            if yellow[at+3]>0{visible+=1}
            if mask[at+3]>0 && yellow[at+3]>0 && red[at+3]>0 && yellow[at..<at+3] != red[at..<at+3]{changed+=1;if black[at..<at+3].allSatisfy({$0==0}){blackPixels+=1}}
            if mask[at+3]==0 && yellow[at+3]>0{check(yellow[at..<at+4]==red[at..<at+4],"Whole-car tint affected unpainted geometry");unchanged+=1}
            check(yellow[at+3]==red[at+3]&&yellow[at+3]==black[at+3],"Vehicle paint altered actual part alpha")
        }
        check(visible>100&&changed>50&&blackPixels>25&&unchanged>10,"Complete taxi material coverage visible\(visible) changed\(changed) black\(blackPixels) nonpaint\(unchanged)")
        try Data(yellow).write(to:research.appendingPathComponent("taxi-yellow.rgba"));try Data(red).write(to:research.appendingPathComponent("taxi-red.rgba"))
        return ["device":device.name,"readback":"private RGBA8 render target copied by actual Metal blit into shared buffer","paletteEntries":paint.metadata.palette.count,"sourceShaderCases":shaderCases,"maximumChannelError":maxError,"legacyEquivalenceCases":legacyCases,"taxiVisiblePixels":visible,"taxiChangedPaintPixels":changed,"taxiBlackPaintPixels":blackPixels,"taxiUnpaintedPreservedPixels":unchanged]
    }
}
