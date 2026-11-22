# Shared ambient pedestrians — Core158

## Core183 original population resources — decoder foundation

The local preparation command now decodes `pedgrp.dat`, `cargrp.dat`,
`popcycle.dat`, `info.zon` and `map.zon` from an owner's extracted game folder.
It retains group order, repeated names, raw population bytes and zone geometry.
The lookup helper addresses the two-hour table buckets explicitly by population
type and week part. Model resolution uses a complete IDE identity index before
the pedestrian/vehicle group capacities; a missing mesh subset must not shift
group identities. Resource admission and actual runtime population remain separate.

```sh
python3 tools/assets/prepare_population_tables.py \
  --game-dir /path/to/your/extracted-game \
  --output local-only/population-tables.json
python3 tests/resources/test_population_tables.py
```

The output contains original-derived data and must remain local. Identical
preparation reuses the existing file; changed output requires a new destination
and never replaces original inputs or an existing unrelated file. Outputs inside
this repository are restricted to ignored `local-only/`; the prior unrestricted
preparer fails the authored refusal witness. Fifteen
authored tests pass. The retained original corpus separately decodes all groups,
cycle rows and zones; this is data-format validation, not retail execution.

The format reference is the community's source reconstruction of
[population loading](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Population.cpp),
[cycle addressing](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/PopCycle.cpp)
and [zone fields](https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/ZoneInfo.h).
That project includes refactors and bug-fix variants, so these references do not
establish exact original executable behavior. The decoder preserves source values
without silently normalizing weights or assigning a population type to a zone.
Original zone-type initialization, complete model admission, weather/density
policy, server activation, native consumption and visible population acceptance
remain open. The current independent population still uses its existing profile.

The independent server can now own a bounded civilian population on verified
original pavement paths. Native clients receive separate typed NPC records,
load the matching original character resources, predict the announced goals,
draw their original skeletons and register nearby pedestrian collision bodies.
NPCs do not become human roster entries. External servers remain authoritative;
the client does not generate additional local inhabitants in their worlds.

This is an initial integrated population, not complete San Andreas AI. Walking,
obstacle waits, recovery, gunshot flight, injury, death and distance-based
lifetime are implemented. Original population groups, zone/time density,
traffic, police, social activities and complete NPC event/animation behavior
remain incomplete. Campaign missions are outside the project objective.

## Original resources and preparation

The independent path converter reads all64 original PC `NODES*.DAT` areas,
checks identities, adjacency and targets, then writes the compact SDPDv1 graph
used by the existing browser protocol. Original coordinates, pavement widths
and edge kinds are preserved. A node byte unused by that decoder is zeroed;
the converted graph therefore has its own CRC. Do not advertise another file's
CRC or interpret matching graph sections as matching original task policy.

Resource comparisons validate the used original graph sections. Civilian
selection requires prepared mesh, texture and skeleton resources; presence
alone does not establish exhaustive GPU compatibility.

For an already prepared owner-local site and matching extracted original
`peds.ide`, the opt-in server configuration is generated with:

```sh
python3 tools/assets/prepare_population.py --peds-ide /path/to/owned/data/peds.ide
```

The command writes `local-only/selfhost/population.json`. Restart the independent
server to load it. Existing installations without this file retain their
current population behavior. The server and the prepared site must use the
same graph bytes and matching CRC. This command does not extract a complete
playable game from an ISO. Original data and derived resources stay local.

## Ownership and integration

The server admits spawn locations through original graph queries and actual
world height/line checks. It owns health, goals, panic, corpse lifetime and
interest sets. Accepted NPC damage uses the existing connection, weapon,
shot-sequence, range, visibility and cadence validation. Duplicate and stale
claims cannot damage the same actor again. Dead actors stop moving.

Native protocol tags7/8/10/11 retain path/free motion, removal and additional
state separately from human snapshots. Graph loading is bounded and fenced by
resource source, request identity and CRC. Actor replacement, level changes,
disconnects and stale records retire presentation and physical owners. Nearby
upright actors use actual Rapier kinematic capsules in local foot contacts;
no vehicle runover policy is inferred from those bodies.

Blocked server actors publish zero desired speed while preserving their task's
recovery intention. A wait flag alone did not stop client prediction, which
could otherwise drift into a blocked edge between stationary refreshes.

## Verification scope

Focused path/protocol, motion, task, damage-authority, common-animation and
actual Rapier tests pass. Separate comparisons use owner-local original
resources and the archived prediction kernel. Both SDK builds and the complete
selected optional Metal/physics/audio/transport source chain pass.

Controlled retained-data Simulator checks cover development and installed
resource modes, normal walking/camera, Taxi entry/exit, menu restoration,
shared pedestrian motion and original draw encoding. Installed resources and
gameplay preferences remain intact. Reviewed stills do not establish complete
NPC pose quality, all camera transitions or continuous animation timing.
Unsigned iPhone compilation does not establish physical-device performance.

Detailed captures, reference fixtures, measurements and failed-run history
remain owner-local. The public repository contains independent source and tests.
These checks do not establish original PC retail accuracy or full browser/native
multiplayer acceptance.

## NPC pose and route follow-up — Core159 scoped acceptance

NPC animation ownership is separate from human health/timed recovery. The
server down flag holds a fallen pose until cleared, causal hits select the
existing original death/reaction clips, and authoritative recovery restores the
appropriate get-up action. Weapon stances follow task state. Incoming angles
use the correct wire/native axes, shortest wrapping and strict sector ties.

The native pose controller uses a fixed retained clock. Server path arrival
integrates acceleration and carries unused elapsed time into the next edge.
Focused component and separate archived-policy comparisons pass within their
stated boundaries; they do not execute a complete original retail engine.

Social activities, phone, attention, speech, complete special events, runover
and original population/traffic/police AI remain unfinished in this version.
Two rendered clients, hardware behavior and complete NPC visual fidelity still
need appropriate acceptance. No1:1 parity is claimed.


## NPC activities, waiting and local lifetimes

NPC task poses now use a separate owner of the existing original-animation
controller. Activity entry/loop/exit policy, retained down/hit state and model
turn rates are applied without sharing the local player's animation clock.
Optional activity traits are bound to exact model and resource-source identity;
older catalogs remain readable. The source converter derives those traits from
original metadata instead of guessing from a model's name.

Waiting uses the next edge's kind and style-specific crossing or delayed idle
clips. A local generation separates a newly admitted actor from an earlier
actor with the same wire ID, model and seed. Animation, ground smoothing and
nearby physical bodies use that lifetime while preserving server target IDs.
An independent-server wait publishes zero desired speed so prediction stops.

Focused authored gates, separate owner-local controller/resource comparisons,
both SDK builds and the complete selected optional source chain pass. A normal
retained-data Simulator case passes through four joins, character movement,
Taxi entry/exit, camera input and menu restoration. A separate server-owned
population case passes in development and installed modes. Reviewed activity
stills isolate original male/female resources and distinct task stances;
resources/settings are retained and owned QA processes stop afterward.

The stills are not exact blend/timing or retail acceptance. The activity case
uses explicit server inputs on existing NPCs; benches and autonomous social AI
are not implemented by this change. Waiting/crossing/respawn visual coverage
also remains separate. An earlier intermittent missing NPC draw is retained as
an unresolved failure despite the later passing run. Full NPC events, original
population policy, traffic, police and complete gameplay parity remain open.
