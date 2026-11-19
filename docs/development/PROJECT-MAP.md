# Where the ZGTA:SA code currently lives

**This describes the existing repository**, not a proposed folder layout. It helps contributors find things without looking through hundreds of files.

| Folder or file | What it does |
| --- | --- |
| `ios/App/` | Swift iPhone app, menus, gameplay, Metal renderer and native networking |
| `ios/project.yml` | XcodeGen build configuration |
| `native-physics/` | Rust/Rapier physics implementation and native bridge |
| `native-samp/` | Native SA-MP/open.mp protocol transport and related source |
| `native-installer/` | Read-only ISO/InstallShield raw extraction utility, not a complete converter |
| `native-audio/` | Native audio support and licensed codec components |
| `native-menu-codec/` | Native menu/resource helper code |
| `selfhost_backend.js` | Independent multiplayer server logic |
| `host.py`, `serve_local.js`, launch scripts | Host setup, local browser service and development startup |
| `tools/assets/` | Original-resource converters and preparation utilities |
| `tools/archive/` | Public browser archive capture and verification utilities |
| `tools/development/` | Development inspection and repository layout checks |
| `tests/` | Regression runners and their fixtures, grouped by subsystem |
| `test-fixtures/` | Shared, independently authored fixtures |
| `docs/development/` | Living parity, compatibility and contributor records |
| `docs/research/` | Detailed historical CORE reports, grouped by subsystem |
| `local-only/` (ignored) | **Private local** assets, original data, builds and owner receipts; not in public GitHub |

## Which files should I read first?

- For the native client: [ios/App/MainMenuViewController.swift](../../ios/App/MainMenuViewController.swift), [ios/App/NativeGameViewController.swift](../../ios/App/NativeGameViewController.swift).
- For loading resources: [ios/App/NativeGameFilesViewController.swift](../../ios/App/NativeGameFilesViewController.swift), [ios/App/NativeWorldRenderer.swift](../../ios/App/NativeWorldRenderer.swift).
- For the independent backend: [selfhost_backend.js](../../selfhost_backend.js) and [HOSTING.md](../../HOSTING.md).
- For actual current progress: [CORE_GAMEPLAY_JOURNAL.md](CORE_GAMEPLAY_JOURNAL.md), [FEATURE_MATRIX.md](FEATURE_MATRIX.md).

Stable native implementations, server modules and launch entrypoints retain their existing locations. The root now contains 40 regular files; technical reports, tests and converters have moved into the directories above. Original assets and generated private resources remain under ignored `local-only/` paths.

See the [cleanup record](REPOSITORY-CLEANUP.md), [test map](../../tests/README.md), [tool map](../../tools/README.md) and [research index](../research/README.md).

[← Developer docs](../DEVELOPMENT.md)
