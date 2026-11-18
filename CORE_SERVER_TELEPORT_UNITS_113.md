# Self-hosted teleport heading units

Home and pilot teleports now use the heading unit expected by the existing
browser and native clients. A home heading of 90 degrees previously became
1.571 on the wire and was converted a second time by the client, producing
about 0.0274 radians. It now remains 90 on the wire, producing π/2 radians in the
browser and the corresponding mirrored native heading.

The `tp` packet's `h` field is degrees. The archived browser parser forwards
it unchanged to its teleport callback, which converts it to radians. The
current native `tp` parser likewise converts degrees, with its coordinate
system's negative sign. Those consumer contracts remain unchanged.

| Server producer | Source heading unit | `tp.h` conversion |
| --- | --- | --- |
| Home enter | Interior catalogue degrees | Preserve value |
| Home exit | Home exterior degrees | Preserve value |
| Home visit | Home exterior degrees | Preserve value |
| Pilot start | Runway radians, also used by sin/cos | Convert once to degrees |
| Passenger release correction | Vehicle radians | Existing conversion retained |
| Rejected passenger correction | Actor radians | Existing conversion retained |

`tpHeadingFromRadians` makes the three radian producers explicit. Headings
are not rounded or wrapped. Coordinates, ground flags, vehicle claims,
health, armour, ammunition and action policy are unchanged. This change
does not implement reconnect-position persistence.

Run `node smoke_selfhost_tp_units.js`. The independent fixture executes the
actual server action and passenger-correction methods with authored homes,
interiors, airports and transports. It covers 84 cases across all six
producers and passes 690 checks. It does not instantiate the backend, open
a listener, start timers, load game files or write player state. A source
inventory assertion fails if a teleport producer is added without coverage.
The native parser check verifies the actual source contract; it does not
compile or execute Swift.

For a retained earlier source, run
`node smoke_selfhost_tp_units.js --source /path/to/previous/selfhost_backend.js --expect-historical-mismatch`.
The pre-fix source reproduces 52 nonzero-angle failures isolated to home
enter/exit/visit and pilot start; both passenger corrections remain valid.
Running the normal positive gate against that source fails.

Private compatibility analysis separately verifies the existing browser consumer's degree-valued contract. Original code and execution carriers remain local. This supports the inspected protocol contract, not measured retail orientation or physical-device teleport acceptance.
