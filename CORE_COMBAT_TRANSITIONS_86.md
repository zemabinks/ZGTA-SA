# Core86 combat interruption audit

This pass fixes three native reload transition defects. It does not establish
retail San Andreas timing or complete combat parity. Original game bytes,
archived scripts, generated animation clips and measurements stay local.

## Findings and ownership

| Question | Observation and correction | Evidence / boundary |
| --- | --- | --- |
| Can repeated state restart a reload timer? | A duplicate snapshot used `receiveTime + remainingMs` again. An armour purchase changed the inventory revision without changing the reload; a rejected shot advanced its ACK without changing that reload. All three could extend the estimate. `NativeWeaponState` now identifies an ongoing reload by the existing server `reload.until`, taking the earlier local estimate. It uses that field as identity, without converting server wall time into the native clock. Older snapshots without identity retain the same-revision rule. | Reproduced against actual independent server inventory actions, snapshots and per-peer ACKs using a synthetic catalog. A canceled/restarted reload with a new identity receives a fresh deadline. Completion still requires authoritative state; an expired estimate only requests refresh. |
| Can a pending gun request survive reload rejection? | A pre-muzzle request remained in the animator after reload cancellation and could emit when readiness returned. New `NativeFootAnimation.beginReload()` cancels pending gun input before entering reload. Both production Renderer reload sites use it. Raw `reload()` remains unchanged for the archived animation contract. A genuinely held trigger may resume through current held input; a released request cannot do so. | Real native CLP execution covers standing/crouching, held/released input, canceled reload, weapon switch, fresh later press and weapons with/without a dedicated reload clip. Direct archived R6 probes also retain pending input through raw reload; this is a native inventory-task ownership repair, not a claim that archived R6 behaved differently. |
| Can rejected HTTP dispatch still show a reload? | `NativeGameplayClient.perform` can reject inline when offline/busy. The old VC called it before starting feedback, so rollback ran before the animation existed, then animation/audio/status started anyway. Root's VC integration now records synchronous rejection and checks current input/peer ownership before presenting. Delayed rejection still cancels the existing reload. | The extracted current VC method runs with the actual GameplayClient offline gate and real weapon-state model. Controlled delayed callback carriers exercise accepted, rejected, unknown and old-peer completions. No listener/service is started. |

## Executed gates

```sh
python3 smoke_native_combat_transitions.py
python3 smoke_native_combat_animation.py
python3 smoke_native_reload_dispatch.py
python3 smoke_native_ammo_reconciliation.py
python3 smoke_native_shot_delivery.py
python3 smoke_native_gun_animation.py
python3 smoke_native_respawn_dispatch.py
```

- Reload snapshots: **42 checks** at30/60/120Hz, including duplicate, unrelated
  revision, rejected-shot ACK, completion, fresh peer and replacement identity.
- Real CLP: **792 checks,144 scenarios,65,808 native frames** at30/60/120Hz;
  pistol, heavy pistol, sawed-off, rifle, launcher and stream definitions.
- Extracted VC dispatch: **35 checks**, including inline rejection, deferred
  results, repeated requests, unknown outcome, nonce replacement, traversal,
  full/no-reserve/melee restrictions and satchel detonation's separate action.
- Existing prediction engine: **1,725 checks /1,600 frames**; real weapon-state
  reconciliation: **1,816 checks /1,600 frames**, with100–500ms jitter,
  duplicate/first ACK, rejection, HTTP/WS, reload, switch, timeout and reconnect.
- Existing shot delivery passes atomic readiness, twin/catch-up markers, empty,
  stale, reload and fallback-duplicate cases.
- Unchanged archived `tM` gun contract: **15,400 frames /123,200 comparisons**,
  including streams, twin shots, readiness pause, cancel/restart and breakout.
- Respawn dispatch: **37 checks** execute the actual dead-attack method,
  `finishRespawn`, vitals/respawn callback assignments and native health ACK
  methods. Request, rejection and unrelated healing cannot teleport or exit a
  vehicle; a matching accepted acknowledgement does so once. Coverage includes
  duplicate/foreign ACK, retry, legacy synchronous callback, offline/busy input,
  on-foot ownership and a callback that disconnects/replaces its peer. Existing
  bindings/dispatch remain at **3,803 passing checks**. The death vitals callback
  still clears held input; that is separate from an accepted respawn's vehicle
  and world reset. Full HTTP/WS health transport has a separate Root-owned gate.

Each new gate snapshots the tested source and records SHA256 hashes and whether
live files still match. Reports are under ignored
`local-only/native-physics/tests/{combat-transitions,combat-animation,reload-dispatch}`.
The before-fix timer and animation failures are retained there separately.
The archived direct probes are ordinary Node tooling evidence under ignored
`local-only/research/combat-86`; they have no REA capture ID. REA MCP was not
available to this worker. No retail executable or unlicensed reconstructed
implementation was executed or imported.

## Related review and remaining limits

Queued melee is already bound to the selected weapon and canceled with its
task; gun shot delivery updates inventory readiness before the next animation
substep. Their existing event/cadence/ACK contracts are preserved. A potential
missing-fists-catalog issue was checked against the actual owner-local catalog;
it contains weapon0 and was not a reproduced defect. Root separately owns
fresh-world effects, hit/health prediction and its regression evidence.

Server reload duration and damage remain independent self-host policies.
Retail runtime comparison, skill progression and dual-wield acquisition,
precise recoil/spread/pellet behavior, utility/drive-by paths, full melee special
moves and retail bone contact volumes remain unresolved. Original data/static
agreement and browser regression results do not close those gaps. These tests
make no Simulator UI, physical iPhone/controller, FPS or retail-feel claim.
