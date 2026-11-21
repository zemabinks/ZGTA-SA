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

The independent server negotiates grouped ordinary shots with compatible
native clients. One firing marker spends one cartridge and sequence; each
admitted target group settles once. Player damage uses the server's catalog,
world/life/coverage checks and accepted strike metadata. Vehicle hit reports
still do not supply complete vehicle-health authority. Older browser and
legacy adapters retain their own accounting and protocol limits.

Vehicle queries refresh admitted bodies and nominal tyres through the shared
read-only transform producers. Actor/registry lifetimes, resource identity and
compact-vehicle promotion fence completed geometry. A shot query never advances
physics or animation. Model-local hierarchy/visibility and human manually
followed poses remain tied to their last completed presentation phase.

The HUD clears superseded weapon images, rejects stale source completions and
reuses loaded requests. An optional local converter prepares original HUD
sprites at their source resolution and adds them to the prepared resource
index. It requires the user's original files; those files are excluded from
this repository. Preparing a resource is separate from verifying its use in
the running app and after a persistent resource update.

Positive foreground render hitches retain held input and touch aim while
skipping excess simulation time. Clock reversal and existing focus/modal
ownership loss still clear controls. Successful reloads use their owned HUD and
animation feedback without leaving a generic progress message after completion.

Core176 passes both SDK products, the full physics/audio/transport source chain,
four normal resource-preserving joins, six grouped ordinary-shot markers and a
separate scoped far-target case. The latter confirms the original distant actor,
source delivery, ammunition, damage and retained touch aim. All 26 selected
captures are reviewed. The older Core173 far-target failure remains recorded;
it is not relabeled by this newer case. Scope captures also demonstrate exposed
world strips outside the shortened HUD mask; that presentation gap remains open
in this verified build.

Native setup prepares source-resolution weapon icons before indexing. Repeated
preparation verifies current definition/TXD and output identities before reuse;
changed or corrupt output fails without replacing the retained generation. Ten
authored tests pass. Persistent installed icon-package updates remain unverified.

An isolated, explicitly supplemental pedestrian identity admits the user's
original Maccer model without mislabeling it as a retail IDE entry. Genuine
collision inventory regeneration, complete native rig admission, original
material/GPU checks and normal original-model drawing pass in the unchanged
Core176 app. The normal four-join case retains resources and settings. Selected
captures confirm original artwork; resources and supplemental local configuration
are not distributed in this source repository.

Separate normal-input jetpack cases cover short forward takeoffs and a stronger
vertical-thrust, held-brake, descent and landing sequence. The stronger case has
airborne packets during braking/descent and sampled landing headings without a
half-turn. Post-case samples also show a steady
airborne interval during each held brake. All 32 selected flight stills across
the two cases are reviewed. These samples do not rule out subframe animation
faults or establish original-PC flight timing. The first case's nominal hover
and descent phases were grounded, so that case alone does not verify them.

Standing/crouched feet remain visually questionable. Old contact log records
were truncated; a separate read-only debugger attempt failed to decode its array
and detached cleanly. No incomplete measurement supplies a guessed height fix.
Vehicle hierarchy timing, full vehicle-health authority, browser/native combat
accounting, continuous animation, device performance and original-PC fidelity
remain open. No complete-game or 1:1 claim is made.

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
