# ZGTA:SA project status

**Snapshot date: 20 November 2026.** This page describes source and reported test evidence in the repository, **not** a guarantee of gameplay on every device. See the linked technical records for exact scope. New code may appear after this snapshot.

## At a glance

| Area | What the project has | What is not yet established |
| --- | --- | --- |
| **Native iOS client** | Swift/UIKit/Metal renderer, streaming, input, camera, physics, characters, vehicles, effects, audio and HUD; Xcode builds and selected rendered Simulator/device checks | Full GTA SA 1.0 US gameplay equivalence, all original content, stable performance on every iPhone |
| **Mac/browser development world** | Source-hosted local archive, independent Node server, guest accounts, shared lobby/gameplay systems | Complete feature equivalence with the original online service or a retail PC game |
| **iOS installed game resources** | Verified prepared resources can be imported or cached; installed mode reads static assets locally | Automatic full original-ISO-to-playable-native conversion and exhaustive resource coverage |
| **ISO** | Read-only ISO/InstallShield extraction of selected raw original resources, with retained checks | Native conversion of the extracted raw set and one-tap playable installation |
| **Browser ↔ native multiplayer** | Working connection and selected shared movement/vehicle/occupant tests; many incremental fixes | Full two-client vehicle/passenger/visual parity in all scenarios |
| **SA-MP/open.mp** | Separate experimental adapter with controlled legacy open.mp network/gameplay checks | Guaranteed compatibility with all SA-MP servers, extensions, modifications and content |
| **Original browser world's service** | Separate protocol/account integration; partial roster/scene verification | Full movement, combat, vehicles, missions and independent service interoperability |
| **Sandbox** | Many free-roam systems and simulation foundations | Complete original ambient traffic, pedestrians, police, world interactions and all behavior |
| **Public downloads** | Public source repository | No packaged public iPhone release in GitHub Releases |

## Latest verified implementation

Build 136 includes persisted resource-import corrections, owned/parked wheel-phase continuity, browser radio delivery and swimming-exit input/turn ownership fixes. Its source regressions, unsigned Simulator/device builds and selected normal Simulator import/join/walk/camera checks passed. Audio output, full hardware behavior and exhaustive original-retail parity remain unverified.

Repository cleanup is merged in [PR #3](https://github.com/zemabinks/ZGTA-SA/pull/3): 671 public files moved and the root reduced from 711 to 40 files. The full optional core chain, both SDK builds, source/history audit and corrected GitHub CI passed. Existing prepared resources were retained. The public launch commands remain available. See the [cleanup record](development/REPOSITORY-CLEANUP.md) for scope and validation.

Core 140 repairs independent-server breath lifetimes, stale HTTP breath-display writes and respawn oxygen clocks. Focused native/backend checks, the complete optional core chain and both SDK builds pass. A normal Simulator update retains prepared/raw resources and passes join, walking, camera and pause/resume checks. Real-time drowning and hardware acceptance remain unverified. [Breathing repair #4](https://github.com/zemabinks/ZGTA-SA/pull/4) is merged.

Resource preparation also preserves opaque X8 texture semantics while retaining A8 alpha, with authored decoder and prepared-family regression coverage. Existing installed game files remain intact.

A native original-navigation reader and explicit Game Files route checks now provide a pedestrian/vehicle data foundation. Authored raw-store/lease/menu lifecycle checks pass. Ambient traffic, pedestrian AI and original route-selection policy remain open. See [original navigation](research/resources/CORE_NATIVE_RAW_ISO_108.md#original-navigation-reader-142) for scope; build and normal UI results are tracked separately.

Core 143 separates world lighting from model shading and repairs a demonstrated native texture repeat-edge difference with bounded original-size Metal arrays. Authored GPU and resource-owner regressions pass; build and installed-game acceptance are tracked separately. This remains a scoped renderer repair, with retail fidelity and ambient AI still open. See the [rendering record](research/rendering/CORE_PED_RENDERING_119.md#material-ownership-and-native-pedestrian-samplers-143).

Core 144 adds typed legacy-server gravity to native force owners and fixes a demonstrated low-gravity airborne-bike rest condition. Source, real host physics and frame-rate regressions pass. Two native protocol profiles also agree with an owned open.mp server through per-player/global gravity and physical-sync checks; installed-build acceptance remains distinct. [Gravity evidence and limits](research/movement/CORE_PHYSICS_AUDIT.md#legacy-server-gravity-144) describe the supported scope.

Core 145 adds an explicit native-size vehicle texture family, hardware sampling and prepared-install admission. Authored GPU checks and all 212 owner-local family pixel/readback checks pass; complete installed-build acceptance remains separate. Existing server assets were preserved. [Texture scope and remaining differences](research/vehicles/CORE_VEHICLE_PAINT_105.md#native-size-vehicle-images-and-hardware-sampling-145) include generated-versus-stored mips and the unresolved world/material gaps.

Core 146 connects the archived world's previously unused high-resolution image table to optional native resources, bounded background loading and Metal sampling. Existing installed base resources remain usable. The full selected regression chain, both SDK builds and 311-cell resource/186-image GPU readback audit pass. A normal Simulator update retains installed resources and passes HD/base joins, walking, camera/pause, three jumps and mode restoration; physical-device and matched original-PC acceptance remain separate. The archive still lacks 52 declared interior HD files. See [resource scope and memory limits](research/rendering/CORE_PED_RENDERING_119.md#detailed-world-high-resolution-images-146); this is not full original-PC world or gameplay parity.

Core 147 separates detailed-world solid and clear surfaces, then sorts clear world cells with vehicle parts. It also repairs vehicle paint-data binding after switching shader types. Focused actual-Metal/owner regressions, all 311 owner-local cell partitions and the full selected Metal/physics/audio/transport chain pass with 226 app/build inputs held. Both SDK products and a normal retained-resource Simulator join/Taxi/camera/exit/jump/base-source scene also pass. The initial private resource-link packaging failure and separate zero-test runner rejection remain retained; hardware and retail acceptance remain separate. [Surface scope and remaining gaps](research/rendering/CORE_PED_RENDERING_119.md#world-surface-phases-and-mixed-vehicle-transparency-147) distinguish this archived-client repair from original-PC parity.

Core 148 repairs rider presentation time lost on slow displays and prevents new or repeatedly drawn rider/bike owners from borrowing elapsed time. Focused current/historical gates and the full selected Metal/physics/audio/transport chain pass with 226 app/build inputs held. Both SDK products, the actual archived direct-delta replays and normal retained-data Taxi/BMX cases subsequently pass. The owned server records 97 bicycle samples and 7.399 metres of movement. A separate normal installed148 third-person BMX case also passes, with the actual bike and rider visible and all camera preferences restored. Hardware and retail acceptance remain separate. [Timing scope and remaining differences](research/vehicles/CORE_VEHICLE_PRESENTATION_122.md#rider-presentation-intervals-148) preserve the distinction from original-PC accuracy.

Core 149 repairs stock-resource lifetimes when the asset origin or installed-resource generation changes, including old callbacks, physical collision retirement and shared custom-artwork texture bindings. Authored owner and actual HTTP/RW/Metal/Rapier transition gates pass, followed by the full selected Metal/physics/audio/transport chain with all 226 app/build inputs held. Both SDK products and a normal retained-data Simulator source-change/Taxi/camera/exit/jump case subsequently pass; metadata/settings remain retained and owned processes are stopped. Hardware, purple world surfaces and retail acceptance remain open. See the [source lifetime record](research/resources/CORE_STOCK_SOURCE_149.md).

Core 150 repairs original texture and material binding in the existing native CJ/custom-skin draw path. It also adds a verified, bounded stock-rig CPU importer, with authored and three-original-family resource/GPU-byte evidence. Ordinary raw-ped renderer registration remains separate. The full selected Metal/physics/audio/transport chain passes (851.1 seconds) with all227 App/build inputs held. Both SDK products and the normal installed CJ join/walk/camera/jump case subsequently pass; reviewed before/after captures confirm restored original textures. Resource metadata/settings are retained and owned QA processes are stopped. The separate zero-test Apple runner rejection remains recorded; hardware and retail 1:1 remain unverified. See the [character resource record](research/resources/CORE_STOCK_PEDESTRIANS_150.md).

Core 151 connects imported CJ/custom-skin draws to the existing native distance-fog environment, with explicit per-draw state isolation. Focused historical/current GPU gates and the full selected Metal/physics/audio/transport chain pass (854.5s), with227 App/build inputs held. Both SDK products and the normal retained-data join/walk/camera/jump/menu case subsequently pass; reviewed near-character captures retain original textures, objects and HUD. A separate zero-test Apple runner rejection remains retained, and owned QA processes are stopped. Distant fog values remain the focused GPU oracle's scope. This does not establish original pedestrian timecycle lighting or retail parity. See the [scene record](research/rendering/CORE_IMPORTED_CHARACTER_SCENE_151.md).

Core 152 connects original stock pedestrian resources to a bounded native resident owner with full rig/skin compatibility admission, actual GPU allocation accounting and source retirement. Focused gates and the full selected Metal/physics/audio/transport regression pass (945.95s), with229 App/build inputs held. Both SDK products and the normal retained-data three-skin join/walk/camera/Taxi/exit/jump/menu case subsequently pass. Actual original male01 drawing and reviewed captures establish scoped integration; seated-pose quality, hardware and retail acceptance remain separate. Original files/settings are retained and owned QA processes are stopped. Existing same-model fallback, missing raw/canonical identities and original lighting differences are explicit. See the [resource runtime record](research/resources/CORE_STOCK_PEDESTRIAN_RUNTIME_152.md).

Core 153 fences stale camera publications and city collision requests, including physical floor retirement on announced resource-source changes. Focused historical/current authored gates and the corrected full Metal/physics/audio/transport follow-up pass (976.53s), with 229 App/build inputs held. The earlier carrier compile rejection remains retained. Both SDK products and a normal retained-data Simulator three-skin/Taxi/camera-input/exit/jump/menu case pass. Nine reviewed captures show original character textures and the driver head/upper torso through the windshield; exact camera trajectory and full seated-pose quality remain unverified. Actual owned-server logs confirm class movement and driver entry/exit. Resources/settings hold and owned processes are stopped. [Scene resource scope](research/resources/CORE_SCENE_RESOURCE_LIFETIMES_153.md) separates these fixes from original camera timing and complete gameplay parity.


Core 154 moves streamed city collision spatial-index construction, SCL2 decoding and physical mesh grouping to a bounded serial worker, retaining main-thread physics registration and source/material-snapshot admission. Focused worker/renderer/owner gates pass49/41/32 checks, and225 matched original-cell CPU/physical query samples remain exact. Host Debug measurements show a substantial reduction in main-thread work, with residual physical registration cost; hardware frame times are unmeasured. The full selected Metal/physics/audio/transport chain passes (1015.34s), with230 App/build and17 captured test inputs held; project, host and layout gates also pass. Both SDK products subsequently pass (universal Simulator490.6s; arm64 iPhone Release510.3s), with230 product inputs and39 dependency files held. A normal retained-data Simulator case also passes through three streamed characters, Taxi/camera/exit/jump and installed CJ movement, with no installed CJ/collision HTTP fallback. Twelve reviewed captures and four actual owned-server joins establish scoped integration. Resources/settings are preserved and owned test services stop afterward; retail/hardware acceptance remains open. See the [streaming record](research/resources/CORE_SCENE_RESOURCE_LIFETIMES_153.md#bounded-city-collision-preparation-154).

Core156 fences obsolete typed scene metadata and parent/child publications.
Focused historical/current source and actual ground/Rapier checks pass, followed
by the complete selected source chain, both SDK builds and one normal retained-
data Simulator case. Twelve reviewed captures and owned-server logs cover
streamed7/2/0 and installed CJ0 movement, Taxi/camera/exit/jump/menu. Resources
and settings hold, installed base data require no HTTP fallback, and owned test
processes stop afterward. This remains request admission, not an atomic metadata
transaction or verified retail parity. See [scene ownership](research/resources/CORE_SCENE_RESOURCE_LIFETIMES_153.md#current-source-and-latest-metadata-admission-156).

## Where we're going

The project's priorities are **stable shared world state**, **accurate player and vehicle appearances**, **correct passengers/vehicle authority**, **complete original resources**, **authentic NPCs and traffic**, and **original free-roam gameplay fidelity**. Original campaign missions are explicitly not the target.

An SA-MP player, a ZGTA:SA browser player and an iOS player do **not** automatically share a world unless they connect to the same compatible server/destination. “Perfect crossplay” across all servers or extensions has **not** been demonstrated.

## How status is verified

We distinguish **written source**, **unit/fixture tests**, **successful builds**, **Simulator gameplay**, **physical iPhone testing**, and **real multiplayer gameplay**. A passing synthetic test does not turn an experimental feature into a finished product.

For detailed evidence and gaps, see:

- [Feature matrix](development/FEATURE_MATRIX.md)
- [Core gameplay checklist](development/CORE_GAMEPLAY_PARITY.md)
- [Development journal](development/CORE_GAMEPLAY_JOURNAL.md)
- [Original-game reference](development/CORE_RETAIL_REFERENCE.md)
- [Server compatibility](development/SERVER_COMPATIBILITY.md)
- [Raw ISO extraction](research/resources/CORE_NATIVE_RAW_ISO_108.md)
- [Persistent resource storage](research/resources/CORE_NATIVE_RESOURCES_107.md)

**When updating this page:** reflect the latest tested revision, mention the exact scenario/platform, and leave untested items marked as unverified. Do not list unfinished source features as publicly downloadable.

[← All guides](README.md)


Core155 prepares visual world cells on a bounded utility worker, prioritizes the
current detail and retires obsolete visual/collision intents. Focused74 Metal/
scheduling and50 collision checks pass. Three owner-local cells preserve full
GPU geometry, base pixels and metadata; all327 available base cells fit declared
bounds without downscaling. The selected source chain, both SDKs and payload
checks pass with inputs held. Normal retained-data Simulator acceptance passes (one executed case, zero
failures);12 captures and actual owned-server movement/entry/exit logs are
reviewed. Installed world/collision/CJ require no HTTP fallback, resources and
settings hold, and owned test services are stopped. Hardware, original-PC and
complete gameplay parity remain open. See
[visual streaming scope](research/resources/CORE_SCENE_RESOURCE_LIFETIMES_153.md#bounded-visual-world-preparation-155).

Core156 metadata admission and Core157 remote foot playback have completed
their selected source, both SDK and retained-data Simulator gates.157 also
passes a separate real open.mp session with one rendered native app and an
authored headless legacy peer: remote walking, pause/resume, local input and
disconnect. Original resources/settings remain held and owned services stop.
This is scoped multiplayer evidence, not a two-rendered-client/browser or
original-retail1:1 claim. See the
[remote motion record](research/gameplay/CORE_REMOTE_MOTION_157.md).
