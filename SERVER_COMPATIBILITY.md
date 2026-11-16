# Existing SA-MP and open.mp servers

Status checked 2026-11-16: the native ZGTA SA client currently uses our independent
HTTP/WebSocket multiplayer server. It cannot directly join SA-MP 0.3.7,
SA-MP 0.3.DL or open.mp servers. No compatibility option is exposed in the app.

The owner explicitly targets both those existing server lobbies and the
original [play.samp.directory](https://play.samp.directory/) world from the native
app. These are separate adapters; the current independent server remains a
supported destination.

Joining existing servers is technically plausible as a substantial additional
client implementation. Preserving familiar game mechanics remains the first
priority; exchanging positions alone would not make an existing roleplay
server playable.

## Required compatibility work

| Area | Required implementation and evidence |
| --- | --- |
| Transport | Legacy-compatible RakNet/UDP session, connection/challenge handling, reliability, ordering, timeouts and server version negotiation. Current WebSocket JSON packets are a separate protocol. |
| Gameplay synchronization | Pedestrian/vehicle/passenger/aim/bullet/death/animation state, identifiers and their actual packet encodings and authority rules. Preserve responsive local simulation. |
| Server-controlled game world | Spawn/class selection, world/interior changes, vehicles, objects, pickups, actors, checkpoints, attachments, settings and cleanup. |
| Server UI | Chat, commands, dialogs, textdraws, menus and input expected by existing game modes. |
| 0.3.DL | Custom model catalog and downloads, checks, model-ID mapping and runtime asset loading. Existing owner-local offline conversions do not yet provide that protocol or a complete runtime importer. |
| Extensions | Each server's custom launcher, CEF, voice or client-specific extensions require separate supported adapters and acceptance. Do not promise every server works. |
| Validation | Use an owned local test server first, then consenting server operators. Verify real joins, spawn, interaction, driving, combat, reconnect and download behavior on each supported version. |

open.mp explicitly supports SA-MP 0.3.7 and0.3.DL compatibility. Its server has a
published legacy-network component and separate network/RakNet repositories,
which are useful primary technical references. The inspected `open.mp-network`
repository publishes an MIT license and requires the open.mp SDK; its network
classes are not a complete iOS client. The legacy server component carries
MPL2.0 notices. Each dependency needs its own license review before code is
imported; no external networking code is imported in this release. This is server-side evidence,
not a ready-made Swift/iOS client or proof our client can connect.

The linked RakNet fork has its own legacy license notice; its inspected files
do not establish that the network definitions' MIT license covers the transport.
Transport reuse permission remains unresolved. Do not assume all repositories
in the same organization share one license.

Sources:

- [open.mp compatibility release](https://open.mp/blog/server-beta-9)
- [Current network/custom-model configuration](https://open.mp/docs/server/config.json)
- [Legacy-network component](https://github.com/openmultiplayer/open.mp/tree/72bf89ce4c8164f7f7b8271ffc7323bc45ea005f/Server/Components/LegacyNetwork)
- [open.mp network definitions](https://github.com/openmultiplayer/open.mp-network) and [inspected MIT license](https://github.com/openmultiplayer/open.mp-network/blob/f223fbd90e414f6c35f1d20cf916314ea5dcff6f/LICENSE.md)
- [open.mp RakNet fork](https://github.com/openmultiplayer/RakNet)

## ReSA as a reference

ReSA's official features page advertises an independent iOS-capable engine
with SA-MP 0.3.7/0.3.7-R5/0.3.DL-R1 and open.mp support. It also advertises
custom-model downloads, touch/gamepad support and CEF/voice integrations.
These are the project's claims; no ReSA build or interoperability has been
executed or verified in this audit.

The inspected official site, features, download page, terms and public Lua API
do not establish an engine-source redistribution license. No ReSA source or
binary has been imported into ZGTA SA. A downloadable IPA is not evidence of
permission to copy its implementation into this public AGPL project. Public
API/protocol documentation and legitimate behavior comparisons can inform an
independent implementation; any proposed code reuse first needs an identified
source repository and applicable license/permission.

- [ReSA features](https://resa-mp.com/features)
- [Official iOS download](https://resa-mp.com/download?platform=ios)
- [Public Lua API](https://resa-mp.com/al-loader/api-docs.md)
- [Terms](https://resa-mp.com/terms)

Recommendation: keep the independent server working and complete the current
core-gameplay fixes. Then pursue a separate native compatibility adapter,
starting with an owned open.mp server in legacy0.3.7 mode, expanding to DL and
extensions only after measured acceptance. ReSA can be an additional reference
without making our app depend on its service or replacing our source release.

## Original browser world as a native destination

This is an explicit target, not a supported connection claim. The original
browser client and our native client both name `/api/world/live`, but sharing
an endpoint path is not protocol acceptance. Current native hello processing
requires our independent inventory acknowledgement extension and connection
nonce. The archived browser handshake uses its own build/capability fields,
version checks and authentication flow. Preserve the strict independent-server
path while implementing a separately negotiated original-world adapter.

Required work includes legitimate original-site account/session handling,
versioned handshake and state/command support, original inventory and damage
semantics, and a distinct owner-local converted-asset origin/import path where
the original host does not supply the native sidecars. URLSession does not
inherit the separate Chrome profile's login simply because that browser is
signed in. Our server's guest-access policy does not change access rules on
the original service.

Acceptance requires a real authenticated native join, the correct player and
world state, visible interactions with a browser peer, movement/vehicle/combat
transitions and reconnect behavior. A single bounded guest WebSocket probe on 2026-11-16 successfully opened the
original endpoint and received a `login` message. It supplied no cookies and
sent no movement/gameplay actions. This establishes reachability and an
authentication requirement for that guest, not a native gameplay join. No
original-site native join has been verified in this pass. Core gameplay
correctness remains the prerequisite.
