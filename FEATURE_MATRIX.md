# ZGTA:SA feature and evidence matrix

Updated 13 November 2026. This tracks the independent server in this repository.
The archived browser client is under ignored `local-only/` on the host Mac.
The publisher's private server implementation and database are unavailable.
Client files can show a screen or a message format; they cannot establish the
complete rules or data held by that private server.

| System | Independent implementation | Verification and gap |
| --- | --- | --- |
| 3D world and browser client | Archived client and assets served locally | Loaded in Chrome with WebGL. The archive is a discoverable snapshot, not a complete publisher asset inventory. |
| Objective route map | F6 shows the locally archived radar map, player position, and active mission, race, territory, or exploration destination | Chrome showed the player and El Corona markers after entering the world, then hid the route map after untracking. The map does not add 3D checkpoint rings or native game map markers. |
| Guest accounts | Local account cookie and saved player data; Discord is unnecessary | HTTP and WebSocket share an account in isolated tests. F6 and /discord show the host's community invite. Self-hosted pages disable the archived client's tips about unsupported features and its unrelated Discord reward. Optional Discord linking and a one-time $500 bonus pass a mocked test, but need host credentials, HTTPS, and a live sign-in check. |
| Multiplayer | Shared walking and driving positions, passenger state, player list, and chat | Two simultaneous clients pass wire tests. A second physical device has not been tested. |
| Private groups | Up to four players per session, invitations, leader handoff, member removal and private group chat | Two separate browser sessions showed distinct guest accounts. One invited the other in F6; both showed the two-member group, and a private message appeared in both sessions. Three protocol clients confirm membership and chat privacy. Isolated tests cover capacity, invite expiry, leader permissions and disconnect cleanup. Groups end when members leave or the server restarts; publisher party features are not reproduced. |
| Vehicles and aircraft | Local purchase, ownership, spawn, driving or flying, saved condition and position, storage, recall, paid repair, and paid respray | Catalog and gameplay tests cover storage, damaged respawn, repair, custom paint codes on shared vehicles, and restart restoration. A new isolated aircraft test covers archived hangar prices and availability, purchase, spawn, recall restrictions, and restart recovery. Chrome entered a loaner Dodo, but a purchased aircraft has not been checked there. The paint's 3D appearance has not been checked in Chrome. Client updates may lower saved health but cannot repair it for free. Position and damage still come from the owner's client report; ground dealerships, storage buildings, fuel, and other tuning remain unavailable. |
| Courier | Package pickup and delivery to an archived property entrance | Wrong-location actions fail; payout and unfinished-route persistence pass isolated tests. |
| Taxi | Own a car, drive to a pickup, then drive to a different drop-off | Walking pickup/drop-off fails; driving completion and payout pass isolated tests. There is no visible passenger character or fare meter yet. |
| Mechanic | Damaged roadside mission car at a property entrance; approach and repair on foot | Browser objective and isolated location, on-foot, payout, cleanup, and restart tests pass. A second test client sees the car but cannot take it. No towing, repair animation, or general vehicle damage system yet. |
| Medic | Mission ambulance, patient pickup point, and return to starting aid station | Browser showed the ambulance and patient objective; isolated driving, pickup, payout, and cleanup tests pass. No visible patient, hospital system, or healing yet. |
| Street time trial | Three world checkpoints in an owned car within three minutes | Order, driving requirement, timer, and payout pass isolated tests. No visible checkpoint markers or leaderboard yet. |
| Police patrol | Volunteer duty unlocks a four-minute route with a marked loaner police car, three checkpoints, $400 and 80 XP | Chrome started and cancelled a patrol, showed its 3D police car and live objective, then restored duty off. Isolated tests cover duty gate, wrong-car rejection, ordered checkpoints, payout, loaner cleanup, and restart recovery. A full route has not yet been driven in Chrome; there are no 3D checkpoint rings or police NPCs. |
| Pizza delivery | A six-minute, three-address route on a reserved Pizzaboy scooter; $400 and 80 XP on completion | The archived client lists a pizza job and Pizzaboy model. Chrome started a local delivery, showed the scooter and first destination, entered driving mode, and cancelled the route. An isolated test covers the scooter's owner restriction, wrong vehicle, ordered deliveries, payout, cancellation, expiry, and restart recovery. The full route has not been driven in Chrome, and no publisher pizza rules are claimed. |
| Freight delivery and convoy | A seven-minute cargo pickup and delivery route in a reserved Mule truck; $500 and 100 XP on completion; a one-time $100 and 20 XP bonus to each nearby private-group convoy member | The archived English help lists trucker work and the Mule. Chrome showed the F6 route and timer, spawned the 3D truck, entered driving mode, and cancelled the route. Isolated tests cover owner restriction, wrong vehicle, pickup and delivery order, payout, cancellation, expiry, restart recovery, group membership, nearby truck checks, outsider exclusion, and prevention of a second convoy payout. The full route and convoy have not been driven in Chrome. Depots, damage bonus, and publisher trucker rules are not reproduced. |
| Pilot flight | Ten-minute flight in a reserved Dodo from one archived airport hangar to the next; airborne gate, landing zone and two-second stop; $700 and 140 XP | Archived English help describes four airports and a two-second stop. Chrome started the mission at Los Santos International, showed the 3D Dodo, entered it, and cancelled the flight. An isolated test covers marked plane restriction, takeoff altitude, landing location and hold, payout, cancellation, expiry, and restart recovery. A complete flight has not been flown in Chrome. The loaner teleport, route, and reward are local design choices. |
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

## Archived client evidence for freight and pilot

The locally archived English client chunk
`local-only/site/_next/static/chunks/612.b99cc7b46756e1c2.js` contains
`jobHelp_trucker_1` through `jobHelp_trucker_3`. They describe a Mule,
pickup from a work board, and a timed delivery. This is evidence of the
client's displayed help text, not evidence of the publisher's server rules.
The same chunk has `jobHelp_pilot_1` through `jobHelp_pilot_3`, describing
four airports, a flight, and a two-second stop after landing. The archived
catalog lists the four hangar locations, Dodo, and other aircraft prices.
Static REA analysis of the archived chunk directory recorded parent evidence
`ev_e676b08c9c7dc2182b28bc549d8833c514ab2acc2c74472547dee4655cf4855a`
for SHA-256 `f5c275ced14ae2abf38e1eb0e7bf58fbc4fe6488561691888dbe4cebdce04e15`.
It parsed 80 JavaScript files without parse failures, but its semantic graph
coverage was partial because of resource limits. The local route and payout
above are design choices of this independent server.

## Next acceptance targets

1. Drive the freight, pilot flight, pizza, mechanic, medic, time trial, and exploration objectives in a
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
