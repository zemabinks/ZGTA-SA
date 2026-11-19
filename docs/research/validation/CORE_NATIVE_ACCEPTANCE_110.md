# Core110 acceptance and limits

Core110 preserves the final wrecked vehicle state after fatal health releases
driver authority, corrects vehicle transparency ordering, and renders supported
ID-less drivers using their appearance role. The implementation and focused
positive/negative controls are described in
[terminal completion](../vehicles/CORE_TERMINAL_VEHICLE_110.md) and
[vehicle rendering](../vehicles/CORE_VEHICLE_ALPHA_110.md).

## Complete SDK products

Both complete Debug builds pass against the same202 frozen build inputs:
Intel iPhone Simulator in1010.814s and arm64 iPhone in742.367s. The device
product is unsigned and was not installed on the unavailable phone. A normal
update of the dedicated QA Simulator preserves all four cache metadata files
and verifies the executable, actual gameplay debug dylib, Metal library and
preview library separately. The executable stub alone remains unchanged and
cannot identify the updated gameplay implementation.

## Actual shared-car scene

The finalized external XCTest passes one case with zero failures in117.094s;
the complete command takes167.325s. It uses normal menu/server fields and Guest
join, one bounded analog approach, ordinary passenger entry, three camera
gestures, Exit and Jump. No player pose, camera, account, resource-store or
network-state injection is used.

The browser witness identifies driver1/skin2 in the same registered Taxi, and
native118/skin7 first on foot, then in seat1, then back on foot. The retained
interval contains195 passenger-row observations,220 foot-row observations and
two airborne foot observations. These are packet observations, not FPS or a
complete reliable trajectory measurement. The rolling witness is marked
truncated, although its retained beginning precedes this command.

Root-reviewed landscape captures establish:

- Both distinct front occupants simultaneously through the windshield: the
  native dark-haired, blue-jacket passenger and white-hat driver.
- Two near-side wheels beneath the opaque body in a separate side view.
- The native actor beside the car after Exit, while the driver remains visible
  through its window and normal foot controls are restored.
- Visible Jump motion and the same-ID driver retained in the final wire state.

The live scene uses the existing isolated Core108 backend on8808. Core110's
terminal backend change is tested separately with actual native NMP and
ephemeral HTTP/WebSocket fixtures; these complementary results are not labeled
as a single end-to-end Core110 backend scene. The car is stationary here;
dynamic suspension, exact contact, moving-camera continuity, other vehicle
models and physical-iPhone performance still require their own acceptance.
Source resources, recordings, screenshots and raw wire remain private.

The first110 carrier was never executed: review caught a premature teardown
`hasSucceeded` read. A separate110b carrier reports sequence completion pending
the finalized xcresult. Its48 metadata/source checks also prove that all UI
gestures and assertions remain unchanged. An oversized setup witness was
refused before App actions; the original raw evidence was retained and a
bounded read-only projection was used. Initial result-export failures were
retained before sequential host-authorized export obtained the final Passed
result.

## Regression disposition

Thirteen independent source/hosting/authority checks pass, including the new
303-check,17-scenario terminal regression, which also runs in free source CI.
The new pure rendering/appearance regressions are registered in the core gate;
actual desktop Metal execution remains an explicit separate check.

The original frozen Core109 aggregate continues unchanged. At its interim
checkpoint77 of84 completed cases passed, with seven original failures retained.
Separate dispositions are deliberately recorded rather than relabeling that
run green:

| Original failure | Separate qualified result |
| --- | --- |
| Health compile deadline | Unchanged command passes179.12s at the same600s bound, including actual HTTP/WS. |
| Wreck hull | Genuine accepted entry reproduces the production defect; Core110 terminal policy passes303 portable checks and the actual native7+15-check replay. |
| Water parked hull | Corrected actual entry/reentry and Core110 terminal policy pass11+21 native/backend checks; an initial corrected compile timeout remains retained. |
| Bike-exit compile deadline | Unchanged Core109 rerun passes502 checks in447.07s at the same600s bound. |
| Exit-runtime missing camera dependency | Carrier includes the actual camera query and real collision dependencies; original336 runtime assertions pass421.04s. |
| Exit-heading bypassed entry | Genuine acknowledged entry precedes each original case;38 Swift+109 backend checks pass251.98s. |
| Pure-melee missing transport type | A fail-fast, unused HTTP boundary permits actual catalog/inventory/dispatch code to compile; original24 assertions pass74.94s. It cannot silently satisfy a network request. |

All202 App inputs remain frozen across SDK and live UI acceptance. This
milestone fixes demonstrated defects; original-game feel, complete offline
resource conversion, audible hardware radio, all server destinations and every
remaining row in [the parity checklist](../../development/CORE_GAMEPLAY_PARITY.md) remain separate
work. No1:1 accuracy claim is made.
