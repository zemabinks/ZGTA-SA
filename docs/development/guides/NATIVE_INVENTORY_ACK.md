# Native ammunition acknowledgement protocol

Native predictions now retain an authoritative inventory baseline separately
from pending local muzzle events. An older HTTP refresh or the first shot's
reply cannot restore a later in-flight round.

The native WebSocket advertises `inventoryAck:1`. Its hello announces
`inventoryAck:1, inventoryConnection:<nonce>`, then each inventory snapshot has:

```json
{"revision":12,"selected":28,"weapons":[],"reload":null,
 "ack":{"connection":"opaque-per-WebSocket-nonce","processedShot":23}}
```

The nonce is correlation data, not a credential. The server binds it to the
ready authenticated peer. `processedShot` is the highest fully handled sequence,
including rejected shots. Older/skipped/duplicate sequences cannot be charged
later. Both `shot` and the corresponding `hit` carry the same `c` nonce and `s`
sequence; native melee hits carry `c` without consuming a shot ticket.

Every native GET `/api/local/state` and POST `/api/local/action` sends
`X-ZGTA-Inventory-Connection`. The server captures that peer's watermark and
inventory atomically; stale/foreign headers receive409. Missing-header responses
remain available to older browser clients, but cannot overwrite the sequenced
native inventory.

## Native integration

1. `network.onInventoryConnection` sets both
   `gameplay.inventoryConnection` and `weapons.setConnection(nonce)`. A repeated
   hello with the same nonce is idempotent. Closing/replacing the socket clears
   synchronization. Snapshots cannot negotiate a nonce by themselves.
2. Reserve `network.reserveShot()` before consuming an animation round. Pass the
   ticket to `NativeWeaponShotDelivery.deliver`, then forward the identical ticket
   through its emission closure into `network.sendWeaponShot(...ticket:)`.
3. `NativeWeaponState.apply` accepts only the current connection, a nondecreasing
   revision and a nondecreasing processed-shot watermark. It replaces the
   authoritative baseline, removes acknowledged predictions and subtracts the
   remaining weapon-specific predictions. A rejected shot restores only its own
   predicted round. Selection/purchase/reload snapshots follow the same path.
4. `weapons.canFire` drives animator readiness. The delivery boundary publishes
   readiness synchronously before the next hand/fixed substep emits. Native
   muzzle events have no second display-frame/wall-clock rate gate.
5. `beginReloadRequest()` blocks input while the HTTP request is in flight.
   Apply a successful response before `finishReloadRequest(id:succeeded:)`.
   Pass `true` for a confirmed success, `false` for a definite HTTP failure and
   `nil` for an unknown transport outcome. An unrelated old refresh cannot clear
   a local reload request. Countdown expiry requests a refresh but never invents
   reload completion; only a completed authoritative snapshot clears it.
6. `onNeedsResync` calls `network.requestInventoryResync()`. Missing shot ACKs or
   reload responses older than2seconds, an uncertain write, invalid clocks or a
   full128-round queue freeze further predictions. Displayed ammunition does not
   increase while waiting for uncertain results. Reconnect establishes a fresh
   nonce and authoritative baseline; repeated resync requests are idempotent
   until the first acknowledged inventory arrives.
7. Old URLSession receive/send completions are checked against the exact socket
   again on the main queue. They cannot mutate or reconnect a replacement socket.

Production native firing requires acknowledgement negotiation. The explicit
`allowLegacySnapshots:true` initializer is retained only for historical offline
unit fixtures; the server initializer uses the safe default. This is not a
claim that unacknowledged older servers can reconcile optimistic ammunition.

## Verification

- `python3 tests/combat/smoke_native_ammo_reconciliation.py`: the promoted prediction engine
  and actual `NativeWeaponState`/delivery boundary, including3200 deterministic
  frames with100–500ms delays, rejection, duplicates, reordered HTTP/WS snapshots,
  selection, reload, timeout, uncertainty, bounds and reconnect.
- `python3 tests/network/smoke_native_inventory_wire.py`: real Swift URLSession HTTP and
  WebSocket clients against a bounded ephemeral delayed peer; exercises the
  HTTP header, first-ACK preservation, reload, selection, stale responses across
  reconnect and sequence restart. It uses no saved player data.
- `python3 tests/network/smoke_native_wire.py`: the existing native protocol regression now
  negotiates ACKs, reserves tickets and verifies nonce-bound gun/melee hits.
- `node tests/combat/smoke_inventory_ack.js`: the actual self-host backend's separate ACK,
  authentication/header, duplicate/rejection and legacy-browser coverage.

These gates verify protocol/inventory correctness. They do not establish retail
GTA combat parity, network latency compensation or authoritative hit-geometry
accuracy. Game files and test outputs remain local-only.
