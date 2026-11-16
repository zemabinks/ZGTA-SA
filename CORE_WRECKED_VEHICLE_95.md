# Completed vehicle wrecks release and defeat their occupant

The native chassis could finish exploding while the player remained alive in
vehicle ownership. The archived main loop handles a completed wreck before
bike throwing: force an exit, then defeat the actor. A merely disabled vehicle
is distinct from its completed wreck flag.

The Renderer now dispatches that completed-wreck transition after the current
physics update publishes its pose. The game controller parks/publishes the
wrecked hull, switches to native foot movement and releases the vehicle HUD,
controls and radio. A living occupant is defeated once through the existing
health acknowledgement owner. An already accepted death keeps its cause and
does not report a second death. Wreck handling takes priority over queued bike
throwing. Ordinary timed door exits remain their existing path.

Focused verification covers real native vehicle/foot/parked physics and
extracted current Renderer/controller methods across cars, motorcycles,
bicycles, boats and aircraft, with explicit UI/network spies. Separate actual
HTTP/URLSession/WebSocket tests verify a single fatal request, duplicate-request
rejection, a legacy-shaped observer's dead walker and parked wreck, and an
acknowledged respawn that keeps the vehicle wrecked.

The original general ground/door-clearance planner is still missing. The
adjacent entry-animation point is used when available; missing rider metadata
has a documented fallback. Rendered crash alignment, retail execution, physical
input and phone performance are separate acceptance requirements. Final combined
validation is recorded in [Core97](CORE_GAMEPLAY_FOUNDATION_97.md).
