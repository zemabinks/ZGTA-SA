# ZGTA:SA feature and evidence matrix

Updated 12 November 2026. This tracks the independent server in this repository.
The archived browser client is under ignored `local-only/` on the host Mac.
The publisher's private server implementation and database are unavailable.
Client files can show a screen or a message format; they cannot establish the
complete rules or data held by that private server.

| System | Independent implementation | Verification and gap |
| --- | --- | --- |
| 3D world and browser client | Archived client and assets served locally | Loaded in Chrome with WebGL. The archive is a discoverable snapshot, not a complete publisher asset inventory. |
| Objective route map | F6 shows the locally archived radar map, player position, and active mission, race, territory, or exploration destination | Chrome showed the player and El Corona markers after entering the world, then hid the route map after untracking. The map does not add 3D checkpoint rings or native game map markers. |
| Guest accounts | Local account cookie and saved player data; Discord is unnecessary | HTTP and WebSocket share an account in isolated tests. Optional Discord linking and a one-time $500 bonus pass a mocked test, but need host credentials, HTTPS, and a live sign-in check. |
| Multiplayer | Shared walking and driving positions, passenger state, player list, and chat | Two simultaneous clients pass wire tests. A second physical device has not been tested. |
| Private groups | Up to four players per session, invitations, leader handoff, member removal and private group chat | Chrome created and left a group through F6. Three protocol clients confirm invitations, membership and chat privacy. Isolated tests cover capacity, invite expiry, leader permissions and disconnect cleanup. Groups end when members leave or the server restarts; publisher party features are not reproduced. |
| Vehicles | Local purchase, ownership, spawn, driving, saved condition and position, storage, recall, paid repair, and paid respray | Catalog and gameplay tests cover storage, damaged respawn, repair, custom paint codes on shared vehicles, and restart restoration. The paint's 3D appearance has not been checked in Chrome. Client updates may lower saved health but cannot repair it for free. Position and damage still come from the owner's client report; publisher dealerships, storage buildings, fuel, and other tuning remain unavailable. |
| Courier | Package pickup and delivery to an archived property entrance | Wrong-location actions fail; payout and unfinished-route persistence pass isolated tests. |
| Taxi | Own a car, drive to a pickup, then drive to a different drop-off | Walking pickup/drop-off fails; driving completion and payout pass isolated tests. There is no visible passenger character or fare meter yet. |
| Mechanic | Damaged roadside mission car at a property entrance; approach and repair on foot | Browser objective and isolated location, on-foot, payout, cleanup, and restart tests pass. A second test client sees the car but cannot take it. No towing, repair animation, or general vehicle damage system yet. |
| Medic | Mission ambulance, patient pickup point, and return to starting aid station | Browser showed the ambulance and patient objective; isolated driving, pickup, payout, and cleanup tests pass. No visible patient, hospital system, or healing yet. |
| Street time trial | Three world checkpoints in an owned car within three minutes | Order, driving requirement, timer, and payout pass isolated tests. No visible checkpoint markers or leaderboard yet. |
| Police patrol | Volunteer duty unlocks a four-minute route with a marked loaner police car, three checkpoints, $400 and 80 XP | Chrome started and cancelled a patrol, showed its 3D police car and live objective, then restored duty off. Isolated tests cover duty gate, wrong-car rejection, ordered checkpoints, payout, loaner cleanup, and restart recovery. A full route has not yet been driven in Chrome; there are no 3D checkpoint rings or police NPCs. |
| Getaway car | Timed car theft route using a reserved mission vehicle; taking the car raises wanted level | Chrome started and cancelled the mission and displayed its location and timer. Isolated tests cover another player's entry denial, wrong-car rejection, pickup, delivery, payout, cleanup, and restart restoration. This is an independent mission, not the publisher's car thief rules. |
| Exploration trail | Twelve one-time property-entrance discoveries across the map, with cash and XP rewards and a completion bonus | Isolated tests cover on-foot proximity, duplicate rejection, rewards, and restart persistence. Chrome verified F6 track and untrack controls. F6 offers a direction objective; there are no 3D collectible models or publisher collectible locations. |
| Multiplayer race | Shared lobby, two or more racers, temporary cars, three ordered checkpoints, finish ranking, payouts, and saved standings by wins and finishes | Chrome created and cancelled a lobby. Two protocol clients pass route, rank, payout, car cleanup, and account-stat persistence tests. Saved standings survive a restart. A full browser race has not been driven; there are no 3D checkpoint rings. Active race is lost on server restart. |
| Economy | Cash, XP, job payouts, car and home prices | Transactions and saved balances pass isolated tests. Publisher rules, businesses, shops, taxes, and item trading are not reproduced. |
| Player economy | Nearby cash transfers and a local top-ten XP leaderboard | Isolated tests cover amount, balance and distance checks, transfer, and ranking. Item trading, businesses, shops, and publisher rankings remain unavailable. |
| Homes | Purchase, owned markers, exterior visit | Purchase and native home-status tests pass. Interiors rendered as empty space in a Chrome probe, so entry, storage, and garage actions remain disabled. |
| Combat and safety | Saved health, armour, kills and deaths; nearby hit damage, kill feed, passive mode and cooldown | Two protocol clients pass shot, hit, kill and respawn tests, including rejection of distant shot origins and misses. The archived client exposes the packet shapes, but exact publisher damage and physics rules are unavailable. Hit checks still use client reported positions and endpoints; line of sight, weapon inventory and anti-cheat are incomplete. A real browser fight has not been tested. |
| Wanted level and police | Wanted levels rise on attacks and decay over time; volunteers can go on police duty, arrest a nearby wanted player for a fine and reward, and run a patrol | Two protocol clients pass wanted, arrest and passive restrictions; patrol has an isolated route and persistence test. There are no police NPCs, jail, or original publisher rules. |
| Crews and territory | Three local crews and three property based territories; capture progress, rival contest, reward, saved ownership | Isolated tests cover crew switching, location, contest, capture, payout and restart data. No 3D territory marker, gang missions, or publisher gang system. Capture is session state. |
| Internet hosting | LAN launcher and private join code | Join and local LAN-address checks pass. No public deployment, domain, HTTPS endpoint, or internet device test exists. |

The local game should be described as a growing independent implementation.
Exact server parity cannot be verified from the public website alone. Before a
public release using the original client or game assets, the host needs a
distribution plan that respects the owners' rights. The source repository keeps
those files out of GitHub.

## Next acceptance targets

1. Check the new mechanic, medic, time trial, and exploration objectives in a
   real browser and on a second physical device; add visible world markers.
2. Add server-validated vehicle collisions and damage, then property garages,
   fuel, and tuning rules.
3. Validate combat and turf capture in the real browser with two devices;
   add authoritative hit geometry, police NPC behavior, and 3D markers.
4. Expand gangs, territory control, and races with missions and visible
   checkpoints; test the saved race standings with real browser races.
5. Build an original public web experience with guest accounts, configure
   optional Discord linking, HTTPS, abuse controls, and a licensed asset path.

Each target needs gameplay tests and at least one real-browser check before it
is marked complete. Feature names alone are not a substitute for behavior.
