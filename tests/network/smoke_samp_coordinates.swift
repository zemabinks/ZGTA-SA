// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
// ACTUAL_PED_COORDINATES
let references=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))as![[String:Any]]
let output=URL(fileURLWithPath:CommandLine.arguments[2]),assetRoot=URL(fileURLWithPath:CommandLine.arguments[3])
var results=[[String:Any]](),checks=0
func check(_ value:Bool,_ text:String){checks+=1;precondition(value,text)}
for row in references {
    let raw=row["position"]as![NSNumber],point=SIMD3<Float>(raw[0].floatValue,raw[1].floatValue,raw[2].floatValue)
    let path=assetRoot.appendingPathComponent(row["collisionFile"]as!String)
    let data=try Data(contentsOf:path),mesh=try SwiftRapierWorld.decodeSCL2(data)
    let world=SwiftRapierWorld(gravity:.zero)!,collider=world.addTriangleMesh(mesh)!
    let hit=world.raycast(origin:SwiftRapierWorld.gtaToRapier(point+SIMD3(0,0,0.1)),direction:SIMD3(0,-1,0),distance:10)!
    let floor=point.z+0.1-hit.distance
    check(abs(floor-Float((row["floor"]as![String:Any])["z"]as!Double))<0.001,"Actual Rapier imported floor differs from independent triangle query")
    let motor=NativeCharacterController(world:world)!
    let rootInput=row["kind"]as?String=="networkRoot"
    let feet=rootInput ? NativeSAMPPedCoordinates.feet(point):point
    motor.reset(feet:feet)
    for _ in 0..<120{_=motor.update(delta:1.0/60,displacement:.zero,geometryReady:true)}
    let settled=motor.state.feet,network=NativeSAMPPedCoordinates.root(settled)
    check(motor.state.grounded,"Actual native motor failed to settle on original mesh")
    check(settled.z>=floor-0.001 && settled.z<=floor+0.04,"Native foot/contact margin outside measured boundary")
    check(abs(network.z-settled.z-1)<0.0001,"Outgoing root boundary incorrect")
    if rootInput {check(abs(point.z-floor-1)<0.001,"Official class root does not establish1m origin convention")}
    results.append(["label":row["label"]!,"inputKind":rootInput ? "networkRoot":"recordedNativeFeet", "input":[point.x,point.y,point.z],
                    "actualMeshFloorZ":floor,"initialNativeFeetZ":feet.z,"settledNativeFeetZ":settled.z,
                    "measuredNativeContactMargin":settled.z-floor,"outgoingNetworkRootZ":network.z,
                    "networkRootAboveFloor":network.z-floor])
    world.removeCollider(collider)
}
try JSONSerialization.data(withJSONObject:["status":"PASS","checks":checks,"cases":results],options:[.prettyPrinted,.sortedKeys]).write(to:output)
print("PASS: \(checks) actual original-mesh/native-motor pedestrian origin checks; no retail executable claim")
