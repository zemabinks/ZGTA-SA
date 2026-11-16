// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Metal
let root=URL(fileURLWithPath:CommandLine.arguments[1]),report=URL(fileURLWithPath:CommandLine.arguments[2])
let address=CommandLine.arguments[3],expected=Int(CommandLine.arguments[4])!
let device=MTLCreateSystemDefaultDevice()
let installation=try NativeSAMPProtocol.installationID(source:Data("ABCDEFGHIJKLMNOPQRST".utf8))
let client=NativeSAMPClient(address:address,nickname:"ZGTA_DL_Import",version:.dl,installationID:installation)
let cache=try NativeSAMPArtworkCache(root:root,namespace:address)
var session:NativeSAMPArtworkSession!,events:[String]=[],finished=false,spawned=false
var models:[Int32:NativeRenderWareModel.Uploaded]=[:],cpuImports=0,gpuImports=0,finishes=0
func log(_ event:String){events.append(event);print(event);fflush(stdout)}
func finish(_ success:Bool,_ reason:String){
 guard !finished else{return};finished=true
 let status=session.status
 client.disconnect();session.cancel()
 let value:[String:Any]=["status":success ? "PASS":"FAIL","reason":reason,"events":events,"spawned":spawned,"catalogModels":status.catalogModels,"verifiedFiles":status.verifiedFiles,"importedModels":status.importedModels,"cpuImports":cpuImports,"gpuImports":gpuImports,"finishRequests":finishes,"expectedModels":expected,"metalDevice":device != nil,"scope":"Actual owned open.mp DL RPC/catalog/HTTP/CRC -> native generated textured RW CPU+GPU import callback ->184/185 -> stock spawn. Application Renderer/in-world objects remain separate."]
 try! JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:report)
 exit(success ? 0:1)
}
session=try NativeSAMPArtworkSession(cache:cache,sendRPC:{rpc in
 if rpc.id==184 {
  finishes+=1
  guard session.status.importedModels==session.status.requiredModels,
        expected==0 || gpuImports>0 else{finish(false,"184 before required actual GPU import");return false}
 }
 var writer=NativeSAMPProtocol.Writer();writer.bytes(rpc.payload)
 let result=client.sendRPC(rpc.id,writer);log("send\(rpc.id)");return result
},importer:{model,dffURL,txdURL,completion in
 let epoch=session.generation
 DispatchQueue.global().async {
  do {
   let dffData=try Data(contentsOf:dffURL),txdData=try Data(contentsOf:txdURL)
   guard dffData.count==model.dff.size,txdData.count==model.txd.size,
         NativeSAMPArtwork.CRC32.checksum(dffData)==model.dff.checksum,
         NativeSAMPArtwork.CRC32.checksum(txdData)==model.txd.checksum else{throw NativeSAMPArtwork.Failure.checksum}
   let dff=try NativeRenderWareDFF.decode(dffData),txd=try NativeRenderWareTXD.decode(txdData)
   let plan=try NativeRenderWareModel.prepare(dff:dff,txd:txd)
   guard plan.isComplete,plan.draws.count==1,plan.textures.count==1 else{throw NativeSAMPArtwork.Failure.incomplete}
   DispatchQueue.main.async {
    guard epoch==session.generation else{completion(.failure(NativeSAMPArtwork.Failure.cancelled));return}
    do {
     guard let device else{throw NativeSAMPArtwork.Failure.unsupported}
     let uploaded=try NativeRenderWareModel.Uploaded(plan:plan,device:device)
     models[model.customID]=uploaded;cpuImports+=1;gpuImports+=1
     log("actual native CPU+GPU model registered\(model.customID)");completion(.success(()))
    } catch{completion(.failure(error))}
   }
  } catch{completion(.failure(error))}
 }
})
session.onReset={models.removeAll()}
session.onWorld={log("world\($0)")}
session.onReady={_,world in log("server185 current generation world\(world)");client.requestSpawn()}
session.onStatus={status in if let error=status.failure{finish(false,String(describing:error))}}
client.onRawRPC={rpc in if [48,179,183,185].contains(rpc.id){log("receive\(rpc.id)");session.receive(id:rpc.id,data:rpc.data)}}
client.onClass={_ in if session.status.phase == .ready{client.requestSpawn()}}
client.onSpawn={_ in
 spawned=true
 guard session.status.phase == .ready,session.status.catalogModels==expected,
       expected==0 || models.count==expected else{finish(false,"spawn without complete imported artwork");return}
 finish(true,"Actual DL catalog/verified transfer/native GPU import barrier/completion/spawn")
}
client.onStatus={log($0)}
session.reset();client.connect()
DispatchQueue.main.asyncAfter(deadline:.now()+30){finish(false,"owned server test deadline")}
dispatchMain()
