//! Native event values used by the archived chassis contact handler. No health
//! thresholds or damage formula are applied at this engine boundary.
use super::*;
use std::sync::Mutex;

#[derive(Clone)]
struct ContactRecord {
    colliders: [Id; 2],
    bodies: [Id; 2],
    force: [f32; 8],
    started: bool,
}
#[derive(Default)]
pub(super) struct ContactCollector {
    events: Mutex<Vec<ContactRecord>>,
}
impl ContactCollector {
    pub(super) fn clear(&self) {
        self.events
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clear();
    }
}
impl EventHandler for ContactCollector {
    fn handle_collision_event(
        &self,
        _: &RigidBodySet,
        _: &ColliderSet,
        _: CollisionEvent,
        _: Option<&ContactPair>,
    ) {
    }
    fn handle_contact_force_event(
        &self,
        dt: Real,
        bodies: &RigidBodySet,
        colliders: &ColliderSet,
        pair: &ContactPair,
        magnitude: Real,
    ) {
        let event = ContactForceEvent::from_contact_pair(dt, pair, magnitude);
        let Some(first) = colliders.get(event.collider1) else {
            return;
        };
        let Some(second) = colliders.get(event.collider2) else {
            return;
        };
        let body_id = |co: &Collider| {
            co.parent()
                .and_then(|h| bodies.get(h))
                .map(|b| b.user_data as Id)
                .unwrap_or(0)
        };
        let v = event.total_force;
        let d = event.max_force_direction;
        self.events
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .push(ContactRecord {
                colliders: [first.user_data as Id, second.user_data as Id],
                bodies: [body_id(first), body_id(second)],
                force: [
                    v.x,
                    v.y,
                    v.z,
                    event.total_force_magnitude,
                    d.x,
                    d.y,
                    d.z,
                    event.max_force_magnitude,
                ],
                started: event.started,
            });
    }
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_contact_events(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    enabled: u32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(h) = w.collider_ids.get(&id).copied() else {
        return 0;
    };
    let co = &mut w.colliders[h];
    let mut events = co.active_events();
    events.set(ActiveEvents::CONTACT_FORCE_EVENTS, enabled != 0);
    co.set_active_events(events); // Leave Rapier's original force threshold unchanged.
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_contact_events_count(ptr: *mut ZGTAPhysicsWorld) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    w.contact_events
        .events
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .len() as u32
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_contact_events_drain(
    ptr: *mut ZGTAPhysicsWorld,
    out_ids: *mut Id,
    out_forces: *mut f32,
    out_started: *mut u32,
    capacity: u32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    if capacity == 0 || capacity > 100000 || out_ids.is_null() || out_forces.is_null() {
        return 0;
    }
    let mut events = w
        .contact_events
        .events
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let count = events.len().min(capacity as usize);
    for (index, event) in events.drain(..count).enumerate() {
        slice::from_raw_parts_mut(out_ids.add(index * 4), 4).copy_from_slice(&[
            event.colliders[0],
            event.colliders[1],
            event.bodies[0],
            event.bodies[1],
        ]);
        slice::from_raw_parts_mut(out_forces.add(index * 8), 8).copy_from_slice(&event.force);
        if !out_started.is_null() {
            *out_started.add(index) = if event.started { 1 } else { 0 };
        }
    }
    count as u32
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_piece(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    piece: i32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(h) = w.collider_ids.get(&id).copied() else {
        return 0;
    };
    w.pieces.insert(h, piece);
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_shape_info(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    out_data: *mut f32,
    out_piece: *mut i32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(h) = w.collider_ids.get(&id).copied() else {
        return 0;
    };
    if out_data.is_null() {
        return 0;
    }
    w.bodies
        .propagate_modified_body_positions_to_colliders(&mut w.colliders);
    let co = &w.colliders[h];
    let rotation = co.rotation();
    let (kind, dimensions) = if let Some(ball) = co.shape().as_ball() {
        (1, [ball.radius, 0.0, 0.0])
    } else if let Some(box_shape) = co.shape().as_cuboid() {
        (
            2,
            [
                box_shape.half_extents.x,
                box_shape.half_extents.y,
                box_shape.half_extents.z,
            ],
        )
    } else if let Some(capsule) = co.shape().as_capsule() {
        (3, [capsule.half_height(), capsule.radius, 0.0])
    } else {
        (4, [0.0; 3])
    };
    slice::from_raw_parts_mut(out_data, 7).copy_from_slice(&[
        rotation.x,
        rotation.y,
        rotation.z,
        rotation.w,
        dimensions[0],
        dimensions[1],
        dimensions[2],
    ]);
    if !out_piece.is_null() {
        *out_piece = w.pieces.get(&h).copied().unwrap_or(-1)
    }
    kind
}
