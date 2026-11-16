# Core GTA San Andreas gameplay parity

Priority override, 2026-11-15: complete and validate the core game before
advanced roleplay, character creation, voice, ZPhone, gangs or territory work.
The roleplay foundation remains on its separate worktree. This checklist is a
verification ledger, not a claim that an independent engine is already 1:1.

## Evidence rules

1. Original GTA San Andreas is the gameplay target. A versioned, legitimate
   retail runtime recording/test is the strongest evidence of feel and timing.
2. Rockstar's published controls/update notes establish documented behavior;
   they do not establish every numerical physics or animation constant.
3. Public reverse engineering is supporting evidence and must be labeled as a
   community reconstruction. It is neither official Rockstar source nor a
   substitute for testing the original executable. No unlicensed implementation
   is imported from gta-reversed.
4. Archived browser JavaScript/WASM fixtures establish compatibility with that
   browser client only. Existing golden tests remain regressions, not proof of
   retail San Andreas accuracy.
5. Native unit tests, integrated simulator observations, physical device tests,
   and browser/native multiplayer tests are recorded separately. Passing one
   does not imply the others passed. No original retail runtime comparison or
   physical device/controller verification has been established in this audit.

Reference sources checked on 2026-11-15:

- [Rockstar mobile update notes](https://support.rockstargames.com/articles/KlYrReNNBKJIkCUhUb0bR/grand-theft-auto-san-andreas-mobile-title-update-notes-android-and-ios): documented ramp/high-speed and frame limiter fixes demonstrate why FPS and transition tests matter; no physics constants inferred.
- [Rockstar mobile control positioning](https://support.rockstargames.com/articles/7oydRj1ymx0wPSC4eGG8S7/how-to-reposition-on-screen-button-controls-for-gta-san-andreas-mobile): reference for customizable touch layout.
- [gta-reversed jetpack task](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Tasks/TaskTypes/TaskSimpleJetPack.cpp): community reconstruction, behavior investigation only; not copied.
- [Plugin-SDK](https://github.com/DK22Pac/plugin-sdk) and its [zlib license](https://github.com/DK22Pac/plugin-sdk/blob/master/LICENSE): public interface/coordinate research. No retail executable bundled.

## Mechanic checklist

Status: **audit** = implemented but original-game verification still required;
**gap** = known missing/approximate behavior; **fixing** = a reproduced defect is
being corrected. A row is only **verified** for a specifically named test and
platform, never for the entire original mechanic by inference.

| Area | Required cases and transitions | Current evidence / remaining work | Status |
| --- | --- | --- | --- |
| Coordinates | GTA Z-up ↔ physics Y-up; handedness; heading sign; model root versus actor heading; wrapped angles | Heading ownership and wrapped-angle gates pass; full original coordinate/movement comparison remains open | audit |
| Walk/run | Analog magnitude, walk/run thresholds, acceleration/deceleration, start/stop, side/back direction, root distance against actual collision travel | Actual walk-modifier, acceleration/turning/strafe replay passes5,600 frames; retail timing and blocked-foot sliding need comparison | audit |
| Sprint | Held/tapped sprint, stamina, heavy weapons, crouch/aim restrictions, fatigue recovery | Core88 corrects underwater preparation, airborne/parachute recovery, dead-task guards and swimming control ordering against actual archived expressions; original stat curves and physical touch/controller timings remain unverified | audit |
| Crouch | Stand/crouch transitions, strafe, roll, restricted clearance, aim/fire | Archived motor/native movement use fixed walker/probe shapes. Retail stance clearance and transition feel remain unmeasured; no shorter capsule is assumed | audit |
| Turning | Idle turn, moving turn, shortest arc across ±π, camera-independent facing, idle after special modes | Final flight/swim facing is handed to foot once; rotated landing wire trace has0° heading jump; retail turning feel unverified | audit |
| Jump | Launch animation marker, speed carry, short/long jump, ceiling hit, air control, double-request prevention | Browser/motor fixtures; original-game jump height/timing not measured | audit |
| Fall/land | Ledge fall, hard/soft landing, slope contact, repeated tiny ground contacts, damage, death | Held-root release resets obsolete fall/contact history; native frame schedules15–144Hz agree. Regular native landing now applies the checked browser damage/death policy once; original hard/soft landing thresholds and damage remain unmeasured | audit |
| Climb/vault | Height bands, clearance, hanging, pull-up, cancel/drop, obstacle traversal | Core91 admits eligible slow vehicle ledges through the real animation/motor path;21,269 checks cover entry and complete low/high tasks. [Evidence/limits](CORE_CLIMB_ADMISSION_91.md). Entity-relative moving handholds, retail hand alignment and original timing remain unverified | audit |
| Swimming | Entry from walking/falling/flight, breast/crawl/dive, underwater pitch/turn, breath/drown, shore/ledge exit | Swim steering/heading handoff, water-exit animation ownership and Core88 effort ordering are corrected; recovering breath remains visible after surfacing/shore exit. Original shore, lung-capacity curves and underwater feel remain unverified | audit |
| Animation | Correct IFP clips, root motion, timing, blending, reverse/strafe, arm/spine aim, hit/death, motion-mode priority | Real assets and browser fixtures; full retail blend/edge coverage outstanding | audit |
| Camera foot | Follow distance, orbit sensitivity, pitch limits, collision, recenter, scoped aiming | Fixed-step motion now owns crouch-camera stance across15–144Hz; normal camera golden remains unchanged; temporary reverse view preserves follow/aim history across2,016 reference frames. Close-camera/unknown-geometry policies are explicit; original feel unverified | audit |
| Camera vehicle | Enter/exit, reverse/look-back, roof/wall collision, bike/boat/aircraft, first-person | Browser camera fixtures pass; vehicle/foot/teleport histories reset together; original and physical-controller validation outstanding | audit |
| Collision | Terrain, walls/corners, slopes, stairs, floor seams, dynamic bodies, ceilings, unloaded cells | Core90 corrects terrain/fork/trailer-support friction combination and five trailer supports. Held feet/capsule, sphere queries and whole-world camera/weapon rays retain existing coverage; original contact comparison remains outstanding | audit |
| Gravity/momentum | Original unit scaling, fixed-step integration, damping, jump/flight/swim handoffs | Avoid replacing original per-tick units with unrelated SI defaults; test accumulated time | audit |
| Reposition/reset | Teleport, respawn, interior transfer, vehicle reset, death/revival | Hard reset clears transient tasks, collision/solver and camera history; state transition regressions pass, full original edge coverage remains | audit |
| Jetpack takeoff | Ground request, equipped state, thrust, initial facing, collision | Test same heading and rotated takeoff at multiple rates | audit |
| Jetpack flight | Hover, lateral thrust, speed damping, pitch/bank, thrust up/down, stop, death/water | Browser dynamics fixtures; stale landed-canopy phase is cleared on jetpack takeover; retail force/feel still unmeasured | audit |
| Jetpack landing | Ground detection, preserve final heading, one landing event, foot animation continuity | Stale-cache overwrite and touchdown early return fixed. Simulator wire trace:195.569° flight turn followed by0° touchdown heading jump. Grounded removal is server-validated | audit |
| Parachute | Freefall, deploy, glide, turn, landing, collapse/death, water, consume once | Browser flight fixture; original timing/attachment coverage incomplete | audit |
| Car dynamics | Engine gears, torque, braking/reverse, steering, grip/slip, suspension, drag, collision impulse |212 model configs and browser fixtures; full original handling validation outstanding | audit |
| Car reset | Relocation/lift, wheel contact history, damage retention, drivetrain reset policy | Vehicle relocation rebuilds obsolete solver history while retaining damage; original drivetrain reset policy still unverified | audit |
| Vehicle boarding | Door/seat selection, moving targets, timed entry/exit, blocked door, cancel, death | Boarding cancellation releases door holds; promoted parked bodies are removed on ownership transfer. Invalid entry preserves the current chassis; jacking and rollover crawl remain incomplete | gap |
| Bikes/bicycles | Lean, steering, wheel contacts, pedaling, reverse limits, fall-off, rider root synchronization | Brake/hop ownership, charged cancellation and shared stamina pass335 native checks; full fall-off and physical controller tests remain missing | audit |
| Boats | Water plane, buoyancy, wave pitch/roll, thrust/drag, shore collision, exit to swim | 17,339 water-surface reference queries match exactly; buoyancy/boat browser fixtures exist. Original runtime comparison remains outstanding | audit |
| Aircraft | Fixed-wing and helicopter lift/drag, surfaces/rotors, landing gear, ground contacts, stall, cameras | Native specialized solvers exist; fallback assists are approximations, not original parity | gap |
| Trains | Track constraints, forward/reverse, braking, locomotives and carriage transforms | Native rail solver and train consists support owned, remote and parked locomotives; original runtime derailment, switching and train behavior still need comparison | audit |
| Trailers/towing | Compatible anchors, acquisition, two links, tow hook, release/break, ownership, contact suppression, momentum | Core88 adds confirmed two-link/truck towing, moving native joint anchors, source release conditions, hauled force selection and contextual controls. Native/server/legacy wire tests pass within their documented synthetic geometry boundary; original handling and live scene acceptance remain open | audit |
| Working vehicles | Hydraulics, forklift plates, dumper/dozer parts, tow hook, collision/query geometry and tool-state persistence | Core90 adds201 separate support meshes, source Float32 working poses and pedestrian carry queries to the existing six configured rigs/plates/spheres. Controlled golden, native physical and protocol tests are separate; live load carrying and retail behavior remain unverified | audit |
| Moving vehicle support | Body-local feet, platform yaw, slip, jump, momentum, boat decks, body replacement, remote attachment | Core90 implements separate support/carry ownership and integrates actual native queries, post-step presentation and browser-shaped attachment/detach. See [bounded evidence and limitations](CORE_MOVING_SUPPORT_90.md); rendered/device/retail acceptance remains open | audit |
| Combat aim | Hip/arm/whole-body aim, camera-relative yaw/pitch, moving aim, crouch, target line/occlusion | Shortest-arc gun yaw fixed; coherent event-time muzzle/target/LOS repair passes245 checks; actual per-hand muzzle replay adds600 frames/5,415 checks. Original aim feel and skeletal victim hitboxes remain unverified | audit |
| Combat fire/reload | Weapon cadence, reload cancel, empty clip, held trigger, weapon switch, recoil, projectile and hit events | Animation-owned emission and atomic ACK prediction integrated;3200 delayed frames and actual Swift HTTP/WS tests pass. Reload ACK duplicates no longer restart the same countdown; released pre-muzzle input is cancelled at native reload boundaries. Bounded receive-time credit now accepts 69,060 actual native animation events under the stated 15–144 Hz/20 ms jitter envelope; server reload/damage policies and precise recoil still differ/unverified | audit |
| Melee/damage | Combo timing, hit range/line, block, knockdown, hit reaction, death/revive | Core92 connects accepted local hits to real directional flinch/stun/death responses and publishes knock/get-up tags. [Evidence/limits](CORE_LOCAL_HIT_92.md). Animation-marker melee, guard/block and source-based reach are integrated. Special moves, fighting-style acquisition, weapons1–15 acquisition, damage policy for10–15 and full original victim/AI behavior remain gaps | gap |
| Weapon attachment | Hands/spine, dual wield, parachute/jetpack, vehicle drive-by | Event-time hand24/34 muzzle transforms match600 archived rig frames;53 original weapon/skill offset rows match; weapon46 spine placement and consistent carried/wire selection are covered by real-rig tests. Core88 removes fake utility-slot attacks and retains actual detonator/deploy actions. Camera/binocular functionality and drive-by remain incomplete | gap |
| Touch | Safe-area geometry, multitouch, release/cancel, context buttons, overlays, keyboard | Central cancellation clears held gameplay controls across overlays/lifecycle; actual multitouch/device acceptance remains outstanding | audit |
| Controller | Dead zones, press edges, disconnect, release-to-rearm, camera sensitivity | Core88 context bindings/dispatch pass3,833 checks, preserving work tools, towing release, radio, nozzle and normal controls. Disconnect/menu gates require neutral before rearming. Modern triggers and some contextual actions are explicit adaptations; physical controller tests remain required | audit |
| Keyboard/mouse | Held-key focus loss, mouse look, bindings, modifier and device-switch edges | Original PC defaults and context dispatch are audited; slot-ordered cycling and Alt walk are covered. Original-PC bicycle hop and pause key handoff are covered. Full original targeting and hardware acceptance remain gaps | audit |
| Timing |15/30/60/120Hz plus jitter, slow frame, foreground resume, fixed-step catchup | Slow frames retain elapsed time with bounded updates; suspension uses a separate policy; frame-schedule regressions pass, device performance unmeasured | audit |
| Multiplayer | Local input immediate, remote angle shortest arc, foot/flight/vehicle packet state, enter/exit authority | Wire/independent-server tests cover despawn, fresh-world cleanup and acknowledged environmental damage/respawn. Core88 real native HTTP/WS→real backend plus legacy-protocol observer passes160 attachment checks, including lost ACK/reconnect. Rendered browser/native scene transition replay, physical inputs and original-game parity remain separate requirements | audit |
| Player attributes and damage | Stamina, breath, health/armour, fall/fire/drown response, weapon skill, body/stat modifiers | Several controllers exist; complete original stat effects, body-part damage and original damage policies are not established | gap |
| World context | Ground materials, streaming seams, interiors, doors, pickups, NPC/traffic interactions and activity interruption | Audit each interaction against the original; missing geometry must not be treated as a clear shot | audit |
| Other fundamentals | HUD/radar/map, interactions/interiors, collision materials, radio and effects, objects/NPCs/mission context | Existing modules remain partial. Owner-imported original radio recordings now work locally; full original mission/NPC systems remain absent | gap |

## Regression acceptance scenarios

- Flight: face A, take off, rotate close to180°, hover, descend to ground,
  release all input, then walk. Repeat at cardinal headings and across ±π;
  repeat at15/30/60/120Hz and jitter. Compare last flying heading, touchdown
  heading, first idle/foot heading, camera and transmitted actor heading.
- Handoffs: foot ↔ swim, fall → parachute → foot, flight → water, vehicle ↔
  foot, teleport while jumping/swimming/flying/driving, death/revival in each
  mode. No stale velocity, root offset, collider, held action or heading.
- Aim: cross ±π with stationary and moving aim, crouched and standing;
  switching weapons/reloading cannot generate extra shot or reversed arm aim.
- Input: open/close map, pause, text entry; background/foreground; controller
  disconnect/reconnect while holding each control. No stuck movement, unwanted
  jump/shot, or siren toggle from synthesized release.
- Physics: same total elapsed time under fixed and jittered frame schedules;
  collision contacts, teleport and landing events remain bounded and singular.
- Multiplayer follows local correctness: two independent clients observe the
  same mode/facing/weapon/vehicle transition without delaying local control.
- Attachment confirmation: move a trailer/tow pair beyond the existing break
  distance while its acknowledgement is delayed. Loaded incompatible geometry
  must release the authoritative link without creating a joint. Missing
  streamed entities, bodies, definitions or anchors must wait until evidence
  arrives; a bad second link must preserve a valid first link. Declined cleanup
  retries, while accepted pending cleanup remains deduplicated.

## Results and limitations

Audit in progress. Per-change test results and simulator observations are
recorded in `CORE_GAMEPLAY_JOURNAL.md`. Do not mark this checklist complete or
describe the port as1:1 until original runtime evidence covers each mechanic.

The owner supplied a local PC disc image described as1.0US. Its installer
readme saysV1.00. The included modified executable is kept distinct from the
original SecuROM-wrapped installer executable; neither was run. The original
installer's pedestrian animation archive is byte-identical to the browser's.
All550 checked fields across30 selected weapon profiles match the installer
data. Of5,724 checked handling fields across212 mapped models, one boat's
turn-mass value differs only in decimal rounding. These are data comparisons,
not evidence that the independent simulation reproduces the original engine.
All reference images, binaries, extracted data and disassembly stay local.
The supplied iOS Definitive Edition package establishes static menu resources,
not a running original gameplay reference. Original runtime behavior remains open.

Core84 adds fixed-step-owned foot velocity and explicit queued-intent cancellation
(see CORE_FIXED_STEP_VELOCITY_AUDIT.md), plus fresh-baseline connection recovery
(see CORE_CONNECTION_RECOVERY.md). These fix specific demonstrated transition
failures. Passing regression counts do not upgrade the remaining retail-runtime
rows to verified1:1 parity.

Core86 adds water/flight/fall task corrections, stable camera stance over fixed
poses, versioned environmental-health synchronization, reload ownership fixes,
explicit vehicle despawn/session cleanup, parked aircraft equipment retention
and remote/parked train consists. See CORE_TASK_HANDOFF_AUDIT.md,
CORE_FALL_DAMAGE.md, CORE_CAMERA_MOTION_AUDIT.md,
CORE_HEALTH_SYNCHRONIZATION.md, CORE_COMBAT_TRANSITIONS_86.md,
CORE_VEHICLE_DEPARTURE.md and CORE_TRAIN_LAYOUT.md. These are bounded native
correctness/browser-compatibility results; unmeasured retail rows stay open.

Core88 broadens the audit to shared movement effort, combat task ownership,
weapon utility roles, confirmed trailer/tow constraints and working-vehicle
meshes, colliders and controls. See CORE_EFFORT_RECOVERY_88.md,
CORE_COMBAT_TASK_OWNERSHIP_88.md, CORE_VEHICLE_COUPLING.md,
CORE_VEHICLE_CONTROLS_88.md, CORE_COUPLING_TRANSPORT_88.md and
CORE_COUPLING_SERVER_REVIEW_88.md. Browser reference goldens and CPU/transport
tests remain distinct from original-game, GPU, physical input and live
multiplayer acceptance. The supplied iPhone's proposed update and DE install
are not recorded as completed runtime verification.
