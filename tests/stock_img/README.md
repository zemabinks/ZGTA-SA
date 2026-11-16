`prepare_native_stock_img.py` creates an owner-local VER2 IMG index and a separate
virtual stock-model manifest. It reads and hashes source ranges without bulk
extracting their files. Inputs are an existing schema1 stock metadata manifest
and explicitly selected owned PC archives:

```sh
python3 prepare_native_stock_img.py \
  --archive /path/to/owned/models/gta3.img \
  --archive /path/to/owned/models/gta_int.img \
  --manifest local-only/original-world-assets/game/native/stock-models.json \
  --index-output local-only/research/stock-img/index.json \
  --manifest-output local-only/research/stock-img/stock-models.json \
  --report-output local-only/research/stock-img/generation-report.json
```

Each unique DFF/TXD gets its exact archive range, declared logical RW size,
CRC32, SHA-256, allocation hash and explicit zero tail size. Logical extent is
the declared root container plus an optional complete DFF top-level extension.
Only a verified all-zero allocation tail shorter than a sector is excluded;
legitimate zeros inside a declared payload are retained. Unknown root types,
compressed ranges, out-of-bounds/overlapping tables and nonzero or oversized
padding never become guessed file bytes. Limits cover archive count/size,
directory entries, per-file size and output metadata size. Archive fingerprints
are checked again after indexing to detect concurrent source changes.

Case-insensitive duplicate basenames across archives remain ambiguous even if
their bytes happen to match. Their entries are omitted from the native asset
manifest. Invalid/unsupported source names also replace any older same-name
asset with an explicit absence; a similarly named dictionary is never chosen.
Other explicitly supplied non-IMG manifest assets remain available through
their original metadata paths. Exact model IDs and TXD parent rules come from
the existing IDE metadata, not inferred filenames.

`stock_img_assets.js` exports `StockIMGAssetProvider`:

```js
const { StockIMGAssetProvider } = require('./stock_img_assets');
const provider = await StockIMGAssetProvider.open({
  indexPath: privateIndexPath,
  archivePaths: { 'gta3.img': ownedGTA3Path, 'gta_int.img': ownedInteriorPath }
});
// Inside the existing async request handler:
if (await provider.handle(req, res)) return;
// Existing routes continue here. At shutdown: await provider.close().
```

The server must separately expose the generated virtual manifest at its existing
`game/native/stock-models.json` URL. The module only handles the index's virtual
prefix, by default `game/native/stock-img/<sha256>.dff|txd`. It does not modify
`serve_local`, bind a public socket or publish any assets. Archive pathnames
come only from explicit local configuration. Never place original archives,
generated metadata or caches in the public source release.

On open, the provider independently rechecks each actual IMG directory/hash,
range and duplicate-name decision. Before a response, bounded reads verify the
logical RW extent, zero tail, CRC32 and SHA-256. A changing archive fails instead
of serving a stale range. Immutable descriptor maps and exact hash-addressed
routes prevent URL traversal, arbitrary offsets and dictionary substitution.
Only GET/HEAD are accepted; unknown URLs, query aliases and partial ranges do
not return alternate assets. Concurrent jobs, pending work, resident byte
reservations and HTTP response lifetime are bounded. Cancellation and shutdown
release resources; reservations stay active until a response finishes/closes.
`withAsset(name, callback, {signal})` exposes the same verifier for controlled
consumers; any result or bytes deliberately retained by a caller become that
caller's responsibility. There is no unbounded model-byte cache.

The verified owned two-archive inventory contains 18,800 directory entries and
18,108 uniquely indexed DFF/TXD resources. It supplies complete file metadata
for 14,745 of 14,832 IDE definitions. The four ambiguous TXDs are `barrier`,
`changeme`, `kbmiscfrn1` and `lawest1`. Twenty-five DFFs start with RW chunk 43,
identified as `ID_UVANIMDICT` in [librw's primary enum reference](https://github.com/aap/librw/blob/master/src/rwbase.h).
The current clump-only native decoder and this provider explicitly exclude
those files. Their exclusion is a format/animation limitation, not evidence
that the source files are corrupt. No reference implementation is copied.

Run `python3 test_stock_img_assets.py`. Generated cases cover valid declared
payload zeros, complete extra extensions, directory corruption, allocation
bounds, duplicate names, source mutation, actual HTTP bytes/status, cancellation,
queue/resident budgets and shutdown. Eight owned ranges are checked against the
earlier isolated extraction hashes without writing any original payloads. The
generated and full owned virtual manifests are decoded by the actual frozen
Swift stock metadata helper. Reports remain under `local-only/research/stock-img`.
Metadata and verified file availability do not establish native import,
rendering, material effects, animation or collision parity.
