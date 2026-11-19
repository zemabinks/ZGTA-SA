# Core88 coupling server authority review

The independent server now validates trailer and tow topology before granting
movement claims. This review covers actual server handlers and controlled
geometry. It does not establish original retail driving or joint accuracy.

## Reproduced causes and corrections

The reviewed module allowed a tow truck to acquire a tractor, then allowed that
tractor to acquire a trailer. The native topology validator rejects this mixed
tow/trailer chain, so the server could acknowledge a state that its native
client could never apply. The corrected chain walk requires every existing
link in a trailer chain to be a trailer link. A maximum of two remains.

The previous cooldown used the parent as its key and blocked every nearby
target after a release. The archived browser instead excludes only the last
released target for 2,500 milliseconds. The corrected server tracks that target
per controlling peer, permits a different target immediately, and clears its
ephemeral release cache when that peer disconnects. Tow release has no trailer
cooldown. Repeated reports for an already accepted link are idempotent, as
required by the browser's four-second refresh of both trailer links.

The browser creates a speculative physical joint before reporting its hitch.
Ignoring a rejected report would leave that joint alive locally. The backend
now returns the browser's actual target-based `unhitch` message on rejection,
and broadcasts removed target IDs to legacy peers when links are pruned or
released. Native peers receive authoritative topology and their ordered ACK.

Server anchors use physics body origins in GTA wire coordinates. Heading and
roll already contain the protocol signs; rotation is `Ry(h) * Rx(p) * Rz(r)`.
A separate private probe extracted the actual native ground-vehicle rotation,
driving position encoder and parked-vehicle Euler/packet encoder. Across 162
controlled anchor cases, the owned-wire error was at most 0.0000005371 meters;
the rounded parked-wire error was at most 0.008258 meters. Treating native
presentation angles as wire angles instead produced a 12.045-meter error.
That suspected sign defect was withdrawn; no sign change was justified.

The server adds a bounded 20-millimeter allowance to its 0.4/0.5-meter horizontal
and 1-meter vertical acquisition tests to tolerate wire quantization. The
native candidate controller retains its original acquisition distances. This
allowance is a measured interoperability policy, not a new retail value.

## Executable regression gate

```sh
node tests/vehicles/smoke_vehicle_coupling_server.js
```

The gate copies the actual independent module, backend and dependencies into
temporary folders; generates invented model IDs, anchors and accounts; invokes
the real handlers; and removes the fixture afterward. It opens no listener and
needs no original game assets or imported model catalog. One scenario creates
the real backend `Peer` through its upgrade method with an in-memory socket,
then exercises its real close path.

The current reviewed snapshot passes **379 checks in 22 scenarios**:

- Initial state, optional catalog validation, capability negotiation and the
  baseline immediately after `hello`.
- Ready/current-driver, health, mission ownership, missing source/target,
  occupied target, finite geometry, tow-bar state and compatible target rules.
- Two-link chains, third/self/cycle/foreign-claim rejection, idempotent refresh,
  mixed tow/trailer rejection and partial/root release.
- Same-target cooldown, a different target during that cooldown, expiry,
  quantization allowance boundaries and 45 rotated/tilted anchor arrangements.
- Connection nonce, contiguous sequence numbers, accepted/rejected duplicates,
  rejection consumption, gaps, 32-result memo eviction and repeated `hello`.
- Claimed trailer movement restricted to its owner, existing bounds and health
  limits, and compatible movement of unclaimed nearby vehicles.
- Optional work value preservation, clamping, driving and parked propagation
  through actual owned and mission vehicle handlers.
- Exit, death, target occupancy, disconnect and root/target despawn, including
  both descendant claims and both legacy physical-joint release messages.
- Legacy rejection rollback and four-second refresh of both links; startup
  without either optional metadata or the optional module; no topology/ACK
  namespace in saved accounts.

The report and byte-exact copied source snapshot are private under
`local-only/native-physics/tests/coupling-server/current/`. The report records
SHA-256 values for all six copied production files and this gate, and fails if
any selected production source changes during its run. The reviewed hashes are:

| Source | SHA-256 |
| --- | --- |
| `vehicle_coupling.js` | `4844fa37e157ac8a9a05c09bde99d8c2fd2ccccffc56103c01825159061853f7` |
| `selfhost_backend.js` | `3877913858a89e9196a5e3e037e6940ea4e0a436d507257e957eff16cae600c8` |

The old reviewed module snapshot
`b9801c590a777c764a8cc485790f6bd200c9bae5cbdb98897bf5181e434d9006`
was also executed through this gate with `--baseline-module`. It fails five
scenario groups: mixed topology at the module and handler boundaries, the
overbroad cooldown at both boundaries, and the missing wire allowance. That
negative combines the historical module with the current copied backend; it
does not represent a complete historical server process. Its private report
and copied sources are in the neighboring `baseline/` directory.

## Limits and release status

These are offline Node probes, not newly issued REA MCP evidence records.
Synthetic geometry proves authority and protocol boundaries; imported model
anchors, original browser physics, native physical-joint lifetimes and actual
cross-device driving require their separate gates and gameplay observations.
The 162-case wire probe is controlled encoder evidence, not footage of a retail
game. The iOS IPA cannot supply an executable Simulator retail reference.

This is a passing reviewed source snapshot. The parent release process must
rerun the gate after its final source freeze and include it with native wire,
joint, vehicle, effort and broader regression results. No full gameplay or
retail 1:1 claim follows from this gate.
