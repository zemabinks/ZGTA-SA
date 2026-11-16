`serve_local.js` now reserves the stock-native namespace after its existing
Host, Origin and join-code checks. It delegates to `stock_native_assets.js`:

- `/game/native/stock-models.json`: configured complete virtual stock manifest.
- `/game/native/stock-img/<sha256>.dff|txd`: exact indexed IMG resources.
- `/game/native/stock-collision/catalog.json`: the runtime's schema2 COL catalog.
- `/game/native/stock-collision/index.json`: an exact-byte catalog alias.
- `/game/native/stock-collision/<sha256>.col`: catalog-listed authored records.

The helper never proxies these paths upstream or falls through to archived site
files. An unconfigured clean checkout returns 404, including in ordinary mirror
mode. Only GET/HEAD are supported. Query aliases, encoded/traversing paths,
partial ranges, unknown hashes and unlisted COL files cannot return a different
resource. Existing Cross-Origin security headers and access gates are preserved.

Set `ZGTA_STOCK_NATIVE_CONFIG` to an ignored JSON file inside `local-only`.
All configured paths resolve relative to that directory, with absolute owner
paths also supported for the explicitly selected archives:

```json
{
  "imgIndex": "research/stock-img/index.json",
  "stockManifest": "research/stock-img/stock-models.json",
  "archivePaths": {
    "gta3.img": "/path/to/owned/models/gta3.img",
    "gta_int.img": "/path/to/owned/models/gta_int.img"
  },
  "collisionRoot": "research/stock-collision-full/overlay"
}
```

The corresponding explicit overrides are `ZGTA_STOCK_IMG_INDEX`,
`ZGTA_STOCK_MODELS_MANIFEST`, `ZGTA_STOCK_IMG_ARCHIVES` (a JSON object), and
`ZGTA_STOCK_COLLISION_ROOT`. A supplied incomplete/invalid configuration fails
without substituting unrelated assets. IMG and COL preparation can be configured
independently. Configuration is loaded once after the first authorized stock
request; restart the server after changing it. This helper does not create or
modify game data, credentials, original archives or shared selfhost saves.

Configuration JSON is capped at 64KiB; native metadata is capped at 16MiB per
file. The existing IMG provider validates directory/range/hash provenance and
enforces its own 64MiB file and 128MiB resident reservations. The outer HTTP owner
allows two active and 16 pending requests, retaining slots through response
completion or its 30-second response deadline. COL files are bounded at 32MiB,
contained within the configured overlay, and checked for exact length, source
header name/ID/version, CRC32 and SHA-256 before a byte is served. COL completeness
metadata binds the exact stock manifest digest when both are configured.
Logical byte limits do not describe allocator/JSON-object overhead.

The caller must shut down the helper when closing its HTTP server. The
`serve_local.js` server-close hook does that. Existing join-code authentication
remains required for remote clients when enabled; a cookie-free native file
loader receives 401 until the application supplies a legitimate authenticated
transport. This integration does not bypass that gate or establish physical
iPhone gameplay, GPU registration, collision-world installation or parity.

Run `python3 test_stock_native_server.py` for actual HTTP regression. Every test
server uses a temporary copy of the independent server source, synthetic site
files and separate saves. Owned archives/full catalogs are only read. Twelve
owned resources are verified across the four common props. Generated COL cases
exercise corruption, truncation, sparse oversized files and symlink escape.
Tests cover clean-checkout no-fallback behavior, metadata bounds, configuration
errors, Host/Origin/join gates and exact route/method behavior. Existing server
8801 and the Core103 selfhost symlink are never used or changed. Reports remain
under `local-only/research/stock-native-server`.
