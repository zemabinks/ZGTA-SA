# Existing SA-MP, open.mp and original browser servers

Core103 is under integrated acceptance. It is an independent Swift/Metal
client with separate adapters for our own HTTP/WebSocket server, legacy SA-MP
UDP, and the original browser world's versioned WebSocket protocol. Full server
playability and retail1:1 gameplay have not been established.

## Verified boundaries and remaining acceptance

| Boundary | Evidence | Remaining |
| --- | --- | --- |
| Independent server | Core100 public baseline; Core101 frozen123/123 regression gates, optimized Simulator/iPhone builds and actual native stock037/DL test scenes | Physical input/performance, rendered browser peer transitions and retail parity |
|0.3.7/DL profiles on official owned open.mp | Actual UDP join/class/spawn/chat, peer movement, key/axis/weapon states, freeze/spectator212, driver transitions, roster and respawn ownership | Standalone proprietary0.3.7/DL server binaries and full RPC/gameplay coverage |
| DL download/import | Actual official nonempty/empty catalogs, CRC32/size HTTP validation, nativeCPU decode and Metal upload precede184/185 then spawn; Core102 actual UIKit scene passed custom Army skin, legible material text, authored collision and driving/exit/spectator transitions | Physical iPhone scene and large-server acceptance |
| Runtime RenderWare | Owner584DFF/547TXD corpus audits, actual animated custom-ped GPU tests, object materials and authored COL physical contacts; Core103 four retail props pass the actual stock Renderer callback/HTTP/Metal/Rapier path | Complete stock/supplemental and animated-object coverage remains unverified; metadata availability is not render acceptance |
| Vehicle coordinate ownership | Core103212-model/full-quaternion calibration plus raw114 and catalog128 actual UDP checks; two profiles, observer conversion, final parking and respawn | New-session164 only carries heading; absent parked pitch/roll cannot be reconstructed until real rotation sync arrives |
| Server camera/control | Exact command fields/authority tests, actual owned server commands and83 pure camera checks | Integrated rendered following/interpolation/spec transitions; retail camera timings remain unverified |
| Legacy local damage |7714 actual math/network checks across037/DL, exact fractional server seeds, environmentalRPC115, cause53/54 deaths and real respawn cache restoration | Complete incoming combat, hitboxes, weapon/skill/range and server policies |
| Original browser world | Version/build-aware adapter, archived protocol and real local WebSocket regressions; current official Guest API implemented; native guest form verified in Simulator without loading the browser game | Actual app-owned Guest/Discord live gameplay remains unverified |

The QA server is official open.mp1.6.7.3218, nonannouncing and loopback-only.
Core101's accepted checkpoint is not a public release: Core102 corrects the
proven1m distinction between legacy CPed roots and native feet. Its native
contact margin is separately measured, not presented as retail parity.

Core102 integrates verified downloaded DFF/TXD with real native skinned/static
pipelines and actual existing animation tasks. Authored COL1/2/3 physical shapes
are separate from shadow faces and use body-attached kinematic geometry. Material
text uses native CoreText; exact Windows glyph metrics remain unverified.
The importer has a shared192MiB custom/stock GPU budget. Core103 protects active
references during bounded cache eviction; unlimited active models and large RP
server acceptance are not established. Stale downloads/imports cannot
complete a later connection generation.

Core103's owner-local IMG index provides18,108 exact DFF/TXD resources without
bulk extraction. Four ambiguous dictionary names and25 unsupported UV-animation
dictionary carriers remain explicit omissions. The stock COL catalog covers
all251 IMG collections and active explicit COL files. Original header IDs are
hints: exact IDE name/ID provenance selects the resource. A collision-free visual
is admitted only when complete inventory evidence proves there is no authored
COL for that exact stock manifest. No substitute collision box is invented.
These are format/inventory boundaries, not a claim that all assets or gameplay
have been tested. Original archives, indexes and converted files stay local.

## Native legacy implementation

The app exposes a real server-address/profile form, class selection, spawn,
chat/commands, weapon/health/interior commands, streamed players/vehicles,
on-foot and driver synchronization, dialogs, basic TextDraws and click replies.
The asset origin remains the owner's prepared Mac server. It is distinct from
the selected UDP gameplay destination. See [HOSTING.md](HOSTING.md) for required
skin and weapon sidecars and [NATIVE_BUILD.md](NATIVE_BUILD.md) for Go/Rust/SDK
requirements.

Legacy skin IDs are mapped by original model names to the converted asset
namespace; they are not interchangeable numeric IDs. The current owner archive
provides265 mapped pedestrians and lacks11 referenced retail models, including
CJ. Missing models are reported explicitly. Authoritative interior changes
select interior streaming; a high outdoor aircraft position is not assumed to
be an interior solely because of its altitude.

The raw UDP bridge vendors only the pinned Apache2 transport from
[SA-MP Pilot](https://github.com/SA-MP-Android/SA-MP-Pilot), with its license and
provenance under `native-samp/`. Its independently authored C ABI has bounded
handles, queues, packets and asynchronous close. Host race tests, actual C ABI
links and iPhone/universal Simulator SDK links are separate gates. No ReSA code
or original website implementation is included in the public source.

Known incomplete areas include passenger/drive-by/incoming aim and bullet presentation,
complete combat damage and attribution, full server RPC/pickup/checkpoint coverage,
stock and supplemental object assets, sprite/model-preview TextDraws,
all server menus, client-specific anti-cheat/CEF/voice integrations, large-ammo
policies, IPv6/NAT64 and physical input/performance acceptance. Some servers
require their own launcher or extensions. The app does not fabricate PC memory
checks or claim compatibility with those extensions.

## Original browser world

The original adapter preserves its own binary snapshots/deltas, protocol/build
checks, client-owned weapons, fractional health/armour/effects, ordered staff
commands and explicit vehicle/death handoffs. Our independent server retains
strict inventory acknowledgements; they are not invented for the original
service or SA-MP. Local input/physics continue to run in the native engine.

The sign-in screen uses the original service's legitimate Guest-name or Discord
flow and an app-owned session. The native Guest form uses the current public
account API; Discord alone opens a web view. URLSession does not inherit a
separately signed-in Chrome profile. Guest restrictions and the service's build
and protocol checks remain authoritative. A successful Guest POST is followed by
account and build verification, with no automatic resubmission. The Metal
renderer continues to use converted owner-local assets from the Mac.

The earlier Simulator Discord page was blank after WebKit processes crashed.
The native Guest form is independently verified; that does not establish a
successful live connection. XCTest automation initialization on the installed
iPhone reference timed out before capture. Replacing older developer support
with compatible Apple-personalized support enabled a real CoreDevice screenshot
of its Definitive Edition menu. Gameplay measurements, classic-retail parity
and our app's physical controls/performance remain separate open gates.

Remaining original-world gaps include live authenticated acceptance,
server-specific UI/mission/extended-record mapping, remote projectile/effect
rendering, locally owned projectile explosions/detonation, some fighting styles
and complete hospital/arena/custom-map transitions. Controlled goldens establish
agreement with inspected browser expressions, not retail1:1 gameplay.

## Source references and reuse boundaries

open.mp publishes legacy-network and custom-model definitions suitable for
independent interoperability research. License review is per dependency:
open.mp-network's MIT notice does not license every linked RakNet repository.
The legacy server component carries MPL2.0 notices. No code from the separately
licensed open.mp RakNet fork has been imported into our transport.

- [open.mp compatibility release](https://open.mp/blog/server-beta-9)
- [Network and model-download configuration](https://open.mp/docs/server/config.json)
- [Legacy-network component](https://github.com/openmultiplayer/open.mp/tree/72bf89ce4c8164f7f7b8271ffc7323bc45ea005f/Server/Components/LegacyNetwork)
- [Network definitions and MIT license](https://github.com/openmultiplayer/open.mp-network/tree/f223fbd90e414f6c35f1d20cf916314ea5dcff6f)
- [RakNet fork and its separate notice](https://github.com/openmultiplayer/RakNet)

ReSA's official site advertises iOS,0.3.7/0.3.DL/open.mp, custom downloads,
controls and extensions. Those are its claims; no ReSA interoperability has
been executed here. Its inspected site/API/download/terms do not establish an
engine-source redistribution license. A downloadable IPA does not grant
permission to incorporate its implementation into this public AGPL project.
Public APIs and legitimate behavior comparisons can inform independent work.

- [ReSA features](https://resa-mp.com/features)
- [iOS download](https://resa-mp.com/download?platform=ios)
- [Public Lua API](https://resa-mp.com/al-loader/api-docs.md)
- [Terms](https://resa-mp.com/terms)
