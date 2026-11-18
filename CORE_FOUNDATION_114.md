# Gameplay continuity checkpoint114

An interrupted native connection previously restarted at the default location. Server teleports could also leave driver controls or a delayed respawn callback owning an obsolete position. Core114 introduces an opt-in placement acknowledgement: position reports carry the last applied server placement, stale reports are refused, and vehicle/input/radio ownership is cleared before the authoritative position becomes ready.

A reconnect selects the account's last admitted ordinary grounded foot position or valid server placement intent. Health, ammunition and action sequence ownership remain separate. Drivers resume on foot at the prior admitted foot anchor; this does not calculate safe exit beside the current vehicle. Legacy browser clients retain their existing protocol.

Active mission vehicles now retain their admitted body position and condition across a normal server restart. Restore keeps the task/vehicle identity and clears occupancy. Older saves without body state use the existing factory fallback; initial factory ground placement remains unverified.

Implementation and reproducible regressions:

- [Server placement protocol](CORE_POSITION_RESUME_114.md).
- [Native placement and ownership](CORE_NATIVE_PLACEMENT_114.md).
- [Mission vehicle persistence](CORE_MISSION_VEHICLE_PERSISTENCE_114.md).

These are independent implementation repairs. They do not establish complete original GTA San Andreas gameplay accuracy. Original game assets and private test recordings remain outside the source release.

Run `python3 smoke_core_114.py` for the independent placement and mission restart regressions, or add `--server-only` for the Node checks. The existing public aggregate runner is retained; this small entry point adds no original-resource or private-carrier dependency.
