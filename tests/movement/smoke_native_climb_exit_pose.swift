// SPDX-License-Identifier: AGPL-3.0-only
// Actual first-completion-tick poses; original caller/blending timing is separate.
@main enum ClimbExitPoseSmoke {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
  let historical=CommandLine.arguments.contains("historical")
  var rows=[[String:Any]](),differences=0
  for hz in [15,30,60,120,144] {for phase:NativeClimbController.Part in [.stand,.vault] {for cause in ["requested-abort","equipment-abort","successful-finish"] {
   let h=try ClimbRuntimeHarness(root:root,top:1.8,depth:phase == .vault ? 0.08:2)
   h.footLaunchRemaining=nil;h.jump()
   var acquired=false
   for _ in 0..<1200{_=h.frame(1/120);if h.climb?.part == phase{acquired=true;break}}
   precondition(acquired,"Actual phase must be reached, not injected")
   h.completionClips=nil
   if cause=="requested-abort"{h.letGoOfLedge()}
   if cause=="equipment-abort"{h.setFlightGear(parachute:false,jetpack:true);h.cancelGameplayInput()}
   for _ in 0..<(hz*5){_=h.frame(1/Double(hz));if h.completionClips != nil{break}}
   guard let clips=h.completionClips else{preconditionFailure("No actual completion tick")}
   let finish=phase == .stand ? "ped/climb_stand_finish":"ped/climb_jump2fall"
   let expected=cause=="successful-finish",actual=clips.contains(finish)
   if actual != expected{differences += 1}
   rows.append(["hz":hz,"phase":phase.rawValue,"cause":cause,"completionClips":clips,"finishClip":finish,"actualFinishClip":actual,"expectedFinishClip":expected,"differs":actual != expected])
  }}}
  let result:[String:Any]=["status":"ACTUAL_NATIVE_CLIMB_EXIT_POSE_OBSERVATIONS","cases":rows,"differences":differences,"scope":"Actual selected Renderer gear/input/climb/foot owners, real local CLP and native motor/Rapier. Authored admitted ledges and independent first-completion-tick observer. No normal App, GPU, hardware or original retail blending/timing acceptance."]
  try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:output)
  print("Actual climb exit pose:",rows.count,"cases;",differences,"differences")
  precondition(rows.count==30)
  if historical{exit(differences==20 ? 42:1)}
  exit(differences==0 ? 0:1)
 }
}
