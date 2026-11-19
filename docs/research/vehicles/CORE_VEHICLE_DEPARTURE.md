# Vehicle departure and parked aircraft state

Core86 repairs two native integration defects. These are public-browser and
native-world comparisons; no original retail executable was run, and the
changes do not establish retail or physical-device handling parity.

## Explicit disappearance versus streamed omission

The archived public manager `cq` intentionally retains a promoted parked body
when a full-list update omits it. Its explicit `gone(id)` path disposes a
non-held body, removes its colliders and destroys the entry. Native prediction
retained omitted bodies correctly, but had no explicit deletion route. A moving
vehicle removed by the server could therefore leave a ghost collider and
continue predicting movement. Clearing only the network arrays during reconnect
had the same defect.

`NativeGroundVehicle.removeOtherVehicle(id:)` now revokes that parked entry and
returns whether it existed. `clearOtherVehicles()` disposes the parked world
at a session boundary. Both operate through the pool's existing disposal path,
which also removes any queued shove/reference and future movement callbacks.
They do not remove the separately owned chassis. Ordinary list omission keeps
its existing behavior. The network/controller must route explicit vehicle-gone
and new-session events to the appropriate method; full-list omission alone is
not an explicit disappearance.

## Rotor and landing gear after exit

The owned-to-parked transfer already preserved physical linear/angular velocity,
rotor speed and landing gear in the unattended solver. The displayed parked
snapshot omitted rotor/gear, and demotion discarded those states. A spinning
helicopter or gear-up plane could consequently display a stopped rotor or
lowered gear immediately after exit.

The parked snapshot exposes `rotor` and `gearUp`. The pool retains them across
demotion and re-promotion. A demoted rotor coasts through the same original
`89888.s2` rule used by the physical flight solver, shared as
`NativeFlightDynamics.stoppedTurning(kind:amount:ticks:)`; ticks are the
source's normalized 50 Hz steps. The renderer should apply these fields only
to a parked vehicle without a live remote driver, preserving that driver's
independent network kit. No nozzle state or new force constant was invented.

## Entry policy investigated separately

The actual browser entry caller takes the parked object, sets the car and its
damage, then calls `stand(position, quaternion)` before resuming driving. The
`62540` stand/resume path resets its stored motion before recreating the solver;
setCar resets the gear flag. Native fresh owned entry currently makes that same
reset. It was not changed to restore snapshot momentum/rotor/gear without an
original-game behavior reference. The parked transfer and demotion repairs do
not claim that this browser entry policy reproduces retail San Andreas.

## Focused verification

```sh
node tests/vehicles/smoke_vehicle_departure.js
zsh tests/vehicles/smoke_vehicle_lifecycle.sh
python3 tests/vehicles/smoke_vehicle_air_handoff.py
```

The actual archived manager passes 119 disappearance/omission/held-ownership
checks across seven model classes. Native-world lifecycle tests pass 92 checks
including deletion, queued-shove cleanup, idempotency, same-id replacement,
session teardown, owned-body exclusion, authority transfer and wreck coasting.
Aircraft tests pass 11,037 comparisons covering actual source rotor coasting
at 15/30/60/120 Hz, physical momentum on exit, raised gear, demotion, coasting,
re-promotion and fresh owned entry. They also extract and compile the actual
renderer's remote-kit and parked-snapshot clauses with production rig inputs,
checking dynamic/demoted output and live-player gear/nozzle-kit dominance.
This is a clause integration gate, not a rendered-frame or device test.
Maximum rotor reference error was
3.47e-17. The runners contain no original model tables or recorded samples;
required owner-local models and generated reference values remain ignored.

Remaining gaps include retail moving-vehicle entry behavior, jacking/fall-off,
rollover crawl, special working-vehicle controls, modification acquisition and
full aircraft handling acceptance. Acceleration conversion and high-speed
suspension candidates remain unchanged; their raw data identity does not prove
the missing engine behavior.
