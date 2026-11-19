# One logical parked/driven vehicle

Core105 corrects the confirmed independent-server case where the browser showed
both the parked mission cab and the same-ID player's driving cab. This is a
vehicle presence/authority correction, not a claim of complete vehicle parity.

## Original wire contract

The owner's shipped browser archive uses vehicle row slot11 as `driver`:

| State | Row11 | Logical registry row |
| --- | --- | --- |
| Parked or pending entry | `null` | Retained |
| Confirmed driving | String player number, e.g. `"2"` | Retained |
| Confirmed exit | `null` | Retained at final body pose |

The actual parked manager briefly keeps a parked stand-in while the remote
driving model loads. Once its `handed(vehicleID)` callback confirms that driving
representation exists, it hides the parked group and removes its parked physics.
It retains the map entry, ID, owner, condition and other metadata. A subsequent
null driver restores that same entry immediately.

`veh` and `spawned` both feed this manager's row parser. `vgone` is a logical
removal: the archive records a 60-second same-ID tombstone, and a locally held
vehicle has a separate promotion path. It is unsuitable for hiding a parked
counterpart during driving. Core105 sends no visibility-only `vgone`, filters
no occupied rows out of HTTP/full-state snapshots, and needs no browser patch.

The original `own()` serializer also deliberately omits `vehicle` for local
free-play cars. Such an unbound driving actor remains supported. It cannot hide
or update a registry car, acquire its identity, couple through a borrowed ID, or
advance a marked-vehicle job/race.

Primary evidence is the owner's archived factory 19737, SHA256
`4eb2f2ce8f593a05f6514eb207d23643afbb81b9832dd2509bd9bf8d5a0636a7`.
The focused browser test extracts and executes the actual manager, network
dispatch and own-report serializer in an offline VM; it never imports original
source or assets into public source. REA runtime tools were unavailable for this
scope, so this is explicitly ordinary static inspection plus offline execution.

## Independent server behavior

`selfhost_backend.js` binds each entry reservation to the actual transport peer
and vehicle object incarnation. An account number or reused string ID is not
authority. Nearby entry/jack acknowledgment leaves parked appearance unchanged.
Only the first valid, matching driving report sets row11. Competing claims,
foreign mission claims, wrong models, stale incarnations and malformed poses are
rejected before overwriting the last accepted actor state.

Publication order is deliberate:

1. Start: occupied `veh` row, then the matching driving `cars` row.
2. Exit: replacement foot `cars` row, then unoccupied `veh` at its final pose.
3. Disconnect/death: retire the driver representation before restoring parked
   appearance, retaining the last accepted body pose and condition.

Browser explicit `exit` supplies a final body snapshot; its following foot state
completes the transition. Native `sendExit` supplies its existing foot report
with nested `parked` state. Entry cancellation, timeout, death and disconnect all
release reservations. Ordinary foot reports during a get-in animation do not
cancel an entry. Occupancy changes preserve coupling vehicle IDs; actual exit,
death, disconnect or deletion releases the appropriate existing driver links.

Health cannot increase through driving/parking reports, empty damage does not
repair a driven car, and omitted working angles retain their prior value.
Authorized borrowers update the owner's garage. Position persistence is
throttled; condition changes and final release force a save. Real deletion
revokes the claim and retains ordinary `vgone` semantics. An owner-slot respawn
uses a new wire ID.

The 8-metre entry radius, 16-metre first-body allowance, 12-second pending timeout,
10-second active timeout, stock model 400...611 namespace, finite world bounds
and 5000ms save interval are independent server policies. They are not measured
retail animation/physics constants. Proximity is checked against the last
accepted reported actor position; this change does not add an authoritative
movement/physics solver.

## Verification

Run the focused sequence from the project directory:

```sh
node tests/vehicles/smoke_selfhost_vehicle_presence.js
node smoke_selfhost_vehicle_presence_browser.js
node tests/vehicles/smoke_selfhost_vehicle_presence.js --archived-serializer local-only/research/vehicle-presence/browser-serializer-report.json
node smoke_selfhost_vehicle_presence_browser.js
python3 tests/vehicles/smoke_native_coupling_backend.py
```

The first fixture uses real ephemeral loopback HTTP/WebSocket connections with
authored accounts, world, vehicles and coupling anchors. It checks publication
order, pending/competing claims, both exit forms, cancellation/expiry, invalid
reports, late joins/API snapshots, mission access, owner persistence, death,
disconnect, stale drivers, deletion/reuse and linked-body state. The optional
serializer input feeds the actual archived `own()` output through the real
server rather than inferring behavior from field names alone.

The browser fixture executes actual archived code and owner-local geometry/
Rapier for seven vehicle classes. It verifies stand-in timing, hidden parked
physics, retained map identity and immediate final restoration, then replays
the real observed synthetic-server packets through the original dispatch. Its
negative case reproduces the duplicate when the driver marker is omitted.

The native fixture compiles the unchanged real Swift networking client and
connects it to the copied independent backend with a separate legacy WebSocket
observer. It uses actual `requestEnter`/`onEnter`, first driving, parking,
coupling acknowledgment and reconnect paths; occupancy must never trigger its
logical removal callback. Existing vehicle, mission, combat, garage, coupling
and whole-server regressions remain required.

Ignored reports are written to `local-only/research/vehicle-presence/` and
`local-only/research/coupling-backend/`; they record input hashes and scope.
Original archive execution requires the owner's local files. No physical phone
was accessed for this correction. Rendered browser/Simulator validation is a
separate acceptance step; these tests do not establish GPU, retail physics,
animation timing or complete 1:1 behavior.

## Remaining distinctions

Occupied-vehicle carjacking needs the original victim/animation handoff, which
the independent server has not implemented. `jack` can reserve a parked car;
it does not steal a competing live reservation or driver. True server removal
also retains the archive's locally held promotion behavior rather than
inventing a new force-exit command. Registry/mission authority is revoked even
if the original browser continues a local free-play representation afterward.
These are explicit limits, not completed gameplay parity.


## Paired rendered acceptance,17 November2026

The complete native Simulator105 guest/taxi/entry/drive/exit UIKit scenario
passes in165.445 seconds. A separate actual browser records the same logical
vehicle with row11 null → driver17 → null, without `vgone`. Rendered parked,
driving and drive-away frames show one yellow cab; a supplemental normal camera
look shows the restored final parked body beside the on-foot native player.
Native screenshots show the matching yellow car and final foot handoff.
Original browser source and rendering were unchanged. This is a bounded real
browser/Simulator transition, not physical iPhone or retail-engine acceptance.

The old handbrake control failed actual hit testing under brake/reverse.
Consequently this run does not certify handbrake input, even though its exit
assertions passed. Core106 handles that separate touch-layout defect. The
initial runner's nonexistent `PLAY` label failure and the corrected
`PLAY ON THIS SERVER` rerun are retained separately in local evidence.
