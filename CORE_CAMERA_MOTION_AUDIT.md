# Fixed-step movement and camera stance

Core86 corrects a native camera integration defect. It does not establish the
original retail camera equation or measured retail crouch heights.

The preserved browser camera identifies moving crouch by differentiating its
incoming render poses. Native movement commits60 physical ticks/second, while
its camera can see repeated poses at high display rates or during substeps of a
slow display frame. Treating those repetitions as a stopped character changes
the camera stance even during constant committed movement.

The actual native motor/Rapier/Renderer-camera probe measures this steady-state
camera height above feet with zero camera pitch and1m/s committed travel:

| Display rate | Previous moving-crouch height | Core86 height |
| --- | --- | --- |
|15Hz |1.0092–1.0418m |1.4000m |
|30Hz |1.1391–1.1609m |1.4000m |
|60Hz |1.4000m |1.4000m |
|120Hz |1.1447–1.1553m |1.4000m |
|144Hz |1.1002–1.1164m |1.4000m |
|Mixed cadence |1.0812–1.1479m |1.4000m |

These are existing native/browser profile values, not newly measured original
San Andreas constants. The change preserves the60Hz moving result and the
stationary crouch stance. `Foot.planarSpeed` is an optional physical-motion
snapshot; absent or invalid values preserve the archived camera contract.
`NativeWorldRenderer` passes the current available motor velocity, not intended
stick travel or a smoothed display derivative. Blocked/resting motion settles
to the stationary stance. Neither collision/follow equations nor aim constants
were retuned.

`NativeCharacterController` separately retains `stepVelocity` for momentum
handoffs and publishes `currentVelocity` only when movement is available.
Collision-streaming or invalid-clock suspension therefore reports zero current
movement without destroying the last committed momentum. Valid no-tick display
frames retain their physical snapshot. The camera and outgoing wire velocity
use current availability; water/parachute inheritance retains committed history.
See [CORE_TASK_HANDOFF_AUDIT.md](CORE_TASK_HANDOFF_AUDIT.md).

The camera gate compiles the actual Renderer follow call and velocity getter,
actual camera and native Rapier motor. It includes stop/start, zero-tick frames,
streaming suspension, teleport, nil/invalid hints, and cancellation of an old
world's camera shake. The separate archived camera golden retains its original
contract. Run `python3 smoke_native_camera_motion.py` and
`python3 smoke_native_camera.py` with owner-local resources prepared.

Host numerical proof does not establish physical iPhone feel, complete pose
interpolation, original animation blending or retail-runtime parity.
