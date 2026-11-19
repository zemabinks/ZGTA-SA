# Pedestrians, moving vehicle surfaces and trailer support

Core90 continues the core-gameplay priority. It separates three systems that
the native implementation previously combined or omitted: vehicle rigid-body
collision, pedestrian support triangles, and ownership of a pedestrian riding
a moving surface. This work establishes bounded browser compatibility; it does
not establish original retail San Andreas accuracy.

## Findings and implementation

The archived vehicle code adds a massless supporting sphere to five ordinary,
unheld trailer models:435,450,584,591,610. It removes that support when hauling,
recreates the hauled solver with zero initial velocity, then preserves that
solver's acquired momentum on release. Native promotion, hauling, parking,
demotion and despawn now follow those boundaries. Physical support is separate
from the trailer joint anchor and must never survive on a disposed body.

The archived terrain, fork plates and trailer support use Rapier's default
average friction combination. Chassis explicitly use minimum combination. A
generic native minimum default had silently applied chassis behavior to
terrain and new support shapes. Those three callers now explicitly select
average. The chassis rule remains explicit and separate. A private copied
wrapper with the old terrain rule fails the physical golden on the first
frame; that negative experiment does not modify released code or libraries.

The importer derives pedestrian support meshes from the owner's local DFF
collision data:201 models have meshes and11 do not. Base query vertices cross
the same Float32 boundary as the browser. Working vertices use the original
unrounded source point, apply the imported working transform, then return to
Float32. Material65 selects the moving vertex union. These triangles answer
pedestrian rays; they are not extra global rigid-body colliders.

`NativeMovingSupport` owns local foot coordinates, physical carry, platform
yaw, support acquisition, jumping release, free momentum, slip, blocked fits,
tilted surfaces, occupied-body replacement and post-step presentation. Scene
entries remain live objects so a retained ride reads updated driver and
presentation state. `NativeVehicleSupportScene` supplies the actual Rapier
queries, local meshes, working transforms, nearby collider filtering and live
vehicle body snapshots. Carry precedes foot motion; settle follows the motor;
presentation refreshes after the shared physical world advances and on display
frames with no fixed motor tick. The adapter keeps the visual entry pose
separate from the Float physical body pose. A local/remote transform regression
exposed both boundaries before acceptance.

The existing character task boundaries cancel support for swimming, flight,
climbing, death, vehicle entry, relocation and reset. Boat support suppresses
water entry. A support throw uses the original four knock directions, clears
crouch and seeds separately owned ground momentum. Platform yaw updates facing
and locomotion together without resetting gait. The browser-shaped `on` field
publishes the body-local attachment; remote drawing applies that offset to the
vehicle's native transform. Detachment sends an explicit null attachment.

## Evidence and regression scope

- `tests/vehicles/smoke_native_vehicle_support.py`: actual archived trailer lifecycle and
  body descriptors, plus1,200 original/native physical frames;4,782 checks.
- `tests/vehicles/smoke_native_vehicle_treads.py`:201 original meshes,306 original working
  poses and31,995 original rays;71,081 checks. Maximum measured ray difference
  is8.44e-15 in this fixture set.
- `tests/vehicles/smoke_native_moving_support.py`: the unchanged archived coordinator runs
  against controlled body snapshots, broad-phase responses and synthetic tread
  triangles. It covers3,876 ticks over six rates and275,453 checks, including
  separately extracted original knock direction and momentum clauses. These
  controlled responses are not a full-world physical playtest.
- `tests/vehicles/smoke_native_support_runtime.py`: actual native world, imported truck/boat
  surfaces, parked bodies, controller and extracted Renderer callbacks across
  five display rates;3,253 checks. It checks body-local drift, yaw, display/wire axes,
  remote transforms, jump, teleport and task cancellation. The recording knock
  animator is an explicit test double; animation playback has separate gates.
- `tests/vehicles/smoke_native_support_backend.py`: actual Swift URLSession guest handshake,
  attachment and detach through the unchanged independent backend, observed
  by a legacy WebSocket peer through its normal full-state messages.
- `tests/vehicles/smoke_native_working_assets.js`: actual isolated HTTP service, both native
  metadata overlays, authorization/origin boundaries, missing metadata,
  GET/HEAD and rejected methods. Original archive files remain unchanged.

Three deliberately sampled knock directions fall exactly on45/135-degree
classification thresholds. V8 and Darwin `atan2` round to adjacent bins within
2e-14 radians there. The regression records these adjacent-bin ambiguities
explicitly; all non-boundary directions must match exactly. This is a known
numerical difference, not an assertion of bitwise gameplay identity.

Final acceptance passes **94/94 gates**, captured sources unchanged, Release
Simulator and unsigned generic iPhone builds90, and all five Apple Swift/C/Rust
ABI links. Reports are retained separately under the owner's ignored
`local-only/acceptance-core-90` directory.

## Remaining acceptance work

Original retail comparisons, rendered browser/native moving-platform scenes,
real touch/controller handling, physical iPhone performance and WAN behavior
remain unverified. These tests do not establish arbitrary cargo/lifting
simulation, moving climbing handholds, every occupied vehicle or every
collision topology. Missing collision cells retain the native fail-closed
pause; carry is not advanced through unloaded terrain. This differs from
claiming that all original streaming edge cases are reproduced.

The supplied Definitive Edition IPA provides static resource evidence only.
No trusted running retail app has been observed in this work. The owner's
planned device installation can provide the later runtime reference.

## Host setup and source boundary

`host.py prepare --native` includes `tools/assets/prepare_native_vehicle_treads.js` after
native physics/coupling preparation. A standalone rerun is:

```sh
node tools/assets/prepare_native_vehicle_treads.js
```

The generated `local-only/selfhost/tread-catalog.json` is served at
`/game/native/vehicle-treads.json` behind the existing host/join/origin gates.
Malformed conversions retain the prior catalog. Native loading accepts only a
complete valid version1 catalog and retains the prior one on failure. Converted
meshes, original DFFs, archived code and private golden outputs remain local.
The public AGPL source contains the independent implementation, importer,
tests and audit conclusions.
