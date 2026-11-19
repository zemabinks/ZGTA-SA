# Native authoritative placement adapter

Core114 implements the opt-in native side of the independent server protocol in `docs/research/network/CORE_POSITION_RESUME_114.md`. Core113 remains unchanged. Focused source and transport regressions exercise the protocol below. Full gameplay and retail parity remain separate acceptance scopes.

## Runtime interface and ownership

`NativeMultiplayerClient` exposes read-only properties:

- `positionAcknowledgements: Bool`: strict placement was negotiated on this peer.
- `isPlacing: Bool`: a validated authoritative pose is awaiting synchronous owner completion.
- `appliedPlacementRevision: Int?` and `placementConnection: String?`: the last **applied** envelope, not a newly received/pending revision.

The existing `onTeleport` callback remains `(SIMD3<Float>, Float?) -> Void`. For strict placement it runs with `positionAcknowledgements == true`, `isPlacing == true` and `isReady == false`. The callback must synchronously apply the server pose and discard revoked driver/passenger/UI/physical ownership. A missing strict callback fails the transport instead of pretending that a pose was applied. This requirement does not affect legacy or original-world adapters.

The network client clears pending seat/boarding correlation before the callback. It retains vehicle-entry request numbers across a TP on the same socket, so delayed positive or negative entry replies cannot match a new request. A full disconnect/new transport still resets that namespace. Driver body/UI/radio cleanup belongs to GVC/Renderer, rather than a fabricated ordinary exit/parked report.

No new App source dependency is required: the independently authored Foundation `NativePlacementSession` resides in `NativeMultiplayerClient.swift`, alongside existing protocol helpers. Existing concatenated wire fixtures therefore compile the actual owner without adding a mock or hidden dependency.

## Message behavior

The self-host initial `hi` advertises `positionAck:1` alongside native inventory/health ACK support. Original-world hello and legacy SA-MP adapter behavior are unchanged.

A fresh strict hello requires the matching connection nonce, revision zero, four finite non-Boolean pose numbers, and valid matching health-ACK/life prerequisites. Nonces match the server's bounded base64url form; revisions are nonnegative JavaScript-safe integers. Coordinates/headings are bounded by the server placement record's domain. `hello.spot[3]` is radians; TP heading is degrees and converts once to native radians. A server advertising malformed strict placement fails the transport before publishing the new namespace callback or applying a pose.

The placing barrier is established before namespace/world-reset callbacks. A transaction commits only after its synchronous pose callback returns and the same task, transport generation and nonce remain current. Reentrant disconnect/replacement prevents commit. A same-socket hello with a different nonce now fails the transport before negotiating anything; the older implementation's shot-sequence guard already refused the changed nonce, but only reported a status while leaving that transport ready. It did **not** successfully mutate the nonce. A fresh socket remains the legitimate namespace transition.

Same-nonce duplicate hello never reapplies its cached original spot, resets a newer TP revision, upgrades a previously legacy connection or downgrades strict mode. A strict TP accepts only a finite pose with the current nonce and a newer safe revision. Stale, equal, wrong-transport, wrong-nonce, Boolean, nonfinite or malformed commands do not apply.

The sole self-host `send` serialization boundary stamps the applied envelope on every `me`: ordinary foot, driver, swim/flight variants, explicit driver exit, passenger position and passenger exit. Producer-supplied envelopes cannot override it. Positions are refused before readiness or during placement. `sendPosition`, `requestEnter`, shot reservation and `sendExit` observe the same temporary readiness barrier, so an exit attempted during cleanup cannot rewrite the local parked vehicle cache or emit parked/foot reports. No old position/action is queued for replay. Disconnect clears the placement owner along with the existing health/inventory/remote baselines.

Strict server respawn sends TP before health ACK. The ordinary accepted `onRespawn` callback still occurs once for the pending health sequence; it does not itself teleport. The GVC negotiated branch performs presentation/reset cleanup without its legacy hardcoded default teleport. In particular, a first respawn ACK arriving after a newer home/pilot TP must retain that newer placement. Legacy and original-world respawn policies remain separate.

## Focused validation

```sh
python3 tests/network/smoke_native_placement.py
python3 tests/network/smoke_native_placement_wire.py
node tests/server/smoke_selfhost_tp_units.js
node tests/network/smoke_selfhost_position_resume.js
```

- **215 actual Foundation checks** execute the extracted production placement and seat owners: strict parsing/Boolean rejection, numerical limits, heading units, pending/applied separation, duplicate hello, stale/replaced/reset transaction tokens, revision extremes and seat correlation. A separate control deliberately uses full reset on the same peer to reproduce the initial Core114 adapter draft's request-ID alias; it is labeled **draft regression, not historical Core113 behavior**.
- **160 actual URLSession checks**, 12 disposable connections and 49 native packets: all outgoing position producers, authoritative central stamping, cleanup attempts through the actual driver/passenger send methods, malformed/old transport packets, namespace and pose-callback disconnects, changed-nonce/missing-owner fail-close, legacy fallback, and first/duplicate/rejected respawn ACK ordering. Held old positive and negative entry ACKs cannot clear, complete or grant the newer post-TP request; its current ACK succeeds.
- **699 TP-unit checks**, 85 actual method cases: all 84 previous six-producer legacy cases remain, plus the new strict respawn producer, including placement-before-ACK and duplicate suppression. Historical four-producer unit-negative support remains (`--source /path/to/old/selfhost_backend.js --expect-historical-mismatch`), with 52 expected mismatches across the original 84 cases.
- The separate **737-check/19-scenario server gate** covers actual independent backend construction/actions/persistence with virtual files/sockets/timers and authored collision data. It exercises all seven TP producers across seven headings, reconnect/dead-health persistence, stale nonce/revision rejection, home/pilot intent and conservative role revocation.

The URLSession gate's Node peer intentionally authors valid/malformed protocol packets and delayed replies; it is not evidence of production authority or a rendered world. Reports and immutable source hashes are written only under ignored `local-only/research/native-placement-114/`. The actual-backend health compatibility gate remains separate (`python3 tests/combat/smoke_native_health.py`), using its synthetic account/catalog and temporary server data.

Copied-backend fixture setup lists now include the new required `player_placement.js`. Four headless native backend fixtures (health, recovery, coupling authority and the existing owner-resource skin fixture) explicitly record/validate placement callbacks before connecting. These recording owners are protocol test adapters, not claims of rendered pose or physical egress. The owner-resource skin fixture was not run as part of this focused scope.

## Limits

- The public regressions use independent fixtures and disposable transports. They do not require original game data or a physical device.
- Native GVC/Renderer cleanup has separate extracted-owner regression coverage. Rendered and physical behavior still requires ordinary installed-app testing.
- The server's last verified static-ground foot anchor remains conservative. It does not solve current-hull safe egress, dynamic/custom-object ground, full capsule clearance or broader movement validation.
- This is the independent self-host protocol. It does not assert Rockstar retail save behavior or a complete browser/retail 1:1 port.
