# Temporary on-foot look-behind

`NativeGameCamera.followFoot(_:delta:look:)` now accepts `"behind"` while held.
It first advances the ordinary camera, then returns a temporary reverse view.
It does not change persistent yaw/pitch, actor facing, chase anchors, aim/scope
clocks, the independent aim origin, or the source used by later shake effects.
Release immediately uses the uninterrupted ordinary camera history.

## Evidence and its limits

The [official PS3 manual](https://media.rockstargames.com/rockstargames-newsite/img/manuals/en_us/GTA_SA_PS3_MANUAL_ENG.pdf)
lists on-foot R3 look-behind. The publisher-supplied
[PC manual on Steam](https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/12120/manuals/GTASA_PC_MANUAL_FINAL.pdf)
has an indexed foot-controls table mapping it to Number Pad 1 / middle mouse.
The PC PDF open failed in this investigation; that binding was available in
the primary document's search index. These manuals establish the control;
they do not establish the camera equations or prove retail runtime behavior.

The camera behavior comes from the archived browser's **render-time wrapper**,
separate from its ordinary on-foot follow function. The wrapper saves camera
position/quaternion before drawing and restores them afterwards.

| Archived source | Location / identity |
| --- | --- |
| Chunk | `9737.c81ad6ccfd85b371.js` |
| Full chunk SHA-256 | `5a8a7fa71560badc0d9353e88deaa164323544d47a5d4c20e6a92d04c1c78c36` |
| Wrapper UTF-8 byte range, end exclusive | `2370688–2371065` |
| Wrapper UTF-16 range, end exclusive | `2368384–2368761` |
| Wrapper SHA-256 | `19e9a0ce29874074a97f9248f28ed60b00d492cae1a0c4ae7fefc49170b8eb3c` |
| Saved-camera restoration | UTF-16 offset `2376153` |
| Bounded REA static evidence | `ev_3090c64d57fcb1e2c6dee40e49093b5377a90b4e416bea98c2559d6546d7225b` |
| REA controlled Node replay, exit 0 | `ev_35e209fc5f79a8fdbbe5b2c7d52511a5c99d443d683b929d9dcb4307aec33cba` |

REA parsed only the selected 377-byte wrapper as inert text. Its semantic
coverage remains unknown with 39 unresolved relationships. Execution evidence
comes from the controlled replay, which runs that actual wrapper with the
shipped vector class and the existing archived follow-camera reference.
Extracted bytes, generated fixtures and measurements remain in ignored
`local-only/research/foot-look-behind`.

The successful REA process capture covers the Node reference replay. The native
comparison completed through the ordinary Swift runner. An earlier combined
capture hit its idle deadline during Swift compilation and returned
`cleanup_incomplete` because macOS withheld process ownership tokens; it is not
treated as complete runtime Evidence. No unverified process was killed manually.

## Supported behavior

- The focus is current player feet plus 1.4 metres, independent of the ordinary
  follow camera's smoothed ledge anchor.
- The temporary view uses the opposite horizontal side of that focus. It keeps
  the ordinary camera's height and field of view, and looks toward the focus.
- It traces from the focus in that horizontal direction. The archived solid
  collision rule subtracts 0.3 metres and retains a 0.6-metre minimum reach.
- Aim **input** suppresses the override. Crouch, ledge and parachute do not add
  exclusions; their ordinary camera updates continue. A scope remains governed
  by aim input and its ordinary visibility; the wrapper does not force it off.
- Horizontal separation at or below 0.05 metres keeps the ordinary frame.
- `"left"`, `"right"`, unknown values and `nil` leave on-foot follow unchanged.

The native streaming-boundary callback may shorten the solid-wall minimum to
avoid crossing unavailable geometry. This is the existing native safety policy,
not a claim about the browser or retail engine. Invalid reverse-trace distances
are rejected defensively. If the shortened source and focus collapse to the
same Float point, the already-computed ordinary frame is retained. The recorded
case was `[1480,-1738,14.4]` at pitch `0.057174`, with unavailable front reach0.
The renderer already guards zero/vertical directions; retaining the ordinary
frame avoids selecting its generic direction fallback. There is no added
smoothing or persistent pi offset.

## Verification

Run:

```sh
python3 tests/ui/smoke_native_camera.py
python3 tests/movement/smoke_native_foot_look_behind.py
```

The ordinary camera gate preserves **8,334 comparisons**. The focused replay
passes **2,016 frames in 84 scenarios and 32,083 checks**, at 30/60/120 Hz, with
headings crossing both pi and full-turn boundaries. Maximum position/query
difference is **1.2572855e-8 metres**. Scenarios cover press/release, crouch,
aim/scope changes, hanging ledges and parachuting. Paired uninterrupted cameras
prove equal release frames and aim history. Additional checks cover solid walls,
unavailable cells, malformed callback values and subsequent vehicle shake.

`ZGTASA_CAMERA_REPORT_DIR` can isolate a concurrent evidence run. Generated
fixture values and reports are not repository test data.

## Renderer contract and remaining gaps

Pass `look: cameraLookDirection` into the existing `followFoot` call. Use its
returned frame for rendering. Continue using `gameCamera.heading/pitch` for
ordinary on-foot input; do not copy the temporary frame's reverse orientation
back into those values. Clear the caller's held look input on focus loss as
before. The helper stores no pending look-behind input.

Renderer/input wiring and device UI acceptance belong to their existing owners.
The synthetic world-query callbacks verify the wrapper contract, not every
world collision mesh. Retail executable camera behavior, platform-specific
smoothing and retail visual feel have not been observed or claimed.
