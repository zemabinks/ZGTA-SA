// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

@main enum CJProfileSmoke {
    enum Failure: Error {case check(String)}
    static var checks=0
    static func check(_ value:Bool,_ reason:String)throws{checks+=1;if !value{throw Failure.check(reason)}}
    static func reject(_ reason:String,_ body:()throws->Void)throws{
        do{try body()}catch{checks+=1;return};throw Failure.check("Expected rejection: "+reason)
    }
    static func main()throws{
        let root=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
        let data=try Data(contentsOf:root.appendingPathComponent("profile.json")),profile=try NativeCJProfile.decode(data)
        var bytes=[String:Data]()
        for file in profile.files{bytes[file.role]=try Data(contentsOf:root.appendingPathComponent(NativeCJProfile.filenames[file.role]!))}
        let prepared=try profile.prepare(bytes)
        try check(prepared.assembly.dff.geometries[0].vertexCount==20,"actual authored body preparation")
        try check(prepared.contentIdentity==profile.contentIdentity,"Python producer matches actual Swift content identity")
        try check(prepared.assembly.animationStyleModel=="null","PLAYER1 style identity")
        let json=try JSONSerialization.jsonObject(with:data)as![String:Any]
        func changed(_ body:(inout[String:Any])->Void)throws->Data{var object=json;body(&object);return try JSONSerialization.data(withJSONObject:object)}
        for (field,value) in [("schema",2),("legacyID",1),("nativeID",7)]{
            try reject(field){_=try NativeCJProfile.decode(changed{$0[field]=value})}
        }
        for (field,value) in [("variant","Fat"),("profile","unspecified"),("model","male01"),("animationStyleModel","special01")]{
            try reject(field){_=try NativeCJProfile.decode(changed{$0[field]=value})}
        }
        try reject("descriptor bound"){_=try NativeCJProfile.decode(Data(repeating:32,count:65_537))}
        try reject("missing role"){_=try NativeCJProfile.decode(changed{$0["files"]=Array(($0["files"]as![[String:Any]]).dropLast())})}
        try reject("duplicate role"){_=try NativeCJProfile.decode(changed{var rows=$0["files"]as![[String:Any]];rows[1]=rows[0];$0["files"]=rows})}
        for path in ["game/../private.dff","https://other.invalid/player.dff",NativeCJProfile.prefix+"../player.dff",NativeCJProfile.prefix+"unexpected.dff"]{
            try reject("noncanonical path"){_=try NativeCJProfile.decode(changed{var rows=$0["files"]as![[String:Any]];rows[0]["path"]=path;$0["files"]=rows})}
        }
        for count in [0,-1,4*1024*1024+1]{
            try reject("file bound"){_=try NativeCJProfile.decode(changed{var rows=$0["files"]as![[String:Any]];rows[0]["bytes"]=count;$0["files"]=rows})}
        }
        var incomplete=bytes;incomplete.removeValue(forKey:"rules")
        try reject("missing acquired bytes"){_=try profile.prepare(incomplete)}
        var corrupt=bytes;corrupt["template"]![0]^=1
        try reject("corruption before parsing"){_=try profile.prepare(corrupt)}
        let wrongCRC=try NativeCJProfile.decode(changed{var rows=$0["files"]as![[String:Any]];rows[0]["crc32"]=0;$0["files"]=rows})
        try reject("CRC binding"){_=try wrongCRC.prepare(bytes)}
        let wrongIdentity=try NativeCJProfile.decode(changed{$0["contentIdentity"]=String(repeating:"0",count:64)})
        try reject("prepared content binding"){_=try wrongIdentity.prepare(bytes)}
        let report:[String:Any] = ["status":"PASS","checks":checks,"fixture":"authored-only","originalAssets":false]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output)
        print("PASS fixed-profile authored checks: \(checks)")
    }
}
