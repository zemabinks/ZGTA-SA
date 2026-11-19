# Native RenderWare pedestrian render regression

Run `python3 tests/resources/smoke_native_renderware_ped.py` on the owner development Mac.
The test compiles the unchanged, actual `NativeSkeletalActor` and its animation
dependencies. It reads local DFF/TXD/CLP1/SKN1 resources; all generated fixtures,
executables, logs, shader products and GPU readbacks stay in
`local-only/research/runtime-ped`. No game data is embedded or downloaded.

Some sandbox profiles hide the physical Metal device. That execution records
`gpu: unavailable`, which is not a GPU pass. After running the CPU/build driver,
run its concrete `local-only/research/runtime-ped/ped-tests` executable with two
arguments: the absolute project root and absolute research output directory,
using an execution environment permitted to access Metal. The executable writes
`report.json` and fails if any GPU, numerical, animation or draw check fails.

`NativeRenderWarePedModel.prepare(dff:txd:rigLimits:modelLimits:)` builds an
immutable plan. It reuses the static model's material, texture and sampler
resolution, then creates mesh attributes in the skeleton's first triangle-use
order, splitting `(sourceVertex, materialSlot)` pairs. Draw indices are grouped
by material without changing that shared mesh/SKN1 vertex order. Referenced
missing textures, missing UVs and incompatible rigs fail explicitly.

`Uploaded(plan:device:)` exposes the actual `actor` and uploaded material
`resources`. The caller obtains a real pose from that actor and an existing
animation library, then calls `encode(drawIndex:pose:encoder:pipelines:
viewProjection:worldTransform:overrides:)`. A pose is required; no generic actor
or unanimated fallback is substituted. The shader library must contain both
`NativeRenderWarePedModel.metal` and `NativeRenderWareModel.metal` functions.

The pose palette already supplies the actor's coordinate basis and bind
correction. `worldTransform` places that pose in the scene exactly once. Do not
apply the DFF atomic, skeleton axis or correction a second time. Mesh position
attributes retain raw source positions; posed bounds should come from the actor
or a deliberate skinning/bounds calculation, rather than those raw attributes.
The owner controls draw culling, transparent draw sorting and scene lighting.

The generated CPU cases check material splits, interleaved material buckets,
original UV sets, normals and prelit colours, texture deduplication, missing
resources, hidden atomics and split mesh/vertex budgets. The physical GPU cases
use bmori, army and wmopj plus an original generated rig, real CLP1 walking and
aiming, numerical position/normal probes sharing the exact vertex-stage helpers,
stock actor position comparisons and textured offscreen render readback.

Validated on the development Mac: 24 animated draws, 15,132 sampled vertices,
maximum position difference 3.4241e-7 metres, maximum normal difference 2.0006e-7,
and zero position difference from the existing stock actors. The exact sources
also pass arm64 iOS 15 SDK typechecking, iPhoneOS Metal compilation and metallib
linkage. These tests establish this resource/render bridge, not original-game
gameplay parity, arbitrary rig retargeting or in-world multiplayer integration.
