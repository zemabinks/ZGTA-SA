import Foundation
import CoreGraphics
func hex(_ value:String)->Data{let chars=Array(value);return Data(stride(from:0,to:chars.count,by:2).map{UInt8(String(chars[$0...$0+1]),radix:16)!})}
var checks=0
func check(_ test:@autoclosure()throws->Bool,_ label:String){checks+=1;do{let result=try test();precondition(result,label)}catch{preconditionFailure("\(label):\(error)")}}
func rejects(_ label:String,_ body:()throws->Void){checks+=1;do{try body();preconditionFailure(label)}catch{}}
// Actual C++ compressed-string fixture retained in Apache2 Pilot huffman_test.go.
var compressed=try NativeSAMPProtocol.Reader(hex("8630252840"),bits:34)
check(try NativeSAMPTextCodec.compressed(&compressed)==Data("hello".utf8),"C++ Huffman golden")
rejects("Huffman output bound"){var r=try NativeSAMPProtocol.Reader(hex("8630252840"),bits:34);_=try NativeSAMPTextCodec.compressed(&r,maxBytes:4)}
check(NativeSAMPTextCodec.decode(hex("cff0e8e2e5f2"),encoding:.windows1251)=="Привет","CP1251 incoming")
check(try NativeSAMPTextCodec.encode("Привет",encoding:.windows1251)==hex("cff0e8e2e5f2"),"CP1251 response")
check(NativeSAMPTextCodec.decode(Data("é".utf8),encoding:.windows1251)=="é","UTF8 first")
check(NativeSAMPTextCodec.decode(hex("d6d0cec4"),encoding:.gbk)=="中文","CP936 incoming")
check(try NativeSAMPTextCodec.encode("中文",encoding:.gbk)==hex("d6d0cec4"),"CP936 response")
rejects("GBK is not GB18030 emoji"){_=try NativeSAMPTextCodec.encode("🙂",encoding:.gbk)}
rejects("Unsupported input encoding"){_=try NativeSAMPTextCodec.encode("🙂",encoding:.windows1251)}
rejects("Input bytes bound"){_=try NativeSAMPTextCodec.encode(String(repeating:"é",count:128),encoding:.utf8)}
let dialogData=hex("2a000203426f78024f4b0643616e63656c8630252840"),dialogBits=17*8+34
guard case .dialog(let parsed)?=try NativeSAMPServerUI.decode(.init(id:61,data:dialogData,bits:dialogBits)),let dialog=parsed else{fatalError("dialog decode")}
check(dialog.id==42 && dialog.style == .list && dialog.title=="Box" && dialog.message=="hello","actual Huffman dialog")
let reply=try NativeSAMPProtocol.rpc(NativeSAMPServerUI.dialogResponse(dialog,accepted:true,selectedRow:0))
check(reply.id==62 && reply.data==hex("2a000100000568656c6c6f"),"dialog response known wire fields")
for bits in 0..<dialogBits{rejects("truncated dialog\(bits)"){_=try NativeSAMPServerUI.decode(.init(id:61,data:dialogData,bits:bits))}}
let headers=NativeSAMPServerUI.Dialog(id:7,style:.headers,title:"Select",button1:"OK",button2:"Cancel",message:"Name\tCost\n{FF0000}Alpha\t$25\nBeta\t$50\n")
check(headers.rows.count==2 && headers.header=="Name\tCost","headers are not list item0")
let headerReply=try NativeSAMPProtocol.rpc(NativeSAMPServerUI.dialogResponse(headers,accepted:false,selectedRow:0))
check(headerReply.data==hex("070000000005416c706861"),"cancel retains selected index and first column without colors")
rejects("invalid list row"){_=try NativeSAMPServerUI.dialogResponse(headers,accepted:true,selectedRow:2)}
rejects("missing selected row"){_=try NativeSAMPServerUI.dialogResponse(headers,accepted:true)}
let password=NativeSAMPServerUI.Dialog(id:9,style:.password,title:"Login",button1:"Login",button2:"Cancel",message:"Password")
let passReply=try NativeSAMPProtocol.rpc(NativeSAMPServerUI.dialogResponse(password,accepted:false,input:"abc"))
check(passReply.data==hex("090000ffff03616263"),"password cancel fields")
for raw in UInt8(0)...UInt8(5){
 let d=NativeSAMPServerUI.Dialog(id:9,style:.init(rawValue:raw)!,title:"",button1:"",button2:"",message:"One\nTwo")
 let r=try NativeSAMPProtocol.rpc(NativeSAMPServerUI.dialogResponse(d,accepted:true,selectedRow:d.style.isList ? d.rows.count-1:nil,input:"abc"));check(r.id==62,"six styles")
}
let closed=try NativeSAMPServerUI.decode(.init(id:61,data:hex("ffff"),bits:16));check(closed == .dialog(nil),"hide dialog")
var tw=NativeSAMPProtocol.Writer();tw.integer(2051,size:2);tw.integer(19,size:1);tw.float(0.5);tw.float(1.25);tw.integer(0xff332211,size:4);tw.float(120);tw.float(40);tw.integer(0x80224466,size:4);tw.integer(2,size:1);tw.integer(1,size:1);tw.integer(0xff000000,size:4);tw.integer(4,size:1);tw.integer(1,size:1);tw.float(100);tw.float(200);tw.integer(411,size:2);tw.vector(SIMD3(10,20,30));tw.float(1.5);tw.integer(65535,size:2);tw.integer(6,size:2);tw.integer(6,size:2);tw.bytes(Data("sprite".utf8))
guard case .showTextDraw(let draw)?=try NativeSAMPServerUI.decode(.init(id:134,data:tw.data,bits:tw.bits))else{fatalError("TextDraw")}
check(draw.playerTextDraw && draw.id==2051 && draw.letterColor==0xff332211 && draw.rotation==SIMD3(10,20,30) && draw.zoom==1.5 && draw.color1 == -1,"all TextDraw wire fields")
for bits in 0..<tw.bits{rejects("truncated TextDraw\(bits)"){_=try NativeSAMPServerUI.decode(.init(id:134,data:tw.data,bits:bits))}}
let store=NativeSAMPServerUI.Store();store.apply(.showTextDraw(draw))
rejects("click needs selection"){_=try store.click(draw.id)}
var selection=NativeSAMPProtocol.Writer();selection.bit(true);selection.integer(0x11223344,size:4)
guard let event=try NativeSAMPServerUI.decode(.init(id:83,data:selection.data,bits:selection.bits))else{fatalError()};store.apply(event)
check(store.selection && store.highlight==0x11223344,"unaligned selection BIT and RGBA")
let click=try NativeSAMPProtocol.rpc(store.click(draw.id));check(click.id==83 && click.data==hex("0308"),"player TextDraw click ID retained")
check(try NativeSAMPProtocol.rpc(store.click(nil)).data==hex("ffff"),"selection cancel sentinel")
store.apply(.textDrawString(draw.id,"changed"));check(store.draws[draw.id]?.text=="changed","text update")
store.apply(.hideTextDraw(draw.id));rejects("hidden clickable removed"){_=try store.click(draw.id)}
store.apply(.dialog(password));store.reset();check(store.dialog==nil && store.draws.isEmpty && !store.selection,"session reset")
rejects("TextDraw ID bound"){_=try NativeSAMPServerUI.clickTextDraw(2304)}
for viewport in [CGRect(x:0,y:0,width:640,height:448),CGRect(x:47,y:0,width:750,height:390),CGRect(x:0,y:20,width:1170,height:2332)] {
 let rect=NativeSAMPTextDrawLayout.box(draw,viewport:viewport)
 check(abs(rect.minX-(viewport.minX+100*viewport.width/640))<0.001 && abs(rect.minY-(viewport.minY+200*viewport.height/448))<0.001,"sprite origin scaling")
 check(abs(rect.width-120*viewport.width/640)<0.001 && abs(rect.height-40*viewport.height/448)<0.001,"sprite extent scaling")
}
print("PASS native server UI/codec \(checks) golden, truncation, encoding, response and selection checks")
