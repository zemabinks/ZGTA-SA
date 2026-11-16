# Core gameplay audit journal

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
