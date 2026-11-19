// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// The declared WRL2 mapping selects original 256px world images. No texture
/// is resized to satisfy a budget; an unavailable HD family keeps base detail.
struct NativeWorldSharpLayout {
    enum Invalid:Error {case dimensions,mapping,budget}
    static let cellSize=256,columns=8,maximumLayers=384
    static let maximumGPUBytes=96*1024*1024
    let baseLayers:Int,sharpLayers:Int,width:Int,height:Int
    let map:[UInt32],baseTexelBytes:Int,fullMipTexelBytes:Int

    init(world:WorldBinary,sharpLayers:Int,width:Int,height:Int)throws {
        try self.init(baseLayers:world.layers,mapping:world.sharpLayers,sharpLayers:sharpLayers,width:width,height:height)
    }
    init(baseLayers:Int,mapping:[UInt16],sharpLayers:Int,width:Int,height:Int)throws {
        guard (1...Self.maximumLayers).contains(sharpLayers),
              width==Self.columns*Self.cellSize,
              height==((sharpLayers+Self.columns-1)/Self.columns)*Self.cellSize,
              height<=16_384 else{throw Invalid.dimensions}
        guard (1...4096).contains(baseLayers),mapping.count==baseLayers,
              mapping.allSatisfy({Int($0)<=sharpLayers}),mapping.contains(where:{$0>0}) else{throw Invalid.mapping}
        var size=Self.cellSize,perLayer=0
        while true{perLayer+=size*size*4;if size==1{break};size/=2}
        let bytes=sharpLayers*perLayer
        guard bytes<=Self.maximumGPUBytes else{throw Invalid.budget}
        self.baseLayers=baseLayers;self.sharpLayers=sharpLayers
        self.width=width;self.height=height
        map=[UInt32(baseLayers),UInt32(sharpLayers),0,0]+mapping.map(UInt32.init)
        baseTexelBytes=sharpLayers*Self.cellSize*Self.cellSize*4;fullMipTexelBytes=bytes
    }
    /// Check dimensions before handing encoded pixels to the platform decoder.
    /// The native producer emits single, noninterlaced RGBA8 PNG images.
    func acceptsPNG(_ data:Data)->Bool {
        guard (33...64*1024*1024).contains(data.count) else{return false}
        let b=[UInt8](data.prefix(33))
        func word(_ p:Int)->UInt32{UInt32(b[p])<<24|UInt32(b[p+1])<<16|UInt32(b[p+2])<<8|UInt32(b[p+3])}
        return Array(b[0..<8])==[137,80,78,71,13,10,26,10] && word(8)==13 &&
            Array(b[12..<16])==[73,72,68,82] && word(16)==width && word(20)==height &&
            Array(b[24..<29])==[8,6,0,0,0]
    }
    func rectangle(layer:Int)->[Int]? {
        guard (0..<sharpLayers).contains(layer)else{return nil}
        return [(layer%Self.columns)*Self.cellSize,(layer/Self.columns)*Self.cellSize,Self.cellSize,Self.cellSize]
    }
}
