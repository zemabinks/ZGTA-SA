# Projectile time during missing collision coverage

Native prediction previously returned before advancing a projectile's age
whenever the next segment lacked streamed collision geometry. That froze its
fuse until coverage or a newer server snapshot arrived. The archived browser
manager advances age before movement/contact; it does not establish the policy
for the native engine's separate unavailable-coverage state.

Admitted simulation time now advances age during that wait. Position, velocity,
rotation, collision checks and trails still wait for coverage. An expired
uncovered prediction is removed without creating a guessed impact, blast or
molotov fire. The normal known-coverage fuse branch is unchanged; a resting or
stuck projectile uses its known resting policy. Server snapshots and blast
echoes remain authoritative and can replace the local prediction normally.

This fixes a local prediction/presentation discrepancy, not server-authoritative
damage timing. Production native effects consume server snapshots; they do not
launch a second independently authoritative projectile. The server normally
supplies age/removal updates and dimension-matched blasts, which can mask the
local stall. No new geometry, collision, blast position or damage is invented
to fill a missing cell. The uncovered-expiry policy is a native adaptation,
not a measured retail rule.

`python3 smoke_native_projectile_clock.py` passes87 checks/21 cases over the
actual complete helper with authored snapshots and explicit coverage callbacks.
It covers all supported projectile weapon families, display schedules15–144Hz,
coverage return, resting expiry, server replacement, molotov echoes and session
clear. Optional `--historical-root /path/to/Core116` compiles the old helper and
requires failure of the frozen-age assertion. No listener, renderer or live
damage test is involved. Existing eleven actual archived trajectory/fuse/bounce
cases also pass unchanged. These are not GPU, retail, physical-device or full
multiplayer acceptance.
