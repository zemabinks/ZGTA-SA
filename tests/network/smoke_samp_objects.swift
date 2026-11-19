// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
var checks = 0
func check(_ value: Bool, _ label: String) { precondition(value, label); checks += 1 }
func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>, tolerance: Float = 0.005) -> Bool { simd_length(a - b) <= tolerance }
func bytes(_ string: String) -> Data {
    var result = Data(); var index = string.startIndex
    while index < string.endIndex { let end = string.index(index, offsetBy: 2); result.append(UInt8(string[index..<end], radix: 16)!); index = end }
    return result
}
var events: [String: NativeSAMPObjects.Event] = [:]
for row in root["packets"] as! [Any] {
    guard let row = row as? [String: Any] else { continue }
    let id = UInt8(row["id"] as! Int), data = bytes(row["hex"] as! String), label = row["label"] as! String
    let event = try NativeSAMPObjects.decode(.init(id: id, data: data, bits: data.count * 8))!
    events[label] = event
    for count in 0..<data.count {
        do { _ = try NativeSAMPObjects.decode(.init(id: id, data: data.prefix(count), bits: count * 8)); preconditionFailure("Accepted truncated \(label) prefix\(count)") }
        catch { checks += 1 }
    }
    do { _ = try NativeSAMPObjects.decode(.init(id: id, data: data + Data([0]), bits: data.count * 8 + 8)); preconditionFailure("Accepted trailing \(label)") }
    catch { checks += 1 }
}
guard case .create(let base) = events["custom"]!, case .create(let attached) = events["attached"]!,
      case .create(let stock) = events["stock"]! else { fatalError("Wrong actual packet kind") }
check(base.id == 17 && base.model == -1001 && base.cameraCollision && base.drawDistance == 300, "DL model/id/distance/camera fields")
check(base.position == SIMD3(1.25, -4, 8.5) && base.rotation == SIMD3(10, 20, 350), "Preserve original Z-up positions and degree rotations")
check(base.attachment == nil && attached.attachment?.parent == .vehicle(4) && stock.attachment?.parent == .object(17), "Attachment sentinel and parent kinds")
check(attached.attachment?.offset == SIMD3(1, 2, 3) && attached.attachment?.rotation == SIMD3(4, 5, 6) && attached.attachment?.syncRotation == true, "Attached transform fields")
check(base.materials[3] == .texture(model: 19379, dictionary: "concrete", texture: "wall_01", abgr: 0x80332211), "Actual default material slots and ABGR")
let store = NativeSAMPObjects.Store(maximumObjects: 2)
try store.apply(events["custom"]!, at: 0); try store.apply(events["attached"]!, at: 0)
do { try store.apply(events["stock"]!, at: 0); preconditionFailure("Unbounded object pool") } catch { checks += 1 }
try store.apply(events["custom"]!, at: 0); check(store.count == 2, "Replacement works within pool limit")
try store.apply(events["move"]!, at: 1)
let duration = Double(simd_length(SIMD3<Float>(10, 20, 10)) / 5)
let midpoint = try store.instances(at: 1 + duration / 2).first { $0.id == 17 }!
check(near(midpoint.position, SIMD3(6.25, 6, 13.5)), "Actual MoveObject speed/time interpolation")
check(near(midpoint.rotation, SIMD3(10, 20, 180)), "Raw350→10 rotation must not silently use shortest arc")
try store.apply(events["stop"]!, at: 1 + duration / 2)
let stopped = try store.instances(at: 100).first { $0.id == 17 }!
check(stopped.position == midpoint.position && stopped.rotation == midpoint.rotation, "Stop retains sampled geometry pose")
let backwards = try store.instances(at: 0).first { $0.id == 17 }!
check(backwards == stopped, "Regressing clock cannot rewind object movement")
try store.apply(events["player"]!, at: 100)
check(try store.instances(at: 100).first { $0.id == 17 }!.attachment?.parent == .player(35), "Attach to actual player ID")
try store.apply(events["destroy"]!, at: 100)
check(store.count == 1, "Destroy releases exact object namespace")
try store.apply(events["custom"]!, at: 100)
check(try store.instances(at: 100).first { $0.id == 17 }! == base, "Reused ID must not retain old movement, attachment or material ownership")
store.reset(); check(store.count == 0, "Disconnect releases complete object pool")
var motionRows = 0
for rate in [15, 30, 60, 90, 120, 144] {
    let runtime = NativeSAMPObjects.Store(); try runtime.apply(events["custom"]!, at: 0); try runtime.apply(events["move"]!, at: 0)
    for entry in root["motion"] as! [Any] {
        guard let row = entry as? [String: Any], row["hz"] as? Int == rate else { continue }
        let time = (row["at"] as! NSNumber).doubleValue
        let point = (row["point"] as! [NSNumber]).map(\.floatValue), turn = (row["rotation"] as! [NSNumber]).map(\.floatValue)
        let instance = try runtime.instances(at: time)[0]
        check(near(instance.position, SIMD3(point[0], point[1], point[2])), "Official advanceMove position at\(rate)Hz/\(time)")
        check(near(instance.rotation, SIMD3(turn[0], turn[1], turn[2])), "Official advanceMove degree rotation at\(rate)Hz/\(time)")
        motionRows += 1
    }
}
let zero = NativeSAMPObjects.Store(); try zero.apply(.create(base), at: 0)
try zero.apply(.move(17, from: base.position, to: base.position, speed: 1, rotation: SIMD3(-1000, -2000, 90)), at: 0)
check(try zero.instances(at: 0)[0].rotation == SIMD3(10, 20, 90), "Zero distance and no-rotation axis sentinels")
check(try NativeSAMPObjects.decode(.init(id: 1, data: Data(), bits: 0)) == nil, "Unrelated RPC remains available to its actual owner")
for value in [Double.nan, .infinity, -.infinity] {
    do { _ = try zero.instances(at: value); preconditionFailure("Accepted invalid monotonic time") } catch { checks += 1 }
}
print("PASS \(checks) object codec/state checks; \(motionRows) actual official motion samples across6 frame schedules")
let turned=NativeSAMPObjectScene.transform(position:SIMD3(20,30,40),degrees:SIMD3(0,0,90))
let east=turned*SIMD4<Float>(1,0,0,1)
check(near(SIMD3(east.x,east.y,east.z),SIMD3(20,29,40)),"GTA positiveZ degrees rotate clockwise; preserve Z-up")
let fullScene=NativeSAMPObjectScene.resolve([base,attached,stock]){parent in parent == .vehicle(4) ? turned:nil}
check(fullScene.draws.count==3 && fullScene.unresolved.isEmpty,"Parent graph resolves regardless of input ID order")
let carObject=fullScene.draws.first{$0.object.id==18}!
check(near(SIMD3(carObject.transform.columns.3.x,carObject.transform.columns.3.y,carObject.transform.columns.3.z),SIMD3(22,29,43)),"Vehicle-attached offset follows its real parent transform")
let missingScene=NativeSAMPObjectScene.resolve([base,attached,stock]){_ in nil}
check(missingScene.unresolved==[18] && missingScene.draws.count==2,"Missing parent never draws attached object at zero or stale pose")
let duplicates=NativeSAMPObjectScene.resolve([base,base,stock]){_ in nil}
check(duplicates.draws.isEmpty && duplicates.unresolved==[17,19],"Duplicate identity cannot acquire arbitrary scene ownership")
var cyclic=base
cyclic.attachment = .init(parent:.object(19),offset:.zero,rotation:.zero,syncRotation:true)
let cycles=NativeSAMPObjectScene.resolve([cyclic,stock]){_ in nil}
check(cycles.draws.isEmpty && cycles.unresolved==[17,19],"Cyclic attachment graph remains unresolved")
var independent=attached
independent.attachment = .init(parent:.vehicle(4),offset:SIMD3(1,2,3),rotation:.zero,syncRotation:false)
let independentPose=NativeSAMPObjectScene.resolve([independent]){_ in turned}.draws[0].transform
check(near(SIMD3(independentPose.columns.0.x,independentPose.columns.0.y,independentPose.columns.0.z),SIMD3(1,0,0)),"Disabled rotation sync preserves its world orientation")
var invalidMatrix=matrix_identity_float4x4;invalidMatrix.columns.0.x = .nan
check(NativeSAMPObjectScene.resolve([attached]){_ in invalidMatrix}.draws.isEmpty,"Invalid parent matrices cannot reach Metal")
print("PASS \(checks) combined object wire, motion and native attachment scene checks")

// Display reads cannot consume the fixed physical timeline.
for rate in [15,30,60,90,120,144] {
 let runtime=NativeSAMPObjects.Store();try runtime.apply(.create(base),at:0)
 try runtime.apply(.move(base.id,from:.zero,to:SIMD3(60,0,0),speed:1,rotation:SIMD3(-1000,-1000,-1000)),at:0)
 var clock=NativeSAMPObjectSimulationClock(),accumulator=0.0,ticks=0
 let fixed=1.0/60
 for frame in 1...(rate*2) {
  let now=Double(frame)/Double(rate)
  _=try runtime.sampledInstances(at:now) // Deliberately sample display first.
  accumulator+=1/Double(rate)
  while accumulator+1e-10>=fixed {
   let at=clock.advance(delta:fixed,now:ticks==0 ? fixed:now)!
   let object=try runtime.sampledInstances(at:at)[0];ticks+=1;accumulator-=fixed
   check(abs(at-Double(ticks)*fixed)<1e-10,"Fixed object clock independent of display schedule")
   check(abs(Double(object.position.x)-Double(ticks)*fixed)<0.000001,"Earlier physical sample not clamped to later render timestamp")
  }
 }
 check(ticks==120,"Every frame rate advances same120 physical targets")
 clock.reset();check(clock.advance(delta:fixed,now:20)==20,"Suspension explicitly rebases physical epoch")
 let previous=clock.timestamp
 check(clock.advance(delta:.nan,now:21)==nil && clock.timestamp==previous,"Invalid delta cannot consume physical epoch")
}
print("PASS \(checks) combined object/scene/physical-clock checks")
