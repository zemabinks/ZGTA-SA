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
| Original PC executable gameplay | Not executed or observed | No classic-retail runtime parity established |
| Supplied iOS Definitive Edition1.86 IPA | Menu resources inspected statically | Menu asset/layout evidence; an iPhoneOS binary cannot run in Simulator |
| User-installed DE1.86.44544238 on iPhone12Pro/iOS27.2 | Actual menu, opening CJ scene/HUD, joystick/release, orbit/pitch and bicycle entry captured through paired screen/HID services | A bounded edition-specific runtime baseline; no completed native side-by-side parity or engine-FPS measurement |

The supplied mobile package and current phone reference are Definitive Edition,
distinct from the original mobile renderer/gameplay revision. Phone inventory
and visible running gameplay establish the reported edition/version, not a
cryptographic guarantee of a pristine App Store binary. Controlled captures now
exist for a bounded set of ordinary inputs; matched native comparison and
classic-retail timing measurements remain open.

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
During that earlier static pass, no original app was installed, launched,
re-signed or decrypted. The later user-installed physical reference is recorded
separately below; the audit does not merge these evidence types.

The owner initially supplied only the IPA. Apple Simulator
requires a build for its platform; the supplied iPhoneOS binary is not such a
build. Re-signing or editing bundle metadata does not supply the missing
Simulator executable and dependencies. See Apple's
[device/Simulator binary guidance](https://developer.apple.com/documentation/technotes/tn3117-resolving-build-errors-for-apple-silicon).
A genuine running iPhone/iPad installation remains the practical mobile
reference. PlayCover is a separate Apple Silicon compatibility route, not a
Simulator build or an established compatible runtime for this package; its
[published requirements](https://docs.playcover.io/getting_started/download_playcover)
exclude Intel Macs. No PlayCover installation or original-game Simulator
execution was attempted. Our Simulator builds come from our independent source.

## Physical reference status, 2026-11-16

The initial inventory reported iOS14.5.1 with no usable developer support.
After the owner's update and installation, actual inventory reports a paired
iPhone12Pro on iOS27.2/build24B119, Developer Mode enabled, with the installed
DE reference reporting1.86.44544238. The audit did not perform the OS update or
install that game.

XCTest UI automation timed out before its test method. A separate paired
CoreDevice capture identified older mounted support17C529, which did not offer
the screenshot service. Compatible Apple-personalized developer support27B52
mounted successfully and enabled direct screenshots. Ordinary visible inputs
then reached the main menu, opening gameplay and nearby BMX. No game binary,
save-file extraction, cheat or private-process instrumentation was used.

The local reference captures retain input contact timestamps and screen RTP
access-unit timestamps. Review MP4s use nominal30fps playback solely for visual
inspection; this is not a measurement of the game's frame rate or of exact
input-to-photon latency. The same scene, controls, equipment and measured native
conditions still need a matched side-by-side replay. The current BMX first-use
steering prompt retained its default Slider choice.

Definitive Edition is useful for its own presentation and gameplay behavior;
edition-specific differences must not silently replace the classic San Andreas
target. The classic PC executable and classic mobile runtime remain unverified.
All footage, contact sheets, device identifiers and test logs stay local-only.
