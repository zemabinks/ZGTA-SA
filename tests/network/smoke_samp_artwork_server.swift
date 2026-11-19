import Foundation
let root=URL(fileURLWithPath:CommandLine.arguments[1]),report=URL(fileURLWithPath:CommandLine.arguments[2])
let installation=try NativeSAMPProtocol.installationID(source:Data("ABCDEFGHIJKLMNOPQRST".utf8))
let client=NativeSAMPClient(address:"127.0.0.1:7789",nickname:"ZGTA_DL_Artwork",version:.dl,installationID:installation)
let artwork=NativeSAMPArtwork(),cache=try NativeSAMPArtworkCache(root:root,namespace:"actual-openmp-7789")
var events:[String]=[],downloads:[NativeSAMPArtwork.Receipt]=[],generation=0,started=false,spawned=false,finished=false
func record(_ text:String){events.append(text);print(text);fflush(stdout)}
func finish(_ success:Bool,_ reason:String){
 guard !finished else{return};finished=true;client.disconnect();cache.cancelAll()
 let result:[String:Any]=["status":success ? "PASS":"FAIL","reason":reason,"events":events,"spawned":spawned,"acknowledged":artwork.acknowledged,"models":artwork.models.count,"downloads":downloads.map{["kind":$0.file.kind.rawValue,"crc":$0.file.checksum,"size":$0.file.size,"md5":$0.md5,"fromCache":$0.fromCache]},"limit":"Real server download handshake and stock spawn only. Synthetic files are deliberately not RenderWare models; no custom model rendering claim."]
 try! JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:report)
 exit(success ? 0:1)
}
func send(_ rpc:NativeSAMPArtwork.RPC){var payload=NativeSAMPProtocol.Writer();payload.bytes(rpc.payload);guard client.sendRPC(rpc.id,payload)else{finish(false,"RPC queue refused\(rpc.id)");return};record("sent RPC\(rpc.id)")}
func progress(){
 guard started else{return};for request in artwork.requests(){send(request)}
 if let finish=try? artwork.finishRequest(){send(finish)}
}
client.onRawRPC={rpc in
 do {switch rpc.id {
 case 179:try artwork.receiveModel(rpc.data);record("received model179");progress()
 case 48:
  var reader=try NativeSAMPProtocol.Reader(rpc.data);let world=Int32(bitPattern:try reader.integer(4));generation+=1;let epoch=generation
  DispatchQueue.main.asyncAfter(deadline:.now()+0.05){guard epoch==generation else{return};artwork.begin(world:world);started=true;record("world download boundary\(world)");progress()}
 case 183:
  let download=try artwork.receiveURL(rpc.data);record("received URL183 \(download.file.kind)")
  cache.fetch(download){result in do{let receipt=try result.get();try artwork.completed(receipt);downloads.append(receipt);record("verified \(receipt.file.kind) CRC\(receipt.file.checksum)");progress()}catch{finish(false,"native download \(error)")}}
 case 185:
  try artwork.receiveCompleted(rpc.data);record("received server completion185");client.requestSpawn()
 default:break
 }}catch{finish(false,"RPC\(rpc.id): \(error)")}
}
client.onStatus={record($0)}
client.onClass={_ in if artwork.acknowledged{client.requestSpawn()}}
client.onSpawn={_ in spawned=true;record("actual stock class/spawn transaction completed");guard artwork.acknowledged,artwork.models.count==1,downloads.count==2,Set(downloads.map{$0.file.kind})==[.dff,.txd]else{finish(false,"Incomplete download/spawn evidence");return};finish(true,"Actual native DL transport+download+completion+stock spawn")}
client.connect()
DispatchQueue.main.asyncAfter(deadline:.now()+20){finish(false,"Actual artwork server timeout")}
dispatchMain()
