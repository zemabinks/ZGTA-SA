# Native game-file management foundation

The GAME menu can present `NativeGameFilesViewController()` in the existing San Andreas DE panel style. The view is independently implemented and shares the resource store rather than maintaining another asset library or game engine.

## Functional actions

- Import or repair a prepared folder containing `zgta-resources.json` and `blobs/<sha256>`. The resource store verifies content and atomically activates the catalogue.
- Verify installed resources and report the store's actionable failures.
- Cache or repair resources from a Mac resource-server origin. The store reuses matching verified blobs and retains the active catalogue if a job fails or is cancelled.
- Select development or installed mode. Installed mode remains unavailable until the store reports a verified usable installation.
- Inspect an original ISO through Files. This reads bounded ISO9660 metadata and reports the discovered installer filename set. It does **not** extract InstallShield, convert game resources, verify the game edition or install a playable game.

The coordinator owns an operation independently of the screen. Closing a screen does not cancel an installation or end the source provider's security-scoped access. Cancellation is explicit; access remains held until worker completion. Operation IDs reject late callbacks, and publication/cancellation guards prevent reentrant callbacks from rewinding or cancelling a replacement job. Installed resource identity is separate from app build number and multiplayer accounts.

Prepared package/profile validation, persistence, runtime resolution and transfer are owned by `NativeResourceStore` / `NativeResourceManifest`; this view does not fabricate their results. The current ISO inspection is a preparation foundation, not completion of standalone original-ISO installation.

## Verification

Run on a Mac with Xcode command-line tools:

```sh
python3 smoke_native_game_files.py
```

To additionally inspect an existing owner ISO without copying, extracting or modifying it:

```sh
python3 smoke_native_game_files.py --iso /absolute/path/to/your.iso
```

The test compiles immutable snapshots of the actual coordinator, inspector and resource store. It exercises cancellation/access lifetime, concurrent-action refusal, stale/duplicate/background callbacks, reentrant notification/operation changes, source validation, synchronous completion and a real production-store import/reopen/corruption/repair cycle. Its package contents are invented bootstrap/resource bytes: passing that plumbing test does not establish actual model/texture decoding or game rendering.

The ISO matrix uses synthetic valid, incomplete and malformed images, including byte-order disagreement, invalid extents, block sizes, unsafe/duplicate names, directory cycles and unsupported multi-extent records. Parsing uses primary ISO9660 descriptors and directory records from [ECMA-119](https://ecma-international.org/publications-and-standards/standards/ecma-119/); it intentionally supports only 2048-byte logical blocks and bounded metadata.

Reports, actual owner file inventories, source snapshots and compiler output stay under ignored `local-only/research/game-files-107/`. Focused UIKit SDK typechecking and full application builds are distinct from actual Files-picker/Simulator/physical-device acceptance. No physical installation, disconnected-Mac gameplay or app-update acceptance is claimed by these tests.
