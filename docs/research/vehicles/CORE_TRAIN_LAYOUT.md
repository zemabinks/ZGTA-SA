# Train carriage layout across ownership

The native renderer previously appended carriage models only while the local
player was driving a train. A remote-driven or newly parked locomotive lost its
consist. Its exported locomotive rig contains only that locomotive, whereas the
public browser's 62540 model factory attaches the additional models for every
train instance and positions them through 91584.wY.

The renderer now uses the existing native carriage placement for owned,
remote-driven and visible parked locomotives. The original data supplies three
freight flats for 537, three passenger carriages for 538 and none for 449. No new
track, carriage-spacing, force or coupling values are introduced.

`NativeGroundVehicle.trainCarriages` accepts the raw rigid-body position and
heading/pitch/roll, with an optional exact predicted physical pose. It retains
per-vehicle nearest-node caches and shares the existing
`NativeTrainDynamics.carriages` calculation. The locally owned path retains its
existing physical pose and renderer tokens. Parked predicted poses avoid an
unnecessary Euler round trip. Remote wire coordinates convert once from GTA
Z-up into the existing Rapier Y-up calculation. Model origins are applied once
when constructing the final GTA model matrix.

Visible parked rows exclude a locomotive already represented by a remote
driver. Remote duplicate IDs are filtered, and layout caches are pruned when a
train streams out, disappears, changes model or crosses a fresh-session/data
boundary. Existing parked/owned physics and authority remain separate from
this model-layout helper.

Run `python3 smoke_train_layout.py` with the owner-local model/rail archive and
native test library. It generates its reference with the actual public 91584.wY
function and compiles the actual renderer collection clauses. The gate passes
2,820 checks across 72 curved-track, reverse and tilted poses, with a maximum
matrix-component error of 2.08e-17. It also covers owned/remote/parked rendering,
duplicate IDs, exit continuity, streaming, missing tracks, model changes and
session/explicit-disappearance cleanup. Reference values stay in ignored
local-only output; no original data tables are committed.

This verifies public-browser layout compatibility and native integration. It
does not establish retail train handling, derailment, collision behavior of
every carriage, shunting or physical coupling. Trailer/tow-truck controls and
their required joint/ownership APIs remain separate unfinished systems.
