# Developer documentation — ZGTA:SA

This page is for contributors, advanced testers and anyone who wants to understand how the project is built. **If you just want to try the game, start with the [beginner guide](START-HERE.md).**

## First steps

- [Build the native iOS app in Xcode](development/BUILD-IOS.md)
- [Understand the repository's current source layout](development/PROJECT-MAP.md)
- [Safe, staged repository reorganization plan](development/REPOSITORY-CLEANUP.md)
- [Prepare/host the browser and native resources](../HOSTING.md)
- [Full native build details](../NATIVE_BUILD.md)
- [Source license and third-party notices](../LICENSE)

## Systems and compatibility

| Area | Main technical reference |
| --- | --- |
| Overall feature and test coverage | [FEATURE_MATRIX.md](../FEATURE_MATRIX.md) |
| Original GTA SA free-roam parity | [CORE_GAMEPLAY_PARITY.md](../CORE_GAMEPLAY_PARITY.md) |
| Current core development records | [CORE_GAMEPLAY_JOURNAL.md](../CORE_GAMEPLAY_JOURNAL.md) |
| Original 1.0 game comparisons | [CORE_RETAIL_REFERENCE.md](../CORE_RETAIL_REFERENCE.md) |
| SA-MP/open.mp/browser-world compatibility | [SERVER_COMPATIBILITY.md](../SERVER_COMPATIBILITY.md) |
| Local resource installation | [CORE_NATIVE_RESOURCES_107.md](../CORE_NATIVE_RESOURCES_107.md) |
| ISO raw extraction | [CORE_NATIVE_RAW_ISO_108.md](../CORE_NATIVE_RAW_ISO_108.md) |
| Game files interface | [CORE_GAME_FILES_107.md](../CORE_GAME_FILES_107.md) |
| Native backend build and toolchain | [NATIVE_BUILD.md](../NATIVE_BUILD.md) |
| Independent multiplayer server | [HOSTING.md](../HOSTING.md) |

**Why are there still many CORE_ reports at the repository root?** They are currently part of the active development/reproducibility workflow. Their migration is deliberately **separate** from this beginner-documentation update to avoid breaking tests, source links or an active Codex worktree.

The [cleanup plan](development/REPOSITORY-CLEANUP.md) gives the order and checks for moving them safely. Do not delete old verification records merely to make the GitHub front page look empty.

[← All guides](README.md)
