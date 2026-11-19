# Resource and development tools

| Directory | Purpose |
| --- | --- |
| `assets/` | Decode, convert and catalog owner-provided game resources |
| `archive/` | Capture and verify the browser reference archive |
| `development/` | Inspect native physics, prepare controlled network tests and verify repository layout |

Run utilities from the repository root using their full relative paths. Python helpers use explicit `tools` package imports. Generated resources and original data belong under ignored `local-only/`, never beside the source tools.

The stable entrypoints remain at the root:

```sh
python3 host.py setup --download
python3 host.py doctor
python3 host.py serve
zsh prepare_native_runtime.sh
zsh build_native.sh simulator
zsh build_native.sh device
zsh build_native.sh all
```

These commands can download or prepare substantial owner-side resources. Use the documented development caches instead of repeating preparation after an ordinary source update. Raw ISO extraction alone is not a complete playable native installation.

See [hosting](../HOSTING.md), [native builds](../NATIVE_BUILD.md), [game files](../docs/GAME-FILES.md) and [source layout](../docs/development/PROJECT-MAP.md).
