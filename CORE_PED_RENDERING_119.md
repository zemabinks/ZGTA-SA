# Ordinary character rendering and loading, Core119

The ordinary-pedestrian renderer previously assumed that every texture occupied
a 128-pixel square. The optional `pedAtlasV1` resource family instead carries
validated pixel rectangles, so a 128×256 body image can retain its source detail.
Existing model-index maps and legacy resource paths retain their old meaning.
The producer and resource format are described in `CORE_PED_TEXTURES_119.md`.

The new fragment path uses the same lighting, fog, opacity, alpha-test and blend
policy as the existing ordinary actor path. Only its texture-coordinate mapping
changes. Static, baked-animation and skeletal vertex stages remain separate;
the rectangle buffer belongs to fragment index 2 and must never replace the
vertex-stage skin or bone palette at indices 2 and 3.

`smoke_native_ped_atlas_gpu.py` compiles the unmodified production World and
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
