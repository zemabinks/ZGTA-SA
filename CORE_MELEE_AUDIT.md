# Native melee event integration

Melee now has its own input/animation event path. The ordinary gun ticket/ACK
path remains separate. Accepted R6 strike requests trigger swing audio; actual
animation hit markers publish the selected weapon, combo/aside, fixed-step feet
and actor heading. A rejected request does not manufacture a hit.

## Evidence

The owner-supplied original PC `weapon.dat` and `melee.dat` contain melee weapon
groups, hit/chain frames, radii, hit levels, damage and sound data. Independent
parsing matched403 compared fields across16 archived browser weapon profiles
and13 original combo groups. This establishes data agreement, not retail runtime
collision, damage multipliers, input cadence or visual feel. No retail executable
or unlicensed reconstructed implementation was executed or copied.

The original PC tutorial in `american.gxt` confirms guard-plus-enter special
attack and jump-as-block inputs. The existing R6 API does not establish which
retail special move should play. Alternate intent therefore returns unsupported;
it does not enter a vehicle or disguise an ordinary strike as the special move.

Browser behavior comes from the actual archived main9737 input/fire/ground
expressions and49368.R6. The source hashes/ranges and original-data comparisons
are retained privately in the prior frozen audit under
`local-only/research/remaining-melee`; no original bytes are repository fixtures.
The bounded60662.OY selector static REA record is
`ev_3a1a27d8fecc0b07f9484aa299ca9abd9157899bd3cde2bb67065aa1c6d32ec2`.
Static selector coverage does not establish the entire game/control graph.
The actual input/fire/R6/ground Node reference replay completed with exit0 in
REA controlled process evidence
`ev_8230373ee27339980ecd3998ee9b72131fc833f6bb0aaa3d45445b8b81afbca3`.
The Swift comparison is a separate ordinary regression, not a retail process
capture. The prior U1/OY probe is controlled evidence
`ev_2e6289280ed9fbc21bc5ac99fb41820fe96af186522173bb6c26f330c099d66c`.

The frozen integration audit measured18 fixed-.35s punch requests,7 rejected
animation requests,11 real animation markers and0 reachable melee event
callbacks. Its R6 animator already cycled all three `fighta` clips; the issue was
disconnected input/hit delivery, not universal use of only the first animation.

## Implemented contracts

- `prepare_native_melee.js` extracts original U1 metadata into the isolated
  `local-only/native/melee.json` overlay. It does not modify the shared game
  archive. The server exposes that authenticated local overlay separately.
- The loader checks data validity and compatibility with actual loaded attack
  clips. OP caps raw chain99 timing at clip duration; compatibility preserves
  that cap instead of treating99 frames as a mandatory3.3s interval. Availability
  flags also exclude unused combo-table slots; flowers expose one playable strike.
- `NativeMeleeInput` retains the browser's .4s rising-edge buffer. Weapon9 alone
  requests repeated strikes while held. Queued intent is bound to its weapon;
  focus/task cancellation discards it and stops unconsumed melee markers.
- The Renderer routes guard/block to actual R6 inputs and guard locomotion,
  without changing camera aiming. Run and ground asides use movement state and
  a live prone-target query. A newly accepted strike owns a simultaneous queued
  jump before its launch can take effect.
- `NativeMeleeTargeting` uses source-backed reach/radius, height, facing and
  target ordering. Ground attacks use the original target-oriented rectangle
  and angular preference, including living-prone priority over corpses.
- Geometry chooses the original target first. Explicit LOS then rejects that
  victim when blocked or unavailable; it does not choose a different victim
  around a wall. The trace uses melee sweep height1m and impact height1.2m
  standing, .8m crouching or .25m prone.

LOS and missing-world rejection are deliberate **independent self-host safety**.
The browser OY selector itself has no world LOS test. Server fist damage8 and
300ms victim cadence remain independent local policy, not a retail damage claim.
No client-supplied metadata grants health/damage authority.

## Verification

```sh
python3 smoke_native_melee.py
python3 smoke_native_climb_runtime.py
```

The focused melee runner executes actual archived input/fire expressions with
real R6/ANP3 at30/60/120Hz, comparing the extracted current Renderer input,
accepted-request and marker-dispatch methods. It also executes the actual ground
selector, and checks cancellation, weapon changes, blocked/expired input,
missing/mismatched metadata, unsupported special intent and LOS rejection.
It passes **5,040 frames in24 scenarios,31,275 checks,102 actual marker
deliveries and114 accepted strike starts**, including672 original ground-query
examples. All16 data profiles validate against their playable animation clips.
Generated reference measurements stay under ignored `local-only/research/melee`.

The climb regression continues linking the actual native world, motor and clip
library. Its fixture includes the real melee helper methods; it retains all
existing8,369 checks /1,504 display frames /1,308 physics ticks.

Server/VC delivery, overlay serving and original PC bindings have independent
focused gates owned by their respective integrations.

## Remaining limits

Melee weapons1–15 are not added to the acquisition catalog. Fighting-style
acquisition, the distinct retail special move, stealth/backstab task mapping and
retail bone/weapon contact volumes remain unverified. Original data exists for
several of these systems; their runtime semantics must be established before
claiming them. This change restores standard native melee timing and delivery;
it does not claim complete retail combat parity.
