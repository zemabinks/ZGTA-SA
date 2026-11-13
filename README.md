# ZGTA:SA

A local-only preservation workspace for the public browser game at
[play.samp.directory](https://play.samp.directory/), following the separation
of code and local game content used by ZGTAIV.

The website mirror and all downloaded game assets live in `local-only/`, which
Git ignores. This repository contains archival tools, an independent server,
and original local gameplay UI code. The
original site is a live multiplayer service; its account, world, and other
server APIs are not captured by static file downloads. A complete, working
offline game therefore cannot be claimed from a static snapshot.

The 11 November 2026 snapshot has **2,728 verified files (999,510,957 bytes)**,
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
not authenticate the player. The independent server below provides local
accounts and a growing set of gameplay systems. The publisher's complete
server implementation is not present in the public website files.

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
The launchers derive a vehicle and property catalog from the archived browser
bundles with `extract_client_catalog.py` before starting the server. The
catalog, like the game client and assets, stays under ignored `local-only/` on
this Mac. The server does not
forward API, WebSocket, or missing-asset requests to the original site. It
creates local player accounts automatically, with no Discord login. Names,
settings, cash, XP, owned cars, owned homes, and an active job are saved in
ignored `local-only/selfhost/players.json`; type `/name Your Name` in chat to
change a local name.

Self-hosted pages turn off the archived client's built-in tips, which describe
publisher-only features and an unrelated Discord reward. F6 provides the
ZGTA:SA community invite, and `/discord` in chat shows it too. Joining that
community is optional. The only local Discord bonus is the one described
below, when the host configures account linking.

Optional Discord account linking is available when the host supplies a
[Discord developer application](https://docs.discord.com/developers/topics/oauth2)
and a callback URL. Create `local-only/selfhost/discord-oauth.json` on the Mac:

```json
{
  "clientId": "YOUR_APPLICATION_ID",
  "clientSecret": "YOUR_APPLICATION_SECRET",
  "redirectUri": "https://YOUR_HOST/api/local/discord/callback"
}
```

Keep this file private (`chmod 600 local-only/selfhost/discord-oauth.json`)
and restart the server. The callback URL must be registered in the app's
OAuth2 settings and must use the same host where players begin linking.
Loopback `http://127.0.0.1` is also supported for local testing. The current
plain HTTP LAN URL does not enable Discord linking. When configured, the F6
panel offers a voluntary `identify`-only link. A verified Discord identity
receives a one-time $500 local bonus; returning with the same identity opens
its linked account. Guest progress is not merged into a different linked
account. Tokens and the client secret are not stored in player data. The
mocked OAuth test passes, but a live Discord sign-in has not been tested
because no application credentials or public callback URL have been provided.

Press **F6** in the game to open the ZGTA:SA local gameplay panel. It offers
ten independent local activities: courier, taxi, mechanic, medic, a timed
street trial, a police patrol, pizza delivery, freight delivery, pilot flight,
and a getaway car mission.
Courier is a staged mission: collect a package where you start,
then travel to a real property entrance from the archived map catalog and
deliver within 12 meters. Taxi is a staged fare: own a car, drive to a property
entrance for pickup, then drive to a different entrance for drop-off. Pickup
and drop-off both require the player to be driving within 12 meters. Mechanic
spawns a damaged roadside car at a property entrance; reach it and repair it
on foot. Medic spawns an ambulance; drive to a patient pickup point and return
to the starting aid station. The time trial requires an owned car and three
property checkpoints within three minutes. The patient and taxi passenger do
not yet appear as characters. Pizza delivery spawns a reserved Pizzaboy
scooter and sends its driver to three ordered property entrances within six
minutes for $400 and 80 XP. The route, scooter, and completed stops recover
after a server restart; an expired route is discarded. The archived client
lists a pizza job and Pizzaboy vehicle, but these delivery rules are original
to this local server. Freight delivery spawns a reserved Mule truck near the
player. Drive to a cargo pickup, then deliver to a second property entrance
within seven minutes for $500 and 100 XP. The cargo stage and truck return
after a server restart; an expired route is discarded. The archived client's
help describes trucker work and a Mule, while this server uses its own route
and payment rules. Two members of the same private group can earn a one-time
$100 and 20 XP convoy bonus each when their marked Mules are within 80 meters
of the same delivery destination as one member finishes. The bonus survives a
restart and cannot be claimed twice for one route. Pilot flight loans a Dodo
at the nearest of four archived airport hangars. Climb at least 35 meters
above the departure hangar, then land and hold still for two seconds at the
next hangar within ten minutes for $700 and 140 XP. The server checks the
marked aircraft, altitude, destination, speed, and timer. The stage survives
a restart, but the two-second landing hold starts over. This route and reward
are local rules; the archived client help only confirms the four-airport
flight concept. In the getaway mission, take a spawned car at a
property entrance and deliver that same car to a second property within five
minutes. Taking it starts a wanted level. The mission car is visible to other
players but reserved for the mission owner, and an unfinished mission returns
after a server restart. An objective box shows the destination,
distance, and compass direction while the panel is closed. F6 shows a route
map with the player's current position and the active mission, race,
territory, or tracked exploration target. Its radar image is served only
from the Mac's ignored local asset archive. These are independent local
substitutes, not the publisher's job missions. The panel sells three inexpensive starter cars,
the ground vehicles, and fourteen priced aircraft listed in the archived client catalog.
Aircraft can be bought and spawned within 100 meters of a hangar that lists
that model; the panel shows the nearest hangar. An owned vehicle
can be spawned nearby and driven. Its last reported position, health, and
damage are saved per garage slot. Active cars return after a server restart;
you can recall a car beside you, or stand within 18 meters to store or repair
it. Repairs cost at least $50, based on condition. Client driving updates can
lower saved vehicle health but cannot raise it; repairing requires the paid
garage action. When standing near an active owned car, F6 can also respray it
for $120. The new paint code is sent with the shared vehicle and survives a
restart; its 3D appearance has not yet been checked in Chrome.
This local garage does not reproduce the publisher's storage buildings, other
tuning, or fuel rules. The panel
sells two starter homes and the 29
properties listed in the archived client catalog. A purchased original
property can be visited at its world entrance. Property interiors and garage
buildings are not implemented. The client shows owned-house markers; its house
entry prompt reports that interior actions are unavailable. A Chrome test of
the extracted interior coordinates rendered an empty void, so interior entry
is not enabled.

The F6 panel also offers a separate multiplayer race. A host opens a lobby
near other players, starts once at least two have joined, and each racer gets
a temporary Manana. Racers drive through three shared property checkpoints
within five minutes. First place earns $600, second $400, and later finishers
$250; completed races and wins are saved to each account. F6 shows saved race
standings ranked by wins, then finishes. The lobby, active race, and temporary
cars are session state and do not survive a server restart. This independent
race has no 3D checkpoint rings. Chat commands
`/jobs`, `/job courier`, `/job taxi`, `/job mechanic`, `/job medic`, `/job trial`, `/job patrol`, `/job pizza`, `/job trucker`, `/job carthief`,
`/pickup`, `/checkpoint`, `/repair`, `/finish`, `/deliver`, `/balance`, `/garage`, `/buycar 410`,
`/spawncar 1`, `/storecar 1`, `/repaircar 1`, `/respraycar 1`, and `/buyhome starter`
expose the same local systems. Type `/race` for the multiplayer race commands.

The independent combat layer tracks health, armour, kills, deaths, and a wanted
level. Nearby player hits apply simplified server damage and send a kill feed.
Passive mode blocks player damage; turning it off starts a two-minute cooldown.
Wanted levels decay over time. A player on volunteer police duty can arrest a
wanted player when both are on foot within four metres, clearing the wanted
level and charging a small fine. F6 shows these controls and nearby suspects.
While on police duty, a player can start a patrol. The server spawns a marked
police car; drive it through three ordered property checkpoints within four
minutes to earn $400 and 80 XP. A patrol in progress and its route survive a
server restart; the loaner returns to its starting position. You cannot leave
police duty until the patrol is finished or cancelled. This is an independent
mission and does not reproduce the publisher's police jobs.
The server rejects shot origins far from the shooter and hits far from the
reported impact point. The rules still use client reported positions and do
not provide authoritative line of sight, weapon inventory, police NPCs, or the publisher's original combat
system. Type `/wanted`, `/passive`, `/police`, or `/arrest NUMBER` in chat.

F6 also offers three local crews and three property based territories. Join a
crew, stand on foot near a territory, and hold a capture for 30 seconds. A
rival crew member nearby pauses the capture. The owning crew and player rewards
are saved on this Mac; an active capture ends when the server stops. Changing
crews has a ten-minute cooldown. These are original local rules. They do not
reproduce the publisher's gang missions or territory system.
The F6 panel also lists the top ten local players by XP and lets nearby
players give each other cash. The server checks the amount, sender balance,
and an eight-metre distance before moving funds. Item trading and publisher
businesses are not included.

F6 now supports private groups of up to four online players. A leader can
invite or remove members; an invite lasts one minute. Group messages reach
only group members through the local game's notification feed. Type `/party`
in chat for invitation and membership commands, or `/p MESSAGE` for a private
group message. Groups are session state and end after the server restarts.
Two separate browser sessions verified an invitation, shared membership,
and delivery of a private group message.
This is an independent social feature, not the publisher's party system.

F6 also has a twelve-location exploration trail through Los Santos, San
Fierro, Las Venturas, and the countryside. Track a location to see its
distance and compass direction, then stand on foot within 12 metres to
discover it. Each location pays $75 and 20 XP once; finding all twelve gives
another $500 and 100 XP. Progress and the tracked location are saved on this
Mac. Type `/explore` for chat commands. These property-entrance stops are
original local objectives, not the publisher's collectible locations; they
have no 3D pickup model yet.

This is a **work-in-progress independent server**. It supports local accounts,
settings, walking and driving player positions, passenger state, live chat,
player list, job payouts, cash, vehicle ownership, spawning, condition,
storage, repair, a multiplayer race, simplified combat and wanted levels,
volunteer arrests, local territory capture, nearby cash transfers, private
groups, an exploration trail, and a local leaderboard, plus
property ownership and exterior visits. The extracted catalog contains 212
vehicle definitions, of which 110 have listed prices. Purchases use this
independent server's cash balance and the archived hangar list for aircraft;
other publisher dealer rules and the original economy are unavailable. The original service's job missions, economy rules,
property interiors, the publisher's race formats and combat and gang rules,
administration, and other
server systems still need independent implementations. The browser download
does not include the original server logic or database. The 3D map and solo
mode remain available from the local archive.
See [FEATURE_MATRIX.md](FEATURE_MATRIX.md) for the current implementation and
verification status of each major system.

Run `node smoke_multiplayer.js`, `node smoke_gameplay.js`,
`node smoke_gangs.js`, `node smoke_parties.js`, `node smoke_explore.js`,
`node smoke_patrol.js`, `node smoke_pizza.js`, `node smoke_trucker.js`,
`node smoke_pilot.js`, `node smoke_convoy.js`, and `node smoke_aircraft.js`
with Node.js 24 to
test the local wire protocol, two-player exchange, courier pickup and delivery,
taxi and medic pickup and drop-off with driving requirements, mechanic roadside
repair, timed checkpoints, police patrol, pizza delivery, freight delivery, and pilot flight
in marked loaners, shared convoy rewards and hangar aircraft ownership,
getaway car pickup and delivery, mission vehicle cleanup, two-client visibility and
entry restrictions, owned car storage, repair, paid respray, restart persistence, and a
two-player race with ordered checkpoints and payouts, player combat, kill feed,
wanted levels, passive mode, volunteer arrests, territory capture and contests,
cash transfers, leaderboard ranking, group invitations, private chat privacy,
vehicle spawning and entry, starter and archived catalog purchases, property
exterior teleportation, persistence, and car ownership after
reconnect. The gameplay test also checks that static asset requests do not
create extra player accounts. The tests use isolated temporary servers and leave saved players
untouched. Chrome was also used to load the actual archived client, walk a
courier route, claim its payout in the HUD, buy and spawn a Manana, enter it,
and drive it in the 3D world. A later Chrome check started and cancelled the
mechanic and medic missions, displayed their objectives, and showed the medic
ambulance beside the player. The full new routes were exercised by the
isolated gameplay test, not by driving them in Chrome. Chrome also created and
cancelled a race lobby in the F6 panel; the complete race was exercised by
two protocol test clients. Chrome verified exploration tracking and clearing
in F6. It also loaded the route map with the archived radar image, showed
both live player and target markers, and removed the map after untracking;
the twelve discovery payouts were checked in an isolated test. LAN access checks
passed, but a second physical device and all original game systems have not
been verified.
Chrome also started and cancelled the getaway mission, showing its destination
and countdown in F6. The complete route and restart restoration were exercised
by isolated gameplay clients; it has not yet been driven end to end in Chrome.
Chrome also entered the 3D world, started a police patrol, showed the spawned
police car and live objective, then cancelled the patrol and ended duty. The
full patrol route and restart recovery passed an isolated test; it has not
yet been driven end to end in Chrome.
Chrome also started pizza delivery, showed the Pizzaboy scooter and first
route objective, entered driving mode, and cancelled the mission. The three
deliveries, payout, and restart behavior passed an isolated test; the full
route has not been driven in Chrome.
Chrome also started a freight delivery, displayed its F6 route map and timer,
showed the spawned Mule in the 3D world, entered its driving mode, and then
cancelled the mission. Pickup, delivery, payout, and restart behavior passed
the isolated freight test; the full route has not been driven in Chrome.
Chrome also started a pilot flight at Los Santos International, displayed the
loaner Dodo in the 3D world, entered it, and cancelled the flight. Takeoff,
landing, payout, and restart behavior passed the isolated pilot test; the full
flight has not been flown in Chrome. Hangar purchase, aircraft spawn, access
restrictions, and restart recovery passed an isolated test; a purchased
aircraft has not been spawned in Chrome.
Run `node smoke_discord.js` for an isolated mocked OAuth, identity, one-time
bonus, and returning-account test. It makes no Discord network request.

### Host from this Mac over LAN

Double-click `ZGTA-SA Share.command` or run `zsh launch_share.sh lan` in
Terminal. The launcher finds this Mac's `en0` IPv4 address, starts **one**
independent server on port 8766, and prints its LAN URL. On the current network
the address can change when the Mac changes networks. Open the printed URL on
a second device on the same home network. The first visit shows a join screen.
The launcher also prints the private join-code file location on this Mac.
Share the code privately with the people joining your game. The file is created with owner-only permissions and
is ignored by Git. To change the code, stop the server, delete that file, and
start the launcher again; everyone will need the new code.
On a fresh GitHub checkout, run `chmod +x 'ZGTA-SA Share.command'` once before
double-clicking it; this Mac's local copy is already executable.

Keep the Terminal window open while hosting. Ctrl-C stops the server. If
another local server is already using port 8766, stop it before starting the
share launcher. The Mac firewall is currently off; if you enable it, allow
incoming connections to Node for LAN play. This LAN link uses plain HTTP, so
use it only on a trusted home network and do not forward port 8766 through the
router to the public internet. The game files continue to be served from
`local-only/` on this Mac; nothing in that directory goes to GitHub.

The LAN route passed a join redirect, wrong-code rejection, successful
join-cookie, game-page, local asset byte-range, and WebSocket upgrade test.
Chrome connected as one player, entered on-foot mode, moved, chatted, and
showed the player list while the LAN server ran. A second physical device has
not been verified yet. The independent server still has the feature limits
above.

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

