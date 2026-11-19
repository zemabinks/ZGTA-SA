# Slow vehicle climb admission

Core91 removes a native-only rejection after the existing ledge finder. The
finder already implements the archived client's strict linear-speed limit:
nonfixed bodies are eligible below0.5 world units/s and ineligible at or above
that actual queried speed. The Renderer then rejected every nonfixed result,
so stationary and slow vehicles could never start climbing.

The actual archived pedestrian entry function accepts an eligible vehicle
ledge. A retained negative run of the expanded native gate reproduces the
old rejection for `vehicle=true, normal`. The correction removes the extra
`ledge.fixed` requirement while preserving the existing health, flight,
animation, clearance and speed requirements. Vehicle ledges still cannot
select the fixed-wall vault path.

## Verification

`tests/movement/smoke_native_climb_entry.js` executes the unchanged archived entry predicate
with ten controlled cases: fixed/vehicle ledges, normal entry, worn jetpack,
active flight, death and unavailable animation. Original source and generated
references remain local; the published test contains the independent loader.

`tests/movement/smoke_native_climb_runtime.py` compiles actual current Renderer methods,
animation code, real local clips, collision queries and the native character
motor. Its expanded gate passes21,269 checks over3,626 display frames and3,137
physics ticks. Dynamic, position-kinematic and velocity-kinematic bodies cover
admission, actual queried speed near the strict boundary, forbidden vehicle
vaulting and complete low/high climbs at30/60/120 display rates.

For position-kinematic fixtures, velocity comes from a next pose and physical
step. A requested `setBodyState` linear velocity is not an established input
for that body type. The test verifies the measured velocity and compares
admission against that value, rather than silently assuming the request took
effect.

The separate support/runtime gate now passes3,303 checks, adding explicit
handoffs from vehicle support to climbing, swimming, flight, death and driving.
Each handoff must clear physical support ownership, carried presentation and
the outgoing network attachment. The recording task/knock probes in that gate
retain their documented boundaries; they do not replace the real climb gate.

Final acceptance passes **94/94 gates**, captured sources unchanged, and
Release Simulator plus unsigned generic iPhone builds91. The unchanged native
bridge/header/core reuses Core90's five-link Apple ABI evidence; both Core91
platform builds link their real libraries. Reports remain under the owner's
ignored `local-only/acceptance-core-91` directory.

## Limits

The archived climb controller captures its ledge in world coordinates. This
change reproduces that admission and snapshot behavior. It does not add an
entity-relative moving handhold or establish how the original retail engine
handles a vehicle accelerating or rotating during a climb. Original retail,
rendered scene, physical touch/controller and iPhone performance comparisons
remain open. No1:1 gameplay accuracy is claimed.
