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

Compact traffic now has separate native record/scene ownership, original road
prediction and vehicle presentation, bounded nearby contacts and materialization
requests. Optional owner-provided metadata selects original seated characters.
Source/session cleanup, graph and metadata retries, predicted lane presentation
and passenger camera filtering have corresponding regressions.

Compact lamp inputs now follow time, weather and the selected signed motion
sample. Spatial vehicle audio accepts typed traffic sources separately from
players, with stable ordering and voice identities.

Both unsigned native builds, the current full source regression chain and
controlled retained-resource Simulator cases pass. Reviewed captures show
original characters, Taxi/Infernus presentation, healthy/dead/restored seated
poses and day/night transitions. Actual original Taxi metadata also passes the
renderer lamp-selection checks. These cases do not establish exact GPU lamp
brightness, projected beams, audio playback, physical-iPhone performance or
original-PC gameplay parity.

Compact motorcycle riders now play original fall clips, retain completed fallen
poses and preserve their animation when a compatible original model arrives.
Detached drivers expire independently of retained passengers. An existing
server-owned NPC can receive the completed driver pose without creating a
player or changing authoritative health or goals. The latest normal four-join
and controlled traffic/bike cases pass, with 41 captures reviewed. The NPC
handoff has an actual draw receipt; its body is partly obscured in the capture,
so unobstructed visual continuity remains unverified.

Original traffic AI, ownership transfer/jacking, broader collision-driven
ejection, driver gun/look/voice behavior and general traffic combat remain
incomplete. The previously
reported intermittent pedestrian draw still lacks a confirmed cause. See the
[traffic implementation scope](research/gameplay/CORE_AMBIENT_TRAFFIC.md).

Compact traffic shots now enter a shared native bullet-presentation path with
bounded Metal tracers, material-aware impacts and positioned attack/pass-by
audio. The selected source chain, both native SDK builds and normal retained-data
Simulator cases pass; 46 captures were reviewed. Actual tracer submission was
observed, while the short-lived effects and audible playback are not verified
for every shot. These shots cannot grant damage. Seated gun poses, the human
shot path, local ordinary hit resolution and procedural fallback effects remain
separate work. Original PC gameplay parity remains unverified.

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
