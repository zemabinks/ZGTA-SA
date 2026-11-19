`NativeSAMPArtworkSession` joins the existing DL wire/cache helper to an actual
asynchronous native importer. It does not change `NativeSAMPArtworkCache`, touch
the application Renderer, or treat downloaded bytes as rendered models.

All entry points and callbacks use the main dispatch queue. Construct with one
cache owner, `sendRPC: (Artwork.RPC) -> Bool`, and
`importer: (Model, dffURL, txdURL, completion) -> Void`. The importer must finish
real decoding/upload/registration before reporting success. It should capture
`session.generation` when invoked and check it again before committing GPU state;
the session ignores retired completions but cannot undo an importer's side effects.

Call `reset()` for a new connection and bind the returned `connectionGeneration`
to transport callbacks through `receive(id:data:connection:)`. `onWorld` updates
the application's current virtual world. `onReset` clears connection/catalog
registrations on true reset, cancellation or replacement; ordinary world changes
preserve the cache and need not evict resident GPU assets. `onGenerationChanged`
can invalidate pending registrations. `onStatus` exposes counts, deadlines and
failures; `onReady` fires only after the current server acknowledgement.

The session waits for a complete catalog and a real virtual-world boundary. Every
required pair is verified by the existing CRC/size cache and every model must
complete its importer callback before RPC184 is sent. Requests, downloads, imports,
catalog size, aggregate required bytes and deadlines are bounded. Duplicate and
retired callbacks cannot finish a later generation. Catalog growth retains prior
records with updated count semantics; a conflicting pool-zero replacement starts
a new catalog. Cache files remain on disk and are revalidated when reused.

Official ordering was checked in
[open.mp models.cpp](https://github.com/openmultiplayer/open.mp/blob/master/Server/Components/CustomModels/models.cpp)
(`onPlayerClientInit`, checked source SHA-256
`c16ceca925ed6c07df4bf8cd70d1840c2319aeaa7f9661c12563015a9fc46fe2`)
and [custommodels.hpp](https://github.com/openmultiplayer/open.mp/blob/master/Shared/NetCode/custommodels.hpp)
(SHA-256 `6af3ad492b1b19f7552a9c0ec5b3c109653fe7289cae02d69890e56fe3f654aa`).
The server sends catalog179 before two ordered world48 messages (world+1, world),
including when there are zero models. Zero catalogs have no invented179 marker.
Work is deferred to the next queue turn to coalesce a transport poll batch, with
no wall-clock quiet-period guess. An outstanding184/185 transaction is serialized
across world changes because185 has no generation identifier. Caller-side batch
draining can explicitly invoke `advance()` if desired.

Run `python3 tests/network/test_samp_artwork_session.py` for real localhost HTTP/cache tests with
independently generated, valid textured RW files and the production CPU importer.
They hold actual import completions to verify the184 barrier, reject a real
unsupported skin import, and cover duplicate/stale completions, reconnects,
catalog growth/replacement, empty catalogs, limits, transfer failures and deadlines.
The cache's default cookie-free requests and SAMP user agent are checked.

`python3 tests/network/test_samp_artwork_session_server.py` additionally requires the existing
local QA Docker image and native transport library. It creates separate disposable
localhost UDP/TCP7793 servers for a textured model and an empty catalog. The model
case performs actual DL join/catalog/HTTP verification, native CPU decode plus
Metal GPU registration,184/185 acknowledgement and stock spawning. It never
publishes original assets or contacts production servers. Successful standalone
tests do not establish application scene integration or multiplayer visual parity.

Reports, generated fixtures, cache files, logs and temporary server contexts stay
under `local-only/research/artwork-session`. Some sandbox profiles deny localhost
listeners or physical Metal devices; authorized execution outside that sandbox is
needed for these integration tests. No unrelated installation is performed.
