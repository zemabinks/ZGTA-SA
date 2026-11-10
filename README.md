# ZGTA:SA

A local-only preservation workspace for the public browser game at
[play.samp.directory](https://play.samp.directory/), following the separation
of code and local game content used by ZGTAIV.

The website mirror and all downloaded game assets live in `local-only/`, which
Git ignores. This repository contains archival tools and notes only. The
original site is a live multiplayer service; its account, world, and other
server APIs are not captured by static file downloads. A complete, working
offline game therefore cannot be claimed from a static snapshot.

The 10 November 2026 snapshot has **2,126 verified files (941,058,647 bytes)**,
including the site's four linked language variants, its companion 3D map, and
the service worker's offline resources. The archive includes 271 world
textures, 250 high-detail textures, all 212 vehicle thumbnails, and the HUD
and sound files observed during Chrome testing. The count can grow as the local
server caches more public assets on first use.
The local manifest records **62 unavailable URLs**, mostly world breakage
files that the source returned as 404. The original server has no public file
index, so the manifest is an audit of discoverable assets, not proof that every
server file was copied.

Run `python3 archive_site.py` to continue downloading public files. The
archiver records each successful file with its URL, byte length, and SHA-256
hash in `local-only/manifest.json`. It can be rerun to resume interrupted work.
Run `python3 verify_archive.py` to check the downloaded files against that
manifest. Do not add `local-only/` to Git.

Run `node serve_local.js` and open `http://127.0.0.1:8765/` in a browser with
working WebGL. The server reads the local asset copy. It forwards `/api/` HTTP
and WebSocket traffic to the original site's live service, so multiplayer
needs an internet connection and that service to remain available.
If a public game asset is absent locally, the server downloads it from the
original site, saves it under `local-only/site/`, and adds its hash to the local
manifest. That first use needs internet; subsequent uses read the cached file.
Links to pages outside this archive open the original website.

## Connected multiplayer

Double-click `ZGTA-SA Connected.command` in Finder, or run
`zsh launch_connected.sh` in Terminal. It opens a separate Chrome profile at
`https://play.samp.directory/`, maps only that hostname to this Mac's local
HTTPS mirror, and keeps the original site's API and WebSocket connections
proxied to the live service. Sign in with Discord **in that separate window**;
the existing Chrome profile's login cannot be copied to it. Keep the Terminal
window open while playing; press Ctrl-C there to stop the local server. If the
Chrome window closes, run the launcher again to reopen it.
On a fresh GitHub checkout, run `chmod +x 'ZGTA-SA Connected.command'` once
before double-clicking it; this Mac's local copy is already executable.

The launcher generates a certificate and key under `local-only/`, and pins
that certificate only in its separate Chrome profile. It does not change Mac
DNS, the system trust store, or the normal Chrome profile. Requests to
`play.samp.directory`, including its session cookie, pass through the local
proxy in memory. The Discord callback stays on the publisher's real
`samp.directory` site; only `play.samp.directory` is mapped to this Mac. No
cookie or OAuth code is written to the archive or logs. The separate Chrome
profile, which stores its own login, also stays under `local-only/`. The
original multiplayer server remains
necessary; this is not an independent or offline multiplayer server.

Before a Discord sign-in, the connected mode passed a Chrome page-load test,
an HTTPS API test, and a WebSocket upgrade test. Authenticated multiplayer
still needs a sign-in and an in-game check in that dedicated window.

For a route that does **not require Discord**, open
`http://127.0.0.1:8765/tools/world` or choose **Solo free roam (no Discord)**
from the local welcome screen. This archives the publisher's separate
[3D map tool](https://samp.directory/tools/world), which lets one person fly,
walk, and drive around San Andreas. It is not the multiplayer game: it has no
shared players, jobs, or live economy. It still requires a browser with WebGL.
The local world rendered in Chrome during testing. Fly, on-foot, vehicle
selection, and the vehicle image were checked in the browser. The local HTTP
server also passed page, service worker, texture, and byte-range checks.

The original welcome screen has a **Play** button that dismisses its Discord
prompt, but the live WebSocket then sends a login request to an unsigned
visitor. Replacing the Discord OAuth link with a Discord server invite would
not authenticate the player. Independent play of the full game would require
a compatible local game server, which is not present in the public website
files.

Signing in on the original site makes its multiplayer world playable there,
but the login does not carry over to `127.0.0.1`. Chrome scopes the site's
session cookie to the original domain. The plain localhost mirror renders the
world but remains unsigned; use the connected launcher to sign in under the
original domain while serving the local copy.

The local welcome dialog also shows [ZGTA:SA community Discord](https://discord.gg/Cg39cguVUa).
That link is a community invite. The original site's login opens its own site
in a new tab; signing in there does not authenticate the local mirror.

This is an unofficial local archive. Grand Theft Auto: San Andreas and its
assets remain the property of their respective owners. No copied site files
or game data are intended for publication in this repository.

