# Vehicle completion and condition publication

## Core184 condition and lifetime ownership

Registered vehicle rows now publish their authoritative condition consistently.
Normal, pending and terminal parked reports follow the current registered hull
only within the same vehicle and driver-claim lifetime. Later collisions cannot
be reversed by a retained exit snapshot, and a replacement cannot borrow that
old stand-in. Empty unattended predictions cannot clear accepted damage; actual
paid repairs still create their correct fresh condition.

Three retained previous-source witnesses fail. Focused handler, real loopback
HTTP/WebSocket and complete native URLSession receiving cases pass, including
baseline, queued driving, parking, later motion and replacement. Native product
inputs remain identical to the accepted Core182 SDK/App. The complete Core184 selected physics/audio/transport source chain passes.
Core185 resource-specific checks pass separately. No new rendered App, browser,
hardware or original-retail accuracy is inferred from these transport cases.

NPC population preparation and server admission now require structurally matching
prepared mesh/atlas-header/skeleton families. Newly generated profiles bind the
index, navigation and selected family files to source hashes. Explicit model
selection requires every requested civilian family. Existing owner-local aliases
remain supported. Authored malformed-family, CLI and actual loader tests pass;
retained original-resource admission also passes without altering the sources. A separate offline original-world task probe
also runs the existing independent NPC tasks over original navigation and
collision; its packets are in memory, without a rendered client.
These checks do not decode pixels, reconstruct bind poses, sample animations or
establish a GPU draw. Legacy profiles validate current families without a
historical source-hash guarantee.

The cumulative local/server vehicle-damage ledger, full vehicle weapon damage,
original population groups/zone/time density, client-wide model availability,
complete NPC/traffic/police AI and retail gameplay accuracy remain incomplete.
Original assets, derived tables, measurements, recordings and private Git
ancestry remain local. Only independently authored source and these qualified
implementation records are published.

## Earlier completion work

Fatal vehicle exit could retain a healthy parked hull. The actual controller calls `Renderer.exitVehicle` before `NMP.sendExit`; the wrecked Renderer reports fatal health during that first call. Core109 pruned the dead driver's claim before applying its final parked hull. A private replay with genuine nearby entry, accepted ACK, driver claim and slot11 verification still failed the original `Exit lost authoritative wrecked hull` assertion. Core109 remains unchanged.

Core110 retains a separate terminal completion after releasing occupancy immediately:

- It is tied to the exact transport, inventory connection, vehicle incarnation, owner/garage slot and unchanged body snapshot. It grants no driver, passenger or reservation rights and cannot raise hull health.
- Only one on-foot release can complete it. The finite body pose uses the existing 16 unit first-driver envelope. The existing `lastSeen + 10s` deadline never extends. Duplicate health and rejected queued driver frames grant no authority. Ordinary foot, respawn, disconnect, replacement/body change, or a new driver/passenger claim invalidates completion.
- Denied explicit registry-ID fields cannot publish parked row33/vehicle row35 ghosts. Legitimate pending browser get-in and ID-omitted free-play stand-ins remain supported; passengers use row34. Subsequent normal native foot reports leave the sole same-ID parked registry vehicle intact.

The wreck/water fixtures now obtain and verify actual native entry before driving; water reentry uses the body's current position. Original hull, armour, death-count, yaw and acknowledged-respawn expectations are retained. Hull health is monotonic; the opaque damage string retains existing bounded live-report validation, without a new per-panel monotonicity claim.

| Check | Result |
| --- | --- |
| Original Core109 genuine-claim wreck replay | FAIL: original hull assertion; proves the production defect separately from missing entry in the older fixture. |
| `node tests/vehicles/smoke_native_terminal_vehicle.js` | PASS: 303 checks / 17 real ephemeral HTTP/WebSocket scenarios; source unchanged. Both health/exit orders, queued/duplicate packets, row33/35, pending/free-play, deadline, malformed/repair/range reports, and reconnect/respawn/incarnation/new occupant fences. |
| `python3 -B tests/vehicles/smoke_native_wreck_backend.py` | PASS: 7 Swift + 15 backend checks in 377.46s; actual NMP self-host adapter, accepted claim, fatal/parked/respawn sequence; source unchanged. |
| `python3 -B tests/movement/smoke_native_water_backend.py` | Initial corrected-entry attempt hit its 600s compile bound before runtime and is retained. Separate unchanged rerun PASS: 11 Swift + 21 backend checks in 438.18s, source unchanged. |
| Original Core109 full aggregate | Still running: 39/45 cases passed as of 2026-11-17T18:00:55.864969+00:00. Original failures remain recorded. |
| Separate Core109 health rerun | PASS in 179.12s at the same 600s bound; full actual NMP HTTP/WS and 30,520 calculation checks, 848 source hashes / 202 App inputs unchanged. Original timeout remains failed. |

Other initial aggregate failures remain distinct: bike-exit compile timeout; exit-runtime fixture missing the new `cameraRay` dependency; exit-heading fixture bypassing entry before checking parked yaw. Their assertions/budgets were not weakened. Further focused compiler runs await Root's optimizer-idle notice.

Evidence: `local-only/research/terminal-vehicle-110`; original aggregate/replay under Core109 `local-only/research/core-gate-109`. Test sandboxes protect prior checkpoints and current runtime source. Fixtures use authored data and ephemeral loopback only; no owner archive dependency, converters, rendered browser, Simulator, phone or production listener. These transport bounds are independent-server policy, not retail physics or 1:1 gameplay verification.
