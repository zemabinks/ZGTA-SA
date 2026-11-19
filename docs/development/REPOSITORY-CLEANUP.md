# Safe repository cleanup plan

**Status: proposed follow-up, not executed by this documentation change.**

The current GitHub root has accumulated large groups of `CORE_*.md` reports, `smoke_*` and `test_*` files, converters and server scripts. This makes the repository intimidating for new readers even though many of those files are legitimate, useful work.

**Do not mass-move them without a local Codex/worktree preflight.** This first documentation milestone changes the public guides and provides a source map; it deliberately does not modify gameplay logic, move active files, alter the build graph or change the local game-asset layout.

## Intended destination layout (subject to dependency checks)

```text
ZGTA-SA/
├── README.md, LICENSE, NOTICE.md
├── .github/
├── ios/                       # keep project and source under the current build root
├── native-physics/            # preserve until build and ABI references are reconciled
├── native-samp/
├── native-audio/
├── native-installer/
├── server/                    # eventual home for independent hosting/network helpers
├── tools/                     # eventual asset preparation / conversion / build helpers
├── tests/                     # grouped smoke tests and fixtures
├── docs/
│   ├── START-HERE.md
│   ├── GAME-FILES.md
│   ├── MULTIPLAYER.md
│   ├── TROUBLESHOOTING.md
│   ├── PROJECT-STATUS.md
│   ├── development/
│   └── research/              # eventual home for historical CORE_ ledgers
└── host.py, build_native.sh   # keep easy stable entrypoints, or backwards-compatible wrappers
```

This tree is an **organization target**, not a claim these directories exist today.

## Required preflight before moving code

1. Work from the **latest local branch**; inspect `git status`, active worktrees and in-progress Codex tasks. Preserve uncommitted changes and all `local-only/` resources. Never replace a running host or reset user data just to reorganize files.
2. Record the exact current baseline and run the applicable existing source checks, host tests, native project generation, Swift/Metal builds and asset preparation tests.
3. Search for every hard-coded filename, working-directory assumption, `__file__`-relative path, Python import, shell invocation, Node `require()`, XcodeGen path and Markdown link affected by each proposed move.
4. Move a **small, coherent group** in a separate commit. Update every importer, path, test invocation, workflow and documentation reference. Keep stable root launch commands or provide tested compatibility wrappers.
5. Run all focused tests, then the broader relevant regressions. Confirm the native app still builds and the independent server still starts. Do not mistake a source-only test for physical gameplay acceptance.
6. Check Git history/rename detection and diff: no lost files, no unwanted contents changes, no original proprietary assets introduced.
7. Continue in batches only when each group is verified. **Stop and isolate** any failing move; do not silently remove or skip tests to make the cleanup pass.

## Suggested ordering

**Stage 1 — Beginner-facing README and guides:** this change. No production-path migration.

**Stage 2 — Documentation-only moves:** organize the `CORE_*.md` reports under `docs/research/` in coherent groups. Repair links in every report, the source README, PR references and any test/scripts that open those documents. Don't move a file merely to reduce the root count if external consumers rely on its current path.

**Stage 3 — Test scripts:** inventory executable entrypoints, imports and fixture paths. Move test families into `tests/` gradually, preserving tested root entrypoints or wrappers until all scripts and CI are updated.

**Stage 4 — Converters and server helpers:** move separately from gameplay changes. First reconcile absolute/relative paths, `cwd`, scripts and installation docs. Verify source-only and owner-asset workflows before deprecating compatibility entrypoints.

**Stage 5 — CI and public docs:** update GitHub Actions, issue links, README navigation and maintainer documentation. Run the exact revised workflows and inspect the GitHub-rendered README. Add **real** app screenshots only when verified screenshots are available; do not use invented previews or claim a playable downloadable IPA.

## Publication and cost

Local commits are inexpensive recovery checkpoints. **Batch related commits into fewer GitHub pushes**, but keep remote/off-device backups before risky changes and at meaningful milestones. Do not add paid runners, services or billable automation.

The public GitHub repository should remain **source-only**, with copyrighted game data, the ISO, user saves, credentials and generated runtime payloads excluded.

## Suggested GitHub repository description

`ZGTA:SA — Experimental native iOS San Andreas project built with Swift/Metal, focused on authentic free-roam gameplay and cross-platform multiplayer.`

GitHub's repository-description field is a separate setting; changing this file does **not** update that setting.

[← Developer docs](../DEVELOPMENT.md)
