# Repository cleanup

The cleanup continues from native build 136; it does not replace the game implementation. The public root previously contained 711 files. It now contains 40 regular files, with stable hosting and build entrypoints retained.

## Locations

- Living parity and compatibility records: `docs/development/`.
- Historical technical reports: `docs/research/`, grouped by subsystem.
- Regression runners and companions: `tests/`, grouped by responsibility.
- Asset converters: `tools/assets/`.
- Browser archive utilities: `tools/archive/`.
- Source-layout verification and development inspection: `tools/development/`.

See the [source map](PROJECT-MAP.md), [test map](../../tests/README.md) and [tool map](../../tools/README.md).

Native implementation folders, independent server modules and the simple public commands retain their existing locations. Imports, Node requires, project-root calculations, fixture copies, shell invocations, CI commands and Markdown links were updated with the moves. Python packages are explicit; direct test invocation still works outside the repository directory.

## Validation

The work uses a dedicated worktree and recoverable local commits. Source-safety checks now traverse `docs`, `tests` and `tools`; private-file denies remain enforced. The layout verifier checks package imports, documentation links, stable entrypoints and negative safety fixtures inside all three relocated trees.

The complete build-136 regression chain and sequential Simulator/device SDK builds are required before publication. Final outcomes are recorded in the [project status](../PROJECT-STATUS.md). Authored tests and successful builds do not establish physical-device or original-retail gameplay acceptance.

Existing Mac-hosted resources and prepared Simulator installation metadata are retained. No original game files, converted assets, saves, credentials or private development history belong in the public cleanup commit. Public publication starts from public Git history and uses a public-safe generated Xcode project.

## Follow-up development

Resume demonstrated gameplay defects after cleanup verification, starting with breathing ownership and swimming/reconnection transitions. Gravity propagation, missing original resources, ambient pedestrians, traffic and police remain substantial work. Original campaign missions remain excluded.

Use local checkpoints and coherent public updates with free tooling. Keep the root clean; extend the existing subsystem records instead of adding another top-level report.

[← Developer docs](../DEVELOPMENT.md)
