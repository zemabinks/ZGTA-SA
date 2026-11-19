# Core111 acceptance and regression disposition

Core111 retains each vehicle draw occurrence's identity and state instead of
looking its owner up again by model and position. This prevents coincident
same-model vehicles from sharing roll, wheel, steering, damage, lighting or
working-part state. Explicit local-foot ownership also prevents a remote nil
pose from borrowing local locomotion. The [identity audit](../vehicles/CORE_VEHICLE_IDENTITY_111.md)
describes the reproduced defects, authored tests and unchanged boundaries.

## Complete SDK builds and normal update

The complete Intel iPhone Simulator Debug build passes in579.626s. The complete
arm64 iPhone Release build passes in1290.136s using the actual public
`build_native.sh`, with effective2-thread compilation. All202 frozen App/build
inputs remain unchanged. The device product is unsigned and was not installed
on the unavailable phone. A normal update of the dedicated Simulator verifies
the executable, debug dylib, Metal library and preview dylib separately and
preserves four cache metadata files. There is no resource reset or cache seed.

Core110's separately frozen optimized Simulator build passes in1188.457s with
effective2-thread compilation. The public build script now bounds jobs and
Swift compiler threads to2 by default, allows explicit1–64 overrides, and
disables parallel whole-module compilation for Release. These are successful
builds, not measured FPS improvements.

The adopted dependency ledger remains immutable. During the actual111 device
build, the transport builder correctly regenerated its two owned SDK archives
because the adopted files lacked a current build report. All transport source
hashes match110; current archive hashes match the new successful build receipt.
The earlier Simulator Debug build used verified inherited archives, and the
later device Release build used regenerated archives. Their source/ABI is the
same; their artifact hashes differ. No converter wrote through an asset alias.

## Actual Simulator and browser acceptance

Tests use a dedicated iPhone12Pro Simulator, ordinary UI input and the existing
isolated Core108 server on port8808. The external XCTest runner has no App build
dependency and is bound to the frozen source and installed payload hashes.
The browser observer is passive. There is no pose/camera/state injection, forced
network ID, fabricated ACK or bypass of vehicle entry authority. Original
screenshots, videos and wire captures remain private.

The first passenger attempt fails in93.863s because two short approach gestures
leave the character8.346m from the Taxi, outside the existing8m entry range.
The failed case remains failed. Nominal UI hold duration does not establish
native input time or distance, so this alone is not a diagnosed movement bug.

A separate continuation from the actual current foot position passes in76.279s:
ordinary approach, seat1 passenger entry, three camera gestures, Exit and Jump.
The entire bounded command is covered by the retained wire buffer, despite its
older history being truncated. It contains185 seat1 rows,461 grounded foot rows
and4 airborne foot rows for native118/skin7. Browser1/skin2 remains unpaused in
the same original Taxi throughout3798 observed outgoing samples. Reviewed
captures show near-side wheels, the native passenger, the partially occluded
white-hat driver, normal foot restoration and the jump pose. The front-quarter
view alone does not conclusively reveal both faces simultaneously.

A separately created native-owned Taxi case passes in143.908s. Normal Guest
join and the Taxi job UI create a new vehicle ID. Normal Enter obtains driver
authority, followed by accelerator, brake, handbrake, two camera gestures,
Exit and Jump. Received vehicle snapshots move from y−1735.002 to−1731.570 at
x1484:3.432m horizontal displacement. The same new ID becomes parked with
health1000 and no driver. The browser retains its different original Taxi ID,
skin2 and health1000 throughout4793 unpaused outgoing samples; a small position
drift is retained rather than described as an invariant. A reviewed side view
shows both Taxis, their distinct white-hat and blue-jacket drivers, and wheels.
Exit restores native skin7 on foot beside the empty loaner. The normal job
remains active; the test does not silently cancel or rewrite it.

These scenes cover ordinary own/remote/parked rendering and passenger/foot
handoffs. The rare exact-coincident identity defect is proven by the authored
host reproduction, not claimed to have occurred in these live scenes. Brake
and handbrake actions are exercised, but their original-game force curves and
wheel rotation timing are not established by still captures.

## Initial broad regression and qualified followups

The frozen Core109 aggregate finishes with **149 PASS and17 FAIL across166
cases**, exit1. Its848 source hashes and202 App/build inputs remain unchanged.
That run is not relabeled green, and the complete111 aggregate is not claimed
to have run. The following are separate, versioned followups:

| Original failure | Separate result and boundary |
| --- | --- |
| Health/network600s compile timeout | Unchanged109 command passes179.12s under the same budget, including actual HTTP/WebSocket. |
| Wrecked hull | Genuine accepted-entry reproduction confirms a product defect;110 terminal authority fix passes303 Node checks/17 scenarios and7 Swift/15 backend checks. |
| Water/lost vehicle | Correct entry/reentry plus110 terminal fix passes11 Swift/21 backend checks; the first corrected600s compile timeout remains recorded. |
| Bike-exit compile timeout | Unchanged109 command passes502 checks in447.07s. |
| Exit runtime missing camera helper |110 carrier includes actual cameraRay and real Rapier dependencies;336 checks pass. |
| Exit-heading fixture bypassed entry |110 carrier performs the real entry ACK;38 Swift/109 backend checks pass. |
| Melee fixture missing transport type |110 uses an explicit fail-fast unused HTTP boundary;24 catalog/inventory/dispatch checks pass. This does not test HTTP. |
| SA-MP artwork missing pinned headers | Restored exact reference headers;1622 authored plus16 HTTP checks pass. |
| SA-MP objects missing pinned headers | Restored exact reference headers;2086 checks pass, including108 motion samples over6 schedules. |
| SA-MP combat missing core.hpp | Restored pinned header;5259 checks and320 aim/320 bullet samples pass. |
| Skin namespace missing peds metadata/helpers | Restored owner fixture plus111 composition repair;1148 Python/1067 Swift checks pass. |
| Skin-network missing metadata/entry |111 fixture registers two authored vehicles and obtains8 native/8 browser entry grants;187 checks across32 original identity cases pass. See false-positive correction below. |
| Vehicle paint missing oracle/model closure | Minimal verified fixture restoration;259327 checks,2568 appearance cases and68650 rig draws pass. Actual desktop Metal24 legacy comparisons have max channel error0; no phone/retail/FPS claim. |
| Stock access missing catalog/COL/server dependency | Minimal verified restoration plus111 actual server-file dependency;44 cookie/123 loader/109 HTTP-server checks,12 owner resources and iOS15 arm64 typecheck pass. |
| Stock runtime missing models | Minimal verified restoration; actual Renderer/HTTP/desktop Metal/Rapier case passes141.74s. |
| Game files missing RawLease dependency |111 carrier adds actual source;67 coordinator/store plus23 ISO checks pass. |
| Weapon-state missing transport type |111 adds an explicit fail-fast unused HTTP boundary; actual inventory/arsenal/prediction compile passes110.109s and execution1.664s, under the same600s budget. No HTTP coverage is inferred. |

The110 skin-network wrapper's exit0 was a **false positive**: its Swift child
failed and its wire report said FAIL. That result is invalidated. The111 wrapper
requires child exit0, no signal, the completed PASS marker, a passing wire report
and actual native/browser entry counts. All original identity assertions remain.
Eleven portable negative checks include a real signaled child/null status,
nonzero exit, missing marker, failed report and missing entry counts. This gate
is registered in the aggregate and free source CI.

A read-only audit covers15 aggregate native-child Node wrappers plus one related
helper. Only skin-network coerced null status to0 and ignored its failed report.
None of the149 original PASS logs contains a Swift fatal/precondition/signal
marker. That audit is not proof that every historical assertion is complete.

The fixture closure contains only653 verified minimal files, not a copied game
archive. Older dependencies are read-only. One historical shared browser module
has a different whole-file hash from its older ledger; the resolver actually
used by the namespace fixture matches the retained extracted reference exactly.
That narrower equivalence is recorded explicitly; whole-archive immutability is
not claimed. Original resources and private evidence remain outside GitHub.

## Remaining acceptance

The [core parity checklist](../../development/CORE_GAMEPLAY_PARITY.md) still contains substantial
unverified and approximate mechanics. Physical iPhone rendering, controller
input, matched original1.0US gameplay timing, complete standalone ISO conversion,
audible runtime radio, wider vehicle/animation/world coverage, and full live
SA-MP/DL/open.mp/original-site join-and-play acceptance remain open. The phone
was not operated after its owner reported it unavailable. This checkpoint does
not establish1:1 gameplay or completion of the full port.
