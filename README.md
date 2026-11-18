# ZGTA:SA

Community multiplayer hosting source and a native Swift/Metal iOS client for
San Andreas. Players can join as guests; Discord account linking is optional.
Each host runs its own world, accounts, economy and saved progress.

**Start here: [Hosting guide](HOSTING.md)** · [Native iOS builds](NATIVE_BUILD.md) ·
[Native menu](NATIVE_DE_MENU.md) · [Feature coverage](FEATURE_MATRIX.md) · [AGPL license](LICENSE)

## Run a server

Install Node.js 22 or later and Python 3.9 or later on macOS or Linux:

```sh
git clone https://github.com/zemabinks/ZGTA-SA.git
cd ZGTA-SA
python3 host.py setup --download
python3 host.py serve
```

Open `http://127.0.0.1:8766/`. Setup downloads discoverable public content into
ignored `local-only/`; it can resume existing downloads. To import an existing
site archive or prepare native iOS data, follow [HOSTING.md](HOSTING.md).

For LAN play, replace the example address with your host's LAN IP:

```sh
python3 host.py serve --bind 0.0.0.0 --host 192.168.1.20:8766
```

The launcher creates a private join code under `local-only/selfhost/`. The
hosting guide also covers public HTTPS access through a WebSocket-capable
reverse proxy, backups, guest identities and optional Discord linking.

## What is included

- Independent Node multiplayer server, saved guest accounts, chat, garage and
  property ownership, jobs, races and other local gameplay systems.
- Browser hosting and asset archive/import tools.
- Native Swift, UIKit, Metal and GameController source with touch controls.
- Separate SA-MP/open.mp UDP and original-browser-world adapters; see the
  [tested compatibility boundaries](SERVER_COMPATIBILITY.md).
- Local asset converters, pinned Rust physics bridge and source comparison tests.

Game assets, the original website bundles, extracted game catalogs, converted
meshes/textures, music, player saves, credentials and compiled builds are
excluded from GitHub. A source checkout needs a local content archive before
it can render the game. Download tools depend on the public source remaining
available; they do not obtain the publisher's private backend.

## Development status

Core movement, animation, camera, physics, vehicles and combat now take priority
over advanced roleplay. See the [core parity checklist](CORE_GAMEPLAY_PARITY.md)
and [audit journal](CORE_GAMEPLAY_JOURNAL.md) for tested fixes and remaining work.
The [original-game reference ledger](CORE_RETAIL_REFERENCE.md) records direct
data comparisons and unresolved engine differences.
The [rider clock](CORE_RIDER_RENDER_CLOCK_116.md),
[legacy spawn ownership](CORE_LEGACY_SPAWN_INFO_116.md), and
[browser recovery](CORE_BROWSER_RECOVERY_116.md) notes describe the current
transition fixes and their verification boundaries.
The [owner radio import guide](RADIO_OWNER_IMPORT.md) covers complete local
recordings and the separate compatibility/full-recording programme choices.

This is an in-progress reconstruction. The independent server uses its own
mission/economy policies, and the native client still has gaps compared with
the browser game. It is not yet a full 1:1 port. [FEATURE_MATRIX.md](FEATURE_MATRIX.md)
tracks verification and outstanding work. [Development notes](DEVELOPMENT_NOTES.md)
retain earlier behavior, commands, optional Discord configuration and validation
records. Simulator/generic-device builds do not certify physical iPhone performance.

## Source and license

Project contributions use **AGPL-3.0-only**. See [LICENSE](LICENSE) and
[NOTICE.md](NOTICE.md); separate game content and dependencies retain their own
terms. Hosted modified versions must offer their corresponding source. Set
`ZGTA_SOURCE_URL` to your fork/source archive; the browser game panel exposes it.

```sh
python3 smoke_host.py
python3 smoke_public_source.py
python3 check_public_source.py
```

On macOS with Xcode, `python3 smoke_core_116.py` runs the portable native source
regressions without game assets. Full SDK builds and actual gameplay tests are
separate checks.
After building the host transport, add `--with-transport` to include the full
client/adapter lifecycle gate.

The GitHub workflow runs source/history checks and synthetic hosting tests on
Linux. Full gameplay and native fixtures additionally require your local archive;
the hosting and native build guides list the relevant checks.
