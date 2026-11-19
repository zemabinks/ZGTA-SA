// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import MetalKit
import simd
import CryptoKit
private enum Failure:Error {case check(String),gpu}
private var checks=0,renders=0
private func require(_ value:Bool,_ name:String)throws{checks+=1;if !value{throw Failure.check(name)}}
private let out=URL(fileURLWithPath:CommandLine.arguments[1])
private func hash(_ data:Data)->String{SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
private var layout=try JSONSerialization.jsonObject(with:Data(contentsOf:out.appendingPathComponent("layout.json")))as![String:Any]
private let png=try Data(contentsOf:out.appendingPathComponent("atlas.png"))
private let imageProbe=PreparedImageProbe(),shortPNG=try Data(contentsOf:out.appendingPathComponent("short-native.png"))
try imageProbe.image(shortPNG,path:"authored-short-native",layers:4,cell:128,columns:8,exactSize:SIMD2(1024,16));checks+=1
private func imageRejected(_ exact:SIMD2<Int>?)throws {
    var rejected=false
    do{try imageProbe.image(shortPNG,path:"authored-short-native",layers:4,cell:128,columns:8,exactSize:exact)}catch{rejected=true}
    try require(rejected,"Actual prepared verifier rejects wrong native dimensions and short legacy atlas")
}
try imageRejected(nil);try imageRejected(SIMD2(1024,17));try imageRejected(SIMD2(512,16))
private func binary()->Data {
    var data=Data()
    func u32(_ x:UInt32){var v=x.littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}}
    func u16(_ x:UInt16){var v=x.littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}}
    u32(0x33435056);u32(12);u32(12);u32(4)
    for _ in 0..<12{for x:Float in [0,0,0]{u32(x.bitPattern)}}
    for _ in 0..<12{u32(0);u32(0)}
    for i in 0..<12{u32(UInt32(i))}
    data.append(Data(repeating:255,count:48))
    for slot:UInt16 in [1,2,1,0]{for _ in 0..<3{u16(slot)}}
    data.append(Data(repeating:255,count:48));for _ in 0..<4{u16(0)}
    return data
}
private let mesh=binary()
private let node:[String:Any]=["name":"authored","parent":-1,"position":[0,0,0],"rotation":[0,0,0,1],"scale":[1,1,1],"matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],"matrixAutoUpdate":true,"visible":true,"wheel":false,"damaged":false,"lowDetail":false]
private let paint:[String:Any]=["version":1,"vertexRGB":"neutral-paint-slot-rgb","palette":[[255,255,255],[128,0,0]],"defaults":[0,1],"colorVariants":[],"customFlag":16777216,"customLimit":33554432]
private let rows:[[String:Any]]=[1,2,1,0].enumerated().map{index,slot in ["node":0,"start":index*3,"count":3,"materialVisible":true,"lens":index==0 ? 0:-1,"texture":slot,"litTexture":index==0 ? 2:0,"alphaTest":0,"paint":-1,"color":[1,1,1],"opacity":1]}
private func metadata(_ layout:[String:Any])->[String:Any]{["version":3,"id":999,"kind":"car","nodes":[node],"draws":rows,"joints":["damage":[],"wheels":[],"rotors":[],"gear":[],"nozzles":[],"rearSteerOnly":false],"paint":paint,"binaryEncoding":"VPC3","binarySHA256":hash(mesh),"atlasSHA256":hash(png),"nativeTextures":layout]}
private func rig(_ layout:[String:Any])throws->NativeVehicleRig{guard let value=NativeVehicleRig(data:try JSONSerialization.data(withJSONObject:metadata(layout)))else{throw Failure.check("Authored valid VPC3 family rejected")};return value}
private let current=try rig(layout)
try require(current.validatesAssetFamily(binary:mesh,atlas:png),"Complete family digest admission")
try require(!current.validatesAssetFamily(binary:mesh+Data([0]),atlas:png),"Mixed mesh generation rejected")
try require(!current.validatesAssetFamily(binary:mesh,atlas:png+Data([0])),"Mixed image generation rejected")
private let world=try WorldBinary(data:current.meshData(mesh)!)
try require(current.validatesNativeTextureMesh(layerCount:world.layers,indexCount:world.indices.count,layerAtIndex:{world.vertices[Int(world.indices[$0])].uvLayer.z}),"Prepared/runtime share the actual native mesh contract")
try require(!current.validatesNativeTextureMesh(layerCount:world.layers+1,indexCount:world.indices.count,layerAtIndex:{_ in 0}),"Different staged layer count rejected")
try require(!current.validatesNativeTextureMesh(layerCount:world.layers,indexCount:world.indices.count,layerAtIndex:{_ in 0}),"Wrong material/image identity rejected")
try require(!current.validatesNativeTextureMesh(layerCount:world.layers,indexCount:1,layerAtIndex:{_ in 0}),"Truncated draw index buffer rejected before lookup")
private var state=NativeVehicleRig.State(),input=NativeVehicleRig.Input()
try require(current.pose(input,state:&state,delta:0).draws.map(\.texture)==[1,2,1,0],"Different native images never merge into one draw")
input.lights=true
try require(current.pose(input,state:&state,delta:0).draws.first?.texture==2,"Lamp selects original lit image")
input.brokenLights=[1,0,0,0]
try require(current.pose(input,state:&state,delta:0).draws.first?.texture==1,"Broken lamp restores base image")
private func rejected(_ value:[String:Any])throws{try require(NativeVehicleRig(data:JSONSerialization.data(withJSONObject:metadata(value)))==nil,"Malformed native layout rejected")}
for field in ["version","width","height","rgbaBytes"]{var bad=layout;bad[field]=0;try rejected(bad)}
private var bad=layout
bad["rects"]=[[0,0,1,1],[0,0,256,64],[257,0,64,256],[321,0,3,5]];try rejected(bad)
bad=layout;bad["samplers"]=[];try rejected(bad)
bad=layout;var invalid=layout["samplers"]as![[String:Any]];invalid[1]["minFilter"]=1009;bad["samplers"]=invalid;try rejected(bad)
bad=layout;invalid=layout["samplers"]as![[String:Any]];invalid[1]["minFilter"]=1008;bad["samplers"]=invalid;try rejected(bad)
// ACTUAL_UNIFORMS
private struct Formats{let colorPixelFormat:MTLPixelFormat = .bgra8Unorm,depthStencilPixelFormat:MTLPixelFormat = .invalid}
private func pipeline(_ device:MTLDevice,_ vertex:MTLFunction,_ fragment:MTLFunction)->MTLRenderPipelineState?{
    let view=Formats()
    // ACTUAL_PIPELINE
    return pipeline
}
if let device=MTLCreateSystemDefaultDevice(),let queue=device.makeCommandQueue(){
    let loader=MTKTextureLoader(device:device)
    let atlas=try loader.newTexture(data:png,options:[.SRGB:false,.generateMipmaps:false])
    let library=try device.makeLibrary(source:String(contentsOf:out.appendingPathComponent("production.metal")),options:nil)
    guard let vertex=library.makeFunction(name:"worldVertex"),let fragment=library.makeFunction(name:"vehicleNativeFragment"),let drawPipeline=pipeline(device,vertex,fragment)else{throw Failure.gpu}
    let imageDescription=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.bgra8Unorm,width:16,height:16,mipmapped:false)
    imageDescription.storageMode = .private;imageDescription.usage = .renderTarget
    let target=device.makeTexture(descriptor:imageDescription)!,read=device.makeBuffer(length:256*16,options:.storageModeShared)!
    let points:[SIMD4<Float>]=[SIMD4(-1,-1,0.5,1),SIMD4(1,-1,0.5,1),SIMD4(1,1,0.5,1),SIMD4(-1,1,0.5,1)]
    let indices:[UInt32]=[0,1,2,0,2,3],ib=device.makeBuffer(bytes:indices,length:24,options:.storageModeShared)!
    func render(_ images:NativeVehicleTextures,slot:Int,uv:SIMD2<Float>,scale:Float=0,reference:MTLTexture?=nil,referenceSampler:MTLSamplerState?=nil)throws->[UInt8]{
        renders+=1
        let vertices=points.map{NativeVertex(position:$0,uvLayer:SIMD4(uv.x+($0.x+1)*scale/2,uv.y+($0.y+1)*scale/2,Float(slot),0),tint:SIMD4(repeating:1),dusk:SIMD4(repeating:1))}
        let vb=device.makeBuffer(bytes:vertices,length:vertices.count*MemoryLayout<NativeVertex>.stride,options:.storageModeShared)!
        var uniforms=Uniforms(viewProjection:matrix_identity_float4x4,settings:SIMD4(1024,256,0,128))
        var material=SIMD4<Float>(-1,1,1,0),paint=SIMD4<Float>(1,1,1,0)
        let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
        let command=queue.makeCommandBuffer()!,encoder=command.makeRenderCommandEncoder(descriptor:pass)!
        encoder.setRenderPipelineState(drawPipeline);encoder.setCullMode(.none)
        encoder.setVertexBuffer(vb,offset:0,index:0);encoder.setVertexBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1)
        encoder.setFragmentBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1);encoder.setFragmentBytes(&material,length:16,index:2);encoder.setFragmentBytes(&paint,length:16,index:3)
        try images.bind(slot:slot,encoder:encoder,queue:queue)
        if let reference{encoder.setFragmentTexture(reference,index:0);encoder.setFragmentSamplerState(referenceSampler!,index:0)}
        encoder.drawIndexedPrimitives(type:.triangle,indexCount:6,indexType:.uint32,indexBuffer:ib,indexBufferOffset:0)
        encoder.endEncoding();let blit=command.makeBlitCommandEncoder()!
        blit.copy(from:target,sourceSlice:0,sourceLevel:0,sourceOrigin:MTLOrigin(x:0,y:0,z:0),sourceSize:MTLSize(width:16,height:16,depth:1),to:read,destinationOffset:0,destinationBytesPerRow:256,destinationBytesPerImage:4096)
        blit.endEncoding();command.commit();command.waitUntilCompleted();try require(command.status == .completed,"Actual GPU command completion")
        return Array(UnsafeBufferPointer(start:read.contents().assumingMemoryBound(to:UInt8.self).advanced(by:8*256+8*4),count:4))
    }
    let values:[SIMD2<Float>]=[SIMD2(0,0),SIMD2(0.5,0.5),SIMD2(0.99999,1.00001),SIMD2(-0.00001,0.00001),SIMD2(-1.25,2.125),SIMD2(7.125,-8.75)]
    for minFilter in 1003...1008 {for wrap in 1000...1002{
        var family=layout;family["samplers"]=(0..<4).map{_ in ["wrapS":wrap,"wrapT":1002-(wrap-1000),"magFilter":minFilter%2==0 ? 1006:1003,"minFilter":minFilter,"generateMipmaps":true]as[String:Any]}
        // Independent named-enum sampler oracle. Reference draws do not
        // reuse any production sampler state or mapping helper.
        let referenceDescription=MTLSamplerDescriptor()
        let addresses:[Int:MTLSamplerAddressMode]=[1000:.repeat,1001:.clampToEdge,1002:.mirrorRepeat]
        referenceDescription.sAddressMode=addresses[wrap]!
        referenceDescription.tAddressMode=addresses[1002-(wrap-1000)]!
        referenceDescription.magFilter=minFilter%2==0 ? .linear:.nearest
        referenceDescription.minFilter=[MTLSamplerMinMagFilter.nearest,.nearest,.nearest,.linear,.linear,.linear][minFilter-1003]
        referenceDescription.mipFilter=[MTLSamplerMipFilter.notMipmapped,.nearest,.linear,.notMipmapped,.nearest,.linear][minFilter-1003]
        let referenceSampler=device.makeSamplerState(descriptor:referenceDescription)!
        let r=try rig(family),images=try NativeVehicleTextures(device:device,queue:queue,atlas:atlas,rig:r,world:world)
        try require(images.allocatedBytes<=NativeVehicleTextures.maximumAllocationBytes,"Bounded actual GPU allocation")
        for slot in 0..<4 {
            let reference=try loader.newTexture(URL:out.appendingPathComponent("tile-\(slot).png"),options:[.SRGB:false,.generateMipmaps:[1004,1005,1007,1008].contains(minFilter)])
            let rect=(layout["rects"]as![[Int]])[slot]
            try require(images.textures[slot].width==rect[2] && images.textures[slot].height==rect[3],"Exact original image dimensions")
            try require(images.textures[slot].mipmapLevelCount==reference.mipmapLevelCount,"Explicit generated mip dimensions")
            for uv in values{
                let actual=try render(images,slot:slot,uv:uv),expected=try render(images,slot:slot,uv:uv,reference:reference,referenceSampler:referenceSampler)
                try require(zip(actual,expected).allSatisfy{abs(Int($0)-Int($1))<=1},"Native image equals isolated hardware sample at \(uv), slot \(slot), filter \(minFilter), wrap \(wrap): \(actual) vs \(expected)")
            }
            for scale:Float in [1,4,32] {
                let uv=SIMD2<Float>(-0.25,1.125)
                let actual=try render(images,slot:slot,uv:uv,scale:scale)
                let expected=try render(images,slot:slot,uv:uv,scale:scale,reference:reference,referenceSampler:referenceSampler)
                try require(zip(actual,expected).allSatisfy{abs(Int($0)-Int($1))<=1},"Actual minification/mip sampler differs at scale \(scale), slot \(slot), filter \(minFilter), wrap \(wrap)")
            }
        }
    }}
    for budget in [0,1]{do{_ = try NativeVehicleTextures(device:device,queue:queue,atlas:atlas,rig:current,world:world,maximumAllocationBytes:budget);throw Failure.check("Allocation budget ignored")}catch NativeVehicleTextures.Failure.budget{checks+=1}}
    let images=try NativeVehicleTextures(device:device,queue:queue,atlas:atlas,rig:current,world:world)
    let pass=MTLRenderPassDescriptor();pass.colorAttachments[0].texture=target;pass.colorAttachments[0].loadAction = .clear;pass.colorAttachments[0].storeAction = .store
    let command=queue.makeCommandBuffer()!,encoder=command.makeRenderCommandEncoder(descriptor:pass)!
    do{try images.bind(slot:1,encoder:encoder,queue:device.makeCommandQueue()!);throw Failure.check("Foreign queue admitted")}catch NativeVehicleTextures.Failure.queue{checks+=1}
    do{try images.bind(slot:128,encoder:encoder,queue:queue);throw Failure.check("Invalid image slot admitted")}catch NativeVehicleTextures.Failure.slot{checks+=1}
    encoder.endEncoding();command.commit();command.waitUntilCompleted()
    let report:[String:Any]=["status":"PASS","checks":checks,"renders":renders,"gpu":"PASS","device":device.name,"scope":"Authored native-size image upload and isolated hardware samples; generated mip allocation; actual rig image/lamp selection, bounds and family admission. Retail/stored TXD mips remain separate."]
    try JSONSerialization.data(withJSONObject:report,options:.prettyPrinted).write(to:out.appendingPathComponent("report.json"))
}else{
    if CommandLine.arguments.contains("--require-gpu"){throw Failure.gpu}
    try JSONSerialization.data(withJSONObject:["status":"PASS_SOURCE_GPU_UNAVAILABLE","checks":checks,"renders":0,"gpu":"UNAVAILABLE"]).write(to:out.appendingPathComponent("report.json"))
}
