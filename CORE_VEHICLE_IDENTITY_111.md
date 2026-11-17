# Per-occurrence vehicle rendering identity · Core111

Core110 could draw two distinct same-model vehicles at the same float position
using the first driver's roll and animated state. Its model tuple discarded
source identity, and both the draw transform and rig looked the owner up again
by model and position. A private authored host reproduction executed the full
old rig method and demonstrated shared wheel, steering, lighting, damage,
working-part and cache state. This is native source/host evidence, not a claim
that the defect occurred in a particular live capture or in original retail SA.

Each Core111 vehicle draw occurrence now retains explicit context: the own
vehicle's render snapshot, the actual remote-player snapshot, the actual parked
vehicle and physical render snapshot, or the carriage's parent/index and exact
transform. That context also retains its own appearance code and private cache
key. Model/position no longer selects a vehicle owner, transform or rig state.
Same-model coincident vehicles therefore keep their own roll, wheels, steering,
lights, damage, working parts and bike wrapper state. Parked and carriage exact
transforms no longer overwrite one another in position-keyed dictionaries.

Own physical and legacy wheel inputs are captured only for an explicit own
vehicle occurrence. A remote vehicle or carriage at the camera position cannot
consume the local vehicle's exact transform, wheel angles or controls. Existing
model-matrix algebra and the own legacy fallback remain; this change does not
move bodies, alter collision hulls, change rider transforms or grant authority.
The existing carriage wheel-spin timing is captured as before rather than
retuned here.

Private cache identities distinguish registry vehicles from IDless players
using a type and byte-length prefix. A registry ID such as `player:free-a`
cannot impersonate the IDless player fallback. Carriage ownership is an explicit
flag and includes its actual parent identity, so a real registry ID spelled
`own` cannot impersonate the local train. These keys are transient render state;
no wire ID, persistent save format or registry entry changes. A real registry
vehicle still shares its render cache across driver/parked transitions.

The skeletal pose/transform override queue was audited separately. It already
preserves insertion order for same-skin coincident riders and consumes each
record before mesh admission; it remains intact. One separate fallback used
model/position to apply the local action locomotion to a remote actor when its
queued pose was nil. The local-foot occurrence now has an explicit `ownFoot`
flag, and only that occurrence can request this fallback. Existing nonnil poses,
bone/clip sampling and rider overrides keep their precedence and behavior.

Core110's deferred transparent-vehicle encoder, source alpha/depth-write policy,
stable far-to-near sort, shared-ID parked exclusions, shared vehicle/rider-frame
lookup and remote animation recording remain. No shader, dependency, C/Rust ABI,
generated library, game resource or lighting policy changes are required.

Run the independent authored host gates on macOS with Xcode:

```sh
python3 smoke_native_vehicle_identity.py
python3 smoke_native_remote_appearance.py
python3 smoke_native_vehicle_transparency.py
```

The new gate passes **69** checks using actual extracted append, context,
transform, legacy-wheel, pose-queue/fallback selection and complete rig methods,
plus production rig pose math. It covers coincident, reversed, removed, IDless,
float-quantized, parked, own/remote and train-layout occurrences, key/sentinel
collisions and isolated position/model/role controls. Compact historical110
predicates and a positional carriage dictionary are retained as negative
controls; no sibling checkout is required. Existing gates pass17 packet/role
checks and27 material/deferred-encoder checks.

All fixture nodes, matrices, rows and scalar sentinels are authored source.
External physics boundaries are explicitly inert and original assets are not
loaded. Skeletal sentinels verify queue/selection ownership, not bone animation
math. The tests use no GPU, transport, Simulator or phone. Separate complete
Simulator Debug/device Release builds and normal Simulator passenger/own-Taxi
UI cases now pass; their captures, wire observations and limits are recorded in
[Core111 acceptance](CORE_NATIVE_ACCEPTANCE_111.md). Performance, physical-device
and original-retail parity remain open. No nighttime paint or lighting
explanation follows from this identity repair.
