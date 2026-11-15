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
