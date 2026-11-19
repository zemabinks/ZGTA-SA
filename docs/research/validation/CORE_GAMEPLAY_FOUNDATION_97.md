# Combat, crash and vehicle-to-foot gameplay corrections

Final source candidateCore98 retains the identical native build97 sources.
This pass continues the core-gameplay priority before additional roleplay
features. The public source combines the front melee blocking corrections with
bike impact/rollover ejection, original adjacent exit geometry, completed wreck
death, lost-water release and armour-aware crash damage.

## Shared ownership fixes

Front melee blocks prevent authoritative damage before health/armour changes.
A distinct connection-scoped hit sequence delivers repeated unchanged-health
parries once. [Melee evidence and limits](../combat/CORE_MELEE_PARRY_93.md).

Owned chassis contacts now reach the motorcycle/bicycle rider. The original
weighted impact and contact-gated rollover laws retain preceding velocity and
coalesce one consumed event. Forced exit parks the actual bike with momentum,
uses the entry animation's terminal root for its adjacent point, restores native
foot physics and plays the correct directional knock or death.
[Bike evidence and limits](../vehicles/CORE_BIKE_EJECTION_94.md).

A completed wreck releases and defeats its occupant once, preserving an already
accepted cause. Lost-water release is separate: the occupant stays alive and
returns to the foot/swim owner. The order is completed wreck, lost water, then
bike ejection. Disabled health is not confused with a completed wreck.
[Wreck handling](../vehicles/CORE_WRECKED_VEHICLE_95.md),
[water release](../vehicles/CORE_VEHICLE_WATER_EXIT_96.md).

The deeper damage audit found that crash damage must pass through armour. Native
health prediction now orders armour-absorbing impacts and armour-bypassing falls
in one bounded connection sequence. Authoritative snapshots rebase remaining
operations in that order; acknowledgements remove each accepted operation once.
The real game controller routes a crash amount to that owner instead of also
subtracting health in the Renderer. Both HUD values update immediately. A crash
fully absorbed by armour still produces its original physical knock. A fatal
crash chooses death only after armour is accounted for. Completed wreck defeat
retains its separate armour-bypassing fatal path.

The server accepts the new impact operation in the same health acknowledgement
namespace and deduplicates it before changing armour, health or death counts.
Legacy browser frames can report a bounded armour decrease; stale frames
cannot restore it. Acknowledged native frames do not override their sequenced
authority. Observer rows use authoritative armour, so remote reactions and
HUD values do not display an unaccepted or stale shield.

Amounts are bounded by the maximum200 combined health/armour. Update the native
client and independent server together for this operation. Older independent
servers do not implement it.

## Verification boundaries

The focused record includes actual archived hurt/side/impact/rollover/water/rider
routines, native real clip and physics integration, actual extracted Renderer
and controller methods, and real native HTTP/URLSession/WebSocket through the
independent server with legacy-shaped observers. These categories remain
separate from retail execution and physical-device acceptance.

Armour/crash ordering matches1,512 actual archived integer damage frames across
252 ordered scenarios, with and without immediate acknowledgement. Actual
native transport checks mixed crash/fall requests, intermediate acknowledgements,
duplicate requests and a single fatal death. Existing stale-HTTP, lost-ACK,
respawn, shot/coupling, movement, camera and other core gates remain regressions.
Final acceptance passes**107/107 gates**, captured sources unchanged. Both
Release Simulator and unsigned generic iPhone builds97 pass; every native App
byte inCore98 matches those builds. The unchanged Swift/C/Rust boundary retains
its prior five-link Apple ABI evidence. Reports, hashes and build records stay
in the owner's ignored local-only acceptance directory.

An isolated iPhone12Pro Simulator on iOS26.3.1 also passed an actual UI test:
native main menu, guest multiplayer connection without Discord, world entry
and a synthesized movement-stick gesture. The real server recorded10.14m of
horizontal travel and a stable reported position after release; the native
scene screenshot was inspected. The native97 sources and staged server bytes
match this final candidate. This establishes that named native launch/walk path,
not retail comparison, physical input, device FPS or every rendered transition.
Screenshots, traces and the XCTest result stay local.

## Open differences

No1:1 retail accuracy is claimed. Original retail execution, side-by-side rendered scene
comparison, physical touch/controller acceptance and iPhone performance still
need separate verification. The supplied IPA is a static reference, not a
Simulator executable or proof that retail gameplay ran.

The independent health interface uses integer values; fractional original damage
is rounded at its current boundary. The original general blocked/ground/door
exit-clearance planner, missing-rider fallback, passenger fall-off, complete
vehicle-to-pedestrian ramming/blade contacts, special combat/counterstyles,
complete hitboxes/damage balance and remaining original NPC/world behavior are
still open. Their presence in the checklist does not mark them implemented.

Original assets, website scripts, imported resources, converted game data and
reference captures stay local. Public source remains independently written AGPL.
Production servers and the preserved stable app are unchanged by this QA pass.
