# Optional stock-object prepared packages

The existing visual package can render the city and characters while omitting the separate stock-object catalogues and assets. In installed mode, a missing stock resource fails locally; it must not fall back to the Mac's HTTP resources. A verified visual package therefore does not establish stock-object coverage.

`tools/assets/prepare_native_resource_package.py` now has an explicit extension path. Its ordinary invocation and the existing prepared profile stay compatible. The extension reads a trusted private base catalogue and an explicitly configured stock source, verifies the selected dependency closure, and creates a new regular private catalogue. It does not scan a linked site directory or convert models.

```sh
python3 tools/assets/prepare_native_resource_package.py \
  --local-only /private/new-package-output \
  --base-catalog /private/existing-package/resources-v1/catalog.json \
  --stock-config /private/stock-native-assets.json \
  --include-stock-model 1238
```

Repeat `--include-stock-model` to select more IDs. When extending an already extended catalogue, its previously selected IDs remain included. `--all-supported` explicitly selects all available `object`/`weapon` metadata candidates. The default limits remain 64 models and 128 MiB of new logical resources, including the generated metadata; larger limits require explicit `--stock-max-models` and `--stock-max-bytes`. Unavailable assets, unsupported kinds and missing or ambiguous collision bindings are reported separately in all-supported mode. Metadata availability does not prove that every candidate is supported by the native format decoder, GPU or collision engine.

The private stock configuration names `stockManifest`, `imgIndex`, `archivePaths` and `collisionRoot`. Optional `explicitCOLPaths` permits only explicitly mapped external collision sources with matching whole-file coverage proofs. These configurations and absolute source mappings stay private. The package contains the reduced stock-model catalogue, its exact DFF/TXD dictionaries and inherited dictionaries, and its corresponding collision catalogue and records. It contains no accounts, access tokens or source configuration files.

Optional `explicitRWPaths` maps an exact standalone TXD logical path to an explicitly owned source file. The original path must already be a required resource in the base manifest with matching size and SHA-256, and exactly one stock asset must name it. The source is read through a retained regular descriptor, with bounded reads, cancellation, stable file stamps, exact size/SHA-256/CRC32 and one complete declared TXD root. Missing mappings remain unresolved in all-supported mode; wrong, missing or changing configured files fail the transaction. Standalone mappings cannot override an IMG candidate or select an ambiguous dictionary.

Only the generated subset's asset URL is normalized to its existing stock-img hash namespace. Its bytes/hash/CRC stay unchanged, the base visual logical row stays intact, and the already-required base blob is reused without copying or changing it. The private receipt preserves the original metadata and explicit source mapping. No source roots are inferred or approved by this operation. Native installed-resource and development-cookie policies remain unchanged; direct development HTTP serving of a standalone alias is a separate server capability, not created by packaging it.

The producer checks canonical base manifest identity and required core resources, exact stock/COL catalogue binding, unique IMG basenames and validated ranges, declared RenderWare lengths, sector padding, sizes, SHA-256 and CRC32. Collision records must match their headers and exact original collection boundaries. Nonregular source descriptors are rejected before opening; retained descriptors and file stamps detect replacement or mutation. Child resource symlinks, ambiguous paths and unexpected configuration fields fail closed.

Old visual rows and physical mappings are reused unchanged. Their bulk payloads are not rehashed merely to add a small stock dependency set; the resulting receipt states that boundary. Selected stock bytes, including reused blobs, are verified. Native installation still verifies all payloads before activation through the existing runtime validator. The extension does not grant playable status or change native installed-mode policy.

New payloads are staged under the new output directory. Cancellation and caught errors preserve existing catalogue metadata; late metadata failures restore the previous local and optional portable manifests. A single nonblocking output lock prevents concurrent extension writers. This is process-level rollback, not a multi-file power-loss transaction. Unreferenced immutable portable blobs can remain after an interrupted export.

`--export /private/portable-output` additionally creates a portable package and verifies every copied or reused portable blob, including the old visual payloads. It can therefore read the full visual package. Without `--export`, the new private catalogue references existing visual files. A development server must explicitly approve those existing source roots using its existing private root configuration; the extension does not infer approvals from resource mappings.

Run the authored regression without a compiler, network listener or game assets:

```sh
python3 tests/resources/test_native_stock_package.py
```

Its synthetic tests exercise the real producer, canonical manifests, IMG ranges, texture inheritance, collision provenance, reuse, cancellation, error rollback, budgets and rejection paths. Native stock-object GPU/collision registration and a normally joined installed-package scene remain separate acceptance steps.

The selected1238 extension also passed a normal Game Files cache/repair in
the preserved Core116 Simulator app, whose installed-resource path is unchanged.
It retained installed mode and activated6,778 resources, fetching the five new
blobs. Normal official open.mp join, CJ Spawn and a small touch-camera orbit
show the textured cone in the actual native scene. No cache seeding, pose or
camera-state assignment was used. The combined Core117 source subsequently
passed full iPhone Release and universal Simulator Debug builds. Its normal
installed-package official-server join, CJ Spawn, Pause/Resume and small
touch-camera orbit also pass, with a full scene capture showing the same cone.
A direct walking/contact trial, other stock models and physical-device
acceptance remain separate; this bounded result does not establish all-stock
or retail parity. The standalone mapping extension passes32 authored producer
cases, including descriptor replacement/mutation and exact base-blob reuse.
