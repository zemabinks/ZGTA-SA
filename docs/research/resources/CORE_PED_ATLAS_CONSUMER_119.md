# Versioned ordinary-pedestrian atlas consumer

Core119 can load an explicitly advertised pedestrian atlas without resizing each
source image into the legacy128×128 cells. It keeps the ordinary WRL2/SKN1,
pose ownership, transforms, lighting, fog, blending and alpha path. It does not
switch stock pedestrians to the raw-ped/CJ shader.

The existing `models/index.json` remains `[String:[String:String]]`. An optional
`pedAtlasV1` map associates model names with immutable family URLs:

```
game/native/models/ped-atlas-v1/<manifestSHA256>/<model>.json
```

Clients without this consumer retain the existing maps and files. A model only
uses the new path when advertised. Its schema1 `zgta-ped-atlas-family-v1`
manifest pins mesh, PNG, layout and skeleton, plus hand/parts when advertised.
Every member uses its SHA256 directory and role suffix. The family source ID
is the SHA256 of compact sorted-key JSON containing `model`,
`sourceDFFSHA256` and `sourceTXDSHA256` (explicit null when absent). That ID is
checked against the validated layout. These pins bind the generated family;
they do not independently authenticate a retail release.

An invalid, missing or changed advertised member cannot fall back to the old
scalar-cell shader. Required bytes, layout and source are validated before the
mesh, actor and rectangle buffer publish together. Optional means unadvertised;
an advertised malformed hand/parts file fails admission.

The new fragment maps each layer through its content rectangle using the
existing half-texel inset, `fract`, linear filtering and no mip filtering. One
fragment-stage buffer2 holds dimensions/count/version plus rectangles. Vertex
skin2/palette3, static vertices and baked animation remain unchanged. Both
ordinary fragments share the previous lighting/fog/alpha arithmetic; no new
material tint or second opacity multiplication is added. World, vehicle,
weapon, accessory, raw custom-ped and fixed-CJ routes retain their existing
appearance paths.

`NativePedAtlasLoader` owns suspended bounded transfers. It reserves ownership
before factories can complete, cancels obsolete underlying tasks and fences
completion/publication by request, family and resource source. Its operational
limits are2 active families,4 transfers,32 request descriptors,16MiB per-family
encoded members and24MiB aggregate encoded reservations. Manifest reads are
capped at64KiB and individual members at8MiB. Completed payloads retain their
reservation until consumed or closed, so a stalled main queue cannot create an
unbounded completed-data queue. These are resource policies, not retail
constants. They exclude Foundation/kernel buffers, parsed geometry, Metal
allocations and allocator overhead; they are not an A14 peak-RAM guarantee.

The layout validates content rectangles, dimensions, layers, hashes and a512KiB
logical RGBA8 cap per model. The existing visibility cleanup is still a soft
count-triggered cache policy, not a hard32-model or global GPU-byte limit.

A resource generation change while a game is running retires upgraded families
and cancels their requests. The old catalogue remains fenced until a normal
rejoin/catalogue reload. Game Files import/mode changes use the main GAME menu;
there is no automatic partial skin-map adoption inside a running session.

## Verification

```sh
python3 tests/resources/smoke_native_ped_atlas_layout.py
python3 tests/resources/smoke_native_ped_atlas_loader.py
python3 tests/resources/smoke_native_ped_atlas_dispatch.py
python3 tests/resources/smoke_native_ped_atlas_gpu.py
```

The focused source freeze passes:

- 661 real layout/family parser checks with authored complete resource bytes,
  including schema/hash/source identity, invalid rectangles,1×1 white,
  nonzero Data indices and old index compatibility.
- 50 loader checks:25 deterministic transfer/ownership cases plus actual bounded
  URLSession requests to a disposable authored loopback HTTP peer. They cover
  held-payload budgets, queue bounds, inline completion, cancellation/deinit,
  corrupted/oversized bodies, real socket abort and a fresh request without
  replay. The installed resolver's separate transport regression passes138
  checks plus six HTTP isolation checks and20 existing loader checks.
- 32 literal Renderer resource/draw checks, including the real SKN parser,
  atomic failure, old callback/source/family replacement, source-away/back
  during admission and distinct same-model pose uploads. Image/GPU storage and
  animation sampling are explicitly spied in this gate.
- 1,320 actual offscreen Metal draws/checks on the host AMD GPU, using the real
  PNG loader, Uniforms/blend state and production static/baked/two-bone shader
  stages. Independent sampling/shading expectations, legacy128 equality,
  rectangular/mixed content, UV wrap, alpha and the old scalar negative pass.

The producer separately verifies its authored conversion fixtures and approved
owner-derived exports. A private re-execution of the binary/source-verified
Swift parser accepted the initial three immutable families with516 checks and
all20 input-file hashes unchanged. That check only reads container/header/hash
information; it does not decode original PNG pixels, seed an App cache or prove
main-game rendering. Normal prepared-package import remains mandatory.

No phone, Simulator, live game, account, pose or skin state was manipulated by
these focused consumer gates. Full SDK and normal installed-scene acceptance
are separate Root-owned stages. This change restores stored image detail; it
does not establish1:1 retail rendering. The preserved inset repeat seams and
all-linear/no-mip policy differ from independent repeat filtering and certain
original material headers. Altering that policy requires separate evidence and
an explicit sampling-family version.
