# Bounded Apple ISO / InstallShield bridge

This utility extracts **staged original resources**, not a playable native game.
No Windows executable or installer is run. Native resource conversion and final
runtime verification remain separate requirements.

## Source and licensing

The library subset under `vendor/unshield` is byte-identical to
[twogood/unshield at3914dffb32ad05ebcb3e7f64a033e69b59127f47](https://github.com/twogood/unshield/tree/3914dffb32ad05ebcb3e7f64a033e69b59127f47).
Its MIT notice and per-file hashes are retained. No game archive, CAB, ISO or
original resource is vendored. The upstream RSA MD5 implementation is omitted;
our small compatibility adapter uses Apple CommonCrypto for the cabinet format's
MD5 consistency check. Prepared resource security identities use SHA-256 elsewhere.

`patches/unsigned-le32.json` explicitly records the only build-stage vendor patch.
The original integer reader shifts a promoted signed int; UBSan found overflow
on the owner's actual metadata. The staged patch casts bytes to uint32_t before
shifting, preserving intended little-endian values. The pristine vendor files
are never rewritten. Build receipts record both pristine and staged source hashes.

## Reading and writing

The bridge independently indexes bounded primary ISO9660 directory metadata.
Only 2048-byte logical blocks and the admitted InstallShield6–13 ASCII descriptor
layout are supported; actual original-disc execution here covers version9.
Its callbacks retain one read-only ISO descriptor and read CAB/HDR byte ranges
with `pread`. It never holds the whole ISO in Data or duplicates complete cabinets.

A bounded HDR preflight checks extents, counts, string offsets, group ranges,
member aliases and cycles before calling the decoder. It preserves file-group,
directory and filename identities. Unused component/group-head tables are omitted
only from the RAM metadata view given to the decoder, preventing it from traversing
unvalidated linked lists. No source ISO byte is changed. Callback stream objects
abandoned by decoder error paths are also reclaimed at call boundaries.

C extraction requires an explicit index selection and a **new** staging directory.
It rejects existing destinations, unsafe/duplicate member paths, symlink traversal,
and file/job/input-byte bounds. The canonical caller-owned parent is opened directly without reading sandbox-external ancestors. Descriptor-relative no-follow member-directory traversal,
exclusive temporary files and rename constrain writes to that new stage.
Cancellation/failure rolls the current raw stage back. Previously active resources
are never used as staging. The source ISO remains intact. Persistent raw-job
resumption is not implemented by this low-level bridge.

## Swift boundary and default selection

Add `include/` to Swift's import search path, compile the files in `swift/`,
and link `libzgtasa_installer.a` with the platform's `libz.tbd`. CommonCrypto is
provided by the Apple system libraries. These files are not another game engine.

`NativeISOExtraction` is a synchronous worker API. Its caller retains Files
security-scoped access, runs work off the UI thread and forwards progress to UI.
Each instance supports one operation at a time; cancellation is thread-safe.
The full catalogue remains available for inspection. `gameResources()` and
`extractGameResources(to:)` select the original anim, data, models, text, audio
and movies roots, including extensionless radio streams and resources whose
native converters are still pending. The default excludes Windows components,
installer containers, support groups and HOODLUM extras. Duplicate destination
identities cause refusal, not an arbitrary source choice.

The lower-level explicit selection API exists for controlled source investigation;
the application should use the default raw-resource selection. Extraction success
means selected raw files were written and cabinet consistency checks passed.
It does not identify a game edition, establish converter coverage, activate the
resource store or declare the game playable.

## Builds and checks

```sh
python3 build_installer_bridge.py
python3 smoke_native_installer_bridge.py
```

Build outputs stay under this clone's ignored `local-only/native-installer/`:
host, arm64 device and universal arm64/x86_64 Simulator static archives. This
uses existing Xcode/SDK/system zlib; it installs no global tools. The runner
without owner arguments tests synthetic selection and invalid-source boundaries.

For actual read-only owner ISO tests, provide the existing accepted selected
resource tree:

```sh
python3 smoke_native_installer_bridge.py --iso /path/to/original.iso --accepted-root /path/to/accepted/installed-selected
```

This additionally tests six exact accepted cabinet resource paths and SHA-256s,
a loose extensionless radio stream against independently indexed private fixture
bytes, malformed ISO/HDR/CAB behavior, cancellation, limits and staging isolation.
All original-byte fixtures/output stay in disposable local-only directories.

`--platform host --sanitize` produces a separate ASan/UBSan archive. The C
`tests/sanitize.c` carrier exercises actual extraction and malformed/retry paths.
Device/Simulator compilation and cross-link probes do not establish physical
phone runtime, UI integration, throughput, thermal performance or a complete
standalone installation. Root build orchestration owns app linking and activation.
