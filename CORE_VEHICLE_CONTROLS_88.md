# Native coupling and working controls

The game controller now connects the confirmed coupling transport to the
Renderer's physical helper. A new connection resets that helper's namespace.
Topology is applied only for the current nonce. Requests preserve the original
`NativeVehicleCoupling.Request`, including its generation token, in the ACK
completion; they are not reconstructed from vehicle IDs.

Before a hitch, the controller publishes the full current driver state and
current working-part value, then the available parent/target `vmove` snapshots,
then the hitch packet. The ordinary200ms position interval does not supply an
acquisition pose. Missing poses, unavailable capability/baseline, no driver,
death or lost input readiness produce no partial acquisition traffic. A callback
that changes connection or vehicle ownership during pose publication stops the
remaining moves/hitch. Rejected ACKs reach only the original request/nonce.

A safety detach is distinguished from a player acquisition: a live current
owner may release a broken link while a menu covers input. It still requires
the ready connection/capability/baseline, current driver and fresh pose, and it
still aborts across a nonce/ownership change. Its pose honestly carries the
covered-input paused flag. New acquisitions remain blocked under that menu.

Working state is included in regular driving packets and captured before
`exitVehicle()` clears its owner. Health and damage are captured at that same
boundary. The exit packet combines the preserved vehicle body pose with the
completed pedestrian exit feet.

## Input ownership

| Context | Input | Implemented action |
| --- | --- | --- |
| Vehicle with working controls | Numpad8 / Delete | Source working input-1 |
| Vehicle with working controls | Numpad2 / End | Source working input+1 |
| Vehicle with working controls | Existing upper/lower auxiliary touch buttons | Raise/lower in world space; tow-bar sign is reversed relative to forklift |
| Vehicle with working controls | D-pad up/down | Same world raise/lower; explicit native controller adaptation |
| Confirmed coupling | Keyboard X | Release coupling |
| Confirmed coupling | Existing crouch/gear touch button | Contextual Unhitch action with link icon |
| Confirmed coupling | D-pad right | Release coupling; explicit native adaptation on an otherwise unused direction |
| Jet nozzle without working controls | Existing auxiliary buttons / nozzle keys | Retained nozzle controls |

Working controls own Delete and D-pad up/down, preventing simultaneous radio
changes. Nozzle-down similarly owns its D-pad direction. Vehicle handbrake on
PadX, shoulder look/rudder, sprint/hop, camera, radio outside those contexts and
existing menu key ownership remain intact. No vehicle weapon action is added.
Keyboard source direction and touch/controller world-height semantics are
deliberately distinguished; physical controller/retail runtime acceptance is
not claimed.

The auxiliary UI refresh is separate from `setDrivingControls`, which retains
its ownership-transition reset. Asynchronous metadata/link updates can reveal
working or Unhitch controls without resetting throttle, steering or other held
inputs on every HUD update. A changed auxiliary mode neutralizes only its held
axis; it does not reset the physical part's value. Each touch button releases
its own hold, so one finger cannot cancel the other.

Unsupported camera/goggles/utility gun controls are hidden. The actual camera
profile's aim flag alone does not make its unimplemented gun fallback available.
Parachute deployment, vehicle horn/bunny hop and acknowledged dead-player
respawn retain their contextual actions. Selected detonator40 uses the existing
detonation action on a new press with synchronized inventory and hand/task
eligibility; it spends no gun round or ticket. No acquisition is invented.

## Executed focused checks

```sh
python3 smoke_native_coupling_controls.py
python3 smoke_native_bindings.py
python3 smoke_native_respawn_dispatch.py
python3 smoke_native_melee_delivery.py
```

- **41 extracted actual GameVC checks** cover full driver/working/kit state,
  pose-before-hitch order, original request generation, stale/reentrant nonce,
  exit capture, callback routing, asynchronous UI refresh without resets,
  independent touch release, axis cancellation without value loss, Unhitch
  context, unsupported utility visibility, deploy and respawn. They additionally
  cover allowed safety detach versus blocked acquisition under covered input,
  paused pose, captured generation and stale nonce during that release.
- **3,833 bindings/actual dispatch checks** include the working key signs,
  context-owned radio conflicts, D-pad adaptation, coupling context mapping,
  Unhitch dispatch and detonator release-to-rearm behavior.
- **38 actual respawn checks** additionally prove that a dead parachutist
  requests acknowledged respawn rather than deploying a canopy.
- **24 actual VC melee/utility delivery checks** preserve melee delivery and
  show selected detonator40 uses no gun round/ticket and respects task ownership.

Two historical method-body controls fail as expected: reading working state
after vehicle exit, and using the old shared release handler for both auxiliary
buttons. These are isolated compilations of the earlier owned source, not live
App mutations. The existing menu, reload, combat and full application acceptance
remain separately tracked by their gates.

These are source-extracted regressions with controlled network/Renderer/button
carriers and real bindings/inventory/request types. Actual URLSession packet
and nonce behavior has its separate40-check coupling wire test. No UIKit
rendering, physical multitouch/controller or native-joint claim is inferred from
these focused controller tests. Full optimized builds and the complete suite
are Root's acceptance boundary. Evidence and hashes remain under ignored
`local-only/research/coupling-integration`.
