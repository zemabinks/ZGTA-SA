# Core104 physical-device corrections

**Evidence qualification,2026-11-17:** concurrent human use of the phone was
subsequently confirmed. Exclusive scripted input was not established for the
broader session. Rendered observations remain useful, but later vehicle input,
exit and unexplained state changes cannot diagnose input or exit defects. The
command-free idle interval is not isolated proof of the app's sleep policy.

## Observed warning and display lifecycle

The paired iPhone12Pro, running iOS27.2, displayed the following Metal diagnostic
over the actual Core103 game:

`LSSupportsGameMode key not found in Info.plist.`

Core104 sets `LSSupportsGameMode` to true in the app's actual Info.plist. The
signed build's processed plist contains that value. This declares eligibility;
it is not evidence of a performance increase or of active Game Mode. The
existing performance HUD is a developer diagnostic, not an in-game account or
server error. A subsequent physical screenshot inside the actual Core104 LAN
game shows the warning absent while that HUD remains enabled and reports Game
Mode On. This is an observation of that run, not a guaranteed operating-system
policy for every device or launch.

During physical testing the previous app also let the phone auto-lock.
`NativeGameplayIdleTimer` now owns the display-sleep policy while foreground
gameplay is active. It saves the pre-game value and restores it on background
or final exit. Controller replacement retains that original value. An older
controller's delayed cleanup or notification cannot release a newer game's
ownership. This does not unlock a device or change its configured lock policy.

The native game controller claims ownership on appearance, updates it on
application activity, and releases it on permanent shutdown or deinitialization.
Temporary in-game presentations retain the live world's ownership.

## Validation boundaries

| Evidence | Result and scope |
| --- | --- |
| Actual idle-policy helper |886 checks pass, including replacement, stale callbacks, background/foreground, duplicate notifications and restoration of both possible pre-game values |
| Extracted production controller/renderer lifecycle |61 checks pass; the existing49 checks remain, with display-ownership and actual resign/return-hook checks, including late resume after permanent shutdown. UI/audio/network resource boundaries are explicit spies |
| Actual iPhone SDK |All App Swift files typecheck; the complete Debug app compiles, links, signs, installs and launches successfully |
| Actual physical launch and game entry |Normal menu, private LAN join and world entry succeed. The city, local actor, minimap/HUD and1-player roster are visible; the missing-key warning is absent with the Metal HUD still enabled |
| Physical idle-time interval |318.782 seconds without harness commands, connections, automated input, media or developer power assertions; the endpoint remains unlocked in the foreground game. Auto-lock duration and exclusive human-free conditions were not established, so controlled idle-policy acceptance remains open |
| Physical camera |389 captured access units with0 RTP gaps; horizontal orbit and up/down pitch respond, release stops camera motion, and the standing actor retains independent facing. Exact sensitivity, collision and transition timing are unmeasured |
| Physical jetpack |A clearer530-frame capture shows normal Run/rise, airborne turn, descent and standing touchdown without reproducing an instant180-degree reversal. Exact retail flight animation, forces and timing remain unverified; a short camera-distance change during descent has not been attributed |
| Physical background/resume |Normal Home and non-killing foregrounding reach a stationary recorded endpoint. Later equipment/location changes are human-confounded; no teleport, stuck-input or broken-resume defect is established from them. Full controlled continuity remains unverified |
| Physical controls and rendered peers |Fresh Core104 scenes verify matching own/remote male01 and Maccer appearances. Guarded overlapping recordings show native movement/release in the browser and browser movement/release on the phone. They establish rendered motion, not isolated input-response latency or complete control parity |
| Physical vehicles |The same420.6.1.0. loan taxi is yellow/orange in the browser and grey natively; the browser also shows simultaneous parked/driven bodies for the same vehicle. These two defects are retained. Later gas/brake/exit attribution is human-confounded and is not accepted as a controlled mechanics test |
| Retail gameplay |The owner's DE app provides visible menu, walk/release, turning, camera and BMX boarding/exit reference footage. Exact classic-game feel and a matched quantitative native replay remain open |

This is a Debug functional device build. Core103's separately successful
optimized iPhone and Simulator builds do not establish Core104 sustained FPS.
Single screenshots of a developer FPS counter are not a performance benchmark.
The same captured App sources also pass a complete optimized Core104 iPhone
Release build. Signing/install and that build's device acceptance are separate.

A later top-pause touch was not accepted as successful navigation. Escape and
subsequent touch scrolling/Return to Main Menu were observed working. Human
input was not isolated, so this trial does not establish a broken pause button
or a causal role for the overlapping Metal HUD.

All phone captures, installation details, original assets and source-resource
comparisons stay under ignored `local-only/`. The independent app/server/tools
remain AGPL-3.0 source. No original binary or extracted asset is part of a source
release.
