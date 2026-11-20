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
