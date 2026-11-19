# Native-detail ordinary pedestrian textures

The optional `pedAtlasV1` family preserves the selected original texture's
native dimensions and decoded RGBA pixels. It uses the existing ordinary
pedestrian mesh, skeleton and pose path. The legacy converter remains the
default, and vehicles and weapons keep their existing atlas format.

This is a texture-detail change, not a claim of retail rendering parity. The
initial sampling contract deliberately retains inset/fract UVs, linear
filtering and no mip sampling. Repeat seams, material-specific filtering,
lighting, animation and measured device memory remain separate acceptance
questions. The older scalar-128 fragment cannot render the new sheets.

## Explicit source selection

`tools/assets/prepare_native_ped_atlas.py build` accepts a private JSON selection, not an
archive, network URL, directory discovery or app-cache location:

```json
{
  "schema": 1,
  "models": [{
    "model": "example_ped",
    "sources": {
      "dff": {"path": "/absolute/regular/example_ped.dff", "bytes": 123, "sha256": "<64 lowercase hex>"},
      "txd": {"path": "/absolute/regular/example_ped.txd", "bytes": 123, "sha256": "<64 lowercase hex>"},
      "mesh": {"path": "/absolute/regular/existing.bin", "bytes": 123, "sha256": "<64 lowercase hex>"},
      "skeleton": {"path": "/absolute/regular/existing.skel.bin", "bytes": 123, "sha256": "<64 lowercase hex>"}
    }
  }]
}
```

Select only files you are entitled to use. `parts` and `hand` may be explicitly
advertised with the same record shape; an advertised file is required. Omit
them only when absent from that selected source family. Segmented CJ (`null`)
is handled by its existing separate assembly and is rejected here.

Inputs must be bounded, absolute, regular paths without symlink components or
parent traversal. Specify the canonical existing source path explicitly rather
than a development alias. The producer checks size, SHA256 and stable file
metadata while reading; it never changes source-root approvals. It bounds
decoded source images before invoking the existing decoder. Named materials
must resolve from the selected own TXD; there is no unpinned vehicle-dictionary
fallback in this opt-in mode.

```sh
python3 tools/assets/prepare_native_ped_atlas.py build \
  --selection /private/local-only/selected-peds.json \
  --output /private/local-only/fresh-ped-overlay
```

The output must be fresh and under a regular `local-only` directory. The
producer stages selected conversions privately, rejects a regenerated mesh or
parts file that differs from the selected existing one, validates the SKN1
vertex pairing and any advertised parts/HND1, validates the complete family,
then renames the finished directory into place. It preserves the selected
mesh, skeleton, parts and hand bytes. It does not regenerate animation clips.

## Layout and immutable family contract

The new atlas keeps uniform rectangular cells sized to that model's largest
selected image. It allocates only enough columns/rows for its layers. A white
slot plus one 128×256 body therefore uses a 256×256 sheet. Smaller images in a
mixed dictionary retain their own content rectangle inside the common cell;
sampling the full cell would be incorrect.

The layout sidecar retains:

- `schema: 1`, `layout: "ped-tight-native-v1"`.
- `sampling: "legacy-inset-fract-linear-no-mips"`.
- `cell: [width,height]`, `columns`, `atlas: [width,height]`.
- `layers: [{slot,texture,rect:[x,y,width,height]}]`; slot zero is white.
- `logicalRGBA8Bytes`, `maximumRGBA8Bytes: 524288`.
- `meshSHA256`, `atlasSHA256`, `sourceDFFSHA256`, `sourceTXDSHA256`.

Per-layer UV mapping is:

```text
(contentOrigin + 0.5 + fract(uv) * (contentSize - 1)) / atlasSize
```

The half-texel inset avoids neighboring-cell samples at the base level. It
does not reproduce the cross-edge blend of a separately repeating texture.
Do not add global atlas mip generation without a verified gutter/mip policy.

The family descriptor has `schema: 1`,
`format: "zgta-ped-atlas-family-v1"`, `model`, `sourceIdentity`, and
`resources`. Required roles are `mesh`, `atlas`, `layout`, `skeleton`;
`parts` and `hand` are optional advertisements. Each role contains exact
`path`, `bytes`, `sha256`. Its logical path is:

```text
game/native/models/ped-atlas-v1/<resource SHA256>/<model><role suffix>
```

Role suffixes are `.bin`, `.png`, `.atlas.json`, `.skel.bin`, `.parts.json`,
and `.hand.bin`. The descriptor's own URL is
`game/native/models/ped-atlas-v1/<descriptor SHA256>/<model>.json`.
Hashing the actual descriptor bytes avoids a self-referential identity.

`sourceIdentity` is SHA256 of compact sorted-key ASCII/UTF8 JSON with **no**
trailing newline, exactly:

```text
{"model":...,"sourceDFFSHA256":...,"sourceTXDSHA256":...}
```

The TXD value is explicitly `null` if absent in a valid future layout; the
current selected-source builder requires its own TXD. Descriptor files use
compact sorted-key JSON plus a newline; their external hashes cover those
actual bytes.

The overlay contains `overlay.json`, private provenance, and only the complete
advertised resources under `files/`. Its model map becomes the optional
all-string `models/index.json` entry `pedAtlasV1: {model: familyURL}`. Existing
vehicle, ped-ID and weapon string maps remain unchanged, so older clients can
still parse `[String: [String: String]]` and use their original resources.

## Normal prepared-resource admission

The separate explicit extension takes a trusted existing private catalogue and
a validated overlay. It creates a **fresh** normal prepared catalogue; it does
not overwrite the input catalogue or an existing destination catalogue:

```sh
python3 tools/assets/prepare_native_ped_atlas.py extend \
  --base-catalog /explicit/trusted/local-only/resources-v1/catalog.json \
  --overlay /private/local-only/fresh-ped-overlay \
  --local-only /private/fresh-host/local-only
```

The destination `local-only` directory must already exist and be regular.
Only the selected complete graph and merged string-map index are written
under its normal `resources-v1/generated/ped-atlas-v1/` root. Existing base
resources keep their paths and hash mappings; every family dependency enters
the ordinary required manifest. The catalogue is committed after the generated
family. Content IDs follow the existing `zgta-prepared-v1` rules.

This command grants no extra source-root access. A development server must
still have its normal explicit approvals for old base blob locations. An
installed client must download/verify/import through its normal Game Files
workflow; no cache seeding, implicit source fallback or availability override
is performed. A generated catalogue does not itself prove that a particular
app has activated it or that direct development HTTP routes serve these new
logical paths.

## Verification and remaining acceptance

The portable authored test invokes the actual converter, family producer,
normal resource producer and prepared extension on synthetic DFF/TXD/SKN/HND
carriers. It checks native RGB/partial-alpha gradients and orientation, mixed
sizes, complete immutable identities, unchanged mesh/SKN/parts/hand, normal
manifest admission, source preservation, and fail-closed/atomic rejection.
It uses no original game data, services, SDK or devices:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tests/resources/test_native_ped_atlas.py
```

The optional `--historical-root /explicit/previous-checkout` also runs that
literal converter on the same authored carriers and compares legacy/nonped
binary, parts and PNG bytes. The report states `historicalExecuted` explicitly;
the default has no historical-checkout dependency.

For this development cycle, only the three explicitly approved original
`male01`, `maccer` and mixed-texture `wmyri` families were exported privately.
Their original source hashes match the prior owned IMG-range audit. An
independent BC1 RGB565 palette decoder and literal D3D21/22 BGRA channel mapping
verified the four original texture crops pixel-for-pixel, including orientation.
Mesh, SKN, parts and advertised hand files stayed byte-identical. This covers
these selected decoded pixels, not every source codec or the full catalogue.

Private dimension arithmetic for all 266 ordinary models gives 71.625 MiB of
tight RGBA pixels versus 133 MiB currently, with each proposed atlas at most
512 KiB. This is not measured physical memory or an A14 guarantee: the current
actor-count cleanup is not a hard byte cap. Actual Metal parsing/upload,
atomic scene publication, normal package import, animated near/far seams and
alpha, cache churn, A14 allocations and cold/warm timing still require the
separate consumer/device acceptance. No 1:1 visual claim follows from these
producer tests.

## Opaque D3D9 texture preparation

The preparation converter now discards the unused high byte of D3D format 22 when producing RGBA, matching the native decoder's existing BGRX behavior. Format 21 retains its original alpha. The [Microsoft D3DFORMAT reference](https://learn.microsoft.com/en-us/windows/win32/direct3d9/d3dformat) distinguishes these RGB and ARGB formats.

The authored opacity test covers every possible padding/alpha byte, RGB preservation, both prepared pedestrian-family versions and deterministic content-addressed output. The literal prior converter fails the X8 opacity assertion; the corrected path passes 523 checks. No owner game data is embedded in these fixtures.

```sh
python3 tests/resources/test_native_texture_opacity.py
python3 tests/resources/test_native_ped_atlas.py
```

This is a preparation-format correction, not evidence that an existing visible world defect was caused by X8 padding. Existing installed assets are retained; affected newly prepared families receive their normal content-addressed resource identities. Rendered appearance and complete original-resource coverage remain separate gates.
