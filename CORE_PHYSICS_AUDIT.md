# Core physics and weapon transition audit

This audit covers the isolated native core baseline and its public-client
integration. Passing the archived JavaScript/Rapier fixtures establishes that
boundary only. It does not establish complete retail GTA SA behavior.

## Corrected and exercised

- An externally placed on-foot pose (`heldFeet`, used by climbing/attachments)
  now moves the enabled walker collider before the shared physics step.
- Vehicle teleport rebuilds the physical solver instead of retaining old wheel
  support, steering, transmission, rotor and contact state. It clears pending
  partial-frame time and preserves the existing damage controller and hinges.
  The public client's module62540 `place`/`lift` paths recreate the solver using
  `tp`; its damage owner is separate. The native API intentionally preserves
  damage and does not imply automatic repair of a wreck.
- When another player takes a promoted parked vehicle, the authoritative target
  is applied after demoting the local body. Previously demotion replaced that
  target with the previous parked pose. A stationary driver could leave this
  collision body at the wrong location until another changed packet arrived.
- Invalid vehicle frame deltas and non-finite teleport destinations cannot
  poison the solver or body.
- `NativeWeaponState.consumeAnimationShot(weapon:)` consumes an original gun
  animation emission without imposing a second wall-clock fire interval. It
  rejects emissions after weapon switches, while reloading, or with an empty
  clip. The event owner must update animator readiness synchronously after each
  accepted event, before the next fixed substep. The fallback firing path also
  rejects a selected weapon whose catalog has not arrived.
- Inventory-authorized server shots use optional extracted animation timing,
  including continuous20ms and twin half-cycle emissions. Server-time credit
  permits at most2 ordinary or5 stream transport-credit rounds; switching weapons does
  not create new credit. Native sequence numbers are scoped to each socket,
  preventing replay while allowing a new client to reconnect with a new counter.
  An accepted gun shot authorizes one hit only. Legacy non-inventory traffic
  retains its prior limits. Projectile launch does not impose a conflicting raw
  interval after the inventory already authorizes and bills its ammunition.
- Area-effect hits now require a recent inventory-authorized emission, the
  currently selected non-reloading weapon, plausible muzzle location, matching
  interior, living/non-passive participants, the original stream cylinder and
  a complete unobstructed collision ray. Each shot/target pair is replay-guarded;
  each victim receives at most one check per300ms. No hit bills ammunition a
  second time. This also permits one stream check to affect multiple people.
- Extinguisher emissions suppress the player's existing fire-dispatch spot
  only after server-timed valid spray. They advance that existing mission to
  its next spot/rescue state. They never damage people or repair vehicles.

Run `zsh smoke_core_physics_transitions.sh`. It uses actual local vehicle chassis
and the native Rapier bridge, with an explicitly synthetic flat collision floor.
It checks attached colliders, six vehicle categories' warm-to-cold teleport
equivalence, damage identity, occupied ownership transfer, partial-frame reset,
geometry pause, and equivalent constant input at30/60/90/120/144Hz plus uneven
frame partitions. It is an integration invariant test, not a retail replay.

The standalone inventory test uses no network or game assets:

```sh
mkdir -p local-only/native-physics/tests
env -u SDKROOT xcrun swiftc ios/App/NativeWeaponState.swift \
  smoke_native_weapon_state.swift -o local-only/native-physics/tests/weapon-state
local-only/native-physics/tests/weapon-state
```

Run `node smoke_weapon_cadence.js` for canonical fast-gun and stream timing,
synthetic enabled-twin timing, bounded catch-up, reload/empty/switch/reconnect
guards, and an isolated actual-server shot/hit replay test. It does not start
an HTTP server. Existing inventory and native-server regression tests also pass.

Validated on2026-11-15:

| Gate | Observed result |
| --- | --- |
| `zsh smoke_core_physics_transitions.sh` | PASS: collider attachment,30–144Hz and uneven cadence, occupied handoff, six-category teleport reset/damage identity, invalid input and collision-stream pause |
| compiled `smoke_native_weapon_state.swift` | PASS: twin/catch-up inventory events, empty/switch/reload/catalog guards, stale revisions, fallback cadence |
| `node smoke_weapon_cadence.js` | PASS: canonical timings, bounded2/5 transport credit, replay and reconnect, actual server hit binding |
| `node smoke_weapon_inventory.js` | PASS: existing purchase/refill/slot/ammo/reload/armour/persistence rules |
| `node smoke_native_server.js` | PASS: existing inventory/projectile/home separation and unattended vehicle persistence |
| `node smoke_weapon_streams.js` | PASS: actual backend with synthetic peers and SCL2 geometry, wall/clear/missing-cell validation, area cylinder/cadence/replay/ammo/state guards, extinguisher suppression and no pedestrian damage |
| `node smoke_fire.js` | PASS: existing fire-dispatch truck/suppression/rescue/payout/restart/expiry rules |
| `node smoke_character_motor.js`, then native `smoke_character_motor.swift` | PASS:2100 archived on-foot frames,89,734 comparisons, maximum error6.68e-10 |
| `python3 smoke_native_weapon_effects.py` | PASS:11 archived projectile paths/fuses/bounces plus radial falloff, stream cadence/occlusion and satchels |

The fixture generators write ignored measurements only. The combined iPhone
and Simulator application build remains a separate acceptance gate owned by
the main task, rather than being implied by these helper tests.

## Unit and cadence evidence

The native car and bike solvers express velocity in GTA units divided by50,
apply the normalized gravitational decrement `0.008 * (50 * seconds)`, then
convert velocity back by multiplying by50. Their resulting acceleration before
drag is20world units/s². Replacing this with9.81 would change the existing
behavior. Body gravity scale is0, so the shared world's gravity does not add a
second gravitational acceleration to these controlled bodies.

The public client's module39943 on-foot motor similarly uses its own gravity
and damping. Its fixed60Hz native replay remains a separate regression gate.

For an independent behavioral reference, the community's
[retail1.0US reconstruction of Physical.cpp](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Entity/Physical.cpp)
describes the same normalized gravity value and timestep-scaled movement.
[Timer.h](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Timer.h)
defines50 normalized steps per second;
[Timer.cpp](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Timer.cpp)
bounds the physics step at3 normalized units while preserving a separate
non-clipped clock. These are static reconstruction references, not observed
execution of a retail executable. No implementation was copied from them.

## Open boundaries

- The view controller previously capped every frame at50ms, including visual,
  movement and audio updates. Below20FPS this discarded elapsed time. Its
  cadence integration is being handled separately from the physics helpers.
  Common-frame cadence equality does not prove pause/resume or low-FPS retail
  parity, which also depends on separate game and real-time clocks.
- The archived vehicle `resume` path explicitly resets speed, so zero-speed
  entry has not been changed merely because momentum preservation seems more
  plausible. A retail moving-vehicle entry replay is still needed.
- Native gun animation emits `Frame.shot`/`shotLeft`; original continuous gun
  cycles can emit at20ms intervals. The old view-controller timer bypassed
  these events. Renderer/controller routing must use the synchronous inventory
  API above to align actual firing with the pose. Client-side readiness alone
  does not correct server-owned ammo/damage timing.
- Server inventory ownership, reload policy, damage values and the bounded
  catch-up allowance remain independent self-host policies. Reading public
  animation emission timing does not reveal the publisher's private backend.
  Complete twin assets/attachments and every weapon interaction still need
  coordinated client integration and runtime validation.
- The archived own-player stream wrapper (9737, near byte1744243 of the retained
  bundle) requests hits every0.3s using a target centre0.9m above the feet,
  weapon range,0.8m lateral tolerance and an unobstructed ray. Its callback
  argument1 is a public request value, not evidence of the private server's
  final damage. The separate `cY` extinguisher path reduces flame strength
  by2 per second in a10.1m-long,1m-radius cylinder and batches wet state.
  These constrain the authoritative stream validation now implemented.
- Stream damage is an explicit independent policy: flamethrower37 and spray41
  each request one damage point per eligible300ms check (armour is absorbed
  first); extinguisher42 does no pedestrian damage. The evidence lifetime350ms,
  muzzle-distance bound3.5m and replay/state checks are server safety policies,
  not claimed publisher/retail rules. Fire-job suppression maps one logical
  mission spot to unit strength and requires0.5s valid spray at2strength/s.
  It counts bounded server time, never client-supplied durations or duplicate
  packets. Partial progress belongs to the live peer and is not persisted.
- The server has no continuous authoritative vehicle-engine or molotov flame
  state to douse. Vehicle health is never raised to imitate extinction; those
  world-fire systems remain an explicit gap. Stream weapons must be present in
  the host's granted inventory/catalog; their acquisition is not added by this
  validation patch, and the retained public shop does not sell every weapon.
- Render-time projectile prediction and fixed-step authoritative simulation can
  diverge before reconciliation. The renderer currently deduplicates nearby
  predicted/server blasts by position and time; a robust network identity for
  predicted versus confirmed detonations remains a separate protocol task.
- The independent native Rapier solver is not the original GTA collision
  engine. Matching the browser's solver does not prove original physical
  contact responses, moving-platform behavior, damage or every vehicle task.
