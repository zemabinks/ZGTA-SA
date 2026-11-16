import Foundation
typealias Artwork=NativeSAMPArtwork
var checks=0
func check(_ value:@autoclosure()->Bool,_ message:String){checks+=1;if !value(){fatalError(message)}}
func fails(_ message:String,_ operation:()throws->Void){do{try operation();fatalError(message)}catch{checks+=1}}
func bytes(_ text:String)->Data{var result=Data();var cursor=text.startIndex;while cursor<text.endIndex{let next=text.index(cursor,offsetBy:2);result.append(UInt8(text[cursor..<next],radix:16)!);cursor=next};return result}
func u32(_ value:UInt32)->Data{var n=value.littleEndian;return withUnsafeBytes(of:&n){Data($0)}}
func model(pool:UInt32,count:UInt32,type:UInt8,world:Int32,custom:Int32,dff:Artwork.File,txd:Artwork.File)->Data {
 var d=u32(pool)+u32(count)+Data([type]);for value in [world,Int32(7),custom]{d+=u32(UInt32(bitPattern:value))};d+=u32(dff.checksum)+u32(txd.checksum)+u32(dff.size)+u32(txd.size)+Data([0,0]);return d
}
func urlPacket(_ file:Artwork.File,_ url:String)->Data{Data([6,file.kind.rawValue])+u32(file.checksum)+Data([UInt8(url.utf8.count)])+Data(url.utf8)}
let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))as! [String:Any]
check(fixture["rpcIDs"]as! [Int]==[179,181,182,183,184,185],"Actual official RPC identifiers")
for row in fixture["models"]as! [[String:Any]] {
 let m=try Artwork.Model.decode(bytes(row["hex"]as! String))
 check(m.pool==(row["pool"]as! NSNumber).uint32Value && m.count==256,"Actual ModelRequest pool/count")
 check(m.type==(row["type"]as! NSNumber).uint8Value && m.world==(row["world"]as! NSNumber).int32Value,"Actual type/virtual world")
 check(m.baseID==(row["base"]as! NSNumber).int32Value && m.customID==(row["custom"]as! NSNumber).int32Value,"Actual base/custom signed IDs")
 check(m.dff.checksum==(row["dffCRC"]as! NSNumber).uint32Value && m.txd.checksum==(row["txdCRC"]as! NSNumber).uint32Value,"Actual unsigned CRC values")
 check(m.dff.size==(row["dffSize"]as! NSNumber).uint32Value && m.txd.size==(row["txdSize"]as! NSNumber).uint32Value,"Actual sizes")
 check(m.timeOn==(row["on"]as! NSNumber).uint8Value && m.timeOff==(row["off"]as! NSNumber).uint8Value,"Actual timed model metadata")
}
for row in fixture["crc"]as! [[String:Any]] {let data=bytes(row["hex"]as! String);check(Artwork.CRC32.checksum(data)==(row["crc"]as! NSNumber).uint32Value,"Actual official CRC32 implementation");var crc=Artwork.CRC32();for byte in data{crc.update(Data([byte]))};check(crc.value==(row["crc"]as! NSNumber).uint32Value,"Incremental CRC32 chunk invariance")}
let base=CommandLine.arguments[2],root=URL(fileURLWithPath:CommandLine.arguments[3])
let http=try JSONSerialization.jsonObject(with:Data(base64Encoded:CommandLine.arguments[4])!)as! [String:String]
let dffData=bytes(http["dff"]!),txdData=bytes(http["txd"]!)
let dff=Artwork.File(kind:.dff,checksum:Artwork.CRC32.checksum(dffData),size:UInt32(dffData.count)),txd=Artwork.File(kind:.txd,checksum:Artwork.CRC32.checksum(txdData),size:UInt32(txdData.count))
let state=Artwork(),skin=model(pool:0,count:2,type:1,world:0,custom:20001,dff:dff,txd:txd),object=model(pool:1,count:2,type:2,world:73,custom:-1000,dff:dff,txd:txd)
state.begin(world:73);try state.receiveModel(skin);check(!state.catalogComplete && state.requests().isEmpty,"Partial catalog cannot open requests");fails("Incomplete cannot finish"){_=try state.finishRequest()};try state.receiveModel(object);try state.receiveModel(object)
check(state.catalogComplete && state.requiredFiles.count==2,"Shared TXD/DFF hashes deduplicate")
let requests=state.requests();check(requests.count==2 && Set(requests.map(\.id))==[181,182],"Exact DFF/TXD request IDs");check(requests.allSatisfy{$0.payload==u32($0.id==181 ? dff.checksum:txd.checksum)},"Checksum request bytes");check(state.requests().isEmpty,"No duplicate outstanding requests")
fails("Early completion rejected"){try state.receiveCompleted(Data())};fails("Pending cannot finish"){_=try state.finishRequest()}
let d=try state.receiveURL(urlPacket(dff,base+"/dff"));check(d.file==dff,"Matching URL183 request")
fails("Duplicate URL rejected"){_=try state.receiveURL(urlPacket(dff,base+"/dff"))}
fails("Wrong checksum rejected"){_=try state.receiveURL(urlPacket(.init(kind:.dff,checksum:1,size:5),base+"/dff"))}
try state.completed(.init(file:dff,url:root,md5:"",fromCache:false));_=try state.receiveURL(urlPacket(txd,base+"/txd"));try state.completed(.init(file:txd,url:root,md5:"",fromCache:false))
let finish=try state.finishRequest();check(finish?.id==184 && finish?.payload.isEmpty==true && !state.acknowledged,"Finish184 waits for actual server185");let duplicate=try state.finishRequest();check(duplicate==nil,"Finish once");try state.receiveCompleted(Data());check(state.acknowledged,"Actual185 acknowledged")
state.begin(world:74);check(state.requiredFiles.count==2,"Skins apply across worlds")
for count in 0..<39{fails("Truncated model rejected"){_=try Artwork.Model.decode(skin.prefix(count))}}
for url in ["file:///tmp/a.dff","data:a","https://a.invalid/u#fragment","http://user:password@example.com/a"]{check(!Artwork.permitted(URL(string:url)!),"Unsafe URL form refused")}
let officialURLs=fixture["urls"]as! [String]
let known=Artwork(),knownDFF=Artwork.File(kind:.dff,checksum:0x1234abcd,size:1),knownTXD=Artwork.File(kind:.txd,checksum:0x1234abcd,size:2)
try known.receiveModel(model(pool:0,count:1,type:1,world:-1,custom:20001,dff:knownDFF,txd:knownTXD));known.begin(world:0);_=known.requests();for text in officialURLs{let decoded=try known.receiveURL(bytes(text));check(decoded.file.checksum==0x1234abcd && decoded.url.absoluteString=="http://127.0.0.1:7789/synthetic.dff?test=1","Actual official ModelUrl bytes")}
let cache=try NativeSAMPArtworkCache(root:root,namespace:"owned-fixture",maximumCacheBytes:UInt64(dff.size))
func download(_ path:String)->Artwork.Download{.init(file:dff,url:URL(string:base+path)!)}
func expectFailure(_ result:Result<Artwork.Receipt,Error>,_ error:Artwork.Failure){switch result{case .success:fatalError("Expected failure \(error)");case .failure(let actual):check(actual as? Artwork.Failure==error,"Failure \(actual) != \(error)")}}
let failures:[(String,Artwork.Failure)]=[("/bad",.checksum),("/wrong-size",.size),("/oversize",.size),("/loop",.invalidURL),("/error",.http(403))]
var failureIndex=0,cancellations=0
func finishHTTP(){
 let small=try! NativeSAMPArtworkCache(root:root,namespace:"small",maximumFileBytes:1)
 small.fetch(download("/dff")){r in expectFailure(r,.limit)
  let full=try! NativeSAMPArtworkCache(root:root,namespace:"full",maximumCacheBytes:1)
  full.fetch(download("/dff")){r in expectFailure(r,.cacheFull)
   let cancellation=try! NativeSAMPArtworkCache(root:root,namespace:"cancel")
   for _ in 0..<3{cancellation.fetch(download("/slow")){r in expectFailure(r,.cancelled);cancellations+=1;if cancellations==3{
    cancellation.fetch(download("/dff")){r in let receipt=try! r.get();check(!receipt.fromCache && receipt.md5==http["dffMD5"]!,"Fresh generation recovers after cancellation");print("PASS native DL artwork: \(checks) checks;256 actual official ModelRequest records, CRC32, catalog/request/complete barriers and bounded native HTTP/cache");exit(0)}
   }}}
   DispatchQueue.main.asyncAfter(deadline:.now()+0.1){cancellation.cancelAll()}
  }
 }
}
func nextFailure(){
 guard failureIndex<failures.count else{finishHTTP();return}
 let pair=failures[failureIndex];failureIndex+=1
 let isolated=try! NativeSAMPArtworkCache(root:root,namespace:"failure\(failureIndex)")
 isolated.fetch(download(pair.0)){result in expectFailure(result,pair.1);nextFailure()}
}
cache.fetch(download("/dff")){r in
 let first=try! r.get();check(!first.fromCache && first.md5==http["dffMD5"]! && (try! Data(contentsOf:first.url))==dffData,"Actual native verified file and MD5 receipt")
 cache.fetch(download("/dff")){r in let hit=try! r.get();check(hit.fromCache && hit.url==first.url,"Revalidated cache hit without HTTP")
  var corrupt=dffData;corrupt[0]^=1;try! corrupt.write(to:first.url)
  cache.fetch(download("/dff")){r in let restored=try! r.get();check(!restored.fromCache && (try! Data(contentsOf:restored.url))==dffData,"Corrupt cache revalidated and replaced")
   let redirect=try! NativeSAMPArtworkCache(root:root,namespace:"redirect")
   redirect.fetch(download("/redirect")){r in check((try! r.get()).md5==http["dffMD5"]!,"Redirect uses native validated body");nextFailure()}
  }
 }
}
DispatchQueue.main.asyncAfter(deadline:.now()+35){fatalError("Artwork timeout")}
dispatchMain()
