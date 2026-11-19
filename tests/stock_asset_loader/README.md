`NativeSAMPStockAssetLoader` consumes an already decoded, exact
`NativeSAMPStockModels.Resolution`. It never discovers a replacement model or
dictionary. Public operations and completion handlers run on the main queue:

```swift
let loader = try NativeSAMPStockAssetLoader(assetBaseURL: assetRoot)
let request = loader.load(resolution) { result in
    // A successful result has verified CPU resources. The caller must actually
    // upload/register them and reject stale connection generations before use.
}
loader.cancel(request)
loader.reset()
```

`loadFile(_:completion:)` accepts the same `NativeSAMPStockModels.File` metadata
and uses the identical verifier, pending/concurrency budgets and generation
owner. It returns `BlobData(requestID, generation, file, data)` without choosing
a format decoder. To acquire an external collision catalog entry, copy its
`path`, `bytes`, `crc32`, `sha256` and URL into `StockModels.Asset`/`File`, then
pass the returned bytes to `NativeSAMPStockCollisionCatalog.prepare(_:for:)`
with the original catalog entry. File verification alone does not establish
COL model-name/ID identity or physical registration. Raw and model operations
share cancellation/reset rather than creating a second network engine.

`accessProvider` is optional and defaults to nil. An explicit provider may
snapshot only the current own app session's `zgta_access` through
`NativeStockAssetAccess`. Its exact-origin/path/expiry policy adds that one
manual header for permitted stock URLs. Session cookie handling/storage and
credential storage stay disabled, and redirects remain rejected. See
`tests/stock_asset_access/README.md` for the narrow first-party contract.

`Prepared` carries the request UUID, loader generation, exact model metadata,
decoded DFF, merged texture dictionary, static `NativeRenderWareModel.Plan`, and
fully parsed authored embedded collision models. An empty collision list means
there was no embedded collision. External retail COL association is a separate
exact-name operation. The loader neither uploads Metal resources nor registers
collision volumes, and never treats render triangles as authored collision.

Only object, timed-object and weapon metadata enter this static loader. Ped,
vehicle, animated and hierarchy kinds explicitly require another importer.
Skinned geometry, multiple morph targets, malformed resources, absent files,
unresolved material names and empty render plans fail rather than returning a
placeholder. Plan diagnostics such as an omitted empty source mip remain
available to the caller; no texture pixels or mip levels are invented.

Files are read serially within each job, using bounded URLSession data-delegate
blocks. Every block is size-checked before append; actual complete length,
CRC32 and SHA-256 must match the manifest before any decoder receives the bytes.
HTTP requires status 200, an exact expected response URL, identity content
encoding and matching Content-Length when supplied. Missing Content-Length
never disables the actual body bound. Redirects and HTTP authentication are
rejected. Each transfer uses a dedicated ephemeral session with no cookie store,
credential store or URL cache. Remote URLs must equal the configured base plus
the manifest's validated path, including the same origin. No ambient browser
login, credentials or cookies are used.

Local files require `allowLocalFiles: true`, primarily for controlled offline
tests. Resolved paths must remain within the configured file base, including
symlink resolution. All local bytes undergo the same streaming verification.
Retail assets and generated manifests remain ignored under `local-only`.

Texture dictionaries are consumed only in `Resolution.textureSearch` order.
The first exact case-insensitive RW texture name wins; a duplicate parent cannot
replace a child's pixels. File identity must match the declared dictionary
chain. Limits cover pending/running jobs, per-model files and encoded bytes,
all decoded textures (including discarded parent duplicates), total prepared
mesh and texture bytes, and decoder vertex/triangle counts. These are resource
and data bounds, not a claim that allocator overhead equals logical byte counts.
At most the configured number of jobs can retain CPU work/results inside the
loader; callers own the lifetime of completed results.

Reset increments the generation and cancels pending/running work. Cancelled
workers keep their concurrency slot until they actually exit, so repeated reset
does not multiply simultaneous decoders. A late result from an old generation
is delivered as cancellation. Callers must also check their own connection/world
generation before asynchronous GPU registration. Stock asset loading is
independent of the custom downloaded-artwork RPC184/185 readiness barrier.

Run `python3 tests/network/test_samp_stock_asset_loader.py`. The suite starts a real loopback
HTTP server and exercises independently generated valid textured RW resources,
child/parent precedence, byte/hash/CRC corruption, chunked overruns/truncation,
headers, redirects, timeouts, URL/path containment, unsupported/missing models,
decoder failures, bounded queues, cancellation and reset. It also prepares four
exact owner-local retail props extracted separately from owned IMG archives.
No GPU success is inferred from these CPU tests. Logs, requests and report stay
under `local-only/research/stock-asset-loader`.
