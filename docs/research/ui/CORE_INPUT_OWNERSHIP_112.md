# Core112 gameplay input ownership

The audit reproduced three related input defects in actual native source.

1. Six direct touch handlers could request sprint, jump, aim/guard/lights,
   crouch/dive/hitch release, landing gear or radio changes while the shared
   keyboard/controller action policy rejected input. Forty-eight authored
   handler/context cases demonstrate requests during background/detached/modal,
   connection-not-ready, selection, server-blocked and coughing states. UIKit
   will prevent some of these dispatches itself; the test does not claim that
   every authored context is independently reachable through a visible tap.
2. Controller polling remained eligible during a server freeze, selection or
   connection loss. Neutral polls could rearm the controller while actions were
   blocked, admitting a held control on resumption. The actual poll expression
   now uses the complete frame input-availability decision.
3. Controller neutrality used independent axis thresholds while movement used
   a radial deadzone. In the retained authored sweep,184 out-of-deadzone cases
   could rearm. The typed stick/trigger gate now uses both stick magnitudes.
   Separately, the actual right-stick delivery clause applied another per-axis
   threshold after radial filtering:72 of256 engaged direction/context samples
   were discarded entirely. An engaged right stick now supplies its complete
   vector, preserving direction and owning both camera axes like the left
   stick owns its movement vector. A neutral or invalid stick preserves other
   input. This also deliberately clears the other axis when an engaged stick
   supplies zero there, rather than mixing an old touch axis into that vector.

The existing0.05 native deadzone policy remains. This is a consistency repair,
not a measurement of the original game's undocumented controller response.
No vehicle force, animation curve, sensitivity constant, axis sign, wire format
or server authority is retuned here. Release/cancel handlers remain unconditional.

## Reproduction and regression

```sh
python3 tests/ui/smoke_native_action_gate.py
python3 tests/ui/smoke_native_controls.py
python3 tests/ui/smoke_native_original_controller.py
python3 tests/vehicles/smoke_native_coupling_controls.py
```

The new gate executes the actual extracted six handlers, both eligibility
properties, complete controller poll call and complete right-stick delivery
clause with the actual `NativeGameInput` helpers. Its1022 checks pass with zero
blocked-handler requests, zero out-of-deadzone rearming and zero dropped engaged
camera vectors. Positive action branches, guard exclusion, unsupported gear,
on-foot radio exclusion, normal controller rearming and inactive input fallback
remain covered. All four test inputs are hashed and unchanged through execution.
The test is registered in the broad gameplay gate.

The host fixture's UI, renderer and radio boundaries are explicitly inert request
recorders. It proves dispatch and vector ownership, not UIKit event delivery,
motor physics, audio, real controller hardware or retail gameplay feel. Separate
retained historical modes reproduce each earlier defect; they are not current
acceptance results. The normal aggregate uses only the corrected default mode.

The existing cadence/camera helper gate passes14576 checks over15–144Hz,
suspension, cancellation and angle handoff. Actual original/self-host/legacy
controller dispatch passes152 checks and coupling/passenger controls pass68.
Their narrower source/method boundaries are retained separately from the new
GameVC vector-delivery test. The frozen109 aggregate remains149 PASS/17 FAIL;
these focused results do not rewrite that run.

## SDK and runtime acceptance boundaries

The initial gate/neutral correction, before the additional camera delivery
repair, passes a complete arm64+x86_64 Simulator Debug build in1857.920s with
all202 frozen inputs unchanged. That result is preserved separately. Its device
build was stopped during initial setup after the new camera reproduction was
confirmed; no device PASS is claimed for that interrupted attempt. Final source
has a separate frozen202-input map. The complete revised universal Simulator
Debug build passes in165.578s and the arm64 iPhone Release build passes
in1254.864s through the actual public build script, with effective2-thread
compilation. All202 source inputs stay unchanged. A normal Simulator update
verifies all four installed payloads and preserves all four resource-cache
metadata files byte for byte, without resetting or seeding data. Normal UI
regression and physical112 acceptance are recorded separately from compilation.

The final dedicated Simulator normal-Guest UI regression passes in213.969s.
Reviewed original screenshots establish crouch/stand, a jump pose, grounded
stance and camera orbit through Pause/RESUME. The isolated browser receives718
actual native118 state rows, including five airborne samples, then neutral
rest. All three existing Taxi job records and the browser driver baseline stay
unchanged. The normalized movement gesture spans20.15 points in the155-point
hit region, against44-point stick travel. Its published move0.97 is the smoothed
locomotion ratio, not raw stick amplitude; this agrees with the existing
128/60 locomotion scaling. The retained screenshots occur after release, so
continuous gait and exact walking-threshold acceptance remain separate.
Physical controller response and retail timing remain unverified.

Core111 Release has separately been normally installed on the available
iPhone12Pro and joined the isolated browser/Simulator world through a private
LAN QA route. Genuine footage shows walk/run, release to idle, changed camera
view, crouch/stand, jump, bent landing and settled stance. Browser wire receives
the phone's movement/air/rest states. Another player's mission-Taxi entry
actually displays `VEHICLE ACCESS DENIED`; a normal phone Taxi assignment and
driver grant then succeed. That physical evidence validates the earlier111
product within its scene; it does not validate these112 changes on hardware.
Original resources, recordings and private test carriers remain local.

The paired userspace capture attempt failed before any touch events; its error
and partial recording remain. The separate native-tunnel recording completes.
Nominal video playback rate and host/RTP timestamps are not engine FPS or
input-processing latency. Visible Metal HUD readings are individual captured
observations, not a sustained benchmark. Matched classic-retail comparison,
physical controller testing and full gameplay parity remain open.
