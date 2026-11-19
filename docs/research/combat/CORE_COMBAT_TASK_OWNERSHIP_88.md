# Core88 combat task ownership

This is a native correctness and archived-client compatibility pass. No retail
executable was executed, no unlicensed reconstructed implementation was imported,
and no retail damage, spread, skill or bone-contact formula is claimed.

## Finding ledger

| Question | Evidence and change | Status / limit |
| --- | --- | --- |
| Can guns start during a task that owns the hands? | Actual main9737 input expressions gate new gun intent on busy, stun, rolling and ordinary air state. Native requests previously omitted those checks. `NativeCombatEligibility` now separates new requests, aiming, raw held input and committed markers. Root's actual Renderer request and continuous input use that boundary. | Fixed and exercised with real knock, flinch/stun, roll and CLP associations. Native task/domain mapping is explicit; the original recent-stun-while-moving latch is not implemented by this helper. |
| Can scoped weapons start without their sight? | Actual U1 profiles give sniper34 and launchers35/36 a sight, and the input expression requires aimed sight for new fire. The already-extracted `firstPerson` flag agrees with actual U1 sight presence in tested profiles. `NativeFootWeaponAnimation.requiresAim` exposes it without a new numerical constant. | Fixed through the shared request predicate. Camera43 also has that flag, but remains a distinct utility role. This does not implement every original sight effect. |
| Should a new-start restriction erase a committed shot? | Original marker forwarding suppresses stun, while busy/roll/air start restrictions are separate. Root preserves `animator.gunUp` in the aim basis and checks committed delivery independently. | Real CLP tests retain a pre-knock gun pose/marker. Raw R6 timing/state math remains unchanged. |
| Can melee deliver a hit while stunned? | The actual main9737 marker condition follows both ranged and melee/throw paths and includes `!stunned`. The native melee branch omitted that shared restriction. | Root now checks the common combat-marker boundary in Renderer and VC. A real fist hit marker during a real stun produces no network hit. |
| Can the next hand spend another weapon after a callback? | The old event loop reread `equippedWeapon` after each callback. A first-hand callback could select another weapon, causing the old frame's next hand to use the new identity. | Root captures the frame weapon and rechecks identity/readiness for each event. The paired-hand carrier is synthetic, testing reentrancy; dual-wield acquisition is not claimed. |
| Does atomic last-round delivery erase its stream effect? | Applying the new emission predicate to presentation initially made `weaponReady=false` suppress a round already accepted in that frame. | Root's presentation-only context includes the current accepted marker as readiness, while retaining stun/death/domain/reload checks. New ammunition emission remains blocked. |
| Are all non-melee items ammunition attacks? | Actual OP profiles classify40 as detonator,43 as camera,44/45 as goggles and46 as a utility with no attack profile. The old `!isMelee` gun classification also treated the parachute's legacy `MELEE` stat as a melee attack. | `NativeWeaponState` now recognizes actual melee IDs0–15 and the ranged fire kinds. Other roles cannot call fallback fire or spend predicted ammo. `supportsAttack` exposes this capability for UI. No new utility acquisition is invented. Existing parachute deployment and vehicle contextual controls remain separate. |

Utility follow-through is deliberately bounded. The actual browser detonator
uses an edge action independently of gun ammunition; the native network/server
already have a detonation action. Goggles' night/heat view and camera's
photo/flash callback need their own implementation. Blocking their gun fallback
does not claim those utility features are complete.

The owner-supplied original PC `weapon.dat` independently confirms the static
`USE` types for detonator/night vision/infrared and `CAMERA` for the camera.
It also records the parachute under legacy `MELEE` data; that type field alone
does not establish a playable melee attack. Its distinct OP utility profile
and existing native parachute task remain separate from fist hit delivery.
All five original rows and their file hash were checked locally; no original
data is embedded in these source fixtures.

## Executed focused validation

```sh
python3 tests/combat/smoke_native_weapon_roles.py
python3 tests/combat/smoke_native_combat_eligibility.py
python3 tests/combat/smoke_native_combat_interruptions.py
python3 tests/combat/smoke_native_combat_dispatch.py
```

- **357 checks /44 actual OP profiles** compare role, readiness, prediction and
  attack capability. Utility weapons40/43/44/45/46 neither emit ammunition
  attacks nor become fists.
- **10,260 checks /2,560 actual input-expression combinations** cover aim,
  scope/launcher, busy/stun/roll/air and ownership. The native safety layer also
  requires current inventory readiness. The raw browser fire expression leaves
  readiness to its animation controller; the test records that distinction.
- **403,200 comparisons /28,800 frames /96 real R6/native CLP scenarios** cover
  24 profiles, reload/crouch, cancel, death/revival, knock/stun and weapon switch,
  including utility profiles. Native raw timing/state APIs remain compatible.
- **61 actual extracted Renderer dispatch checks** use real CLP and current
  request/control/emission methods at30/60/120Hz for interruption cases. They
  cover new intent, committed pose, stun markers, cancellation, jetpack arm
  capability, unsupported utilities, synchronous callback ownership and the
  final accepted stream round's presentation without granting another shot.
- Three historical Core87 negative controls fail exactly as expected: busy
  request accepted, stunned melee marker forwarded, and old-frame second hand
  using the newly selected weapon. The current complete dispatch gate passes.

Other focused regressions pass: actual melee **31,275 checks /5,040 frames**;
VC melee dispatch **22 checks**; raw `tM` **15,400 frames /123,200 comparisons**;
projectile manager **11 trajectories** plus falloff/stream/occlusion/detonation;
prediction **1,725** and real state reconciliation **1,816** checks with
100–500ms jitter; reload snapshots **42**, real-CLP reload interruption **792**
checks /144 scenarios /65,808 frames; atomic shot delivery; and accepted respawn
dispatch **37 checks**. Full application builds and the complete suite are Root's
separate acceptance boundary.

Existing Renderer extraction runners now include the actual eligibility methods
and source dependency. Their minimal world/state carriers do not replace the
eligibility implementation. The melee replay no longer runs an exporter: it
requires already-prepared owner-local metadata, preserving read-only links.

## Cadence follow-up from the installed Core86 observation

The actual native Colt45 animator emits three rounds in a cold1.1s hold
(233/533/833ms) or four when already aimed (33/333/633/933ms). Core86's server
started its token bucket with one credit. With bounded10ms second-packet
compression, actual Core86 `create/acceptShot` rejects the second event; the
aimed case accepts three and returns an interval warning. Constant latency and
uncompressed delivery are negative controls without that rejection.

Core88 already inherits Core87's bounded full-capacity fresh bucket. The same
actual event times all pass under0ms, constant30ms and1/10/50ms compression.
No additional cadence policy was changed in this pass. Without the installed
run's emission/arrival timeline, its three accepted shots alone cannot identify
whether it began cold or aimed or uniquely explain the displayed warning.

## Evidence and open questions

Source/data SHA256 manifests and expected historical failures stay under
ignored `local-only/research/combat-88`. Original scripts, CLP and data were
only read. The archived expression/R6 probes use ordinary Node tooling; REA MCP
and CUA were unavailable, and no REA capture ID is claimed. An early replay
used Foundation JSONSerialization for exact decimal deltas and shifted strict
marker boundaries; that discarded fixture is explicitly labeled invalid.
The final replay uses the existing exact JSONDecoder carrier.

Retail runtime feel, original skill progression, dual-wield acquisition,
recoil/spread/pellet simulation, complete utility views, special/stealth melee,
retail hit volumes and original damage policy remain open. Passing browser
compatibility and native task ownership does not close those questions.
