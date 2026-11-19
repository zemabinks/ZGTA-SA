# Environmental damage and multiplayer health

Core86 adds an optional native health acknowledgement contract to the independent
server. This is multiplayer correctness, not a retail gameplay reconstruction.
The browser protocol and servers without this capability keep their previous
compatibility path.

## Reproduced defect

The actual Core85 `reportLocalHealth` and `syncVitals` methods show local100HP
falling to60HP, then an older HTTP snapshot restoring it to90HP. Merely clamping
that snapshot to60 would lose the separate10HP server-owned damage. Correct
composition is50HP. The retained private baseline records the exact old source
hash and the60→90 result.

The new native client advertises `healthAck:1` alongside inventory acknowledgements.
The server binds requests to the current inventory connection nonce. Environmental
losses are ordered delta requests, not periodic absolute-health assignments.
The native HUD predicts each loss immediately, while a server snapshot rebases
still-pending losses over its authoritative health and armour. A processed request
is removed once, so an acknowledgement cannot charge the fall twice. Original
fall/drowning armour bypass remains separate from weapon absorption.

Server snapshots include a peer-local revision and processed-request watermark.
Older HTTP responses, duplicate/stale hellos and old-connection replies cannot
restore health or erase pending losses. Snapshot revisions also cover server-side
healing and armour changes. The actual Peer WebSocket encoder attaches the same
health truth to hit/vitals messages; bound HTTP gameplay responses include it.
Periodic native movement is no longer a second health writer after negotiation.
Legacy clients retain their old absolute-health path.

## Death, respawn and connection boundaries

Fatal loss is counted once. Respawn remains subject to the independent server's
existing cooldown. The native game teleports and announces success only after
an accepted respawn sequence, while rejected/pending requests leave it dead.
An unrelated heal is not a respawn approval. Input and vehicle UI reset at the
accepted transition. Legacy-mode approval remains synchronous.

A fresh peer discards unacknowledged requests and receives the server's current
health under a new nonce. If a loss was accepted but its reply was lost, the new
baseline retains that loss without replay. A request never received by the
server is deliberately not replayed. This does not provide arbitrary crash
persistence or multi-client account conflict resolution. Legacy non-ACK servers
retain their old stale-health limitation.

## Verification

- `node tests/combat/smoke_health_ack.js`: actual independent backend handlers, synthetic
  accounts; loss/armour, concurrent damage, duplicates, stale nonce, sequence
  gaps, malformed amounts, fatal/respawn, HTTP revisions and legacy clients.
- `python3 tests/combat/smoke_native_health.py`: production prediction model and real native
  URLSession HTTP/WebSocket/Peer/backend; earlier server damage, stale HTTP,
  same-nonce hello variants, hit truth, fatal/validated respawn, accepted damage
  with a withheld acknowledgement and abrupt reconnect without replay.
- `python3 tests/network/smoke_native_respawn_dispatch.py`: extracted native controller and
  network callback ordering. Non-UI proof is distinct from Simulator acceptance.

All fixtures use disposable state; no production or owner game data is changed.

## 2026-11-19 — Self-host breathing lifetimes (140)

Fresh independent-server connections now reinitialize the native oxygen pool once per accepted connection namespace. Disconnects and duplicate notifications do not grant air, and the operation preserves movement, facing, stamina, health and animation state. Legacy SA-MP/open.mp and the original browser-world adapter retain their own lifecycle semantics.

The native local swim forecast owns the breath display during gameplay. Older HTTP world snapshots still update the radar but no longer overwrite current breath or surfaced recovery. Accepted acknowledged respawns now start a new server oxygen clock, preventing time spent dead from consuming the new life's pool.

Focused authored evidence passes 88 literal native-method checks and 175 actual-backend/Peer checks. Actual emitted server health ACKs traverse the native consumer with pending fall and impact predictions; drowning preserves armour and does not consume their sequences. Executed historical callback/HUD variants fail at the intended assertions, and the old server reproduces the dead-time charge. Early harness errors remain retained locally.

These results establish the stated source/virtual-transport behavior. Full current regression and SDK results are tracked separately. Real-time network loss, rendered breath/drowning acceptance, physical iPhone behavior, classic retail lung/stat curves and matched original-game timing remain unverified. The server's existing 0.5-second catch-up cap and arrival-state sampling policy remain explicit limitations.
