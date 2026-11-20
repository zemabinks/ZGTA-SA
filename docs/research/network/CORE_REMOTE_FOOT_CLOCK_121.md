# Remote character presentation time

Remote foot animation now owns its display clock per character. Ordinary active
intervals through half a second are retained and advanced in steps no larger
than one sixtieth of a second. The character's network position, local motor,
movement speeds and transport packets are unchanged.

A newly created character starts at zero elapsed time. Leaving visibility,
application suspension, disconnect and model replacement cannot donate an old
draw interval to a new owner. Backward, non-finite and long-gap samples do not
replay background time. A valid resume observes the current snapshot at zero
elapsed time before advancing again. The direct delta animation API retains its
existing contract.

The bounded interval uses the currently observed controls. Position and heading
are interpolated between observed endpoints so repeated substeps do not create
a false jetpack velocity impulse. This is presentation sampling; it does not
invent authoritative packet timestamps or establish the exact time of an
unobserved task change.

The final pose is drawn once. Travel, footstep and projectile events are retained
across all admitted steps. Parachute targets are passed to the actual canopy
pose operation in order, including target disappearance and landed-anchor
retirement. Combining easing factors against only the final moving target would
lose the intermediate poses. Held frames clear their event/target sequences.

Run the portable CPU regression with:

```sh
python3 tests/movement/smoke_native_remote_foot_clock.py
```

The gate compiles the actual CLP reader, animation controllers and literal
Renderer clock/attachment dispatch against authored tracks. It covers slow and
jittered schedules, ownership resets, invalid clocks, traversal presentation,
single/twin/stream firing, reload/switch boundaries and moving canopy targets.
An optional `--negative-root` checks the earlier capped implementation. Optional
`--owned-library` and `--owned-definitions` inputs provide separate private
reference-data checks; those files and results are not published.

These checks establish bounded scheduling and dispatch behavior. They do not
establish retail input timing, rendered foot contacts, exact canopy bones,
physical-device performance or complete gameplay parity. Real multiplayer
scene acceptance remains separate from the CPU gate.


## Remote pedestrian world playback (157)

Remote character roots previously used each latest network point directly.
An authored5Hz/60Hz source carrier reproduces82 held moving display steps out
of90, followed by approximately0.32m jumps at1.6m/s. This concerns remote
world translation, separate from the existing per-character animation clock.
The initial private carrier compiler rejection and later correction-settling
assertion failure remain recorded separately from successful follow-ups.

A new presentation owner retains up to40 snapshots per pedestrian and24
cadence observations. It interpolates feet, velocity and shortest-path yaw,
with bounded prediction (120ms for ordinary foot history;250ms for special
motion) and a120ms correction decay. Adaptive delay is bounded to40–400ms.
Stops, placement warps, streamout/reconnection, appearance, support/passenger
ownership, pause/death and application suspension have explicit boundaries.
Legitimate fast special movement is not classified as a walking warp.
Original Z-up feet and the existing legacy CPed conversion remain separate.

The scene publishes one presentation snapshot to drawing, animation input,
aiming, melee, local projectile effects and the radar. Raw multiplayer rows,
local input/motor timing and server damage/vehicle authority are not rewritten.
The legacy decoder now retains each player's own receipt time, so another
player's or vehicle's callback cannot manufacture a new motion observation.
Sender wall clocks are duplicate identities only; they never select the local
time epoch. Local cadence observations intentionally differ from the archived
browser's server-normalized age observations.

The portable literal decoder/callback/scene/targeting carrier passes1454 checks
with authored clocks, including20/30/60/120Hz display schedules, jitter,
stopping, yaw wrapping, invalid clocks, packet identity, lifecycle and attachment
boundaries. Steady motion has no held sampled frames on those schedules.
A separate offline process executes the actual archived interpolation helpers
and archived vector/quaternion math:24 authored cases yield360 samples. The
native common interpolation kernel matches position, velocity, yaw and discrete
endpoint selection within1e-8. Raw scripts, original files and measurements
remain local. This is finite helper behavior, not a running-browser comparison.

Full source-chain, both SDK products and normal app/remote-peer acceptance are
pending. The native motion owner is not a complete reproduction of the
browser frame function: server-normalized timing, its eligibility epoch,
three-axis spin, action-specific resets, air/ground correction, collision
clipping and explicit kick contributions remain separate. Existing pitch/roll
and animation owners are preserved. Independent-server hit validation still
uses its existing authoritative policy; complete latency/lag-compensation and
rendered browser/native combat acceptance remain open. Original GTA SA1.0US,
physical-device performance, full multiplayer parity and ambient AI are not
established by this work.

Run the source carrier with:

```sh
python3 tests/network/smoke_native_remote_motion.py
```

Its optional `--owned-reference` accepts separately retained private helper
measurements; it does not fetch or redistribute original client scripts.
