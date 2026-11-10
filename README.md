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

The connected mode passed a Chrome page-load test, an HTTPS API test, and a
WebSocket upgrade test. On 10 November 2026, after signing in in the dedicated
window, the player name and live chat were reported visible. Chrome maintained
a connection to the local server while that server maintained a connection to
the original live service. This verifies the connected sign-in and multiplayer
path; individual jobs, vehicles, and economy actions were not all tested.

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

## Independent self-hosted mode

Double-click `ZGTA-SA Self-Hosted.command` in Finder, or run
`zsh launch_selfhost.sh` in Terminal. It opens `http://127.0.0.1:8766/`.
Keep the Terminal window open while playing; Ctrl-C stops the local server.
The server uses the archived game client and assets on this Mac. It does not
forward API, WebSocket, or missing-asset requests to the original site. It
creates local player accounts automatically, with no Discord login. Names and
settings are saved in ignored `local-only/selfhost/players.json`; type
`/name Your Name` in chat to change a local name.

This is a **work-in-progress independent server**. Two loopback clients were
tested exchanging player state and chat. The archived browser client also
reached its local welcome screen and showed a local player name and chat.
The server currently implements account creation, settings, player-position
messages, chat, and the player list. The original service's jobs, economy,
garage, property, races, vehicles, combat, administration, and other server
systems still need their own implementations. Their public browser code does
not contain the original server logic or database. The 3D map and solo mode
remain available from the local archive. Do not describe this mode as a full
replacement for the original game yet.

### Host from this Mac over LAN

Double-click `ZGTA-SA Share.command` or run `zsh launch_share.sh lan` in
Terminal. The launcher finds this Mac's `en0` IPv4 address, starts **one**
independent server on port 8766, and prints its LAN URL. On the current network
the URL is `http://192.168.178.33:8766/`; it can change when the Mac changes
networks. Open that URL on a second device on the same home network. The first
visit shows a join screen. The access code is in
`local-only/selfhost/join-code.txt` on this Mac. Share it privately with the
people joining your game. The file is created with owner-only permissions and
is ignored by Git. To change the code, stop the server, delete that file, and
start the launcher again; everyone will need the new code.

Keep the Terminal window open while hosting. Ctrl-C stops the server. If
another local server is already using port 8766, stop it before starting the
share launcher. The Mac firewall is currently off; if you enable it, allow
incoming connections to Node for LAN play. This LAN link uses plain HTTP, so
use it only on a trusted home network and do not forward port 8766 through the
router to the public internet. The game files continue to be served from
`local-only/` on this Mac; nothing in that directory goes to GitHub.

The LAN route passed a join redirect, wrong-code rejection, successful
join-cookie, game-page, and WebSocket upgrade test. A local Chrome browser also
connected as one player after the LAN server started. These checks establish
the connection path; a second physical device and full game systems have not
been verified yet. The independent server still has the feature limits above.

For private access from outside the home network, `zsh launch_share.sh both`
can also add Tailscale Serve on HTTPS port 8443 **if Tailscale is connected**.
People joining that address must belong to the same tailnet. The launcher
checks for an existing service on port 8443 before changing it and leaves
other Tailscale routes alone. This optional route has not been enabled for this
project. A publicly accessible internet link needs a separate deployment and
security review.

The default `launch_selfhost.sh` server binds only to `127.0.0.1`. The share
launcher sets `BIND_HOST`, a long access code, and `ZGTA_ALLOWED_HOSTS`; its
source files can be kept on GitHub because `local-only/` remains Git-ignored.
On a fresh GitHub checkout, run `chmod +x 'ZGTA-SA Self-Hosted.command'`
before double-clicking it; this Mac's local copy is already executable.

This is an unofficial local archive. Grand Theft Auto: San Andreas and its
assets remain the property of their respective owners. No copied site files
or game data are intended for publication in this repository.

