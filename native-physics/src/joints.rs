//! Additive spherical-joint ABI. Local anchors use the caller's world axes.
use super::{floats, vector, world, Id, ZGTAPhysicsWorld};
use rapier3d::prelude::SphericalJointBuilder;

#[no_mangle]
pub unsafe extern "C" fn zgtaphys_joint_spherical(
    ptr: *mut ZGTAPhysicsWorld,
    body1: Id,
    body2: Id,
    anchors: *const f32,
    contacts_enabled: u32,
    wake_up: u32,
) -> Id {
    let Some(w) = world(ptr) else { return 0 };
    let Some(anchors) = floats(anchors, 6) else { return 0 };
    if body1 == body2 { return 0; }
    let (Some(&first), Some(&second)) = (w.body_ids.get(&body1), w.body_ids.get(&body2)) else {
        return 0;
    };
    let joint = SphericalJointBuilder::new()
        .local_anchor1(vector(&anchors[..3]))
        .local_anchor2(vector(&anchors[3..]))
        .contacts_enabled(contacts_enabled != 0);
    let handle = w.joints.insert(first, second, joint, wake_up != 0);
    let id = w.allocate();
    w.joint_ids.insert(id, handle);
    id
}

#[no_mangle]
pub unsafe extern "C" fn zgtaphys_joint_anchor1(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    anchor: *const f32,
    wake_up: u32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(anchor) = floats(anchor, 3) else { return 0 };
    let Some(&handle) = w.joint_ids.get(&id) else { return 0 };
    let Some(joint) = w.joints.get_mut(handle, wake_up != 0) else { return 0 };
    joint.data.set_local_anchor1(vector(anchor));
    1
}

#[no_mangle]
pub unsafe extern "C" fn zgtaphys_joint_remove(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    wake_up: u32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(handle) = w.joint_ids.remove(&id) else { return 0 };
    w.joints.remove(handle, wake_up != 0).is_some() as u32
}

#[no_mangle]
pub unsafe extern "C" fn zgtaphys_joint_info(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    bodies: *mut Id,
    anchors: *mut f32,
    contacts_enabled: *mut u32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    if bodies.is_null() || anchors.is_null() || contacts_enabled.is_null() { return 0; }
    let Some(handle) = w.joint_ids.get(&id) else { return 0 };
    let Some(joint) = w.joints.get(*handle) else { return 0 };
    let (Some(&first), Some(&second)) =
        (w.reverse_bodies.get(&joint.body1()), w.reverse_bodies.get(&joint.body2())) else { return 0 };
    let a = joint.data.local_anchor1();
    let b = joint.data.local_anchor2();
    std::ptr::copy_nonoverlapping([first, second].as_ptr(), bodies, 2);
    std::ptr::copy_nonoverlapping([a.x, a.y, a.z, b.x, b.y, b.z].as_ptr(), anchors, 6);
    *contacts_enabled = joint.data.contacts_enabled as u32;
    1
}
