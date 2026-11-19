import Foundation
var checks=0
func check(_ value:Bool,_ message:String){checks+=1;if !value{fatalError(message)}}
let rows=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))as![[String:Any]]
for row in rows {
 let id=UInt8(row["id"]as!Int),data=Data(base64Encoded:row["payload"]as!String)!,bits=row["bits"]as!Int,expected=Data(base64Encoded:row["packet"]as!String)!
 var w=NativeSAMPProtocol.Writer();w.bytes(data,bits:bits)
 check(NativeSAMPProtocol.rpc(id,w)==expected,"Actual Go RPC encoding")
 let parsed=try NativeSAMPProtocol.rpc(expected);check(parsed.id==id && parsed.bits==bits,"RPC header")
 var original=try NativeSAMPProtocol.Reader(data,bits:bits),native=try NativeSAMPProtocol.Reader(parsed.data,bits:bits)
 for _ in 0..<bits {check(try original.bit()==native.bit(),"RPC payload bit")}
 if expected.count>1 {check((try?NativeSAMPProtocol.rpc(expected.dropLast()))==nil || bits==0,"RPC truncation rejected")}
}
let key=NativeSAMPProtocol.auth(Data("6C407EC29DE59E2".utf8));check(String(decoding:key.dropFirst(2),as:UTF8.self)=="D9412F235647BAA582089C6F66817F8B8811C057","Published challenge transform")
let gpci=try NativeSAMPProtocol.installationID(source:Data("ABCDEFGHIJKLMNOPQRST".utf8));check(!gpci.isEmpty && gpci.count<=64,"Installation identifier")
for h in stride(from:-3.1,through:3.1,by:0.31){for p in [-1.58,-1.0,-0.3,0.0,0.5,1.58]{for r in [-2.8,-0.8,0.0,1.4,3.0]{
 let q=Reference.rotation(heading:h,pitch:p,roll:r),reference=Reference.euler(q),gta=SIMD4<Float>(Float(q.real),Float(q.imag.x),-Float(q.imag.z),Float(q.imag.y)),actual=NativeSAMPProtocol.nativeAngles(gta)
 func angle(_ a:Double,_ b:Double)->Double{atan2(sin(a-b),cos(a-b))}
 check(abs(angle(Double(actual.heading),-reference.heading))<0.0001,"Full vehicle heading")
 check(abs(Double(actual.pitch)-reference.pitch)<0.0001,"Full vehicle pitch")
 check(abs(angle(Double(actual.roll),-reference.roll))<0.0001,"Full vehicle roll")
}}}
var foot=NativeSAMPProtocol.Foot(position:SIMD3(12,34,56),heading:1.25);foot.velocity=SIMD3(0.1,-0.2,0.3);foot.weapon=24;foot.keys=40
let packet=try NativeSAMPProtocol.onFoot(foot);check(packet.count==69,"Onfoot wire length")
var input=try NativeSAMPProtocol.Reader(packet);check(try input.integer(1)==207,"Onfoot packet ID");_=try input.integer(2);_=try input.integer(2);check(try input.integer(2)==40,"Real held keys");check(try input.vector()==foot.position,"Unchanged GTA coordinates")
check(NativeSAMPAddress("samp://127.0.0.1:7777")?.display=="127.0.0.1:7777","Endpoint parsing")
for invalid in ["https://server:7777","samp://user:password@server:7777","server:0","server:65536","server/path","[::1]:7777","server:7777?secret=x"]{check(NativeSAMPAddress(invalid)==nil,"Reject unsupported endpoint")}
print("PASS native legacy codecs: \(rows.count) actual Go RPC cases, \(checks) checks, full tilted poses and published auth")
