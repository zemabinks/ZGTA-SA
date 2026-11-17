# Core108: persistent prepared-resource admission

`NativeResourceStore` now revokes prepared-installation admission when an ordinary
runtime data/file lookup observes a missing, unreadable, wrong-sized or
checksum-invalid **known** blob. Previously the lookup failed while the Store
continued to advertise a playable installation; a same-sized corrupt file could
also be admitted again by configuration or relaunch.

## Behavior

- Keep the active manifest, content ID, installed mode, receipt and good blobs.
  Remove the observed bad digest from verified cache accounting. Installed mode
  continues to fail closed; it does not start a download or switch to streaming.
- Persist an invalid-admission marker bound to the receipt's admission identity.
  Configuration, relaunch, or merely replacing bytes cannot clear that marker.
  Successful full byte/runtime verification or explicit successful repair
  publishes a fresh admission identity.
- Treat malformed, unreadable and dangling-symlink marker metadata as blocking.
  If the ordinary marker cannot be saved, use staging metadata, then a blocked
  receipt/quarantined receipt as persistence fallbacks. Admission also requires
  writable staging metadata. Verification may repair malformed app-owned marker
  storage, retaining an emergency block before it moves the old metadata.
- Preserve compatible v1 receipts with no admission UUID. Their prior native
  validation identity remains usable when no fault is known. They receive a
  fresh UUID after successful verification; no ISO reimport is required merely
  for this receipt addition.
- Bind fault reports to the captured in-memory admission generation, persisted
  receipt key, current entry and file identity. An old asynchronous read cannot
  invalidate a subsequently verified replacement or remove its accounting. A
  fault observed during verification prevents that pending verification from
  restoring admission; a later complete verification is required.
- Reject invalid URLs, unsupported query strings, unknown resource paths and
  reader budget violations without treating them as corruption. In development
  mode, only the explicitly bound source origin can inspect the local entry; a
  corrupt cached entry becomes a cache miss for that source and can be repaired
  by an explicit cache/import operation.

The Store's `Snapshot`/`Progress` shapes and existing operation APIs are unchanged.
New receipt fields are optional. The initializer adds an optional data-reader
dependency for deterministic regression timing; production uses actual file data
and the same required length/SHA-256 check. The dependency cannot bypass hashing.

## Verification

The actual Store passed **103 folder-only checks** using independently authored
resource bytes and an explicitly synthetic validation identity. They cover both
runtime reader paths, missing/checksum faults, receipt/content/good-blob retention,
cache accounting, configure/relaunch, explicit failed/successful repair,
development-origin behavior, compatible v1 receipts, malformed/unreadable marker
paths, marker write failure, stale same-/separate-Store reads, and a fault during
pending verification.

Concurrency tests inject a bounded reader/validator gate. The reader still reads
the actual fixture file and the Store still hashes its result; the test alters
one returned byte after pausing it. This reproduces the exact admission race
without relying on uncontrolled filesystem timing. These tests certify Store
transactions, not the native game decoder, rendering, hardware or offline-game
playability.

Run the folder-only mode on macOS from the source directory, with a private
output directory:

```sh
mkdir -p local-only/research/resource-admission/manual/modules
xcrun swiftc -swift-version 5 -parse-as-library -whole-module-optimization -Onone \
  -module-cache-path local-only/research/resource-admission/manual/modules \
  ios/App/ServerAddress.swift ios/App/NativeStockAssetAccess.swift \
  ios/App/NativeResourceManifest.swift ios/App/NativeResourceStore.swift \
  ios/App/NativeResourceSession.swift test_native_resources.swift \
  -o local-only/research/resource-admission/manual/admission-tests
local-only/research/resource-admission/manual/admission-tests \
  "$PWD/local-only/research/resource-admission/manual/checks" admission
```

The existing `python3 test_native_resources.py` network/persistence suite retains
its assertions and remains a separate check. It starts disposable loopback
servers and is not part of the folder-only execution above. Core108 App SDK and
device acceptance are separate gates.

## Limits

Runtime lookups verify the bytes they return; file-URL consumers must continue
using app-owned content-addressed paths. This change does not provide an OS-wide
filesystem lock or certify files that another process mutates after verification.
It does not delete corrupt blobs automatically, invent replacement game data,
change the native runtime verifier, or promise power-loss durability beyond the
filesystem's atomic metadata-write behavior. Original game resources remain
private and absent from this source and its portable fixtures.
