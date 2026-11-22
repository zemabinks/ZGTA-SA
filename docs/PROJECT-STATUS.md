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

Registered vehicle rows now publish their authoritative condition consistently.
Normal, pending and terminal parked reports follow the current registered hull
only within the same vehicle and driver-claim lifetime. Later collisions cannot
be reversed by a retained exit snapshot, and a replacement cannot borrow that
old stand-in. Empty unattended predictions cannot clear accepted damage; actual
paid repairs still create their correct fresh condition.

Three retained previous-source witnesses fail. Focused handler, real loopback
HTTP/WebSocket and complete native URLSession receiving cases pass, including
baseline, queued driving, parking, later motion and replacement. Native product
inputs remain identical to the accepted Core182 SDK/App. The complete Core184 selected physics/audio/transport source chain passes.
Core185 resource-specific checks pass separately. No new rendered App, browser,
hardware or original-retail accuracy is inferred from these transport cases.

NPC population preparation and server admission now require structurally matching
prepared mesh/atlas-header/skeleton families. Newly generated profiles bind the
index, navigation and selected family files to source hashes. Explicit model
selection requires every requested civilian family. Existing owner-local aliases
remain supported. Authored malformed-family, CLI and actual loader tests pass;
retained original-resource admission also passes without altering the sources. A separate offline original-world task probe
also runs the existing independent NPC tasks over original navigation and
collision; its packets are in memory, without a rendered client.
These checks do not decode pixels, reconstruct bind poses, sample animations or
establish a GPU draw. Legacy profiles validate current families without a
historical source-hash guarantee.

The cumulative local/server vehicle-damage ledger, full vehicle weapon damage,
original population groups/zone/time density, client-wide model availability,
complete NPC/traffic/police AI and retail gameplay accuracy remain incomplete.
Original assets, derived tables, measurements, recordings and private Git
ancestry remain local. Only independently authored source and these qualified
implementation records are published.

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
