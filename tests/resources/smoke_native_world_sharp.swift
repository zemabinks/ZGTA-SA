// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
private enum TestError:Error {case assertion(String)}
private var checks=0
private func require(_ value:Bool,_ name:String)throws{checks+=1;if !value{throw TestError.assertion(name)}}
private func data(_ map:[UInt16])->Data {
 var value=Data()
 func word(_ n:UInt32){var little=n.littleEndian;withUnsafeBytes(of:&little){value.append(contentsOf:$0)}}
 func half(_ n:UInt16){var little=n.littleEndian;withUnsafeBytes(of:&little){value.append(contentsOf:$0)}}
 for n in [UInt32(0x324c5257),3,3,UInt32(map.count)]{word(n)}
 for _ in 0..<9{word(0)};for _ in 0..<6{word(0)}
 for n:UInt32 in [0,1,2]{word(n)}
 value.append(Data(repeating:255,count:12));for _ in 0..<4{half(0)}
 value.append(Data(repeating:255,count:12));for n in map{half(n)}
 return value
}
@main private enum Tests {
 static func main()throws {
  let bytes=data([0,2,1,3]),world=try WorldBinary(data:bytes)
  try require(world.sharpLayers==[0,2,1,3],"Exact little-endian plus-one footer preserved")
  let layout=try NativeWorldSharpLayout(world:world,sharpLayers:3,width:2048,height:256)
  try require(layout.map==[4,3,0,0,0,2,1,3],"GPU header and source mapping preserved without remapping")
  try require(layout.rectangle(layer:0)==[0,0,256,256] && layout.rectangle(layer:2)==[512,0,256,256],"Original image coordinates")
  try require(layout.rectangle(layer:-1)==nil && layout.rectangle(layer:3)==nil,"Invalid image index rejected")
  try require(layout.baseTexelBytes==3*256*256*4 && layout.fullMipTexelBytes>layout.baseTexelBytes,"Complete generated mip budget")
  let endian=try WorldBinary(data:data([0x1234,0]));try require(endian.sharpLayers==[0x1234,0],"High and low map bytes preserved")
  for count in [1,8,9,186,266]{
   let w=try WorldBinary(data:data([0,UInt16(count)])),height=(count+7)/8*256
   let current=try NativeWorldSharpLayout(world:w,sharpLayers:count,width:2048,height:height)
   try require(current.rectangle(layer:count-1)==[((count-1)%8)*256,((count-1)/8)*256,256,256],"Last source image on complete or partial row")
  }
  for configuration in [(0,2048,256),(385,2048,12544),(3,1024,256),(3,2048,512),(384,2048,12288)] {
   var rejected=false
   do{_ = try NativeWorldSharpLayout(world:world,sharpLayers:configuration.0,width:configuration.1,height:configuration.2)}catch{rejected=true}
   try require(rejected,"Invalid dimensions/count/budget rejected")
  }
  for map:[UInt16] in [[0,4],[0,65535],[0,0]]{
   var rejected=false
   do{_ = try NativeWorldSharpLayout(world:WorldBinary(data:data(map)),sharpLayers:3,width:2048,height:256)}catch{rejected=true}
   try require(rejected,"Out-of-family or empty mapping cannot enable HD")
  }
  var rejected=false;do{_ = try WorldBinary(data:bytes.dropLast())}catch{rejected=true}
  try require(rejected,"Missing footer byte rejected by actual parser")
  let header=Data([137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,8,0,0,0,1,0,8,6,0,0,0,0,0,0,0])
  try require(layout.acceptsPNG(header),"Bounded RGBA8 dimensions accepted before decoder")
  for index in [0,8,12,16,20,24,25,26,27,28] {
   var bad=header;bad[index] ^= 1
   try require(!layout.acceptsPNG(bad),"Invalid PNG profile refused before decode")
  }
  try require(!layout.acceptsPNG(header.dropLast()),"Truncated PNG header refused")
  let document:[String:Any] = ["detail":["cell":128,"columns":16,"sharp":256,"sharpColumns":8,"cells":[["cell":59,"layers":342,"sharp":186]]],"inside":["cells":[["cell":74,"layers":300,"sharp":266]]]]
  func manifest(_ d:[String:Any])throws->NativeWorldSharpManifest{try NativeWorldSharpManifest(data:JSONSerialization.data(withJSONObject:d))}
  let declared=try manifest(document)
  try require(declared.entries["c59"]?.sharpLayers==186 && declared.entries["i74"]?.sharpLayers==266,"Explicit exterior/interior mappings remain distinct")
  for row:[String:Any] in [["cell":-1,"layers":2,"sharp":1],["cell":256,"layers":2,"sharp":1],["cell":1,"layers":1,"sharp":2],["cell":1,"layers":400,"sharp":385],["cell":1,"layers":true,"sharp":1]] {
   var d=document,detail=d["detail"] as![String:Any];detail["cells"]=[row];d["detail"]=detail
   var rejected=false;do{_ = try manifest(d)}catch{rejected=true};try require(rejected,"Malformed manifest row rejected")
  }
  var duplicate=document;var detail=duplicate["detail"] as![String:Any];let rows=detail["cells"] as![[String:Any]];detail["cells"]=rows+rows;duplicate["detail"]=detail
  var duplicateRejected=false;do{_ = try manifest(duplicate)}catch{duplicateRejected=true};try require(duplicateRejected,"Duplicate world identity rejected")
  let work=NativeWorldSharpWork(),active=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0),latest=DispatchSemaphore(value:0)
  let lock=NSLock();var events:[Int]=[]
  work.submit{lock.lock();events.append(1);lock.unlock();active.signal();_ = release.wait(timeout:.now()+5)}
  try require(active.wait(timeout:.now()+5) == .success,"Worker starts its sole active task")
  for n in 2...50 {work.submit{lock.lock();events.append(n);lock.unlock();if n==50{latest.signal()}}}
  release.signal();try require(latest.wait(timeout:.now()+5) == .success,"Latest pending task drains")
  lock.lock();let recorded=events;lock.unlock();try require(recorded==[1,50],"Intermediate pending images are replaced, not accumulated")
  work.close();try require(!work.submit{fatalError("closed worker ran")},"Closed worker refuses new payload")
  let ticket=NativeWorldSharpTicket();var cancelled=0;ticket.attachCancellation{cancelled+=1};ticket.cancel();ticket.cancel()
  try require(cancelled==1 && ticket.isCancelled,"Cancellation reaches transfer once")
  let inline=NativeWorldSharpTicket();inline.finishTransfer();inline.attachCancellation{cancelled+=1};inline.cancel()
  try require(cancelled==1,"Inline completion cannot recreate transfer ownership cycle")
  let retired=NativeWorldSharpTicket();retired.cancel();retired.attachCancellation{cancelled+=1}
  try require(cancelled==2,"Cancellation before factory attachment cancels the late transfer")
  print("PASS \(checks) actual WRL2/native sharp-layout checks; no GPU, installed scene or retail claim")
 }
}
