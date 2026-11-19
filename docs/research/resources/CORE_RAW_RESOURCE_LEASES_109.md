# Core109: verified raw-file leases

`NativeRawResourceStore` now provides asynchronous read-only leases for original
files already saved by its extractor. This is file access infrastructure for
future offline audio; it does not implement playback, decode radio, export PCM,
activate prepared gameplay or turn an ISO into a playable installation.

## Receipt metadata and lazy verification

`readReceiptDescriptor(expectedSourceID:expectedContentID:completion:)` returns an
immutable `ReceiptDescriptor`: source/content/generation/selection identities,
source name/size, and `resourcesByCasefoldedPath`. Values preserve the exact
receipt spelling, byte count, SHA-256, group and source. It validates only the
bounded receipt and catalogue metadata; it does not open/hash all audio packs.
The read does not change `snapshot.verified`.

`acquireLocalFile(path:matching:maximumBytes:verificationProgress:completion:)`
binds a requested file to that exact descriptor. The explicit identity overload
also accepts `expectedSourceID`, `expectedContentID` and `expectedGenerationID`.
Matching is case-insensitive over complete selected paths, with the receipt's
original spelling retained in `lease.binding`.

A bounded worker opens an app-owned regular file through directory FDs with
`openat`/`O_NOFOLLOW`, verifies its actual size and complete SHA-256 using at most
1 MiB per read, checks file identity/timestamps, then rechecks source selection.
Delivery has a final bounded catalogue/receipt metadata fence. Cancellation or a
superseded source/generation returns failure and closes the candidate. Per-file
success never marks the whole raw source verified. A fault can clear only the
same current raw generation and captured snapshot revision; it cannot revoke a
newer whole-source verification or replacement.

Completions run on the main queue. Verification progress is immutable and runs
on the worker; callers must marshal UI updates. The `.verified` progress stage
is not delivery approval: a subsequent source change/cancellation can still
reject the result. Construct/prepare/decode C state on a separate worker.

## Decoder lifetime

The lease exposes no absolute path or file URL:

- `read(atOffset:maximumBytes:)` uses bounded `pread`, permits EOF, and checks
  the owned FD before/after reading. Offset/count overflow and oversized reads
  fail before allocation.
- `withFileDescriptor` borrows an O_RDONLY/CLOEXEC FD within a serialized,
  mutation-checked closure. The closure must not close or retain the borrowed FD.
- `duplicateFileDescriptor()` returns an owned `Descriptor`. Retain it for the
  decoder's entire lifetime, and use its `withFileDescriptor` for C construction,
  preparation and decode operations. C must duplicate the borrowed FD if it
  takes FD ownership. Close the C decoder before closing this owner.
- A Descriptor retains shared lease storage and its generation lock, even after
  the public lease is closed. Read/dup/close and borrowed construction serialize;
  close cannot recycle a descriptor while its closure initializes a decoder.

POSIX duplicated FDs share their open-file position. Independent decoder cursors
must use `pread` or a cursor adapter; the lease's own reads never move that
position. Limits are two acquisition workers, sixteen outstanding file requests,
sixteen live file storages per Store, eight duplicate handles per storage, two
outstanding receipt reads, and 1 MiB per read. Whole-file admission is bounded by
the selected receipt and caller byte budget, at most UInt32.max bytes.

A retune can re-read lightweight metadata and compare source/content/generation
IDs before reusing provider state. Existing opened leases deliberately remain
valid when selection changes. Playback/session ownership must cancel obsolete
requests and decide when to close old decoders; raw-store selection is not a
playback state machine.

## Generation collection

The existing global operation lock still guards extraction/catalogue mutation.
Acquisition holds it only while binding/opening and checking metadata, not for
the whole checksum or lease lifetime. Each live storage retains a shared lock
for its generation in a separate persistent `lease-locks` directory.

All obsolete-generation deletion paths now require a nonblocking exclusive
lock. A leased generation is skipped and can be collected by a later ordinary
operation after its last owner closes. Generation lock files are never unlinked
or recreated by collection, avoiding a second inode that could bypass readers.
A repaired/source-replaced generation cannot delete an already opened lease.

These locks coordinate RawStore operations. They are not an OS-wide prohibition
on external writes. File identity, size, nanosecond modification/change stamps
and whole-file admission detect ordinary replacement/mutation; callers must
honor the borrowed-FD contract. Failed reads do not silently fall back to a URL
or start a download.

## Verification

The actual RawStore and helper passed **76 authored-fixture checks**, covering
receipt-only construction, relaunch, whole-file verification/read bounds,
FD flags/quota/lifetime, repair/source replacement, cancellation, late delivery,
mutation during hashing and after acquisition, newer-verification protection,
symlink/hardlink refusal and cleanup from another Store instance. A deliberately
unreadable/corrupt unrequested pack establishes that catalogue construction does
not open/hash all thirteen fixture packs.

The existing raw/coordinator regression passed **53 checks**. Actual source
snapshots typechecked for arm64 iOS16, arm64 iOS16 Simulator and x86_64 iOS16
Simulator. These are SDK checks, not full-App links or hardware execution.

Run the portable authored-fixture suite with a fresh private output and a pinned
installer archive, or let the helper build the unchanged pinned host C bridge
into its own real private cache:

```sh
python3 tests/resources/smoke_native_raw_leases.py --sdk-check
```

The recorded run used the verified Core108 host archive read-only: its C/header,
config, target and archive hashes match current pinned source, and its Swift
wrapper/header were independently checked unchanged. No C source/project or
playback source was modified. Original assets, actual App data, network services,
Simulator/phone UI and radio decoding were not used by these tests.
