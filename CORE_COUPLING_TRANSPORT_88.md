# Native coupling transport

`NativeMultiplayerClient` now negotiates optional coupling acknowledgements
without changing the existing inventory/health/general-ready handshake.
All new protocol types remain in that file, so the Foundation-only wire
fixtures do not acquire another source dependency.

## Integration API

- `NativeCouplingLink { parent, trailer, kind: String }` is topology only.
- `onCouplings: (([NativeCouplingLink], Int, String) -> Void)?` receives links,
  revision and the current inventory connection nonce after stored state updates.
- Read-only `couplingAcknowledgements`, `couplingRevision: Int?` and
  `couplingLinks` expose capability and the validated current baseline.
- `requestCoupling(parent:trailer:kind:completion:) -> Bool` queues a request
  only when both general readiness and a negotiated topology baseline exist.
  `nil` trailer is an explicit detach. Invalid/offline/unsupported requests
  return false inline, allocate no sequence and invoke no completion.
- `sendPosition(...kit:vehicleWork:paused:)` adds optional driving `w` clamped
  to0...2500. Pedestrian packets omit it. `sendExit(...vehicleWork:)` adds that
  optional working value to the parked payload and local parked row. A nil
  value preserves existing packet omissions.

Root owns the Renderer/VC mapping and physical joints. `onInventoryConnection`
remains the namespace reset signal. Apply received topology before considering
the matching request completion; a rejected request can be handed to the
physical helper's rejection/backoff path. Driver pose and trailer `vmove` can be
sent immediately before `requestCoupling`; the actual wire test verifies order.

## Protocol guarantees

The initial `hi` adds `couplingAck:1`. Only the first validated `hello` selects
this optional capability. Duplicate same-nonce hellos cannot reset sequence,
topology or capability. A server that omits it remains compatible and never
receives hitch requests. A baseline may arrive before the ordinary world
baseline; it does not prematurely mark gameplay ready.

Requests use their own contiguous sequence, scoped to the inventory nonce.
Serialization and validity checks happen before allocation. Up to128 pending
requests are retained. A transport failure or fresh connection discards uncertain
requests without completion or replay. The server decides ownership, geometry,
cooldown and acceptance; the client does not create a speculative joint.

Topology validation checks safe nonnegative revision, bounded IDs/array size,
valid kinds, unique outgoing/incoming links, no self/cycle, maximum two-link
chains and no tow chain mixed with parent/child links. Canonical sorting makes
equal-revision reordered content idempotent. Contradictory equal-revision,
stale-revision, malformed and wrong-nonce packets are ignored, including their
ACK. No vehicle-row field is invented for topology.

ACKs require a real Boolean result, issued exact sequence, monotonic processed
watermark within issued bounds and the current nonce. Each pending callback is
removed before external callbacks run. State delivery then rechecks the same
socket, transport generation and nonce before a completion may run. A callback
that reconnects cannot complete an action against its replacement world.

## Executed tests

```sh
python3 smoke_native_coupling_wire.py
python3 smoke_native_wire.py
```

The new actual URLSession fixture passes **40 checks**, traversing three peer
namespaces and five hitch requests. It covers old-server compatibility;
capability without baseline; baseline before general readiness; invalid requests
without sequence holes; malformed, cycle, duplicate, mixed-kind and oversized
topology; stale nonce/revision; invalid ACK; accepted/rejected/duplicate ACK;
equal-revision reordering; duplicate hello; reentrant disconnect before ACK
completion; fresh sequence1; no uncertain replay; and working-value clamping,
omission and pose-before-hitch ordering.

The existing actual native wire fixture also passes unchanged. Additional
health and inventory compatibility results are recorded in the local evidence
directory. This is protocol validation using controlled loopback peers, not
vehicle-joint or retail runtime verification.

For a controlled negative, `--negative-no-callback-guard` removes only the
post-state-callback boundary check from a private compiled snapshot. The fixture
then fails because an old request completes after the new peer owns the world.
The live source is never changed. This is a regression sensitivity check, not
a historical retail or client-build observation.

Source hashes, positive output and the expected negative failure are retained
under ignored `local-only/research/coupling-wire`. No original assets, saved
players, production ports, microphone or external service are used. Loopback
listening requires the test environment's local network permission.
