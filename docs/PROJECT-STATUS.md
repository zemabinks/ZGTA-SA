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

Local foot rendering and camera follow now interpolate fixed-step display
history and vertical easing. Physics state, velocity, network positions and
shot-marker feet retain their committed boundaries. Focused source regressions
cover 30/60/75/120/144 Hz and reproduce the previous high-refresh defect.

The scope mask covers the full game window, including partial redraws. Bounded,
checksummed diagnostics retain complete submitted-pose records, including the
maximum slash-heavy payload case. No generic gravity or character-height offset
was changed to compensate for incomplete contact evidence.

Both unsigned SDK products and the full selected physics/audio/transport
regression chain pass. Dedicated Simulator cases pass normal development and
installed-resource joins, grouped pistol/shotgun firing, reload and far-target
scoped shooting. Original characters, HUD resources, real server settlement,
settings and installed metadata are retained. All 26 selected saved stills are
reviewed, and 16 complete contact records are decoded. Earlier failed attempts
remain preserved locally; later passing cases do not relabel them.

These cases establish limited integration scopes. Stable CPU contact records
are not visible-sole measurements. Continuous animation and display behavior,
complete vehicle/world interactions, ambient AI, physical-iPhone performance and
original-PC retail equivalence remain open. Original resources, captures and
private history remain outside this repository. No complete-game or 1:1 claim
is made.

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
