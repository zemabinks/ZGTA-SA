import Foundation
import CoreFoundation

/// Retail/SA-MP skin IDs and the browser catalogue's compact IDs are different
/// namespaces. Resolve them only through the owner-imported model-name join.
struct NativeSAMPSkinCatalog {
    struct Mapping: Equatable {let legacyID:Int;let nativeID:Int?;let model:String;var femaleActivity=false}
    enum Error:Swift.Error{case invalid}
    let sourceIdentity:String?
    let mappings:[Int:Mapping]
    private let activityProfiles:[String:Bool]
    init(data:Data,sourceIdentity:String?=nil)throws{
        self.sourceIdentity=sourceIdentity
        guard data.count<=2_000_000,let object=try JSONSerialization.jsonObject(with:data)as?[String:Any],
              Self.integer(object["schema"])==1,let rows=object["skins"]as?[[String:Any]],!rows.isEmpty,rows.count<=512 else{throw Error.invalid}
        var result:[Int:Mapping]=[:],profiles:[String:Bool]=[:]
        for row in rows{
            guard let id=Self.integer(row["legacyID"]),(0...311).contains(id),result[id]==nil,
                  let model=row["model"]as?String,(1...40).contains(model.utf8.count),model.utf8.allSatisfy({(97...122).contains($0)||(48...57).contains($0)||$0==95})else{throw Error.invalid}
            let native:Int?
            if row["nativeID"] == nil || row["nativeID"]is NSNull{native=nil}
            else{guard let value=Self.integer(row["nativeID"]),(0...65535).contains(value)else{throw Error.invalid};native=value}
            var female=false
            if let value=row["femaleActivity"] {
                guard let number=value as?NSNumber,CFGetTypeID(number)==CFBooleanGetTypeID()else{throw Error.invalid}
                female=number.boolValue
            }
            if let previous=profiles[model],previous != female{throw Error.invalid}
            profiles[model]=female
            result[id]=Mapping(legacyID:id,nativeID:native,model:model,femaleActivity:female)
        }
        mappings=result;activityProfiles=profiles
    }
    private static func integer(_ value:Any?)->Int?{
        guard let number=value as?NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),number.doubleValue.isFinite,
              let value=Int(exactly:number.doubleValue)else{return nil};return value
    }
    /// Exact model identity only. Older prepared catalogs retain the previous
    /// default until regenerated from the owner's original voice-bank fields.
    func femaleActivity(forModel model:String,sourceIdentity:String?=nil)->Bool {
        guard self.sourceIdentity==sourceIdentity else{return false}
        return activityProfiles[model] ?? false
    }
    func nativeSkin(forLegacy id:Int)->Int?{mappings[id]?.nativeID}
    func model(forLegacy id:Int)->String?{mappings[id]?.model}
    /// Protocol identity is separate from render readiness. Canonical zero is
    /// the composite player; the renderer must admit its declared profile.
    /// Other retail IDs still require the exact imported ordinary-ped join.
    static func canonicalSkin(legacyID:Int,customID:Int?,catalog:Self?)->Int? {
        if let customID,(20001...30000).contains(customID){return customID}
        if legacyID==0{return 0}
        return catalog?.nativeSkin(forLegacy:legacyID)
    }
}
