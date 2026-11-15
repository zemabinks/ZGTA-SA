//! Thin C ABI over the exact native Rapier source used by the archived JS build.
//! Coordinates are passed unchanged; clients choose their world axis system.
mod contact_events;
mod query_metadata;
use rapier3d::parry::shape::FeatureId;
use rapier3d::prelude::*;
use std::{
    collections::{HashMap, HashSet},
    slice,
};

type Id = u64;
struct MeshInfo {
    surfaces: Vec<i32>,
    materials: Vec<i32>,
}
pub struct ZGTAPhysicsWorld {
    gravity: Vector,
    parameters: IntegrationParameters,
    pipeline: PhysicsPipeline,
    islands: IslandManager,
    broad: BroadPhaseBvh,
    narrow: NarrowPhase,
    bodies: RigidBodySet,
    colliders: ColliderSet,
    joints: ImpulseJointSet,
    multibody_joints: MultibodyJointSet,
    ccd: CCDSolver,
    body_ids: HashMap<Id, RigidBodyHandle>,
    collider_ids: HashMap<Id, ColliderHandle>,
    reverse_bodies: HashMap<RigidBodyHandle, Id>,
    meshes: HashMap<ColliderHandle, MeshInfo>,
    pieces: HashMap<ColliderHandle, i32>,
    query_metadata: HashMap<ColliderHandle, (i32, i32)>,
    contact_events: contact_events::ContactCollector,
    next_id: Id,
    archived_step: Option<(f32, f32, u32)>,
}
impl ZGTAPhysicsWorld {
    fn allocate(&mut self) -> Id {
        let id = self.next_id;
        self.next_id += 1;
        id
    }
    fn collider(
        &mut self,
        builder: ColliderBuilder,
        parent: Id,
        pose: Pose,
        friction: f32,
        restitution: f32,
    ) -> Id {
        if parent != 0 && !self.body_ids.contains_key(&parent) {
            return 0;
        }
        let id = self.allocate();
        let builder = builder
            .position(pose)
            .density(0.0)
            .friction(friction.max(0.0))
            .restitution(restitution.clamp(0.0, 1.0))
            .friction_combine_rule(CoefficientCombineRule::Min)
            .restitution_combine_rule(CoefficientCombineRule::Average)
            .user_data(id as u128);
        let handle = if parent == 0 {
            self.colliders.insert(builder)
        } else {
            self.colliders
                .insert_with_parent(builder, self.body_ids[&parent], &mut self.bodies)
        };
        self.collider_ids.insert(id, handle);
        id
    }
}
fn vector(values: &[f32]) -> Vector {
    Vector::new(values[0], values[1], values[2])
}
unsafe fn floats<'a>(ptr: *const f32, count: usize) -> Option<&'a [f32]> {
    if ptr.is_null() || count > 12_000_000 {
        return None;
    }
    let values = slice::from_raw_parts(ptr, count);
    values.iter().all(|v| v.is_finite()).then_some(values)
}
unsafe fn pose(ptr: *const f32) -> Option<Pose> {
    let p = floats(ptr, 7)?;
    let q = Rotation::from_xyzw(p[3], p[4], p[5], p[6]);
    if !q.length_squared().is_finite() || q.length_squared() < 0.000001 {
        return None;
    }
    Some(Pose::from_parts(vector(p), q))
}
unsafe fn mass(ptr: *const f32) -> Option<MassProperties> {
    let p = floats(ptr, 7)?;
    if p[0] <= 0.0 || p[4..7].iter().any(|v| *v <= 0.0) {
        return None;
    }
    Some(MassProperties::new(
        vector(&p[1..4]),
        p[0],
        vector(&p[4..7]),
    ))
}
unsafe fn world<'a>(ptr: *mut ZGTAPhysicsWorld) -> Option<&'a mut ZGTAPhysicsWorld> {
    ptr.as_mut()
}

#[no_mangle]
pub extern "C" fn zgtaphys_bridge_version() -> u32 {
    1
}
#[no_mangle]
pub extern "C" fn zgtaphys_world_new(x: f32, y: f32, z: f32) -> *mut ZGTAPhysicsWorld {
    if ![x, y, z].iter().all(|v| v.is_finite()) {
        return std::ptr::null_mut();
    }
    let mut parameters = IntegrationParameters::default();
    parameters.dt = 1.0 / 60.0;
    Box::into_raw(Box::new(ZGTAPhysicsWorld {
        gravity: Vector::new(x, y, z),
        parameters,
        pipeline: PhysicsPipeline::new(),
        islands: IslandManager::new(),
        broad: BroadPhaseBvh::new(),
        narrow: NarrowPhase::new(),
        bodies: RigidBodySet::new(),
        colliders: ColliderSet::new(),
        joints: ImpulseJointSet::new(),
        multibody_joints: MultibodyJointSet::new(),
        ccd: CCDSolver::new(),
        body_ids: HashMap::new(),
        collider_ids: HashMap::new(),
        reverse_bodies: HashMap::new(),
        meshes: HashMap::new(),
        pieces: HashMap::new(),
        query_metadata: HashMap::new(),
        contact_events: contact_events::ContactCollector::default(),
        next_id: 1,
        archived_step: None,
    }))
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_world_free(ptr: *mut ZGTAPhysicsWorld) {
    if !ptr.is_null() {
        drop(Box::from_raw(ptr))
    }
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_world_step(ptr: *mut ZGTAPhysicsWorld) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    if let Some((base, ulp, index)) = w.archived_step {
        let next = (index + 1) % 262144;
        w.parameters.normalized_prediction_distance = base + next as f32 * ulp;
        w.archived_step = Some((base, ulp, next));
    }
    w.contact_events.clear(); // Match EventQueue(true) auto-clear each physics step.
    w.pipeline.step(
        w.gravity,
        &w.parameters,
        &mut w.islands,
        &mut w.broad,
        &mut w.narrow,
        &mut w.bodies,
        &mut w.colliders,
        &mut w.joints,
        &mut w.multibody_joints,
        &mut w.ccd,
        &(),
        &w.contact_events,
    );
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_body_new(
    ptr: *mut ZGTAPhysicsWorld,
    kind: u32,
    transform: *const f32,
    mass_properties: *const f32,
    gravity_scale: f32,
) -> Id {
    let Some(w) = world(ptr) else { return 0 };
    let Some(pose) = pose(transform) else {
        return 0;
    };
    if !gravity_scale.is_finite() {
        return 0;
    }
    let builder = match kind {
        0 => RigidBodyBuilder::fixed(),
        1 => RigidBodyBuilder::dynamic(),
        2 => RigidBodyBuilder::kinematic_position_based(),
        3 => RigidBodyBuilder::kinematic_velocity_based(),
        _ => return 0,
    };
    let mut builder = builder
        .pose(pose)
        .gravity_scale(gravity_scale)
        .ccd_enabled(true)
        .can_sleep(false);
    if kind == 1 {
        let Some(props) = mass(mass_properties) else {
            return 0;
        };
        builder = builder.additional_mass_properties(props)
    }
    let id = w.allocate();
    let handle = w.bodies.insert(builder.user_data(id as u128));
    w.bodies[handle].recompute_mass_properties_from_colliders(&w.colliders);
    w.body_ids.insert(id, handle);
    w.reverse_bodies.insert(handle, id);
    id
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_body_remove(ptr: *mut ZGTAPhysicsWorld, id: Id) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(handle) = w.body_ids.remove(&id) else {
        return 0;
    };
    let attached: HashSet<_> = w.bodies[handle].colliders().iter().copied().collect();
    w.collider_ids.retain(|_, h| !attached.contains(h));
    w.meshes.retain(|h, _| !attached.contains(h));
    w.pieces.retain(|h, _| !attached.contains(h));
    w.query_metadata.retain(|h, _| !attached.contains(h));
    w.reverse_bodies.remove(&handle);
    w.bodies.remove(
        handle,
        &mut w.islands,
        &mut w.colliders,
        &mut w.joints,
        &mut w.multibody_joints,
        true,
    );
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_body_state(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    out: *mut f32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(handle) = w.body_ids.get(&id) else {
        return 0;
    };
    if out.is_null() {
        return 0;
    }
    let b = &w.bodies[*handle];
    let p = b.translation();
    let q = b.rotation();
    let v = b.linvel();
    let a = b.angvel();
    let values = [
        p.x, p.y, p.z, q.x, q.y, q.z, q.w, v.x, v.y, v.z, a.x, a.y, a.z,
    ];
    slice::from_raw_parts_mut(out, 13).copy_from_slice(&values);
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_body_set_state(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    input: *const f32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(p) = pose(input) else { return 0 };
    let Some(v) = floats(input, 13) else { return 0 };
    let Some(handle) = w.body_ids.get(&id) else {
        return 0;
    };
    let b = &mut w.bodies[*handle];
    b.set_position(p, true);
    b.set_linvel(vector(&v[7..10]), true);
    b.set_angvel(vector(&v[10..13]), true);
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_body_set_velocities(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    input: *const f32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(v) = floats(input, 6) else { return 0 };
    let Some(handle) = w.body_ids.get(&id) else {
        return 0;
    };
    let b = &mut w.bodies[*handle];
    b.set_linvel(vector(v), true);
    b.set_angvel(vector(&v[3..]), true);
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_body_set_mass(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    input: *const f32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(m) = mass(input) else { return 0 };
    let Some(handle) = w.body_ids.get(&id) else {
        return 0;
    };
    w.bodies[*handle].set_additional_mass_properties(m, true);
    w.bodies[*handle].recompute_mass_properties_from_colliders(&w.colliders);
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_body_impulse(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    input: *const f32,
    kind: u32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(v) = floats(input, if kind == 2 { 6 } else { 3 }) else {
        return 0;
    };
    let Some(handle) = w.body_ids.get(&id) else {
        return 0;
    };
    let b = &mut w.bodies[*handle];
    match kind {
        0 => b.apply_impulse(vector(v), true),
        1 => b.apply_torque_impulse(vector(v), true),
        2 => b.apply_impulse_at_point(vector(v), vector(&v[3..]), true),
        _ => return 0,
    };
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_ball(
    ptr: *mut ZGTAPhysicsWorld,
    parent: Id,
    radius: f32,
    transform: *const f32,
    friction: f32,
    restitution: f32,
) -> Id {
    let Some(w) = world(ptr) else { return 0 };
    let Some(p) = pose(transform) else { return 0 };
    if !radius.is_finite() || radius <= 0.0 || !friction.is_finite() || !restitution.is_finite() {
        return 0;
    }
    w.collider(
        ColliderBuilder::ball(radius),
        parent,
        p,
        friction,
        restitution,
    )
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_box(
    ptr: *mut ZGTAPhysicsWorld,
    parent: Id,
    half_extents: *const f32,
    transform: *const f32,
    friction: f32,
    restitution: f32,
) -> Id {
    let Some(w) = world(ptr) else { return 0 };
    let Some(p) = pose(transform) else { return 0 };
    let Some(h) = floats(half_extents, 3) else {
        return 0;
    };
    if h.iter().any(|x| *x <= 0.0) || !friction.is_finite() || !restitution.is_finite() {
        return 0;
    }
    w.collider(
        ColliderBuilder::cuboid(h[0], h[1], h[2]),
        parent,
        p,
        friction,
        restitution,
    )
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_convex(
    ptr: *mut ZGTAPhysicsWorld,
    parent: Id,
    vertices: *const f32,
    vertex_count: u32,
    transform: *const f32,
    friction: f32,
    restitution: f32,
) -> Id {
    let Some(w) = world(ptr) else { return 0 };
    let Some(p) = pose(transform) else { return 0 };
    if vertex_count < 4
        || vertex_count > 1_000_000
        || !friction.is_finite()
        || !restitution.is_finite()
    {
        return 0;
    }
    let Some(v) = floats(vertices, vertex_count as usize * 3) else {
        return 0;
    };
    let points: Vec<_> = v.chunks_exact(3).map(vector).collect();
    let Some(builder) = ColliderBuilder::convex_hull(&points) else {
        return 0;
    };
    w.collider(builder, parent, p, friction, restitution)
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_trimesh(
    ptr: *mut ZGTAPhysicsWorld,
    vertices: *const f32,
    vertex_count: u32,
    indices: *const u32,
    triangle_count: u32,
    surfaces: *const i32,
    materials: *const i32,
) -> Id {
    let Some(w) = world(ptr) else { return 0 };
    if vertex_count < 3
        || vertex_count > 1_000_000
        || triangle_count == 0
        || triangle_count > 1_000_000
        || indices.is_null()
    {
        return 0;
    }
    let Some(v) = floats(vertices, vertex_count as usize * 3) else {
        return 0;
    };
    let idx = slice::from_raw_parts(indices, triangle_count as usize * 3);
    if idx.iter().any(|i| *i >= vertex_count) {
        return 0;
    }
    let points = v.chunks_exact(3).map(vector).collect();
    let triangles = idx.chunks_exact(3).map(|v| [v[0], v[1], v[2]]).collect();
    let Ok(builder) = ColliderBuilder::trimesh(points, triangles) else {
        return 0;
    };
    let id = w.collider(builder, 0, Pose::IDENTITY, 0.8, 0.0);
    if id == 0 {
        return 0;
    }
    let count = triangle_count as usize;
    w.meshes.insert(
        w.collider_ids[&id],
        MeshInfo {
            surfaces: if surfaces.is_null() {
                vec![2; count]
            } else {
                slice::from_raw_parts(surfaces, count).to_vec()
            },
            materials: if materials.is_null() {
                vec![-1; count]
            } else {
                slice::from_raw_parts(materials, count).to_vec()
            },
        },
    );
    id
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_remove(ptr: *mut ZGTAPhysicsWorld, id: Id) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(handle) = w.collider_ids.remove(&id) else {
        return 0;
    };
    w.meshes.remove(&handle);
    w.pieces.remove(&handle);
    w.query_metadata.remove(&handle);
    w.colliders
        .remove(handle, &mut w.islands, &mut w.bodies, true);
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_enabled(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    enabled: u32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(handle) = w.collider_ids.get(&id) else {
        return 0;
    };
    w.colliders[*handle].set_enabled(enabled != 0);
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_surface(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    surface: i32,
    material: i32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(handle) = w.collider_ids.get(&id) else {
        return 0;
    };
    let count = w.meshes.get(handle).map(|m| m.surfaces.len()).unwrap_or(1);
    w.meshes.insert(
        *handle,
        MeshInfo {
            surfaces: vec![surface; count],
            materials: vec![material; count],
        },
    );
    1
}
fn groups(packed: u32) -> InteractionGroups {
    InteractionGroups::new(
        Group::from_bits_retain(packed >> 16),
        Group::from_bits_retain(packed & 0xffff),
        InteractionTestMode::And,
    )
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_groups(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    collision: u32,
    solver: u32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(handle) = w.collider_ids.get(&id) else {
        return 0;
    };
    let co = &mut w.colliders[*handle];
    co.set_collision_groups(groups(collision));
    co.set_solver_groups(groups(solver));
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_raycast_groups(
    ptr: *mut ZGTAPhysicsWorld,
    origin: *const f32,
    direction: *const f32,
    max_distance: f32,
    query_groups: u32,
    exclude_body: Id,
    excluded: *const Id,
    excluded_count: u32,
    out_geometry: *mut f32,
    out_info: *mut i32,
    out_body: *mut Id,
) -> Id {
    let Some(w) = world(ptr) else { return 0 };
    let Some(o) = floats(origin, 3) else { return 0 };
    let Some(d) = floats(direction, 3) else {
        return 0;
    };
    let d = vector(d);
    if !max_distance.is_finite()
        || max_distance <= 0.0
        || !d.length_squared().is_finite()
        || d.length_squared() < 0.000001
        || excluded_count > 100000
    {
        return 0;
    }
    let ignored = if excluded_count == 0 {
        &[][..]
    } else if excluded.is_null() {
        return 0;
    } else {
        slice::from_raw_parts(excluded, excluded_count as usize)
    };
    let exclude = w.body_ids.get(&exclude_body).copied();
    w.bodies
        .propagate_modified_body_positions_to_colliders(&mut w.colliders);
    let ray = Ray::new(vector(o), d);
    let mut closest = max_distance;
    let mut result = None;
    // Shapes retain their own acceleration structures (including SCL2 triangle
    // BVHs). Direct shape queries also work before the first physics step and
    // immediately after streaming/removing a cell, without stale broad-phase data.
    for (handle, co) in w.colliders.iter() {
        let id = co.user_data as Id;
        if !co.is_enabled()
            || co.is_sensor()
            || ignored.contains(&id)
            || !co.collision_groups().test(groups(query_groups))
            || exclude.is_some() && co.parent() == exclude
        {
            continue;
        }
        if let Some(hit) = co
            .shape()
            .cast_ray_and_get_normal(co.position(), &ray, closest, true)
        {
            if hit.time_of_impact <= closest {
                closest = hit.time_of_impact;
                result = Some((handle, hit))
            }
        }
    }
    let Some((handle, hit)) = result else {
        return 0;
    };
    let co = &w.colliders[handle];
    let point = ray.origin + ray.dir * hit.time_of_impact;
    if !out_geometry.is_null() {
        slice::from_raw_parts_mut(out_geometry, 7).copy_from_slice(&[
            hit.time_of_impact,
            hit.normal.x,
            hit.normal.y,
            hit.normal.z,
            point.x,
            point.y,
            point.z,
        ])
    }
    let triangle = match hit.feature {
        FeatureId::Face(index) => index as usize,
        _ => usize::MAX,
    };
    let metadata = w.meshes.get(&handle);
    let index = metadata.map(|m| triangle % m.surfaces.len()).unwrap_or(0);
    if !out_info.is_null() {
        slice::from_raw_parts_mut(out_info, 3).copy_from_slice(&[
            if triangle == usize::MAX {
                -1
            } else {
                index as i32
            },
            metadata.map(|m| m.surfaces[index]).unwrap_or(2),
            metadata.map(|m| m.materials[index]).unwrap_or(-1),
        ])
    }
    if !out_body.is_null() {
        *out_body = co
            .parent()
            .and_then(|h| w.reverse_bodies.get(&h).copied())
            .unwrap_or(0)
    }
    co.user_data as Id
}

#[no_mangle]
pub unsafe extern "C" fn zgtaphys_raycast(
    ptr: *mut ZGTAPhysicsWorld,
    origin: *const f32,
    direction: *const f32,
    max_distance: f32,
    exclude_body: Id,
    excluded: *const Id,
    excluded_count: u32,
    out_geometry: *mut f32,
    out_info: *mut i32,
    out_body: *mut Id,
) -> Id {
    zgtaphys_raycast_groups(
        ptr,
        origin,
        direction,
        max_distance,
        0xffffffff,
        exclude_body,
        excluded,
        excluded_count,
        out_geometry,
        out_info,
        out_body,
    )
}

#[no_mangle]
pub unsafe extern "C" fn zgtaphys_body_next_kinematic(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    input: *const f32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(p) = pose(input) else { return 0 };
    let Some(handle) = w.body_ids.get(&id) else {
        return 0;
    };
    w.bodies[*handle].set_next_kinematic_position(p);
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_capsule(
    ptr: *mut ZGTAPhysicsWorld,
    parent: Id,
    half_height: f32,
    radius: f32,
    transform: *const f32,
    friction: f32,
    restitution: f32,
) -> Id {
    let Some(w) = world(ptr) else { return 0 };
    let Some(p) = pose(transform) else { return 0 };
    if !half_height.is_finite()
        || half_height < 0.0
        || !radius.is_finite()
        || radius <= 0.0
        || !friction.is_finite()
        || !restitution.is_finite()
    {
        return 0;
    }
    w.collider(
        ColliderBuilder::capsule_y(half_height, radius),
        parent,
        p,
        friction,
        restitution,
    )
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_character_move_filtered(
    ptr: *mut ZGTAPhysicsWorld,
    collider: Id,
    desired: *const f32,
    parameters: *const f32,
    options: u32,
    query_groups: u32,
    query_flags: u32,
    excluded_colliders: *const Id,
    excluded_collider_count: u32,
    excluded_bodies: *const Id,
    excluded_body_count: u32,
    out_movement: *mut f32,
    out_colliders: *mut Id,
    out_collisions: *mut f32,
    capacity: u32,
    out_count: *mut u32,
) -> u32 {
    use rapier3d::control::{CharacterAutostep, CharacterLength, KinematicCharacterController};
    let Some(w) = world(ptr) else { return 0 };
    let Some(translation) = floats(desired, 3) else {
        return 0;
    };
    let Some(p) = floats(parameters, 12) else {
        return 0;
    };
    let Some(handle) = w.collider_ids.get(&collider).copied() else {
        return 0;
    };
    if out_movement.is_null()
        || capacity > 4096
        || capacity > 0 && (out_colliders.is_null() || out_collisions.is_null())
        || p[0] <= 0.0
        || p[11] <= 0.0
        || p[11] > 1.0
    {
        return 0;
    }
    let up = vector(&p[1..4]);
    if !up.length_squared().is_finite() || up.length_squared() < 0.000001 {
        return 0;
    }
    w.bodies
        .propagate_modified_body_positions_to_colliders(&mut w.colliders);
    let co = &w.colliders[handle];
    let shape = co.shared_shape().clone();
    let pose = *co.position();
    let parent = co.parent();
    let controller = KinematicCharacterController {
        up: up.normalize(),
        offset: CharacterLength::Absolute(p[0]),
        slide: options & 1 != 0,
        max_slope_climb_angle: p[4],
        min_slope_slide_angle: p[5],
        snap_to_ground: if p[6] < 0.0 {
            None
        } else if options & 8 != 0 {
            Some(CharacterLength::Relative(p[6]))
        } else {
            Some(CharacterLength::Absolute(p[6]))
        },
        autostep: if p[7] < 0.0 {
            None
        } else {
            Some(CharacterAutostep {
                max_height: CharacterLength::Absolute(p[7]),
                min_width: CharacterLength::Absolute(p[8]),
                include_dynamic_bodies: options & 2 != 0,
            })
        },
        normal_nudge_factor: p[9].max(0.0),
    };
    // Rebuild a small query broad-phase independently of the physics pipeline.
    // This sees streamed shapes and moved kinematic bodies before the first
    // step without consuming the real solver's collision-pair changes.
    let mut tree = rapier3d::parry::partitioning::Bvh::new();
    for (h, co) in w.colliders.iter() {
        if co.is_enabled() {
            tree.insert(co.compute_aabb(), h.into_raw_parts().0)
        }
    }
    let Some(ignored_colliders) = ids(excluded_colliders, excluded_collider_count) else {
        return 0;
    };
    let Some(ignored_bodies) = ids(excluded_bodies, excluded_body_count) else {
        return 0;
    };
    let ignored_handles: HashSet<_> = ignored_bodies
        .iter()
        .filter_map(|id| w.body_ids.get(id).copied())
        .collect();
    let predicate = |_handle: ColliderHandle, co: &Collider| {
        !ignored_colliders.contains(&(co.user_data as Id))
            && co
                .parent()
                .map(|h| !ignored_handles.contains(&h))
                .unwrap_or(true)
    };
    let filter = QueryFilter {
        flags: QueryFilterFlags::from_bits_truncate(query_flags),
        groups: if options & 16 != 0 {
            Some(groups(query_groups))
        } else {
            None
        },
        exclude_collider: Some(handle),
        exclude_rigid_body: parent,
        predicate: Some(&predicate),
    };
    let mut queries = QueryPipelineMut {
        dispatcher: w.narrow.query_dispatcher(),
        bvh: &tree,
        bodies: &mut w.bodies,
        colliders: &mut w.colliders,
        filter,
    };
    let mut events = Vec::new();
    let movement = controller.move_shape(
        p[11],
        &queries.as_ref(),
        &*shape,
        &pose,
        vector(translation),
        |hit| events.push(hit),
    );
    if options & 4 != 0 && p[10] > 0.0 {
        controller.solve_character_collision_impulses(
            p[11],
            &mut queries,
            &*shape,
            p[10],
            events.iter(),
        )
    }
    slice::from_raw_parts_mut(out_movement, 5).copy_from_slice(&[
        movement.translation.x,
        movement.translation.y,
        movement.translation.z,
        if movement.grounded { 1.0 } else { 0.0 },
        if movement.is_sliding_down_slope {
            1.0
        } else {
            0.0
        },
    ]);
    let count = events.len().min(capacity as usize);
    if !out_count.is_null() {
        *out_count = count as u32
    }
    if count > 0 {
        let ids = slice::from_raw_parts_mut(out_colliders, count);
        let data = slice::from_raw_parts_mut(out_collisions, count * 10);
        for (index, event) in events.iter().take(count).enumerate() {
            ids[index] = w.colliders[event.handle].user_data as Id;
            let n = event.hit.normal1;
            let point = event.hit.witness1;
            let applied = event.translation_applied;
            data[index * 10..index * 10 + 10].copy_from_slice(&[
                event.hit.time_of_impact,
                n.x,
                n.y,
                n.z,
                point.x,
                point.y,
                point.z,
                applied.x,
                applied.y,
                applied.z,
            ]);
        }
    }
    1
}

#[no_mangle]
pub unsafe extern "C" fn zgtaphys_character_move(
    ptr: *mut ZGTAPhysicsWorld,
    collider: Id,
    desired: *const f32,
    parameters: *const f32,
    options: u32,
    query_groups: u32,
    query_flags: u32,
    out_movement: *mut f32,
    out_colliders: *mut Id,
    out_collisions: *mut f32,
    capacity: u32,
    out_count: *mut u32,
) -> u32 {
    zgtaphys_character_move_filtered(
        ptr,
        collider,
        desired,
        parameters,
        options | 16,
        query_groups,
        query_flags,
        std::ptr::null(),
        0,
        std::ptr::null(),
        0,
        out_movement,
        out_colliders,
        out_collisions,
        capacity,
        out_count,
    )
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_archived_stepping(
    ptr: *mut ZGTAPhysicsWorld,
    enabled: u32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    if enabled != 0 {
        let base = IntegrationParameters::default().normalized_prediction_distance;
        let ulp = 2.0f32.powf(base.log2().floor() - 23.0);
        w.archived_step = Some((base, ulp, 0));
        w.parameters.normalized_prediction_distance = base;
    } else {
        w.archived_step = None;
        w.parameters.normalized_prediction_distance =
            IntegrationParameters::default().normalized_prediction_distance;
    }
    1
}
unsafe fn ids<'a>(ptr: *const Id, count: u32) -> Option<&'a [Id]> {
    if count > 100000 {
        return None;
    }
    if count == 0 {
        return Some(&[]);
    }
    if ptr.is_null() {
        None
    } else {
        Some(slice::from_raw_parts(ptr, count as usize))
    }
}
fn accepts(
    w: &ZGTAPhysicsWorld,
    co: &Collider,
    query_groups: u32,
    flags: u32,
    options: u32,
    ignored_colliders: &[Id],
    ignored_bodies: &[Id],
) -> bool {
    if !co.is_enabled()
        || ignored_colliders.contains(&(co.user_data as Id))
        || !QueryFilterFlags::from_bits_truncate(flags).test(&w.bodies, co)
        || options & 1 != 0 && !co.collision_groups().test(groups(query_groups))
    {
        return false;
    }
    if let Some(parent) = co.parent() {
        !ignored_bodies.contains(&w.reverse_bodies.get(&parent).copied().unwrap_or(0))
    } else {
        options & 2 == 0
    }
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_translation(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    position: *const f32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(p) = floats(position, 3) else {
        return 0;
    };
    let Some(handle) = w.collider_ids.get(&id).copied() else {
        return 0;
    };
    w.colliders[handle].set_translation(vector(p));
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_info(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    out_position: *mut f32,
    out_body: *mut Id,
    out_dynamic: *mut u32,
    out_material: *mut i32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(h) = w.collider_ids.get(&id).copied() else {
        return 0;
    };
    w.bodies
        .propagate_modified_body_positions_to_colliders(&mut w.colliders);
    let co = &w.colliders[h];
    if !out_position.is_null() {
        let p = co.translation();
        slice::from_raw_parts_mut(out_position, 3).copy_from_slice(&[p.x, p.y, p.z]);
    }
    if !out_body.is_null() {
        *out_body = co
            .parent()
            .and_then(|h| w.reverse_bodies.get(&h).copied())
            .unwrap_or(0)
    }
    if !out_dynamic.is_null() {
        *out_dynamic = if co
            .parent()
            .map(|h| w.bodies[h].is_dynamic())
            .unwrap_or(false)
        {
            1
        } else {
            0
        }
    }
    if !out_material.is_null() {
        *out_material = w
            .query_metadata
            .get(&h)
            .map(|value| value.1)
            .or_else(|| w.meshes.get(&h).and_then(|m| m.materials.first()).copied())
            .unwrap_or(-1)
    }
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_intersections_capsule(
    ptr: *mut ZGTAPhysicsWorld,
    position: *const f32,
    half_height: f32,
    radius: f32,
    query_groups: u32,
    query_flags: u32,
    options: u32,
    excluded_colliders: *const Id,
    excluded_collider_count: u32,
    excluded_bodies: *const Id,
    excluded_body_count: u32,
    out_colliders: *mut Id,
    capacity: u32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(p) = floats(position, 3) else {
        return 0;
    };
    let Some(ec) = ids(excluded_colliders, excluded_collider_count) else {
        return 0;
    };
    let Some(eb) = ids(excluded_bodies, excluded_body_count) else {
        return 0;
    };
    if capacity > 100000
        || capacity > 0 && out_colliders.is_null()
        || !half_height.is_finite()
        || half_height < 0.0
        || !radius.is_finite()
        || radius <= 0.0
    {
        return 0;
    }
    w.bodies
        .propagate_modified_body_positions_to_colliders(&mut w.colliders);
    let shape = SharedShape::capsule_y(half_height, radius);
    let pose = Pose::from_translation(vector(p));
    let mut count = 0;
    for (_, co) in w.colliders.iter() {
        if !accepts(w, co, query_groups, query_flags, options, ec, eb) {
            continue;
        }
        if rapier3d::parry::query::intersection_test(&pose, &*shape, co.position(), co.shape())
            .unwrap_or(false)
        {
            if count < capacity as usize {
                *out_colliders.add(count) = co.user_data as Id;
                count += 1
            } else {
                break;
            }
        }
    }
    count as u32
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_contact(
    ptr: *mut ZGTAPhysicsWorld,
    first: Id,
    second: Id,
    prediction: f32,
    out: *mut f32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    if out.is_null() || !prediction.is_finite() || prediction < 0.0 {
        return 0;
    }
    let Some(a) = w.collider_ids.get(&first).copied() else {
        return 0;
    };
    let Some(b) = w.collider_ids.get(&second).copied() else {
        return 0;
    };
    w.bodies
        .propagate_modified_body_positions_to_colliders(&mut w.colliders);
    let a = &w.colliders[a];
    let b = &w.colliders[b];
    let Ok(Some(hit)) = rapier3d::parry::query::contact(
        a.position(),
        a.shape(),
        b.position(),
        b.shape(),
        prediction,
    ) else {
        return 0;
    };
    let n = hit.normal2;
    let a = hit.point1;
    let b = hit.point2;
    slice::from_raw_parts_mut(out, 10)
        .copy_from_slice(&[hit.dist, n.x, n.y, n.z, a.x, a.y, a.z, b.x, b.y, b.z]);
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_project_point(
    ptr: *mut ZGTAPhysicsWorld,
    collider: Id,
    point: *const f32,
    solid: u32,
    out: *mut f32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(p) = floats(point, 3) else { return 0 };
    let Some(h) = w.collider_ids.get(&collider).copied() else {
        return 0;
    };
    if out.is_null() {
        return 0;
    }
    w.bodies
        .propagate_modified_body_positions_to_colliders(&mut w.colliders);
    let co = &w.colliders[h];
    let projected = co
        .shape()
        .project_point(co.position(), vector(p), solid != 0);
    let p = projected.point;
    slice::from_raw_parts_mut(out, 3).copy_from_slice(&[p.x, p.y, p.z]);
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_query_ray(
    ptr: *mut ZGTAPhysicsWorld,
    origin: *const f32,
    direction: *const f32,
    distance: f32,
    query_groups: u32,
    query_flags: u32,
    options: u32,
    excluded_colliders: *const Id,
    excluded_collider_count: u32,
    excluded_bodies: *const Id,
    excluded_body_count: u32,
    out_geometry: *mut f32,
) -> Id {
    let Some(w) = world(ptr) else { return 0 };
    let Some(p) = floats(origin, 3) else { return 0 };
    let Some(d) = floats(direction, 3) else {
        return 0;
    };
    let Some(ec) = ids(excluded_colliders, excluded_collider_count) else {
        return 0;
    };
    let Some(eb) = ids(excluded_bodies, excluded_body_count) else {
        return 0;
    };
    let d = vector(d);
    if !distance.is_finite()
        || distance <= 0.0
        || !d.length_squared().is_finite()
        || d.length_squared() < 0.000001
    {
        return 0;
    }
    w.bodies
        .propagate_modified_body_positions_to_colliders(&mut w.colliders);
    let ray = Ray::new(vector(p), d);
    let mut closest = distance;
    let mut result = None;
    for (_, co) in w.colliders.iter() {
        if !accepts(w, co, query_groups, query_flags, options, ec, eb) {
            continue;
        }
        if let Some(hit) = co
            .shape()
            .cast_ray_and_get_normal(co.position(), &ray, closest, true)
        {
            closest = hit.time_of_impact;
            result = Some((co.user_data as Id, hit));
        }
    }
    let Some((id, hit)) = result else { return 0 };
    if !out_geometry.is_null() {
        let n = hit.normal;
        let p = ray.point_at(hit.time_of_impact);
        slice::from_raw_parts_mut(out_geometry, 7).copy_from_slice(&[
            hit.time_of_impact,
            n.x,
            n.y,
            n.z,
            p.x,
            p.y,
            p.z,
        ]);
    }
    id
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_cast_ball(
    ptr: *mut ZGTAPhysicsWorld,
    origin: *const f32,
    direction: *const f32,
    radius: f32,
    distance: f32,
    query_groups: u32,
    query_flags: u32,
    options: u32,
    excluded_colliders: *const Id,
    excluded_collider_count: u32,
    excluded_bodies: *const Id,
    excluded_body_count: u32,
    out_geometry: *mut f32,
) -> Id {
    let Some(w) = world(ptr) else { return 0 };
    let Some(p) = floats(origin, 3) else { return 0 };
    let Some(d) = floats(direction, 3) else {
        return 0;
    };
    let Some(ec) = ids(excluded_colliders, excluded_collider_count) else {
        return 0;
    };
    let Some(eb) = ids(excluded_bodies, excluded_body_count) else {
        return 0;
    };
    let d = vector(d);
    if !radius.is_finite()
        || radius <= 0.0
        || !distance.is_finite()
        || distance <= 0.0
        || !d.length_squared().is_finite()
        || d.length_squared() < 0.000001
    {
        return 0;
    }
    w.bodies
        .propagate_modified_body_positions_to_colliders(&mut w.colliders);
    let shape = SharedShape::ball(radius);
    let pose = Pose::from_translation(vector(p));
    let mut closest = distance;
    let mut result = None;
    for (_, co) in w.colliders.iter() {
        if !accepts(w, co, query_groups, query_flags, options, ec, eb) {
            continue;
        }
        let options = rapier3d::parry::query::ShapeCastOptions::with_max_time_of_impact(closest);
        if let Ok(Some(hit)) = rapier3d::parry::query::cast_shapes(
            co.position(),
            Vector::ZERO,
            co.shape(),
            &pose,
            d,
            &*shape,
            options,
        ) {
            closest = hit.time_of_impact;
            result = Some((co.user_data as Id, hit, co.position()));
        }
    }
    let Some((id, hit, pose)) = result else {
        return 0;
    };
    if !out_geometry.is_null() {
        let n = pose.rotation * hit.normal1;
        let p = pose * hit.witness1;
        slice::from_raw_parts_mut(out_geometry, 7).copy_from_slice(&[
            hit.time_of_impact,
            n.x,
            n.y,
            n.z,
            p.x,
            p.y,
            p.z,
        ]);
    }
    id
}
