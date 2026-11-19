# Native vehicle occupants and shared authority

Core107 adds local passengers to the independent server adapter and corrects
native rider attachment. It preserves the existing paint pipeline and the
same-ID parked/driver lifecycle. This is a bounded compatibility correction,
not complete vehicle or original-game parity.

## Causes and corrected boundaries

The previous native entry path requested only a driver. Its controller promoted
every successful entry into local driving physics, and its position sender had
only driver and ordinary pedestrian states. It could not represent a local
passenger without claiming the vehicle body.

The existing remote passenger renderer read row34, but applied the130m visibility
test to the passenger's walking coordinates before resolving the vehicle. A
passenger whose walking report remained at an old location could disappear while
the shared car remained nearby. Its attachment also selected independent driver,
parked and local pose components rather than one resolved vehicle frame.

The new native seat state binds a request to vehicle ID, seat and connection-
scoped request number. Cancellation, denial, revocation, despawn and reconnect
clear the relevant state. A cancelled response cannot grant the replacement
same-ID/same-seat request. Earlier independent hosts retain their uncorrelated
driver acknowledgment compatibility; passengers require the explicit matching
grant. See [the backend/browser contract](CORE_VEHICLE_SEATS_107.md).

| Native state | Publication and physics |
| --- | --- |
| Driver | Existing vehicle code/ID, body pose and condition; owns the local driving chassis |
| Passenger | Walking-shaped skin actor with `riding` ID and `seat`; never publishes `car`, driver body, `parked` state or moving-vehicle authority |
| Passenger exit | Explicit seat release, then ordinary foot state; preserves the existing shared chassis |
| Cancel/reconnect/despawn | Clears the request/seat and pending rider state; never manufactures a parked car |

The actual driver frame, local physics model matrix or parked model matrix now
supplies the complete attachment transform. Passengers are culled at the shared
vehicle, not their stale walking coordinates. Entry/exit playback uses the exact
imported seat, its door state and the existing native rider animation pipeline.
Changing vehicle/seat or the actual pedestrian actor resets that rider's transition capture. This also prevents bone arrays captured from an old rig from being indexed by a replacement rig.

The local passenger stays out of driving physics. Exit clearance reuses the
existing imported-hull/ground/capsule planner against the shared body without
taking, parking or removing it. Camera queries exclude only that shared body's
colliders; those colliders remain physically active.

Passenger controls retain exit, camera and radio while hiding driver pedals and
currently unsupported foot-combat actions. Native entry into an occupied car
chooses an available passenger seat from the imported per-model seat inventory
and current occupant rows. The server independently validates the claim.

## Driver visibility and resource readiness

The own-driver draw path now requests an absent rider before requiring its pose.
This prevents the missing/evicted-actor loading dependency from suppressing the
reload. The exact imported rider seat can also satisfy the driver seat lookup
when the optional old parts metadata is unavailable.

These corrections are separate from the resource owner's atomic mesh/skeleton/
vehicle-rig readiness and retry repair. The observed browser/native invisible-
driver report still requires actual rendered scene acceptance; passing a pose or
loading test alone does not certify every visibility cause. Unsupported/missing
skins, including segmented CJ assembly, are not substituted with another model.

## Verification and limits

Current focused acceptance records70 actual native/backend checks and3,325
Renderer/session/skinning checks. The actual Rapier/exit/camera carrier records336
checks, the driver/crash/wreck regression502, controller dispatch68 and connection
owners62. These separate counts are not a full-game acceptance total.

The focused test entry point is `python3 local-only/research/native-occupants-107/test_native_vehicle_occupants.py`.
`--network-only` runs the real unmodified native URLSession client against a
copied real backend and separate browser-shaped peer. `--renderer-only` runs the
actual extracted passenger/shared-frame methods with real imported animations
and native skeletal actors. Owner data, generated references and reports remain
under ignored `local-only/research/native-occupants-107`.

- Actual native/backend checks cover both driver/passenger directions, shared
  movement, stale walking reports, cancel/late acknowledgment, normal exit,
  reconnect, explicit deletion and role-correct packets. The backend agent's
  independent raw-wire and actual archived-browser checks are recorded separately.
- The Renderer carrier checks200 repeated request/cancel/grant lifecycles and120
  moving/rotating vehicle frames with two independent real skeletal passengers.
  It also checks local-driver and parked transforms, missing vehicle/actor
  behavior, shared door state and actual actor replacement. Mesh loading and draw append are explicit
  carrier boundaries; this is not a complete rendered App frame.
- Actual Rapier/controller regression covers three imported passenger hulls,
  collision-clear exits, subject-only camera exclusion and preservation of the
  existing physical body. Prior driver/crash/wreck/water/facing assertions remain.
- Controller dispatch and connection-owner tests retain earlier assertions and
  add passenger-only publication, functional controls and seat-state teardown.
  The real-UIKit carrier includes passenger car/bike contexts; executing it is a
  separate App-runner acceptance step.

Local passenger control remains explicitly unavailable through the legacy SA-MP
and original-site adapters until their outgoing seat synchronization is actually
implemented and verified. This does not establish passenger drive-by support,
jacking, every vehicle-specific exit, universal custom seats, first-person
passenger camera accuracy, retail timing or device performance. Physical and
browser/native rendered acceptance must be reported separately.

All public changes are independently authored source/tests. Original game
resources and archived browser implementations remain local to the owner.
