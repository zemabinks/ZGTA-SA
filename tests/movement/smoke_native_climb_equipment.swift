// SPDX-License-Identifier: AGPL-3.0-only
// App dispatch and flight physics are separate gates. This carrier executes
// actual selected gear/input/climb/foot owners, real CLP and native Rapier.
@main enum ClimbEquipmentSmoke {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  let output=URL(fileURLWithPath:CommandLine.arguments[2])
  let historical=CommandLine.arguments.contains("historical")
  var rows=[[String:Any]](),differences=0
  func reach(_ part:NativeClimbController.Part)throws->ClimbRuntimeHarness {
   let low=part == .edge || part == .stand || part == .vault
   let h=try ClimbRuntimeHarness(root:root,top:low ? 1.8:2.7,depth:part == .vault ? 0.08:2)
   h.footLaunchRemaining=nil;h.jump()
   for _ in 0..<1200 {
    _=h.frame(1/120)
    if h.climb?.part == part{return h}
    if part == .pull,h.climb?.part == .hang{h.jumpHeld=true}
   }
   preconditionFailure("Actual task did not reach required phase: \(part)")
  }
  func observe(_ h:ClimbRuntimeHarness,_ hz:Int,_ kind:String,_ phase:NativeClimbController.Part,_ shouldOwn:Bool) {
   h.recordNextOwnerTick=true;h.recordedClimbOwner=nil
   for _ in 0..<3 {
    _=h.frame(1/Double(hz))
    if h.recordedClimbOwner != nil{break}
   }
   guard let owns=h.recordedClimbOwner else{preconditionFailure("No receiving fixed tick")}
   let differs=owns != shouldOwn
   if differs{differences += 1}
   rows.append(["hz":hz,"kind":kind,"phase":phase.rawValue,"climbOwnsFirstReceivingTick":owns,"wornEquipment":h.personalFlight.worn,"expectedClimbOwnership":shouldOwn,"differs":differs])
  }
  for hz in [15,30,60,120,144] {
   // Retain the exact three causal orderings from the initial real witness.
   for kind in ["gear-then-input-loss","gear-without-input-loss","drop-input-then-input-loss"] {
    let h=try reach(.hang)
    if kind=="drop-input-then-input-loss"{h.letGoOfLedge()}else{h.setFlightGear(parachute:false,jetpack:true)}
    if kind != "gear-without-input-loss"{h.cancelGameplayInput()}
    let shouldOwn=kind=="drop-input-then-input-loss"
    precondition(h.personalFlight.worn != shouldOwn)
    observe(h,hz,kind,.hang,shouldOwn)
   }
   // Granting then revoking equipment before the physical tick leaves an
   // ordinary input cancellation. It must not invent a persistent drop.
   let revoked=try reach(.hang)
   revoked.setFlightGear(parachute:false,jetpack:true)
   revoked.setFlightGear(parachute:false,jetpack:false)
   revoked.cancelGameplayInput()
   precondition(!revoked.personalFlight.worn)
   observe(revoked,hz,"grant-revoke-then-input-loss",.hang,true)
   // Acquire each phase on actual fixed ticks, then vary the display cadence
   // of the grant/cancellation and receiving updates. No phase is injected.
   for phase:NativeClimbController.Part in [.jump,.pull,.edge,.stand,.vault] {
    for inputLoss in [false,true] {
     let h=try reach(phase)
     h.setFlightGear(parachute:false,jetpack:true)
     if inputLoss{h.cancelGameplayInput()}
     observe(h,hz,inputLoss ? "phase-gear-then-input-loss":"phase-gear",phase,false)
    }
   }
  }
  let result:[String:Any]=["status":"ACTUAL_CLIMB_EQUIPMENT_OWNERSHIP","cases":rows,"differences":differences,
   "scope":"Actual selected Renderer owners, actual CLP phases and native motor/Rapier. Authored admitted ledges and event ordering; no actual flight dispatch, UI, network, GPU, hardware or retail acceptance."]
  try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:output)
  precondition(rows.count==70)
  print("Actual climb/equipment ownership:",rows.count,"cases;",differences,"differences")
  if historical{exit(differences==30 ? 42:1)}
  exit(differences==0 ? 0:1)
 }
}
