import Foundation
import simd

@main enum CameraVisibilitySmoke {
 static func main() {
  var checks=0
  func check(_ value:Bool,_ label:String){checks += 1;precondition(value,label)}
  let feet=SIMD3<Float>(1480,-1738,13)
  for hz in [30,60,120] {
   var state=NativeCameraVisibility()
   check(!state.update(eye:feet+SIMD3(0,-4,2.4),feet:feet,nearPlane:0.15),"ordinary follow remains visible")
   for turn in 0..<360 {
    let radians=Float(turn)*Float.pi/180
    check(state.update(eye:feet+SIMD3(sin(radians)*0.4,cos(radians)*0.4,1.6),feet:feet,nearPlane:0.15),"collision-clamped0.4m eye hides own mesh at every angle")
   }
   for frame in 0..<hz*2 {
    let distance:Float=frame%2==0 ? 0.495:0.505
    check(state.update(eye:feet+SIMD3(distance,0,1.6),feet:feet,nearPlane:0.15),"spatial hysteresis prevents edge flicker")
   }
   check(!state.update(eye:feet+SIMD3(0.61,0,1.6),feet:feet,nearPlane:0.15),"clearance restores model")
   check(!state.update(eye:feet+SIMD3(0.55,0,1.6),feet:feet,nearPlane:0.15),"outside enter threshold remains visible")
   check(state.update(eye:feet+SIMD3(0.49,0,1.6),feet:feet,nearPlane:0.15),"near plane overlap hides model again")
   state.reset();check(!state.hidden,"teleport/model/mode can reset visibility history")
  }
  var state=NativeCameraVisibility()
  check(!state.update(eye:feet+SIMD3(0,0,2.5),feet:feet,nearPlane:0.15),"above head remains visible")
  check(state.update(eye:feet+SIMD3(0,0,1.2),feet:feet,nearPlane:0.15),"inside torso hides")
  state.reset();check(state.update(eye:feet+SIMD3(0.6,0,1.5),feet:feet,nearPlane:0.15,attachmentRadius:0.2),"optional measured attachment extent supported")
  state.reset();check(state.update(eye:SIMD3(.nan,0,0),feet:feet,nearPlane:0.15),"invalid transform cannot expose clipped own geometry")
  state.reset();check(state.update(eye:feet+SIMD3(0.2,0,1.2),feet:feet,nearPlane:0.15,bodyBottom:1,bodyTop:1,radius:0.35),"zero-length capsule supported")
  print("PASS: camera own-mesh visibility \(checks) checks at30/60/120Hz, all360 angles, collision clamp, near-plane clearance/hysteresis, attachment extent and reset")
 }
}
