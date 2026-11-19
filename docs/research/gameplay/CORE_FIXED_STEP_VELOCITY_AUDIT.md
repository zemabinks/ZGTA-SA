# Fixed-step velocity and cancelled intent

Core84 fixes two native integration defects. These checks establish native
cadence consistency and retain the separate archived-browser reference; they
do not establish retail GTA San Andreas runtime parity.

## Velocity ownership

The native character motor advances at 60 physical ticks per second. Previously,
`NativeWorldRenderer.move` recomputed `lastFootVelocity` from the current display
slice's position change divided by that display slice's duration. At 120 FPS,
alternate display slices contain no motor tick. This published zero velocity
followed by roughly double velocity, despite constant physical movement.

That value is consequential: the renderer uses it for outgoing on-foot velocity,
parachute dive inheritance and water-entry inheritance. This was not a camera
smoothing issue or another version of the previously fixed landing half-turn.

The retained before/after probe uses the real native motor, Rapier world,
personal-flight controller and extracted renderer velocity block. A controlled
2 m/s horizontal fall produces:

| Display cadence | Core83 observed velocity | Parachute inherited X | Core84 inherited X |
| --- | --- | --- | --- |
| 30 Hz | 1.999998–2.000005 m/s | 2.000005 m/s | 2.000005 m/s |
| 60 Hz | 1.999998–2.000005 m/s | 2.000005 m/s | 2.000005 m/s |
| 120 Hz | 0–4.000010 m/s | 0 m/s | 2.000005 m/s |

The dive occurs at the same physical tick, 32, in every case. The old 120-Hz
path has 30 zero samples before entry; the corrected path has none. Measurements
use a controlled origin. City-coordinate tests separately retain the existing
Float position quantization rather than filtering it away.

`NativeCharacterController.stepVelocity` now records the last committed tick in
Rapier axes and world units per second. It measures the same published Float
feet boundary used by the prior 60-Hz renderer calculation. No-tick display
frames retain that physical snapshot. The renderer samples it before each
fixed-step task handoff and after the controller update. Reset/ownership changes
clear it. The non-native-character fallback retains its existing calculation.

No forces, body positions, physics clock, axis signs, movement speed constants,
render interpolation or ordinary camera equations were changed.

## Cancelled half-tick input

When animation metadata is unavailable, fallback jump intent can enter the
character coordinator before its next physical tick. The old renderer cleared
its outer `pendingNativeJump`, but the coordinator still held a queued jump.
The real motor probe shows a cancelled half-tick request becoming a 6.07 m/s
launch on the next half-tick, moving the feet upward by 0.1011667 m.

`NativeCharacterController.cancelPendingInput()` clears only queued displacement
and jump intent. The existing renderer cancellation path invokes it. It retains
the accumulator phase, committed velocity, grounded/airborne state, physical
momentum and animation-owned root. Existing flight input cancellation remains
separate from stopping the physical flight task. A subsequent fresh jump works.
An already accepted animation task is not reclassified as an unconsumed command.

## Browser evidence and timing boundary

The selected original public archive's module39943 `ts` uses a 1/60 accumulator
with a six-tick cap. Executing that exact function for two seconds produces
120 ticks at 30/60/120-Hz display cadence; a 0.25-second input is capped to six
ticks. The main19737 wrapper clamps its display delta to 0.1 seconds, stores
the foot task's `tY` velocity inside its fixed callback, passes that value into
parachute/water transitions, and interpolates previous/current walking poses
for drawing. Those are browser observations, not retail executable behavior.

The existing native clock deliberately preserves ordinary intervals through
0.5 seconds and rejects suspension/discontinuity time. Its policy remains
unchanged. Native background handlers reset clocks and controls. Visible menu
overlays suppress input while the multiplayer world can continue simulating.
These source boundaries and existing controls tests were checked; this pass
does not claim a new physical-device or UIKit pause observation.

Bounded REA static analysis of the selected 39943/54205 modules is retained as
`ev_2315c1db53a39b690176165ecd847a866c76fb3983c77a3fe0faa24ccc653389`.
It parsed the selected source without executing bootstrap code. Dynamic semantic
relationships remain partial/unknown; direct controlled replays supply the
clock and state evidence. No original snippets or assets are included here.
The direct clock replay is retained as
`ev_1e2b9825bdcd9c60fc688288df4b4420522a9fbc78c4657e26d565d44a2dbbea`;
it exits successfully with verified process cleanup.

## Reproduction and remaining limits

Run:

```sh
python3 tests/movement/smoke_native_fixed_velocity.py
python3 tests/movement/smoke_native_heading_transitions.py
python3 tests/movement/smoke_native_climb_runtime.py
python3 tests/ui/smoke_native_controls.py
```

The focused runner extracts the current renderer water/flight/cancellation
methods and velocity boundaries, links the actual character controller and
native Rapier, and loads the owner's existing CLP animation library. It compares
fixed body/task traces and original animation clips, clocks and weights across
30/60/120-Hz and uneven display schedules. Controlled scenes cover water-edge
entry, parachute opening, native-floor jetpack touchdown, wall contact, streaming
pauses, no-tick frames, reset/ownership changes and cancelled/fresh jump intent.
Water planes and pre-flight walking intent are explicit fixtures; camera,
UIKit and Metal are outside that gate. Other presentation owners are inert in
the cancellation fixture, while the real physical flight/root states are checked.

Final focused results: 69,333 fixed-velocity/cancellation checks, 3,976 heading
checks, 8,369 climb-runtime checks and 14,576 controls/lifecycle checks pass.

Private reports are generated under `local-only/research/fixed-velocity/`.
The preserved Core83 baseline probe lives only in its ignored research folder.
Original tracks, browser bundles, generated runtime fixtures and native libraries
remain local-only. Full Simulator/iPhone builds and live acceptance are separate.

The browser's previous/current pose interpolation is still a separate boundary:
the native rendering path follows current committed poses. Fixing velocity
ownership does not add render interpolation or prove physical 120-Hz display
smoothness, original camera feel, retail input latency or full gameplay parity.
