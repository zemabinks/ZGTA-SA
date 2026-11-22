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

Native application build189 and independent server changes throughCore191 form
the latest verified source batch.

Native pedestrian pose time now follows observation boundaries. New hit/down
states begin at receipt rather than inheriting the preceding display interval;
fractional intervals retain their ownership without advancing twice. Rider
handoffs reset that clock. Persistent head visibility also applies at stream-in,
and a late first death cause can correct the existing clip without resetting its
phase or the later get-up orientation. Authored backend-packet/native-controller
checks cover fixed and irregular display schedules, late and split observations,
repeated metadata, invalid clocks and lying rider handoffs. These are independent
contracts, not original executable timings.

Both native SDK builds and the complete selected regression chain pass. The
verified native bundle completes a normal Simulator join, scoped NPC lifecycle
observation and menu/resource restoration; saved captures were reviewed. The
private scene uses owner-supplied original model/world resources with explicit
scripted idle/streaming and an owned acknowledged shooter. It does not establish
native aiming, full ambient AI, physical-device behavior, audible output,
continuous animation fidelity or retail parity. Existing installed resources and
meaningful settings survive the update and normal test flow.

The optional archived-policy test carrier now supports the current controller
interface and persistent visibility. An independent authored contract exercises
that optional path in the default regression chain, including delayed death
correction and recovery. The old carrier fails compilation as expected. Authored
rows are identified separately from real archived observations; compilation of
this path does not turn those authored rows into an original-game comparison.

Authoritative NPC movement also settles before flee, gunshot, injury and death
events. Panic expiry splits the running/walking interval at its deadline;
repeated or backward clock samples cannot replay motion. Hit clearance and range
checks observe the settled target. The old source reproduces event, deadline,
shared-actor, clock and stale melee-range failures. Analytical task/producer and
actual backend handler checks pass with authored pavement/geometry boundaries,
alongside retained lifetime, body-part, protocol and complete selected checks.
The existing catch-up cap and independent movement parameters remain explicit.

These changes improve independently implemented core correctness. Complete
original NPC/traffic/police AI, density/model-group policy, cumulative vehicle
damage authority, external-server coverage, full original resource/runtime
support and comprehensive original-game comparisons remain open. Only independent
source and qualified notes are public; original resources, derived data,
measurements, captures and private ancestry remain local.

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
