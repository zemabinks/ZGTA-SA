# Camera and physical city-cell source lifetimes (153)

Two existing scene loaders could publish a completed old request after a newer
resource selection. Cancelling a transport cannot retract a publication block
that its completed callback has already queued on the game main thread.

The camera now gives each load its own request token, including retries at the
same origin. Only the latest invocation may install its table or notify its
completion owner. It releases the accepted request before notification so a
completion that starts another load retains the new request. Existing accepted
tables remain the fallback after a failed new response. Direction, selected
views and camera algorithms are preserved; this does not change original-game
camera curves or assert that they already match the PC game.

City collision loads now carry the announced resource identity and an individual
cell request token. Old callbacks cannot publish geometry, remove a new loading
slot or impose a retry delay on its replacement. Source synchronization cancels
owned transfers, revokes their tokens, clears the old CPU collision cells and
retires the corresponding cells through the existing native ground owner.
Other bodies, vehicles and object owners remain separate. Same-source updates
retain the accepted cells. Streaming refresh, server replacement and explicit
cell acquisition all synchronize the identity.

This identity follows the existing origin/installation generation and resource
mode contract. Arbitrary server file changes without an identity refresh are
not detected. Other metadata/resource loaders are outside this change's scope.

## Focused measured evidence

The actual old camera source fails the obsolete completed-publication assertion.
The current camera and production transport dispatcher pass 26 authored checks:
queued old success, source replacement, same-origin retry, failed latest reply,
independent camera instances, direction/view preservation and completion reentry.
The fixture controls transport scheduling; it does not claim a real HTTP or
original-game camera timing comparison.

The actual old collision loader fails because its obsolete loading slot blocks
the new source. The current literal renderer methods, real SCL2 parser, native
ground-cell owner and Rapier world pass 37 authored checks. Distinct floor
heights and face materials are queried through both native cell and physical
queries. Source retirement removes the old physical floor while preserving an
unrelated object and another body's identity, pose and momentum. Old failures,
same-source retention and no-longer-retained responses are also covered.

An initial fixture compile rejection remains retained: its authored helper
overloaded Foundation's `floor`. Renaming that helper changes neither product
code nor assertions. The subsequent historical rejection and current pass are
separate executed runtime receipts; a compiler failure is not accepted as the
historical product failure.

The first combined chain subsequently stops at the older source-owner carrier:
its extracted server setter now calls the collision owner, but the carrier did
not include that dependency. All 229 product/build inputs remained held. The
updated carrier extracts the real retirement method and checks server/source
wiring, token revocation before cancellation, cell retirement, same-source
retention and installation-generation replacement. All prior assertions remain;
the composed source-owner gate passes 32 checks. The failed combined attempt
and the separate full follow-up remain distinct records.

These focused tests use independently authored bytes and deterministic binding/
transport seams. The full combined Metal/physics/audio/transport follow-up passes (976.53s),
with all 229 App/build inputs and 14 captured test inputs held. Project, hosting
and layout gates also pass. The earlier original-rig and stock-HTTP/Metal/
Rapier evidence is explicitly reused with product inputs held; the failed
combined attempt remains retained. Universal Simulator Debug (502.1s) and
arm64 iPhone Release (539.7s) SDK products subsequently pass with all 229
App/build inputs, 39 dependency files and 14 private menu files held. These
unsigned SDK products are not a physical-device result. A normal retained-data
Simulator case passes (433.555s, one executed test, zero failures), covering
original male01, converted Maccer and segmented CJ joins, walk/camera input,
Taxi entry, exit, jump/landing/walk and installed-menu restoration. Nine complete
captures are manually reviewed. The front three-quarter car view shows male01
head/upper torso behind the windshield, while the car obscures lower limbs and
most arm placement. Both car captures occur after the gesture, so they do not
establish a before/after orbit or original-camera trajectory.

Actual owned open.mp logs record972 updates, movement for all three skins,185
Taxi model420 reports and on-foot/driver/on-foot transitions. This is one
actual native client plus its owned server, not a second rendered browser
client. All prepared/raw metadata, original files and native preferences are
preserved; the app, Simulator and owned test services stop afterward. Initial
postcheck sandbox denials are retained separately from the successful gameplay
case; identical reviewed local log/export actions subsequently succeed.

Original-PC and physical-device evidence, complete ambient simulation and
full gameplay parity remain open. Original
resources, captures, account information and private histories stay local.


## Original park-color reference check

A separate local resource check verifies the indexed hashes of the owner-supplied
classic-game `pershingsq` texture dictionary and both `pershingsq1_lan` and
`pershingsq2_lan` models. Both models reference `pershing1_LAn`; decoding its
stored DXT1 base mip shows purple colors. Archived c59 base layer247 and its
HD144 mapping contain closely corresponding purple samples and park geometry.

This supports the inference that the observed purple park material is intended
source artwork. The color alone is not a demonstrated rendering defect. It does
not verify full texture equivalence, original lighting, every purple surface or
a pristine retail runtime. Original bytes, decoded samples and captures remain
local; this note includes only independently written findings.


## Bounded city collision preparation (154)

The previous renderer performed the CPU spatial-grid build, physical SCL2
parse, grouping and native collider registration in its main-queue completion.
A bounded owner now admits one active transfer/preparation and at most32 small
pending descriptors. Each response is capped at16MiB with identity encoding;
all currently available archived city/interior cell files fit that cap. A
cancelled decoder keeps its serial slot until it exits, and resetting the
source releases queued descriptors without retaining their old payloads.

The utility worker uses the actual immutable WorldCollision parser and the
extracted physical-cell preparation operation. Material classes and fallback
parts are captured by value. The renderer checks the current source, request,
retained-cell intent and material snapshot before publication. Physical
registration stays on the existing world owner, rolls back partial failures
and preserves unrelated bodies. The old synchronous entry point remains for
explicit callers and deferred metadata rebuilds; those paths are not claimed
as asynchronous. No movement, handling, camera or multiplayer policy changes.

Executed focused gates pass49 worker/physics checks,41 renderer/source/floor
checks and32 composed-owner checks. They use authored bytes and controlled
transport/serial scheduling, with actual CPU preparation and native Rapier
queries. They cover bounded admission, main-queue responsiveness while a
worker is deliberately held, cancellation, reset, completion reentry,
malformed/oversized/HTTP/wrong-URL replies, physical floor/material queries,
empty cells, changed material snapshots, fallback bounds and deferred metadata.
They do not measure real HTTP latency or original-game frame timing. The
historical renderer still fails its intended obsolete-loading runtime oracle.

A matched Debug host comparison runs both actual153 and154 ground/parser
sources on three unchanged owner-local cells for three iterations each.
All225 deterministic CPU height and native floor-distance/surface/material
samples match exactly. The measured main-thread-equivalent path falls from
235–404ms to26–55ms; worker preparation measures207–363ms. These are desktop
host measurements, not Simulator frame traces or physical-iPhone results.
Native collider registration still has a measurable synchronous cost.

The initial authored fixture compared momentum across a legitimate physics
step and failed; its corrected comparison brackets installation itself. The
initial diagnostic benchmark rejected an ambiguous Float conversion before
execution. Both failures remain retained separately, with product source
unchanged by their fixture-only corrections. The accepted follow-up is distinct.

The complete selected Metal/physics/audio/transport regression passes
(1015.34s), with all230 App/build and17 captured test inputs held. The separate
four-original-rig and stock HTTP/Metal/Rapier gates pass, followed by project,
host and layout checks. Both SDK products subsequently pass: universal Simulator Debug490.6s and
arm64 iPhone Release510.3s. All230 product inputs,39 dependency files and14
private menu files remain held; product verification confirms self-contained
menu resources and the intended architectures/version. These unsigned builds
are not physical-device acceptance. A normal retained-data Simulator case
subsequently passes (512.352s, one executed test, zero failures). It performs
three development-source joins for7/2/0, original Taxi entry, a normal camera
gesture, exit/jump/landing/walk, then installed CJ0 walk/camera/jump and menu
restoration. Twelve complete captures are manually reviewed. The paired car
view changes from rear to front/three-quarter with ordinary right-stick input;
this establishes response, not original orbit curves or continuous smoothness.
The driver head/upper torso is visible, while lower limbs remain obscured.

The13 existing installed CJ files match their declarations and owner-local
sources. During the installed join, neither CJ nor city collision files fall
back to the Mac HTTP proxy. Installed CJ retains skin, white vest, denim and
shoes in the reviewed captures. Its base world appearance is less sharp than
the development source's optional HD overlay; world/lighting equivalence is
not claimed. This is installed-resource multiplayer, not offline gameplay or a
complete on-device original-ISO conversion.

The owned server records1153 updates, four distinct native joins with movement
in each and198 Taxi model420 reports with driver entry/exit. The installed
CJ join moves9.326m horizontally from its first reported on-foot point. This
is one actual native client and its owned server, not a second rendered
browser client. Prepared/raw metadata, original files and native preferences
are retained, and the app, Simulator and owned test services stop afterward.

Publication rejects a completed cell that has left the retained set. Pending
work is not currently reprioritized or retired early merely because visibility
changes. Rapid-teleport/cold-load latency and the residual synchronous work
still need rendered and hardware measurement. Original assets,
measurements, screenshots and private histories stay local. Original-retail,
hardware, ambient population and complete gameplay parity remain open.


## Bounded visual world preparation (155)

Visual WRL2 parsing, base PNG decode, Metal buffer allocation and cell bounds
previously ran in the scene's main-thread publication block. A utility worker
now prepares immutable GPU products. The scene still owns mesh admission and
optional HD scheduling. One active bin/PNG pair and preparation uses bounded
identity transfers (64MiB per file), up to32 queued descriptors and a192MiB
prepared-resource budget. Parser scratch/input data are additional memory;
these limits are not a whole-process RAM guarantee. All327 available archived
base cells pass a read-only header/size bound audit without downscaling.

The current detail takes precedence over neighbors and far cells. Each scene
refresh updates queued priorities and revokes no-longer-wanted visual and
collision intents before acquiring new cells. A cancelled active CPU operation
keeps its serial slot until it actually exits. Source/request fences prevent a
retired result from installing meshes, clearing a newer slot or imposing its
retry delay. Existing geometry, materials, movement and physics algorithms are
preserved.

Focused source tests pass74 actual Metal/scheduling/scene-admission checks and
50 collision/physical-owner checks. Unchanged154 fails the new rapid-teleport
oracle because obsolete collision intents block the retained cell. A first
fixture compiler rejection is retained; the correction only spaces a Swift
comparison operator. The later receipts are separate executed tests.

Three unchanged original owner-local cells retain identical complete GPU vertex
and index bytes, decoded base-level texture pixels, bounds, layer maps and
texture interpretation. Desktop Debug baseline preparation measures390–981ms;
new worker preparation measures400–1237ms while the main run loop continues.
This establishes work placement and output preservation, not a faster total
load, rendered frame-time improvement, physical-device or retail acceptance.
The complete selected source chain passes (1117.96s), with231 App/build and
20 test inputs held; original-rig, stock HTTP/Metal/Rapier, project, host and
layout gates also pass. Both SDK products and payload checks pass with the
source,39 dependencies and14 private owner-menu files held. Normal retained-data Simulator acceptance passes (495.511s, one executed case,
zero failures): development skins7/2/0, Taxi/camera/exit/jump, then installed
CJ0 movement/camera/jump/menu restoration. All12 full captures are reviewed.
The paired car views show rear-to-front input response and a textured driver
head/upper torso, with lower limbs occluded.36 visual and8 collision HTTP
replies use bounded identity transfers; the installed join has no world,
collision or CJ HTTP fallback. Actual owned-server logs record1161 updates,
movement on all four joins and207 Taxi reports with driver entry/exit.
Resources/settings remain held and owned services stop afterward. Original resources, full captures and raw measurements stay
local. Full ambient simulation, complete game fidelity and hardware evidence
remain open.


## Current-source and latest metadata admission (156)

The existing model-index loader captured a source identity but several typed
metadata callbacks did not use it. Completed old seating data could replace the
current animation table, and old physics data could replace materials and reset
coupling/support owners. Older requests at the same source could also overwrite
a newer successful response or defeat its failed-reload fallback.

Fourteen main-queue publications now check both the current resource identity
and their parent invocation token. Grouped effects and renderer camera/water
completion effects use that admission too. Coupling and tread metadata have
independent child tickets. A new parent invocation revokes both child tickets
before its physics response can schedule replacement children. Existing typed
decoders remain the data boundary; failed latest reloads retain accepted tables.

All four old155 seating modes fail their intended runtime assertions. The
corrected physical-owner fixture also rejects155 for both stale-source and
same-source material/coupling/support mutations; the child fixture rejects its
old-source side effects. The current seating modes pass16/12/3/7 checks, child
admission passes38 and the actual ground/Rapier modes pass11/4. They cover
parent/child separation, queued and late callbacks, request reentry, fallback
preservation and an unrelated body's pose/momentum. All captured Swift/test
inputs stay held. These are literal-source/authored-transport tests; a normal
production UI trigger for overlapping metadata reloads is not established.

The first physical fixture is retained as a compiler rejection because it tried
to read a fileprivate field. The follow-up compares public Equatable cell
snapshots; product visibility and parser assertions were not relaxed. The complete selected Metal/physics/audio/transport source chain passes
(962.43s), with231 App/build and25 test inputs held. Four original rigs,
stock HTTP/Metal/Rapier, project, hosting and layout checks also pass.
Universal Simulator Debug and arm64 iPhone Release SDK products and payload
checks pass;39 dependency files and14 private menu files remain held.
A normal retained-data Simulator case passes (494.485s, one executed test,
zero failures): development skins7/2/0, Taxi/camera/exit/jump and installed CJ0
movement/camera/jump/menu. Twelve captures are reviewed. Actual owned-server
logs confirm all four joins move and driver entry/exit. Installed world,
collision and CJ need no HTTP fallback; original files, resources and settings
remain held. Owned app, Simulator and test services stop afterward. This is admission
rather than an atomic multi-table transaction or automatic accepted-table
retirement. Sub-loader weather/waves internals and flight/particle asset owners
remain outside this change; original-game behavior and complete parity remain
unverified.
