import Foundation
import Metal
import simd

/// Metal presentation of the public generic FX shader and original texture
/// arrays. Physics values remain Double until the same final Float32 packing
/// the browser uses for its instanced attributes.
final class NativeParticleRenderer {
    struct Sheet:Decodable {var width:Int;var height:Int;var colorSpace:String;var layers:Int;var file:String;var magFilter:Int;var minFilter:Int;var generateMipmaps:Bool;var anisotropy:Int}
    struct Sprite:Decodable {var sheet:Int;var layer:Int}
    struct Document:Decodable {var sheets:[Sheet];var sprites:[String:Sprite]}
    struct Instance {var place:SIMD4<Float>;var size:SIMD4<Float>;var color:SIMD4<Float>;var way:SIMD4<Float>;var kind:SIMD4<Float>}
    struct Uniforms {var projection:simd_float4x4;var viewRotation:simd_float4x4;var fogColor:SIMD4<Float>;var fog:SIMD4<Float>}
    let document:Document
    private let device:MTLDevice
    private let queue:MTLCommandQueue
    private let pipeline:MTLRenderPipelineState
    private let depth:MTLDepthStencilState
    private var textures:[Int:MTLTexture]=[:]
    private var samplers:[Int:MTLSamplerState]=[:]
    var ready:Bool{textures.count==document.sheets.count && !textures.isEmpty}
    init?(device:MTLDevice,queue:MTLCommandQueue,library:MTLLibrary,metadata:Data) {
        guard let document=try? JSONDecoder().decode(Document.self,from:metadata),!document.sheets.isEmpty,document.sheets.count<=8,
              document.sheets.allSatisfy({$0.width>0 && $0.height>0 && $0.width<=4096 && $0.height<=4096 && $0.layers>0 && $0.layers<=256}),
              document.sprites.values.allSatisfy({document.sheets.indices.contains($0.sheet) && $0.layer>=0 && $0.layer<document.sheets[$0.sheet].layers}),
              let vertex=library.makeFunction(name:"nativeFXVertex"),let fragment=library.makeFunction(name:"nativeFXFragment") else{return nil}
        let p=MTLRenderPipelineDescriptor();p.vertexFunction=vertex;p.fragmentFunction=fragment;p.colorAttachments[0].pixelFormat = .bgra8Unorm;p.depthAttachmentPixelFormat = .depth32Float
        let color=p.colorAttachments[0]!;color.isBlendingEnabled=true;color.sourceRGBBlendFactor = .one;color.destinationRGBBlendFactor = .oneMinusSourceAlpha;color.sourceAlphaBlendFactor = .one;color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        let d=MTLDepthStencilDescriptor();d.depthCompareFunction = .lessEqual;d.isDepthWriteEnabled=false
        guard let pipeline=try? device.makeRenderPipelineState(descriptor:p),let depth=device.makeDepthStencilState(descriptor:d) else{return nil}
        self.device=device;self.queue=queue;self.pipeline=pipeline;self.depth=depth;self.document=document
    }
    func install(sheet index:Int,data:Data)->Bool {
        guard document.sheets.indices.contains(index) else{return false}
        let sheet=document.sheets[index],bytesPerImage=sheet.width*sheet.height*4
        guard data.count==bytesPerImage*sheet.layers else{return false}
        let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:sheet.colorSpace=="srgb" ? .rgba8Unorm_srgb:.rgba8Unorm,width:sheet.width,height:sheet.height,mipmapped:sheet.generateMipmaps)
        d.textureType = .type2DArray;d.arrayLength=sheet.layers;d.storageMode = .shared;d.usage = .shaderRead
        guard let texture=device.makeTexture(descriptor:d) else{return false}
        data.withUnsafeBytes{bytes in
            for layer in 0..<sheet.layers{texture.replace(region:MTLRegionMake2D(0,0,sheet.width,sheet.height),mipmapLevel:0,slice:layer,withBytes:bytes.baseAddress!.advanced(by:layer*bytesPerImage),bytesPerRow:sheet.width*4,bytesPerImage:bytesPerImage)}
        }
        let s=MTLSamplerDescriptor();s.sAddressMode = .repeat;s.tAddressMode = .repeat;s.magFilter=sheet.magFilter==1003 ? .nearest:.linear
        s.minFilter=[1003,1004,1005].contains(sheet.minFilter) ? .nearest:.linear
        s.mipFilter=[1005,1008].contains(sheet.minFilter) ? .linear:[1004,1007].contains(sheet.minFilter) ? .nearest:.notMipmapped;s.maxAnisotropy=max(1,min(16,sheet.anisotropy))
        guard let sampler=device.makeSamplerState(descriptor:s) else{return false}
        if sheet.generateMipmaps {
            guard let command=queue.makeCommandBuffer(),let blit=command.makeBlitCommandEncoder() else{return false}
            blit.generateMipmaps(for:texture);blit.endEncoding();command.commit()
        }
        textures[index]=texture;samplers[index]=sampler;return true
    }
    func instances(_ particles:[NativeParticleEffects.Particle],eye:SIMD3<Double>,view:simd_float4x4,projection:simd_float4x4)->[Instance] {
        let rotation=simd_double3x3(columns:(SIMD3<Double>(SIMD3(view.columns.0.x,view.columns.0.y,view.columns.0.z)),SIMD3<Double>(SIMD3(view.columns.1.x,view.columns.1.y,view.columns.1.z)),SIMD3<Double>(SIMD3(view.columns.2.x,view.columns.2.y,view.columns.2.z))))
        var rows:[(Int,Int,Double,NativeParticleEffects.Particle,Sprite)]=[]
        for(index,p)in particles.enumerated() where p.on {
            guard let name=p.emitter?.texture,let sprite=document.sprites[name] else{continue}
            var center=p.position
            if p.flat{let c=cos(p.turned),s=sin(p.turned);center+=SIMD3(p.across*c+p.up*s,p.across*s-p.up*c,0)}
            let camera=rotation*(center-eye)
            let depth=Double(projection.columns.0.z)*camera.x+Double(projection.columns.1.z)*camera.y+Double(projection.columns.2.z)*camera.z+Double(projection.columns.3.z)
            rows.append((p.rank,index,depth,p,sprite))
        }
        rows.sort{a,b in a.0 != b.0 ? a.0<b.0:a.2 != b.2 ? a.2>b.2:a.1<b.1}
        return rows.map{_,_,_,p,sprite in
            Instance(place:SIMD4<Float>(SIMD4(p.position-eye,p.turned)),size:SIMD4(Float(p.wide),Float(p.tall),Float(p.across),Float(p.up)),color:SIMD4<Float>(SIMD4(p.color,p.shows)),way:SIMD4<Float>(SIMD4(p.velocity,p.flat ? 0:p.trail)),kind:SIMD4(Float(sprite.layer),Float(sprite.sheet),p.flat ? 1:0,p.adds ? 1:0))
        }
    }
    func draw(_ particles:[NativeParticleEffects.Particle],eye:SIMD3<Float>,view:simd_float4x4,projection:simd_float4x4,
              fogColor:SIMD3<Float>,fogNear:Float,fogFar:Float,fogAmount:Float,encoder:MTLRenderCommandEncoder) {
        guard ready else{return}
        let values=instances(particles,eye:SIMD3<Double>(eye),view:view,projection:projection)
        guard !values.isEmpty,let buffer=device.makeBuffer(bytes:values,length:values.count*MemoryLayout<Instance>.stride) else{return}
        var rotation=view;rotation.columns.3=SIMD4(0,0,0,1)
        var uniforms=Uniforms(projection:projection,viewRotation:rotation,fogColor:SIMD4(fogColor,1),fog:SIMD4(fogNear,fogFar,fogAmount,0))
        encoder.setRenderPipelineState(pipeline);encoder.setDepthStencilState(depth)
        encoder.setVertexBuffer(buffer,offset:0,index:0);encoder.setVertexBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1);encoder.setFragmentBytes(&uniforms,length:MemoryLayout<Uniforms>.stride,index:1)
        for index in 0..<8{encoder.setFragmentTexture(textures[index] ?? textures[0],index:index);encoder.setFragmentSamplerState(samplers[index] ?? samplers[0],index:index)}
        encoder.drawPrimitives(type:.triangle,vertexStart:0,vertexCount:6,instanceCount:values.count)
    }
}
