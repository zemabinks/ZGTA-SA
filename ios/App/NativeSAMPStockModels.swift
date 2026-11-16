// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Exact owner-local stock IDE/raw-file metadata. A file being present does not
/// establish that the DFF/TXD importer, collision or rendering supports it.
struct NativeSAMPStockModels {
    struct Limits { var metadataBytes=16*1024*1024;var models=30_000;var assets=50_000;var parentDepth=32 }
    enum Failure: Error { case malformed,limit,invalidPath,missingModel(Int32),cycle }
    enum Kind:String,Decodable { case object,timed,animated,vehicle,ped,weapon,hierarchy }
    struct Model:Decodable {let id:Int32;let kind:Kind;let model,txd,source:String;let line:Int}
    struct Asset:Decodable {let path:String;let bytes:Int;let crc32:UInt32;let sha256:String}
    struct File {let metadata:Asset;let url:URL}
    struct Dictionary {let name:String;let file:File?}
    struct Resolution {
        let model:Model
        let dff:File?
        /// Explicit child -> parent chain, including unavailable dictionary names.
        let dictionaries:[Dictionary]
        /// Vehicle generic is searched first by the supporting engine reference.
        let textureSearch:[Dictionary]
        var missingDFF:String?{dff == nil ? model.model+".dff":nil}
        var missingTXDs:[String]{dictionaries.filter{$0.file==nil}.map{$0.name+".txd"}}
        var allFilesAvailable:Bool{dff != nil && missingTXDs.isEmpty}
    }
    private struct Manifest:Decodable {
        let schema:Int;let models:[Model];let parents:[String:String];let assets:[String:Asset]
        let vehicleDictionary:String;let vehicleGenericFirst:Bool
    }
    private let models:[Int32:Model],parents:[String:String],assets:[String:Asset],vehicleDictionary:String
    private let vehicleGenericFirst:Bool,maximumParentDepth:Int
    var count:Int{models.count}
    var modelIDs:[Int32]{models.keys.sorted()}
    static func decode(_ data:Data,limits:Limits=Limits())throws->Self{
        guard limits.metadataBytes>0,limits.models>0,limits.models<=100_000,limits.assets>0,limits.assets<=100_000,
              limits.parentDepth>0,limits.parentDepth<=128 else{throw Failure.limit}
        guard data.count<=limits.metadataBytes else{throw Failure.limit}
        let value=try JSONDecoder().decode(Manifest.self,from:data)
        guard value.schema==1,value.models.count<=limits.models,value.assets.count<=limits.assets,value.parents.count<=limits.assets else{throw Failure.limit}
        var models:[Int32:Model]=[:]
        for row in value.models{
            guard (0...19999).contains(row.id),validName(row.model),validName(row.txd),validPath(row.source),row.line>0,
                  models.updateValue(row,forKey:row.id)==nil else{throw Failure.malformed}
        }
        for (name,asset) in value.assets{
            guard name==name.lowercased(),validPath(name),!name.contains("/"),name.hasSuffix(".dff") || name.hasSuffix(".txd"),
                  validPath(asset.path),asset.bytes>=12,asset.bytes<=64*1024*1024,asset.sha256.count==64,
                  asset.sha256.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else{throw Failure.invalidPath}
        }
        guard validName(value.vehicleDictionary) else{throw Failure.malformed}
        for (child,parent) in value.parents{guard validName(child),validName(parent)else{throw Failure.malformed}}
        let result=Self(models:models,parents:value.parents,assets:value.assets,vehicleDictionary:value.vehicleDictionary,
                        vehicleGenericFirst:value.vehicleGenericFirst,maximumParentDepth:limits.parentDepth)
        for name in value.parents.keys{_ = try result.chain(name)}
        return result
    }
    func model(_ id:Int32)->Model?{models[id]}
    func dictionary(named name:String,assetBaseURL:URL)throws->Dictionary{
        guard Self.validName(name.lowercased())else{throw Failure.invalidPath}
        return Dictionary(name:name.lowercased(),file:try file(name.lowercased()+".txd",base:assetBaseURL))
    }
    func resolve(id:Int32,assetBaseURL:URL)throws->Resolution{
        guard let model=models[id]else{throw Failure.missingModel(id)}
        let dictionaries=try chain(model.txd).map{try dictionary(named:$0,assetBaseURL:assetBaseURL)}
        var search=dictionaries
        if model.kind == .vehicle,vehicleGenericFirst,let generic=search.firstIndex(where:{$0.name==vehicleDictionary}){
            let value=search.remove(at:generic);search.insert(value,at:0)
        }
        return Resolution(model:model,dff:try file(model.model+".dff",base:assetBaseURL),dictionaries:dictionaries,textureSearch:search)
    }
    private func chain(_ dictionary:String)throws->[String]{
        var result:[String]=[],current:String?=dictionary
        while let value=current{
            guard !result.contains(value),result.count<maximumParentDepth else{throw Failure.cycle}
            result.append(value);current=parents[value]
        }
        return result
    }
    private func file(_ name:String,base:URL)throws->File?{
        guard let asset=assets[name]else{return nil}
        guard ["http","https","file"].contains(base.scheme?.lowercased() ?? ""),base.user==nil,base.password==nil,base.query==nil,base.fragment==nil else{throw Failure.invalidPath}
        var result=base
        for part in asset.path.split(separator:"/"){result.appendPathComponent(String(part))}
        return File(metadata:asset,url:result)
    }
    private static func validName(_ value:String)->Bool{
        !value.isEmpty && value.utf8.count<=128 && value==value.lowercased() && !value.contains("..") &&
        value.utf8.allSatisfy{(97...122).contains($0)||(48...57).contains($0)||[95,35,40,41,43,45,46].contains($0)}
    }
    private static func validPath(_ value:String)->Bool{
        !value.isEmpty && value.utf8.count<=1_024 && value.split(separator:"/",omittingEmptySubsequences:false).allSatisfy{part in
            !part.isEmpty && part != "." && part != ".." && part.utf8.allSatisfy{(65...90).contains($0)||(97...122).contains($0)||(48...57).contains($0)||[95,35,40,41,43,45,46].contains($0)}
        }
    }
}
