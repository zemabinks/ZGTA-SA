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
python3 smoke_native_vehicle_presentation.py
python3 smoke_native_remote_bike_owner.py
```

They exercise the literal renderer method and owner argument with the actual
rig and bike controllers, using authored geometry, inputs, clocks and storage.
Optional historical roots verify the earlier failures. The parked lifecycle
gate additionally requires a separately built macOS native-physics archive:

```sh
python3 smoke_native_parked_phase.py
```

That gate runs the actual world, solver and parked manager on an invented car
and floor, checks repeated demotion/promotion and verifies that restoring visual
counters preserves physical state. It requires no game files.

These are bounded source and physics tests. Rendered aircraft/bike/wheel scenes,
all ownership transitions, original handling, physical-device performance and
retail1:1 gameplay remain separate acceptance requirements. In particular, these
changes do not establish wheel-phase transfer on every owned-player exit path.
