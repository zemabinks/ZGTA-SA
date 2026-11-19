# Native connection recovery regression

Run `python3 tests/movement/smoke_native_recovery.py` on macOS with Xcode Swift tools and Node with its built-in WebSocket client. The fixture uses actual `NativeMultiplayerClient`, `NativeConnectionRecovery` and `NativeGameplayClient` source snapshots. Reports and hashes are written only to ignored `local-only/native-physics/tests/connection-runtime`.

The Node controller starts the actual independent backend in a separate temporary process. Game and control listeners use kernel-selected loopback ports; production8766 and QA8778 are not addressed or restarted. Its catalog and flat collision mesh are explicit synthetic fixtures. No owner game assets, player saves, microphone, device or Simulator are used.

The46 checks cover:

- Negotiated hello, matching inventory and full-world baseline are all required before ready. Position, chat and combat requests are gated before that barrier.
- A real accepted shot consumes one round and a real hit damages a second WebSocket player. The inventory ACK is withheld, and the socket is destroyed before delivery. Recovery settles the uncertain write from the fresh authoritative inventory; an old shot ticket and pending/offline chat are not replayed.
- An actual backend process is checkpointed, killed with SIGKILL and restarted on the same disposable port. The same guest, ammunition and damage state are restored. New chat at sequence1 remains visible after the old server had reached41.
- Injected monotonic ticks exercise bounded offline retry, inactive retry suppression and explicit-stop suppression. The transport and server traffic remain real.
- A valid HTTP GET is allowed to finish while the main callback queue is blocked. A ready→offline→ready boundary with the same nonce then discards its queued old success.
- Held old refresh/action responses cannot overwrite a fresh peer baseline, invoke old completions/results, release a newer busy action or send an extra request. An older same-peer GET cannot rewind a subsequent mutation.
- Reentrant `onState` can start another same-peer action: the accepted first completion remains valid, its stale status is suppressed, and the next action retains busy ownership. An offline/online or actual nonce replacement inside `onState` suppresses the old completion instead.

The test publishes a fresh absolute on-foot state after each resync before requesting position-dependent actions, matching the app contract. It uses the real `weapon.select` action. Snapshot annotations identify responses without replacing gameplay or inventory logic.

Observed passing metrics: six fresh nonces, four offline failures within the bounded retry window, two saved accounts, ammunition16, victim health82, one shot packet and one hit packet. These are fixture measurements, not retail-game damage, timing or device-performance claims.

The restart state is deliberately checkpointed before SIGKILL. This tests identity/state recovery and replay prevention, not arbitrary-crash persistence guarantees. Physical backgrounding, touch/controller input, iPhone networking and full App acceptance remain separate. The isolated server and test executables exit at the end.
