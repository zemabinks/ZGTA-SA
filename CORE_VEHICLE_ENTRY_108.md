# Browser driver entry retains its reservation during get-in

Core108 fixes a confirmed independent-backend failure: a normal browser driver
entry received a successful ACK, then its legitimate on-foot/get-in report
cancelled the reservation before the first driving report. The server rejected
that drive and never published the registry's driver marker. A locally predicted
car could therefore remain unrepresented correctly to other clients.

The archived browser controller's `stand()` phase keeps the car model visible
while it is not yet driving. Its actual `parked` getter returns a valid snapshot
in this state, and its unchanged `own()` serializer includes that snapshot in
ordinary foot reports during get-in. Core107 incorrectly treated every matching
foot/parked snapshot as pending-entry cancellation. The previous serializer
fixture hardcoded `cj.parked:false`, so it did not exercise this real transition.

`selfhost_backend.js` now reserves implicit pending cancellation by a final
parked report for peers that negotiated the native inventory protocol. Browser
stand/get-in snapshots preserve the existing reservation; explicit `t:exit`
still cancels either client's pending entry. Active driver exit, the original
twelve-second lease, exclusivity, pose/model checks, mission borrower authority,
disconnect/reconnect and vehicle-incarnation checks retain their existing rules.
A pending ACK alone still publishes no driver and moves no parked body. The
first accepted drive still publishes registry slot 11 before its driving row.
No entry time limit was increased and no unclaimed driving report is trusted.

## Validation

The portable HTTP/WebSocket regression reproduces the old failure before the
fix, then checks ordinary browser foot/get-in snapshots, actual accepted report
state, bounded lease, competing entry denial, first-drive publication order,
HTTP registry visibility, completed exit, explicit quick cancellation and
expired/late drive denial. It continues to cover native final-park cancellation,
owner persistence, stale incarnations, reconnect and existing coupling rules.

Private owner-archive execution additionally extracts the unchanged controller
`parked` getter and browser `own()` serializer. Its generated foot and resumed
drive reports pass through the real disposable HTTP/WebSocket backend. A
separate assertion verifies the backend actually processed the archived foot
report with its proper `t:me` transport envelope; parser/serializer execution
alone is not counted as a network result.

Accepted focused results:

- 98 real HTTP/WebSocket presence checks across 6 scenarios, including 19 checks
  for this transition, with actual archived get-in output replayed.
- 82 existing HTTP/WebSocket driver/passenger seat-authority checks.
- 127 actual archived manager/dispatch/getter/serializer checks over 7 model
  classes, including original parked/driver handoff and real server wire replay.

The archived getter/serializer inputs use explicit authored foot/stance carriers;
they are not a whole original running browser or game. All original source,
geometry, generated reports and wire evidence remain under ignored `local-only`.
The portable regression uses authored data and does not require original assets.

## Commands and private archive carrier

The public authored regression remains:

```sh
node smoke_selfhost_vehicle_presence.js
```

The archive-executing carrier is kept only in ignored local research. With the
owner-local archive and its existing independent tools prepared, use:

```sh
node local-only/research/vehicle-entry-108/smoke_selfhost_vehicle_presence_browser.cjs
node smoke_selfhost_vehicle_presence.js --archived-serializer local-only/research/vehicle-presence/browser-serializer-report.json
node local-only/research/vehicle-entry-108/smoke_selfhost_vehicle_presence_browser.cjs
```

These commands preserve the existing generate → wire replay → manager replay
order. The public tree does not contain the archive-executing carrier. The
recorded 127-check execution occurred before this path-only relocation; its
original source bytes and hash remain privately preserved. Relocation was
syntax-checked without rewriting any accepted test result or count.

## Actual QA boundaries

The Core107 rendered reverse test is preserved as failed evidence. It showed
browser entry ACK, subsequent bound foot report and first drive well within the
lease, but no occupied publication for its cab. Offline exact-method execution
and the new portable HTTP/WebSocket regression independently reproduced the
underlying cancellation.

That run also placed the native actor closer to its own parked taxi than to the
browser's cab. The native correctly chose the nearest registered car; this is
not evidence of a native candidate-priority bug. The next rendered two-client
test must make the occupied browser cab nearest through normal input and then
verify actual passenger selection, visible occupants, shared chassis motion and
release. No native App source or test pose was changed by this backend fix.

These results establish the targeted backend/input contract. They do not claim
that the corrected Core108 scene, reverse passenger ride, retail gameplay feel
or complete 1:1 engine parity has already passed rendered acceptance.

## Evidence and source identity

Core107 backend before the fix:
`144e2230513fc02010edaf26ffa310b664bdb95315ef9ecedae7a9f90ac7ecd8`.
Core108 backend:
`a02d41c481e9e04bbcfda9abd10e3e154c469e2cce12339670063d8092814c97`.

The private acceptance ledger is
`local-only/research/vehicle-entry-108/acceptance.json`.
Its original Core107 evidence is retained in that candidate's
`local-only/research/occupant-ui-107/browser-entry-107-failure-proof.json` and
`runs/sim107-20261117-d-passenger/wire-failed-native-entered-own-car.json`.
No original bytes, saved guest tokens or cookies are included in public source.

Related occupancy/attachment contracts remain documented in
`CORE_VEHICLE_SEATS_107.md` and `CORE_NATIVE_OCCUPANTS_107.md`.
