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
| `prepare_*.py` / `prepare_*.js` | Asset converters and preparation scripts |
| `CORE_*.md` | Detailed technical progress and verification records |
| `smoke_*`, `test_*`, `check_*` | Regression tests, fixtures and source checks |
| `tests/`, `test-fixtures/` | Some already-grouped testing infrastructure |
| `local-only/` (ignored) | **Private local** assets, original data, builds and owner receipts; not in public GitHub |

## Which files should I read first?

- For the native client: [ios/App/MainMenuViewController.swift](../../ios/App/MainMenuViewController.swift), [ios/App/NativeGameViewController.swift](../../ios/App/NativeGameViewController.swift).
- For loading resources: [ios/App/NativeGameFilesViewController.swift](../../ios/App/NativeGameFilesViewController.swift), [ios/App/NativeWorldRenderer.swift](../../ios/App/NativeWorldRenderer.swift).
- For the independent backend: [selfhost_backend.js](../../selfhost_backend.js) and [HOSTING.md](../../HOSTING.md).
- For actual current progress: [CORE_GAMEPLAY_JOURNAL.md](../../CORE_GAMEPLAY_JOURNAL.md), [FEATURE_MATRIX.md](../../FEATURE_MATRIX.md).

Most code is already grouped by technology. **The root folder is the real organizational problem.** There are many valid test runners and historical reports at the top level. They should be moved carefully, with calls, imports, build paths and documentation links updated together.

See [Safe cleanup plan](REPOSITORY-CLEANUP.md). The first documentation update intentionally leaves those tested paths intact.

[← Developer docs](../DEVELOPMENT.md)
