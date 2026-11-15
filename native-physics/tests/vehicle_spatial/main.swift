import Foundation
import simd
typealias Spatial = NativeVehicleAudioSpatial
let root = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
func vector(_ value: Any) -> SIMD3<Double> {let a=value as! [Double];return SIMD3(a[0],a[1],a[2])}
let data=root["catalogue"] as! [String:[Int]]
let catalogue=Spatial.Catalogue(road:Set(data["road"]!),aircraft:Set(data["aircraft"]!),boats:Set(data["boats"]!),special:Set(data["special"]!),trains:Set(data["trains"]!))
let specialNames:[Int:String]=[539:"hover",457:"golf"]
var count=0,maximum=0.0
for scene in root["scenes"] as! [[String:Any]] {
    let candidates=(scene["candidates"] as! [[String:Any]]).map {Spatial.Candidate(id:$0["id"] as! String,model:$0["model"] as! Int,position:vector($0["position"]!),speed:$0["speed"] as! Double)}
    let actual=Spatial.select(candidates,listener:vector(scene["listener"]!),catalogue:catalogue)
    let expected=scene["selected"] as! [[String:Any]]
    precondition(actual.count==expected.count)
    var configs:[Spatial.Panner]=[]
    for (a,e) in zip(actual,expected) {
        precondition(a.candidate.id==e["id"] as! String)
        precondition(abs(a.distance-(e["distance"] as! Double))<1e-12)
        configs.append(Spatial.panner(kind:a.kind,special:specialNames[a.candidate.model]))
        if a.kind == .aircraft {configs.append(Spatial.panner(kind:a.kind,far:true))}
    }
    let expectedConfigs=scene["configs"] as! [[String:Double]]
    precondition(configs.count==expectedConfigs.count)
    for (a,e) in zip(configs,expectedConfigs) {precondition(a.reference==e["reference"] && a.maximum==e["maximum"] && a.rolloff==e["rolloff"])}
    count += actual.count
}
for row in root["spatial"] as! [[String:Any]] {
    let actual=Spatial.azimuth(source:vector(row["source"]!),listener:vector(row["listener"]!),forward:vector(row["forward"]!))
    let error=abs(actual-(row["azimuth"] as! Double));maximum=max(maximum,error);precondition(error<1e-10)
    for (i,mono) in [true,false].enumerated() {
        let actual=Spatial.matrix(azimuth:actual,mono:mono),expected=(row["matrices"] as! [[Double]])[i]
        for component in 0..<4 {precondition(abs(actual[component]-expected[component])<1e-12)}
    }
}
precondition(Spatial.panner(kind:.road).gain(distance:220)==7/(7+1.6*(220-7)))
precondition(Spatial.panner(kind:.boat).gain(distance:300)==1)
precondition(Spatial.azimuth(source:.zero,listener:.zero,forward:SIMD3(0,0,-1))==0)
print("PASS: original nearest-five selection/configurations \(count) voices,800 W3C azimuth+mono/stereo matrices; maximum angle error \(maximum)")
