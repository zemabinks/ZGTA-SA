# Core gameplay audit journal

## 2026-11-17 — Core110 terminal vehicle and rendering corrections

A genuine accepted native driver reproduced the wrecked-hull loss separately
from the older fixtures' missing entry handshake. Fatal health can release the
driver before its final parked snapshot arrives. Core110 releases occupancy
immediately while retaining one bounded, transport/incarnation-bound terminal
completion that cannot grant driving rights or repair the hull. Unauthorized
explicit-ID foot reports cannot publish duplicate parked stand-ins. The actual
HTTP/WebSocket regression passes303 checks across17 scenarios. Corrected-entry
native wreck and water fixtures pass their original hull/death/respawn
assertions; an initial water compile timeout remains recorded separately. See
[terminal vehicle evidence](CORE_TERMINAL_VEHICLE_110.md).

Actual offscreen Metal tests reproduce a second defect: a depth-writing car
window drawn before the remote driver can hide that driver. Core110 completes
opaque actors before drawing stable far-to-near transparent vehicle packets,
retaining original depth writes and all per-instance state. Classification
matches15,422 material groups across212 archived browser models. A separate
appearance/registry-ID mismatch prevented ID-less free-play drivers from
reaching their rider-rendering path; rendering roles now follow the existing
wire appearance contract without inventing IDs or changing authority. The
focused gates pass80 actual Metal,27 Rig/encoder and17 packet/cache/role checks.
See [rendering evidence and limits](CORE_VEHICLE_ALPHA_110.md).

Thirteen separate source/hosting/authority regressions pass against unchanged
Core110 backend source, including inventory, health, weapon, armour, melee,
coupling and terminal-exit transport. The new terminal regression is also part
of free source CI. Complete Core110 Debug SDK builds pass for Intel Simulator
(1010.814s) and arm64 iPhone (742.367s), with all202 frozen inputs unchanged.
The normal dedicated-Simulator update verifies four installed payloads and
preserves all four cache metadata files. The device build is unsigned and is
not installed on the unavailable phone. The actual shared-car UI case passes
117.094s: Root-reviewed front-quarter captures now show both distinct occupants,
side captures show the near-side wheels, and normal Exit/Jump retain the shared
Taxi identity. Fresh wire confirms native118/skin7 in seat1 and back on foot,
with browser driver1/skin2 unchanged. The live scene uses the isolated108 backend;
110 terminal authority is tested separately through actual native HTTP/WS.
[Acceptance and the seven original regression dispositions](CORE_NATIVE_ACCEPTANCE_110.md)
retain these boundaries. No original-game parity or performance claim follows.

The frozen Core109 optimized Simulator build separately passes in2963.207s.
Xcode appended a12-thread compiler argument after the requested2-thread flag;
the requested compiler-thread cap was not honored. Its202 source inputs stay
unchanged. A successful optimized build alone is not an FPS measurement.


## 2026-11-17 — Core109 built and installed-resource scene accepted

The complete Debug App builds for Intel iPhone Simulator and arm64 iPhone
against the same202 frozen inputs (2804.312s and1525.894s). The device product
is unsigned and was not installed on the unavailable phone. A normal Simulator
update verifies the actual debug dylib, Metal library, preview library and
executable separately, preserving all four cache metadata files. A fresh
read-only audit hashes every6700 unique blob backing6760 logical resources.
No App reset, cache seeding or resource-store activation shortcut is used.

The actual109 installed-resource denial UI case passes213.820s: normal main
menu/Game Files status, Guest join, a normal Jump touch and a45-second interval
without operator input. Reviewed landscape captures show the city, native
skin7, taxi/wheels, HUD and radar. The external proxy records zero asset
requests across the complete command interval while observing63 gameplay HTTP
requests and two WebSocket upgrades. The wider baseline/final counter window
contains91 HTTP requests and the same two upgrades, with zero asset attempts.
The prior107 scene attempted seven metadata requests; those bypasses are now
corrected for this actual scene. Missing stock coverage, all other scenes,
complete ISO conversion and audible radio remain separate acceptance work.

The108b actual camera probe passes one XCTest case with zero failed tests. It
completes three ordinary camera gestures and normal passenger Exit, with fresh
wire confirming native118 back on foot and browser1 retaining the same taxi ID.
The native passenger and two near-side wheels are visible. Both occupied seats
and driver skin2 are still not conclusively established by the selected views.
A teardown attachment labels the interaction failed because it reads
`hasSucceeded` before XCTest finalizes success; that discrepancy is retained
alongside the authoritative finalized Passed result. Earlier failed probes stay
failed. Recordings and screenshots remain private.

The initial broad regression is still running. Its first health/network case
reaches the600-second compile deadline under concurrent SDK work. After SDK
completion, the unchanged command passes in179.12s under the same budget and
sandbox, including the actual HTTP/WebSocket fixture. The original timeout is
not relabeled as a pass. Source and202-input hashes stay unchanged.

The independent source candidate is backed up on `codex/core109-foundations`
at `5c222500f577a7dae2232bbef437593d1b968449`; its962-file tree and107 changed
blobs are independently verified and free CI44126553765 passes. The public
project is generated from the base spec without local owner-menu references,
retaining176 compile members. The actual tested local owner project is
unchanged. GitHub main remains the verified108 milestone. No original resources,
owner recordings, private runtime carriers or captures are published, and no
retail, physical-device, optimized-performance or1:1 claim is made.

## 2026-11-17 — Core109 local-runtime and camera audit

The completed107 Game Files UI run passes normal cache/reuse, full native graph validation, explicit installed-file verification and process relaunch. A separate read-only audit hashes all6700 unique blobs backing6760 logical files. The following resource-denial scene run passes188.744 seconds of normal UI: its landscape captures show the city, character, taxi and HUD, and it receives real gameplay HTTP/WebSocket traffic. It also makes seven denied asset requests, so fully local resource routing is **not** accepted by that run.

Four direct metadata loaders bypassed the cache, requesting camera twice, atmosphere, water waves and regional environment. Those files exist in the installed profile. Two additional stock-model/collision catalogues are absent from that profile and used a separate HTTP reader. The109 correction routes the four loaders through the actual resolver and makes stock metadata consult installed admission before development HTTP. Twenty authored real-Store/Session checks pass; actual109 rendered denial acceptance remains pending. Missing stock coverage is separate from transport correctness.

Core108's complete Intel Simulator Debug build passes and its normal Simulator update preserves the cache metadata and selected mode. The actual debug dylib and Metal library are recorded separately from Xcode's unchanged executable stub. The optimized Simulator and single-file device Debug builds reached their execution limits; neither is a build pass or an FPS measurement. A separately logged whole-module device Debug build passes against the same195 frozen inputs; it is unsigned and not installed on the phone. A separate optimized per-file Simulator retry also reaches its3600-second limit with unchanged source. No optimized108 product or FPS acceptance is claimed.

The reverse shared-car interaction subflow now reaches actual native seat1, follows the browser driver through6.920m of displacement, and restores native foot state while preserving the vehicle ID. All317 saved browser frames have guarded capture and the before/motion/exit wire buffers are not truncated. Overall visual acceptance remains incomplete: dark rear/high-angle views do not establish every rider or wheel contact, and the final Root review deadline failed. Earlier setup and Apple runner/destination failures remain retained. Normal movement around the nearer local car and F entry establish the genuine shared browser driver. The archived contract explains that a healthy null-driver row can localize a held browser car, after which local entry skips the shared handshake. The saved late buffer does not establish the original authority-release trigger. These are distinct from a completed native-passenger motion/exit proof.

The camera audit isolates the original driven-vehicle collision predicate from the on-foot and legacy camera owners. Final-source private browser comparisons pass8334 checks. Native policy/lifecycle/query and bounded writer tests pass11677 checks; removing the dynamic-other exclusion triggers the intended negative. Optional diagnostics do not change gameplay and remain disabled by default. A close roof view alone does not establish a near-plane or algebra defect, and no speculative hull/fade/near-plane patch is applied.

The native compressed-radio foundation passes235 orchestration checks,982557 actual C-API assertions in both ordinary and strict ASan/UBSan runs,138 Swift archive checks and five platform compile/link targets. The pinned Xiph sources remain original; a source-hash-verified compile-only upstream libvorbis unsigned-shift fix removes a reproduced sanitizer fault. A fresh private owner comparison of seven representative records and35 windows against libsndfile is bit-identical after that fix. These checks do not establish audible playback or full-station acceptance.

Raw-generation read leases pass76 checks, the existing raw/coordinator53 checks and three SDK targets. Descriptor ownership and persistent shared generation locks protect active decoders across source replacement and cleanup; receipt metadata alone never marks a full installation verified. The actual local-radio provider and PCM scheduling pass32177 authored checks plus compile/link for device and both Simulator architectures. A negative control reproduces the prior completion-before-request-bookkeeping race. Late windows trim elapsed samples or drop obsolete data while keeping the prepared decoder. Complete App build and audible interruption/retune acceptance remain separate.

A separate actual108 normal-touch camera probe completes three ordinary gestures and yields a finalized screen recording with clear side/front-quarter views. Two near-side wheels and a front-cabin rider are visible. Both occupants are not conclusively distinguished. The fourth gesture, final exit and complete UI test are not accepted because the runner times out and its result bundle is unfinalized. No rendering change is inferred from that incomplete observation.

The frozen109 candidate contains202 build inputs. Whole-App Debug SDK builds and the broader sandboxed regression suite are in progress. Extracting raw files still does not convert the complete ISO into playable native resources. Phone/retail input, audible hardware playback, performance and exact original-game parity remain pending while the phone is unavailable. No1:1 claim is made.

## 2026-11-17 — Core108 transition and resource corrections in progress

The browser-entry cancellation defect is fixed with a bounded independent-backend change: legacy browser stand/get-in reports retain the existing driver reservation, while native final-park cancellation, explicit exit and the original lease remain enforced. The portable presence regression passes94 checks and the existing seat regression82. Private archived-getter/serializer replay and manager checks remain distinct. A fresh real browser normal Taxi/F entry now publishes its actual driver1 in registry slot11; native passenger/rendered acceptance still remains open.

Remote car/trailer wheel projection now uses the final authoritative model transform, imported wheel dimensions/travel and loaded static collision, excluding vehicle bodies. It preserves owned/dynamic suspension and body/rider/network transforms. Portable native90 and browser59 checks plus private original-reference queries pass; whole-App rendered and retail suspension feel remain separate. Explicitly unsupported specialized/hydraulic paths retain their owners.

The native Files flow adds separate raw ISO resource extraction and verification. Raw source-SHA receipts, reuse/repair/cancellation and security-scope lifecycle are separate from prepared native installation; raw files never enable Play. Public synthetic raw checks53 and private six-path original-source checks9 pass. Complete source409-file extraction through Files and native conversion are not yet verified.

Actual107 Game Files continuation confirms advancing cache progress, leave/reopen and normal cancellation while retaining cached files. A later full-page scroll carrier failed to reach its field; target-directed normal drags subsequently reach/type the field and restart real caching. No UI geometry patch is inferred. Core108 separately retains the validated requested Mac origin in a UI-only preference, without changing the active resource catalogue origin. Native radio keeps an action accessibility label with the current station as its value.

The current prepared profile still omits lazy radio index/tracks. Full offline radio/native decoding, all original resources, installed rendered acceptance, physical input/performance and matched original-game mechanics remain required. No1:1 claim is made.

## 2026-11-17 — Core107 occupants, persistent resources and live-test findings

Core107 compiles the complete Debug App for iPhone arm64 and Intel Simulator against frozen sources. Its source-only development branch passes GitHub hosting/source checks; original resources, archived-client carriers and owner captures stay local. These checks do not establish rendered gameplay or original-game parity.

The actual native-driver/browser-passenger continuation passes through normal controls: a single shared taxi moves4.413m, the browser stays attached in seat2, native driver exit restores the same parked ID, and the browser subsequently exits. The earlier full-flow attempts remain failed setup/coordination runs. The motion capture contains actual browser frames and native UI input; its long-lived wire event buffer had already truncated, so no complete motion trajectory or maximum speed is inferred. Default rear views and dark windows do not establish that every occupant was visible.

The reverse attempt failed. Native chose its nearer own parked taxi; that is valid nearest-vehicle selection and requires a corrected test setup. Independently, normal browser entry revealed an authority defect: the original get-in state sends a parked stand snapshot, and the server cancelled its pending driver reservation before the first driving report. A bounded108 correction and repeat live acceptance are required; the failed run is not a passenger pass.

Persistent prepared resources have6760 logical files in6700 verified content-addressed blobs (2.46GB). Host tests cover repair/reuse, offline reads, native graph validation and atomic actor recovery. Real Game Files UI download testing reached partial progress; its first carrier failed by reading one changing accessibility label twice for a regex. The failed result and cached files are retained. A separate corrected carrier resumes the actual operation for cancellation/full verification/restart; it is not yet acceptance of the complete installed scene.

The native ISO bridge has bounded raw extraction and real owned-resource checks. Raw extraction is not native conversion or a playable installation. Standalone full ISO conversion, matched retail mechanics, physical input/performance and complete external-server interoperability remain open. The physical107 App installed without deleting user data, but UI automation could not start; the user cannot check the phone now, so further work uses the dedicated Simulator.

## 2026-11-17 — Core106 touch ownership and paired acceptance

The real Core105 UI run exposed a covered handbrake: its reused Jump button
shared the brake/reverse frame, and brake was later in the hit-test order.
Core106 gives the road handbrake a separate44-point lower-row target, leaving
foot Jump and its special-mode handlers intact. The real UIKit carrier passes
20574 checks across144 synthetic screen/context cases and reproduces270
historical105 overlap hit failures. Its final verifier pins current controller,
HUD, stick and both test sources. These are synthetic geometry/context cases
executed with real UIKit, not144 tested physical devices.

Actual extracted input bindings pass3836 checks. The coupling-control carrier
needed its new handbrake button spy; its repaired65 checks pass with unchanged
App source, preserving the initial failed compile. An earlier240-second
concurrent-build timeout is also retained separately. See
`CORE_TOUCH_OWNERSHIP_106.md` for these boundaries.

Both complete App SDK builds pass against unchanged181-file App/resource
hashes. The optimized iPhone product remains unsigned and uninstalled while
someone is using the phone. The separate full-game Simulator joins fresh8806,
starts the real taxi job, enters, checks three distinct hittable driving
controls, presses/releases gas and handbrake, and exits with foot Jump restored.
The174.050-second actual UIKit run passes with no handbrake hit-point fallback.
The cab was stationary before that press, so braking deceleration is not
certified. Independent unpatched browser frames and wire confirm one same-ID
yellow cab, occupied publication before driver and foot publication before
final parked restoration, without `vgone`. Physical-phone/retail performance
and remaining fundamental mechanics are still open. The155-case registry is
not represented as one freshly completed full run.

## 2026-11-17 — Core105 vehicle appearance and presence

The grey native taxi was traced through export, rig decoding and draw state.
The correction retains intrinsic painted vertex colour and per-part material
slots, then applies the actual instance's original palette/custom RGB through
a separate Metal fragment entry. New neutral-painted VPC2 families are
explicitly distinguished from legacy baked WRL2. All212 families and six
working overrides are adopted only in the private candidate; actual HTTP
hash verification covers all848 files. Fresh normal host preparation accepts
the new families and rejects mixed generations. See
`CORE_VEHICLE_PAINT_105.md` for primary, actual GPU and migration coverage.

The duplicate cab was a separate authority-publication defect. The original
browser's parked manager expects the retained registry row's driver marker,
then hides its parked representation after the driving body actually exists.
Core105 reserves entry by transport and vehicle incarnation, publishes that
marker only after a valid driving report, and restores the same ID at its
final accepted pose on release. It never uses visibility-only `vgone`, which
would create an original-browser tombstone. Unbound original free-play actor
reports remain supported without giving them registry/mission authority.
Actual archived manager/serializer execution, real HTTP/WebSocket, unchanged
Swift client and18 affected server regressions pass. See
`CORE_VEHICLE_PRESENCE_105.md` for scope and remaining carjacking/removal limits.

Both complete App SDK builds pass with unchanged captured App sources. The
Release iPhone product is unsigned and uninstalled; the human-used phone and
its current Core104 world are untouched. Isolated paired Simulator/browser
screen acceptance is recorded separately. The registry now contains155 cases;
a single full155-case run has not been executed. Earlier frozen/composite
results and focused new regressions remain distinct. No1:1 claim is made.

## 2026-11-16 — Core103 stock resources, coordinates and real reference access

The previous Core102 source snapshot compiled both optimized Apple SDKs and
passed actual UIKit custom DL scene acceptance. Its full gate recorded135/141,
with unchanged sources. Two carriers needed newly added ownership dependencies;
one lacked a pinned private protocol reference. Three GPU tests exposed a real
test-platform readback problem on the discrete AMD GPU: direct render-target
getBytes returned zeros, while an explicit GPU copy returned the exact expected
pixels. Core103 fixes the carriers and uses aligned GPU-to-buffer copies while
retaining the strict existing pixel assertions. The historical failed report
is preserved; it is not relabeled as a pass.

Core103 addresses actual vehicle-coordinate ownership rather than adjusting
spawn heights. All212 original vehicle model offsets are used with the full
quaternion to convert network model origins to native physics bodies and back.
The pure calibration passes30,535 checks. Actual owned open.mp raw114 and
catalog128 checks pass for037 and DL, including independent observer conversion,
full rotation, final parked position/health and respawn cache replay. Fresh164
only transmits heading; absent parked pitch/roll is an explicit protocol limit.
Fatal wreck reports now retain cause51 and exact local vitals ownership; an
unknown absolute zero-health update is no longer mislabeled as a fall.

The stock resource path indexes18,108 exact DFF/TXD ranges in the owner's IMG
archives. It serves only declared, revalidated hashes, with bounded jobs/bytes
and no bulk extraction. The complete external COL inventory preserves original
header IDs as hints and binds exact model names to original IDE definitions.
Missing physical geometry is accepted only when complete inventory evidence
proves its absence for the exact manifest. No fake collider replaces a failure.
Four owner props have passed actual Renderer callbacks, HTTP validation, native
Metal rendering and parented Rapier collision/moving-object registration. This
is a narrow integrated sample, not a claim that18,108 resources have rendered.
Host/origin/join gates remain enforced; original resources stay local.

The current original browser service exposes a legitimate Guest-name API.
The new native account helper passes137 Swift and20 actual controlled HTTP
checks, including strict response limits, cancellation, account/build verification
and authoritative guest restrictions. The actual native Simulator form passes
its UIKit test with the Guest/name/Discord controls visible and no browser game
loaded. No external Guest POST was made by that test. User-controlled live-world
authentication remains an acceptance gate; browser login state is never imported
from Chrome.

The connected iPhone reference could not initialize XCTest UI automation.
The actual blocker to direct screenshots was older mounted developer support.
Compatible Apple-personalized support enabled a real screenshot of the installed
Definitive Edition main menu. The capture and subsequent legitimate reference
tests are local-only; this edition does not by itself prove classic-retail
physics, frame timings or full native-app parity.

Core103 full frozen-source regression, both optimized Apple builds and final
source-only release acceptance are still pending. The remaining checklist is
active. Incoming combat presentation/damage, passengers, pickups/checkpoints,
animated and supplemental stock assets, retail timing and physical native-app
input/performance remain open. No full1:1 or universal-server claim is made.

##2026-11-15 — priority override and preserved baseline

- Baseline source:482af7dc7b42be7723fb76c823d03f311c061610.
- Active branch: `codex/core-gameplay-parity-20261115`. The roleplay work is
  preserved separately on `codex/roleplay-foundation-20261115`; advanced
  roleplay implementation is paused. Original archive and production saves
  remain outside this worktree's source changes.
- Original GTA San Andreas is now the primary gameplay target. Existing
  browser JS/WASM fixtures remain useful regression evidence, not proof of
  original game accuracy. No original retail runtime test has been completed.
- Confirmed flight-to-foot heading cache ownership mismatch, a touchdown
  early return, held-position/collider discrepancy, vehicle solver history
  after relocation, and incomplete control neutralization. Work is addressing
  the shared causes before cosmetic smoothing or speculative force tuning.
- The landscape black pill in build75's screenshot matches the simulated
  iPhone's physical camera cutout; it is not evidence of a malformed joystick.
- Public source remains AGPL. Original game assets, archived scripts, converted
  runtime files and build libraries remain local. No production deployment.

## Validation ledger

Pending integrated results. Record each executed command, passed/failed scope,
and any device/runtime limitation here as work proceeds.

### Reproduced causes and implemented corrections

- Flight/swim own the actor heading until the foot task explicitly adopts the
  final facing. Jetpack touchdown publishes heading even when its motion result
  is nil. The canopy's presentation-only landed state does not repeatedly reset
  walking. The pre-fix180° snap reproduces at30/60/120Hz; the heading handoff
  test measures0° Double error after the fix, across3,976 checks. Original ANP3
  idle root rotation was checked; it does not contain a hidden half-turn.
- Surface swim movement intent now updates when the actual skeletal animator
  is present. Previously only the fallback animation path updated its target,
  so surface swimming could turn toward a stale/default world heading.
- External movement publishes current horizontal momentum for an airborne
  return to foot movement. Teleport clears jump/fall/landing/swim/flight/weapon
  transients, while retaining equipment and the separately owned death state.
- Gun arm yaw uses shortest angular distance across±π. Animation fire markers
  now own gun, launcher, thrown and stream emission timing. Dual/continuous
  emissions preserve each event instead of collapsing them into one Boolean.
  Inventory readiness updates synchronously before the next hand/substep.
- Central input cancellation clears sticks, keys, gas/brake, horn, flight and
  queued weapon/jump/deploy commands. Controller reconnect requires neutral
  controls. A cancelled horn gesture cannot toggle the emergency siren.
- Ordinary15/20FPS elapsed time is retained and movement/camera lag is advanced
  in bounded slices. Suspension is a separate discontinuity. This improves
  internal consistency; it is not a claim to reproduce retail timer bugs.
- Camera enter/exit and teleport reset task history while preserving the visible
  viewing direction at vehicle exit. Jetpack mode changes do not reset orbit.
- Held/hauling positions relocate the actual collision walker. Vehicle teleport
  rebuilds solver/contact histories while retaining damage identity. A remote
  occupied-vehicle takeover no longer overwrites its incoming pose with the old
  parked position.
- Authoritative server cadence reads optional local animation metadata, retains
  bounded elapsed-time credit for catch-up, and avoids conflicting70/80/90ms
  secondary gates. Sequenced native hits spend one accepted shot authorization;
  selected weapon, ammo, reload, replay and rate validation remain server-owned.
- Stream audio selects one active weapon instead of allowing inactive weapons
  to stop the same shared loop. The final accepted round remains visible for
  its current input frame even when readiness becomes false immediately.

### Executed focused gates

- `python3 smoke_native_heading_transitions.py`: PASS3,976 checks,30/60/120Hz.
- `python3 smoke_native_task_transitions.py`: PASS523 checks against1,871 local
  CLP clips; event multiplicity, queued cancellation and hard task resets.
- `python3 smoke_native_controls.py`: PASS14,576 checks,15–144Hz clock,
  controller neutral gate, safe-area sticks and camera handoffs.
- `python3 smoke_native_camera.py`: PASS8,334 archived-browser comparisons.
- `python3 smoke_native_horn.py`: PASS12,000 browser frames plus interrupted
  horn/siren cases at15/30/60/120Hz.
- `python3 smoke_native_wire.py`: PASS actual Swift URLSession WebSocket peer,
  heading/roll signs, foot/flight/vehicle state and shot/hit sequence identity.
- Physics, inventory, projectile, native-server and cadence focused gates pass;
  exact scopes are recorded in `CORE_PHYSICS_AUDIT.md`.
- Source allowlist check passed328 blobs at this point. Full combined regression
  run and optimized Simulator/unsigned device builds are still in progress.

### Remaining evidence limits

No original retail executable was found as a top-level installed Mac app and no
retail runtime comparison has been performed. A community reconstruction and
the archived browser are supporting references only. Physical iPhone/controller
feel, thermal/FPS performance, retail vehicle handling and every transition in
the checklist remain unverified. Launcher/throw timing is now integrated but
precise hand muzzle positions and full original recoil/targeting remain gaps.
The render camera uses current body poses during bounded lag slices; it does
not yet interpolate a complete historical physics pose at every camera slice.

## Core77 — next acceptance boundary

Core76 is committed locally at6b4a698b5cd30739d5f7ef89dcda199f0efc1990.
Its full24-gate frozen-source suite passed, and both optimized Simulator and
unsigned ARM64 iPhone builds succeeded. Simulator testing used only disposable
localhost worlds; the production server and saves were not deployed or changed.

### Actual Core76 UI and wire observations

- The installed optimized Simulator app loaded the real city, character, pack,
  original HUD, map/font and weapon data. One fire tap consumed exactly one
  round; a1.2s held touch consumed four. Reload transferred five rounds from
  reserve to the magazine (12/68→17/63).
- A59s isolated wire recording contains295 unique player packets,195.569° of
  actor/camera turning, and a flight61→ground-pack60 transition with0° heading
  change. This validates the reported landing defect under that scenario; it
  does not establish every jetpack or original-game behavior.
- A server-address typing attempt initially retained8774. It was corrected
  through the settable field and verified before connecting to8775. Tests
  against each world are kept distinct.
- Live testing found camera near-plane clipping through the character/pack
  near an obstruction and a connection-menu width collapse on repeated return.
  Those defects became additional Core77 acceptance items.
- Browser startup on the isolated world produced a blank view; automation then
  lost its debugger and native Chrome inspection timed out. HTML/scripts return
  HTTP200, but browser UI gameplay/cross-client visual acceptance is not passed.

### Implemented Core77 corrections

- Static-world ledge detection, jump/grab, hang, pull, edge, stand and vault;
  first/completion held feet and collision capsule are synchronized. Native
  queries distinguish fixed, dynamic and kinematic parents; unknown parents
  fail closed. Moving-carrier climbing remains explicitly unsupported.
- Climb animation clocks start only at phase transitions. Manual animation,
  direct fire, reload and unusable aim cannot override the held climbing task.
  Touch jump begins on touch-down and a held jump can continue a climb; the
  contextual action lets go. Teleport/death/vehicle transitions clear the task.
- Server/client inventory uses connection-scoped reserved shot tickets and
  atomic processed-shot watermarks on both HTTP and WebSocket snapshots.
  Duplicate/late replies cannot restore unacknowledged predicted ammunition.
  Reload intent remains pending until its actual response; uncertain outcomes
  freeze prediction and resynchronize. Old socket completions are ignored.
- Held instant-hit fire requests an automatic reload once when the magazine
  empties. Native reload failure rolls back its predicted animation without
  resetting locomotion facing. Projectile/stream reload rules remain server
  policies, not a claim of original retail timing.
- A camera clearance envelope hides the local mesh if the near plane enters
  the player's body, with spatial hysteresis. The existing camera follow
  equations remain intact. This is clipping protection, not retail alpha fade.
- Home/connection menus use an explicitly full-width scroll-content container
  and a required bounded column width. Keyboard editing ends before gameplay.
- Grounded jetpack removal uses the context action or equipment menu, updates
  the independent server and browser/native gear state, and preserves the
  parachute. Removal while flying, swimming, driving or dead is rejected.

### Core77 frozen-source verification

- Static climb controller/query gate:17,307 checks; actual Renderer/native-world
  integration:8,365 checks,1504 display frames,1308 fixed physics ticks and1871
  local animation clips.
- Inventory engine + actual State/Delivery:3541 checks across3200 delayed frames;
  actual native HTTP/WS delayed/reordered/reconnect integration passes.
- Camera visibility:1520 checks. Final31-gate suite passed with unchanged
  production sources. Optimized Simulator and unsigned ARM64 iPhone builds
  both succeeded. The installed Simulator executable hash matches that build;
  its bundle version is77. A separate diagnostic build also succeeded.
- Diagnostic Simulator accepted sequenced firing and held-fire auto reload:
 16 loaded/68 reserve became12 loaded/51 reserve after sustained fire, including
  one automatic17-round refill. This is functional evidence, not an FPS claim.
- The ACK backend regression is now archive-free and passes on actual Node
 22.23.5 in an isolated six-source-file checkout. GitHub CI runs that gate.

### Core77 final optimized Simulator observations

- Actual city geometry: a low wall completed a stand-up climb; a high ledge
  held in action21 and accepted a second jump for pull-up. The held hang
  ignored a one-second fire touch and ammunition remained17/68. Let go
  returned to the ground. A separate wall traversal emitted edge23, vault25,
  then foot0; its heading matched the slanted ledge normal throughout.
- The map opened with the current city position and original map tiles, then
  closed back into gameplay. Repeated pause/return kept the connection menu
  full width. Grounded contextual jetpack removal was observed in the final
  installed bundle, with server confirmation and the visible pack removed.
- These tests exposed additional defects: a selected pistol remains attached
  during a two-handed climb, and a low ceiling can leave the camera outside
  the near-plane capsule guard while the enlarged body obscures the scene.
  These are Core78 corrections, not passed Core77 acceptance claims.
- The hang/drop recording later includes a fixture teleport into the separate
  vault test. Trace segments are interpreted with those boundaries; no
  teleport is represented as continuous movement.
- Static replay over147 real city colliders found five grazing sphere-query
  differences in the zero-height-capsule approximation. Full climb results
  agreed, but strict primitive parity failed. An isolated literal-sphere
  candidate removes all five differences; cross-target integration is next.

### Owner-provided original PC reference

The supplied installer provides a direct animation/data reference, inspected
without executing the installer or included replacement executable. Pedestrian
animation bytes match the browser archive. Selected weapon profiles match all
550 checked fields;212 handling models match5,723 of5,724 fields, with one
decimal-rounding difference. The disc's modified executable has separate
provenance from the SecuROM-wrapped original installer executable. Static
reconstruction and modified-binary observations remain explicitly qualified.
No original data, binary, disassembly or converted game asset is source-release
content. There is still no original-game runtime comparison or physical device
acceptance. Advanced roleplay remains paused.

## Core78/79 — collision precision and event geometry

An independent source workspace and separate native library outputs preserve
the accepted77 build. App, Rust/header and server files are frozen together for
the34-gate acceptance run; both Apple application builds use matching bridges.

- Literal sphere queries replace the zero-height-capsule approximation only
  where a sphere is required. The ordinary motor capsule is unchanged. The
  recorded real-city corpus now has no ray/sphere/probe disagreements. Public
  game-data-free triangle-plane cases reproduce the old grazing-contact defect.
- Local and remote weapon attachments are suppressed during nonzero climb and
  swim blends, including exit blends. The selected inventory remains intact.
- The first78 preview tried proximity transparency. Actual low-ceiling UI
  testing exposed unsorted internal skeletal faces, so that effect was rejected.
  Build79 uses binary body/weapon/pack visibility with spatial hysteresis and
  a close-camera presentation clearance. Hidden local pack rendering still
  updates audio/effect state. The clearance is a native visibility policy,
  not a measured original-game camera constant.
- Target cone, range, obstruction and emitted impact use one muzzle-to-torso
  segment. Original feet-to-feet selection rejected accurately pitched close
  shots. Targets behind unloaded collision cells fail closed; world queries
  span crossed cells and exclude the local walker/probe/chassis.
- Fixed-step animation shot markers expose their current physics feet during
  synchronous emission, rather than the previous display pose. The event
  snapshot clears after emission and never delays local input.

Focused gates pass:239 target/packet checks,242 actual native obstruction/cell
checks,6,630 visibility checks,2,383 task/input/presentation checks, and8,367
actual Renderer/climb integration checks. The78 aggregate passed34/34 with unchanged production sources after two
missing local reference catalogs were copied; first failures are preserved. Its
optimized Simulator build succeeded. Its unsigned ARM64 iPhone build also succeeded, but the candidate was
rejected for the observed camera transparency artifact. Final79 aggregate/build/UI results are
recorded after they finish. See `CORE_RETAIL_REFERENCE.md` for the new direct
reference evidence, unresolved handling candidates and original runtime plan.

### Final79 acceptance

- All34 core gates pass with unchanged121-file App/bridge/server manifest.
  Optimized universal Simulator and unsigned ARM64 iPhone builds both pass.
  Installed Simulator bundle79 matches the built executable SHA256.
- The exact low-ceiling vault scene no longer renders translucent internal
  faces. The body is hidden when obstructing the close camera, and an open-area
  reset restores its ordinary opaque appearance. This validates the visibility
  defect, not original camera clearance constants or every camera transition.
- Entry, touch acceleration, reverse and exit were exercised in the original
  city geometry. The recorded acceleration segment has176 distinct vehicle
  packets and26.538m of travel. These are functional controls/handoff checks,
  not original handling or performance certification.
- City hang/pull UI tests in the preceding geometry-equivalent78 build
  kept the pistol out of both hands during the climb; afterward a fire tap
  consumed exactly one round. The scoped79 camera correction leaves those
  mechanics unchanged and its full integration regressions pass again.

### Original radio recordings and import repair

The supplied PC image contains the missing station/emergency/advertisement
packs. Thirteen packs totaling976,800,537 compressed bytes were extracted only
under the ignored retail-reference directory. All1,731 original Ogg records
have complete stereo32kHz boundaries. The lookup mixes header-inclusive and
payload-only sizes; the existing reader truncated8,068 bytes from613 payloads.
The independent reader now proves and normalizes the exact next-record span.

The compatibility programme remains unchanged. A separate explicit
full-recording variant uses complete end-granule lengths; original retail
on-air cut/schedule policy is not inferred from those lengths. The importer
creates a fresh output exclusively and protects existing inputs, aliases and
other assets from overwrite.

Real-file conversion decoded15 recordings and33,971,644 finite channel samples.
The unchanged native programme/playback source passed45 PCM windows,752,000
exact channel samples and a real AVAudioEngine offline transition. Synthetic
mixed-layout/EOF/overlap/alias protection tests also pass on Node22 without game
files. Source CI runs the independent bounds regression.

On an isolated8776 world, the installed79 app spawned/entered a car, selected
Bounce FM, switched to SF-UR and exited. Three complete PCM files appeared in
the Mac cache and the app's own cache, confirming live UI/download integration.
This is separate from the offline sample proof; physical listening is not
claimed. Normal production registration remains absent, its compatibility
programme unchanged, and no production server/saves were deployed or migrated.
See `RADIO_OWNER_IMPORT.md` for the reproducible local import workflow.


## Core80 — core state, authority and query integration

This pass keeps advanced roleplay paused. The App/bridge/server boundary is
frozen as 124 files before optimized Simulator and unsigned iPhone builds.
No Rust/C ABI or frozen native library was changed.

- Movement resets now clear obsolete fall, slope, step-easing, carrying and
  contact/exclusion history. Animation-owned held roots reset that history
  once on entry and retain the actual capsule at the held root. A streaming
  pause preserves physical momentum but discards pending input/contact debt.
  Positive elapsed samples through 0.5 s retain their time at fixed 1/60 ticks;
  suspension remains a separate pause policy.
- Vehicle authority handoff removes both promoted dynamic and parked static
  duplicates. External kept/AI poses revoke local parked prediction. Invalid
  entry leaves the existing chassis and damage owner intact. Zero health
  disables propulsion/control channels while the hull coasts, including
  helicopter lift/rotor behavior. Cancelled boarding no longer exports a
  stale door hold.
- Camera and weapon queries use ordered coverage of crossed collision cells,
  with own walker/probe/chassis exclusions. Missing cells fail closed and
  request collision data separately from GPU meshes. At most eight additional
  query cells are retained for two seconds. Camera streaming boundaries can
  be closer than the ordinary solid-wall minimum; only that unknown-geometry
  case bypasses the minimum. Loaded-wall camera behavior remains unchanged.
- Projectile prediction has a fixed 1/60 clock independent of display cadence.
  Unknown geometry pauses local prediction rather than fabricating a clear
  path or impact; server snapshots remain authoritative. Duplicate/nonfinite
  projectile snapshots are rejected. Area effects check the actual victim
  segment, and extinguishers cannot erase flames through a solid wall.
- Paid firing events sample original hand 24/34 transforms with selected weapon
  offsets and the left attachment convention. The chosen event ray also owns
  subsequent stream effects. Hidden traversal weapons do not emit. A barrel
  beyond a near wall falls back to the safe body origin. This is a documented
  native obstruction policy, not a measured original-game constant.
- Continuous weapon claims use the existing server's cylinder instead of a
  single gun cone. Multiple eligible players share the exact accepted shot
  ticket; per-victim 300 ms cadence and connection ownership remain enforced.
  Server damage/cadence policy has not been redefined as original retail.

Focused results already executed: 39,068 movement checks with 12,960 identical
native frame comparisons; 20 vehicle lifecycle checks; 7,200 interrupted rider
frames; 39 integrated world/prediction checks; 8,334 camera comparisons; 8,367
current Renderer/climb checks. Full frozen aggregate/build/installed-bundle
acceptance is recorded below after completion.

Crouch still does not resize the collision capsule. Full original vehicle
handling, drive-by, melee, NPC/traffic reactions, hitboxes and retail feel are
not established. The supplied PC data and browser replays support bounded
claims; original runtime and physical iPhone/controller acceptance remain open.


### Frozen Core80 regression result

All 40 core gameplay gates passed against the same 124-file App/bridge/server
manifest; the source remained unchanged throughout. Separately, the optimized
water reference gate passed 17,339 actual archived-factory queries with zero
height differences, including triangle tolerances, degenerate polygons and
depth limits. Its checks now remain enabled in optimized test binaries. The
water gate is included in subsequent aggregate runs.

The actual Ko/R6 muzzle replay passed 600 frames and 5,415 checks, with maximum
world-space difference 0.173 mm. All 53 original installer weapon/skill offset
rows match. Continuous-weapon testing passed 57 geometry/cadence/real-wire and
async callback checks, including failed or replaced transports.

Desktop Safari loaded the isolated 8777 city and entered on-foot play. Held
walking input moved 11.844 m from the initial position; the final feet packet
was 1484.0063,-1726.8538,12.5669. IAB connected but its on-foot activation was
not established. Native80/browser visible parity and optimized installed-bundle
acceptance remain pending. No production server or save deployment occurred.


## Core81 — input contexts, reverse view and bicycle ownership

The next pass continues the core foundation. It does not resume advanced
roleplay. App/bridge/server sources are frozen as 127 files for the expanded
44-gate run and optimized Simulator/unsigned iPhone builds.

- Keyboard and controller commands now pass through context-aware bindings.
  The main PC sprint/jump, vehicle entry, movement and weapon-selection defaults
  follow the original manual. Console face-button actions are distinguished
  from the retained modern trigger adaptation. Menus cancel gameplay input;
  held Menu/Escape cannot immediately reopen or dismiss a new pause panel.
- Weapon cycling uses authoritative owned inventory slots and serializes rapid
  selection requests. Failed, cancelled and stale-connection completions cannot
  advance a newer selection queue. Radio previous/next uses the actual station
  ring, including off and restricted vehicle modes.
- Alt walk selects the existing walk phase without adding a speed constant.
  A 5,600-frame replay exercises the actual archived walk-modifier clause and
  preserves acceleration, facing and strafe behavior. Sprint effort remains a
  separately owned input, matching that reference.
- On-foot look-behind is a temporary presentation returned after normal follow.
  It preserves persistent camera yaw/pitch, actor facing and follow/aim history.
  The actual archived wrapper and collision margins are replayed over 2,016
  frames. A directionless Float result at a missing boundary retains the
  ordinary frame. This avoids an arbitrary fallback view direction; the
  renderer already guards degenerate look-at vectors.
- Bicycle brake and charged hop are separate inputs. Cancelling input discards
  an unlaunched charge while preserving an already launched physical hop.
  Boarding and wreck transitions clear pending charge before neutral stepping.
  A shared ownership gate retains passive solver data, neutralizes drive
  controls and applies a holding brake until the rider owns control. This is
  an explicit native policy; the browser additionally supports some analog
  boarding-cancellation behavior.
- Owned bicycle pedal effort now uses the same player stamina pool as walking
  and swimming. Original 50 Hz costs flow through NativeStamina.take without
  applying its existing division twice. Pedal/breath algorithms and retail
  handling constants remain unchanged.

Focused results: 3,619 binding/dispatch/queue checks; 335 real bicycle/body,
ownership, cancellation and shared-stamina checks; 32,083 look-behind checks;
5,600 locomotion frames; and 8,334 ordinary camera comparisons all pass.
The frozen full-run/build/installed build 81 results are recorded after completion.

### Installed build 80 baseline used during this pass

Both optimized build 80 application builds passed; installed Simulator executable
SHA256 matches the built bundle. On the isolated port 8777 world, the native app
showed the actual browser player. One touch fire tap consumed one round;
keyboard R reloaded it to 17 loaded/67 reserve. Grounded pack removal succeeded.
A successful touch trial recorded 991 native samples: 3.651 m forward travel,
height 12.4028–13.4747 m, health 100 and unchanged heading 0 through landing.
An earlier automation timeout recorded no activated movement and is retained
as an incomplete trial, not a gameplay pass. Production port 8766 and saves remain
untouched. This is functional native/browser evidence, not retail equivalence.

Primary control references:

- [Rockstar PC manual supplied through Steam](https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/12120/manuals/GTASA_PC_MANUAL_FINAL.pdf).
- [Rockstar PS3 manual](https://media.rockstargames.com/rockstargames-newsite/img/manuals/en_us/GTA_SA_PS3_MANUAL_ENG.pdf).

Physical controller behavior, the PC bicycle-hop binding, original lock-on and
full vehicle weapon/submission controls remain unverified or incomplete. Retail
runtime movement, damage, handling and feel still require direct comparison.


### Frozen81 regression result

The complete44-gate run passed against the unchanged127-file App/bridge/server
manifest, including bindings, temporary reverse view, bicycle input ownership,
shared stamina, original animation/rig fixtures, camera, world queries,
projectiles and actual local WebSocket/inventory traffic. Optimized application
builds and installed81 acceptance are still pending at this entry.

### Installed81 movement/input acceptance

The optimized universal Simulator application built successfully, and the
installed executable SHA256 matched the built bundle. Native and actual Safari
browser players connected to the isolated8777 city. In826 native samples, the
W/Shift+W trial moved12.433m forward, reachedZ13.2913m, retained health100 and
heading0. Separate200ms Q/E presses visibly switched Colt 45→fists→Colt 45 with
17loaded/67reserve. A held Escape opened pause once. The first subsequent
Escape was swallowed and the following press dismissed it: this is a reproduced
modal key-release handoff defect, queued forCore82 rather than counted as a
pass. The optimized unsigned iPhone application is still building. No original
retail runtime or physical controller/device parity is inferred.

Both optimized build81 targets subsequently passed: universal ARM64/x86_64
Simulator and unsigned ARM64 iPhone. The frozen127-file App/bridge/server
manifest remained unchanged. Simulator movement/selection observations above
remain separate from physical-device and original-retail-runtime acceptance.

## Core82 — animation-owned melee, input handoffs and equipment

This pass continues the core-first override. The frozen candidate contains 131
App/physics-bridge/server files. The expanded 50-gate regression and both optimized
application builds subsequently passed; installed acceptance is recorded below.
Roleplay expansion remains paused.

Melee requests now enter a source-derived edge buffer and the real R6 animation
task. Damage is considered at its hit marker, with event-time feet, heading,
weapon and combo/run/ground identity. Rejected or cancelled requests cause no
hit and reserve no ammunition sequence. The previous immediate3.5m wall-clock
fist branch is removed. Actual original PC data agrees across403 checked melee
fields; playable-attack flags and clip-capped chain markers are validated too.

Guard/block and simultaneous aim-plus-jump use the original tutorial semantics.
They do not enter gun camera aim or leak an ordinary jump. The distinct special
attack intent stays unsupported while its authentic clip/task mapping is unknown.
Held keyboard/pad/touch input no longer re-buffers a punch every display frame.
Owned nonzero melee metadata no longer requires ammunition readiness.

Every valid melee hit marker advances the public strike counter, including
misses and blocked targets; victim damage messages do not count it twice. This
restores remote missed-punch playback. Remote ground-strike visuals now infer
nearby floored/dead walking people using the actual wrapper's horizontal rule.
That inference is separate from actual hit targeting and server damage checks.

Native targeting uses the archived reach/radius, height, facing and nearest/
prone selection rules. World visibility fails closed for a chosen victim. The
independent server also rejects fists through blocked/missing geometry, retains
selected-weapon/connection authority and no longer requires a prior gun shot
for owned nonzero melee. Existing local damage/cadence policies are explicit;
unsupported damage/acquisition for melee10–15 is not invented.

The folded parachute now follows animated spine3 with its evidenced model-local
transform. Native model/cache and wire agree on effective equipment, including
swimming and airborne jetpack arm restrictions. Grounded worn-pack combat uses
the same melee capability gate throughout the frame. Native parachute utility
selection remains a documented bridge policy, not full browser inventory parity.

The installed81 acceptance exposed a lost opening-Escape release across modal
presentation. A shared handoff records release in either presenter or panel,
without reseeding on appearance. Original PC tutorial data also identifies the
bicycle-hop secondary-fire action; LeftCtrl/keypad0 now charge/release hop,
separate from braking. No guessed crouch collider or movement constant was added.

Focused evidence before the full frozen run:5,040 actual melee/R6 frames and
31,275 checks;3,798 binding/dispatch/lifecycle checks;8,369 integrated climb checks;
480 actual holder/rig frames,5,320 bag-vertex comparisons and maximum0.173mm error;
plus2,325 remote ground-context cases and4,659 checks. Synthetic server/HTTP tests
cover wall/missing-world rejection, owned/unowned melee, ticketless-gun rejection,
metadata GET/HEAD, join/origin gates and private-data separation. Actual Swift
WebSocket and inventory/cadence regressions also pass their focused runs.

Original retail runtime timing/feel, physical iPhone/controller behavior,
fighting styles, special/stealth tasks, utility-slot selection and the broader
parity-ledger gaps remain open. The owner identified the forthcoming iOS file as
Definitive Edition; no file path has arrived or been inspected at this entry.
Production 8766, its saves and the stable LAN deployment remain unchanged.

### Frozen82 regression result

All50 core regression gates pass against the unchanged131-file App/bridge/server
manifest. The initial aggregate was49/50 because the new wire fixture attempted
to inspect a private counter. That fixture now verifies the actual outgoing
WebSocket counter values3,4,4 for hit, miss and rejected gun-on-melee requests,
and the focused rerun passed. The original failed report and corrected run are
both retained privately; no App change was needed. Host, optional Discord and
radio-import release checks also pass. Both optimized application builds and
the bounded installed82 acceptance below subsequently completed.

### Optimized 82 builds and installed acceptance

Release build 82 passed for the universal ARM64/x86_64 Simulator application and
the unsigned ARM64 iPhone application. The installed Simulator executable
matched its built SHA-256:
`4a2eacc68d007c2172c84431895a4048eedf686c8b305ab337d893c01f21b579`.
The iPhone build executable SHA-256 was
`65d05e58e9b6811359332724dbe578027b64b2af783f2055aa456231c206ac17`.
The frozen 131-file App/bridge/server manifest remained unchanged. An iPhone
build is not physical-device execution or controller acceptance.

The native Simulator and actual browser connected to the isolated 8778 world.
A fresh Escape correctly resumed from pause, exercising the modal release
handoff that failed in the installed 81 trial. One native punch reduced the
browser player's server armour from 25 to 17 and advanced the native strike
counter to 1. A separate 1.6-second held-miss trial produced one further strike
counter increment to 2 and left the browser player's armour at 25. This verifies
bounded hit/miss and held-input behavior, not retail damage equivalence.

The guard/block trial captured 509 samples with actions 0, 28 and 36. Player Z
remained 12.5668745 throughout, so the tested block input did not leak a jump.
Car entry, W acceleration, braking and F exit worked, with native health 100
and vehicle health 1000 in the captured packets. That initial fixture contained
overlapping nearby parked spawns: the result is functional contact/transition
evidence and must not be counted as clean handling parity.

A clean BMX brake recheck captured 415 samples at constant Z 12.4015999. The
separate touch-hop trial captured 423 samples, starting at Z 12.4015999 and
reaching 13.345336, with native health 100 and vehicle health 1000. It demonstrates
the tested brake/hop distinction without claiming every bicycle input context.

Build identities, the initial and resolved gate reports, and the live packet/
sample summaries remain in ignored local acceptance evidence. No physical
iPhone/controller or original retail-runtime parity is inferred. Production
port 8766, its saves and the stable LAN deployment were unchanged. The supplied
Definitive Edition IPA and its menu are a separate next reference/design pass;
this release does not claim an original story Singleplayer runtime.

## Core83–84 — owner DE menu and further core transition audit

The owner's Definitive Edition IPA was investigated as a local data source.
Selected Pak indexes and compressed payload hashes, tagged UMG properties,
resolved font/texture imports and raw pixels established the menu presentation.
The independent importer reproduces six PNGs, two unchanged fonts and four
unchanged frontend WAVs. All original bytes and decoded outputs remain ignored
under local-only. The menu implementation and bounded importers are independent
public source. See NATIVE_DE_MENU.md and OWNER_MENU_IMPORT.md for the exact
presentation scope, touchscreen adaptations and unverified runtime animation.

The three title actions connect to actual guest Multiplayer, Game management
and native Options. There is no advertised story campaign or fake voice/chat/
character-slot UI. Existing profile/statistics/status APIs and per-server guest
identities are reused. Persisted settings apply to their renderer, camera,
radar and audio owners; default gains and gameplay values are preserved.
Menu keyboard/controller ownership is released across responders, so closing a
menu cannot repeat its Escape/Space into gameplay. Raw keyboard state also
clears on lifecycle interruption. Pause remains available during reconnection.

Menu integration checks passed101 geometry assertions across compact/wide
phones, iPad and design canvas;450 settings checks;25 existing management plus45
real HTTP connection checks;27 extracted responder checks;152 gain/envelope plus
25713 real offline PCM checks. Every one of15180 samples in the four original
menu sounds matched an independent decoder. The importer passed its synthetic
integrity/boundary groups and two complete selected-resource imports with exact
output hashes. Core83's56 aggregate gates passed against unchanged App sources.
Both optimized diagnostic Simulator/device builds passed. Installed diagnostic
UI confirmed the original art/font rendering and actual saved profile, statistics,
server information and contextual help. These builds preceded the final input/
core fixes and are not substitutes for final Core84 build/installed acceptance.

That passing baseline did not establish complete cadence parity. A separate
real native-controller/Rapier/Renderer probe found a constant2m/s movement became
0–4m/s at120 display FPS; deploying a parachute at the tested fixed tick inherited
zero horizontal speed. The old renderer differentiated fixed-step body position
using a display-frame delta. Core84 publishes the last committed fixed-step
velocity, retains it across zero-tick display frames and supplies it before
water/parachute handoff. The30/60 baseline is unchanged;120 now inherits the same
2.000005m/s at that tick. No averaging/filter or guessed acceleration was added.

The same audit reproduced a queued fallback jump surviving cancellation: a
half-tick press, cancelled outer input and another half tick still launched at
rising6.07. Cancelling the controller's queued travel/jump intent now preserves
its accumulator, committed velocity and ongoing physical/root-motion state.
The expanded real integration gate passes69333 checks across30/60/120/uneven
cadence, original animation clocks, actual jetpack touchdown, wall contact,
streaming pause, reset and queued-intent cancellation. Original retail-runtime
feel and all moving-carrier cases remain separate verification requirements.

The network audit also found that native receive failure permanently closed
its socket, and a naive retry would teleport a stale owned vehicle on hello.
Core84 adds bounded retries/watchdog/foreground repair and requires a fresh hello,
matching inventory and complete world baseline before accepting gameplay.
Connection loss clears old peer state, pending commands and local driver/body
ownership without parking/exit packets or an exit-side offset. It preserves the
self-hosted server's existing fresh-spawn policy; this differs from the archived
browser's guarded reconnect spawn behavior. Saved account identity and a new
inventory nonce serve different purposes. HTTP generations cancel/suppress old
peer replies, prevent an older GET rolling back a mutation and preserve current
busy ownership during reentrant callbacks. Full network/build acceptance is
recorded separately after those concrete checks complete.

### Core85 — keyboard events must not reach a covered presenter

Installed Core84 live acceptance found a gap despite60 passing regression gates:
Escape opened the game pause path and was also forwarded to UIKit's next
responder. Its presenting connection screen now inherited the DE Back handler,
so that second handler dismissed the game. The exact candidate build and
observations were retained privately. This was not a server disconnect or a
Metal-rendering failure.

Core85 consumes keyboard presses owned by the game and forwards only non-key
presses. Covered title/submenu controllers also reject navigation while they
present another controller. The added responder-chain test must model actual
super-to-presenter propagation; a responder stub that silently dropped super
calls was insufficient coverage. Final build/live regression is recorded after
this correction. Core83/84 remain bounded diagnostic candidates, not releases
claiming complete native interaction parity.

### Core85 final native/source checks

The corrected frozen App passed all60 aggregate gates without source changes.
The responder suite now has61 checks: it retains the original27 release-latch
cases and adds34 real-method propagation/mixed-batch/covered-parent cases.
The frozen Core84 handler specimens reproduce the old failure. Optimized Core85
builds passed for universal ARM64/x86_64 Simulator and unsigned ARM64 iPhone.
Simulator executable SHA-256:
`6875423c8e491e57f5b2130c1494ed46f44ff95cd93592db18f2915b58030a2c`.
iPhone executable SHA-256:
`5317f1655fcbfb43b5ca4873e1595d53cc565bf14480633254a108dc4ec6432e`.
The131-file App manifest remained unchanged. Generic-device compilation is not
physical-device performance or controller acceptance.

Installed final-build acceptance loaded the real isolated multiplayer world as
the existing guest beside a browser player. Escape opened Pause, resumed and
opened Pause again while preserving the game, inventory, cash and both peers.
The in-game Options route returned to the same live game on Back/Escape; its
visual capture was unavailable during that transition. The same actual Options
controller was visually exercised from the title screen. Resolution/FPS changes
updated their persisted values. A separate compact iPhone SE3 Simulator displayed
the original title art and all actions in landscape; keyboard focus scrolled to
the settings footer, changed Reduce Motion, restored defaults and returned.
Intermittent blank computer-use captures are not counted as visual acceptance.

Fresh-source packaging received a separate correction: XcodeGen's `optional`
source flag merely suppresses path validation, leaving a dangling copy reference.
The public base project now contains no original-resource reference. A second
owner spec adds that folder only when the build wrapper finds a manifest.
Four isolated generation cases preserve all110 App compile entries and all App
bytes; the generated owner-enabled project is byte-identical to the project
used for the accepted private builds. This verifies both source-only fallback
and owner-resource packaging without publishing original files.

A separate sampled-stack hypothesis about KCC query-tree construction was tested
before changing the engine. The actual spawn cells had109 colliders; controlled
queries were under0.1ms. An isolated bulk-tree alternative preserved exact query/
contact outputs but slightly regressed the interleaved city cases. It was not
adopted. The retained private research does not establish the cause of capture
failures, device FPS or a general renderer performance result. Accepted physics
source/libraries remain unchanged.

An additional isolated iPhone17 Pro Max Simulator displayed the title artwork,
logo, portrait and all three actions with notch-safe landscape placement.
Keyboard opened the actual Options controller and Back returned to the title.
The display and camera settings were visually checked at the large size.
Repeated capture sometimes returned blank; rotating/rebinding recovered actual
rendered menu and Options images. This does not extend acceptance to a physical
phone or prove original runtime animation timing.

### Core86 — core task, camera, damage and vehicle audit

Water-exit simulation was advancing the pedestrian animation twice in one
physical tick. Four real controller/CLP exit paths now match a single-update
reference. A landed parachute could also leave state10 active during jetpack
takeoff; the new task clears obsolete canopy-phase ownership. Available current
velocity is separated from retained committed momentum, so streaming suspension
does not export motion or destroy a later water/parachute handoff.

The actual fixed motor/camera integration reproduced moving crouch-camera
heights of1.01–1.16m at15/30/120/144Hz versus1.40m at60Hz. Repeated body poses
were mistaken for stopping. An optional committed planar-speed input now keeps
the existing moving stance across display rates while preserving the default
archived camera contract and its separate golden. See camera-motion audit.

Regular foot falls previously selected collapse/skid animations without health
loss. Actual native-floor drops now apply the observed browser policy once,
bypass armour, and enter fatal animation on the landing tick when appropriate.
The pre-round below-one-health death threshold is preserved. Controlled3/10/30m
drops agree across30/60/120/uneven cadence. These constants are browser evidence,
not newly verified original retail-runtime values.

The new damage work also reproduced an old multiplayer race: local100→60HP
could be overwritten by an earlier90HP server snapshot. A clamp alone would
lose separate server damage. Optional nonce/sequence/revision health ACKs compose
these losses as50HP, reject stale HTTP/hello state, accept actual server healing,
and resolve death/respawn after authority. Duplicate hello must neither clear
pending damage nor teleport. A lost accepted reply settles from the fresh peer
baseline without replay. Legacy servers keep their previous compatibility path.

Reload snapshots identified by the same server deadline no longer extend the
local estimate when duplicated or accompanied by an unrelated inventory
revision. Native reload begin cancels unconsumed trigger intent without changing
the raw archived animation method. Synchronous HTTP busy/offline rejection no
longer starts feedback after cancellation. Real-CLP and extracted dispatch gates
retain historical negative controls from the accepted prior source.

Explicit vehicle disappearance now differs from distance-list omission: parked
prediction bodies, colliders and pending shoves are removed only for explicit
despawn or world teardown. Removed local ownership cannot leave a delayed exit
or manufacture a parked hull. Fresh worlds also clear old animation/gear/effect
caches and camera shake. Original effect definitions remain loaded and reusable.
Parked aircraft retain rotor/gear through demotion/re-promotion, with real
Renderer glue and remote-player kit precedence checked. Existing train placement
now supplies carriage consists for remote and parked locomotives as well as the
local driver; curve/reverse/exit/streaming cases reuse the same placement math.

All original fixtures, extracted resources and retained evidence stay local.
No acceleration/suspension constants, short crouch capsule, original skill
curves, towing joint ABI or full NPC behavior were guessed into place. Retail
execution, physical controls and remaining large engine systems remain open.
The frozen application source passed both Release builds: universal Simulator
and unsigned ARM64 iPhone. All 132 App files and the six engine/backend inputs
matched the recorded snapshot afterward. The complete regression run passed
72/72 gates with unchanged sources. A later, separate respawn-dispatch gate
passed 37 checks and is now included in the runner for subsequent full runs.
Archived camera and particle goldens also passed, as did host/join-code/origin,
mocked optional Discord and generated-project matrix checks. These are distinct
from retail runtime verification and physical iPhone performance tests.

Integrated UI acceptance used an isolated loopback server on 8780 and its own
saves. Production 8766 and the prior 8778 QA instance were untouched. Native and
Chrome guests joined without Discord; both occupied the same world, and the
native HUD listed both guests. A real city-floor drop reduced native/server
health to 82; a higher drop produced death, and accepted server respawn restored
100 HP at the city centre. The live sloped-city result is not substituted for
the controlled flat-floor fall fixtures. After a deliberate QA-server restart,
native recovery retained the guest account, received a fresh nonce/baseline and
accepted crouched movement. A test Colt 45 loadout fired 17→14 rounds and reload
completed 17/65. UI capture was intermittent; Simulator's own Save Screen action
retained rendered acceptance views locally.

Held-fire UI testing also surfaced a server interval rejection during normal
animation-driven fire. Successful ammo/reload transitions do not close that
cadence issue. A separate receive-jitter reproduction is in progress; the
frozen candidate's existing rate limits have not been relaxed without evidence.
No original-game runtime, physical controller, device FPS or 1:1 gameplay claim
is made by this batch. All screenshots and fixture assets remain local-only.

### Core87 — reject false receive-time firing failures

The held-fire warning found during Core86 acceptance was reproduced separately
using the real native animator and local CLP. Under the tested frame grouping
and 0–20 ms receive jitter, the old rate bucket rejected 568 of 69,060 events in 106
of 140 cases. It began with only one token, leaving no credit for ordinary
startup grouping or small arrival variation. Continuous 15 Hz traffic also
exceeded the old four-token reservoir under the tested jitter.

The independent server now starts with its full bounded transport allowance:
two ordinary events and five continuous-stream events. The latter adds one
20 ms stream token for arrival variation. The sustained refill interval and all
native animations remain unchanged. Source-driven tests accept every event in
the stated 140 cases; synthetic pressure tests enforce the 2/5 limits and the
same sustained rate, including reconnect, switch and persisted cooldown.
See `CORE_FIRE_ARRIVAL.md` for the precise envelope and evidence limits.

Core87 has no App source, physics library or original asset changes. Core86's
native Release builds and 72-gate result remain their own frozen acceptance
record. The expanded aggregate runner is for subsequent full prepared-engine
runs; it has not been presented as a newly completed full Core87 run.

Focused Core87 acceptance passed 14/14 gates: 11 server/inventory/health/melee/
vehicle Node gates, the native real-animation arrival gate, native ammo
reconciliation and atomic shot delivery. All 132 App files still match the
Core86 frozen source. The first HTTP melee-assets attempt hit the sandbox's
loopback-listen restriction; its authorized isolated rerun passed. No production
listener or saves were changed. This is not a newly run 75-gate aggregate, new
Simulator playtest, device measurement or original retail comparison.

### Core88 — shared effort, combat ownership and physical towing/tools

Continued the core-mechanics priority through movement, combat, special
vehicles, controls, native physics and the independent server. Advanced
roleplay remains deferred; this batch does not establish overall 1:1 parity.

- Movement effort now follows the checked incoming-task ordering: exhausted
  underwater preparation, swimming recovery before its state transition,
  airborne/parachute recovery without erasing cached sprint pace, and no
  dead-task budget/counter advancement. Recovering breath remains visible
  after surfacing or reaching shore. Full original stat/training curves
  remain unavailable.
- Actual task eligibility gates new foot attacks, aim and committed animation
  emissions separately. Stun suppresses melee/gun markers; a reentrant
  first-hand callback cannot spend a newly selected weapon's second round.
  Accepted final stream rounds keep their presentation. Utility slots no
  longer manufacture ammo/melee attacks; actual detonator, parachute deploy
  and dead-player respawn actions retain their owners.
- Trailer/tow constraints use imported body-local anchors, confirmed topology,
  native spherical joints, two-link limits and source release conditions.
  Tow anchors move continuously. Forklift plates and the original selected
  dumper/dozer spheres move with their tool pose; hauled cars receive the
  source held force profile. Working values persist across parking and body
  promotion, while cancelling input releases the axis.
- Six working model families are staged together with mesh, normals, atlas and
  metadata validation. The HTTP overlay rejects incomplete exports. The
  original configured Andromada frame is absent, so no invented ramp/control
  is exposed. Remaining moving triangle-query deformation and live load
  carrying are explicitly open.
- Context controls preserve normal driving, nozzle, horn, bicycle, radio,
  deploy and respawn actions. Tow directions account for the original
  reversed hook axis. Independent touch releases do not erase another held
  button. The full binding gate passes 3,833 checks.
- The independent server negotiates connection/sequence-owned attachment
  acknowledgements, validates current driver/model/geometry/claims and emits
  actual legacy unhitch messages. It preserves work state in parked/owned
  rows. Reconnect, exit, death and entity deletion revoke attachment claims.
  Wire-body transforms were checked through 162 actual encoder/decoder cases;
  the server's extra 20 mm acquisition tolerance is a documented transport
  quantization policy, not an original gameplay constant.
- Cross-system review reproduced lost safety cleanup: declining the first
  detach enqueue previously produced attempts 1→1→1 while the physical joint
  had already vanished. Invalid confirmed links now retain cleanup intent
  until authoritative removal; the checked result is 1→2→2, with no uncertain
  replay after the second request queues. Safety detach can run under covered
  input while new acquisitions remain blocked; nonce/owner checks still apply.
- The additive Swift/C/Rust bridge implements spherical joints, lifetime and
  parent-local collider movement. All five Apple libraries and ABI links
  pass. The expanded actual WASM/native joint gate passes 56,094 checks,
  including genuinely overlapping contact suppression and force events.
  Six archived pre-step whole-world ray misses differ from native immediate
  queries; this known query-policy difference is retained, not called parity.

Focused evidence is documented in CORE_EFFORT_RECOVERY_88.md,
CORE_COMBAT_TASK_OWNERSHIP_88.md, CORE_VEHICLE_COUPLING.md,
CORE_VEHICLE_CONTROLS_88.md, CORE_COUPLING_TRANSPORT_88.md and
CORE_COUPLING_SERVER_REVIEW_88.md. The additional
CORE_COUPLING_BACKEND_INTEGRATION_88.md records 160 checks using the actual
native URLSession client, copied real backend/Peer/authority and a separate
legacy-protocol WebSocket observer. Eight attachment requests across two
cookie/nonce sessions cover two links, rejection/sequence continuity, five
legacy releases, cooldown, saved work and an accepted deliberately lost ACK
without replay. Initial garage/anchor data is synthetic administrative fixture
setup; the observer is not a rendered browser game. Original expressions, binary resources,
catalogs, generated rigs and numerical traces stay local-only. REA tooling was
unavailable; new source probes used ordinary local Node execution and have no
fabricated REA Evidence IDs.

Final frozen full-suite acceptance passed **89/89 gates**, with all captured
production, importer and test sources unchanged throughout the run. Both
Release Simulator and unsigned generic iPhone builds passed against unchanged
production sources; both bundles identify build88. All five native Apple
physics libraries and Swift/C/Rust ABI links pass. The final expanded coupling
gate passes 161,058 checks; working rigs pass 182,608 matrix checks over 606
archived poses; effort/breath passes 104,253 comparisons plus 15 guards; the
actual native/backend/legacy-observer integration passes 160 checks. These
results apply to the bounded regressions described above, not retail parity.

The first aggregate is a diagnostic run:
84/88 passed, with four reduced-harness compile failures repaired in the shared
movement fixtures and bicycle harness. It predates the final
cleanup/covered-input fix. The initial app build exposed the missing Apple
Metal compiler component, which was restored through Xcode's component tool;
the pre-cleanup build was intentionally interrupted for the final source.
Those attempts are retained separately and are not final passing acceptance.

Two additional regressions use unchanged existing test bodies and the frozen
v2 native library. All 212 production chassis, including trains, enter/exit;
the tested real-contact driving trajectory agrees at 60/120 Hz. The actual
archived unattended manager generates nine scenarios/3,480 frames; the existing
native controller comparison covers its seven non-pool cases/2,580 frames.
Maximum position error is 2.20e-17, with zero health error or damage-state
mismatches. These bounded regressions do not establish original retail vehicle
handling or live traffic behavior.

No physical input, device FPS, new GPU playtest, live browser/native vehicle
scene or original retail runtime comparison has been established here. The
owner plans to update the iPhone 12 Pro and install Definitive Edition; actual
version/install/runtime availability remains to be verified. Original-game
comparison stays an open checklist requirement.

### Core89 — delayed attachment confirmation

Further lifecycle review reproduced a gap after the Core88 acceptance freeze:
confirmation can arrive after loaded trailer/tow anchors have moved beyond the
existing 1.5 m/3 m break distance. The local helper declines joint creation, but
its old break checks only inspect joints that already exist. That leaves a
server attachment without a local constraint. The executed old-helper matrix
produces no cleanup for loaded anchor separations of 1.51 m and 3.01 m.

The separate Core89 candidate marks that confirmed suffix for cleanup when
both endpoints, bodies, compatible definitions and anchors are present. It
preserves the existing distances and releases downstream constraints in reverse
order. Missing entities/bodies/definitions/anchors continue waiting for data.
Reconciliation precedes the existing generation-scoped cleanup dispatch, so
declined delivery retries while accepted pending requests remain deduplicated.
The accepted Core88 source, 89-gate report, libraries and bundles remain intact.

Core89 final acceptance passes **89/89 gates**, with all captured sources
unchanged, plus Release Simulator and unsigned generic iPhone builds, both
identified as build89. The expanded real-Rapier coupling gate passes 161,133
checks, including 75 new delayed-confirmation checks. Every other App file is
byte-identical to accepted Core88 apart from the bundle version; the already
validated v2 physics libraries are reused as read-only dependencies. No
original retail, physical input, rendered browser scene or iPhone performance
claim is made by this follow-up.

### Core90 — moving vehicle surfaces and physical support

The audit found missing trailer support spheres and a terrain/plate friction
combination inherited from chassis defaults. Actual archived/native body
replays now cover the correct support lifecycle and friction. The hauling
transition recreates the physical solver; release retains its current momentum.
Existing coupling fixtures now follow the current hauled body, rather than
asserting separation against a disposed pre-haul handle.

A separate pedestrian tread importer, Float32 query mesh, carry coordinator
and live native scene adapter now connect support to the fixed foot motor,
locomotion facing, knock momentum, boat water suppression, post-step display
and browser-shaped attachment packets. The actual native/server/legacy peer
regression verifies both attachment and detach. Original assets and reference
fixtures stay local.

[Core90 evidence and remaining limits](CORE_MOVING_SUPPORT_90.md) distinguish
controlled coordinator queries, physical/native integration, protocol tests
and the outstanding original retail/device/rendered-scene acceptance. Three
exact knock-direction threshold samples have documented adjacent-bin numerical
ambiguities; no bitwise or1:1 gameplay accuracy is claimed.

The first aggregate run found an outdated dispatch test double and a real
local/remote presentation mismatch. The corrected adapter uses the live visual
entry pose independently of physical body queries; presentation also refreshes
on display frames with no motor tick. The expanded actual native runtime gate
then passes3,253 checks, including matching remote attachment transforms. The
initial92/94 run was not accepted. Final frozen-source acceptance is recorded
separately after rerunning the full suite.

Core90 final acceptance passes **94/94 gates** with captured sources unchanged.
Release Simulator and unsigned generic iPhone bundles both report build90 and
all five Apple Swift/C/Rust ABI links pass. The six new/expanded support gates
retain their own reference, source and runtime limits. No original game data
is included in the public source release; original retail, rendered scenes,
physical input and iPhone performance still require separate acceptance.

### Core91 — eligible vehicle ledges and support handoffs

The existing finder already checks source vehicle speed/clearance, but native
Renderer rejected every nonfixed ledge afterwards. Executing the actual
archived entry predicate confirms that eligible vehicle ledges are accepted.
The expanded native regression reproduces the old rejection before removing
that extra guard. It now passes21,269 checks, including full low/high vehicle
climbs across three body kinds and three display rates. Support handoffs to
climb/swim/flight/death/driving add50 checks to that separate runtime gate.

[Core91 evidence](CORE_CLIMB_ADMISSION_91.md) retains the distinction between
world-space ledge snapshots and still-unimplemented entity-relative handholds.
It also records the corrected position-kinematic velocity fixture. Full frozen
regression and native build acceptance are recorded separately.

Core91 final acceptance passes **94/94 gates**, captured sources unchanged, and
Release Simulator plus unsigned generic iPhone builds91. Only the bundle
version and one extra Renderer admission guard differ in App source from
accepted Core90. The unchanged bridge/header/core retains the prior five-link
Apple ABI evidence; Core91 builds also link the real platform libraries.
Retail/device/rendered acceptance remains open.

### Core92 — local accepted-hit feedback and replicated knockdown

Native hit reception previously updated health/status without invoking local
reactions. The animator's existing remote damage logic did not fix that missing
local route. Decoded knockdown rows also lacked a corresponding outgoing local
tag. The response now preserves health authority and connects actual weapon,
source position, piece and liveness context to original reaction decisions,
real native clips and one-shot motor impulses.

The archived hurt decision replay passes12,532 checks; actual native/backend
transport proves snapshot/event races, deliberate duplicates and legacy down
recovery. [Core92 evidence and exclusions](CORE_LOCAL_HIT_92.md) document the
separate model, animation/physics and transport boundaries. The real clip gate
corrects its fixtures to use canonical clip names, preserve animation-owned
travel and wait for a fixed tick on high-refresh display frames.

Core92 final acceptance passes **97/97 gates**, captured sources unchanged, and
Release Simulator plus unsigned generic iPhone builds92. The response model
passes12,532 checks; the real clip/native motor gate passes2,179 checks; actual
native/backend transport passes13 client and10 authority/legacy checks. The
unchanged native bridge/header/core retains Core90's five-link Apple ABI
evidence, and both Core92 builds link their actual platform libraries.
Original retail, rendered scenes, physical input and device FPS remain open.


##2026-11-16 — Core93 front blocking and hit-event ownership

The blocking pose and independent damage authority disagreed. Added an
owner-profile-based strict front block before armour/health subtraction and
wired accepted parry feedback to the real local animator. A distinct hit event
sequence prevents unchanged-health blocks from being lost while rejecting
duplicate/stale events and resetting ownership on reconnect.

Focused actual archived decisions, native animation/motor and actual native
HTTP/WebSocket/server plus legacy-shaped defence pass within their documented
boundaries. Core93 final acceptance passed99/99 unchanged-source gates and both native93 builds. See
[front melee blocking](CORE_MELEE_PARRY_93.md) for scope and open limits.


##2026-11-16 — Core94 bike crash and rollover handoff

Added the missing owned bike contact-to-rider path: actual original impact
weighting, retained pre-impact velocity, contact-gated rollover, consumed
ejection event, forced controller exit, directional knock/death and single
local health report. Native parking preserves the released bike's physical
momentum. Recovered the source adjacent point from the entry clip's end root;
full general exit-clearance planning is still a documented gap. Focused rule,
physical and actual exit-method gates pass; frozen full-suite/build acceptance
is running. See [bike ejection](CORE_BIKE_EJECTION_94.md).


##2026-11-16 — Core95–97 vehicle handoffs and crash armour

Completed wrecks now release/defeat an occupant once; lost-water vehicles
release a living actor to the native foot/swim owner. Preserved the existing
death cause on forced exit and the released hull's state/momentum. Added the
original no-buoyancy water fallback and verified adjacent entry-end-root geometry
against actual rider frames.

The deeper hurt audit found crash damage bypassing armour in the first draft.
Core97 moves impacts and falls into one ordered health/armour prediction and
acknowledgement namespace. Rendering reports the amount once; the shared owner
predicts and reconciles both values. Wreck defeat remains its separate fatal
path. Focused actual archived/native/transport checks pass. Combined frozen
acceptance is running; the Core94–96 intermediates are not public releases.
See [combined evidence and remaining differences](CORE_GAMEPLAY_FOUNDATION_97.md).


##2026-11-16 — Core98 browser/native armour consistency

Legacy browser actors could consume armour locally without updating the
independent server. Added bounded decrease-only legacy armour synchronization;
stale frames cannot heal a shield. Acknowledged native peers retain sequenced
authority. Player rows now publish that authority instead of raw reported armour.
An18-check actual-handler regression covers both owners and observer rows.
Native sources are byte-identical toCore97; final combined acceptance is running.


##2026-11-16 — Final Core98 combined acceptance

PASS107/107 regression gates, captured source unchanged. The final native App
bytes exactly match both successful Release97 Simulator/iPhone builds.
Actual isolated iPhone12Pro Simulator UI testing passed menu, anonymous guest
connection, world entry and a synthesized movement-stick gesture. Server trace
records10.14m travel and a stable position after release; scene inspected.
Earlier intermediateCore97's one integration compile timeout is retained in its
raw report; the same integration passes442checks in the final complete suite.
No intermediate94–97 source release was made. All original assets, references,
captures and outputs remain local. Retail1:1/device performance is not claimed.

## Core99 — driver exit placement and delayed geometry ownership

Replaced fixed/animation-only exit placement with the archived search policy
over original imported hulls, actual native ground/reach queries and foot
capsules. Missing cells defer ownership, health effects and exit packets; stale
retry identity and changed wreck causes are handled before release. See
[CORE_VEHICLE_EXIT_99.md](CORE_VEHICLE_EXIT_99.md) for evidence and limits. The
new real-Rapier runtime and archived planner gates join the frozen regression
suite. Retail phone capture remains pending while the owner is away.

Investigated reSA/open.mp as requested; recorded current lack of native legacy
protocol support and a scoped compatibility path in
[SERVER_COMPATIBILITY.md](SERVER_COMPATIBILITY.md). No third-party engine code
or binaries were imported.

## Core100 — separate pedestrian and chassis exit facing

The completed native exit could face away from both the chassis and resumed
camera. Preserve that actor facing in the immediate exit packet while keeping
the parked body's angles. Real native/server/legacy-observer tests cover nine
first-packet cases; the real Renderer/controller runtime now imports the
production direction property and checks three different angle roles. See
[CORE_EXIT_FACING_100.md](CORE_EXIT_FACING_100.md). No original-site/SA-MP/open.mp
join or retail-gameplay parity is claimed by this change.

Final combined acceptance passes110/110 frozen-source regression gates and
Release100 Simulator/generic unsigned iPhone builds. Actual UIKit/Metal guest
testing completes taxi entry/exit,5.33m walking, jetpack takeoff/turn/descent and
landing. The first exit packet and subsequent idle samples retain the actor's
facing separately from the parked chassis. The airborne/grounded wire boundary
has0rad heading change at251ms sampling. Six full-screen captures were exported
and the exit/hover/landing scenes inspected. The isolated QA server and
Simulator were shut down afterward. No physical-device or retail comparison,
rendered browser-peer test or external-server native join is established.


## Core101 — native existing-server adapters, acceptance in progress

Implemented separate legacy UDP and original-browser-world connections while
retaining strict independent-server inventory acknowledgements. The legacy path
uses the licensed Apache2 transport through an independent bounded C ABI; it
performs real challenge/join/class/spawn transactions. Semantic native controls,
player/vehicle streams, mapped original skin IDs, interiors, weapons, health,
chat, dialogs and basic TextDraws are connected to the actual native game.

Owned official open.mp tests establish0.3.7 and DL-profile spawn, chat and mutual
movement. A pre-final UIKit scenario renders the assigned SWAT/interior/HUD,
walks5.67m and stops with zero observed drift across14 subsequent sync samples;
final frozen-build UI acceptance remains in progress. A real separate DL server
exercises CRC32 catalog/download/completion helpers with synthetic payloads;
custom downloaded geometry is not rendered yet.

Original-world work adds versioned snapshots/deltas, app-owned service login,
client-owned arsenal/FIFO commands, fractional health/armour/burn/gas behavior,
actual staff commands and delayed fatal-vehicle exit ownership. Regression work
also exposed and fixed dropped accepted last-round shots, compact versus retail
skin ID confusion, stale animation state on model-style changes, actor/chassis
quaternion conversion and altitude-only interior selection.

A fresh complete frozen regression suite and both optimized native SDK builds
are running. No Core101 acceptance/public release, authenticated original-site
join, separate legacy SA-MP server-binary acceptance, physical iPhone result or
retail1:1 claim is made by this in-progress entry. See
[server compatibility](SERVER_COMPATIBILITY.md) for the full remaining boundary.


##2026-11-16 — Core102 legacy gameplay and actual native assets

Core101 checkpoint passed123/123 frozen-source gates, both optimized SDK builds,
and actual UIKit stock037/DL join/spawn/walk/dialog tests. It was not published:
Core102 fixes the independently measured1m CPed-root/native-feet mismatch.
Official class root10.8203 corresponds to original collision9.8203125; the
native controller's separate0.02m contact margin is documented as a difference.

Core102 now integrates DL catalogs/downloads with actual bounded DFF/TXD decode,
static/skinned Metal upload, the existing CLP1 skeletal animation owner, custom
skin registration, object transforms, material colors/text and exact dictionaries.
Imported COL main faces/spheres/boxes are actual parented Rapier bodies; shadow
faces are excluded. The owner corpus admits212 collision models/5,632 physical
colliders while retaining2,666 main faces separately from81,404 shadow faces.
Failed/missing resources are explicit; no alternate stock model is substituted.

Server control/camera/spectator commands now reach the actual controller and
rendered camera, with generation ownership, finite look vectors and the same
eye used for212/streaming. Remote scripted views retain the local actor's physical
floor. Normal spectator views reuse native camera algorithms; side mode and
untimed smooth-look policy remain explicit unverified gaps.83 pure camera checks
and1,673 real Renderer boundary checks pass; integrated UIKit acceptance is running.

A distinct fractional legacy vitals owner preserves exact Float14/66 seeds,
keeps byte sync quantization separate, forwards actual environmental115 damage,
and reports first zero-health sync with cause53/54 once.7,714 actual official
owned037/DL checks pass, plus110 decoder/lifecycle and30,520 unchanged independent
health checks. Death/respawn testing found and fixed lost roster/vehicle caches:
only actual current streamed Client state is republished after a confirmed spawn.

Moving-object staging is now tied to each actual native60Hz tick, before existing
coupling/unattended forces. Non-consuming Store samples prevent a later display
pose from clamping earlier physical substeps.2,086 codec/scene/clock checks pass
across15..144Hz. The actual support callback test passed3,792 checks including
an authored object translate/yaw/remove/reuse scenario; final fixed-tick callback
regression is running. Physical/browser/retail behavior is not inferred from these
controlled fixtures.

All five native physics architectures were rebuilt with the additive parented
triangle bridge. Integrated Debug Simulatorv3 compiled with unchanged sources;
its exact executable/dylib/metallib manifest is retained locally. Actual custom
DL UIKit and witness tests are now running against the isolated7793 fixture.
Final full regression and optimized both-SDK acceptance are still pending.

Remaining interoperability includes incoming203/206 presentation and actual
combat damage/hitbox policies, passengers/drive-by, full RPC/pickup/checkpoint
coverage, raw stock/supplemental object assets, client extensions and proprietary
server-binary acceptance. Original browser guest requests login; the legitimate
app-owned authenticated live world still needs the user's sign-in. No retail,
physical-phone, universal-server or full1:1 claim is made.

##2026-11-16 — Core103 physical reference and regression checkpoint

Both optimized SDK builds pass. The frozen149-check regression run completed
with146 passes and unchanged captured sources. Two extracted exit carriers
omitted newer production dependencies, and the server-UI SDK check inherited
compiler caches from another candidate directory. The initial failures remain
preserved. The exact carrier repairs now pass502 bike-exit and309 exit-runtime
checks; the repaired server-UI host/iPhone/Simulator SDK check also passes.
The composite acceptance therefore covers149/149 cases with unchanged App,
transport and physics source. Only the three listed test-carrier files changed.
These results are not relabeled as a single all-pass original run.

Normal inputs and paired CoreDevice capture reached the owner's separately
installed DE menu, live gameplay and nearby BMX. Walk/release, turning, camera
orbit and bicycle entry/exit were captured. Jump was not established. No save
files, private game process state or original executable modifications were
used. See `CORE_RETAIL_REFERENCE.md` for edition and timing limitations.

The actual native iPhone joined the isolated LAN server, rendered the city/HUD,
walked and stopped. A separate browser showed the native peer; the phone showed
the browser peer and its removal after that browser closed. This establishes
reciprocal static presence/leave, not synchronized motion or combat acceptance.
Input-service and XCTest initialization failures remain in the local evidence.
The Simulator also displayed the original public world's roster and native
scene after its own legitimate guest flow; complete original-server gameplay
has not been verified.

##2026-11-16 — Core104 device lifecycle and skin identity

Direct phone capture identified the user's visible error as the missing
`LSSupportsGameMode` Metal warning. Core104 includes that plist key and an owned
foreground-gameplay idle policy after actual testing exposed unwanted display
sleep.886 helper checks and61 extracted lifecycle checks pass. The complete
iPhone Debug app compiles, signs, installs and opens its native main menu.
Physical in-game capture now verifies the missing-key warning is gone with the
Metal HUD still enabled and Game Mode On.389 camera access units show working
horizontal orbit, up/down pitch, release and independent actor facing. A later
530-frame trial captures jetpack rise/turn/descent/landing without reproducing
the instant reversal.318.782 seconds of command-free/assertion-free idle retains
the foreground game. Broader resume continuity, vehicles, precise retail timing
and performance remain open; see `CORE_NATIVE_DEVICE_104.md`.

The reciprocal browser/native test also exposed different characters for the
same wire skin ID. The exporter had enumerated an animation/style array rather
than the browser's explicit model-ID catalogue. Core104's converter now reads
the explicit catalogue. The265-model migration retains all model bytes and
keeps browser-wire IDs distinct from retail aliases. Maccer is separately decoded,
converted and validated on real Metal, producing266 available models. Namespace,
actual native WebSocket and1675 actual Renderer/animation/Rapier checks pass
against the adopted metadata. Fresh iPhone/browser scenes show the same wire7
male01 and wire2 Maccer, and overlapping recordings verify both directions of
short walking/release. Known texture resampling,45 missing canonical IDs and
unmeasured mechanics remain explicit in `CORE_SKIN_IDENTITY_104.md`.

The updated registry contains152 cases; a single full152-case run is not claimed.
Acceptance combines the preserved149-case baseline with repaired carriers,
unchanged core sources, focused Core104 lifecycle/model/network checks, actual
device observations and a successful optimized iPhone build.

##2026-11-17 — physical evidence qualification and vehicle findings

Concurrent human phone use was confirmed after the physical trial. Exclusive
scripted input was not established for the broader session. Retain the actual
warning removal, corrected rendered models and observable cross-client motion,
but do not claim isolated input latency, controlled idle-policy acceptance or
later vehicle gas/brake/exit correctness. The318.782-second interval was free of
harness commands, not proven free of human input. Stuck-input, broken-exit and
teleport suspicions from later state changes are withdrawn.

Two independent rendered vehicle defects remain: the same420.6.1.0. taxi is
grey natively and yellow/orange in the browser, and the browser displays its
parked and driven bodies simultaneously. The next candidate investigates the
generic paint/material and ownership-publication boundaries. Live phone control
has stopped; the current user's server and game remain unchanged.
