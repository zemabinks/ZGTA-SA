# Vehicle presentation ownership

Remote aircraft now receive their presentation rotor defaults when no owned
input exists. Explicit owned and parked rotor values keep their priority,
including a stopped rotor. This changes display animation, not engine authority,
lift, handling or network state. Unrelated vehicle kinds retain their inputs.

A parked vehicle retains its front and rear wheel phase when its dynamic solver
is replaced with a kinematic body. A later promotion seeds the new solver's
display counters. The renderer also retains those phases in its fallback cache.
Restoring phase does not change chassis pose, momentum, wheel forces or collider
geometry. Replacing the model or despawning the vehicle creates a new owner.

Remote bike lean now distinguishes the full appearance, authoritative vehicle
identity and loaded mesh-buffer identity. Rebuilding an appearance with the same
base model therefore gets the source owner's immediate lean sample. Crank,
packet serial, prediction age and pending correction retain their existing
state; they are not all reset as a side effect of appearance replacement.

The existing capped vehicle/bike draw intervals remain unchanged. The archived
browser also uses those caps; these fixes do not establish original retail
scheduling or remove a limit without a separate timing investigation.

Portable CPU checks:

```sh
python3 tests/vehicles/smoke_native_vehicle_presentation.py
python3 tests/vehicles/smoke_native_remote_bike_owner.py
```

They exercise the literal renderer method and owner argument with the actual
rig and bike controllers, using authored geometry, inputs, clocks and storage.
Optional historical roots verify the earlier failures. The parked lifecycle
gate additionally requires a separately built macOS native-physics archive:

```sh
python3 tests/vehicles/smoke_native_parked_phase.py
```

That gate runs the actual world, solver and parked manager on an invented car
and floor, checks repeated demotion/promotion and verifies that restoring visual
counters preserves physical state. It requires no game files.

These are bounded source and physics tests. Rendered aircraft/bike/wheel scenes,
all ownership transitions, original handling, physical-device performance and
retail1:1 gameplay remain separate acceptance requirements. In particular, these
changes do not establish wheel-phase transfer on every owned-player exit path.

## Rider presentation intervals (148)

The renderer's remaining seated fallback and remote-bike paths used a shared
100 ms cap even though the boarding pose clock already admits ordinary active
intervals up to 500 ms. This discarded valid presentation time. They now use the
same active/window/time admission boundary: five fallback pose paths consume
bounded 100 ms slices, while remote-bike closed-form easing and crank rates
receive the admitted elapsed interval.

Each fallback animator and remote-bike presentation adapter also owns its last
presentation timestamp. A new instance cannot borrow time from before it was
created. Repeated intervals cannot advance the same owner twice, and missed
draws do not create catch-up debt. Invalid or suspended intervals hold time;
the bike adapter retains its last valid pose if its timestamp is nonfinite.
The original direct-delta animation and bike algorithm bodies remain unchanged.
These are presentation clocks; physics, local controls, wire timestamps and
server authority retain their separate owners.

The new authored gate extracts the actual renderer clock prelude and local
fallback call, then executes the production clock, seated animator and bike
consumer at 15/30/60/120/144 Hz, mixed intervals and 125–500 ms hitches. It also
checks new owners, duplicates, missing draws, inactive/windowless views,
backwards/nonfinite timestamps and suspension. The existing literal remote-bike
dispatch fixture now checks fresh admission and repeated draws. Focused execution passes 3,081 checks. The actual earlier renderer fails the
retained-time assertion; its old bike dispatch separately reproduces borrowed
crank time (0.42 instead of 0.2). The updated current boarding gate passes 1,420
checks, and a separate frozen-historical run passes 1,435 checks, retaining its
5 Hz half-second/one-second and queued-exit witnesses. The first full run stops
at a prior assertion that explicitly required the now-retired cap. That failure
is retained; the assertion now checks exact admitted time, while its historical
cap witness remains. Failure reporting also preserves the Swift result instead
of hiding it behind a missing metadata key.

The complete selected Core148 chain subsequently passes with required Metal,
physics, audio and transport (745.7 seconds), with all 226 app/build inputs
unchanged. Host, native-project and repository-layout gates pass. Both SDK
products, actual archived direct-delta replays and the normal installed scene
remain separate acceptance gates. Their completed outcomes belong in the
release PR; these CPU results are not rendered or retail acceptance.

Thirteen owner-reference replay carriers still referred to a helper's former
root path after repository reorganization. Two actual Node executions reproduce
MODULE_NOT_FOUND without invoking Swift. All thirteen imports now resolve the
relocated offline helper. Python syntax and path-only source identity pass; the
actual archived rider/bike golden replays remain a separate pending check.
No archived script bytes or generated reference data are added to public source.

The current native per-step Euler response curves, boarding frame-rounding
policy and special-task choices still require their own original-PC comparison.
This repair deliberately retains the direct-delta reference APIs and does not
claim indistinguishable retail movement, hardware hitch acceptance or complete
multiplayer vehicle behavior. SDK, normal installed scene, physical device and
retail acceptance remain separate from authored CPU timing evidence.
