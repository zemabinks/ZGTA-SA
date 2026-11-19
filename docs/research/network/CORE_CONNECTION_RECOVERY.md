# Native multiplayer recovery

The native transport now reconnects after socket receive/send failures and bounded handshake/inbound timeouts. Intentional disconnect is terminal. Recovery uses one current transport generation; old callbacks cannot close, unlock, or continue receiving on its replacement.

`NativeMultiplayerClient` exposes `state` (`stopped`, `connecting`, `reconnecting`, `ready`), `isReady`, `onConnectionState`, `setApplicationActive(_:)` and `tickConnection(now:)`. An internal 250 ms main-queue timer also drives recovery while game frames are unavailable. The injected clock and explicit tick must share a monotonic uptime basis. Tests can inject a URLSession/clock and disable the automatic timer.

After an established valid hello, a lost connection waits 500 ms before retry. Failed attempts wait 2 s, 4 s, 8 s, ... up to 60 s. A current peer gets 10 s to complete its hello/inventory/world baseline and 10 s without valid inbound control/baseline traffic before expiry. Pings run every 2 s. A tick gap exceeding 1 s resets timeout clocks; becoming active grants a fresh bounded grace period. Inactive apps do not start retries or expire connections. These retry/watchdog constants follow inspected public browser control flow; the independent native baseline and lifecycle policy is explicit.

Ready requires all three current-generation messages: negotiated inventory hello, a matching ACK with a complete valid inventory, and a valid full world snapshot. A syntactically valid ACK cannot unlock movement by itself. Unsupported ACK negotiation remains offline. Every fresh peer clears remote actors/vehicles/projectiles, queued chat/commands, chat high-water marks, and connection-bound shot counters. Uncertain shots/actions are never replayed. Offline chat gets an explicit not-sent status.

The account cookie is retained; reconnecting transport does not create an account or reuse its old inventory nonce. The existing self-host hello spawn policy is retained. The game controller discards previous vehicle/carrier ownership and held input before that baseline is applied. The HTTP gameplay client invalidates pending work at the connection boundary and suppresses obsolete state/results/completions, including reentrant callbacks. Older GET replies cannot overwrite a newer mutation; stale replies cannot unlock a newer action. Temporary menus keep the live world connected; permanent exit disposes its owners. These owners have a separate extracted lifecycle gate. Native respawning on hello is not claimed to reproduce the public browser's one-time initial-spawn behavior.

Run `python3 tests/network/smoke_native_connection_recovery.py` on macOS with Swift. It checks 10,734 deterministic lifecycle/readiness/FPS/background/generation conditions and compares the readiness inventory validator against the actual NativeWeaponState parser. It opens no network service or UI. The real URLSession/backend fixture, `python3 tests/movement/smoke_native_recovery.py`, passes46 checks, including an accepted shot whose ACK is withheld before disconnect, abrupt process restart with checkpointed guest state, fresh nonce/baselines, no ammunition/damage replay, chat reset and HTTP-generation/reentrant cases. See NATIVE_CONNECTION_RECOVERY_TESTS.md. The extracted owner gate `python3 tests/network/smoke_native_connection_owners.py` separately checks14 call-order/state/lifetime assertions with non-UI spies. These checks do not establish physical network or iOS suspension behavior.

## Core86 world ownership cleanup

An omitted vehicle in a streamed list is not an explicit despawn. Dynamic parked
vehicles retain their existing distance-streaming behavior, while `vgone` now
routes an explicit callback through the actual native client/controller/renderer
to remove the old body, collider and pending shove. The callback is delivered
even after its row was already omitted, and repeated deletion is harmless.
An explicitly removed owned vehicle discards its chassis and delayed rider task
without manufacturing a parked body, network exit request or side displacement.
Other players, the live connection, equipment and unrelated effects remain.

A fresh peer/world additionally clears all promoted parked bodies, remote
animation/sample caches, local/remote canopy presentation, retained flight
audio, projectiles, fires, held streams, queued particles, blast sprites and
camera shake. Loaded asset definitions remain reusable. Particle reset also
releases old anchors and rebases its fixed pool; effect reset discards fractional
simulation time. This is native session isolation, not original singleplayer
gameplay parity. Actual helper, extracted ownership and real WebSocket tests
are distinct gates. See `tests/network/smoke_native_world_reset.py`,
`tests/network/smoke_native_connection_owners.py`, `tests/network/smoke_native_wire.py` and
[CORE_VEHICLE_DEPARTURE.md](../vehicles/CORE_VEHICLE_DEPARTURE.md).
