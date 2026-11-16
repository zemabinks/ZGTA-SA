# Core88 actual native/backend coupling integration

Run `python3 smoke_native_coupling_backend.py` on macOS with Xcode command-line tools and Node with its built-in WebSocket client. The runner needs ephemeral loopback listener permission. It does not use production ports or existing saves.

The native executable compiles the actual unchanged `NativeMultiplayerClient` and its Foundation dependencies. Its private URLSession first obtains a real guest cookie over the actual backend HTTP route, then connects to the actual backend WebSocket upgrade and Peer implementation. A separate Node WebSocket client sends the legacy/browser protocol `hi` and observes real wire packets.

The fixture copies the backend modules into a disposable private directory. It invents two model definitions and anchor geometry, then explicitly seeds an owned garage tractor and three target rows before the first native handshake. This setup does not claim original game geometry, ownership acquisition, rendering, physical joints, or retail runtime behavior. No original assets are needed or copied. Unrelated backend job/projectile timers are stopped; real handshake/message handlers, coupling authority, garage saves, transport recovery and Peer disconnect cleanup execute unchanged.

Coverage:

- The actual server sends negotiated `hello`, unacknowledged coupling baseline, then full world state. Requests are blocked before readiness and after explicit stop.
- Current full driver position/work and current target `vmove` packets reach real backend rows before hitch evaluation.
- Aligned first and second links succeed; a third link fails without changing topology. The next contiguous sequence succeeds and releases only the second link, followed by root release.
- The independent legacy peer receives authoritative release packets keyed by target IDs. It receives no native-only coupling topology packet.
- Native parking updates work in the local row, actual backend row, garage entry and disk save. A normal legacy full-state refresh sees the saved value.
- The fixture waits the real trailer cooldown rather than replacing the clock or timing constant.
- A real accepted second-link ACK is deliberately withheld and its real socket destroyed. Backend Peer cleanup releases both claims. The same guest reconnects with a fresh nonce, an empty baseline and sequence one; the uncertain request/callback is never replayed.
- Final parking automatically releases the current claim. Work remains authoritative through wire, full state and persisted save.

Reports and exact source hashes are under ignored `local-only/research/coupling-backend/`. `server-report.json` records actual requests, topology/ACK wire observations and legacy releases; `report.json` records all compiled/copied source hashes and whether live files still matched their captured snapshots. The runner fails on either native or backend assertions or fixture cleanup failure.

This complements `smoke_native_coupling_wire.py` (controlled malformed/stale protocol packets) and `smoke_vehicle_coupling_server.js` (the broader authority matrix with direct handler fixtures). The legacy observer is a genuine independent WebSocket connection, not a rendered browser UI, physical iPhone or controller acceptance test.
