# Core104 physical-device corrections

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
| Physical idle-time interval |318.782 seconds without device commands, connections, input, media or developer power assertions; the endpoint remains unlocked in the foreground game with a stationary actor. The user's configured auto-lock duration is unknown, so this is bounded observational evidence |
| Physical camera |389 captured access units with0 RTP gaps; horizontal orbit and up/down pitch respond, release stops camera motion, and the standing actor retains independent facing. Exact sensitivity, collision and transition timing are unmeasured |
| Physical jetpack |A clearer530-frame capture shows normal Run/rise, airborne turn, descent and standing touchdown without reproducing an instant180-degree reversal. Exact retail flight animation, forces and timing remain unverified; a short camera-distance change during descent has not been attributed |
| Physical background/resume |Normal Home and non-killing app foregrounding return to a stationary actor in the recorded endpoint. A later capture shows changed equipment/location with no intervening tester action; its cause is unresolved. Full equipment/position continuity is not accepted |
| Physical controls and rendered peers |Fresh Core104 scenes verify matching own/remote male01 and Maccer appearances. Guarded overlapping recordings cover native4.766m walk/release in the browser and browser853ms forward/release on the stationary phone. Vehicle and controller acceptance remain separate |
| Retail gameplay |The owner's DE app provides visible menu, walk/release, turning, camera and BMX boarding/exit reference footage. Exact classic-game feel and a matched quantitative native replay remain open |

This is a Debug functional device build. Core103's separately successful
optimized iPhone and Simulator builds do not establish Core104 sustained FPS.
Single screenshots of a developer FPS counter are not a performance benchmark.
The same captured App sources also pass a complete optimized Core104 iPhone
Release build. Signing/install and that build's device acceptance are separate.

One later touch on the top pause action did not open its menu. Keyboard Escape
opened it, and subsequent touch scrolling and Return to Main Menu worked. The
Metal HUD overlapped that region; its involvement and the precise cause remain
unverified. This isolated failure is retained rather than counting every issued
input as a successful UI action.

All phone captures, installation details, original assets and source-resource
comparisons stay under ignored `local-only/`. The independent app/server/tools
remain AGPL-3.0 source. No original binary or extracted asset is part of a source
release.
