import Foundation
import CoreFoundation

/// Retail/SA-MP skin IDs and the browser catalogue's compact IDs are different
/// namespaces. Resolve them only through the owner-imported model-name join.
struct NativeSAMPSkinCatalog {
    struct Mapping: Equatable {let legacyID:Int;let nativeID:Int?;let model:String}
    enum Error:Swift.Error{case invalid}
    let mappings:[Int:Mapping]
    init(data:Data)throws{
        guard data.count<=2_000_000,let object=try JSONSerialization.jsonObject(with:data)as?[String:Any],
              Self.integer(object["schema"])==1,let rows=object["skins"]as?[[String:Any]],!rows.isEmpty,rows.count<=512 else{throw Error.invalid}
        var result:[Int:Mapping]=[:]
        for row in rows{
            guard let id=Self.integer(row["legacyID"]),(0...311).contains(id),result[id]==nil,
                  let model=row["model"]as?String,(1...40).contains(model.utf8.count),model.utf8.allSatisfy({(97...122).contains($0)||(48...57).contains($0)||$0==95})else{throw Error.invalid}
            let native:Int?
            if row["nativeID"] == nil || row["nativeID"]is NSNull{native=nil}
            else{guard let value=Self.integer(row["nativeID"]),(0...65535).contains(value)else{throw Error.invalid};native=value}
            result[id]=Mapping(legacyID:id,nativeID:native,model:model)
        }
        mappings=result
    }
    private static func integer(_ value:Any?)->Int?{
        guard let number=value as?NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),number.doubleValue.isFinite,
              let value=Int(exactly:number.doubleValue)else{return nil};return value
    }
    func nativeSkin(forLegacy id:Int)->Int?{mappings[id]?.nativeID}
    func model(forLegacy id:Int)->String?{mappings[id]?.model}
}
