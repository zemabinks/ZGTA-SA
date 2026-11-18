import Foundation
import CryptoKit

/// Versioned ordinary-ped atlas family. Existing model-index maps remain strings.
/// Only explicit pedAtlasV1 entries select this family; no implicit PNG upgrade.
struct NativePedAtlasFamily:Decodable {
    struct Resource:Decodable {
        let path:String
        let bytes:Int
        let sha256:String
        func validate()throws {
            let pieces=path.split(separator:"/",omittingEmptySubsequences:false)
            guard path.hasPrefix("game/native/models/"),path.utf8.count<=240,
                  pieces.allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".."}),
                  path.utf8.allSatisfy({(48...57).contains($0)||(65...90).contains($0)||(97...122).contains($0)||[45,46,47,95].contains($0)}),
                  bytes>0,bytes<=8*1024*1024,NativePedAtlasLayout.digestString(sha256) else{throw NativePedAtlasLayout.Invalid.family}
        }
        func validate(_ data:Data)throws {
            try validate()
            guard data.count==bytes,NativePedAtlasLayout.digest(data)==sha256 else{throw NativePedAtlasLayout.Invalid.family}
        }
    }
    struct Resources:Decodable {
        let mesh:Resource,atlas:Resource,layout:Resource,skeleton:Resource
        let hand:Resource?,parts:Resource?
        var all:[String:Resource] {
            var result=["mesh":mesh,"atlas":atlas,"layout":layout,"skeleton":skeleton]
            if let hand{result["hand"]=hand};if let parts{result["parts"]=parts};return result
        }
    }
    let schema:Int
    let format:String
    let model:String
    let sourceIdentity:String
    let resources:Resources
    func validate(expectedModel:String)throws {
        guard schema==1,format=="zgta-ped-atlas-family-v1",model==expectedModel,
              NativePedAtlasLayout.digestString(sourceIdentity),
              !model.isEmpty,model.utf8.count<=64,model != "null",!model.hasPrefix("samp-dl-"),
              model.utf8.allSatisfy({(48...57).contains($0)||(97...122).contains($0)||[45,95].contains($0)}) else{throw NativePedAtlasLayout.Invalid.family}
        let suffixes=["mesh":".bin","atlas":".png","layout":".atlas.json","skeleton":".skel.bin","hand":".hand.bin","parts":".parts.json"]
        for (role,resource) in resources.all {
            try resource.validate()
            guard resource.path=="game/native/models/ped-atlas-v1/\(resource.sha256)/\(model)\(suffixes[role]!)" else{throw NativePedAtlasLayout.Invalid.family}
        }
        guard Set(resources.all.values.map(\.path)).count==resources.all.count,
              resources.all.values.reduce(0,{$0+$1.bytes})<=16*1024*1024 else{throw NativePedAtlasLayout.Invalid.family}
    }
    func validateSource(layout:NativePedAtlasLayout)throws {
        var canonical:[String:Any]=["model":model,"sourceDFFSHA256":layout.sourceDFFSHA256]
        if let txd=layout.sourceTXDSHA256{canonical["sourceTXDSHA256"]=txd}else{canonical["sourceTXDSHA256"]=NSNull()}
        let data=try JSONSerialization.data(withJSONObject:canonical,options:[.sortedKeys])
        guard NativePedAtlasLayout.digest(data)==sourceIdentity else{throw NativePedAtlasLayout.Invalid.family}
    }
    static func digest(in path:String,model:String)->String? {
        let pieces=path.split(separator:"/",omittingEmptySubsequences:false)
        guard pieces.count==6,pieces[0]=="game",pieces[1]=="native",pieces[2]=="models",pieces[3]=="ped-atlas-v1",
              pieces[5]==Substring(model+".json"),NativePedAtlasLayout.digestString(String(pieces[4])) else{return nil}
        return String(pieces[4])
    }
}

struct NativePedAtlasLayout:Decodable {
    enum Invalid:Error {case family,format,dimensions,rectangles,mesh,atlas}
    struct Layer:Decodable {let slot:Int;let texture:String?;let rect:[Int]}
    struct Validated {
        /// Fragment buffer2: dimensions/count/version, followed by pixel rects.
        /// These do not share the vertex-stage skin/palette binding namespace.
        let vectors:[SIMD4<Float>]
        let width:Int,height:Int,textureBytes:Int
    }
    let schema:Int,layout:String,sampling:String
    let cell:[Int],columns:Int,atlas:[Int],layers:[Layer]
    let logicalRGBA8Bytes:Int,maximumRGBA8Bytes:Int
    let meshSHA256:String,atlasSHA256:String,sourceDFFSHA256:String
    let sourceTXDSHA256:String?
    static func digest(_ data:Data)->String{SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func digestString(_ value:String)->Bool{value.utf8.count==64 && value.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}}
    func validate(mesh:Data,png:Data,world:WorldBinary)throws->Validated {
        guard schema==1,layout=="ped-tight-native-v1",sampling=="legacy-inset-fract-linear-no-mips",
              Self.digestString(sourceDFFSHA256),sourceTXDSHA256.map(Self.digestString) ?? true,
              sourceTXDSHA256 != nil || layers.count==1 else{throw Invalid.format}
        guard Self.digest(mesh)==meshSHA256,world.layers==layers.count,!layers.isEmpty,layers.count<=4096 else{throw Invalid.mesh}
        let header=Array(png.prefix(24))
        guard Self.digest(png)==atlasSHA256,header.count==24,Array(header.prefix(8))==[137,80,78,71,13,10,26,10],
              Array(header[12..<16])==[73,72,68,82] else{throw Invalid.atlas}
        func u32(_ offset:Int)->Int{header[offset..<offset+4].reduce(0){$0*256+Int($1)}}
        guard cell.count==2,atlas.count==2,(1...4096).contains(cell[0]),(1...4096).contains(cell[1]),
              (1...8).contains(columns),(1...4096).contains(atlas[0]),(1...4096).contains(atlas[1]),
              columns*cell[0]==atlas[0],((layers.count+columns-1)/columns)*cell[1]==atlas[1],
              u32(16)==atlas[0],u32(20)==atlas[1],logicalRGBA8Bytes==atlas[0]*atlas[1]*4,
              logicalRGBA8Bytes<=maximumRGBA8Bytes,maximumRGBA8Bytes<=512*1024,maximumRGBA8Bytes>0 else{throw Invalid.dimensions}
        var values=[SIMD4(Float(atlas[0]),Float(atlas[1]),Float(layers.count),1)]
        var names=Set<String>()
        for (index,row) in layers.enumerated() {
            guard row.slot==index,row.rect.count==4 else{throw Invalid.rectangles}
            let r=row.rect
            guard r[0]==(index%columns)*cell[0],r[1]==(index/columns)*cell[1],
                  r[2]>0,r[2]<=cell[0],r[3]>0,r[3]<=cell[1] else{throw Invalid.rectangles}
            if index==0 {guard row.texture==nil else{throw Invalid.rectangles}}
            else {guard let texture=row.texture,!texture.isEmpty,texture.utf8.count<=256,names.insert(texture).inserted else{throw Invalid.rectangles}}
            values.append(SIMD4(Float(r[0]),Float(r[1]),Float(r[2]),Float(r[3])))
        }
        return Validated(vectors:values,width:atlas[0],height:atlas[1],textureBytes:logicalRGBA8Bytes)
    }
}
