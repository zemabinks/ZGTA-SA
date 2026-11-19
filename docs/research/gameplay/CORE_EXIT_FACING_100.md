# First exit packet facing — Core100

The first pedestrian packet after a vehicle exit used the parked chassis yaw.
A door animation can leave the actor facing another direction, and the resumed
camera can have a third angle. The next ordinary movement packet already used
the actor's facing, so a remote client could receive an inconsistent initial
pose at the transition.

`NativeMultiplayerClient.sendExit` now accepts a separate pedestrian heading.
GameVC samples it from `renderer.direction` after the exit succeeds. Its
pre-exit body heading, pitch and roll remain the parked-vehicle snapshot. The
actor packet uses the final actor facing, independent of the camera orbit.
Existing callers can omit the new argument; a non-finite optional angle falls
back to the existing finite body angle rather than entering JSON as NaN/Inf.
There is no new wire field or server capability requirement.

The extracted Renderer/GameVC runtime gate now uses the production
`direction` property. It exercises body yaw 0.7, completed actor facing 1.9 and
resumed camera yaw −2.4 together, checking that the packet retains the correct
roles. This closes a blind spot in its earlier simplified property carrier.

`tests/vehicles/smoke_native_exit_heading_backend.py` runs the actual native multiplayer
client against the actual independent server and a separate browser-protocol
observer. Nine cases include distinct actor/body angles, crossing ±π, omitted
heading and non-finite optional values. It checks the first foot packet, the
parked body, the first observer row and unchanged health/armour. The focused
pass has 20 native checks and 100 server/observer checks. It does not send a
follow-up walking update to repair the first exit row.

Final acceptance passes110/110 regression gates with source hashes unchanged,
plus Release100 Simulator and generic unsigned iPhone builds. A real UIKit/
Metal Simulator test joins the independent server as a guest, enters and exits
a seeded taxi, then walks5.33m. Its first pedestrian heading is1.571862rad
while the parked car retains−0.000428rad; nine subsequent idle samples retain
the pedestrian heading. Health stays100 throughout.

The same test equips a jetpack through the actual menu, takes off, turns and
lands. The last airborne and first grounded network samples both face
2.599369rad, with a251ms sample gap and0rad heading difference. Six full-screen
captures include the on-foot exit, hover and landing scenes. This is one
controlled self-host scenario; sampled packets cannot establish every rendered
frame's continuity. Test results, traces and captures stay owner-local.

This correction does not establish retail feel, full exit-animation parity,
physical-device performance, WAN performance or joining the original browser/
SA-MP/open.mp services. Those remain separate requirements in the gameplay
checklist and server compatibility assessment.
