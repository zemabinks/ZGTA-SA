Run `python3 tests/resources/test_native_renderware_model.py` for generated CPU regressions and,
when accessible, native Metal offscreen readback. Add
`--owner-corpus local-only/site/game` for a read-only pass over local DFFs and
their same-name TXDs. Generated outputs and reports remain under
`local-only/research/runtime-model`; no game assets are embedded or downloaded.

`NativeRenderWareModel.prepare(dff:txd:limits:)` returns an immutable CPU plan.
Referenced geometry is stored once; visible atomics refer to it with original
frame transforms. Non-render atomics are skipped. Rendered skin geometry is
explicitly unsupported here, pending the separate skeletal path. Positions,
winding, normals, prelit colors, original texture coordinate sets, material slots,
colors and alpha remain available. The base-texture shader uses UV set zero.

`Uploaded(plan:device:)` creates shared geometry buffers and separate original-size
RGBA textures with all stored, contiguous mip levels. Missing tiny tails are
reported and omitted; no mipmaps or atlases are fabricated. Named missing textures
produce diagnostics and a white fallback, so `plan.isComplete` remains false.
Untextured materials legitimately use white. Additional morph targets are reported
because this path only draws the first static target.

`Pipelines(device:library:color:depth:)` expects the checked-in Metal functions
`native_rw_model_vertex` and `native_rw_model_fragment`. `encode(drawIndex:...)`
lets the caller cull or sort individual draws, supply its explicit coordinate and
world transforms, and override visibility, attachment transform, tint and lighting.
Callers must sort blended geometry appropriately. This is a static mesh/material
loader, not a collision, vehicle, animation, or original-engine material pipeline.
Successful upload does not establish multiplayer or in-world rendering parity.

Limits bound aggregate unique vertices, indices, materials, instances, draw calls,
mesh bytes, and referenced texture bytes. Repeated atomics do not duplicate vertex
or texture data. Unsupported filter/address modes fail explicitly. Original RW
texture streams with V-address zero inherit U-address, as confirmed by
[librw texture.cpp](https://github.com/aap/librw/blob/master/src/texture.cpp), file
blob SHA `961649e0bc0568c663b730746a8be9fd28222aea` checked on 2026-11-16.
Filter and addressing bit fields follow
[librw rwobjects.h](https://github.com/aap/librw/blob/master/src/rwobjects.h), file
blob SHA `da95a5ca80004d354a03b6a82fe01189906cc1b1`. These are format references;
no librw implementation is included or linked.

The generated suite checks Swift/Metal vertex and uniform ABI offsets, index and
UV preservation, original full-size mip upload, empty-tail handling, missing-name
diagnostics, hidden/skinned atomics, 20 shared instances, each allocation budget,
and 96 filter/wrap configurations. On a Metal device it compiles the exact shader,
uploads and reads each mip, and compares a rendered 4×4 image byte-for-byte.
Some sandbox profiles hide physical Metal devices; that run reports `unavailable`
instead of claiming a GPU pass. A separately authorized execution outside that
sandbox can exercise the same compiled binary and shader without recompiling.
