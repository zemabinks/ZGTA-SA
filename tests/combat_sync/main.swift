// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
var checks=0
enum Regression:Error {case failed(String)}
func require(_ value:@autoclosure()throws->Bool,_ message:String)throws{checks+=1;if try !value(){throw Regression.failed(message)}}
func reject(_ message:String,_ operation:()throws->Void)throws{do{try operation()}catch{checks+=1;return};throw Regression.failed("accepted "+message)}
func bytes(_ text:String)throws->Data {
    guard text.count%2==0 else{throw Regression.failed("hex")};var data=Data();var index=text.startIndex
    while index<text.endIndex{let next=text.index(index,offsetBy:2);guard let byte=UInt8(text[index..<next],radix:16)else{throw Regression.failed("hex byte")};data.append(byte);index=next};return data
}
typealias Codec=NativeSAMPCombatSync
let goldens=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))as![String:[String]]
let modes:[UInt8]=[4,7,8,18,53,55]
for (i,text) in goldens["aim"]!.enumerated(){
    let data=try bytes(text),remote=try Codec.serverAim(data),p=remote.value
    try require(data.count==34 && remote.player==UInt16(i+1),"aim server header")
    try require(p.cameraMode==modes[i%6] && p.zoom==i%64 && p.weaponState==(i/64)%4 && p.aspectRatio==i%256,"packed aim fields")
    try require(p.front==SIMD3<Float>(i%2==0 ? 1:-1,0,0) && p.position==SIMD3<Float>(Float(i*13-2000),Float(1000-i*7),Float(i%90)),"physical camera coordinates")
    try require(p.aimZ==Float(i%21-10)/10,"AimZ preserved without pedestrian offset")
    try require(try Codec.aim(p,sender:remote.player)==data,"official aim server write")
    let client=try Codec.aim(p)
    try require(client==Data([203])+data.dropFirst(3) && client.count==32,"official aim client layout")
    try require(try Codec.clientAim(client)==p,"aim client decode")
    try require(abs(p.cameraFOV-(Float(i%64)/63*35+35))<0.00001,"published FOV unpacking")
    try require(abs(p.aspect-(Float(i%256)/255+1))<0.00001,"published aspect unpacking")
}
for (i,text) in goldens["bullet"]!.enumerated(){
    let data=try bytes(text),remote=try Codec.serverBullet(data),p=remote.value
    try require(data.count==43 && remote.player==UInt16(i+1),"bullet server header")
    try require(p.hitType.rawValue==i%5 && p.hitID==(i%5==0 ? 65535:i%100) && p.weapon==22+i%13,"bullet target/weapon")
    try require(p.origin==SIMD3<Float>(Float(i*13-2000),Float(1000-i*7),Float(i%90)) && p.position==p.origin+SIMD3(8,-5,1),"physical shot coordinates")
    try require(p.offset==SIMD3<Float>(Float(i%9-4),Float(i%7-3),Float(i%5-2)),"entity-relative offset preserved")
    try require(try Codec.bullet(p,sender:remote.player)==data,"official bullet server write")
    let client=try Codec.bullet(p)
    try require(client==Data([206])+data.dropFirst(3) && client.count==41,"official bullet client layout")
    try require(try Codec.clientBullet(client)==p,"bullet client decode")
}
let a=try bytes(goldens["aim"]![0]),b=try bytes(goldens["bullet"]![0])
for length in 0..<a.count{try reject("truncated aim \(length)"){_=try Codec.serverAim(a.prefix(length))}}
for length in 0..<b.count{try reject("truncated bullet \(length)"){_=try Codec.serverBullet(b.prefix(length))}}
try reject("aim trailing byte"){_=try Codec.serverAim(a+Data([0]))}
try reject("bullet trailing byte"){_=try Codec.serverBullet(b+Data([0]))}
func replacingFloat(_ data:Data,_ at:Int,_ bits:UInt32)->Data{var d=data;for i in 0..<4{d[at+i]=UInt8(truncatingIfNeeded:bits >> (i*8))};return d}
for at in [4,8,12,16,20,24,28]{for bits:UInt32 in [0x7fc00000,0x7f800000,0xff800000]{try reject("nonfinite aim"){_=try Codec.serverAim(replacingFloat(a,at,bits))}}}
for at in stride(from:6,through:38,by:4){for bits:UInt32 in [0x7fc00000,0x7f800000,0xff800000]{try reject("nonfinite bullet"){_=try Codec.serverBullet(replacingFloat(b,at,bits))}}}
var bad=a;bad[1]=255;bad[2]=255;try reject("invalid aim sender"){_=try Codec.serverAim(bad)}
bad=b;bad[1]=255;bad[2]=255;try reject("invalid shot sender"){_=try Codec.serverBullet(bad)}
bad=b;bad[3]=5;try reject("invalid shot type"){_=try Codec.serverBullet(bad)}
bad=b;bad[3]=1;try reject("target ID65535"){_=try Codec.serverBullet(bad)}
bad=b;bad[42]=47;try reject("weapon outside legacy slots"){_=try Codec.serverBullet(bad)}
var aim=try Codec.serverAim(a).value
aim.front = .zero;try reject("zero camera vector"){_=try Codec.aim(aim)}
aim.front=SIMD3(2,0,0);try reject("oversized camera vector"){_=try Codec.aim(aim)}
aim.front=SIMD3(1,0,0);aim.zoom=64;try reject("zoom overflow"){_=try Codec.aim(aim)}
aim.zoom=0;aim.weaponState=4;try reject("weapon state overflow"){_=try Codec.aim(aim)}
var shot=try Codec.serverBullet(b).value
shot.origin=SIMD3(20001,0,0);try reject("origin norm limit"){_=try Codec.bullet(shot)}
shot.origin = .zero;shot.hitType = .player;shot.hitID=12;shot.offset=SIMD3(1001,0,0);try reject("target offset norm limit"){_=try Codec.bullet(shot)}
shot.hitType = .none;shot.hitID = .max;shot.offset=SIMD3(20001,0,0);try reject("miss offset norm limit"){_=try Codec.bullet(shot)}
let report:[String:Any]=["status":"PASS","checks":checks,"officialAimRecords":goldens["aim"]!.count,"officialBulletRecords":goldens["bullet"]!.count,"scope":"Exact wire codecs only. No live server, animation, shot damage or retail timing acceptance."]
print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),encoding:.utf8)!)
