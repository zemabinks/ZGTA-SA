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

An opt-in independent-server road population now uses verified prepared road
and vehicle identities. One fixed simulation clock owns shared traffic, bounded
route following, braking for nearby obstacles, oriented body footprints,
publication interest and stopped-car transfer into the normal registered vehicle
permission system. The native client negotiates traffic separately from
pedestrian capability and revokes pending callbacks when its session changes.

Spawn admission checks body-length static rays, model-origin offsets and
endpoint support on slopes before a lifetime appears. Unobserved stopped cars
release the population budget after the existing timeout. Previous-source
witnesses and focused source/transport regressions are retained locally.

Both unsigned native SDK products and the full selected physics/audio/transport
source chain pass. Earlier dedicated Simulator cases cover retained resources,
normal joins, grouped firing, scope rendering and original-model traffic draws.
The current touch HUD includes a negotiated traffic-only entry target and shares
its range/capability predicate with the actual action. Previous source fails the
traffic-only visibility witness; the current branch passes 20 authored checks.

A dedicated normal-touch Simulator case verifies traffic-only entry after real
AI braking for an ordinary registered roadblock, server driver permission,
shared compact/registered identity, normal reverse/park/exit/reentry and claim
release on disconnect. Both
protocol observers receive the handoff. This is not a rendered browser case.
Current shoreline test results and remaining limitations are maintained in the
parity checklist; they do not establish every water state or original timings.

This remains an independent traffic foundation. Original zone/time/model
distribution, signals, intersections, complete avoidance and crash physics,
moving-car jacking, NPC driver egress, vehicle damage and police remain open.
A protocol observer is not a rendered browser test. No complete traffic AI,
hardware performance or original-PC retail parity is claimed. Original resources,
measurements, captures and private Git ancestry remain outside this repository.

A separate normal-touch Simulator shoreline case observes all seven supported swim actions, oxygen consumption and recovery, return to dry ground and a subsequent foot jump. Saved captures and received movement samples are reviewed separately. It uses one controlled initial shoreline spawn and actual subsequent input; it does not establish original-PC swim timings, underwater animation fidelity, exact camera behavior or hardware performance. The first short-return scenario remains a recorded failure; a longer return gesture completes the actual shore transition.

Original population group, cycle and zone resources now have an independent local decoder and preparation command. Fifteen authored tests and retained original-data decoding/addressing pass. These tables are not yet activated in native or server population policy; full original density, zone assignments, model admission and NPC AI remain open. Generated original-derived data stays local.

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
