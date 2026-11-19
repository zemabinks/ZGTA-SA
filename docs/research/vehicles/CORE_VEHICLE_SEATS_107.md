# Shared vehicle seats and movement authority

Core107 extends the Core105 parked/driver publication correction to passengers.
The native and server changes are independent implementations. The original
browser bundles and game resources are unchanged and remain owner-local.

## Confirmed contract and prior gaps

The owner's pinned browser factory19737 uses the following distinct fields:

| Participant/state | Outgoing report | Published actor row |
| --- | --- | --- |
| Driver | `driving:true`, car appearance token, logical `vehicle`, actor `skin` | Car token in2, driver skin31, logical vehicle35 |
| Passenger | `walking:true`, `driving:false`, actor `skin`, logical `riding`, integer `seat` | Skin token in2, `[vehicleID,seat]` in34; no driving ID35 |
| Parked vehicle | Registry retained through occupation | Driver player-number string in11, or null when unoccupied |

The browser's passenger input never requests a `ride` RPC. It selects an available
seat and its actual `own()` serializer reports that attachment. Its actual
shared-vehicle resolver prefers the matching driving body after occupied
metadata is present. Its local passenger controller follows that exact group;
the original remote occupant selector uses the same group and seat. The actual
bA animation owner attaches the original skinned actor to the model seat.

Core106's server published an unvalidated `riding`/seat pair and had no passenger
seat owner. The native path separately lacked outgoing passenger state and
promoted every accepted entry to a driver. Driver slot11 alone cannot resolve
those missing ownership and attachment boundaries. Inspection of an incomplete
mode is not proof of the cause of every user-observed rendered case; fresh
combined rendered acceptance remains separate.

## Independent server policy

`selfhost_backend.js` now binds each passenger seat to the transport peer and
particular vehicle object incarnation. It loads the existing prepared
`game/native/riders.json` version2, with bounded file/model/seat/coordinate sizes.
That file is generated from the actual original DFF/bv seat builder. Missing or
invalid model metadata denies passenger entry; no generic four-seat fallback
is invented. The normal preparation workflow already creates this resource.

The archived browser's first valid nearby `walking+riding` report acquires its
seat atomically. Native clients may reserve the same seat explicitly through
`{t:"enter",v,seat,passenger:true,request}`. The normal ACK echoes a valid positive
safe-integer request when supplied; older browser packets are unchanged. A seat
cannot be held by two peers, nor can one peer hold passenger and driver claims
simultaneously. Seat0 remains the existing driver entry path.

Garage ownership and mission borrowing remain distinct from seat/drive authority.
A passenger may ride another player's mission vehicle; that does not authorize
them to drive that reserved mission, change its appearance/damage, park it,
move its unattended body, store it or repair it. An authorized unlocked-car
borrower continues updating the actual owner's garage through the existing
driver-only path.

Passenger reports preserve character/vitals/animation input but cannot move the
shared vehicle. Published passenger position, orientation and velocity use the
current accepted driver/body state. The original row34 provides the exact model
seat attachment; raw reported passenger coordinates do not become a second
chassis simulation. Aimed passengers retain their world-space gun heading
without rotating the shared vehicle. The physical-on-foot predicate excludes
active seat claims even though the browser actor row must remain walking-shaped;
foot-only gameplay actions and UI fields use that separate predicate.
Server-internal occupied-body membership also protects
existing coupling checks, while the passenger wire row35 stays empty.

Ordinary foot reports during a pending get-in do not cancel its reservation.
Explicit passenger exit cancels only that seat and ignores any supplied parked
snapshot. A completed on-foot report releases an active passenger attachment.
Driver exit/disconnect restores the same-ID parked vehicle; remaining passengers
can stay in its real parked seats. Passenger disconnect/death, vehicle removal,
wreck, changed incarnation, interior change and stale transport invalidate the
appropriate passenger claim. Reconnection never inherits a former socket's seat.

Rejected implicit browser entry uses the original finite `tp` correction callback,
which actually drops its passenger owner before restoring foot ownership. The
`tp.h` field uses degrees; ordinary movement/body headings remain radians. Native
seat revocation uses the existing enter-ACK shape with `ok:false` and seat,
without a request ID. The correction does not add a browser-only force-exit RPC.

The8m entry radius,12s pending lease and10s active-transport timeout are independent
server policies, not measured original-retail animation or physics constants.
The two ordered messages at driver exit still replace the driving actor before
restoring parked metadata; an intermediate message boundary can temporarily
resolve the retained stand-in before the immediately following final metadata.
The tests distinguish that ordered handoff from persistent passenger ownership.

## Reproducible acceptance

```sh
node tests/vehicles/smoke_selfhost_vehicle_seats.js
node tests/vehicles/smoke_selfhost_vehicle_presence.js
node smoke_selfhost_vehicle_presence_browser.js
```

The seat HTTP/WebSocket fixture uses real ephemeral loopback connections and
synthetic finite resource metadata. It verifies duplicate/out-of-range/missing
seats, normal implicit and explicit entry, request correlation, live driver
movement, rejected passenger body/damage writes, driver/passenger exit,
parking, deletion, expiry, disconnect, death, wreck and reconnection. The owner-only second pass can replay the actual unchanged archived passenger serializer outputs with `--seat-serializer`; that report is not distributed.

The owner-only offline browser fixture is excluded from the public source release because it executes the archived client. Its private invocation is `node local-only/research/vehicle-seats-107/smoke_selfhost_vehicle_seats_browser.js`. It executes the actual serializer, vehicle resolver,
remote driver/passenger selector, local passenger controller, original bA
boarding owner and real male01/Taxi/ANP3 resources. It checks real skinned world
vertices while the shared driver moves, then replays actual server wire and
same-ID parked handoff. Its negative control reproduces stationary parked-body
selection without the required driver marker. Its original teleport callback
executes an actual passenger drop and checks heading/axis conversion. This is
ordinary pinned-source execution; REA tools were unavailable, so no fabricated
REA runtime Evidence ID is supplied.

`tests/vehicles/test_native_vehicle_seats_backend.js` runs the separate actual full native
network executable against copied server source, normal guest sessions and a
separate browser-shaped peer. Its public test controls exist only on that
short-lived loopback fixture. It records no credentials/cookies. Native session,
Renderer/physics and combined rendered results are recorded separately by their
owners in [native occupant evidence](CORE_NATIVE_OCCUPANTS_107.md); this document
does not infer those passes from backend or browser tests.

New reports and retained initial failures live under ignored
`local-only/research/vehicle-seats-107/` and `vehicle-seats-native-107/`.
The broad carrier repairs preserve real assertions: supplies establishes an
actual validated driver with matching damaged condition; multiplayer rejects
an invented vehicle ID and seats its passenger in a genuinely spawned Taxi;
both temporary web-server carriers include the resource-server module dependency.
No live listener, original archive, phone or user save is changed by these tests.

## Remaining limits

- No GPU, physical input, live browser/native scene or retail-gameplay accuracy
  follows solely from offline skeletal or transport checks.
- Full drive-by, occupied-vehicle jacking and every moving entry/exit context
  remain separate gameplay work.
- Missing custom seat metadata is explicit. The stock table does not establish
  compatibility with arbitrary server-defined vehicle formats.
- The original driver selector treats rider0 as absent, and CJ's segmented
  native resources are a separate known gap. This patch preserves a known
  driver skin when a report temporarily omits it; it does not substitute a
  different character for unsupported CJ.
- External SA-MP/open.mp and the original public service have separate protocol
  owners; this independent-server seat extension does not certify them.
