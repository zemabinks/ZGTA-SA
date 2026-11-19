# Regression tests

Run commands from the repository root. Python runners add that root to their import path, so direct invocation also works from other working directories. Swift and JavaScript companions belong beside their corresponding runner.

| Directory | Scope |
| --- | --- |
| `core/` | Versioned core chains and aggregate gameplay checks |
| `hosting/` | Public-source safety, host setup, origin policy and project generation |
| `resources/` | Resource admission, extraction, conversion and installation |
| `movement/` | Character tasks, locomotion, swimming and physics handoffs |
| `vehicles/` | Vehicle dynamics, occupants, rigs and synchronization |
| `combat/` | Weapons, damage, inventory and animation ownership |
| `network/` | Connection recovery, protocol adapters and remote state |
| `server/` | Independent backend gameplay and persistence |
| `browser/` | Archived-client compatibility patches and recovery |
| `audio/` | Radio, audio delivery and native sound behavior |
| `rendering/` | Native scene, material and rendering checks |
| `ui/` | Input ownership, camera, menus and settings |

Common checks:

```sh
python3 tests/hosting/smoke_public_source.py
python3 tests/hosting/smoke_native_project.py
python3 tests/hosting/smoke_host.py
python3 tools/development/verify_repository_layout.py
python3 tests/core/smoke_core_140.py
```

Some tests require Xcode, native dependencies or owner-provided local resources; inspect each runner's requirements. Passing authored fixtures does not establish retail accuracy, rendered gameplay or physical-device acceptance. Runtime receipts stay in ignored local storage.

[Developer documentation](../docs/DEVELOPMENT.md)
