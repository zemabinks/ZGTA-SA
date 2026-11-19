# Development notes and earlier validation

These records describe earlier checkpoints and may be superseded by newer
source and validation. For current installation use HOSTING.md and NATIVE_BUILD.md;
for current coverage use FEATURE_MATRIX.md.

The project also maintains a local preservation workspace for the browser game at
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

Run `python3 tools/archive/archive_site.py` to continue downloading public files. The
archiver records each successful file with its URL, byte length, and SHA-256
hash in `local-only/manifest.json`. It can be rerun to resume interrupted work.
Run `python3 tools/archive/verify_archive.py` to check the downloaded files against that
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
bundles with `tools/assets/extract_client_catalog.py` before starting the server. The
catalog, like the game client and assets, stays under ignored `local-only/` on
this Mac. The server does not
forward API, WebSocket, or missing-asset requests to the original site. It
creates local player accounts automatically, with no Discord login. Names,
settings, cash, XP, owned cars, owned homes, and an active job are saved in
ignored `local-only/selfhost/players.json`; type `/name Your Name` in chat to
change a local name.

For LAN play, run `zsh launch_share.sh lan`. The same listener serves friends on
the LAN and the Mac's `127.0.0.1` address, so the browser and native simulator
share one world and one saved player file. A second server process using that
file is rejected to prevent competing saves. Local guest cookies persist across
browser restarts, and the native app keeps a separate guest identity per server.

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
twelve independent local activities: courier, taxi, mechanic, medic, a timed
street trial, a police patrol, pizza delivery, freight delivery, pilot flight,
fire response, a getaway heist, and a getaway car mission.
Courier is a staged mission: collect a package where you start,
then travel to a real property entrance from the archived map catalog and
deliver within 12 meters. Taxi now gives a new guest a marked cab with no
car purchase required. Drive it to an archived property entrance for pickup,
then to a second entrance for drop-off. Both stops require the same cab
within 12 meters. The fare pays $300, plus a local $75 clean ride bonus when
the reported cab condition stays at 95% or better, $50 for a quick ride, and
up to $250 for consecutive fares completed within ten minutes of each other.
F6 shows the base fare, time window, condition, and streak. Every three completed
fares unlocks a local taxi level. At level 8 a Cabbie can earn an extra $75 per
fare; at level 20 a limousine can earn an extra $200. Select either cab in F6.
The cab choice, fare count, and streak survive a restart; cancelling a fare
breaks the streak. After each drop-off, another pickup appears and the same cab
stays with the driver until the shift is ended in F6. Get out of the cab before
ending the shift so the archived client removes it from the world. A shift in progress and
its completed-fare count survive a server restart. These levels and premiums
are local rules. A passenger character, cab rank, mood meter, upgrades, and
publisher fare rules are not implemented. The archived client's “press 2 to
start a shift” tip still appears inside the cab; use F6 for this local shift.
Mechanic spawns a damaged roadside car at a property entrance. Stand on foot within
8 meters to repair its engine, tyres, then bodywork, three seconds per stage.
Leaving the car resets the current stage. The job pays automatically when
all three stages are done, and finished stages survive a server restart.
These stage names come from the archived client help; the timing and automatic
payout are local rules. Medic spawns a reserved ambulance; drive that ambulance
to a patient pickup point and return to the starting aid station. The time trial requires an owned car and three
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
a restart, but the two-second landing hold starts over. Completing a flight
adds to a saved pilot record. This server pays an extra $150 for a reported
clean aircraft, $100 with at least two minutes left, and $500 on every fifth
consecutive completed flight. Cancelling a flight breaks the streak. These
amounts and the route are local rules; the archived client help describes
the bonus types and four-airport flight concept without supplying the server
formula. Every three completed flights adds one local pilot level, up to 50.
F6 offers the Dodo, Beagle, Maverick, Shamal, Nevada, Leviathan, AT-400, and
Andromada at the unlock levels shown in the archived help. Larger aircraft
have wider landing zones and local model pay premiums. The loaner aircraft
and unlocked selection survive a mission restart. Fire response spawns a reserved fire truck near the player and
dispatches a call to an archived property entrance. Drive the truck to the
call, use F6 to suppress three nearby fire spots from the truck or on foot,
then get out and rescue a person at the call point within eight minutes for
$650 and 130 XP. The mission stage and truck recover after a restart. The
public client describes firefighting, but this local mission has no 3D flames,
water cannon interaction, extinguisher model, or rescue character yet.
Getaway heist spawns a reserved Sultan. Visit a local robbery site at an
archived property entrance and collect the bag on foot; this raises wanted
level to two. Lose the police, then drive the marked car to the drop-off
within ten minutes for $900 and 180 XP. Up to three private-group members
present when the bag is taken can each earn $200 and 40 XP if they remain
near the final drop-off; the leader earns the same bonus. The robbery starts
a five-minute repeat cooldown. Death or arrest after taking the bag fails
the mission. The route, cooldown, and bag stage survive a server restart.
This local heist does not reproduce the publisher's 24/7, bank, casino,
interior, guard, or bag-model systems. In the getaway car mission, take a spawned car at a
property entrance and deliver that same car to a second property within five
minutes. Taking it starts a wanted level. The mission car is visible to other
players but reserved for the mission owner, and an unfinished mission returns
after a server restart. An objective box shows the destination,
distance, and compass direction while the panel is closed. A compact in-world
waypoint badge also points to the target and shows its distance; clicking it
opens F6. F6 shows a route
map with the player's current position and the active mission, race,
territory, or tracked exploration target. Its radar image is served only
from the Mac's ignored local asset archive. These are independent local
substitutes, not the publisher's job missions. The panel sells three inexpensive starter cars,
the ground vehicles, and fourteen priced aircraft listed in the archived client catalog.
Archived ground vehicles must be bought within 100 meters of a dealership
that lists the selected model. F6 shows the nearest dealership and marks
models unavailable there. Starter cars remain available anywhere as a local
onboarding choice.
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
Ground dealerships also sell local workshop supplies: a $125 repair kit and
a $100 paint can, up to five of each. On foot beside an active owned car,
the kit restores its condition and the can changes its paint. Either item
can be handed to another on-foot player within 8 meters. Counts, ownership,
and transfers are checked by the server and saved across restarts. These
supplies are local features, not copied publisher inventory rules.
An owned property with an exterior has two local parking spaces. Bring an
owned ground vehicle to within 25 meters of that exterior, leave it, and
park it through F6. The car disappears from the shared world and keeps its
condition and paint through a restart. It can only be retrieved at that
property. This is exterior parking, not an interior garage or the
publisher's storage system. Fuel and other tuning rules remain unavailable.
The panel sells two starter homes and the 29 properties listed in the archived
client catalog. A purchased original
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
race has no 3D checkpoint rings.

During the local time trial, police patrol, pizza delivery, and multiplayer
race, a driver who reaches the active checkpoint triggers the F6 checkpoint
action automatically. The server still checks route order, distance, time,
and the marked mission vehicle when required. Other missions keep their
explicit pickup, robbery, rescue, or delivery actions.
Chat commands
`/jobs`, `/job courier`, `/job taxi`, `/job mechanic`, `/job medic`, `/job trial`, `/job patrol`, `/job pizza`, `/job trucker`, `/job pilot`, `/job pilot 511`, `/job fire`, `/job heist`, `/job carthief`,
`/pickup`, `/checkpoint`, `/repair`, `/respond`, `/extinguish`, `/rescue`, `/rob`, `/finish`, `/deliver`, `/balance`, `/garage`, `/buycar 410`,
`/spawncar 1`, `/storecar 1`, `/repaircar 1`, `/respraycar 1`,
`/supplies`, `/buykit`, `/usekit 1`, `/givekit 2`, `/buypaint`,
`/usepaint 1`, `/givepaint 2`, and `/buyhome starter`
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
See [FEATURE_MATRIX.md](../FEATURE_MATRIX.md) for the current implementation and
verification status of each major system.

Run `node tests/server/smoke_multiplayer.js`, `node tests/server/smoke_gameplay.js`,
`node tests/server/smoke_gangs.js`, `node tests/server/smoke_parties.js`, `node tests/server/smoke_explore.js`,
`node tests/server/smoke_patrol.js`, `node tests/server/smoke_pizza.js`, `node tests/server/smoke_trucker.js`,
`node tests/server/smoke_pilot.js`, `node tests/server/smoke_fire.js`, `node tests/server/smoke_heist.js`,
`node tests/vehicles/smoke_convoy.js`, `node tests/vehicles/smoke_aircraft.js`,
`node tests/server/smoke_property_garage.js`, `node tests/server/smoke_supplies.js`,
`node tests/server/smoke_mechanic_stages.js`, and `node tests/server/smoke_taxi.js` with Node.js 24.
Run `node tests/ui/smoke_route_ui.js`
for the browser-side waypoint and automatic-checkpoint gates. These checks
test the local wire protocol, two-player exchange, courier pickup and delivery,
taxi and medic pickup and drop-off with assigned-vehicle requirements, staged mechanic
roadside repair, timed checkpoints, police patrol, pizza delivery, freight delivery,
pilot flight, fire response, and a heist route
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
isolated gameplay test, not by driving them in Chrome. Chrome also started a
guest taxi fare at $0, showed the F6 fare meter and route, displayed the 3D
cab after reentering the game, entered and drove it. A later check showed
F6 disabled End shift while seated; after exiting, ending the shift removed
the cab from the 3D world. The full fare and level-unlocked cabs were checked in isolated tests, not driven
in Chrome. Chrome also created and
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
landing, bonus and streak payout, and restart behavior passed the isolated pilot test; the full
flight has not been flown in Chrome. Hangar purchase, aircraft spawn, access
restrictions, and restart recovery passed an isolated test; a purchased
aircraft has not been spawned in Chrome.
Chrome also started a fire response, displayed the 3D fire truck beside the
player, entered it, showed the call route and countdown in F6, and cancelled
the call. The dispatch, three suppression steps, rescue, payout, and restart
behavior passed an isolated test; the route has not been driven in Chrome.
The archived client still displays its native “press 2 to start a shift” tip
inside the fire truck. This local mission is controlled through F6 instead.
Chrome displayed the pilot aircraft selector with level locks and started a
heist, showed its route and marked Sultan, entered the Sultan, and cancelled
the mission. The robbery, wanted escape, group bonus, death, arrest, cooldown,
and restart checks passed an isolated test. The full heist route has not been
driven in Chrome.
Run `node tests/server/smoke_discord.js` for an isolated mocked OAuth, identity, one-time
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

### Native iPhone preview

The ios/ Xcode project is a native Swift, UIKit, Metal, and GameController
client. It does not embed a web view or any archived game files. Its menu uses
the newer ZGTA V Native layout language with original San Andreas themed art.
It fetches WRL2 world meshes, SCL2 collision meshes, and locally converted
texture atlases from your Mac. It also loads locally converted San Andreas DFF
character and vehicle geometry with TXD textures. Metal renders the scene;
the iPhone sends movement and vehicle state to the same independent local
multiplayer server used by the self-hosted browser game. Discord is not needed.
Local guest accounts survive app restarts and stay separate for each Mac server
address. The app stores the guest token in Keychain when available; unsigned
Simulator builds use app preferences when Keychain is unavailable.

On this Mac, prepare the ignored local game files once:

    python3 prepare_native_assets.py --all-details
    python3 archive_public_models.py
    python3 prepare_native_models.py --all
    python3 prepare_native_skeletons.py --all --archive-all-blocks
    python3 archive_public_audio.py
    python3 archive_public_interiors.py
    python3 prepare_native_assets.py --all-details
    python3 prepare_native_hud.py
    python3 prepare_native_audio.py
    python3 prepare_native_environment.py
    python3 prepare_native_atmosphere.py
    python3 prepare_native_water_waves.py
    python3 prepare_native_weapons.py
    python3 prepare_native_effects.py
    node prepare_native_physics.js
    python3 prepare_native_seating.py
    node prepare_native_foot_animation.js
    zsh native-physics/build.sh all

The model archive command fetches public DFF and TXD files that are missing
from `local-only/site/game/`. It currently fills all 212 listed vehicle model
and texture pairs. The converter prepares 212 vehicle and 265 pedestrian meshes
under `local-only/site/game/native/models/`. These binaries and textures are
excluded from GitHub by `.gitignore`.
`tools/assets/extract_client_catalog.py` also recovers the archived client's 212 per-model
handling rows and writes them to the ignored
`local-only/site/game/native/handling.json`. The native client fetches that
table from the Mac. Ground cars/trailers now use a literal translation of the
original custom solver and a native Rust Rapier bridge built from the engine
commit behind the archived WASM. Metadata extraction executes the original DFF
parser, wheel stance, handling and chassis builder for all 212 models, including
159 ground-car/trailer chassis. Unsupported vehicle categories retain the
earlier movement path until their separate solver comparisons pass.
Hard impacts against the archived collision mesh now reduce native vehicle
health; the updated value is reported to the local multiplayer server and
saved for owned vehicles. A vehicle at zero health cannot accelerate until it
is repaired. In the simulator a taxi hit a downtown wall, the HUD reported
910/1000 health, and the server saved 910 for that mission vehicle. Collision
queries now include the front or rear bumper so the vehicle stops before its
centre reaches a wall; a second simulator impact showed the taxi stopping at
the wall with its rear still on the sidewalk.
The active animation path is runtime skeletal animation. The compact converter
prepares 265 DFF skin rigs and a shared library containing all 1,871 clips in
all 134 blocks listed by the archived animation index. Native Swift samples
ANP3 quaternion and translation tracks, composes the bone hierarchy, and sends
bone matrices to a Metal skinning vertex shader. Upper-body actions can be
layered over a separate walking or running cycle. Hand attachments use the same
runtime pose. These rigs and tracks stay under ignored local game data.
The optional `tools/assets/prepare_native_animations.py` frame baker remains as a reference
and fallback; the active app fetches a compact rig first. It no longer needs a
large per-model frame bake for normal use. The native verifier checks all 265
rigs and all 1,871 raw poses; 147,138 sampled CPU and GPU vertex comparisons
against 61 reference clips differed by at most 0.0000013741 m. This verifies
sampling and skinning, not every original animation state transition or IK rule.
Native crouch, swim, underwater, death, jump/landing, vehicle entry/exit, and gun
actions use recovered clips. The Social panel has a searchable animation picker
for the complete runtime library. Movement cancels a manually selected animation.
The HUD converter derives San Andreas font atlases and glyph metrics from the
archived font on this Mac. The derivative images remain under `local-only/`.
The native HUD loads those glyphs, the archived radar map, and weapon icons at
runtime. Tapping the radar opens a full city map. In gameplay, the ZGTA V Native
style touch buttons float over the world without a top navigation bar. On foot,
only movement, jump, sprint, combat, weapon, and nearby vehicle actions appear;
driving swaps those for enter/exit, radio, accelerator, and brake actions.
Controller triggers accelerate and brake while driving, and fire on foot.
The floating chat icon opens a native message composer. Messages and commands
use the local multiplayer WebSocket, and the newest confirmed lines appear in
the game view. Nearby mission targets have a translucent Metal checkpoint.
A contextual touch action appears only when the local server reports a usable
pickup, delivery, fire, heist, flight, or completed distance objective; the
server still validates each action.

Radio station selection is implemented natively. To play audio you provide
tracks on your Mac under `local-only/site/game/radio/custom/` as `CH.mp3`,
`CO.mp3`, `CR.mp3`, `DS.mp3`, `HC.mp3`, `MH.mp3`, `MR.mp3`, `NJ.mp3`, `RE.mp3`,
`RG.mp3`, `TK.mp3`, or `USER.mp3`; `.m4a` and `.wav` are also accepted. The
public archive has no original station streams, so station names and controls
work but original radio music is unavailable. Supply only audio you have the
right to use. These tracks also stay outside GitHub.

Start the server with zsh launch_share.sh lan for iPhone access on the same
Wi-Fi. In the iOS app, enter the LAN address and join code printed by that
launcher. For an iOS Simulator on this Mac, a loopback self-hosted server at
http://127.0.0.1:8766 also works. To regenerate the Xcode project, run
cd ios && xcodegen generate --spec project.yml, then open
ios/ZGTASA.xcodeproj.

Build optimized gameplay with `zsh build_native.sh simulator` (the default),
`zsh build_native.sh device`, or `zsh build_native.sh all`. The generated Xcode
scheme also runs Release by default. Use `--debug` or change the scheme's Run
configuration to Debug for unoptimized troubleshooting. Binaries stay under
ignored `local-only/native-build/`. Device builds from this script are unsigned;
installing on a physical iPhone requires your Xcode signing setup. See
[native build details](../../../NATIVE_BUILD.md) for the measured reason to test gameplay
with optimization enabled.

The iPhone 15 Pro simulator loaded the textured city, drew an archived
pedestrian and taxi model, displayed a baked San Andreas walk pose, walked
across the road using the archived collision mesh, entered and drove a marked
taxi, and started and advanced a courier
mission from the native Jobs panel. A second multiplayer client observed native
walking, driving, and jump height updates. The local server's taxi smoke test
also checks that a mission cab follows its driver and remains at the exit
point. Native fist combat uses the HIT touch button or the controller right
trigger. In an isolated two-player test, an iPhone simulator hit dealt 8 server
damage, incoming hits changed the native health display, and defeat and respawn
restored the server's player health to 100. A separate app restart and server
switching test returned to the same guest account without adding another player.
The PISTOL/FISTS and RELOAD touch controls equip a locally archived Colt .45,
show magazine and reserve rounds, and fire using the controller right trigger;
the controller shoulders switch weapons and reload. The simulator showed the
archived gun pose. In another isolated two-player test, firing at a player sent
the local multiplayer server a Colt .45 shot and delivered 18 damage. Shots use
the local collision mesh to reject targets behind visible walls. The native client now uses the Mac server's saved weapon inventory, with
archived shop offers, ammunition packs, slots, capacities and refill prices.
Fresh accounts start unarmed. Buy weapons or armour within eight metres of one
of the eleven archived Ammu-Nation entrances or an interior counter, then equip
them in the weapon panel. The server accepts shots only when the native account
owns the selected weapon, has ammunition and is not reloading. Native shots
report revisions so stale HTTP state cannot restore spent ammunition. Legacy
browser protocol clients retain their existing combat path; full browser
inventory synchronization is not yet implemented.
The on-foot camera and pedestrian now have separate headings: the character
faces the direction of travel instead of staying pointed at the viewer, while
the right LOOK stick or controller right thumbstick moves the camera. The
RenderWare pedestrian meshes are turned to match the world's heading axis.
Walk and run travel are scaled to the archived animation cycles, and Metal
blends adjacent baked frames. These movement changes were checked visually in
the iPhone 15 Pro simulator in forward, sideways, and camera-orbit views.
Vertical LOOK movement now raises or lowers the camera around a focus point
near the character at a slower rate. The previous fixed-eye pitch pushed the
character off screen; the simulator now keeps the full character visible at
both vertical limits.
The compact iPhone 13 mini simulator
displayed the menu. A signed
physical-iPhone build has not been verified; the generic device target compiles
unsigned.
The iPhone 15 Pro simulator also showed the new circular radar and full city
map, San Andreas bitmap HUD font, weapon icon, health, money, and compact touch
buttons after loading the independent multiplayer world. A local taxi mission
spawned a cab; entering it replaced the on-foot buttons with radio, gas, brake,
and exit, and a held gas press moved the cab about 30 m. Exiting restored the
on-foot buttons, then the test mission was ended. Simulator and generic iPhone
builds passed after the controls changed. Radio playback with a real track and
the native app on a physical iPhone still need testing.
The simulator also started a local pilot flight, entered a converted Dodo, and
climbed enough for the server to advance from takeoff to landing. The first
flight stopped at airport structures; after adjusting takeoff assist and
runway placement, a second simulator flight climbed above the port at about
160 km/h. A complete native flight and landing have not been verified. Large
airport ground triangles are now included in the native collision index so
aircraft remain on the visible runway surface.
In another simulator check, a native chat message appeared in the server echo
and the in-game feed. A courier pickup drew the Metal objective marker, and its
contextual touch button collected the package without reopening Jobs. The
objective changed to delivery; the test mission was then cancelled.
The native multiplayer client now uses the browser-compatible vehicle ID in
position updates to move a remote driver's car and suppress its old parked
copy. It also applies the parked position sent when that driver gets out.
The isolated multiplayer wire test passes; a second-device visual drive is
still needed to verify this rendering path end to end.

This remains a native gameplay work in progress. The iOS client does not yet
reproduce the browser vehicle physics exactly or expose every browser
interaction. Its native panels now show jobs,
garage and workshop supplies, the vehicle catalog, races, police and safety,
crews and territory, exploration, homes, private groups, cash transfers, and
the local leaderboard. World and Social panels were opened in the iPhone 15 Pro
simulator; individual actions there have not all been exercised end to end.
Other weapons and some job-specific controls remain absent. The local server is independent; signing in
to the original public site does not provide its private multiplayer backend.


### Additional native systems and verification, 14 November 2026

The native renderer now uses the archived 23-weather/eight-time-bin colour
interpolation for sky, fog and water, including altitude smog rules, plus the
browser's 24-minute day cycle. The shared server supplies weather and clock
settings. A 672-case executable comparison against the archived JavaScript
passed with maximum colour error below 0.00000042. Water surfaces use the 307
archived polygons; native swimming and diving use those heights, and the server
checks breath and drowning against the same data. The twenty-second breath
window and drowning damage rate are local server policies.

The model converter follows the archived default damaged/LOD/extra visibility
filter and clones stock right-front wheel geometry into the actual wheel hubs.
Native wheels use original suspension offsets, steering and accumulated axle
rotation. Full chassis orientation and DFF origin offsets pass through to
vehicle meshes and seat transforms. Driver clips are selected from the original
per-model boarding groups (cars, low cars, trucks, karts, boats and all astride
families), using the sampled pelvis to align the original seat anchor. Remote
drivers use their transmitted skin and seated pose.

The HUD uses the archived glyph advances and bold glyph mapping, original radar
sprites, map POIs, weapon icons, health, armour, breath, wanted and ammunition.
The city map supports pan, zoom, POI selection and waypoints. Native gameplay
labels and buttons use the extracted bitmap fonts; editable text stays native.
The simulator showed crouching, an AK-47, ammunition use/reload, changing evening
light and map waypoints before the compact skeletal path was integrated. The
newer combined build still needs its final visual acceptance pass; the computer
UI connection began timing out during subsequent menu testing.

All 481 native sound samples are now local, including the archived sandstorm stream decoded to PCM.
Native playback includes material-specific footsteps, gunfire, reloads, impacts,
landing, splashes, engine banks, flame/spray/foam loops and the archived layered
explosion mix. Fifty-four explosion-mix plans matched the original JavaScript.
Vehicle engine speed/throttle mixing is still approximate; original radio music
is not available from the captured station endpoint.

All 56 listed interior meshes and atlases are prepared. Fifty-five collision
cells are available; `i148.col.bin` returns HTTP 404. Owned homes can be entered
on foot near their archived exterior and exited to the saved exterior point.
Native indoor streaming selects the `i` cell set at the high-altitude property
interiors. House permission radius, exit distance and instance policy remain
local server rules, and low-altitude/interior-ID routing still needs expansion.

Grenades and satchels use the archived projectile equations, with the Mac owning
launch validation, ammunition, simulation, collision and blast damage. Native
clients reconcile projectile snapshots and draw the archived projectile models
and effect sprites. Rockets, homing and area-effect helpers exist, but they need
further end-to-end checks and acquisition paths beyond the currently extracted
shop offers. Particle composition is not a verified pixel match. The server
rejects blast hits through missing geometry and walls. No arbitrary client
explosion request is exposed.

`node tests/server/smoke_native_server.js` verifies the native inventory handshake, purchase,
throw, empty-magazine denial, shared blast damage through real clear geometry,
and saved ammunition. `node tests/combat/smoke_weapon_inventory.js`,
`node tests/combat/smoke_local_projectiles.js`, `node tests/server/smoke_world_collision.js`,
`node tests/movement/smoke_water.js`, `node tests/server/smoke_interiors.js`,
`python3 tests/rendering/smoke_native_environment.py`, and
`python3 tests/combat/smoke_native_weapon_effects.py` cover their named subsystems.
`tests/resources/smoke_native_skeletons.swift` verifies the runtime rig and GPU skinning path.
Hardware keyboard controls include WASD movement, arrows for look/pitch,
Space jump, C crouch, E vehicle, R reload/detonate, Q aim, T chat, M map,
F jobs and G animations. Keyboard/controller mappings still need physical-device
acceptance across all activities.

This remains an incomplete reconstruction. All vehicle categories, the full
pedestrian state machine and IK, traffic and ambient NPCs, all dynamic mission
actors/props, breakable world objects, every interior interaction, all weapon
and pickup behavior, and the private publisher server's rules are not yet
verified as a 1:1 native port. A successful build or helper test does not certify
those remaining systems.

Ground-car force replay passes 8,160 original frames across 17 handling scenarios
with maximum numerical error below 0.00000000000003. The integrated native engine
comparison covers 1,860 baseline frames: maximum position difference is 4.291 mm
in a suspension drop and the largest final difference is 1.439 mm. This is
behavioral verification with measured floating-point differences, not binary
identity. The native bridge and source pin/build instructions are documented in
`native-physics/README.md`; generated toolchains, libraries and reference captures
remain ignored under `local-only/`.

The public on-foot motor is translated separately from visual animation. Its
capsule contact handling, slope/step logic, jump/gravity, ceiling collisions,
vehicle pushing constraints and stair easing pass 2,100 original frames and
89,734 comparisons. `node tests/movement/smoke_character_motor.js` creates measurements using
the actual archived JS/WASM; `tests/movement/smoke_character_motor.swift` replays them through
the Swift motor. Native integration tests exercise the disabled probe capsule,
KCC, shape/contact/project queries and holding position while collision cells
load. The complete locomotion/combat/swim/climb animation state machine remains
a separate port.

Sky and weather helpers execute the original sun/moon/star/cloud/rain/fog,
wind and lightning formulas. Water uses the original near-net shoreline builder,
wave formulas and repeated `waterclear256` texture. Native helper, spatial-index,
shader and GPU tests are in `tests/rendering/smoke_native_atmosphere.py`,
`tests/rendering/smoke_native_weather_particles.py`, `tests/movement/smoke_native_water_waves.py`,
`tests/movement/smoke_native_world_water.py` and `tests/rendering/smoke_native_atmosphere_metal.py`.
The wave GPU test compares 7,200 vertices against actual browser results; the
maximum measured height difference is 0.0000119 m.
