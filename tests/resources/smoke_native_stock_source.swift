// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
var checks=0
func require(_ condition:@autoclosure()->Bool,_ message:String){checks+=1;if !condition(){fatalError(message)}}
final class Resource {}
final class Task {var cancellations=0;var onCancel:(()->Void)?;func cancel(){cancellations+=1;onCancel?()}}
final class CityLoader {var tasks:[Task]=[];func reset(){let retired=tasks;tasks.removeAll();for task in retired{task.cancel()}}}
final class Loader {var resets=0;@discardableResult func reset()->Int{resets+=1;return resets}}
final class GroundCells {
    var cells=Set<String>(),retentions=0
    func retainCells(_ names:Set<String>){cells.formIntersection(names);retentions+=1}
}
final class MaterialOwner {var resets=0;func reset(){resets+=1}}
final class Selection {var cancellations=0;func cancel(){cancellations+=1}}
final class CJ {var resets=0;func reset(){resets+=1}}
struct ServerAddress:Equatable {let value:String}
enum NativeSAMPObjectMaterials {
    struct TextureRequest:Hashable {let model:Int32;let dictionary,texture:String}
    struct Texture {let image:Resource}
}
final class Carrier {
    typealias Key=NativeSAMPObjectMaterials.TextureRequest
    var generation=0
    func fixedCJSourceIdentity()->String{"\(server?.value ?? "none")|\(generation)"}
    let actorSelection=Selection();var fixedCJ:CJ?=CJ(),needsFixedCJ=false,atlasInvalidations=0
    func invalidatePedAtlasSourceIfChanged(){atlasInvalidations+=1}
    func ensureFixedCJ(){fatalError("unrequested CJ load")}
    // Explicit cell/resource spies. Real parser/ground/Rapier behavior is
    // exercised separately by smoke_native_collision_source.
    let collisionCellLoader=CityLoader()
    var collisions:[String:Resource]=[:],collisionRequests=Loader()
    let groundVehicle:GroundCells?=GroundCells()
    var collisionLoading=Set<String>(),collisionRetryAfter:[String:Date]=[:]
    var collisionResourceSource:String?,collisionLoadTokens:[String:UUID]=[:],collisionLoadTasks:[String:Task]=[:]
    var legacyStockSource:String?,legacyStockMetadataEpoch:UInt64=0
    var stockPedRuntime:Loader?,stockPedIDs:[String:Int32]=[:],stockPedCatalogueSHA:String?,stockPedErrors=Set<Int32>(),stockPedDrawn=Set<Int32>()
    var legacyStockMetadataTasks:[UUID:Task]=[:],legacyStockMetadataPending=0,legacyStockMetadataRetryAfter:Double=0
    var legacyStockCatalog:Int?,legacyStockCollisionCatalog:Int?,legacyStockManifestSHA256:String?
    var legacyStockLoader:Loader?,legacyStockLoads:[Int32:Int]=[:],legacyStockRetries:[Int32:Double]=[:]
    var legacyStockModels=Set<Int32>(),legacyStockUse:[Int32:Double]=[:],legacyStockCollisionKinds:[Int32:Int]=[:],legacyStockReferences=Set<Int32>()
    var legacyModels:[Int32:Resource]=[:],legacyCollisionModels:[Int32:Int]=[:],legacyModelCosts:[Int32:Int]=[:],legacyModelBytes=0
    var legacyCollisionKinds:[UInt16:Int32]=[:],removedColliders=Set<UInt16>(),legacyMissingObjects=Set<Int32>()
    func removeLegacyObjectCollision(_ id:UInt16){legacyCollisionKinds.removeValue(forKey:id);removedColliders.insert(id)}
    var legacyTextureTasks:[Key:Task]=[:],legacyTextureTokens:[Key:UUID]=[:],legacyTextureLoads=Set<Key>(),legacyTextureRetries:[Key:Double]=[:]
    var legacyExactTextures:[Key:NativeSAMPObjectMaterials.Texture]=[:],legacyTextureSources:[Key:UInt32]=[:],legacyTextureConflicts=Set<Key>()
    var legacyExternalTextureBytes:[Key:Int]=[:],legacyTextureUse:[Key:Double]=[:]
    var legacyArtworkTextureBindings:[Int32:[Key:(crc:UInt32,texture:NativeSAMPObjectMaterials.Texture)]]=[:]
    var legacyMaterialOwner:MaterialOwner?=MaterialOwner(),legacyAssetEpoch:UInt64=0
    // ACTUAL_OWNERS
    func seed()->(Task,Task,Loader,Resource,Resource,Key,Key,Key,Key){
        let metadata=Task(),dictionary=Task(),loader=Loader(),stock=Resource(),artwork=Resource()
        let key=Key(model:980,dictionary:"original",texture:"paint"),external=Key(model:19000,dictionary:"external",texture:"raw")
        let custom=Key(model:20001,dictionary:"dl",texture:"custom"),conflict=Key(model:980,dictionary:"shared",texture:"ambiguous")
        legacyStockMetadataTasks=[UUID():metadata];legacyStockMetadataPending=2;legacyStockMetadataRetryAfter=999
        legacyStockCatalog=1;legacyStockCollisionCatalog=2;legacyStockManifestSHA256="old"
        legacyStockLoader=loader;legacyStockLoads=[980:1];legacyStockRetries=[980:999]
        legacyStockModels=[980];legacyStockUse=[980:1];legacyStockCollisionKinds=[980:1];legacyStockReferences=[980]
        legacyModels=[980:stock,20001:artwork];legacyCollisionModels=[980:1,20001:2];legacyModelCosts=[980:10,20001:20];legacyModelBytes=30
        legacyCollisionKinds=[1:980,2:20001];legacyMissingObjects=[980,20001]
        legacyTextureTasks=[external:dictionary];legacyTextureLoads=[external];legacyTextureTokens=[external:UUID()];legacyTextureRetries=[external:999]
        legacyExactTextures=[key:.init(image:stock),external:.init(image:stock),custom:.init(image:artwork)]
        legacyTextureSources=[key:7,custom:8];legacyTextureConflicts=[key,conflict];legacyExternalTextureBytes=[external:16];legacyTextureUse=[external:1]
        legacyArtworkTextureBindings=[20001:[key:(8,.init(image:artwork)),custom:(8,.init(image:artwork)),conflict:(10,.init(image:artwork))],
                                      20002:[conflict:(11,.init(image:Resource()))]]
        return(metadata,dictionary,loader,stock,artwork,key,external,custom,conflict)
    }
}
let c=Carrier();c.server=ServerAddress(value:"A")
let witness=c.seed(),epoch=c.legacyStockMetadataEpoch
c.server=ServerAddress(value:"B")
require(c.legacyModels[980]==nil && c.legacyStockModels.isEmpty,"source change retained old stock GPU registration")
require(c.legacyModels[20001] === witness.4 && c.legacyCollisionModels[20001]==2,"source retirement erased independent artwork")
require(witness.0.cancellations==1 && witness.1.cancellations==1 && witness.2.resets==1,"source retirement failed to cancel work")
require(c.legacyStockLoader==nil && c.legacyStockLoads.isEmpty && c.legacyStockRetries.isEmpty,"old loader/retry owner survived")
require(c.legacyStockMetadataEpoch != epoch && c.legacyStockMetadataPending==0 && c.legacyStockMetadataTasks.isEmpty,"old pending bootstrap owner survived")
require(c.legacyStockCatalog==nil && c.legacyStockCollisionCatalog==nil && c.legacyStockManifestSHA256==nil,"old catalog identity survived")
require(c.legacyStockMetadataRetryAfter==0 && c.legacyStockReferences.isEmpty && c.legacyStockUse.isEmpty,"new source inherited suppression/references")
require(c.legacyCollisionKinds==[2:20001] && c.removedColliders==[1],"stock source retirement removed wrong physical owner")
require(c.legacyModelCosts==[20001:20] && c.legacyModelBytes==20,"stock source retirement corrupted shared accounting")
require(c.legacyExactTextures[witness.5]?.image === witness.4 && c.legacyTextureSources[witness.5]==8 && !c.legacyTextureConflicts.contains(witness.5),"surviving DL binding not restored")
require(c.legacyExactTextures[witness.6]==nil && c.legacyExternalTextureBytes.isEmpty && c.legacyTextureUse.isEmpty,"external dictionary retained old source")
require(c.legacyExactTextures[witness.7]?.image === witness.4,"unrelated artwork texture erased")
require(c.legacyTextureConflicts.contains(witness.8) && c.legacyExactTextures[witness.8]==nil,"two surviving different artwork bindings silently guessed")
require(c.legacyMissingObjects==[20001] && c.legacyStockCollisionKinds.isEmpty,"stock-specific readiness state survived")
require(c.legacyTextureTasks.isEmpty && c.legacyTextureTokens.isEmpty && c.legacyTextureLoads.isEmpty && c.legacyTextureRetries.isEmpty,"raw transfer bookkeeping survived")
let ready=c.seed(),sameEpoch=c.legacyStockMetadataEpoch
c.synchronizeLegacyStockSource()
require(c.legacyModels[980] === ready.3 && c.legacyStockLoader === ready.2,"same source unnecessarily reset resources")
require(c.legacyStockMetadataEpoch==sameEpoch && ready.0.cancellations==0 && ready.1.cancellations==0,"same source cancelled work")
c.generation+=1;c.synchronizeLegacyStockSource()
require(c.legacyModels[980]==nil && ready.2.resets==1 && c.legacyStockSource==c.fixedCJSourceIdentity(),"same-content generation repair retained obsolete resource owner")
let imports=c.seed(),importEpoch=c.legacyAssetEpoch,metadataEpoch=c.legacyStockMetadataEpoch
c.invalidateLegacyImports()
require(c.legacyAssetEpoch != importEpoch && imports.2.resets==1 && imports.1.cancellations==1,"connection import cancellation retained work")
require(c.legacyModels[980] === imports.3 && c.legacyStockLoader === imports.2 && c.legacyStockMetadataEpoch==metadataEpoch,"same-source import cancellation erased ready resources")
require(c.legacyTextureTasks.isEmpty && c.legacyTextureLoads.isEmpty && c.legacyTextureTokens.isEmpty,"cancelled dictionary blocked retry")
let external=Carrier.Key(model:19001,dictionary:"keep",texture:"external"),image=Resource()
c.legacyExactTextures[external] = .init(image:image);c.legacyExternalTextureBytes[external]=16
c.retireLegacyStockTextures([980])
require(c.legacyExactTextures[external]?.image === image && c.legacyExternalTextureBytes[external]==16,"ordinary stock eviction erased unrelated external dictionary")
require(c.legacyExactTextures[imports.5]?.image === imports.4,"stock eviction did not reveal surviving artwork binding")
print("PASS \(checks) actual source/repair/cancellation/texture lifetime checks")
