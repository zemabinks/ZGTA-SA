# Core109: static gameplay loader transport

The actual Core107 installed-resource scene test passed its UI assertions in
188.744 seconds, but its external denial proxy recorded **seven non-probe
static resource requests**. That result remains a rendered-scene/UI test with
seven denied requests; it is not zero-request or resource-free acceptance.

The requests were the stock model and collision catalogs, camera metadata twice,
atmosphere metadata, water-wave metadata and regional environment metadata.
The four non-stock loaders used `URLSession.shared` directly; the stock metadata
loader used its separate bounded URLSession delegate. These paths bypassed the
persistent resolver even though most of their data was already installed.

## Transport changes

`NativeGameCamera`, `NativeAtmosphere`, `NativeWaterWaves` and
`NativeRegionalWeather` now create their data tasks through
`NativeResourceTransport`. Their retained request type accepts the resolver's
cancellable task. Decoding, table validation, camera/gameplay algorithms and
completion scheduling are unchanged. Both normal and legacy camera instances
therefore use the same resource boundary.

`LegacyStockMetadataTransfer` first asks the existing bounded prepared-data
reader installed by `NativeResourceSession`. Verified local bytes complete the
transfer; an installed lookup error completes as failure. Only a development
cache miss returning nil reaches the existing HTTP implementation. Its byte
limits, streaming sink, redirect rejection, explicit first-party access-cookie
policy and dedicated ephemeral session remain unchanged.

The camera and stock-helper edits were coordinated with the camera owner and
avoid their observation, physics and camera-policy regions. Audio transports
and server-specific downloaded artwork are outside this change.

## Missing package coverage is separate

The canonical 6760-resource package, content ID
`f6c5c96913bbb076964bef55fb4134e8ddc0799f42f55c9a91cc1d4a29d6ee5e`,
contains camera, atmosphere, water-wave and environment metadata. It does **not**
contain `game/native/stock-models.json` or
`game/native/stock-collision/catalog.json`. The latter catalogs describe a
separate owner-local stock asset provider that the current producer does not
add to this prepared package.

Correct installed behavior for these absent catalogs is an explicit local
missing-resource failure. This patch does not invent stock content, silently
switch to development streaming or claim that stock object models/collisions
have become available offline. Adding complete stock metadata and its exact
referenced files to an independently validated package is separate work.

## Verification boundaries

`python3 test_native_resource_loaders.py` uses immutable copies of the actual
resource Store/Session and affected loader sources, plus the actual authored
stock metadata helper. All fixture bytes and metadata are authored synthetic
values. Its deliberately separate synthetic runtime-validator identity cannot
stand for the App's native geometry/animation/Metal verifier. The stock error
type is only a test-target type adapter; no stock model parser is replaced.

The test checks real loader completion through installed reads, both camera
instances, installed stock metadata, missing stock catalog failure, reader byte
limits, unchanged gameplay API networking, development cache-miss streaming and
corrupt installed data staying local. Its network path is an injected
URLProtocol, not a running HTTP service. Private reports record the executed
check count, exact source hashes and any source invalidation.

No original game fixtures, installed App data, Simulator or phone is read by the
regression. No Core107/Core108 source, frozen build or running service changes.
A future actual Core109 denial run with full scene review and real proxy counts
is still required; passing offline tests cannot replace it.
