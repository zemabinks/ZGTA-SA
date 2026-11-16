# Authored COL instances in the real native Rapier world

Run `python3 smoke_native_renderware_collision_world.py` after building the
owned Core102 host native library. `--library /absolute/directory` selects a
different host archive. The driver verifies `source-stamp.json` before linking;
it never builds, copies, or changes platform libraries. All test products remain
under ignored `local-only/research/runtime-collision-world`.

`NativeRenderWareCollisionWorld(world:limits:surfaceClass:)` owns kinematic
instances in an existing `SwiftRapierWorld`. `insert(Instance)` returns a handle
containing an entity ID, generation and private owner identity. `move(handle:to:)`
stages the next rigid GTA pose; the existing game loop still owns `world.step()`.
`remove`, `removeAll`, stale-handle rejection and failure rollback preserve native
body/collider ownership and aggregate budgets. No step callbacks are installed.

Authored spheres, boxes and main triangles remain local to their real kinematic
body. Points use `(x,y,z) -> (x,z,-y)` and quaternion imaginary components use the
same proper basis conjugation. Boxes swap Y/Z half extents. Main meshes use the
additive `zgtaphys_collider_trimesh_parented` ABI and Swift
`addTriangleMesh(_:body:localPose:friction:restitution:)` overload. This keeps
native parent motion, angular contact velocity and per-face metadata; meshes are
never rebuilt or world-baked when the object moves. The old standalone mesh ABI
and caller behaviour remain unchanged.

Camera-disabled instances expose `cameraExcludedColliderIDs`. The owner passes
these to camera queries only. Collision/solver groups remain unchanged, so those
same colliders still block pedestrians and vehicles. Raw COL material bytes are
retained in native material tags. Primitive flag/piece bytes and complete raw
surfaces remain available through collider/triangle `metadata`. COL has no
browser query-class field: the optional caller mapper supplies that class, or
it remains explicitly unclassified. Friction and restitution are explicit
instance coefficients, not inferred retail surface properties.

`motion(entityID:)` reads the actual native pose, linear velocity and angular
velocity back into GTA axes. Its point-velocity helper and entity/body lookup are
available for moving-support registration. Shadow triangles, visual geometry,
empty collision models and non-rigid transforms never become fallback colliders.
The owner confines this object and its world to one thread.

The native parented export validates world/parent membership, unit local/body
poses, finite coordinates within ±1,000,000, coefficient ranges, bounded counts
and triangle indices. It preserves the standalone path's default mesh flags,
face order, Average friction combination and per-face query metadata. Raw C IDs
are scoped to their originating world; the higher-level owner/generation handles
also reject cross-manager use. Existing source stamping includes the changed
Rust/header bytes, preventing a stale native archive from passing the driver.

Validation passed against the real freshly rebuilt host archive: 18 raw C
negative boundary cases, nonidentity collider-local poses, parent move/removal,
authored floor and wall raycasts, real KCC landing/blocking, a dynamic sphere
vehicle proxy, camera-only exclusion, moving-triangle contact velocity, full
multi-axis rotation/normal agreement, stale/foreign handles and resource limits.
All 584 owner DFFs were inspected; 212 authored models created and removed 5,632
native physical colliders with 2,666 main faces. Their 81,404 shadow faces created
no physics. A moved platform imparted 0.08174999 m/s to its contacting dynamic
body, confirming real kinematic contact rather than static mesh replacement.
The Swift bridge and owner also pass arm64 iOS 15 SDK typechecking.

These are authored collision/native bridge tests. They do not establish retail
gameplay feel, multiplayer synchronization, per-material retail friction, or a
physical iPhone comparison.
