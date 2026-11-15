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
| Coordinates | GTA Z-up ↔ physics Y-up; handedness; heading sign; model root versus actor heading; wrapped angles | Trace all mode handoffs and wire heading; prevent visual offsets leaking into gameplay | fixing |
| Walk/run | Analog magnitude, walk/run thresholds, acceleration/deceleration, start/stop, side/back direction, root distance against actual collision travel | Browser fixtures exist; retail timing and blocked-foot sliding need comparison | audit |
| Sprint | Held/tapped sprint, stamina, heavy weapons, crouch/aim restrictions, fatigue recovery | Browser stamina/sprint fixtures; physical touch/controller timings unverified | audit |
| Crouch | Stand/crouch transitions, strafe, roll, restricted clearance, aim/fire | Full low-ceiling capsule and original transition feel not verified | audit |
| Turning | Idle turn, moving turn, shortest arc across ±π, camera-independent facing, idle after special modes | Flight and swim can return to stale foot heading | fixing |
| Jump | Launch animation marker, speed carry, short/long jump, ceiling hit, air control, double-request prevention | Browser/motor fixtures; original-game jump height/timing not measured | audit |
| Fall/land | Ledge fall, hard/soft landing, slope contact, repeated tiny ground contacts, damage, death | Review velocity/grounded history and clip transitions at15/30/60/120FPS | audit |
| Climb/vault | Height bands, clearance, hanging, pull-up, cancel/drop, obstacle traversal | Six static-ledge phases implemented; real Renderer/animation/native-world integration gate passes8,365 checks. Moving carriers, retail hand alignment and original phase timing remain unverified | audit |
| Swimming | Entry from walking/falling/flight, breast/crawl/dive, underwater pitch/turn, breath/drown, shore/ledge exit | Browser swim fixtures; heading ownership on shore exit needs handoff | fixing |
| Animation | Correct IFP clips, root motion, timing, blending, reverse/strafe, arm/spine aim, hit/death, motion-mode priority | Real assets and browser fixtures; full retail blend/edge coverage outstanding | audit |
| Camera foot | Follow distance, orbit sensitivity, pitch limits, collision, recenter, scoped aiming | Mode history, look wrap and timestep audit in progress | fixing |
| Camera vehicle | Enter/exit, reverse/look-back, roof/wall collision, bike/boat/aircraft, first-person | Browser camera fixtures; reset histories at vehicle/teleport boundaries | fixing |
| Collision | Terrain, walls/corners, slopes, stairs, floor seams, dynamic bodies, ceilings, unloaded cells | Native KCC/Rapier regressions; held-position path leaves collider behind | fixing |
| Gravity/momentum | Original unit scaling, fixed-step integration, damping, jump/flight/swim handoffs | Avoid replacing original per-tick units with unrelated SI defaults; test accumulated time | audit |
| Reposition/reset | Teleport, respawn, interior transfer, vehicle reset, death/revival | Reset body, solver/contact, animation and camera histories together | fixing |
| Jetpack takeoff | Ground request, equipped state, thrust, initial facing, collision | Test same heading and rotated takeoff at multiple rates | audit |
| Jetpack flight | Hover, lateral thrust, speed damping, pitch/bank, thrust up/down, stop, death/water | Browser dynamics fixtures; retail force/feel still unmeasured | audit |
| Jetpack landing | Ground detection, preserve final heading, one landing event, foot animation continuity | Stale-cache overwrite and touchdown early return fixed. Simulator wire trace:195.569° flight turn followed by0° touchdown heading jump. Grounded removal is server-validated | audit |
| Parachute | Freefall, deploy, glide, turn, landing, collapse/death, water, consume once | Browser flight fixture; original timing/attachment coverage incomplete | audit |
| Car dynamics | Engine gears, torque, braking/reverse, steering, grip/slip, suspension, drag, collision impulse |212 model configs and browser fixtures; full original handling validation outstanding | audit |
| Car reset | Relocation/lift, wheel contact history, damage retention, drivetrain reset policy | Native teleport retains obsolete solver history unlike public reset | fixing |
| Vehicle boarding | Door/seat selection, moving targets, timed entry/exit, blocked door, cancel, death | Boarding queues exist; jacking, rollover crawl and interruption coverage incomplete | gap |
| Bikes/bicycles | Lean, steering, wheel contacts, pedaling, reverse limits, fall-off, rider root synchronization | Browser rigs/dynamics fixtures; full fall-off behavior and physical controller tests missing | audit |
| Boats | Water plane, buoyancy, wave pitch/roll, thrust/drag, shore collision, exit to swim | Browser fixtures; legitimate original runtime comparison outstanding | audit |
| Aircraft | Fixed-wing and helicopter lift/drag, surfaces/rotors, landing gear, ground contacts, stall, cameras | Native specialized solvers exist; fallback assists are approximations, not original parity | gap |
| Trains/trailers/tools | Track constraints, coupling, towing, hydraulics, vehicle-specific controls | Full original special vehicle and tool behaviors incomplete | gap |
| Combat aim | Hip/arm/whole-body aim, camera-relative yaw/pitch, moving aim, crouch, target line/occlusion | Raw heading subtraction can clamp aim to wrong side across angle wrap | fixing |
| Combat fire/reload | Weapon cadence, reload cancel, empty clip, held trigger, weapon switch, recoil, projectile and hit events | Animation-owned emission and atomic ACK prediction integrated;3200 delayed frames and actual Swift HTTP/WS tests pass. Held-fire automatic reload verified in diagnostic Simulator; server reload/damage policies and precise recoil still differ/unverified | audit |
| Melee/damage | Combo timing, hit range/line, block, knockdown, hit reaction, death/revive | Full original melee/target AI not established | gap |
| Weapon attachment | Hands/spine, dual wield, parachute/jetpack, vehicle drive-by | Full dual wield/drive-by/weapon46 attachment incomplete | gap |
| Touch | Safe-area geometry, multitouch, release/cancel, context buttons, overlays, keyboard | Held sticks/gas/brake/horn survive some overlays; central cancellation needed | fixing |
| Controller | Dead zones, press edges, disconnect, release-to-rearm, camera sensitivity | Disconnect can retain held state; physical hardware test still required | fixing |
| Keyboard/mouse | Held-key focus loss, mouse look, bindings, modifier and device-switch edges | Review shared cancellation and pointer-vs-analog delta semantics | audit |
| Timing |15/30/60/120Hz plus jitter, slow frame, foreground resume, fixed-step catchup | VC discards time over50ms; long suspended gaps need a distinct policy | fixing |
| Multiplayer | Local input immediate, remote angle shortest arc, foot/flight/vehicle packet state, enter/exit authority | Wire and independent server tests exist; cross-client transition replay still required | audit |
| Other fundamentals | HUD/radar/map, interactions/interiors, collision materials, radio and effects, objects/NPCs/mission context | Existing modules are partial; licensed radio recordings and all original mission/NPC systems absent | gap |

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
Original runtime behavior and the forthcoming iOS reference remain open gates.
