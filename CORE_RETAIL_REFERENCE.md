# Original-game reference and acceptance

Original GTA San Andreas remains the target. Archived browser regression,
matching game data and an original-game playtest answer different questions.
They must not be combined into an unsupported1:1 claim.

## Available evidence

The owner supplied a PC disc image described as1.0US. The installer readme
identifiesV1.00. Inspection extracted26 selected reference files without running
the installer or executable. The disc's loose modified executable was recorded
separately from its original SecuROM-wrapped installer executable. That disc
provenance does not independently establish a pristine US executable identity.

| Comparison | Observed result | What it establishes |
| --- | --- | --- |
| Pedestrian animation archive | Exact byte identity with browser archive | Same source animation tracks |
| Selected ranged/projectile/area weapon profiles |30 profiles,550 fields match their selected skill levels | Same checked static weapon inputs |
| Vehicle handling catalog |212 model mappings,5,723/5,724 fields match; one decimal rounding difference | Same checked raw handling inputs |
| Pedestrian heading/style/type |276 rows,828 fields match | Same checked pedestrian style inputs |
| Tyre adhesion | Rubber-versus-ground values match | Same checked tyre surface inputs |
| Original executable gameplay | Not executed or observed | No original runtime parity established |
| Supplied iOS Definitive Edition1.86 IPA | Menu resources inspected statically; no original app execution | Menu asset/layout evidence only, no original gameplay-runtime acceptance |

The supplied mobile package is the Definitive Edition, distinct from the original
mobile renderer/gameplay revision. No running unmodified retail installation or
controlled retail gameplay recording has yet been established for side-by-side
mechanics measurements. A request for a runnable reference remains open.

Original binaries, images, extracted files, derived catalogs, disassembly and
private recorded fixtures remain local. The source release includes our own
code, tests and audit conclusions.

## Known engine differences beyond data identity

- Native/browser drivetrain loading applies an additional acceleration factor
  relative to a community reconstruction and the supplied modified executable.
  The wrapped original function bodies do not directly corroborate it. Keep it
  a candidate until a trustworthy original conversion or runtime test resolves
  the difference; do not silently change the fleet from a guessed road speed.
- High-speed suspension compression input is absent for affected models. Its
  extra contact/depth response needs original comparison; ordinary spring
  damping is a separate input and must not be substituted for it.
- Muzzle and torso targeting offsets remain approximations. Full per-hand
  bones, skill/spread, shotgun pellets, body parts and original damage response
  are not established by the coherent-ray repair.
- Static ledge climbing does not yet support moving entity-relative handholds.
  Correct animation tracks do not establish correct hand placement or original
  phase timing under every collision.
- Close-camera body visibility is a native correction. Its clearance
  envelope is not a measured original-game camera constant. An attempted
  translucent-body effect was rejected after live skeletal rendering artifacts.
- Complete original NPC decisions, melee, special vehicles and mission systems
  remain gaps in the broader checklist. Multiplayer policies are independent
  server behavior, not original single-player engine verification.

## Runtime comparison procedure

Record edition/executable identity, platform, active controller scheme, camera
view, frame limiter, measured frame rate, relevant player/weapon skill and
test location before recording. Use the same initial facing, movement mode,
equipment, input duration and environment for original and native samples.

1. Record idle → walk → run → sprint → stop and turn, including analog partial
   input, reversal and collision-blocked travel. Measure travel, facing, clip
   phase and stopping time separately.
2. Record jump/fall/land, low wall, high hang/pull/drop and vault. Compare feet,
   hands, capsule placement and root motion at phase boundaries.
3. Record jetpack takeoff/hover/turn/descent/grounded removal and transitions
   to water, parachute and death. Compare last flight and first foot heading.
4. Record camera pitch/orbit/obstruction at walls, ceilings, corners and slopes,
   then vehicle entry/exit. Compare target, eye path and visibility changes.
5. Record straight acceleration/coast/brake/reverse, turning and curb impacts
   for cars and bikes, then each boat/aircraft/special vehicle class. Keep
   handling data, damage, weather, tyres and player skill controlled.
6. Record aimed/hip shots, movement, reload cancellation, empty/held fire,
   dual-hand events, pellets and melee. Compare both visible muzzle and actual
   impact, then armour/body-part damage independently.
7. Repeat the relevant cases at measured supported frame rates and with input
   interruptions. Verify native/browser multiplayer only after local mechanics
   pass; network agreement alone does not prove original accuracy.

For each discrepancy, save the reproduction, reference observation, root cause,
changed code, regression and remaining limits in the gameplay journal. A result
is accepted only for the tested mechanic, scenario and platform.

The supplied DE executable was additionally inspected without execution: its
only architecture isARM64, its build platform is iPhoneOS (minimumiOS16/A12),
and it contains no Simulator slice. Binary signing metadata alone does not
establish a trusted App Store installation or a pristine gameplay build.
Selected metadata/binary extraction and full retained evidence remain local.
A compatible running device reference is still needed for gameplay recordings;
no original app was installed, launched, re-signed or decrypted in this audit.

The owner initially supplied only the IPA. Apple Simulator
requires a build for its platform; the supplied iPhoneOS binary is not such a
build. Re-signing or editing bundle metadata does not supply the missing
Simulator executable and dependencies. See Apple's
[device/Simulator binary guidance](https://developer.apple.com/documentation/technotes/tn3117-resolving-build-errors-for-apple-silicon).
A genuine running iPhone/iPad installation remains the practical mobile
reference. PlayCover is a separate Apple Silicon compatibility route, not a
Simulator build or an established compatible runtime for this package; its
[published requirements](https://docs.playcover.io/getting_started/download_playcover)
exclude Intel Macs. No PlayCover installation or original-game execution was
attempted. Our Simulator builds come from our independent app source.

## Physical reference status, 2026-11-16

The connected iPhone 12 Pro was reported by device inventory as iOS 14.5.1;
the development tools reported a missing compatible Developer Disk Image.
The owner owns the classic mobile app but has not installed it. The owner
plans to update the phone and install Definitive Edition. No OS update,
original-app installation or original gameplay launch was performed or
verified during this pass. Re-check actual device/version availability before
recording any reference observations; a proposed OS version is not a detected
or validated version.

When the original runs, record its edition/build, selected graphics/control
mode, measured frame rate and test conditions alongside each comparison.
Definitive Edition is useful for its own presentation and gameplay behavior;
edition-specific differences must not silently replace the classic San
Andreas target. Static IPA resources and archived browser outputs remain the
available references until that runtime comparison is established.
