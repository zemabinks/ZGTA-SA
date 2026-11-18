# Authoritative foot-position resume candidate

Core114 implements this independent self-host protocol in the server and native app. Core113 remains unchanged. The native adapter is documented in `CORE_NATIVE_PLACEMENT_114.md`; engine accuracy and installed-app validation are separate from the protocol tests below.

## Behavior

An opted-in connection starts at its last admitted ordinary foot anchor, or a still-valid server placement intent, with a fresh connection nonce and revision zero. New guests retain `[1480, -1738, 13, 0]`. Heading in the saved record and `hello.spot[3]` is GTA radians; `tp.h` remains degrees, preserving the separately verified Core113 unit repair.

The anchor belongs to the account. It contains position, heading, dimension and source metadata; it contains no role, body authority, health, ammunition, queued actions or transport sequence. Disconnect and reconnect continue to release driver/passenger/coupling claims. A driver resumes at the last verified foot anchor, which may be far from the parked vehicle after a long journey. This does not compute safe egress beside the current hull or grant another entry.

A foot report is eligible only with the exact current placement envelope, living health, ordinary on-foot state, finite bounded coordinates, appropriate owned-home dimension and covered SCL2 ground beneath it. The check uses the existing bounded downward query; it excludes its above-input floor results. This is a conservative ground admission rule, not capsule clearance, general teleport detection or a retail save-system reconstruction. No original physics constants changed. Unknown collision coverage retains the previous anchor.

Server-authored home entry/exit/visit, pilot placement, passenger corrections and explicit respawn each advance a placement revision before sending a command. The persistent intent is committed in memory before the command; a queued old `me` is rejected before actor changes, command/chat handling, terminal reports or other `me` side effects. Verified current foot clears the intent. Home intent must still match current owned-home metadata; pilot intent must match a current runway. Passenger body-origin corrections fence the live command but are not accepted as safe reconnect anchors.

TP clears live actor state and revokes current vehicle/seat/coupling claims without moving, repairing or replacing their hulls. The first new position is a baseline, so the teleport does not earn job-distance progress. Repeated unchanged foot reports do not perpetually schedule saves. Persistent records are normalized both on load and save. Existing atomic `.partial` + rename/debounced save remains; abrupt OS failure before a scheduled flush can lose the newest few hundred milliseconds. This is not a synchronous durability guarantee.

Saved health zero remains zero on restart, and `lastDeath` survives to retain the respawn cooldown. Placement alone never heals, consumes/refunds ammunition or replays shots. Older saved data without a placement record uses default spawn. The zero-health load correction applies globally; legacy live health-report behavior is otherwise retained.

## Negotiation and compatibility

Strict position resume is enabled only by the **first** `hi` on a fresh peer:

```json
{"t":"hi","nativeInventory":true,"inventoryAck":1,"healthAck":1,"positionAck":1}
```

Existing optional fields such as `couplingAck` remain compatible. Native inventory and health ACK prerequisites are mandatory: a legacy health `me` can implicitly revive a dead actor, so strict resume must not negotiate without sequenced health ownership. A late/duplicate `hi` cannot opt in, downgrade, change nonce or reset placement state.

A fresh strict hello includes the existing `inventoryConnection` and:

```json
{"positionAck":1,"placement":{"connection":"<inventoryConnection>","revision":0},"spot":[125,140,20,0.75]}
```

After applying that placement, every strict `me`, including foot, driver, passenger and exit reports, carries:

```json
{"placement":{"connection":"<same nonce>","revision":0}}
```

Each later strict TP has `placement` with the incremented safe integer revision. Missing, stale, future, fractional, negative, wrong-nonce and malformed envelopes reject the whole `me` before side effects. The server does not infer that receiving an untagged report means a teleport was applied. Duplicate hello preserves the initial hello's original spot/revision, even after a later TP; it must not rewind the client. Revision exhaustion rejects relocating actions/respawn before partial mutation; reconnect establishes a new namespace.

Legacy clients receive the existing fixed hello spawn and untagged TP, require no position field and do not write strict foot anchors. Their existing same-peer old-`me`/TP ambiguity is explicitly retained. A remembered strict anchor may therefore predate intervening legacy play. There is no safe server-only inference that can repair that ambiguity for an unchanged client.

## NativeMP / GVC integration contract

Core114 implements the following contract. These requirements also describe what another compatible client must do.

1. Add `positionAck:1` to the initial self-host `hi` alongside the already supported inventory and health ACK flags. Do not add it late. Expose a read-only negotiated capability and applied-placement namespace; preserve old-server behavior when the capability is absent.
2. On a fresh valid hello, require matching `inventoryConnection`, `positionAck:1`, revision zero and a finite valid spot. Establish a *placing* barrier; preserve the existing fresh-baseline/cache/input/world resets. Apply the authoritative spot once (hello heading is radians). Only after the synchronous placement callback returns, with the same current socket generation/nonce, mark the revision applied. Do not send `me` from within placement cleanup. Fail closed/reconnect if a server advertises strict mode without a valid envelope.
3. Same-nonce duplicate hello must not apply its cached initial spot/revision again. Existing health/inventory handling may proceed; neither placement, role state nor action counters rewind.
4. For strict TP, require the current nonce and a strictly newer safe integer revision, finite coordinates and heading. Ignore stale/duplicate/wrong-transport commands. Hold the placing barrier during cleanup/teleport and commit the new applied revision only after the callback returns for that same generation. `tp.h` converts **degrees to native radians once**. No client teleport or latest locally reported pose overrides a legitimate server command.
5. Every self-host `me` producer must echo the **applied** envelope: normal `sendPosition`, explicit driver/foot exit, passenger exit and any other direct `sendOriginal` path. Gate writes while placing or before readiness. Clear the envelope on disconnect/transport replacement. No old position or action is queued/replayed on reconnect. Existing inventory/health/coupling namespaces stay independent, even though they share the connection nonce.
6. Extend GVC teleport cleanup to a current **driver as well as passenger**. Clear current vehicle/UI/radio and pending boarding/working controls, discard the owned physical body/authority through the existing server-revocation/reset path, and teleport at the command target. Do not use the ordinary parked exit path to manufacture an exit offset or send a stale hull/foot report: the server already revoked occupancy. Preserve fresh-world/nonce cleanup callbacks and their reentrancy guards. Core114 extends the older passenger-only cleanup to driver ownership as well.
7. Strict accepted respawn sends a fenced default-spawn TP **before** the sequenced health ACK. `onRespawn` still completes exactly once only for its accepted pending health sequence, but in negotiated mode `finishRespawn` must perform presentation/reset cleanup **without its current hardcoded default teleport**. An ACK arriving after a newer home/pilot TP must not move the player back. Rejected/duplicate/unrelated health ACKs must never teleport. Legacy/original-world paths retain their current policies. Keep the TP and health callbacks guarded against a disconnect or namespace change during either callback.

The server orders its own sends. It does not claim that TP/ACK have already reached or been applied by the client. The adapter needs actual URLSession/dispatch tests for fresh and duplicate hello, all `me` producers, TP during driver/passenger ownership, callback reentrancy/disconnect, reordered/late health ACK presentation, and physical Home/foreground acceptance before enabling the feature in a released App.

## Validation

Run the independently authored gate from this source directory:

```sh
node smoke_selfhost_position_resume.js
```

The default gate passes **737 checks in 19 scenarios**, including all seven actual TP producers across seven angle inputs. It executes the actual backend constructor, guest HTTP route, upgrade/Peer framing, actions, collision reader, inventory and persistence. All catalogs, SCL2 floors, sockets, timers, process IDs and filesystem writes are authored/virtual. No listener, service, live save, original data, compiler, browser, Simulator or phone is used.

An optional read-only comparison against an accepted Core113 source checkout adds seven historical checks:

```sh
node smoke_selfhost_position_resume.js --baseline /absolute/path/to/ZGTA-SA-core-113
```

That run passes **744 checks** while positively reproducing the actual old stale-`me` ambiguity, default reconnect spawn and saved-health-zero-to-one load defect. The source hashes are recorded. This negative control is distinct from runtime browser or physical testing.

The default source-only gate emits reports under ignored `local-only/research/position-resume-114/`. Preserve the baseline report separately before a default rerun overwrites `report.json`. No copied App, assets, libraries, accounts or player saves are required. Source is independently written AGPL code.

## Remaining limits

- The Core114 native adapter and actual URLSession tests are implemented. Broader installed gameplay and retail comparisons remain separate acceptance scopes; Core113 App behavior is unchanged.
- A covered downward ground query does not prove a clear full character capsule, navigable slope or safe egress beside a moved hull. Dynamic/custom-object surfaces are not admitted by this static-ground path.
- A long drive may resume far from the vehicle at the prior foot anchor; vehicle/job identity persists and the normal entry-distance/access checks still apply.
- Trusted catalog placement intents preserve home/pilot semantics. They are not newly certified by runtime capsule clearance.
- Existing server movement trust, legacy live health semantics, debounce/crash durability and independent-world rules remain. No retail or full browser 1:1 claim is made.
