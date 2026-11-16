// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CoreGraphics
import CoreText
import Metal
import simd

/// Native object material84/44 resolution. Texture lookup is injected and exact;
/// this owner never substitutes a similarly named texture from another TXD.
/// Wire texture colors are ABGR, text colors ARGB (open.mp object.hpp, commit
/// 72bf89ce4c8164f7f7b8271ffc7323bc45ea005f). Public API color0 inherits the
/// existing color. Text dimensions/alignment follow open.mp's published tables.
enum NativeSAMPObjectMaterials {
    struct Limits {
        var cacheEntries = 128
        var cacheBytes = 128 * 1024 * 1024
        var fontEntries = 32
        var nameBytes = 128
        var textUTF8Bytes = 8_192
        var textUTF16Units = 4_096
    }
    enum Failure: Error, CustomStringConvertible {
        case invalid(String), limit, unresolvedTexture(String, String), unavailableFont(String), graphics, gpu
        var description: String {
            switch self {
            case .invalid(let s): return "Invalid object material: \(s)"
            case .limit: return "Object material resource limit"
            case .unresolvedTexture(let d,let t): return "Unresolved exact object texture \(d)/\(t)"
            case .unavailableFont(let s): return "Object material font unavailable: \(s)"
            case .graphics: return "Object text rasterization failed"
            case .gpu: return "Object material GPU upload failed"
            }
        }
    }
    struct Text: Hashable {
        let size: UInt8, font: String, fontSize: UInt8, bold: Bool
        let foregroundARGB: UInt32, backgroundARGB: UInt32
        let alignment: UInt8, text: String
    }
    struct Image {
        let width: Int, height: Int
        /// Top-down straight-alpha RGBA8 in sRGB component space.
        let rgba8: Data
        let containsTransparency: Bool
        let lineCount: Int
        let clipped: Bool
        let actualFont: String
    }
    struct TextureRequest: Hashable {
        /// Signed wire16 model; -1 is color-only, 0 is the documented alpha case.
        let model: Int32
        let dictionary: String
        let texture: String
    }
    struct Texture {
        let image: MTLTexture
        let sampler: MTLSamplerState?
        let containsTransparency: Bool
    }
    typealias TextureResolver = (TextureRequest) throws -> Texture?
    typealias FontResolver = (String, CGFloat, Bool) throws -> CTFont
    struct Resolved {
        let texture: MTLTexture?
        let sampler: MTLSamplerState?
        let materialColor: SIMD4<Float>?
        let blend: Bool?
        let ignoreVertexColor: Bool
        let clippedText: Bool
        let font: String?
        func apply(to value: inout NativeRenderWareModel.DrawOverrides) {
            if let texture { value.textureOverride = texture }
            if let sampler { value.samplerOverride = sampler }
            if let materialColor { value.materialColorOverride = materialColor }
            if let blend { value.blendOverride = blend }
            if ignoreVertexColor { value.ignoreVertexColor = true }
        }
    }
    static func dimensions(_ size: UInt8) throws -> (width: Int,height: Int) {
        let values = [(32,32),(64,32),(64,64),(128,32),(128,64),(128,128),(256,32),(256,64),(256,128),(256,256),(512,64),(512,128),(512,256),(512,512)]
        guard size >= 10,size <= 140,size % 10 == 0 else { throw Failure.invalid("text size") }
        return values[Int(size/10)-1]
    }
    static func argb(_ n: UInt32) -> SIMD4<Float> { SIMD4(Float((n>>16)&255),Float((n>>8)&255),Float(n&255),Float(n>>24))/255 }
    static func abgr(_ n: UInt32) -> SIMD4<Float> { SIMD4(Float(n&255),Float((n>>8)&255),Float((n>>16)&255),Float(n>>24))/255 }
    private static func color(_ value: SIMD4<Float>,_ space: CGColorSpace) -> CGColor {
        CGColor(colorSpace:space,components:[CGFloat(value.x),CGFloat(value.y),CGFloat(value.z),CGFloat(value.w)])!
    }
    static func systemFont(_ name: String,size: CGFloat,bold: Bool) throws -> CTFont {
        let base=CTFontCreateWithName(name as CFString,size,nil)
        func normalized(_ s:String)->String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        let wanted=normalized(name),family=normalized(CTFontCopyFamilyName(base) as String),postscript=normalized(CTFontCopyPostScriptName(base) as String)
        let full=normalized(CTFontCopyFullName(base) as String)
        guard wanted==family || wanted==postscript || wanted==full else { throw Failure.unavailableFont(name) }
        if !bold { return base }
        guard let font=CTFontCreateCopyWithSymbolicTraits(base,size,nil,.traitBold,.traitBold),
              CTFontGetSymbolicTraits(font).contains(.traitBold) else { throw Failure.unavailableFont(name+" bold") }
        return font
    }
    static func rasterize(_ value: Text,limits: Limits = Limits(),fontResolver: FontResolver? = nil) throws -> Image {
        let (width,height)=try dimensions(value.size)
        guard value.fontSize>0,value.alignment<=2,!value.font.isEmpty,
              !value.font.unicodeScalars.contains(where:{$0.value<32 || $0.value==127}) else { throw Failure.invalid("font/alignment") }
        guard value.font.utf8.count<=limits.nameBytes,value.text.utf8.count<=limits.textUTF8Bytes,
              value.text.utf16.count<=limits.textUTF16Units,width*height*4<=limits.cacheBytes else { throw Failure.limit }
        let font=try (fontResolver ?? {try systemFont($0,size:$1,bold:$2)})(value.font,CGFloat(value.fontSize),value.bold)
        guard let space=CGColorSpace(name:CGColorSpace.sRGB) else { throw Failure.graphics }
        var alignment: CTTextAlignment = value.alignment==0 ? .left:value.alignment==1 ? .center:.right
        var lineBreak=CTLineBreakMode.byWordWrapping
        let paragraph: CTParagraphStyle = withUnsafePointer(to:&alignment) { alignment in
            withUnsafePointer(to:&lineBreak) { lineBreak in
                var settings=[CTParagraphStyleSetting(spec:.alignment,valueSize:MemoryLayout<CTTextAlignment>.size,value:alignment),
                              CTParagraphStyleSetting(spec:.lineBreakMode,valueSize:MemoryLayout<CTLineBreakMode>.size,value:lineBreak)]
                return CTParagraphStyleCreate(&settings,settings.count)
            }
        }
        let baseColor=argb(value.foregroundARGB)
        let attrs: [NSAttributedString.Key:Any] = [.init(kCTFontAttributeName as String):font,
            .init(kCTParagraphStyleAttributeName as String):paragraph,.init(kCTForegroundColorAttributeName as String):color(baseColor,space)]
        let text=NSMutableAttributedString(string:"")
        let source=value.text as NSString
        let matcher=try NSRegularExpression(pattern:"\\{([0-9a-fA-F]{6})\\}")
        var offset=0,current=attrs
        for match in matcher.matches(in:value.text,range:NSRange(location:0,length:source.length)) {
            text.append(NSAttributedString(string:source.substring(with:NSRange(location:offset,length:match.range.location-offset)),attributes:current))
            let rgb=UInt32(source.substring(with:match.range(at:1)),radix:16)!
            // Embedding changes RGB; preserve the explicitly requested font alpha.
            current[.init(kCTForegroundColorAttributeName as String)]=color(argb((value.foregroundARGB&0xff000000)|rgb),space)
            offset=match.range.location+match.range.length
        }
        text.append(NSAttributedString(string:source.substring(from:offset),attributes:current))
        let framesetter=CTFramesetterCreateWithAttributedString(text)
        let frame=CTFramesetterCreateFrame(framesetter,CFRange(location:0,length:0),CGPath(rect:CGRect(x:0,y:0,width:width,height:height),transform:nil),nil)
        var pixels=Data(count:width*height*4)
        let drew=pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context=CGContext(data:raw.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:space,
                                        bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.setFillColor(color(argb(value.backgroundARGB),space));context.fill(CGRect(x:0,y:0,width:width,height:height))
            context.setAllowsFontSmoothing(false);context.setShouldSmoothFonts(false);context.setShouldAntialias(true)
            context.textMatrix = .identity
            // Bitmap memory is top-down; Quartz/CoreText user coordinates are y-up.
            // Do not apply UIKit's extra vertical flip to this native bitmap.
            CTFrameDraw(frame,context)
            return true
        }
        guard drew else { throw Failure.graphics }
        var transparent=false
        pixels.withUnsafeMutableBytes { (raw:UnsafeMutableRawBufferPointer) in
            let p=raw.bindMemory(to:UInt8.self)
            for i in stride(from:0,to:p.count,by:4) {
                let a=Int(p[i+3]);transparent = transparent || a<255
                for channel in 0..<3 { p[i+channel]=a==0 ? 0:UInt8(min(255,(Int(p[i+channel])*255+a/2)/a)) }
            }
        }
        return Image(width:width,height:height,rgba8:pixels,containsTransparency:transparent,
                     lineCount:CFArrayGetCount(CTFrameGetLines(frame)),clipped:CTFrameGetVisibleStringRange(frame).length<text.length,
                     actualFont:CTFontCopyPostScriptName(font) as String)
    }

    final class Owner {
        private enum Key: Hashable { case texture(UInt16,String,String,UInt32),text(Text) }
        private struct FontKey: Hashable { let name:String,size:Int,bold:Bool }
        private struct Entry { let value: Resolved; let bytes: Int; var used: UInt64 }
        private let device: MTLDevice,limits:Limits,resolver:TextureResolver,fontResolver:FontResolver?
        private let lock=NSRecursiveLock()
        private var entries:[Key:Entry]=[:],bytes=0,clock:UInt64=0
        private var fonts:[FontKey:(font:CTFont,used:UInt64)]=[:]
        private let linear:MTLSamplerState,white:MTLTexture
        init(device:MTLDevice,limits:Limits=Limits(),textureResolver:@escaping TextureResolver,fontResolver:FontResolver?=nil)throws {
            guard limits.cacheEntries>0,limits.cacheEntries<=4_096,limits.cacheBytes>0,limits.fontEntries>0,limits.fontEntries<=512,
                  limits.nameBytes>0,limits.nameBytes<=255,limits.textUTF8Bytes>0,limits.textUTF8Bytes<=32_768,
                  limits.textUTF16Units>0,limits.textUTF16Units<=16_384 else { throw Failure.limit }
            self.device=device;self.limits=limits;resolver=textureResolver;self.fontResolver=fontResolver
            let descriptor=MTLSamplerDescriptor();descriptor.minFilter = .linear;descriptor.magFilter = .linear
            descriptor.sAddressMode = .clampToEdge;descriptor.tAddressMode = .clampToEdge
            guard let sampler=device.makeSamplerState(descriptor:descriptor) else { throw Failure.gpu };linear=sampler
            let t=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:1,height:1,mipmapped:false)
            t.storageMode = .shared;t.usage = .shaderRead
            guard let texture=device.makeTexture(descriptor:t) else { throw Failure.gpu };white=texture
            var rgba:UInt32=0xffffffff
            withUnsafeBytes(of:&rgba){texture.replace(region:MTLRegionMake2D(0,0,1,1),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:4)}
        }
        var cachedBytes:Int { lock.lock();defer{lock.unlock()};return bytes }
        var cachedCount:Int { lock.lock();defer{lock.unlock()};return entries.count }
        var cachedFontCount:Int { lock.lock();defer{lock.unlock()};return fonts.count }
        func reset(){lock.lock();defer{lock.unlock()};entries.removeAll();fonts.removeAll();bytes=0;clock=0}
        func resolve(_ material:NativeSAMPObjects.Material)throws->Resolved {
            lock.lock();defer{lock.unlock()};clock &+= 1
            let key:Key
            switch material {
            case .texture(let model,let dictionary,let texture,let abgr):
                guard dictionary.utf8.count<=limits.nameBytes,texture.utf8.count<=limits.nameBytes else { throw Failure.limit }
                key = .texture(model,dictionary,texture,abgr)
            case .text(let size,let font,let fontSize,let bold,let fg,let bg,let alignment,let text):
                guard font.utf8.count<=limits.nameBytes,text.utf8.count<=limits.textUTF8Bytes,text.utf16.count<=limits.textUTF16Units else { throw Failure.limit }
                key = .text(Text(size:size,font:font,fontSize:fontSize,bold:bold,foregroundARGB:fg,backgroundARGB:bg,alignment:alignment,text:text))
            }
            if var entry=entries[key]{entry.used=clock;entries[key]=entry;return entry.value}
            let value:Resolved,allocation:Int
            switch key {
            case .texture(let model,let dictionary,let texture,let tint):
                let color=tint==0 ? nil:abgr(tint),signed=Int32(Int16(bitPattern:model))
                if signed == -1 || (dictionary.lowercased()=="none" && texture.lowercased()=="none" && signed != 0) {
                    value=Resolved(texture:nil,sampler:nil,materialColor:color,blend:color.map{$0.w<1 ? true:nil} ?? nil,
                                   ignoreVertexColor:tint != 0,clippedText:false,font:nil);allocation=0
                } else if signed==0 {
                    value=Resolved(texture:white,sampler:linear,materialColor:color,blend:color.map{$0.w<1},ignoreVertexColor:tint != 0,clippedText:false,font:nil);allocation=4
                } else {
                    for name in [dictionary,texture] {
                        guard !name.isEmpty,!name.unicodeScalars.contains(where:{$0.value<32 || $0.value==127}),!name.contains("/"),!name.contains("\\") else { throw Failure.invalid("texture name") }
                        guard name.utf8.count<=limits.nameBytes else { throw Failure.limit }
                    }
                    guard let found=try resolver(TextureRequest(model:signed,dictionary:dictionary,texture:texture)) else { throw Failure.unresolvedTexture(dictionary,texture) }
                    allocation=try estimatedBytes(found.image)
                    value=Resolved(texture:found.image,sampler:found.sampler,materialColor:color,
                                   blend:found.containsTransparency || (color?.w ?? 1)<1 ? true:(tint != 0 ? false:nil),
                                   ignoreVertexColor:tint != 0,clippedText:false,font:nil)
                }
            case .text(let text):
                let image=try rasterize(text,limits:limits,fontResolver:{try self.font($0,size:$1,bold:$2)})
                let d=MTLTextureDescriptor.texture2DDescriptor(pixelFormat:.rgba8Unorm,width:image.width,height:image.height,mipmapped:false)
                d.storageMode = .shared;d.usage = .shaderRead
                guard let texture=device.makeTexture(descriptor:d) else { throw Failure.gpu }
                image.rgba8.withUnsafeBytes{texture.replace(region:MTLRegionMake2D(0,0,image.width,image.height),mipmapLevel:0,withBytes:$0.baseAddress!,bytesPerRow:image.width*4)}
                allocation=image.rgba8.count
                value=Resolved(texture:texture,sampler:linear,materialColor:SIMD4(repeating:1),blend:image.containsTransparency,
                               ignoreVertexColor:true,clippedText:image.clipped,font:image.actualFont)
            }
            guard allocation<=limits.cacheBytes else { throw Failure.limit }
            while entries.count>=limits.cacheEntries || allocation>limits.cacheBytes-bytes {
                guard let oldest=entries.min(by:{$0.value.used<$1.value.used}) else { throw Failure.limit }
                bytes-=oldest.value.bytes;entries.removeValue(forKey:oldest.key)
            }
            entries[key]=Entry(value:value,bytes:allocation,used:clock);bytes+=allocation;return value
        }
        private func estimatedBytes(_ texture:MTLTexture)throws->Int {
            guard texture.textureType == .type2D,texture.width>0,texture.height>0,texture.width<=16_384,texture.height<=16_384,texture.mipmapLevelCount<=15 else { throw Failure.invalid("resolved texture") }
            guard [.rgba8Unorm,.rgba8Unorm_srgb,.bgra8Unorm,.bgra8Unorm_srgb].contains(texture.pixelFormat) else { throw Failure.invalid("resolved texture pixel format") }
            var total=0
            for level in 0..<texture.mipmapLevelCount {
                let size=max(1,texture.width>>level)*max(1,texture.height>>level)*4
                guard size<=limits.cacheBytes-total else { throw Failure.limit };total+=size
            }
            return total
        }
        private func font(_ name:String,size:CGFloat,bold:Bool)throws->CTFont {
            let key=FontKey(name:name,size:Int(size),bold:bold)
            if let found=fonts[key]{fonts[key]=(found.font,clock);return found.font}
            let font=try (fontResolver ?? {try systemFont($0,size:$1,bold:$2)})(name,size,bold)
            if fonts.count>=limits.fontEntries,let oldest=fonts.min(by:{$0.value.used<$1.value.used}){fonts.removeValue(forKey:oldest.key)}
            fonts[key]=(font,clock);return font
        }
    }
}
