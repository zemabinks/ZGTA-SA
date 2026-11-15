# Native climbing evidence

The native helper implements static-ledge approach, hanging, pull-up,
standing, vaulting and dropping. Its secondary reference is the archived
browser controller. Original GTA SA retail accuracy has not been verified.
Renderer/core integration is CPU-tested below; visual acceptance is separate.

Run the reproducible CPU/controller/native geometry gate:

```sh
python3 smoke_native_climb.py
python3 smoke_native_climb_runtime.py
```

The reference uses actual local animation durations and executes two bounded
archived functions offline with the shipped Rapier/Three runtime. Native
checks use the existing host Rapier library. No Simulator, network access or
game-asset writes are involved. Generated source extracts, fixtures and proof
reports stay in ignored `local-only/research/climbing/`.

| Gate | Coverage | Result |
| --- | --- | --- |
| State, clock, heading and physical anchors | 2,475 frames at 30/60/120 Hz; hang, direct pull, delayed pull, stand, vault, drop, timeout | Maximum error 6.94e-18 |
| Probe construction and ordering | 456 archived-engine ray/sphere queries | 16,337 combined checks pass |
| Native query geometry | Same controlled scenes using real native engine queries | Maximum numeric error 5.96e-8 |
| Body classification | Fixed/no-parent, fixed-parent, dynamic, kinematic, speed threshold, unknown-parent, removed body | Explicit type registry; unknown parents fail closed |
| PED and blocked surface handling | PED material 62 alone/in front of a wall; materials 17/18; fast body in front of wall | Filtering and rejection match bounded source |
| Current Renderer/core integration | Actual extracted Renderer methods; 1,504 display frames, 1,308 native fixed ticks, 1,871 local clips | 8,365 checks pass |

The integration gate executes the current `beginClimb`, `climbingMotion`,
`footMotion`, input-cancel and let-go methods through the actual
CharacterController/shared native world. It checks constructor/completion held
ticks, contact-capsule placement before the world advances, paused EDGE pose,
uninterrupted clip clocks, rooted phase/exit clips, first resumed foot heading,
gravity after drop, death, input neutralization, airborne grab cadence/stretch
threshold and deliberate rejection of unsupported vehicle carriers. It loads
the real animation library once, as production does. Metadata loading, UIKit
events, camera framing and Metal hand/foot placement are outside this gate.

`SwiftRapierWorld.bodyKind(id)` records a type only after successful creation
and removes it only after successful removal. A kinematic parent remains a
vehicle; `ColliderInfo.dynamic == false` is not used as a static detector.
Unknown parent bodies cannot become handholds and block clearance. The query
adapter explicitly excludes the walker/probe and filters PED before selecting
the closest ray hit. The selected body's speed check then happens after that
selection, preserving occlusion by a fast vehicle.

Climb phases use the real `ped/climb_*` ANP3 tracks. Physical foot anchors and
rooted animation movement are separate; adding animated root travel into
physical held feet would count the translation twice. Heading remains with
the climb task until foot locomotion adopts its final facing.

Moving carrier support is deliberately unavailable: no world-space handhold
is frozen onto a moving boat, train or vehicle. Native zero-height capsule
overlaps matched original Ball decisions in these controlled scenes;
arbitrary mesh grazing, moving-carrier handholds, retail camera/hand placement
and a retail executable replay remain unverified.

The archived chunk SHA256 is
`5a8a7fa71560badc0d9353e88deaa164323544d47a5d4c20e6a92d04c1c78c36`.
Controller offsets are 1716131–1717082 and probe offsets 1873824–1875876,
expressed as UTF-16 half-open ranges in chunk 9737. That is a chunk name;
the implementation belongs to the main 19737 bundle factory.

REA bounded static Evidence:
`ev_06a884101e37a62466a0ca86307009ac414cf9b5bb19ff46f36e25c73c47af5b`.
Only 3,062 bytes from the two extracted functions were analyzed. Static
relationships are partial and do not establish runtime behavior; the replay
gates supply the controlled execution evidence.

The community [GTA reconstruction](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Tasks/TaskTypes/TaskSimpleClimb.cpp)
was consulted only as a behavioral comparison. No implementation was copied;
its license provenance remains unresolved. It describes entity-relative
handholds and animation-driven phase/position changes that differ from the
browser's fixed handholds, timers and ray/sphere probes. A passing browser
fixture therefore does not establish a 1:1 retail port.

## Actual city geometry acceptance fixtures

A local scout loaded the real c59/c60 region and neighboring SCL2 cells through
`NativeGroundVehicle.installCell`, with the real material classes. These are
reproducible starting **feet** positions in GTA coordinates; all use initial
native heading 0 radians (browser hello heading 0), facing toward increasing
GTA Y. Each point passed the native motor body-fit test, 1.5m of clear approach
space and an actual KCC approach query with zero movement error.

| Case | Feet X, Y, Z | Detected handhold Z | Native result |
| --- | --- | --- | --- |
| Low stand | 1548, -1680, 12.5800166321 | 13.9456416321 | high=false, vault=false |
| High hang/pull | 1550, -1680, 12.5757794571 | 15.0914044571 | high=true, vault=false |
| Vault | 1594, -1774, 12.5408139420 | 14.9251889420 | high=false, vault=true |

The vault task aligns the character to the actual wall normal at approximately
0.2609105 native radians after acquisition. The tested initial approach heading
remains 0. These positions are query acceptance fixtures; a live visual/UI
playtest is separate and must not be inferred from a successful query.

The original 40m search was a legitimate negative result. Its 1m grid covered
5,025 points: 319 had steep ground, 463 failed the deliberately restricted
8–17m ground-height range, 221 failed body fit, and 4,022 passed both ground and
fit. Of 32,176 tested headings, 31,452 had no nearby wall in the scout's cheap
prefilter. The remaining 724 full probes rejected 474 for upper clearance,
196 for no usable edge and 54 for body clearance. None yielded a handhold.

Expanding to a 120m radius on a 2m grid produced 3,084 full probes: 1,924 failed
upper clearance, 1,034 had no edge, 63 failed body clearance and one failed the
facing-normal test. The 62 accepted static handholds became 42 after the
combined walk-space/KCC approach test. The 20 approach rejections were not
separately classified by walk-space continuity, body fit and KCC movement.
The scout uses a forward-ray prefilter and a restricted ground-height range;
these are bounded searches, not an exhaustive inventory of climbable objects.

## Proven sphere-query boundary gap in build 77

Actual archived `39943.addCell` grouping and the browser ledge finder were
replayed against the same 12 real collision cells as native. QA aliases kept
all cells resident; this tests collider/query behavior, not streaming policy.
Both produced 147 colliders. Across 21 full probe cases, both accepted the
same 20 handholds and agreed on high/vault state. All 438 ray distances were
identical; maximum normal error was 1.09e-19 and maximum handhold/direction
error was 1.12e-16.

**The strict sphere-overlap gate fails.** The 190 ordinary clearance queries
agreed, but five of 21 deliberately tangent/near-tangent sphere samples were
reported blocked by the native zero-height Capsule and clear by the original
Ball. All use radius 0.3m; the mismatches below list GTA query centres:

| Case | X, Y, Z | Constructed tangent offset |
| --- | --- | --- |
| Stand | 1548, -1679.440725, 13.6456416321 | -0.0001m |
| Stand | 1548, -1679.440625, 13.6456416321 | 0m |
| High | 1550, -1679.440725, 14.7914044571 | -0.0001m |
| High | 1550, -1679.440625, 14.7914044571 | 0m |
| Vault | 1593.9225861010, -1773.7863902940, 14.6251889420 | -0.0001m |

The offsets describe the controlled query construction; Float conversion at
these world coordinates also affects the exact contact separation. A Capsule
with zero half-height is therefore not an exact substitute for a Ball on
these real trimesh boundaries. Build 77 preserves the frozen implementation
and this unresolved result. A literal Ball overlap boundary requires a later
bridge/reference phase; shrinking radii or silently relaxing the test would
not establish parity. No retail behavior claim follows from these browser
comparisons, and no App/bridge change was made during this investigation.

All raw collision inputs, bounded source extracts, query fixtures and detailed
reports remain under ignored `local-only/research/climbing/`. This document
contains only independently measured results and test coordinates.
