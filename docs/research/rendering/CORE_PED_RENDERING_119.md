# Ordinary character rendering and loading, Core119

## Material ownership and native pedestrian samplers (143)

World tiles now use a separate Metal material with additive day/night prelight;
static and animated model consumers keep their existing shading. Literal renderer
constructor/batch checks and actual offscreen authored pixels cover the split.
This matches the inspected archived-browser base-lighting rule, not a verified
retail PC lighting comparison. Sharp maps and full transparency policy remain open.

A strict original-sized Metal sampler comparison also reproduced a pre-existing
v2 atlas repeat-edge discrepancy on the Intel host. The production v2 path now
copies validated rectangles into original-size texture arrays, retaining the raw
UVs for hardware repeat sampling. Matching image dimensions share bounded array
slices; alternating group runs retain original triangle order. Body-part ranges
retain their own transforms and index offsets, including clipped runs. Static,
baked and skeletal vertex bindings remain independent of fragment metadata.

The independently authored GPU gate passes 6,157 checks over 7,155 offscreen
renders on Intel UHD Graphics 630. It checks the production shaders and actual
PNG uploads against isolated original-size hardware samplers, including the
repeat-edge input which failed before the fix. Existing ideal-arithmetic CPU
assertions remain on the explicit compatibility atlas algorithm; the strict
hardware comparison and its UV inputs/tolerance remain on production v2. The
legacy v1 path retains its prior behavior. Large integral Float UVs repeat at
zero; no new mip levels are generated.

Texture plans cap copied pixels at 512 KiB and 256 slices per group. Device-size
preflight and actual allocation accounting cap additional native resources at
2 MiB per model. Uploads precede draws on the same command queue without a CPU
wait. Queue, group, bounds, budget and malformed-part failures refuse publication
or clear the complete affected family for bounded retry. A source/generation
change cannot admit an obsolete upload. Failed bodies do not leave attachments.

Pure authored plan checks and literal renderer-owner tests separately cover
bounded runs, source changes, resource failures, all three vertex routes,
attachments and part-range delegation. `smoke_core_143.py --require-gpu` requires
the actual Metal gates locally; source-only CI reports unavailable hardware
honestly. Full-chain, SDK and normal Simulator results are recorded in the
release evidence after they run. Physical iPhone sampling/performance, original
retail animation/lighting, complete mip support and full-game fidelity remain
unverified. Original resources and comparison evidence remain local.


The ordinary-pedestrian renderer previously assumed that every texture occupied
a 128-pixel square. The optional `pedAtlasV1` resource family instead carries
validated pixel rectangles, so a 128×256 body image can retain its source detail.
Existing model-index maps and legacy resource paths retain their old meaning.
The producer and resource format are described in `docs/research/resources/CORE_PED_TEXTURES_119.md`.

The new fragment path uses the same lighting, fog, opacity, alpha-test and blend
policy as the existing ordinary actor path. Only its texture-coordinate mapping
changes. Static, baked-animation and skeletal vertex stages remain separate;
the rectangle buffer belongs to fragment index 2 and must never replace the
vertex-stage skin or bone palette at indices 2 and 3.

`tests/resources/smoke_native_ped_atlas_gpu.py` compiles the unmodified production World and
Skeletal Metal files, extracts the actual Uniforms layout and blend descriptor,
and renders independently authored PNGs through `MTKTextureLoader`. Its 1,320
checks/renders passed on the tested AMD Radeon Pro 555X host. They cover:

- Pixel equality with the existing 128-cell shader for its existing square atlas.
- 128×256 bodies, mixed content rectangles and a 1×1 white-only family.
- Negative/repeated UVs, rectangle borders and isolation from adjacent cells.
- Independent CPU bilinear, day/night, fog, texture/vertex/owner opacity and
  discard-threshold expectations, with a three-byte color tolerance.
- Identical complete images through static, interpolated packed-float3 positions
  and a nontrivial weighted two-bone skeletal palette.
- Rejection of invalid layer values and an unknown layout version.

The first fixture compile used an invalid SIMD initializer. That private failed
attempt was retained; correcting the fixture did not change application code.

The separately authorised local asset audit now covers all 266 ordinary models
and 290 referenced textures: 7,422 producer/pixel checks passed with no failures.
All 266 meshes, skeletons and parts files, and all 265 advertised hand files,
remain byte-identical to their prior prepared versions. The original-size atlas
set occupies 71.625 MiB of logical RGBA8 pixels, compared with the old fixed
133 MiB set; neither figure measures process residency or peak memory.

The held Swift family/layout parser separately passed all 266 families with
42,137 checks and unchanged source, executable and input files. That run checks
mesh/layout/source identities, PNG headers and advertised member hashes. It
does not decode all skeleton/hand/parts files or upload original textures to a
GPU. The independently authored Metal gate above provides a different scope.

This is a host GPU regression, not an iPhone performance or original-game visual
parity result. The existing linear/inset/fract/no-mip sampling remains deliberate
compatibility behavior; original RenderWare wrap/filter/mip behavior, physical
A14 memory/FPS, retail lighting and matched original animation still require
their own comparisons. All original and converted game resources stay local.

## Detailed-world high-resolution images (146)

The archived detailed-world mesh ends with a UInt16 plus-one image table: zero
keeps the base atlas, while positive entries select a separate 256px image.
The native parser previously skipped this table and the renderer never loaded
the corresponding HD resources. It now retains the table, admits only matching
bounded index/image profiles, and uploads each declared image to an individual
Metal array slice without resizing it. The shader keeps the existing world
lighting, fog and alpha behavior and falls back to the base image per layer.

Host world preparation converts available HD WebP files to exact RGBA8 PNGs.
Missing optional HD files preserve the required base-world installation. The
normal prepared-resource packager already includes PNG members; existing
installed packages remain usable without a bulk reimport. Their absent HD files
continue using base detail until the owner prepares and repairs those resources.

Only the active central detailed cell receives HD residency. Encoded reads are
capped at 64 MiB. A serial utility worker retains at most one active decode and
one replaceable pending image; cancelled/source-retired results cannot publish.
PNG dimensions are checked before decode. Each admitted texture array and its
map have a 96 MiB allocation cap, including generated mip levels. That cap is
not a total process-memory measurement: encoded images, staging textures,
in-flight render references and other engine resources consume additional RAM.
Upload completion waits only on the utility worker, never the render thread.

Focused authored evidence passes 46 layout/manifest/ownership checks, 162 actual
Metal assertions over 100 renders, and 89 existing material/batch assertions over
39 pixels. Pixel tests cover transparent RGB, all declared plus-one mappings,
negative/edge UVs, repeat filtering, generated minification, a standalone image
reference, budget/queue rejection, inline completion ownership and base fallback.
The first WebP fixture accidentally discarded invisible RGB before invoking the
producer; its failure is retained and the fixture now explicitly preserves it.

The complete selected Core146 chain passes with required Metal, physics,
audio and transport gates (742.1 seconds), with all 225 frozen app/build inputs
unchanged. Native-project, host and repository-layout checks also pass. A
separate owner-local native audit passes 1,113 checks over all 311 detailed
cells and 186 exact RGBA GPU image readbacks for the central exterior. Its
observed texture/map allocation is 73,928,704 bytes on Intel UHD 630. Original
archive files and served resources remain unchanged. SDK and normal installed
acceptance remain separate pending checks.

The owner archive declares 302 nonzero HD families across 311 detailed cells;
250 source files are present and 52 interior HD files are unavailable. This
resource path closes a demonstrated archived-client omission. It does not
establish full original-PC texture coverage, recover original TXD stored mips,
implement adjacent-cell HD residency or prove retail renderer fidelity. World
purple surfaces, complete transparent sorting/depth behavior, full lighting,
reflections, ambient AI and matched classic-retail comparisons remain open.
Full-chain, SDK, installed-scene and physical-device evidence are tracked
separately from these focused source tests.
