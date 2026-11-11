# ZGTA:SA feature and evidence matrix

Updated 11 November 2026. This tracks the independent server in this repository.
The archived browser client is under ignored `local-only/` on the host Mac.
The publisher's private server implementation and database are unavailable.
Client files can show a screen or a message format; they cannot establish the
complete rules or data held by that private server.

| System | Independent implementation | Verification and gap |
| --- | --- | --- |
| 3D world and browser client | Archived client and assets served locally | Loaded in Chrome with WebGL. The archive is a discoverable snapshot, not a complete publisher asset inventory. |
| Guest accounts | Local account cookie and saved player data; Discord is unnecessary | HTTP and WebSocket share an account in isolated tests. Optional Discord account linking and rewards are not implemented. |
| Multiplayer | Shared walking and driving positions, passenger state, player list, and chat | Two simultaneous clients pass wire tests. A second physical device has not been tested. |
| Vehicles | Local cash purchase, ownership, spawn, entry, and driving using the extracted vehicle catalog | Catalog and gameplay tests pass. Original dealership rules, persistent garage storage, damage, fuel, and tuning are not reproduced. |
| Courier | Package pickup and delivery to an archived property entrance | Wrong-location actions fail; payout and unfinished-route persistence pass isolated tests. |
| Taxi | Own a car, drive to a pickup, then drive to a different drop-off | Walking pickup/drop-off fails; driving completion and payout pass isolated tests. There is no visible passenger character or fare meter yet. |
| Mechanic, medic, street trial | Distance-based local activities with cash and XP payouts | Payout and persistence tests pass. These are placeholders for world objectives and original-style behavior. |
| Economy | Cash, XP, job payouts, car and home prices | Transactions and saved balances pass isolated tests. Publisher rules, businesses, shops, taxes, and trading are not reproduced. |
| Homes | Purchase, owned markers, exterior visit | Purchase and native home-status tests pass. Interiors rendered as empty space in a Chrome probe, so entry, storage, and garage actions remain disabled. |
| Police, combat, gangs, races | No independent implementations | These advertised or client-facing systems need behavioral specifications, original code/data, or independent designs and tests. |
| Internet hosting | LAN launcher and private join code | Join and local LAN-address checks pass. No public deployment, domain, HTTPS endpoint, or internet device test exists. |

The local game should be described as a growing independent implementation.
Exact server parity cannot be verified from the public website alone. Before a
public release using the original client or game assets, the host needs a
distribution plan that respects the owners' rights. The source repository keeps
those files out of GitHub.

## Next acceptance targets

1. Replace the remaining distance-based jobs with world actions and visible
   objectives; verify each with a browser player and a second client.
2. Add server-owned vehicle state, damage, repair, and a persistent garage.
3. Add health, combat, wanted levels, and police behavior with rules enforced
   by the server.
4. Add gangs, territory control, and races as multiplayer systems.
5. Build an original public web experience with guest accounts, optional
   Discord linking, HTTPS, abuse controls, and a licensed asset path.

Each target needs gameplay tests and at least one real-browser check before it
is marked complete. Feature names alone are not a substitute for behavior.
