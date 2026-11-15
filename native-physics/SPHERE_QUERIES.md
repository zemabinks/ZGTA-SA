# Literal sphere overlap queries

`zgtaphys_intersections_sphere` constructs Rapier's actual `Ball` shape.
A zero-height `Capsule` is geometrically equivalent away from boundaries, but
uses a different query path: a recorded SCL2 corpus produced five extra capsule
overlaps at approximately 0–0.1mm grazing clearance. The literal Ball matched
all211 recorded Ball decisions without changing the existing capsule API.

Swift exposes `sphereIntersections(center:radius:groups:flags:excludingColliders:excludingBodies:)`.
The climbing clearance adapter uses it. Group/flag handling, optional parent
filter, enabled checks, exclusions and output-buffer contract follow the existing
capsule query. The original motor's nonzero-height capsule queries stay intact.

Run the game-data-independent C and Swift gates after building matching host
libraries:

```sh
zsh native-physics/test_sphere.sh
```

The tests cover groups, query flags, body/shape exclusions, capacity and invalid
arguments, a caller PED predicate, and Swift buffer growth beyond64/128 results.
An independent triangle-plane corpus at coordinates128/1024/1500/2048 also
reproduces the erroneous zero-height-capsule contact while the Ball correctly
rejects a center3–49µm farther from the plane than its radius. This makes the
shape-type regression detectable without private assets. The tests require no
server, Simulator, microphone or game files.

An owner-provided recorded world corpus can additionally verify real collision
cells and ledges:

```sh
PHYSICS_SPHERE_REFERENCE_DIR=/path/to/private/reference zsh native-physics/test_sphere.sh
```

The optional directory supplies `world-trimesh-reference.json`; matching native
metadata and SCL2 assets remain under ignored `local-only/site`. The current
`NativeGroundVehicle.installCell` method is extracted for that replay. Inputs
are read only, and reports/build outputs stay under ignored `local-only`.
No recorded game corpus or game assets are included in source control.

This is geometry/query regression evidence against an archived browser/WASM
reference, not proof of original retail GTA San Andreas behavior. Native device
and Simulator ABI/build checks remain separate integration gates.
