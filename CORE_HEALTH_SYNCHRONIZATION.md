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

- `node smoke_health_ack.js`: actual independent backend handlers, synthetic
  accounts; loss/armour, concurrent damage, duplicates, stale nonce, sequence
  gaps, malformed amounts, fatal/respawn, HTTP revisions and legacy clients.
- `python3 smoke_native_health.py`: production prediction model and real native
  URLSession HTTP/WebSocket/Peer/backend; earlier server damage, stale HTTP,
  same-nonce hello variants, hit truth, fatal/validated respawn, accepted damage
  with a withheld acknowledgement and abrupt reconnect without replay.
- `python3 smoke_native_respawn_dispatch.py`: extracted native controller and
  network callback ordering. Non-UI proof is distinct from Simulator acceptance.

All fixtures use disposable state; no production or owner game data is changed.
