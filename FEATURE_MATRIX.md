# ZGTA:SA feature and evidence matrix

Updated 14 November 2026. This tracks the independent server in this repository.
The archived browser client is under ignored `local-only/` on the host Mac.
The publisher's private server implementation and database are unavailable.
Client files can show a screen or a message format; they cannot establish the
complete rules or data held by that private server.

| System | Independent implementation | Verification and gap |
| --- | --- | --- |
| 3D world and browser client | Archived client and assets served locally | Loaded in Chrome with WebGL. The archive is a discoverable snapshot, not a complete publisher asset inventory. |
| Objective route map and waypoint | F6 shows the locally archived radar map, player position, and active mission, race, territory, or exploration destination. A compact in-world badge shows a cardinal arrow, target, and distance. | Chrome showed the player and El Corona map markers, and separately showed the new waypoint badge over the 3D world during a pizza route. An isolated browser-script test checks target updates and visibility. These are UI overlays, not 3D checkpoint rings or native game map markers. |
| Guest accounts | Local account cookie and saved player data; Discord is unnecessary | HTTP and WebSocket share an account in isolated tests. F6 and /discord show the host's community invite. Self-hosted pages disable the archived client's tips about unsupported features and its unrelated Discord reward. Optional Discord linking and a one-time $500 bonus pass a mocked test, but need host credentials, HTTPS, and a live sign-in check. |
| Multiplayer | Shared walking and driving positions, passenger state, player list, and chat | Two simultaneous clients pass wire tests. A second physical device has not been tested. |
| Private groups | Up to four players per session, invitations, leader handoff, member removal and private group chat | Two separate browser sessions showed distinct guest accounts. One invited the other in F6; both showed the two-member group, and a private message appeared in both sessions. Three protocol clients confirm membership and chat privacy. Isolated tests cover capacity, invite expiry, leader permissions and disconnect cleanup. Groups end when members leave or the server restarts; publisher party features are not reproduced. |
| Vehicles and aircraft | Local purchase, ownership, spawn, driving or flying, saved condition and position, storage, recall, paid repair, and paid respray. Archived ground vehicles require one of their catalog dealerships; aircraft require a listed hangar. | Catalog and integrated gameplay tests cover dealer restrictions, wrong-dealer rejection, storage, damaged respawn, repair, custom paint codes on shared vehicles, and restart restoration. Chrome displayed the nearest dealership and its catalog in the live game. An isolated aircraft test covers archived hangar prices and availability, purchase, spawn, recall restrictions, and restart recovery. Chrome entered a loaner Dodo, but a purchased aircraft has not been checked there. The paint's 3D appearance has not been checked in Chrome. Client updates may lower saved health but cannot repair it for free. Position and damage still come from the owner's client report; fuel, other tuning, and publisher storage buildings remain unavailable. |
| Workshop supplies | Repair kits and paint cans bought on foot at ground dealerships, used on nearby owned cars, or given to an on-foot player within 8 m; five of each per account | An isolated test covers dealership and cash gates, capacity, actual vehicle repair and paint code change, wrong-distance and full-recipient transfer rejection, and restart persistence for both accounts. Chrome showed the F6 stock and purchase controls. A live browser purchase and player-to-player handoff have not been performed. These are local inventory items, not publisher shop rules. |
| Courier | Package pickup and delivery to an archived property entrance | Wrong-location actions fail; payout and unfinished-route persistence pass isolated tests. |
| Taxi | Guest gets a reserved cab and completes consecutive pickups and drop-offs at archived property entrances in one shift. The same cab remains until the driver exits and ends the shift. $300 base fare plus local clean, quick and consecutive-fare bonuses. Every three fares unlocks a level; Cabbie at level 8 and limousine at level 20 add local premiums. F6 shows cab selection, fare meter and record. | The archived English help names the Cabbie and limousine unlock levels, but not its server level or fare formula. Isolated tests cover no-cost guest start, wrong-car rejection, two fares in one cab, clean and quick bonuses, late and damaged rides, streak, locked cab rejection, premium payout, shift cancellation, and restart recovery during a fare and between fares. The integrated wire test covers pickup, delivery, next-fare dispatch, refusal to end the shift while seated, and cab cleanup after exiting. Chrome showed the guest fare meter and route, the spawned 3D taxi, entering and driving it. Chrome revealed that its vehicle manager keeps an occupied car local when the server removes it. The updated F6 panel disabled End shift while seated; after the player exited, End shift removed the cab from the 3D world. Chrome has not driven a full fare or tested the level-unlocked cabs. There is no visible passenger, cab rank gate, mood meter, upgrades, or publisher fare formula. The archived client's “press 2 to start a shift” tip still appears in the cab; F6 controls the local shift. |
| Mechanic | Damaged roadside mission car at a property entrance; hold beside it on foot for engine, tyre and bodywork repairs, three seconds each. Moving away resets the current stage. Completed stages persist and payout is automatic. | The archived English help names the three repair parts; timing and payout remain local rules. Chrome showed the stage 1 objective and route map, then cancelled the call; it has not shown progression while standing beside the car. Isolated tests cover interruption, stage order, restart, payout and cleanup. A second test client sees the car but cannot take it. No tow truck, towing, repair animation, shared crew repair or general vehicle damage system yet. |
| Medic | Reserved ambulance, patient pickup point, and return to starting aid station in that same ambulance | Chrome showed the ambulance and patient objective. The integrated wire test checks wrong-vehicle denial at pickup and return, payout, and cleanup. No visible patient, CPR, hospital system, or healing yet. |
| Street time trial | Three world checkpoints in an owned car within three minutes; local browser requests automatic checkpoint passage on arrival | Order, driving requirement, timer, and payout pass isolated tests. The browser-side auto-action gate is tested with simulated state; a complete trial has not been driven in Chrome. No 3D checkpoint markers or leaderboard yet. |
| Police patrol | Volunteer duty unlocks a four-minute route with a marked loaner police car, three checkpoints, $400 and 80 XP; local browser requests automatic checkpoint passage on arrival | Chrome started and cancelled a patrol, showed its 3D police car and live objective, then restored duty off. Isolated tests cover duty gate, wrong-car rejection, ordered checkpoints, payout, loaner cleanup, and restart recovery. A browser-script test rejects automatic actions in the wrong marked vehicle. A full route has not yet been driven in Chrome; there are no 3D checkpoint rings or police NPCs. |
| Pizza delivery | A six-minute, three-address route on a reserved Pizzaboy scooter; $400 and 80 XP on completion; local browser requests automatic checkpoint passage on arrival | The archived client lists a pizza job and Pizzaboy model. Chrome started a local delivery and showed the new in-world waypoint over the 3D scooter scene; the test route was cancelled. An isolated mission test covers the scooter's owner restriction, wrong vehicle, ordered deliveries, payout, cancellation, expiry, and restart recovery. A browser-script test covers auto-action selection and vehicle/distance gates. The full route has not been driven in Chrome, and no publisher pizza rules are claimed. |
| Freight delivery and convoy | A seven-minute cargo pickup and delivery route in a reserved Mule truck; $500 and 100 XP on completion; a one-time $100 and 20 XP bonus to each nearby private-group convoy member | The archived English help lists trucker work and the Mule. Chrome showed the F6 route and timer, spawned the 3D truck, entered driving mode, and cancelled the route. Isolated tests cover owner restriction, wrong vehicle, pickup and delivery order, payout, cancellation, expiry, restart recovery, group membership, nearby truck checks, outsider exclusion, and prevention of a second convoy payout. The full route and convoy have not been driven in Chrome. Depots, damage bonus, and publisher trucker rules are not reproduced. |
| Pilot flight and record | Ten-minute flight in one of eight level-unlocked loaner aircraft between archived airport hangars; airborne gate, model-sized landing zone and two-second stop; $700 and 140 XP base pay, plus local aircraft, clean, early, and fifth-flight bonuses | Archived English help describes four airports, a two-second stop, bonus types, and the aircraft unlock levels. Chrome started the Dodo mission, showed the 3D aircraft, entered it, and cancelled the flight. It also displayed the F6 aircraft selector with level locks. Isolated tests cover locked Beagle rejection, its level-four unlock, model-specific vehicle spawn and wider landing, premium payout, takeoff, clean versus damaged flights, streak rewards, cancellation, expiry, and restart recovery. A complete flight or larger aircraft flight has not been flown in Chrome. The local level formula adds one level for every three completed flights; the loaner teleport, route, and bonus amounts are also local design choices. |
| Fire response | Eight-minute dispatch to an archived property entrance in a reserved fire truck; three fire spots, then an on-foot rescue; $650 and 130 XP | Archived English help describes a fire truck, multiple fires, and rescues. Chrome started the mission, showed the truck and route, entered it, and cancelled the call. An isolated test covers truck reservation, arrival location and correct vehicle, ordered suppression, on-foot rescue, payout, cancellation, expiry, and restart recovery. The fire spots are controlled through F6; there are no 3D flames, water cannon interaction, extinguisher model, rescued character, or publisher fire-level rules. The original client's “press 2 to start a shift” prompt still appears in the truck and does not reflect this local F6 mission. |
| Getaway heist | Ten-minute route: take a bag on foot at a property entrance, gain two wanted stars, lose police, and deliver it in a reserved Sultan; $900 and 180 XP plus a nearby private-group share | Archived heist help describes a getaway vehicle, robbery, police response, and drop-off. Chrome started the local route, showed the F6 objective, entered its 3D Sultan, and cancelled the test. Isolated checks cover the marked vehicle, proximity and on-foot robbery, two-star escape, saved cooldown and stage, crew snapshot and outsider exclusion, payout, death and arrest failure, cancellation, expiry, and restart recovery. The local target is an archived property entrance; publisher stores, banks, casinos, guards, interiors, and visible bag assets are unavailable. A complete route has not been driven in Chrome. |
| Getaway car | Timed car theft route using a reserved mission vehicle; taking the car raises wanted level | Chrome started and cancelled the mission and displayed its location and timer. Isolated tests cover another player's entry denial, wrong-car rejection, pickup, delivery, payout, cleanup, and restart restoration. This is an independent mission, not the publisher's car thief rules. |
| Exploration trail | Twelve one-time property-entrance discoveries across the map, with cash and XP rewards and a completion bonus | Isolated tests cover on-foot proximity, duplicate rejection, rewards, and restart persistence. Chrome verified F6 track and untrack controls. F6 offers a direction objective; there are no 3D collectible models or publisher collectible locations. |
| Multiplayer race | Shared lobby, two or more racers, temporary cars, three ordered checkpoints, finish ranking, payouts, and saved standings by wins and finishes; local browser requests automatic checkpoint and finish actions on arrival | Chrome created and cancelled a lobby. Two protocol clients pass route, rank, payout, car cleanup, and account-stat persistence tests. A browser-script test checks the final-checkpoint action. Saved standings survive a restart. A full browser race has not been driven; there are no 3D checkpoint rings. Active race is lost on server restart. |
| Economy | Cash, XP, job payouts, car and home prices, and two local workshop supplies | Transactions and saved balances pass isolated tests. Publisher rules, businesses, wider shops, taxes, and broader inventory are not reproduced. |
| Player economy | Nearby cash and workshop-supply transfers plus a local top-ten XP leaderboard | Isolated tests cover cash amount, balance and distance checks, supply capacity and on-foot proximity, transfers, and ranking. Broader item trading, businesses, and publisher rankings remain unavailable. |
| Homes and exterior parking | Purchase, owned markers, exterior visit, and two parking spaces per owned property exterior; parked ground cars retain condition and paint through restart and require local retrieval | Integrated gameplay verifies parking and retrieval restrictions. An isolated test covers two-car capacity, saved condition, restart, and local retrieval. Interior coordinates rendered as empty space in a Chrome probe, so interior entry and actual garage buildings remain disabled. The parking controls have not yet been used end to end in Chrome with an owned property. |
| Combat and safety | Saved health, armour, kills and deaths; nearby hit damage, kill feed, passive mode and cooldown | Two protocol clients pass shot, hit, kill and respawn tests, including rejection of distant shot origins and misses. The archived client exposes the packet shapes, but exact publisher damage and physics rules are unavailable. Hit checks still use client reported positions and endpoints; line of sight, weapon inventory and anti-cheat are incomplete. A real browser fight has not been tested. |
| Wanted level and police | Wanted levels rise on attacks and decay over time; volunteers can go on police duty, arrest a nearby wanted player for a fine and reward, and run a patrol | Two protocol clients pass wanted, arrest and passive restrictions; patrol has an isolated route and persistence test. There are no police NPCs, jail, or original publisher rules. |
| Crews and territory | Three local crews and three property based territories; capture progress, rival contest, reward, saved ownership | Isolated tests cover crew switching, location, contest, capture, payout and restart data. No 3D territory marker, gang missions, or publisher gang system. Capture is session state. |
| Internet hosting | LAN launcher and private join code | Join and local LAN-address checks pass. No public deployment, domain, HTTPS endpoint, or internet device test exists. |

The local game should be described as a growing independent implementation.
Exact server parity cannot be verified from the public website alone. Before a
public release using the original client or game assets, the host needs a
distribution plan that respects the owners' rights. The source repository keeps
those files out of GitHub.

## Archived client evidence for freight, pilot, fire, and heist

The locally archived English client chunk
`local-only/site/_next/static/chunks/612.b99cc7b46756e1c2.js` contains
`jobHelp_trucker_1` through `jobHelp_trucker_3`. They describe a Mule,
pickup from a work board, and a timed delivery. This is evidence of the
client's displayed help text, not evidence of the publisher's server rules.
The same chunk has `jobHelp_pilot_1` through `jobHelp_pilot_3`, describing
four airports, a flight, and a two-second stop after landing. The archived
catalog lists the four hangar locations, Dodo, and other aircraft prices.
`jobHelp_pilot_5` describes smooth, early, and fifth-flight bonuses without
their exact payout formula. `jobHelp_pilot_6` lists the Beagle, Maverick,
Shamal, Nevada, Leviathan, AT-400, and Andromada unlock levels.
`jobHelp_fire_1` through `jobHelp_fire_8` describe
fire trucks, suppression, rescue, later call types, and crews. These are
client-facing instructions rather than the private server implementation.
`jobHelp_heist_1` through `jobHelp_heist_8` describe a getaway car, robbery,
police escape, drop-off, crew participation, and failed escapes.
`jobHelp_mechanic_3` names the engine, tyres, and bodywork as ordered on-foot
repairs. Its later help also describes towing and shared crew repairs, which
the local server does not yet implement. `jobHelp_medic_2` and
`jobHelp_medic_5` describe ambulance dispatch and a hospital return.
`jobHelp_taxi_1` through `jobHelp_taxi_5` describe a cab rank start, a
dispatched cab, Cabbie and limousine unlock levels, passenger pickup,
distance pay, ride bonuses, mood, upgrades, and a fare meter. The local job
uses archived property entrances and its own level formula, bonus amounts,
and time window.
The archived game chunk `9737.c81ad6ccfd85b371.js` dispatches `vgone` to
the vehicle manager. Its `gone` branch marks the current driver's car as
local rather than removing it. Chrome confirmed that ending a taxi job while
seated left the cab visible. The local server therefore requires the driver
to exit before ending a taxi shift. A focused REA parse of that chunk produced
parent Evidence `ev_e84c35f870c00c6cb34e1773ff13f21fa359efa018c248f9b46def8baba9dcf1`;
semantic coverage was partial after a heap limit, so this branch was checked
directly against the archived bytes and Chrome behavior.
Static REA analysis of the archived chunk directory recorded parent evidence
`ev_e676b08c9c7dc2182b28bc549d8833c514ab2acc2c74472547dee4655cf4855a`
for SHA-256 `f5c275ced14ae2abf38e1eb0e7bf58fbc4fe6488561691888dbe4cebdce04e15`.
It parsed 80 JavaScript files without parse failures, but its semantic graph
coverage was partial because of resource limits. The local routes and payouts
above are design choices of this independent server.

## Next acceptance targets

1. Drive the freight, pilot flight, heist, fire response, pizza, mechanic, medic, time trial, and exploration objectives in a
   real browser and on a second physical device; add visible world markers.
2. Add server-validated vehicle collisions and damage, then fuel, tuning,
   and a visible parking or garage interaction at owned properties.
3. Validate combat and turf capture in the real browser with two devices;
   add authoritative hit geometry, police NPC behavior, and 3D markers.
4. Expand gangs, territory control, and races with missions and visible
   checkpoints; test the saved race standings with real browser races.
5. Build an original public web experience with guest accounts, configure
   optional Discord linking, HTTPS, abuse controls, and a licensed asset path.

Each target needs gameplay tests and at least one real-browser check before it
is marked complete. Feature names alone are not a substitute for behavior.
