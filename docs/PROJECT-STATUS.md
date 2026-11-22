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

Population preparation can optionally derive zone settings from an owner-supplied
classic main.scm. A bounded typed parser admits only a statically verified literal
configuration block, without running or reconstructing campaign missions. Zone
keys, shared settings, short bounds and lookup follow the primary source-level
references; original executable behavior is not established by those references.
Original-derived tables stay local and the original v1 output remains unchanged.
Authored miniature-script/lookup/CLI tests and independent local static comparison
pass. Original density and model-group activation remain separate requirements.

Pedestrian retention now uses the same distance as publication and local spawn
counts. An invisible outer ring can no longer occupy shared capacity indefinitely;
another nearby observer still preserves the exact actor. The previous source
reproduces the stall. Authored boundary/lifetime tests and two real loopback
WebSocket scenarios pass, including streamout, replacement and disconnect.
Their pavement and geometry are authored boundaries, not a rendered world test.

Accepted ordinary shot body parts now reach the pedestrian reaction state and
supplemental packet. Later claims cannot replace the accepted ticket metadata.
Unrepresentable legacy/absent pieces retain the old torso fallback. Damage,
ammunition and range/visibility authority remain unchanged. The previous source
loses admitted head metadata; current actual handler/task/packet checks pass.
Actual backend-produced bytes also pass through the complete native decoder and
common animation owner at several display rates, including its existing terminal
head visibility result. This uses authored clips, catalog, graph and transport/
geometry boundaries; it does not establish rendered rig or retail accuracy.

The full Core187 selected physics/audio/transport regression chain passes. The
Core188 metadata change passes its affected handler and native pipeline checks.
All native product inputs retain the accepted Core182 SDK/App sources. No new
App/SDK, rendered-world, physical-device or retail acceptance is inferred. Full vehicle damage
authority, original population density/groups, complete NPC/traffic/police AI,
external-server coverage and exhaustive core gameplay parity remain incomplete.
Only independently authored source and qualified implementation notes are public;
original resources, derived data, measurements, captures and private ancestry stay
local.

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
