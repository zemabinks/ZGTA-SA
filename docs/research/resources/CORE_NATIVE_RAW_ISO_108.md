# Original ISO raw-resource extraction

Core108 connects the bounded native ISO/InstallShield bridge to GAME → GAME FILES.
`EXTRACT RAW RESOURCES FROM ISO` opens the normal Files picker without making an
App-managed copy of the ISO. The worker reads source ranges directly and saves
original resources in a separate app-owned raw store. No Windows executable or
installer is run. The existing prepared-folder, Mac cache, verification and
development/installed-mode workflows remain separate.

The last valid requested Mac origin is remembered separately as a UI preference,
including after cancellation, navigation and App restart. It is never substituted
for the installed catalogue's committed development origin. Invalid or
credential-bearing addresses do not overwrite that saved draft. This corrects
the observed first-install BACK/reopen address loss without changing cache
admission or the resource store's atomic source binding.

**Saved raw resources are not a playable native installation.** This action does
not convert original formats, produce a prepared package, change the active
native-resource source or set `hasPlayableInstallation`. The UI states that
native conversion is still required. `VERIFY SAVED RAW RESOURCES` checks the raw
receipt and output checksums; it is not the native runtime-format verifier.

## Storage and lifetime

The source identity is the SHA-256 of the complete ISO, read in bounded chunks.
It is independent of the App build number, source filename and Mac server. The
source's file identity, size and modification time are checked around extraction
to reject a source changed during the job. The source must remain unchanged;
Files-provider runtime behavior still needs actual App/device acceptance.

The default selection retains all recognized anim, data, models, text, audio and
movies resources, including extensionless audio. Windows components, installer
containers and support extras are excluded. Original relative spelling is kept.
The complete-path case-insensitive index rejects ambiguous duplicates instead
of silently choosing one Windows-style identity. A raw asset is not discarded
merely because its future converter is unavailable.

The shared coordinator retains the selected source's security-scoped access and
its operation until worker completion and cleanup. Leaving the screen does not
cancel the operation. Cancel requests are idempotent; stale callbacks cannot
release a newer operation's access or replace its presentation. Existing
foreground resource-busy ownership keeps the display awake while appropriate;
this does not promise unrestricted background execution.

`Application Support/ZGTA-SA/RawResources-v1` holds immutable output generations,
their checked raw receipts and one atomically replaced catalogue. Newly decoded
files are hashed before a generation becomes selected. Cancelled/failed stages
are removed, and a previous raw generation or installed native catalogue is not
used as scratch space. A failed or cancelled replacement cannot select its
partial output. Interrupted staging and unreferenced generations are cleaned
under the exclusive storage lock when a subsequent raw operation starts.

Completed raw data survives normal App restarts and updates. Opening the screen
does not reopen or re-extract the ISO. Selecting the same ISO again verifies and
reuses an existing complete generation; damaged raw output is replaced only
after a new checked generation commits. Interrupted new extraction is rolled
back, rather than advertised as a resumable complete set. Deleting/resetting the
App removes its private raw data; the externally selected original ISO remains
unchanged.

## Build boundary

The iOS project includes the independently authored Swift wrapper and the
`CZGTAInstaller` module, links the matching private platform archive and system
zlib, and uses Apple's system CommonCrypto. The pinned MIT vendor source and C
bridge are unchanged from Core107.

`build_installer_bridge.py --check --platform device` and `--platform simulator`
are read-only source/archive checks. Ordinary builds reuse matching archives;
UI/Swift-only changes do not force a C rebuild. Rebuilding refuses linked output
or cache paths. Build commands never extract an ISO, run converters or replace
owner resources. Source, receipts and build artifacts remain separate.

## Focused verification

```sh
python3 tests/resources/smoke_native_raw_resources.py
python3 tests/resources/smoke_native_game_files.py
python3 tests/resources/smoke_native_raw_sdk.py
```

The raw-store test uses explicitly injected authored bytes for lifecycle,
atomicity, reuse, repair, casefold ambiguity, concurrency, cancellation,
directory-link refusal and stale/reentrant coordinator cases. This fixture
extractor has a separate identity and is never the App's default extractor.
The actual default C parser also refuses a malformed source without replacing
the existing raw catalogue. Existing prepared/cache/mode/source-inspection
regressions compile against the new real dependencies.

The separate owner-only carrier checks six original relative paths against the
already accepted extraction. It is retained privately under ignored
`local-only/`, not included in public source or required by the synthetic gate.
In the owner's workspace its command is:

```sh
python3 local-only/research/raw-iso-108/owner_raw_resources.py --iso /absolute/path/original.iso --accepted-root /absolute/path/accepted/resources
```

This uses the real native decoder and actual persistent raw-store machinery,
but a test-only selection identity. It does not claim a complete 409-resource
extraction or native conversion. Original bytes and temporary test output stay
under ignored `local-only/research/raw-iso-108/` and are cleaned after the run.

The SDK gate links immutable snapshots of the actual raw-store/coordinator/
wrapper sources and typechecks the actual Game Files view for the device and
both Simulator architectures. Only the unrelated base-menu contract is reduced.
SDK checks are distinct from the full App build and actual picker/UI/runtime
acceptance, which must be reported separately.

## Next boundary

A converter must consume the checked raw receipt/index, establish its supported
source edition and formats, and produce a genuine verified prepared-resource
package. Activation must still pass the existing native resource-store/runtime
verification. There is no extraction-to-playable shortcut or second engine.
No original game assets, ISO/CAB payloads, owner receipts or captures belong in
the public repository. Native conversion, standalone scene acceptance, device
throughput/thermal measurements and full-game parity remain open.


## Original navigation reader (142)

The native resource path now includes an independently written exterior
`NODES0.DAT`–`NODES63.DAT` reader and immutable pedestrian/vehicle graph queries.
An explicit **Check Original Navigation** action in Game Files reads the saved
raw set through its existing verified lease API, checks linked nodes and runs
pedestrian and vehicle nearest-node/route queries. It does not run at startup,
change installed mode, spawn actors, or send entities to a multiplayer server.

The loader binds source, content, selection and generation, closes each lease
after a bounded copy, hashes the copied bytes and repeats the source fence
before delivering the graph. Reads and decoding run on a serial utility queue;
progress, cancellation and completion use the existing app-owned coordinator.
A same-content repair still invalidates the old generation. Missing areas,
malformed sections, invalid references, changed files and resource/query limits
produce explicit failures. Cancellation and leaving the screen preserve saved
resources and do not leave file leases pinned.

The parser covers node positions, widths, flags and adjacency; vehicle navi
records, lane counts and signal metadata; and crossing/intersection flags. The
queries use independent geometric A*. This is a data/query foundation: original
CPathFind choices, dynamic node switches, population scheduling, lane following,
signals, obstacle avoidance, police and traffic behavior remain unimplemented.
It does not make a raw installation playable or establish retail parity.

Format declarations were cross-checked against the licensed
[Plugin-SDK node declarations](https://github.com/DK22Pac/plugin-sdk/blob/master/plugin_sa/game_sa/CPathNode.h)
and [rwfury path reader](https://github.com/Hancapo/rwfury/blob/master/rwfury/paths.py).
The decoder was authored independently. No third-party implementation or
original game bytes are embedded in these sources. Reserved link slots and
length/intersection padding are checked as distinct sections rather than
silently discarding crossing flags.

Run `python3 tests/resources/smoke_native_original_navigation.py` for authored
DAT/query cases and actual raw-store/lease/coordinator lifecycle tests. This
includes missing, oversized and unsupported files, wrong selection, invalid and
unloaded references, query limits, same-content generation repair, source swap,
post-verification mutation, symlink/FIFO refusal, busy admission, cancellation,
menu completion and dismissal. Existing resource tests compile the actual new
dependencies. Full SDK and normal installed-menu acceptance are separate checks.
Owner-data comparisons and screenshots remain ignored and local.
