# ZGTA:SA

A local-only preservation workspace for the public browser game at
[play.samp.directory](https://play.samp.directory/), following the separation
of code and local game content used by ZGTAIV.

The website mirror and all downloaded game assets live in `local-only/`, which
Git ignores. This repository contains archival tools and notes only. The
original site is a live multiplayer service; its account, world, and other
server APIs are not captured by static file downloads. A complete, working
offline game therefore cannot be claimed from a static snapshot.

The 10 November 2026 snapshot has **1,387 verified files (626,373,513 bytes)**,
including the site's four linked language variants, its companion 3D map, and
the service worker's offline resources.
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

For a route that does **not require Discord**, open
`http://127.0.0.1:8765/tools/world` or choose **Solo free roam (no Discord)**
from the local welcome screen. This archives the publisher's separate
[3D map tool](https://samp.directory/tools/world), which lets one person fly,
walk, and drive around San Andreas. It is not the multiplayer game: it has no
shared players, jobs, or live economy. It still requires a browser with WebGL.
The local page and its scripts loaded in a browser test; that test browser had
WebGL disabled, so rendering and controls could not be verified there.

The original welcome screen has a **Play** button that dismisses its Discord
prompt, but the live WebSocket then sends a login request to an unsigned
visitor. Replacing the Discord OAuth link with a Discord server invite would
not authenticate the player. Independent play of the full game would require
a compatible local game server, which is not present in the public website
files.

The local welcome dialog also shows [ZGTA:SA community Discord](https://discord.gg/Cg39cguVUa).
That link is a community invite. The original site's login opens its own site
in a new tab; signing in there does not authenticate the local mirror.

This is an unofficial local archive. Grand Theft Auto: San Andreas and its
assets remain the property of their respective owners. No copied site files
or game data are intended for publication in this repository.

