// SPDX-License-Identifier: AGPL-3.0-only
// Authored images and geometry; production shader, ABI and blend descriptors.
import Foundation
import MetalKit
import simd

private enum Failure:Error {case unavailable(String),assertion(String)}
private var checks=0,renders=0
private func require(_ condition:Bool,_ message:String)throws {
    checks+=1;if !condition{throw Failure.assertion(message)}
}
private let output=URL(fileURLWithPath:CommandLine.arguments[1])
guard let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue() else{throw Failure.unavailable("Host Metal GPU")}
private let library=try device.makeLibrary(URL:output.appendingPathComponent("production.metallib"))
// ACTUAL_UNIFORMS
private struct Formats {let colorPixelFormat:MTLPixelFormat = .bgra8Unorm,depthStencilPixelFormat:MTLPixelFormat = .invalid}
private func pipeline(_ vertex:MTLFunction,_ fragment:MTLFunction)->MTLRenderPipelineState? {
    let view=Formats()
    // ACTUAL_PIPELINE
    return pipeline
}
private let routes=["worldVertex","animatedActorVertex","skeletalActorVertex"]
private var pipelines:[String:MTLRenderPipelineState]=[:]
for route in routes {for fragment in ["ordinaryPedAtlasFragment","worldFragment","nativePedReferenceFragment"] {
    guard let vertex=library.makeFunction(name:route),let function=library.makeFunction(name:fragment),let value=pipeline(vertex,function) else{throw Failure.unavailable(route+fragment)}
    pipelines[route+fragment]=value
}}
private let size=32,row=256
private let description=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:size,height:size,mipmapped:false)
description.storageMode = .private;description.usage = .renderTarget
private let target=device.makeTexture(descriptor:description)!,readback=device.makeBuffer(length:row*size,options:.storageModeShared)!
private struct Skin {var point:SIMD4<Float>,bones:SIMD4<UInt32>,weights:SIMD4<Float>}
private let points:[SIMD4<Float>]=[SIMD4(-1,-1,0.5,1),SIMD4(1,-1,0.5,1),SIMD4(1,1,0.5,1),SIMD4(-1,1,0.5,1)]
private let indices:[UInt32]=[0,1,2,0,2,3]
private let indexBuffer=device.makeBuffer(bytes:indices,length:indices.count*4,options:.storageModeShared)!
private struct Fixture {
    let name:String,layout:NativePedAtlasLayout,validated:NativePedAtlasLayout.Validated,texture:MTLTexture,pixels:[UInt8],tiles:[MTLTexture]
}
private let loader=MTKTextureLoader(device:device)
private let names=try JSONDecoder().decode([String].self,from:Data(contentsOf:output.appendingPathComponent("fixtures/cases.json")))
private var fixtures:[Fixture]=[]
for name in names {
    let root=output.appendingPathComponent("fixtures/"+name)
    let mesh=try Data(contentsOf:root.appendingPathComponent("mesh.data")),png=try Data(contentsOf:root.appendingPathComponent("atlas.data"))
    let layout=try JSONDecoder().decode(NativePedAtlasLayout.self,from:Data(contentsOf:root.appendingPathComponent("layout.json")))
    let validated=try layout.validate(mesh:mesh,png:png,world:WorldBinary(data:mesh))
    let texture=try loader.newTexture(data:png,options:[.SRGB:false,.generateMipmaps:false])
    try require(texture.width==validated.width && texture.height==validated.height && texture.mipmapLevelCount==1,"Actual PNG dimensions/no generated mips: "+name)
    let tiles=try layout.layers.map{try loader.newTexture(data:Data(contentsOf:root.appendingPathComponent("tile-\($0.slot).png")),options:[.SRGB:false,.generateMipmaps:false])}
    fixtures.append(.init(name:name,layout:layout,validated:validated,texture:texture,pixels:Array(try Data(contentsOf:root.appendingPathComponent("pixels.rgba"))),tiles:tiles))
}
private let clear:[Float]=[12/255,18/255,25/255,1]
private func render(_ fixture:Fixture,route:String,uv:SIMD2<Float>,slot:Float,night:Float=0,alpha:Float=1,owner:Float=1,fog:Float=0,legacy:Bool=false,version:Float?=nil,badSampling:SIMD4<Float>?=nil,reference:Bool=false)->[UInt8] {
    renders+=1
    let tint=SIMD4<Float>(0.45,0.32,0.2,alpha),dusk=SIMD4<Float>(0.18,0.3,0.5,alpha)
    let vertices=points.map{NativeVertex(position:$0,uvLayer:SIMD4(uv.x,uv.y,slot,0),tint:tint,dusk:dusk)}
    let vertexBuffer=device.makeBuffer(bytes:vertices,length:MemoryLayout<NativeVertex>.stride*vertices.count,options:.storageModeShared)!
    var uniforms=Uniforms(viewProjection:matrix_identity_float4x4,settings:SIMD4(Float(fixture.texture.width),Float(fixture.texture.height),night,128))
    uniforms.fogColor=SIMD4(0.2,0.35,0.6,1);uniforms.fogSettings=SIMD4(0,2,fog,0);uniforms.tintColor=SIMD4(0.7,0.85,0.9,owner)
    var layout=fixture.validated.vectors
    if let version{layout[0].w=version}
    if let badSampling,fixture.layout.schema==2{layout[2]=badSampling}
    let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target
    pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor=MTLClearColorMake(Double(clear[0]),Double(clear[1]),Double(clear[2]),1)
    let command=queue.makeCommandBuffer()!,encoder=command.makeRenderCommandEncoder(descriptor:pass)!
    encoder.setRenderPipelineState(pipelines[route+(reference ? "nativePedReferenceFragment":legacy ? "worldFragment":"ordinaryPedAtlasFragment")]!)
    encoder.setCullMode(.none);encoder.setVertexBuffer(vertexBuffer,offset:0,index:0)
    encoder.setVertexBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1)
    encoder.setFragmentBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1)
    if reference {
        var filter=Float(fixture.layout.layers[Int(slot)].sampler!.filter)
        encoder.setFragmentBytes(&filter,length:4,index:2);encoder.setFragmentTexture(fixture.tiles[Int(slot)],index:0)
    } else {
        encoder.setFragmentBytes(layout,length:layout.count*16,index:2);encoder.setFragmentTexture(fixture.texture,index:0)
    }
    if route=="animatedActorVertex" {
        // packed_float3: twelve-byte stride. Interpolated positions equal points.
        let previous=points.flatMap{[$0.x-0.125,$0.y,$0.z]},next=points.flatMap{[$0.x+0.375,$0.y,$0.z]}
        encoder.setVertexBytes(previous,length:previous.count*4,index:2);encoder.setVertexBytes(next,length:next.count*4,index:3)
        var mix:Float=0.25;encoder.setVertexBytes(&mix,length:4,index:4)
    } else if route=="skeletalActorVertex" {
        let skin=points.map{Skin(point:SIMD4($0.x-0.125,$0.y,$0.z,1),bones:SIMD4(0,1,0,0),weights:SIMD4(0.75,0.25,0,0))}
        var a=matrix_identity_float4x4,b=matrix_identity_float4x4;a.columns.3.x=0.25;b.columns.3.x = -0.25
        let palette=[a,b]
        encoder.setVertexBytes(skin,length:skin.count*MemoryLayout<Skin>.stride,index:2)
        encoder.setVertexBytes(palette,length:palette.count*64,index:3)
    }
    encoder.drawIndexedPrimitives(type:.triangle,indexCount:6,indexType:.uint32,indexBuffer:indexBuffer,indexBufferOffset:0)
    encoder.endEncoding();let blit=command.makeBlitCommandEncoder()!
    blit.copy(from:target,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:size,height:size,depth:1),to:readback,destinationOffset:0,destinationBytesPerRow:row,destinationBytesPerImage:row*size)
    blit.endEncoding();command.commit();command.waitUntilCompleted()
    precondition(command.status == .completed && command.error==nil,"Metal execution failed")
    let raw=readback.contents().assumingMemoryBound(to:UInt8.self)
    return (0..<size).flatMap{y in Array(UnsafeBufferPointer(start:raw+y*row,count:size*4))}
}
private func expected(_ fixture:Fixture,uv:SIMD2<Float>,slot:Int,night:Float,alpha:Float,owner:Float,fog:Float)->[Int] {
    let rect=fixture.layout.layers[slot].rect,width=fixture.texture.width
    var sample=[Float](repeating:0,count:4)
    let phase=SIMD2(uv.x-floor(uv.x),uv.y-floor(uv.y))
    if fixture.layout.schema==2 {
        let filter=fixture.layout.layers[slot].sampler!.filter
        func wrapped(_ n:Int,_ extent:Int)->Int{let residue=n%extent;return residue<0 ? residue+extent:residue}
        func value(_ xx:Int,_ yy:Int,_ component:Int)->Float {
            let x=rect[0]+wrapped(xx,rect[2]),y=rect[1]+wrapped(yy,rect[3])
            return Float(fixture.pixels[(y*width+x)*4+component])/255
        }
        if filter==1 {
            let x=Int(floor(phase.x*Float(rect[2]))),y=Int(floor(phase.y*Float(rect[3])))
            sample=(0..<4).map{value(x,y,$0)}
        } else {
            let x=phase.x*Float(rect[2])-0.5,y=phase.y*Float(rect[3])-0.5
            let x0=Int(floor(x)),y0=Int(floor(y)),fx=x-Float(x0),fy=y-Float(y0)
            for c in 0..<4 {
                let a=value(x0,y0,c),b=value(x0+1,y0,c),d=value(x0,y0+1,c),e=value(x0+1,y0+1,c)
                sample[c]=(a+(b-a)*fx)*(1-fy)+(d+(e-d)*fx)*fy
            }
        }
    } else {
        let x=Float(rect[0])+phase.x*Float(rect[2]-1),y=Float(rect[1])+phase.y*Float(rect[3]-1)
        let x0=Int(floor(x)),y0=Int(floor(y)),fx=x-Float(x0),fy=y-Float(y0)
        for c in 0..<4 {
            func value(_ xx:Int,_ yy:Int)->Float{Float(fixture.pixels[(yy*width+xx)*4+c])/255}
            let a=value(x0,y0),b=value(min(width-1,x0+1),y0),d=value(x0,min(fixture.texture.height-1,y0+1)),e=value(min(width-1,x0+1),min(fixture.texture.height-1,y0+1))
            sample[c]=(a+(b-a)*fx)*(1-fy)+(d+(e-d)*fx)*fy
        }
    }
    if sample[3]*alpha<0.1{return clear.map{Int(($0*255).rounded())}}
    let light:[Float]=[0.45,0.32,0.2],dusk:[Float]=[0.18,0.3,0.5],tint:[Float]=[0.7,0.85,0.9],fogColor:[Float]=[0.2,0.35,0.6]
    let opacity=sample[3]*alpha*owner
    var result:[Int]=[]
    for c in 0..<3 {
        let mixed=light[c]+(dusk[c]-light[c])*night
        var color=min(1,sample[c]*max(mixed*1.8,0.2))*tint[c]
        color=color+(fogColor[c]-color)*fog*0.5
        result.append(Int((255*(color*opacity+clear[c]*(1-opacity))).rounded()))
    }
    return result+[255]
}
private func center(_ image:[UInt8])->[Int]{let i=(size/2*size+size/2)*4;return [Int(image[i+2]),Int(image[i+1]),Int(image[i]),Int(image[i+3])]}
private let uvCases:[SIMD2<Float>]=[SIMD2(0,0),SIMD2(0.999,0.999),SIMD2(0.17,0.73),SIMD2(-0.25,2.3),SIMD2(3,-2),SIMD2(0.5,0.5)]
private let policies:[(Float,Float,Float,Float)]=[(0,1,1,0),(1,1,1,0),(0.35,0.6,0.4,0.8),(0.5,0.1,1,1)]
for fixture in fixtures {
    var positions=uvCases
    if fixture.layout.schema==2 {
        let extra:[SIMD2<Float>]=[SIMD2(0.00001,-0.00001),SIMD2(0.99999,1.00001),SIMD2(0.5/128,0.5/256),SIMD2(-3.5,8.5),SIMD2(Float.greatestFiniteMagnitude,-Float.greatestFiniteMagnitude),SIMD2(-Float.leastNonzeroMagnitude,Float.leastNonzeroMagnitude)]
        positions.append(contentsOf:extra)
    }
    for slot in fixture.layout.layers.indices {for uv in positions {for (night,alpha,owner,fog) in policies {
        let reference=render(fixture,route:routes[0],uv:uv,slot:Float(slot),night:night,alpha:alpha,owner:owner,fog:fog)
        let want=expected(fixture,uv:uv,slot:slot,night:night,alpha:alpha,owner:owner,fog:fog),actual=center(reference)
        try require(zip(want,actual).allSatisfy{abs($0-$1)<=3},"CPU bilinear/light/fog/alpha: \(fixture.name), slot \(slot), uv \(uv), expected \(want), actual \(actual)")
        if fixture.layout.schema==2 && abs(uv.x)<100 && abs(uv.y)<100 {
            let independent=render(fixture,route:routes[0],uv:uv,slot:Float(slot),night:night,alpha:alpha,owner:owner,fog:fog,reference:true)
            try require(zip(center(independent),actual).allSatisfy{abs($0-$1)<=3},"Independent isolated-texture hardware repeat sampler: \(fixture.name), slot \(slot), uv \(uv)")
        }
        for route in routes.dropFirst() {
            let image=render(fixture,route:route,uv:uv,slot:Float(slot),night:night,alpha:alpha,owner:owner,fog:fog)
            try require(image==reference,"Fragment-only buffer2 preserves \(route): \(fixture.name)")
        }
        if fixture.name=="legacy" {
            let old=render(fixture,route:routes[0],uv:uv,slot:Float(slot),night:night,alpha:alpha,owner:owner,fog:fog,legacy:true)
            try require(old==reference,"Legacy 128-cell pixels preserved, including lighting/fog/alpha")
        }
    }}}
    let background=render(fixture,route:routes[0],uv:.zero,slot:-1)
    for bad in [Float(-1),Float(fixture.layout.layers.count),Float.nan,Float.infinity] {
        try require(render(fixture,route:routes[0],uv:SIMD2(0.4,0.7),slot:bad)==background,"Invalid layer is discarded")
    }
    try require(render(fixture,route:routes[0],uv:.zero,slot:0,version:3)==background,"Invalid layout version is discarded")
    if fixture.layout.schema==2 {
        for uv in [SIMD2<Float>(.nan,0),SIMD2<Float>(0,.nan),SIMD2<Float>(.infinity,0),SIMD2<Float>(0,-.infinity)] {
            try require(render(fixture,route:routes[0],uv:uv,slot:0)==background,"Nonfinite v2 interpolants are discarded before integer conversion")
        }
        for sampling in [SIMD4<Float>(0,1,1,0),SIMD4<Float>(3,1,1,0),SIMD4<Float>(1,2,1,0),SIMD4<Float>(6,1,2,0),SIMD4<Float>(6,1,1,1)] {
            try require(render(fixture,route:routes[0],uv:.zero,slot:0,badSampling:sampling)==background,"Invalid v2 GPU sampler record is discarded")
        }
    }
}
private let byName=Dictionary(uniqueKeysWithValues:fixtures.map{($0.name,$0)})
private let oldEdge=render(byName["v1compare"]!,route:routes[0],uv:.zero,slot:1)
private let wrappedEdge=render(byName["v2comparelinear"]!,route:routes[0],uv:.zero,slot:1)
try require(oldEdge != wrappedEdge,"Literal retained v1 inset differs from source-repeat cross-edge interpolation")
private let oldPoint=render(byName["v1compare"]!,route:routes[0],uv:SIMD2(0.17,0.73),slot:1)
private let nativePoint=render(byName["v2comparepoint"]!,route:routes[0],uv:SIMD2(0.17,0.73),slot:1)
try require(oldPoint != nativePoint,"Literal retained v1 linear differs from source-native nearest")
for name in ["v2nearest","v2linear","v2linear2","v2mixed"] {
    let fixture=byName[name]!
    let a=render(fixture,route:routes[0],uv:SIMD2(0.17,0.73),slot:1)
    let b=render(fixture,route:routes[0],uv:SIMD2(2.17,-3.27),slot:1)
    try require(zip(center(a),center(b)).allSatisfy{abs($0-$1)<=3},"V2 periodic repeat including negative UV")
}
try require(render(byName["v2linear"]!,route:routes[0],uv:SIMD2(0.17,0.73),slot:1)==render(byName["v2linear2"]!,route:routes[0],uv:SIMD2(0.17,0.73),slot:1),"Native2/6 use identical base-linear texels for one-level PNGs")
let report:[String:Any]=["status":"PASS","checks":checks,"renders":renders,"device":device.name,"fixtures":names,
    "unmodifiedProductionShaders":true,"actualPNGTextureLoader":true,"actualBlendAndUniformABI":true,
    "independentIsolatedHardwareRepeatSampler":true,
    "vertexRoutes":routes,"retailRuntimeVerified":false,"phoneOrSimulatorUsed":false,
    "samplingPolicy":"V1 exact existing inset; V2 found-native repeat nearest/base-linear, no generated mips; retail runtime remains unverified"]
try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("gpu-report.json"))
print("PASS \(checks) checks / \(renders) actual offscreen Metal renders; independently authored fixtures")
