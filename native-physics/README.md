# Native Rapier bridge

This C library links the native Rust engine used by the archived browser's
Rapier package. `SwiftRapierWorld` owns real dynamic rigid bodies, engine
collision response and native shape raycasts. Vehicle handling supplies its
custom velocity changes before a fixed `1/60` engine step.

The archived WASM is byte-identical to official
`@dimforge/rapier3d-compat` **0.20.0**. That package's npm git commit is
[`3e12c2679cb1940a876bde93af9cec0cf2f57944`](https://github.com/dimforge/rapier/tree/3e12c2679cb1940a876bde93af9cec0cf2f57944),
whose native workspace version is **0.35.1**. The Cargo dependency pins that
exact commit. JS package version and Rust engine version are different.
Verification details and original package/WASM digests remain in ignored
`local-only/reverse-engineering/vehicle-physics/rapier-package-provenance.json`.

## Build

On a fresh Mac, install full Xcode with its iOS/Simulator SDKs and Metal Toolchain,
then install XcodeGen (`brew install xcodegen`). Run:

```sh
zsh native-physics/setup.sh
zsh native-physics/setup.sh --check
```

The setup downloads official Rust1.100.0 and all five Apple target standard
libraries into `local-only/toolchains/`. It does not edit shell profiles, global
Rust, Xcode settings or an existing project-local toolchain. An already matching
local compiler is reused. The check also compiles a minimal iPhone Metal kernel,
including the downloaded Xcode26 Metal component when `xcrun` resolves a stub.
See [fresh-host instructions](../NATIVE_BUILD.md). Browser-only hosting does not
require Rust or Xcode.

```sh
zsh native-physics/build.sh all
zsh native-physics/test.sh
zsh native-physics/test_character.sh
zsh native-physics/test_vehicle.sh
zsh native-physics/test_contacts.sh
zsh native-physics/test_rotation.sh
zsh native-physics/test_boundaries.sh
zsh native-physics/test_apple_abi.sh
```

Static libraries and executable tests stay under ignored
`local-only/native-physics/`. `ios-device` contains ARM64, `ios-simulator`
contains ARM64 and Intel, and `macos` contains ARM64 and Intel.
Builds fetch missing Cargo dependencies by default; use `ZGTA_NATIVE_OFFLINE=1`
only after the local cache exists. `build_parallel.sh [1..4]` builds independent
targets concurrently and falls back to regular copies on non-APFS volumes.
Source stamps make the gameplay launcher rebuild stale libraries after a pull.
Most reference fixture tests also require the owner's local archived client;
the engine build and toolchain preflight need no game assets.

Xcode integration uses the `ZGTARapier` Clang module in `include/`, adds its
path to Swift's import search path, links `libzgtasa_native_physics.a` from the
appropriate platform directory, and links the system Security and
CoreFoundation frameworks. Do not add the Rust cache or generated libraries
to GitHub.

## Boundary

The C ABI uses primitive values and borrowed arrays. A world belongs to one
calling thread. Body state arrays contain position XYZ, quaternion XYZW,
linear velocity XYZ, then angular velocity XYZ. Custom mass properties contain
mass, local centre of mass XYZ, and principal inertia XYZ. Colliders have zero
density so they preserve those handling mass properties. Vehicle primitives use
minimum friction; SCL2 world meshes preserve the original Average friction rule.
Restitution uses default Average. Explicit friction-combine setters expose all
four original rules. Dynamic bodies use CCD and remain awake.

Effective mass follows JS timing: newly created bodies have mass0 until the
first physics step, and `setMass` leaves the old mass effective until the next
step. `recomputeMassProperties` is the separate explicit JS operation for an
immediate update. `mass(of:)` exposes the actual engine value. The original
11-stage creation/setter/impulse trace matches exactly; all480 Average/Min
synthetic contact frames also match the source engine exactly. Calibration
shapes are explicit and are not claimed to be publisher vehicle geometry.

Coordinates pass through unchanged. The original solver uses Y up;
`SwiftRapierWorld.decodeSCL2` converts the locally archived GTA Z-up mesh into
that coordinate system and preserves triangle surface/material annotations.
Raycasts exclude an entire own body and any caller-supplied collider IDs.
Native triangle meshes retain Rapier's per-shape acceleration structures.

The C and Swift smoke tests exercise dynamic floor contacts, fast CCD impact,
custom mass/inertia impulses, shape queries and exclusions, mesh metadata,
and a ray against an actual locally archived city collision cell. Full vehicle
handling comparisons use the separate archived JS solver fixtures.

The character adapter exposes the original capsule contact/intersection queries,
point projection, ball shape casts and Rapier kinematic character controller.
Explicit collider/body exclusion sets and optional interaction groups remain
native engine filters. A query-only BVH includes current enabled collider AABBs
without advancing the solver or consuming its change tracking. The disabled
probe capsule remains available as the character controller's query shape.
`enableArchivedStepping()` reproduces the public world factory's one-ULP
prediction-distance increment; it is separate from default engine stepping so
plain official-WASM golden fixtures can be compared independently.

The source commit contains no historical Cargo.lock. Embedded panic paths in
the archived WASM identify glam 0.33.3, glamx 0.3.0 and smallvec 1.15.2; the
lockfile pins those observed versions alongside the other recovered engine
dependencies. The original compat build omits SIMD. Native builds therefore
use glam's scalar-math feature by default, matching the original arithmetic
path without enabling unrelated Rapier determinism features.

`test_vehicle.sh` replays the first four recorded browser car scenarios twice:
recorded requested velocities through native Rapier, then the Swift handling
solver with native wheel rays and integration. It rejects over 1 cm position
error, 0.1 m/s velocity error, or 0.005 quaternion-component error against the
original f32 engine trace. The complete-path maximum position error is below 4.45e-16 m on the
Intel Mac scalar baseline, with zero suspension-drop final error. Collider
insertion order matches the original fixture because it controls contact-pair
ordering. The JSON numeric report remains under ignored local-only. These are
synthetic calibration-box scenarios; production vehicle shapes are extracted
separately from the original chassis factory.

## Contact forces

Chassis colliders opt in through `setContactForceEvents`. The bridge calls the
engine's `ContactForceEvent::from_contact_pair`, preserving the summed force,
summed force magnitudes, strongest normal force and its direction. Both
collider IDs and parent body IDs are captured at emission time, so removing a
body does not change an already emitted event. The queue auto-clears at each
step, matching the browser's `EventQueue(true)`; handlers should drain it inside
each fixed step. Enabling events leaves the engine's default force threshold
unchanged. Damage scaling and material/piece rules belong to the translated
game handler, rather than the physics bridge.

Collider information retains world rotation and sphere/cuboid/capsule
dimensions for the original support-extent impact-point calculation. Shape
piece IDs can be registered from locally extracted chassis metadata.
`test_contacts.sh` executes the archived engine offline to obtain contact
measurements, then compares native force fields and tests queue ownership,
flag toggles, auto-clear and collider metadata. All generated traces remain in
ignored local-only directories.

`test_character.sh` runs the complete native motor and real engine query path
against all 2,100 recorded browser frames: wall movement, ceiling jumps,
stairs, 25-degree and slippery slopes, falling, vertical override and contact
with a dynamic vehicle box. The dynamic fixture exports the original engine's
mass, COM and principal inertia after constructing its default-density collider.
Native positions match within 1.05e-17 m, rising and grounded/propped/barrier
states match exactly, and dynamic press speed differs by at most 3.18e-10 m/s.

Binding details matter: character settings default to no ground snap as the
JS constructor specifies, rather than the native Rust controller's different
snap default. Ray directions and quaternion components pass through unchanged
after Float conversion, matching the original JS raw bindings. Ray/cast time of
impact is a parameter along that supplied direction; it is a metric distance
when the direction is unit length. The bridge validates finite nonzero inputs
without inserting an extra normalization step. Explicit `setBrowserRotation`
and `setBrowserNextKinematicRotation` are separate: they reproduce the JS
setter's scalar Float normalization, while `setBodyState` continues to preserve
raw recorded state. `test_rotation.sh` compares both setter results bit for bit
against the original WASM, including a zero quaternion being ignored.

`test_apple_abi.sh` links an immutable Swift bridge snapshot with the actual
static libraries for iPhone ARM64, Simulator ARM64/Intel and Mac ARM64/Intel.
Each compiler invocation selects its platform SDK explicitly. This checks the
full Swift/C/Rust symbol boundary independently of ongoing UIKit app edits;
it does not substitute for device runtime or complete-app tests.

The controlled aircraft/boat comparison covers 15,000 original frames across
20 scenes; scalar native trajectories match within 2.1e-17 m. Bike integration
covers 8,280 frames across 15 scenes with maximum position error 2.09e-17 m.
These measurements validate the selected native math path; platform machine
code and the complete untested state space are separate claims.

`prepare_native_collision_fallback.js i148` reconstructs the sole missing
publisher collision cell from the archived WRL2 loader, spatial range builder
and actual render-mesh collision function. The generated file is explicitly
labeled as reconstructed, with asset/function hashes and the original nine
partitions. `test_fallback.sh` checks its 1,431 triangles against 81 actual
archived-engine rays; all 52 floor hits and all misses, distances and normals
match exactly. The generated game geometry and provenance stay local-only.

Streamed SCL2 meshes preserve raw face annotations separately from normalized
collider-wide query classes. `setColliderQueryMetadata` tags the classes used
by character and wheel queries, while ray hits retain raw material values for
impact effects. The manager preserves the original surface/material grouping,
first-appearance order and vertex remapping instead of assigning an entire
mixed-material cell its first triangle's classification.
