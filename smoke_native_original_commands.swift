import Foundation

let input=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
var checks=0
func check(_ condition:Bool,_ label:String){checks+=1;guard condition else{fatalError("Original commands: \(label)")}}
func equal(_ a:Any,_ b:Any)->Bool{
    guard JSONSerialization.isValidJSONObject(a),JSONSerialization.isValidJSONObject(b),
          let x=try?JSONSerialization.data(withJSONObject:a,options:[.sortedKeys]),
          let y=try?JSONSerialization.data(withJSONObject:b,options:[.sortedKeys]) else{return false}
    return x==y
}
let vehicleCases=input["cases"]as![[String:Any]]
for (index,test)in vehicleCases.enumerated(){
    let message=test["message"]as![String:Any],model=test["model"]as!Int,driving=test["driving"]as!Bool
    let hit=NativeOriginalWorldCommands.vehicleDamage(message,driving:driving,model:model)
    var effects:[[Any]]=[]
    if let hit{
        if hit.damage>0{effects.append(["damage",hit.damage])}
        if let wheel=hit.wheel{effects.append(["wheel",wheel])}
    }
    check(equal(effects,test["expected"]!),"vehicle callback \(index): \(message), \(effects)")
}
let commandCases=input["commandCases"]as![[String:Any]]
for (index,test)in commandCases.enumerated(){
    let message=test["message"]as![String:Any],events=NativeOriginalWorldCommands.decode(message)
    let expected=test["expected"]as![[Any]]
    var effects:[[Any]]=[]
    for event in events{
        switch event{
        case .repairVehicle:effects.append(["fix"])
        case .flipVehicle:effects.append(["flip"])
        case .slap(let amount):effects.append(["slap",amount])
        case .dress(let skin,let note):effects.append(["dress",skin,note as Any? ?? NSNull()])
        case .cash(let amount):effects.append(["cash",amount])
        case .teleport(let t):
            let out:Any=t.out.map{[$0.x,$0.y]}as Any? ?? NSNull()
            effects.append(["tp",["x":t.point.x,"y":t.point.y,"z":t.point.z,"ground":t.ground,
                "heading":t.heading as Any? ?? NSNull(),"out":out]as[String:Any]])
        case .passive(let on,let wait):effects.append(["passive",["on":on,"wait":wait]])
        case .shield(let seconds):effects.append(["shield",["seconds":seconds]])
        case .style(let style):effects.append(["style",style])
        case .name(let name):effects.append(["name",name])
        case .profile(let name):effects.append(["profile",name])
        case .heal(let heal):effects.append(["dose",heal])
        default:break
        }
    }
    // The helper carries the displayed name/heal only. Other profile/dose
    // fields belong to separate service UI and are outside this comparison.
    let reduced=expected.map{row->[Any]in
        if row[0]as?String=="name",let value=row.dropFirst().first as?[String:Any]{return["name",value["name"]!]}
        if row[0]as?String=="dose",let value=row.dropFirst().first as?[String:Any]{return["dose",value["heal"]!]}
        return row
    }
    check(equal(effects,reduced),"command callback \(index): \(message), \(effects), \(reduced)")
}
// Peer input validation remains explicit. These malformed-object checks are
// stricter than browser coercions and are not called original runtime parity.
for invalid:Any in [true,false,"10",NSNull(),Double.nan,Double.infinity]{
    check(NativeOriginalWorldCommands.number(invalid)==nil,"strict finite numeric")
}
check(NativeOriginalWorldCommands.integer(1.5)==nil,"fractional integer")
check(NativeOriginalWorldCommands.integer(9_007_199_254_740_992.0)==nil,"unsafe integer")
check(NativeOriginalWorldCommands.boolean(1)==nil,"numeric is not strict boolean")
check(NativeOriginalWorldCommands.truthy([Any]()),"empty JS array remains truthy")
check(NativeOriginalWorldCommands.truthy([String:Any]()),"empty JS object remains truthy")
check(!NativeOriginalWorldCommands.truthy(""),"empty JS string false")
let staff:[String:Any]=["t":"staff","freeze":true,"hp":-1,"armour":50.5,
    "give":[22,17],"take":24,"back":[25,9],"fill":[22,100],
    "arm":[[31,30.5],[22,10],["bad",1],[25,true]],"jetpack":"yes","skin":287,"disarm":1,"respawn":true,"clear":false]
guard case .staff(let parsed)?=NativeOriginalWorldCommands.decode(staff).first else{fatalError("staff parse")}
check(parsed.freeze==true && parsed.health == -1 && parsed.armour==50.5,"staff numeric and freeze")
check(parsed.give == .init(id:22,amount:17),"staff give")
check(parsed.take==24 && parsed.back == .init(id:25,amount:9),"staff take/back")
check(parsed.fill == .init(id:22,amount:100),"staff fill total")
check(parsed.arm == [.init(id:31,amount:30.5),.init(id:22,amount:10)],"staff rearm finite filter")
check(parsed.jetpack && parsed.skin==287 && parsed.disarm && parsed.respawn && !parsed.clear,"staff flags")
let bigArms=Array(repeating:[22,10],count:5000)
guard case .staff(let bounded)?=NativeOriginalWorldCommands.decode(["t":"staff","arm":bigArms]).first else{fatalError("bounded staff")}
check(bounded.arm?.count==4096,"bounded rearm work")
check(NativeOriginalWorldCommands.decode(["t":"flightgear","jetpack":true]).isEmpty,"selfhost gear is not an original command")
guard case .wake(let point,let heading)?=NativeOriginalWorldCommands.decode(["t":"wake","at":[1,2,3,4]]).first else{fatalError("wake")}
for row in input["teleportCases"]as![[String:Any]]{
 let raw=row["message"]as![String:Any]
 guard case .teleport(let teleport)?=NativeOriginalWorldCommands.decode(raw).first else{fatalError("actual teleport")}
 let point=row["point"]as![Double]
 check(teleport.point==SIMD3(point[0],point[1],point[2]),"original network teleport GTA axes")
 if raw["h"] != nil{check(abs(Double(teleport.nativeHeading!)-(row["nativeHeading"]as!Double))<0.000001,"actual original teleport callback h degrees, unlike hello/wake radians")}
 else{check(teleport.nativeHeading==nil,"no h leaves current native facing to owner")}
}
check(point==SIMD3(1,2,3) && heading==4,"wake preserves wire position/heading")
check(NativeOriginalWorldCommands.decode(["t":"wake","at":[1,2,3,true]]).isEmpty,"wake rejects bool heading")
guard case .escape(let escape)?=NativeOriginalWorldCommands.decode(["t":"escape","c":"respawn","go":false,"no":"wanted","s":3.5]).first else{fatalError("escape")}
check(escape.command=="respawn" && !escape.allowed && escape.seconds==4 && escape.reason=="wanted","escape defers approval")
check(NativeOriginalWorldCommands.decode(["t":"cash","cash":Double.infinity]).isEmpty,"nonfinite cash")
print("PASS original command decoding: \(vehicleCases.count) actual vehicle callback cases, \(commandCases.count) actual command callbacks, \(checks) checks")
