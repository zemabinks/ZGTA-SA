# Native camera collision policy

The native driven-vehicle camera now ignores only the locally dynamic vehicles
owned by `NativeOtherVehicles`. Ordinary kinematic neighboring cars remain
camera-solid. This restores a demonstrated archived-client query distinction;
it does not establish original retail camera behavior or solve every close-car
view obstruction.

The parked/remote owner is the proven equivalent of the archived client's
vehicle `others` registry. Promotion creates a dynamic unattended body;
occupation, demotion, replacement, removal and ownership handoff replace or
remove that body's membership. Camera exclusions are derived from the current
owner and checked against current collider/body identities. No physics state,
shape, pose, contact coefficient or collision mask is changed.

The native material number 63 is used for vehicle damage/query metadata. It is
**not** evidence that a vehicle collider belonged to the archived client's
separate material registry. The policy keeps those concepts independent. The
archived tagged-other pedestrian branch has no corresponding native remote-ped
collision owner yet; the implementation does not invent that registration.

The on-foot camera retains its existing world-only query mask. The SA-MP camera
adapter retains its previous solid-body policy through an explicit separate
trace path. Authored custom objects retain their explicit camera-collision
flags, and missing streamed collision remains an unavailable boundary rather
than becoming clear space.

## Passive local diagnostics

Recording is disabled by default. No menu item, launch argument, automatic
capture or upload activates it. An owner-controlled diagnostic integration can
call:

```swift
renderer.beginPassiveCameraTrace(maximumRecords: 1800,
                                maximumBytes: 2 * 1024 * 1024)
renderer.endPassiveCameraTrace { summary in
    // Inspect summary.error and the returned local summary.file URL.
}
```

The journal stays in the app's `Caches/CameraAudit` directory. It records actual
camera view/time/delta, observed queued orbit input, subject camera-input basis,
bounds and wheels, desired/collision-resolved/post-shake eye, and actual ray hit
identity, body kind and independently classified membership. A separate draw
record contains the rendered eye/projection and available exact vehicle model
matrix, identifying legacy camera overrides. A missing `up` or model matrix is
recorded as absent rather than reconstructed. It records no game account,
authentication material or player names; the journal stores only its own file
basename, not a user's filesystem path.

Submission performs no file I/O or JSON encoding. A serial utility queue owns
those operations, bounded to 32 pending records by default, at most 7200 accepted
records and 8 MiB per session. Four trace files are retained. The summary reports
queue/record/byte/encoding/I/O drops and the complete written byte count.
Stopping drains accepted writes and returns on main; a second recording cannot
start while the renderer is finishing the first. The cache may be evicted by
the operating system. These files are diagnostics, not a save format.

Recording observes normal inputs and camera results; it does not inject
controls, select views, change camera integration or send transport messages.

## Focused verification

```sh
python3 tests/ui/smoke_native_camera_policy.py --sensitivity
```

If the accepted host archive is elsewhere, pass its directory using `--library`.
The runner checks its native source stamp, compiles immutable source copies and
never rebuilds or changes the archive. Its public fixtures use independently
authored metadata and real native geometry. It extracts the actual renderer
query methods, exercises real parked-body lifecycle transitions and explicitly
separates native material tags from original registry membership. The negative
control removes the new scoped exclusion from the extracted test candidate and
must fail the promoted-body query assertion. The optional recorder is checked
for bounded writing, cancellation/stop, failures and camera-result equality
across 15/30/60/120 Hz and all six vehicle views.

Original browser execution, owner data, captures and their reports remain in
ignored local research. There is no retail executable, GPU, physical-controller
or iPhone performance claim in this host regression. A close view obstructed by
the owned car can still follow the archived browser algorithm; this change
introduces no speculative vehicle hiding, fade rule or near-plane adjustment.
