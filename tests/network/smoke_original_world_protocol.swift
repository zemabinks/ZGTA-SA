import Foundation
var checks=0
func check(_ condition:@autoclosure()->Bool,_ message:String){checks += 1;if !condition(){fatalError(message)}}
let root=URL(fileURLWithPath:CommandLine.arguments[1]);let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:root)) as! [String:Any]
let cases=fixture["cases"] as! [[String:Any]]
for (index,c)in cases.enumerated(){
 let stream=NativeOriginalWorldStream();stream.clock(serverMilliseconds:(c["anchor"] as! NSNumber).doubleValue,localMilliseconds:1000)
 let data=Data(base64Encoded:c["data"] as! String)!;let events=stream.read(data,now:(c["now"] as! NSNumber).doubleValue)
 check(stream.rows.count==1,"rowcount\(index)");let actual=stream.rows[0],expected=c["row"] as! [Any]
 check(NSArray(array:actual).isEqual(to:expected),"actual original row mismatch\(index) flags\(c["flags"]!)\n\(actual)\n\(expected)")
 var shots:[[String:Any]]=[];for e in events{if case let .shot(shot)=e{shots.append(shot)}}
 check(NSArray(array:shots).isEqual(to:c["shots"] as! [Any]),"shot\(index)")
 check(stream.wanted(now:1500).isEmpty,"unexpected resync\(index)")
 // Every proper truncated frame prefix remains bounded and does not trap.
 for count in 0..<min(data.count,10){let partial=NativeOriginalWorldStream();_ = partial.read(data.prefix(count),now:1000);check(partial.rows.isEmpty,"truncated prefix")}
}
let stream=NativeOriginalWorldStream()
func frame(_ tag:UInt8,_ bytes:[UInt8])->Data{let header:[UInt8]=bytes.count<128 ? [tag,UInt8(bytes.count)]:[tag,UInt8(bytes.count&127)|128,UInt8(bytes.count>>7)];return Data(header+bytes)}
let unknown=frame(2,[0,23,0,29,0,0])
_ = stream.read(unknown,now:1000);check(stream.wanted(now:1249).isEmpty,"resync delay")
check(stream.wanted(now:1250)==["23"],"missing baseline request");check(stream.wanted(now:2000).isEmpty,"resync throttle")
check(stream.wanted(now:2250)==["23"],"resync repeat");check(stream.wanted(now:11001).isEmpty,"resync expiry")
stream.clear();check(stream.rows.isEmpty,"clear")
let first=cases[0];_ = stream.read(Data(base64Encoded:first["data"] as! String)!,now:1000)
check(stream.near([["23",29,0]],serverTime:0,now:1100).count==1,"near matching stamp")
check(stream.near([["23",30,0]],serverTime:0,now:1100).isEmpty,"near unknown stamp")
check(stream.wanted(now:1350)==["23"],"near missing resync")
stream.gone("23");check(stream.rows.isEmpty && stream.wanted(now:3000).isEmpty,"gone clears baseline and requests")
let long=Data(repeating:0,count:1_048_577);check(stream.read(long,now:1000).isEmpty,"bounded frame")
for invalid in [Data([1,128]),Data([1,127,0]),Data([2,6,0,23,0,1,0,0]),Data([3,2,0,1])]{_ = stream.read(invalid,now:1000);check(stream.rows.isEmpty,"malformed frames")}
let unknownEvents=stream.read(frame(99,[1,2,3]),now:1000);check(unknownEvents.count==1,"unknown record surfaced")
if case let .extensionRecord(tag,payload)=unknownEvents[0]{check(tag==99 && payload==Data([1,2,3]),"extension bytes")}else{fatalError("extension event")}
let visibility=NativeOriginalWorldStream(),firstBytes=Data(base64Encoded:cases[0]["data"] as! String)!
_ = visibility.read(firstBytes,now:1000)
var secondRow=cases[0]["row"] as! [Any];secondRow[0]="24"
let secondBytes=[UInt8](try JSONSerialization.data(withJSONObject:secondRow))
_ = visibility.read(frame(1,[0,29]+secondBytes),now:1000)
check(visibility.rows.count==2,"two cached actor baselines")
check(visibility.near([["23",29,0]],serverTime:0,now:1100).count==1,"active near selection")
_ = visibility.read(firstBytes,now:1200)
check(visibility.rows.count==1&&visibility.rows[0][0] as? String=="23","unrelated cached actor cannot resurrect outside near")
check(visibility.near([["24",29,0]],serverTime:0,now:1300).count==1&&visibility.rows[0][0] as? String=="24","retained baseline can return without reparsing a stale peer")
let hi=try NativeOriginalWorldProtocol.hello();check(hi["t"] as? String=="hi","hi");check((hi["c"] as? [String:Int])?.isEmpty==true,"no unimplemented AI capability");let browserHi=try NativeOriginalWorldProtocol.hello(supportsAIDriving:true);check((browserHi["c"] as? [String:Int])?["aidrive"]==1,"explicit implemented capability");check(hi["inventoryAck"]==nil,"no fake independent ACK")
for build in ["", "20261110043x", "2026111004345"]{do{_ = try NativeOriginalWorldProtocol.hello(build:build);fatalError("invalidbuild")}catch{checks+=1}}
check(NativeOriginalWorldProtocol.acceptsProtocol(38),"protocol38");check(!NativeOriginalWorldProtocol.acceptsProtocol(39),"new protocol rejected");check(!NativeOriginalWorldProtocol.acceptsProtocol(true),"bool protocol rejected");check(!NativeOriginalWorldProtocol.acceptsProtocol(nil),"unknown protocol")
let live=try NativeOriginalWorldProtocol.liveURL(deviceID:String(repeating:"a",count:32));check(live.scheme=="wss" && live.host=="play.samp.directory","endpoint")
check(live.query=="device="+String(repeating:"a",count:32),"device")
for url in ["http://play.samp.directory", "https://play.samp.directory.attacker.invalid", "https://u:p@play.samp.directory", "https://play.samp.directory:444/"]{do{_ = try NativeOriginalWorldProtocol.origin(URL(string:url)!);fatalError("origin")}catch{checks+=1}}
func cookie(_ domain:String,_ secure:Bool,_ expired:Bool=false)->HTTPCookie{
 var p:[HTTPCookiePropertyKey:Any]=[.domain:domain,.path:"/",.name:"session",.value:"fixture",.expires:Date().addingTimeInterval(expired ? -10:100)]
 if secure {p[.secure]="TRUE"}
 return HTTPCookie(properties:p)!
}
let cookies=NativeOriginalWorldProtocol.sessionCookies([cookie("play.samp.directory",true),cookie(".samp.directory",true),cookie("discord.com",true),cookie("play.samp.directory",false),cookie("samp.directory.attacker.invalid",true),cookie("play.samp.directory",true,true)])
check(cookies.count==2,"cookie isolation")
print("PASS original browser protocol: \(cases.count) actual archived binary cases; \(checks) checks")
