# Shared ambient pedestrians — Core158

## Core189–191 NPC transition and event clocks

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

## Core186–188 configuration, lifetimes and hit metadata

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

## Core185 prepared model admission

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
