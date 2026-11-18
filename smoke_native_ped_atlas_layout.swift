// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
var checks=0
func check(_ value:Bool,_ label:String){checks+=1;if !value{fputs("FAIL \(label)\n",stderr);exit(1)}}
func rejects(_ label:String,_ body:()throws->Void){checks+=1;do{try body();fputs("FAIL accepted \(label)\n",stderr);exit(1)}catch{}}
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let entries=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("fixtures.json"))) as! [[String:Any]]
for entry in entries {
    let name=entry["model"] as! String,path=entry["path"] as! String
    let metadata=try Data(contentsOf:root.appendingPathComponent(path)),manifest=try JSONDecoder().decode(NativePedAtlasFamily.self,from:metadata)
    try manifest.validate(expectedModel:name)
    check(NativePedAtlasFamily.digest(in:path,model:name)==NativePedAtlasLayout.digest(metadata),"external manifest digest")
    var values:[String:Data]=[:]
    for (role,member) in manifest.resources.all {
        let data=try Data(contentsOf:root.appendingPathComponent(member.path));try member.validate(data);values[role]=data
        var corrupt=data;corrupt[0] ^= 1;rejects("\(role) checksum"){try member.validate(corrupt)}
    }
    let binary=values["mesh"]!,image=values["atlas"]!,layoutData=values["layout"]!
    let world=try WorldBinary(data:binary),layout=try JSONDecoder().decode(NativePedAtlasLayout.self,from:layoutData)
    let admitted=try layout.validate(mesh:binary,png:image,world:world);try manifest.validateSource(layout:layout)
    var prefixed=Data([0,0,0]);prefixed.append(image)
    check(try layout.validate(mesh:binary,png:prefixed[3...],world:world).vectors==admitted.vectors,"nonzero Data startIndex")
    check(admitted.vectors.count==world.layers+1,"header plus each layer")
    check(admitted.width*admitted.height*4==admitted.textureBytes && admitted.textureBytes<=524288,"logical budget")
    for (slot,row) in layout.layers.enumerated() {
        let r=admitted.vectors[slot+1]
        for u in [-2.5,0,0.25,0.999,1,3.4] {for v in [-1.3,0,0.75,1,2.9] {
            let x=Double(r.x)+0.5+(u-floor(u))*(Double(r.z)-1),y=Double(r.y)+0.5+(v-floor(v))*(Double(r.w)-1)
            check(x>=Double(row.rect[0])+0.5 && x<=Double(row.rect[0]+row.rect[2])-0.5,"horizontal content bound")
            check(y>=Double(row.rect[1])+0.5 && y<=Double(row.rect[1]+row.rect[3])-0.5,"vertical content bound")
        }}
    }
    func changed(_ changes:(inout [String:Any])->Void)throws->NativePedAtlasLayout {
        var object=try JSONSerialization.jsonObject(with:layoutData) as! [String:Any];changes(&object)
        return try JSONDecoder().decode(NativePedAtlasLayout.self,from:JSONSerialization.data(withJSONObject:object))
    }
    for field in ["schema","layout","sampling","columns","atlas","cell","logicalRGBA8Bytes","meshSHA256","atlasSHA256","maximumRGBA8Bytes","sourceDFFSHA256"] {
        rejects("layout field \(field)") {
            let broken=try changed{object in
                switch field {
                case "schema":object[field]=true
                case "layout","sampling":object[field]="unknown"
                case "columns":object[field]=0
                case "atlas":object[field]=[4097,4097]
                case "cell":object[field]=[0,4]
                case "logicalRGBA8Bytes":object[field]=0
                case "maximumRGBA8Bytes":object[field]=524289
                default:object[field]="bad"
                }
            }
            _=try broken.validate(mesh:binary,png:image,world:world)
        }
    }
    rejects("mismatched layer count") {
        let broken=try changed{$0["layers"]=[]};_=try broken.validate(mesh:binary,png:image,world:world)
    }
    rejects("incorrect content origin") {
        let broken=try changed{object in var rows=object["layers"] as! [[String:Any]];let slot=min(1,rows.count-1);rows[slot]["rect"]=[1,0,1,1];object["layers"]=rows}
        _=try broken.validate(mesh:binary,png:image,world:world)
    }
    rejects("zero content height") {
        let broken=try changed{object in var rows=object["layers"] as! [[String:Any]];let slot=min(1,rows.count-1);var r=rows[slot]["rect"] as! [Int];r[3]=0;rows[slot]["rect"]=r;object["layers"]=rows}
        _=try broken.validate(mesh:binary,png:image,world:world)
    }
    rejects("wrong model"){try manifest.validate(expectedModel:"different")}
    rejects("source identity") {
        let broken=try changed{$0["sourceTXDSHA256"]=String(repeating:"0",count:64)};try manifest.validateSource(layout:broken)
    }
    var original=try JSONSerialization.jsonObject(with:metadata) as! [String:Any]
    for mutation in ["path","bytes","family","sourceIdentity","boolbytes"] {
        rejects("family \(mutation)") {
            var object=original
            if mutation=="family"{object["format"]="other"}
            else if mutation=="sourceIdentity"{object["sourceIdentity"]="bad"}
            else {
                var resources=object["resources"] as! [String:[String:Any]]
                if mutation=="path"{resources["atlas"]!["path"]="game/native/models/../other.png"}
                if mutation=="bytes"{resources["atlas"]!["bytes"] = 8*1024*1024+1}
                if mutation=="boolbytes"{resources["atlas"]!["bytes"]=true}
                object["resources"]=resources
            }
            let broken=try JSONDecoder().decode(NativePedAtlasFamily.self,from:JSONSerialization.data(withJSONObject:object));try broken.validate(expectedModel:name)
        }
    }
    original["resources"]=[:]
    rejects("missing required skeleton"){_=try JSONDecoder().decode(NativePedAtlasFamily.self,from:JSONSerialization.data(withJSONObject:original))}
}
let index:[String:[String:String]]=["peds":["7":"authored"],"vehicles":["420":"car"],"weapons":["22":"pistol"],"pedAtlasV1":["authored":entries[0]["path"] as! String]]
let decoded=try JSONSerialization.jsonObject(with:JSONSerialization.data(withJSONObject:index)) as? [String:[String:String]]
check(decoded?["peds"]?["7"]=="authored" && decoded?["pedAtlasV1"]?["authored"] != nil,"old complete index cast remains valid")
print("PASS ped atlas layout: \(checks) actual parser/source/hash/rect/schema checks; entirely authored resources")
