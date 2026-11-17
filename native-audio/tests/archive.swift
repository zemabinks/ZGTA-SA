// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Darwin
@main enum RadioArchiveTests {
 static var checks=0
 static func check(_ value:Bool,_ message:String){checks+=1;if !value{fatalError(message)}}
 static func rejects(_ expected:NativeRadioArchive.Failure,_ body:()throws->Void){do{try body();fatalError("Accepted \(expected)")}catch let e as NativeRadioArchive.Failure{check(e==expected,"Wrong failure \(e) expected \(expected)")}catch{fatalError("Unexpected \(error)")}}
 static func main()throws {
  let directory=URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
  let header=8068,first=10000,second=9500,start=29,offset2=start+header+first,total=offset2+header+second
  var names=Data(repeating:0,count:16*3);for (i,n)in["CH","ADVERTS","AA"].enumerated(){names.replaceSubrange(i*16..<i*16+n.count,with:n.utf8)}
  var lookup=Data(repeating:0xcd,count:6*12)
  func row(_ id:Int,_ pack:Int,_ offset:Int,_ bytes:Int){lookup[id*12]=UInt8(pack);for(j,n)in[offset,bytes].enumerated(){for k in 0..<4{lookup[id*12+4+j*4+k]=UInt8((UInt32(n)>>(k*8))&255)}}}
  row(0,0,start,first);row(1,0,offset2,header+second);row(2,1,start,header+first);row(3,2,0,10000);row(4,0,0,0);row(5,0,start,first)
  let available:[String:UInt64]=["CH":UInt64(total),"ADVERTS":UInt64(start+header+first)]
  func parse(_ n:Data?=nil,_ l:Data?=nil,_ a:[String:UInt64]?=nil)throws->NativeRadioArchive.Catalogue{try NativeRadioArchive.catalogue(packNames:n ?? names,lookup:l ?? lookup,availablePacks:a ?? available)}
  let result=try parse();check(result.records.map(\.id)==[0,1,2,5],"Wire IDs must not compact");check(result.records.map(\.byteCount)==[UInt64(header+first),UInt64(header+second),UInt64(header+first),UInt64(header+first)],"Mixed exact boundaries/aliases")
  check(result.stations[1].map(\.id)==[0,1,5]&&result.adverts.map(\.id)==[2],"Station/ad identity");check(result.absentPackRecords==1&&result.emptyLookupRecords==1,"Explicit absent/empty rows")
  rejects(.table){_=try parse(names+Data([0]))};rejects(.table){_=try parse(nil,lookup+Data([0]))};rejects(.table){var b=lookup;b[0]=255;_=try parse(nil,b)}
  rejects(.packIdentity){_=try parse(nil,nil,["CH":1,"ch":1])};rejects(.packIdentity){_=try parse(nil,nil,["UNKNOWN":10000])};rejects(.packIdentity){_=try parse(nil,nil,[:])}
  rejects(.packIdentity){var b=names;b.replaceSubrange(16..<32,with:names[0..<16]);_=try parse(b)}
  rejects(.range){var b=lookup;for k in 4..<8{b[k]=255};_=try parse(nil,b)}
  let saved=lookup;row(0,0,start,header+first+1);rejects(.overlap){_=try parse()};lookup=saved
  row(5,0,start,first+1);rejects(.overlap){_=try parse()};lookup=saved
  var limits=NativeRadioArchive.Limits();limits.maximumLookupRecords=1;rejects(.table){_=try NativeRadioArchive.catalogue(packNames:names,lookup:lookup,availablePacks:available,limits:limits)}
  limits=NativeRadioArchive.Limits();limits.maximumRecordBytes=UInt64.max;rejects(.limits){_=try NativeRadioArchive.catalogue(packNames:names,lookup:lookup,availablePacks:available,limits:limits)}
  let xor:[UInt8]=[234,58,196,161,154,168,20,243,72,176,215,35,157,232,255,241]
  let plaintext=(0..<first).map{UInt8(($0*37+11)&255)}
  var pack=Data(repeating:0,count:total)
  for i in 0..<first{let at=start+header+i;pack[at]=plaintext[i]^xor[at&15]}
  let file=directory.appendingPathComponent("authored-pack.bin");try pack.write(to:file)
  var fd=open(file.path,O_RDONLY);check(fd>=0,"Authored regular FD");check(lseek(fd,17,SEEK_SET)==17,"Initial caller cursor")
  let stream=try NativeRadioArchive.Substream(fileDescriptor:fd,record:result.records[0]);check(lseek(fd,0,SEEK_CUR)==17,"Duplicate does not seek caller")
  for (offset,count)in[(0,100),(1,2),(15,33),(127,8000),(9990,100),(10000,1),(0,0)] {
   let bytes=try stream.read(at:UInt64(offset),maximumBytes:count);check(bytes==Data(plaintext[offset..<min(first,offset+count)]),"Unaligned XOR/range \(offset)")
  }
  check(lseek(fd,0,SEEK_CUR)==17,"Positional reads preserve caller cursor")
  close(fd);check(try stream.read(at:12,maximumBytes:20)==Data(plaintext[12..<32]),"Stream owns its duplicate")
  rejects(.range){_=try stream.read(at:10001,maximumBytes:1)};rejects(.range){_=try stream.read(at:0,maximumBytes:65537)};rejects(.range){_=try stream.read(at:0,maximumBytes:-1)}
  stream.cancel();rejects(.cancelled){_=try stream.read(at:0,maximumBytes:1)};stream.close();stream.close();rejects(.closed){_=try stream.read(at:0,maximumBytes:1)}
  fd=open(file.path,O_RDONLY);let changed=try NativeRadioArchive.Substream(fileDescriptor:fd,record:result.records[0]);close(fd)
  let writer=open(file.path,O_WRONLY);check(ftruncate(writer,1)==0,"Truncate owned fixture");close(writer);rejects(.sourceChanged){_=try changed.read(at:0,maximumBytes:1)};changed.close()
  rejects(.descriptor){_=try NativeRadioArchive.Substream(fileDescriptor:-1,record:result.records[0])}
  fd=open(directory.path,O_RDONLY);rejects(.descriptor){_=try NativeRadioArchive.Substream(fileDescriptor:fd,record:result.records[0])};close(fd)
  try pack.write(to:file);fd=open(file.path,O_RDONLY)
  let invalid=NativeRadioArchive.Record(id:0,packIndex:0,pack:"CH",offset:UInt64.max,byteCount:8069);rejects(.range){_=try NativeRadioArchive.Substream(fileDescriptor:fd,record:invalid)}
  for _ in 0..<100{let s=try NativeRadioArchive.Substream(fileDescriptor:fd,record:result.records[0]);check(try s.read(at:0,maximumBytes:1)==Data(plaintext[0..<1]),"Repeated duplicate/read/close");s.close()};close(fd)
  print("RADIO_ARCHIVE_PASS \(checks) authored checks; no original audio, codec or hardware")
 }
}
