# Native inventory acknowledgement contract

Native clients negotiate `inventoryAck:1` together with `nativeInventory:true`
in their WebSocket `hi`. The server's `hello` returns `inventoryAck:1` and a new
`inventoryConnection` correlation ID for that WebSocket. The initial inventory
has `ack:{connection,processedShot:0}`. Repeating `hi` does not reset the ID or
watermark and cannot downgrade an already authoritative native connection.

Every negotiated native shot carries `c:connection` and a reserved positive
safe-integer `s`. The following hit carries the same values. The server settles
every new sequence, including rejected shots. An already processed or skipped
lower sequence can never mutate inventory later. All native shot rejection
paths return the current authoritative inventory and watermark; a wrong
connection or malformed sequence returns the current watermark without
advancing it. Each inventory result may also include
`result:{sequence,accepted,reason}` for diagnostics.

Inventory snapshots carry `ack:{connection,processedShot}` captured in the same
synchronous server operation as their state. This includes accepted/rejected
shot replies, initial inventory and action broadcasts. If several connections
share an authenticated player, broadcasts have the recipient's own watermark.
Connection IDs and watermarks are ephemeral and are never persisted as ammo.

HTTP refresh and action requests use `X-ZGTA-Inventory-Connection`. The ID must
identify the requesting authenticated player's exact ready, open native peer.
A stale, closed, foreign or invalid ID returns409; an action is not executed.
Actions revalidate the connection after receiving their asynchronous HTTP body,
so disconnecting during upload cannot mutate state using an expired context.
Successful `/api/local/state` and `/api/local/action` responses include the
matching watermark inside `weaponInventory`. Calls without the header retain
the legacy unacknowledged response and must not overwrite sequenced native
predictions. Legacy browser/native clients without negotiation retain their
no-sequence compatibility path.

The native consumer must keep authoritative ammo separately from predictions,
reserve the sequence before consuming locally, and display authoritative rounds
minus only predictions above `processedShot`. Rejected shots can advance the
watermark without increasing the inventory revision. New socket identity resets
prediction synchronization; uncertain writes/timeouts require an acknowledged
resync or reconnect rather than restoring guessed ammo. The server portion
alone does not implement these native client rules.

## Validation

On2026-11-15, all of the following passed against isolated saved state:

- `node smoke_inventory_ack.js`: real backend HTTP/WebSocket handlers with
  synthetic transports; accepted and every rejected/duplicate shot path,
  immutable earlier snapshots, nonce-bound hits/refresh/action, multiple peers,
  delayed-body disconnect, reload completion, reconnect and legacy no-s. The
  real WebSocket upgrade, masked input decoder and output-frame serializer are
  also exercised through an in-memory socket, including forced replacement of
  an old socket for the same player.
- `node smoke_weapon_cadence.js`: canonical timing, bounded catch-up, replay,
  reload/switch and accepted-shot hit binding.
- `node smoke_weapon_streams.js`: authoritative area validation and existing
  mission-fire suppression over actual SCL2 queries with synthetic geometry.
- `node smoke_native_server.js`, `node smoke_weapon_inventory.js`, and
  `node smoke_fire.js`: existing inventory, projectiles, ownership, persistence
  and fire-dispatch rules.

These tests start no listener or production service. Combined application,
HTTP-header delivery and actual network-latency acceptance remain separate
integration gates for the native client changes.
