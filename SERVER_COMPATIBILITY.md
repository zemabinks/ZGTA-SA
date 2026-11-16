# Existing SA-MP, open.mp and original browser servers

Core104 continues the physical-device and asset-identity acceptance. It is an independent Swift/Metal
client with separate adapters for our own HTTP/WebSocket server, legacy SA-MP
UDP, and the original browser world's versioned WebSocket protocol. Full server
playability and retail1:1 gameplay have not been established.

## Verified boundaries and remaining acceptance

| Boundary | Evidence | Remaining |
| --- | --- | --- |
| Independent server | Core103 composite149/149 regression acceptance and both optimized SDK builds; actual iPhone LAN join/walk/release and reciprocal static browser/native peer presence/leave | Overlapping peer motion, broader physical controls/performance and retail parity |
|0.3.7/DL profiles on official owned open.mp | Actual UDP join/class/spawn/chat, peer movement, key/axis/weapon states, freeze/spectator212, driver transitions, roster and respawn ownership | Standalone proprietary0.3.7/DL server binaries and full RPC/gameplay coverage |
| DL download/import | Actual official nonempty/empty catalogs, CRC32/size HTTP validation, nativeCPU decode and Metal upload precede184/185 then spawn; Core102 actual UIKit scene passed custom Army skin, legible material text, authored collision and driving/exit/spectator transitions | Physical iPhone scene and large-server acceptance |
| Runtime RenderWare | Owner584DFF/547TXD corpus audits, actual animated custom-ped GPU tests, object materials and authored COL physical contacts; Core103 four retail props pass the actual stock Renderer callback/HTTP/Metal/Rapier path | Complete stock/supplemental and animated-object coverage remains unverified; metadata availability is not render acceptance |
| Vehicle coordinate ownership | Core103212-model/full-quaternion calibration plus raw114 and catalog128 actual UDP checks; two profiles, observer conversion, final parking and respawn | New-session164 only carries heading; absent parked pitch/roll cannot be reconstructed until real rotation sync arrives |
| Server camera/control | Exact command fields/authority tests, actual owned server commands and83 pure camera checks | Integrated rendered following/interpolation/spec transitions; retail camera timings remain unverified |
| Legacy local damage |7714 actual math/network checks across037/DL, exact fractional server seeds, environmentalRPC115, cause53/54 deaths and real respawn cache restoration | Complete incoming combat, hitboxes, weapon/skill/range and server policies |
| Original browser world | Version/build-aware adapter, archived protocol and real local WebSocket regressions; current official Guest API implemented; Simulator guest form followed by a native scene and live53-player roster | Full movement, interactions, combat and live mission acceptance remain unverified |

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
namespace; browser aliases and retail IDs are not assumed interchangeable.
The Core103 owner archive provided265 mapped pedestrians. The later physical
browser/native comparison exposed incorrect browser-wire IDs in the exporter:
it had enumerated an animation/style list instead of the explicit model-ID
table. Core104 corrects that boundary. A canonical skin-table audit identified46
unresolved SA-MP IDs:11 null mappings plus35 IDs missing from the generated
catalog entirely. The ten story-character slots need SA-MP's explicit names
rather than retail special-slot placeholders. Thirty-three unresolved models
have exact retail DFF/TXD pairs available locally; availability is not native
conversion/registration. CJ needs its segmented player/clothing path, and the
additional300–311 models need their separately supplied resources. Missing
models are reported explicitly. Core104 separately converts and validates Maccer,
bringing the available count to266 and the canonical unresolved count to45.
The corrected266-model namespace has1148 Python,
532 actual server-row/browser-lookup and1067 extracted native-setter checks.
A separate actual NativeMultiplayerClient/backend WebSocket test passes32
bidirectional foot/driver cases. A real Metal four-model test including Maccer
passes30 animated draws. Fresh actual browser/iPhone scenes now agree on s7
male01 and skin2 Maccer; overlapping recordings verify both directions of short
walking and release. These bounded LAN results do not establish every transition
or existing-server destination.
See [character identity evidence and texture limits](CORE_SKIN_IDENTITY_104.md).
The later normal Taxi trial exposed two additional confirmed differences:
native grey versus browser yellow/orange paint, and simultaneous parked/driven
bodies for the same vehicle. Vehicle parity is not accepted. Concurrent human
phone input prevents attributing the later gas/brake/exit sequence to the
scripted controls; stuck-input and broken-exit suspicions are withdrawn.
Authoritative interior changes
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
The native Guest form is independently verified. A later Simulator observation
shows the original world's native scene and53-player roster after the user's
guest attempt. This is admission/presentation evidence, not full gameplay
acceptance. XCTest initialization still timed out, but compatible
Apple-personalized developer support enabled physical screenshots and normal
visible controls. The owner's DE gameplay and our app's separate LAN scene were
captured; see `CORE_RETAIL_REFERENCE.md` and `CORE_NATIVE_DEVICE_104.md`.
Classic-retail parity and complete physical controls/performance remain open.

Remaining original-world gaps include complete live gameplay acceptance,
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
