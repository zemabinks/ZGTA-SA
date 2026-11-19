# Native camera and input audit

This checkpoint fixes native input/lifecycle defects. It does not establish a
retail GTA San Andreas camera reconstruction. The existing public-client camera
profiles remain identifiable and retain their separate archived-JavaScript replay.
No gta-reversed implementation was copied.

## Evidence and changes

| Finding | Evidence | Change / boundary |
| --- | --- | --- |
| Look response | `NativeGameCamera.lookAnalog` already integrates elapsed time. Pointer/touch deltas are displacements and must not be multiplied by elapsed time again. | Preserved those equations. Reject nonfinite/negative analog input. Test 30/60/120Hz held look and one-time vehicle delta consumption across camera substeps. |
| Low-FPS slowdown | VC previously replaced every interval above 50ms with 50ms. A 15Hz frame therefore advanced only 75% of elapsed time before any physics clamps. | Separate monotonic frame clock retains ordinary elapsed time, slices movement at at most 1/60s, and explicitly rejects gaps above 0.5s. Inactive time is not caught up. This is a native consistency policy; it is not a claim about the retail timer's clipping behavior. |
| Old input survives UI transitions | Overlay methods cleared only selected booleans; sticks/gas/brake/nozzles could remain held. Controller disconnect only updated a label. | One reset path covers every presentation, app inactivity, touch/key cancellation, controller changes and vehicle-control changes. Controllers require neutral buttons, triggers and axes before rearming. A panel opened during controller polling suppresses the same frame's remaining commands. |
| Emergency horn cancellation | Releasing a pending emergency horn within 250ms is interpreted as a siren toggle. Cancellation is different from a deliberate release. | VC uses the separate `cancelHornInput` hook; siren selection is preserved by the horn helper. |
| Floating stick geometry | Fixed 110pt ring and 42pt knob could extend outside a hit zone when the initial touch occurred near its edge. | Keep existing safe-area positions/hit-zone sizes. Constrain visual origin using ring/knob travel bounds, while movement remains relative to the actual initial touch. Track the original touch and ignore old movement after reset. |
| Screenshot's tall black pill | Screenshot75 shows an approximately 37×126-display-point black feature at the landscape iPhone15Pro camera edge. The source stick is circular and hidden when untouched. | Strongly consistent with the device's Dynamic Island/camera cutout, not evidence that the stick is stretched. No arbitrary layout redesign was made from that screenshot. |
| Stale camera history | Foot follow retains aim/chase/ledge anchors, and the public vehicle reset does not clear every pending manual hold/delta. | New explicit `resetFoot`, `resumeFoot`, `beginVehicle` lifecycle methods. Resume-foot chooses the nearest equivalent view angle. `cancelLookInput` discards pending input without changing view/zoom. The original public-helper `resetVehicle` remains available for its prior behavior. |
| Fire timing has two owners | VC previously consumed ammo and restarted a firing clip on a wall-clock interval while native animation already reports muzzle events. Touch-up also requested another attack after touch-down. | Native-capable weapons request once on trigger edge; animation events own synchronous predicted ammo consumption, readiness, HUD and network/audio emission. Fallback remains separate. Per-hand muzzle geometry and existing player hit approximation are not claimed accurate. |

## Primary published references

Rockstar's mobile announcement describes dual analog movement/camera control,
MFi controller support and configurable touch schemes. It does not publish
camera acceleration, follow equations or controller deadzone constants:
[Rockstar iOS announcement](https://www.rockstargames.com/newswire/article/9k124883835743/san-andreas-now-available-for-ios.html).

Rockstar support documents moving touch controls and restoring defaults through
Redefine Controls:
[On-screen control positioning](https://support.rockstargames.com/articles/7oydRj1ymx0wPSC4eGG8S7/how-to-reposition-on-screen-button-controls-for-gta-san-andreas-mobile).
These native changes preserve positions; a complete configurable layout editor
is outside this checkpoint.

The public gta-reversed timer reconstruction describes a normalized 50Hz game
step and a clipped physics step, separate from its real-time clock. This is a
static reconstruction reference, not a retail-runtime observation or permission
to copy its code:
[Timer.h](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Timer.h),
[Timer.cpp](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Timer.cpp).

## Verification and limits

`python3 tests/ui/smoke_native_controls.py` exercises the actual Swift helpers at
15/20/30/60/90/120/144Hz, suspension/backwards clocks, controller release-to-rearm,
edge touches, touch cancellation, diagonal stick bounds, look integration,
shortest-angle vehicle exit and fresh-vehicle history. Owner-provided native
camera metadata is required. `python3 tests/ui/smoke_native_camera.py` separately checks
the preserved public-client camera behavior against the archived JavaScript.

`python3 tests/combat/smoke_native_shot_delivery.py` verifies real inventory consumption and
synchronous readiness/emission ordering for final rounds, twin/catch-up rounds,
weapon switches, reload and fallback duplicate suppression.

Full Simulator/device builds and UI QA follow a coherent source freeze. Host
helper tests do not prove physical iPhone touch/controller behavior, retail
camera equality, on-device performance, or complete combat parity. Camera
substeps using a final display-frame body position also do not replace true
physics/render interpolation.

## Close-camera acceptance, builds77–79

Live city testing found that a low ceiling could place the camera outside the
physical near-plane guard while the local body filled the screen. Build78's
trial transparency exposed unsorted internal skeletal triangles in live UI and
was rejected despite passing numerical visibility tests. Build79 uses a separate
1m presentation clearance, spatial hysteresis and binary visibility. Worn
attachments use the same visibility result; hidden pack audio/effects remain
updated. Ordinary distant views remain opaque. This is a native visibility
policy pending original-runtime measurement, not retail camera parity.

The focused gate checks6,630 cases including15/20/30/60/120/144Hz, all orbit
angles, physical clipping, presentation clearance and reset/reappearance.
Live final79 UI acceptance remains separate from that gate.
