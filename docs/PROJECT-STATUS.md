# ZGTA:SA project status

This is an independently developed native iOS client and multiplayer server.
It is unfinished. Public source does not include original game resources or a
packaged public iPhone release. Users must supply their own supported game files.

## Current implementation

| Area | Available foundation | Remaining work |
| --- | --- | --- |
| Native iOS | Swift/UIKit/Metal scene, streaming, character and vehicle controls, physics, animations, HUD and audio | Complete original gameplay fidelity, resource coverage and hardware performance verification |
| Game files | Persistent prepared-resource storage, verification and raw ISO extraction tools | Complete native conversion from a selected original ISO to a playable standalone installation |
| Development resources | Mac-hosted resources and reusable local caches | Broader installation and repair coverage |
| Independent multiplayer | Guest access, shared players, vehicles and gameplay systems | Complete server systems and cross-client consistency |
| Pedestrians | Server-owned population, original character resources, navigation, animation tasks and nearby contacts | Original density, social behavior, full events and AI |
| Traffic and police | Typed traffic records, original road/vehicle presentation, seated actors, lamp inputs, spatial audio candidates and bounded nearby contacts | Original simulation, authority, density, police and complete behavior |
| SA-MP/open.mp | Separate experimental compatibility adapter | Full server, extension and content compatibility |
| Original browser service | Separate account/protocol integration | Complete world and gameplay interoperability |

## Latest verified source

The current verified batch adds shared human/traffic shot presentation, remote
hit reactions and native local ordinary-hit selection. Original shot groups
and material-aware impacts feed bounded Metal effects and positioned audio.
Native hit selection uses the current actor/vehicle pose, typed targets and
world coverage; unloaded collision cannot grant a clear shot. Session and
resource ownership prevent retired actors or resources from supplying targets.

Universal Simulator Debug and arm64 iPhone Release builds pass, together with
the complete current source regression chain. Controlled Simulator cases pass
for four normal retained-resource joins, compact traffic and bike/NPC lifetime
transitions, and normal-input pistol/shotgun firing, reload and hit reports.
All 62 captures were reviewed. Original assets and application settings remain
held; owned test services and the Simulator stop afterward.

These cases establish a limited integration scope. Vehicle hit reports do not
provide complete vehicle-damage authority. Browser/native shot accounting,
complete traffic AI, every animation/contact transition, audible playback,
physical-iPhone performance and original-PC gameplay fidelity remain open.
The NPC handoff has a draw receipt but is partly obscured visually. Weapon-icon
coverage, stale reload text and crouch grounding also need follow-up. No full
gameplay or 1:1 accuracy claim is made.

See the [traffic implementation scope](research/gameplay/CORE_AMBIENT_TRAFFIC.md)
and [core gameplay checklist](development/CORE_GAMEPLAY_PARITY.md).

## Development priorities

Continue improving original movement, animation, cameras, physics, vehicles and
combat before expanding roleplay features. Complete original-resource support,
pedestrians, traffic, police and shared world state remain major priorities.
Original single-player campaign missions are outside this project's scope.

Different server protocols do not automatically share a world. Native and
browser players need the same compatible destination, resources and server
support. Compatibility with every SA-MP/open.mp server is not guaranteed.

## Guides

- [Start here](START-HERE.md)
- [Game files](GAME-FILES.md)
- [Multiplayer](MULTIPLAYER.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Development](DEVELOPMENT.md)
- [Feature matrix](development/FEATURE_MATRIX.md)
- [Core gameplay checklist](development/CORE_GAMEPLAY_PARITY.md)
- [Server compatibility](development/SERVER_COMPATIBILITY.md)

Detailed private captures, original-resource observations and development
measurements remain local. Public documentation distinguishes implemented source
from tested scenarios and unfinished work.

[← All guides](README.md)
