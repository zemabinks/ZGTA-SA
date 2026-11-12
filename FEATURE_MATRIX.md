# ZGTA:SA feature and evidence matrix

Updated 12 November 2026. This tracks the independent server in this repository.
The archived browser client is under ignored `local-only/` on the host Mac.
The publisher's private server implementation and database are unavailable.
Client files can show a screen or a message format; they cannot establish the
complete rules or data held by that private server.

| System | Independent implementation | Verification and gap |
| --- | --- | --- |
| 3D world and browser client | Archived client and assets served locally | Loaded in Chrome with WebGL. The archive is a discoverable snapshot, not a complete publisher asset inventory. |
| Guest accounts | Local account cookie and saved player data; Discord is unnecessary | HTTP and WebSocket share an account in isolated tests. Optional Discord linking and a one-time $500 bonus pass a mocked test, but need host credentials, HTTPS, and a live sign-in check. |
| Multiplayer | Shared walking and driving positions, passenger state, player list, and chat | Two simultaneous clients pass wire tests. A second physical device has not been tested. |
| Vehicles | Local purchase, ownership, spawn, driving, saved condition and position, storage, recall, and paid repair | Catalog and gameplay tests cover storage, damaged respawn, restart restoration, and repair. Condition comes from the owner's client report; publisher dealerships, storage buildings, fuel, and tuning remain unavailable. |
| Courier | Package pickup and delivery to an archived property entrance | Wrong-location actions fail; payout and unfinished-route persistence pass isolated tests. |
| Taxi | Own a car, drive to a pickup, then drive to a different drop-off | Walking pickup/drop-off fails; driving completion and payout pass isolated tests. There is no visible passenger character or fare meter yet. |
| Mechanic | Damaged roadside mission car at a property entrance; approach and repair on foot | Browser objective and isolated location, on-foot, payout, cleanup, and restart tests pass. A second test client sees the car but cannot take it. No towing, repair animation, or general vehicle damage system yet. |
| Medic | Mission ambulance, patient pickup point, and return to starting aid station | Browser showed the ambulance and patient objective; isolated driving, pickup, payout, and cleanup tests pass. No visible patient, hospital system, or healing yet. |
| Street time trial | Three world checkpoints in an owned car within three minutes | Order, driving requirement, timer, and payout pass isolated tests. No visible checkpoint markers or leaderboard yet. |
| Multiplayer race | Shared lobby, two or more racers, temporary cars, three ordered checkpoints, finish ranking, and payouts | Chrome created and cancelled a lobby. Two protocol clients pass route, rank, payout, car cleanup, and account-stat persistence tests. A full browser race has not been driven; there are no 3D checkpoint rings or persistent leaderboard. Active race is lost on server restart. |
| Economy | Cash, XP, job payouts, car and home prices | Transactions and saved balances pass isolated tests. Publisher rules, businesses, shops, taxes, and trading are not reproduced. |
| Homes | Purchase, owned markers, exterior visit | Purchase and native home-status tests pass. Interiors rendered as empty space in a Chrome probe, so entry, storage, and garage actions remain disabled. |
| Police, combat, gangs | No independent implementations | These advertised or client-facing systems need behavioral specifications, original code/data, or independent designs and tests. |
| Internet hosting | LAN launcher and private join code | Join and local LAN-address checks pass. No public deployment, domain, HTTPS endpoint, or internet device test exists. |

The local game should be described as a growing independent implementation.
Exact server parity cannot be verified from the public website alone. Before a
public release using the original client or game assets, the host needs a
distribution plan that respects the owners' rights. The source repository keeps
those files out of GitHub.

## Next acceptance targets

1. Check the new mechanic, medic, and time trial objectives in a real browser
   and on a second physical device; add visible patient and checkpoint markers.
2. Add server-validated vehicle collisions and damage, then property garages,
   fuel, and tuning rules.
3. Add health, combat, wanted levels, and police behavior with rules enforced
   by the server.
4. Add gangs and territory control; expand races with visible checkpoint
   markers and a persistent leaderboard.
5. Build an original public web experience with guest accounts, configure
   optional Discord linking, HTTPS, abuse controls, and a licensed asset path.

Each target needs gameplay tests and at least one real-browser check before it
is marked complete. Feature names alone are not a substitute for behavior.
