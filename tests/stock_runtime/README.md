# Native stock object runtime gate

`NativeWorldRenderer` loads bounded metadata from the asset server's standard
`game/native/stock-models.json` and `game/native/stock-collision/catalog.json` URLs.
The asset server may expose the exact DFF/TXD IMG ranges virtually; original files
and COL records remain owner-local. Metadata bootstrap rejects redirects, encoded
responses, excessive declared/received bytes and credential-bearing origins. An
explicit configured-origin policy may send only our app's own `zgta_access` LAN
join cookie on reserved stock paths; automatic cookies and credential storage stay
disabled. Local identity, original-site and Discord cookies are excluded.

Positive object/material references resolve exact owner IDE definitions. At most
two complete model pipelines share the existing verified DFF/TXD/raw-file loader.
DFF/TXD import, required textures, exact collision identity, integrity and actual
Metal upload must succeed before resources publish. Authored physical volumes are
registered by the existing fixed-step callback; their objects are not drawn until
those actual native handles exist. An explicit empty COL or verified complete
inventory absence gets a separate noncolliding classification and can render
without an invented shape. Incomplete metadata and failed downloads stay unready.

The existing 192MiB logical mesh/texture/collision resource budget is shared with
custom DL imports. Unreferenced stock resources can be evicted; referenced
resources remain protected. Unused cache entries are trimmed toward 128 slots when new resources arrive.
Active references can exceed that slot count while fitting the shared byte budget;
a server exceeding the active byte budget gets an explicit unavailable result. This is a cache budget, not a claim about total application resident memory
or frame rate. Stock and custom material namespace conflicts remain explicit.
The custom DL download/registration barrier is unchanged.

The stock runtime currently accepts supported static object and weapon definitions.
Timed objects, activity-specific animated objects, peds and vehicle object adapters
require their separate verified behavior and remain explicit unsupported kinds.
Raw availability of thousands of names is not proof of render/gameplay parity for
all assets. Breakability, special lamp effects, inherited LOD/timed collision and
all supplemental SA-MP model packs are separate acceptance work.

Run `python3 tests/network/test_samp_stock_runtime.py` where localhost fixture sockets and a
physical Metal device are available. The test compiles actual extracted Renderer
methods, with real metadata/asset HTTP, shared bounded loader, RW parsers, Metal
upload/draw and Rapier collision. Its carrier supplies the device/render formats
and resolves real object-store transforms without external vehicle/player parents.
It invokes the physical callback explicitly; it does not claim UIKit, display-link
or SA-MP session acceptance. Generated fixtures are authored here. Four retail
DFF/TXD/COL pairs are optional owner-local prerequisites for this focused gate and
are never bundled into public source.

Checks include real unauthenticated HTTP 401 responses and successful gated
bootstrap/model/COL delivery with only the own access cookie, while identity and
unrelated cookies exist in the test jar. The join cookie has no Port attribute,
matching the application's real join response. Other checks cover
metadata bounds/redirects/encoding/cancellation, exact retail asset
publication, corruption and incomplete inventory, authored versus absent/empty
collision, full-basis contacts, raw surface tags, movement/support velocity,
reference-protected eviction, namespace conflicts and stale-generation cancellation.
The 192MiB pressure test controls accounting entries without allocating dummy GPU
textures. Source and original-file hashes are checked before/after the run.

GPU-written render targets are read through an explicit texture-to-shared-buffer
blit with 256-byte-aligned rows. A diagnostic on AMD Radeon Pro 555X showed direct
`texture.getBytes` returning zero CPU-mapped pixels while that GPU copy exactly
matched the expected rendered RGBA. Earlier Intel UHD630 runs did not expose that
stale mapping. Pixel/animation assertions remain unchanged; this readback fix is
not a game performance measurement or a shader change. Diagnostic artifacts stay
under `local-only/research/stock-runtime`.
