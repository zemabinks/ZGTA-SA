//! Collider-wide public world classifications are distinct from raw SCL2 face
//! annotations. The original client groups meshes by these classifications.
use super::*;

#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_set_query_metadata(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    surface: i32,
    material: i32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(h) = w.collider_ids.get(&id).copied() else {
        return 0;
    };
    w.query_metadata.insert(h, (surface, material));
    1
}
#[no_mangle]
pub unsafe extern "C" fn zgtaphys_collider_query_metadata(
    ptr: *mut ZGTAPhysicsWorld,
    id: Id,
    out: *mut i32,
) -> u32 {
    let Some(w) = world(ptr) else { return 0 };
    let Some(h) = w.collider_ids.get(&id).copied() else {
        return 0;
    };
    let Some(&(surface, material)) = w.query_metadata.get(&h) else {
        return 0;
    };
    if out.is_null() {
        return 0;
    }
    slice::from_raw_parts_mut(out, 2).copy_from_slice(&[surface, material]);
    1
}
