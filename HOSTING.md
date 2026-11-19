# Host your own ZGTA:SA server

This repository contains the independent multiplayer server, browser hosting
tools and native iOS client source. Each host runs a separate world with its own
players, economy and saves. Discord is optional. This is a development release;
the native client and independent server do not yet reproduce every function of
the publisher's game. See [FEATURE_MATRIX.md](docs/development/FEATURE_MATRIX.md) for the tracked
coverage and limitations.

The original website bundles, San Andreas assets, extracted catalogs, converted
meshes, music and player data are excluded from GitHub. You need a local asset
archive; cloning this repository alone does not include a playable world. The
download tools use public asset URLs without account access. Their success
depends on those URLs remaining available. They do not recover the publisher's
private server implementation.

## Requirements

- macOS or Linux, Python 3.9 or later and Node.js 22 or later.
- Several GB of free disk space for the local archive and native conversions.
- A browser with WebGL. A native app build additionally needs a Mac with full
  Xcode, its iOS platform, XcodeGen and Rust; see [NATIVE_BUILD.md](NATIVE_BUILD.md).

The browser server uses Node's built-in modules; there is no npm install step.

## First setup

```sh
git clone https://github.com/zemabinks/ZGTA-SA.git
cd ZGTA-SA
python3 host.py setup --download
python3 host.py doctor
python3 host.py serve
```

Open `http://127.0.0.1:8766/`. Setup resumes existing downloads. Unavailable
source URLs are recorded under `local-only/`; an updated publisher bundle may
require corresponding extractor updates. Setup stops if a required catalog
cannot be extracted instead of substituting an unrelated game.

To reuse an archive, copy only its `site` directory through the importer:

```sh
python3 host.py setup --import-site /absolute/path/to/local-only/site
```

The importer does not copy another host's `selfhost` directory, accounts,
Discord credentials or browser profile. It rejects symlinks and conflicting
existing files. Stop the server before updating its archive.

## Friends on your LAN

Find your host's LAN address, then substitute it below:

```sh
python3 host.py serve --bind 0.0.0.0 --host 192.168.1.20:8766
```

Friends open `http://192.168.1.20:8766/` on the same network. The launcher creates
a persistent join code in `local-only/selfhost/join-code.txt`; give friends that
code privately. Permit the Node listener through your host firewall if needed.
Keep this process running and prevent the host from sleeping. Ctrl-C stops it.

On macOS, the existing `zsh launch_share.sh lan` shortcut also detects the
network address. It prepares the native runtime too, so install native
conversion dependencies before using that shortcut.

## Public internet hosting

Use an HTTPS reverse proxy that supports WebSocket upgrades and forwards the
original Host header. Keep Node bound to loopback. For example, with Caddy on
the same host and a domain pointed at that host:

```sh
python3 host.py serve --host play.example.com
```

```caddyfile
play.example.com {
    reverse_proxy 127.0.0.1:8766
}
```

This follows Caddy's [reverse proxy configuration](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy),
which supports WebSocket upgrades and preserves the HTTP Host header.

Replace `play.example.com` in both places. Forward ports 80 and 443 to the proxy
when hosting behind a home router, or use a host/tunnel with public inbound
access. Caddy manages HTTPS when the domain and ports are reachable. Do not
serve the repository directory as a static document root: the Node application
serves only the intended routes and local asset folder.

This loopback-proxy configuration permits public guest play without Discord
and without an invite code. To restrict it, add
`--code-file local-only/selfhost/join-code.txt`. Repeat `--host` to permit more
than one domain or LAN address. Preserve the proxy's forwarded headers; the
server uses them for secure cookies and join-code checks.

No domain or tunnel account is needed for LAN hosting. The original Mac's
internet routing and a live public domain have not been configured or tested.

## Native iOS clients

Create a Python environment for converters and optional owner-supplied radio:

```sh
python3 -m venv local-only/venv
local-only/venv/bin/python -m pip install -r requirements-native.txt
local-only/venv/bin/python host.py setup --native
```

Add `--download` when there is no archive yet. Native setup converts world
atlases, models, skeletons, animations, HUD, handling, vehicle rigs, effects and
runtime catalogs under `local-only/site/game/native/`. Some missing public
animation/flight files can be fetched by their preparation tools. Radio
recordings are not bundled; see [NATIVE_RADIO.md](docs/development/guides/NATIVE_RADIO.md).
Native setup also creates the separate local coupling catalog and complete
working-vehicle rig stage. To upgrade an already prepared native archive:

```sh
node tools/assets/prepare_native_vehicle_coupling.js
node tools/assets/prepare_native_working_vehicles.js
node tests/vehicles/smoke_native_working_stage.js
```

Restart the local server after generating the coupling catalog so it can
negotiate the attachment protocol. These commands keep original derived data
under `local-only/`; retain the complete matched rig families. See
[working vehicles and towing](docs/research/vehicles/CORE_VEHICLE_COUPLING.md) for coverage and limits.
When using owner-supplied radio streams, start the server with
`local-only/venv/bin/python host.py serve` so its decoder uses that environment.

Build the app with [NATIVE_BUILD.md](NATIVE_BUILD.md). In its server menu, use
your Mac's LAN URL or the public HTTPS URL. `127.0.0.1` on a physical iPhone
means the phone itself. Native and browser players connected to this server
share its world. Joining the publisher's service still requires its own
authentication and compatible protocol.

## Connecting the native app to an existing game server

The asset origin and gameplay destination are separate. Keep your prepared Mac
asset server available to the phone even when gameplay uses an external SA-MP
server or the original browser world. Native models are not downloaded from an
ordinary SA-MP server. Core compatibility remains in development; consult
[SERVER_COMPATIBILITY.md](docs/development/SERVER_COMPATIBILITY.md) before promising support for
a particular roleplay server.

For the original-world weapon policy, upgrading an existing archive requires:

```sh
node tools/assets/prepare_original_world_weapons.js
```

The normal `prepare_native_runtime.sh` path also runs this exporter. For legacy
SA-MP skins, import your own classic game's `data/peds.ide` after preparing the
native model index:

```sh
python3 tools/assets/prepare_native_samp_skins.py --peds /path/to/your/SA/data/peds.ide
```

Both commands write only ignored `local-only/original-world-assets/` sidecars;
`serve_local.js` exposes those exact native metadata routes. A missing skin is
reported rather than silently substituting an unrelated pedestrian. The native
connection form checks the required sidecars before attempting a legacy join.
The Mac asset server may require its own join code; that is independent of the
SA-MP server password and the original service's login.

In the app's Multiplayer panel, **JOIN SA-MP / OPEN.MP** accepts a host:port,
nickname, optional server password, and0.3.7/open.mp or0.3.DL profile. The
original-world entry opens the service's own sign-in inside the app and uses
that app-owned session. Our independent server's anonymous guest policy does
not change another service's access requirements.

## Accounts, backups and updates

Guest progress is stored in the host's `local-only/selfhost/players.json` and
identified by the visitor's cookie; the native app retains its own server
identity. Clearing that identity can lose access to the guest save. Optional
Discord identity linking and its one-time bonus are documented in DEVELOPMENT_NOTES.md;
the server starts normally without OAuth credentials.

Stop Node, back up `local-only/selfhost/` privately, and then update source.
Back up the asset archive separately if you need offline restoration. Run only
one server per player-state directory; a lock rejects competing writers.
Never publish this directory or copy your credentials into a fork.

## Source availability and verification

The source is licensed under AGPL-3.0-only; see [LICENSE](LICENSE) and
[NOTICE.md](NOTICE.md). If you host a modified version, offer its corresponding
source to players. Set `ZGTA_SOURCE_URL` to your fork or source archive before
starting the server; the game panel exposes the link.

```sh
python3 tests/hosting/smoke_host.py
node tests/server/smoke_discord.js
node tests/server/smoke_multiplayer.js
node tests/server/smoke_gameplay.js
python3 tools/archive/verify_archive.py
```

`tests/hosting/smoke_host.py` uses synthetic assets and temporary state. Multiplayer/gameplay
tests need the local game archive/catalog and use isolated player saves.
`tools/archive/verify_archive.py` checks the archived manifest, not every file generated by
later native converters. No test needs your real Discord secret or uploads
game data. Native numerical fixtures and build checks are documented alongside
the native code; successful builds alone do not prove full gameplay parity.
