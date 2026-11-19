# Working vehicles and confirmed coupling

Core88 adds the archived browser's working-vehicle mechanisms and native local
trailer/tow constraints. The references are the supplied archived browser code
and its owner-local model/collision resources. This work does not establish
original retail San Andreas accuracy or physical iPhone handling parity.

## Evidence and investigation boundary

The relevant routines are in archived factory `19737`: hitch anchors and model
compatibility, `cD` trailer chains, `uu` working/tow state, `vo` part posing,
`vh` moving collision, and the parked manager's force selection. Original
factory `23895.vX` identifies the working collision spheres; `58683.WQ` provides
the original part matrix. These were inspected and selected routines executed
with ordinary local Node tooling. REA MCP was unavailable, so these executions
have no new REA Evidence ID and are not described as live browser observations.

Full factory `19737` SHA-256:
`4eb2f2ce8f593a05f6514eb207d23643afbb81b9832dd2509bd9bf8d5a0636a7`.
The selected original routines, generated catalog, model hashes and numerical
fixtures remain under ignored `local-only`. Factory `91584` is the train module
and `91873` is its track data; neither was used as a towing reference.

## Parity checklist for this scope

| Mechanism | Implemented and checked | Remaining boundary |
| --- | --- | --- |
| Hitch geometry and compatibility | Local importer derives all 212 model profiles, nine rear hitches, nine trailer hooks, actual frame/fallback anchors and compatible models. Anchors use Rapier Y-up body coordinates. | Derived original data is required locally and is excluded from public source. |
| Trailer chains | Confirmed local root, up to two trailers, free spherical joints with contacts disabled, source acquisition thresholds and released-target cooldown. Existing links retain their joint and body identity. | Network authority is an independent server design, not a recovered original backend. |
| Release conditions | Missing/replaced bodies, invalid health/claim, separation and trailer facing/up boundaries remove the downstream chain from back to front. Released bodies keep their velocity. | Retail collision break behavior beyond the browser reference has not been measured. |
| Towtruck | Continuous moving rear anchor, eligible car front anchor, source acquisition/detachment thresholds and the original internal 20,000-unit lift/drop phase. | Live touch/controller towing and adverse network latency still need acceptance tests. |
| Tool scalar and orientation | Original normalized 50 Hz equations advance within the native fixed-step loop; work values survive teleport/parking, while input cancellation releases the held axis. | This does not validate the overall vehicle engine against a running retail game. |
| Working meshes | Actual part grouping and rest transforms for dumper, packer, dozer, towtruck, forklift and configured Andromada are exported as matched rig families. Paired tow parts rotate in opposite directions. | The supplied Andromada has no configured `misc_e` frame. No invented ramp or nonfunctional control is added. |
| Forklift collision | Two original zero-density cuboids use the original extents and continuous body-relative lift. Group masks, friction, lifetime, parent rotation and immediate query updates are tested. | Full load-carrying behavior with every streamed object type has not been accepted in a live scene. |
| Moving chassis collision | The original material-65 selection identifies seven dumper and six dozer spheres. Their centers follow the source pivot matrix while unrelated shapes remain stationary. Parking, demotion and re-promotion retain the work pose. | The original also deforms a separate triangle-query mesh. This change ports the proved physical spheres, not every moving triangle query. |
| Hauled force profile | The parked pool selects the archived held input, clearing abandoned/riderless behavior and the ordinary low-speed brake. Existing ordinary parked inputs remain unchanged. | A held force profile need not produce a longer stopping distance: abandoned axle friction changes too. |
| Asynchronous ownership | Only confirmed topology creates joints. Owner/session/entity generations prevent stale ACKs from clearing a newer request. Negative ACK retries are bounded. Broken-link cleanup survives declined delivery and retries until queued or removed by authority, without replaying an accepted pending request. | The 500 ms negative-ACK retry backoff is an explicit new transport policy, separate from source gameplay cooldown. |

## Source and local resource preparation

Public source contains the independent implementation, importer and test
runners. It contains no original game scripts, model tables, derived anchors,
converted meshes, textures or recorded reference samples. Each host needs its
own permitted local reference files prepared by the existing archive pipeline.

With those files available, run:

```sh
node tools/assets/prepare_native_vehicle_coupling.js
node tools/assets/prepare_native_working_vehicles.js
node tests/vehicles/smoke_native_working_stage.js
```

The catalog defaults to `local-only/selfhost/coupling-catalog.json`. The complete
working asset stage defaults to `local-only/native-working/models`; its sibling
`manifest.json` contains every file's size and SHA-256. The staging command
validates all configured models before publishing readiness and retains a
previous local stage for rollback. Both custom catalog and staging outputs must
remain inside this project's real `local-only` tree and cannot traverse live or
dangling symlinks. Catalog writes use a uniquely owned temporary directory.

Every family consists of matching `.rig.json`, `.rig.bin`, `.rig.normals.bin`
and `.rig.png` files. The new hierarchy changes vertex traversal and atlas
ordering. Serving new metadata beside older buffers can produce the wrong
mesh or texture. The staging validator rejects mixed output; the native overlay
requires all four files and rejects incomplete families rather than falling
back per file. Generate the stage before restarting the server/app; hot
replacement across already in-flight asset requests is not a verified atomic
client reload. Other unchanged models can use the existing local archive.

## Native integration contract

`NativeGroundVehicle.loadCouplingDefinitions` accepts the owner-local catalog.
Its driven and streamed endpoints expose current physical body poses. Wire
vehicle rows also carry body positions; callers must not subtract the render
origin again when transforming an anchor. `modelOffset` is for the rendered
model/body conversion, not an extra network position correction.

`NativeVehicleCoupling` accepts connection-scoped topology revisions and creates
constraints only for the locally driven root. Candidate discovery sends a
generation-tagged request through `onRequest`; the network completion must pass
that same request back to `rejectRequest`. Reconstructing it from only the three
vehicle fields loses its asynchronous owner generation. Reset the helper at
session boundaries, update its owner on driver changes, and remove explicit
despawned entities. Remote actors continue rendering authoritative motion.

Set `workingTowed` from confirmed topology and update the helper through
`onCouplingStep`. That callback runs after driven tool motion advances and
before the existing streamed-force hook inside the same physics step. It does
not replace the parked manager's callbacks. Tool input uses the source axis
`specialDown - specialUp`; labels should follow each model's actual direction,
because the source up key lowers the tow hook but raises forklift plates.

## Delayed confirmation lifecycle

Core89 fixes a confirmed link that arrives after its two live endpoints have
already moved beyond the ordinary break distance. Previously `reconcile`
declined to create the joint, while break detection inspected only existing
joints. The independent server could therefore retain an attachment with no
local constraint or cleanup request.

When both compatible endpoints, their live bodies and their anchors are
available, a separation greater than the existing 1.5 m trailer or 3 m tow
limit now invalidates that chain suffix and requests authoritative cleanup.
Downstream physical constraints are removed in reverse order; a valid prefix
remains intact. Declined delivery retries through the existing cleanup path,
while an accepted pending request remains deduplicated and scoped to its owner
and connection generation.

An unrealized link with a missing streamed entity, configuration, body or tow
anchor keeps waiting. It is not treated as proven geometric failure, and can
create its joint after the missing state arrives. This distinction adds no
timeout and changes none of the acquisition or break thresholds. It applies to
unrealized confirmed links; the existing physical-body destruction rules remain
separate.

## Focused verification

```sh
python3 tests/vehicles/smoke_vehicle_coupling.py
python3 tests/vehicles/smoke_vehicle_working_rigs.py
node tests/vehicles/smoke_native_working_stage.js
node tests/vehicles/smoke_vehicle_departure.js
zsh tests/vehicles/smoke_vehicle_lifecycle.sh
python3 tests/vehicles/smoke_vehicle_air_handoff.py
```

The final frozen expanded coupling gate passed 161,133 checks with unchanged source.
It compares continuous and wire work values with the actual archived controller
at 15/30/60/120/144 Hz, material-65 transforms with actual `vh`, fork collision
with the actual controller's geometry, and held/riderless constants with the
actual parked source. It exercises real native bodies, immediate collision
queries, fixed-step pool ordering, two-link and tow lifecycle, momentum,
negative ACK backoff and same-id owner/session replacement.
The delayed-confirmation cases use real native bodies for both trailer and tow,
including declined delivery, pending deduplication, missing entity/body/config
restoration, an absent tow anchor, within-limit acceptance and preservation of
a valid prefix when a delayed second link is too far away.

The working-rig gate passed 182,608 matrix checks over 606 actual archived poses
for the six configured models; maximum matrix element error was
`8.881784197001252e-16`. The staged-family gate passed 50 checks, including
corrupt metadata, incomplete normals, wrong atlas dimensions, stale generation
and unsafe catalog/stage output rejection. The prior lifecycle, archived
departure and aircraft handoff regressions passed 92, 119 and 11,037 checks
respectively. Numerical and clause tests do not substitute for
GPU images, real touchscreen/controller input, multiple live players or
original retail timing measurements. Those acceptance checks remain open.
