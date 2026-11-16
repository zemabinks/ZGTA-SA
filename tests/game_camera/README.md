`NativeSAMPGameCamera` is a pure, command-driven camera owner. It neither edits
Renderer/GVC/Protocol nor invents player/vehicle spectator offsets. All positions
are physical GTA world points, passed directly from the frozen gameplay commands.

Apply `NativeSAMPGameplayCommands.Event` using `apply(_:at:seed:)`. Supply the
actual current view as `seed` when handing control from the normal camera. Older
generations, duplicate/reordered sequences and retired resets are ignored before
they can affect the clock. `sample(at:normal:subjectProvider:)` returns an actual
`Pose(eye,target,up)` plus ownership, spectator state and diagnostics. Use that
same sampled eye for rendering, spectator212 and streaming; do not substitute the
local pedestrian's position. Use the returned perpendicular up in the view matrix.

Position and target tracks are independent and computed from monotonic elapsed
time, with no display-frame accumulation or lag adaptation. Timed RPC82 preserves
the supplied duration for both cuts: Cut2 is linear; Cut1 uses half-cosine easing.
Zero duration resolves to the endpoint. Endpoints persist, and large time gaps
finish exactly instead of stopping on the last display frame before completion.

Untimed LookAt158 Cut2 changes the target directly. Its Cut1 variant has no
duration on the wire, so `lookAtMovePolicy` must explicitly provide a duration and
curve. Without that policy, the previous target remains and the sample reports
`lookAtMovePolicyRequired`; no arbitrary duration is invented. Timed and untimed
cut meanings are deliberately distinguished.

For spectators, the provider receives `(Subject, SpectateMode)` and returns a
`SubjectFrame` containing actual focus and optional native normal/side views.
The mode argument lets the caller advance the appropriate existing
`NativeGameCamera.followFoot/followVehicle` adapter once. Fixed mode preserves the
camera eye and tracks the supplied focus. Normal mode consumes the provider's view;
camera position/look-at commands are locked while normal/side following is active,
consistent with the published normal-mode restriction. A missing or invalid subject
holds the previous actual view and reports a diagnostic. Missing side poses never
receive an invented offset. Views default to `unverifiedOffsets` provenance; callers
using the existing native camera adapter can label that source explicitly.

CameraBehind clears the override and requests a follower reset through
`followRevision`, while preserving spectator/control authority. Confirmed spawn
uses `spawned(at:generation:)` to clear the override and spectator state. The
generation argument protects against retired spawn callbacks. Disabling spectator
mode holds the last actual subject view until that spawn transition. Input blocking
remains the separate command authority's responsibility.

Requested coordinates, timestamps, durations and configuration values are checked.
Coincident targets use a labeled minimum-distance direction safeguard; vertical or
invalid up vectors receive a finite perpendicular basis. These corrections protect
view matrices without moving the requested eye or substituting a fake subject.

Supporting references checked on 2026-11-16:

- [open.mp interpolation API](https://open.mp/docs/scripting/functions/InterpolateCameraPos), [cut styles](https://open.mp/docs/scripting/resources/cameracutstyles), and [spectator modes](https://open.mp/docs/scripting/resources/spectatemodes) establish the public command contract.
- [gta-reversed Camera.cpp](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Camera.cpp), file blob SHA `47554085221ec7d9065bfec11d53d668279e6459`, describes separate eased/non-eased vector move/track processing. This community reconstruction is supporting evidence, not retail verification; no implementation is copied or linked.
- [MIT SAMP-API CCamera](https://github.com/BlastHackNet/SAMP-API/blob/multiver/src/sampapi/0.3.7-R1/CCamera.cpp), file blob SHA `ebfffbf7f760f92131e8d99e6e1b671cdc12bc2b`, exposes timed move/track wrappers with a smooth flag separately from untimed PointAt switching.

The Cut1/Cut2 mapping for timed RPC82 is an inference from those interfaces and
supporting engine behavior. Exact retail transitions, collision treatment, untimed
switch duration and spectator offsets still require original-game comparison.
Successful tests do not establish retail camera feel or a full gameplay port.

Run `python3 test_samp_game_camera.py`. Tests cover 15/30/60/120Hz sampling, explicit
curve values, independent tracks, interruptions, endpoints, zero duration, clock
regression, explicit untimed policy, actual injected player/vehicle views, fixed
tracking, missing/invalid subjects, stale generations, spawn/behind transitions and
finite/coincident/vertical safeguards. Reports stay under
`local-only/research/game-camera`; no game assets or network access are required.
