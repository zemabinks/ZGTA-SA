#ifndef ZGTA_RAPIER_H
#define ZGTA_RAPIER_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct ZGTAPhysicsWorld ZGTAPhysicsWorld;
uint32_t zgtaphys_bridge_version(void);
ZGTAPhysicsWorld *zgtaphys_world_new(float gravity_x,float gravity_y,float gravity_z);
void zgtaphys_world_free(ZGTAPhysicsWorld *world);
uint32_t zgtaphys_world_step(ZGTAPhysicsWorld *world); /* exactly 1/60 second */
/* transform[7]: position xyz, quaternion xyzw. mass[7]: mass,COM xyz,inertia xyz. */
uint64_t zgtaphys_body_new(ZGTAPhysicsWorld*,uint32_t kind,const float *transform,const float *mass,float gravity_scale);
uint32_t zgtaphys_body_remove(ZGTAPhysicsWorld*,uint64_t body);
/* Spherical impulse joint: anchors[6] are body1/body2 LOCAL xyz. Contacts are
 * disabled for towing. Opaque joint IDs belong to this world and are invalidated
 * by either body's removal. No angular motor, spring or impulse break is added. */
uint64_t zgtaphys_joint_spherical(ZGTAPhysicsWorld*,uint64_t body1,uint64_t body2,const float *anchors,uint32_t contacts_enabled,uint32_t wake_up);
uint32_t zgtaphys_joint_anchor1(ZGTAPhysicsWorld*,uint64_t joint,const float *anchor_xyz,uint32_t wake_up);
uint32_t zgtaphys_joint_remove(ZGTAPhysicsWorld*,uint64_t joint,uint32_t wake_up);
/* All output pointers required. bodies[2], anchors[6], contacts_enabled[1]. */
uint32_t zgtaphys_joint_info(ZGTAPhysicsWorld*,uint64_t joint,uint64_t *bodies,float *anchors,uint32_t *contacts_enabled);
/* state[13]: position xyz, quaternion xyzw, linear xyz, angular xyz. */
uint32_t zgtaphys_body_state(ZGTAPhysicsWorld*,uint64_t body,float *state);
uint32_t zgtaphys_body_set_state(ZGTAPhysicsWorld*,uint64_t body,const float *state);
uint32_t zgtaphys_body_set_velocities(ZGTAPhysicsWorld*,uint64_t body,const float *linear_angular_xyz);
uint32_t zgtaphys_body_set_mass(ZGTAPhysicsWorld*,uint64_t body,const float *mass);
/* Creation/set_mass leave effective mass pending until step or explicit recompute. */
uint32_t zgtaphys_body_mass(ZGTAPhysicsWorld*,uint64_t body,float *mass);
uint32_t zgtaphys_body_recompute_mass(ZGTAPhysicsWorld*,uint64_t body);
/* Original coefficient rule IDs:0Average,1Min,2Multiply,3Max. */
uint32_t zgtaphys_collider_friction_combine(ZGTAPhysicsWorld*,uint64_t collider,uint32_t rule);
/* kind0 linear impulse xyz; kind1 torque impulse xyz; kind2 impulse xyz + point xyz. */
uint32_t zgtaphys_body_impulse(ZGTAPhysicsWorld*,uint64_t body,const float *impulse,uint32_t kind);
uint64_t zgtaphys_collider_ball(ZGTAPhysicsWorld*,uint64_t body,float radius,const float *transform,float friction,float restitution);
uint64_t zgtaphys_collider_box(ZGTAPhysicsWorld*,uint64_t body,const float *half_extents,const float *transform,float friction,float restitution);
uint64_t zgtaphys_collider_convex(ZGTAPhysicsWorld*,uint64_t body,const float *vertices,uint32_t vertex_count,const float *transform,float friction,float restitution);
uint64_t zgtaphys_collider_trimesh(ZGTAPhysicsWorld*,const float *vertices,uint32_t vertex_count,const uint32_t *indices,uint32_t triangle_count,const int32_t *surfaces,const int32_t *materials);
/* Additive parented mesh API. Parent must exist in this world. Vertices and
 * transform[7] are LOCAL to that body; unit quaternion and finite coordinates
 * within +/-1,000,000 are required. Per-face metadata/order and mesh flags match
 * the standalone API; no world-space vertex baking is performed. */
uint64_t zgtaphys_collider_trimesh_parented(ZGTAPhysicsWorld*,uint64_t body,const float *vertices,uint32_t vertex_count,const uint32_t *indices,uint32_t triangle_count,const int32_t *surfaces,const int32_t *materials,const float *transform,float friction,float restitution);
uint32_t zgtaphys_collider_remove(ZGTAPhysicsWorld*,uint64_t collider);
uint32_t zgtaphys_collider_enabled(ZGTAPhysicsWorld*,uint64_t collider,uint32_t enabled);
uint32_t zgtaphys_collider_surface(ZGTAPhysicsWorld*,uint64_t collider,int32_t surface,int32_t material);
uint32_t zgtaphys_collider_groups(ZGTAPhysicsWorld*,uint64_t collider,uint32_t collision_groups,uint32_t solver_groups);
/* Returns colliderID or0. geometry[7]:distance,normalxyz,pointxyz;info[3]:triangle,surface,material. */
uint64_t zgtaphys_raycast(ZGTAPhysicsWorld*,const float *origin,const float *direction,float max_distance,uint64_t exclude_body,const uint64_t *excluded_colliders,uint32_t excluded_count,float *geometry,int32_t *info,uint64_t *hit_body);
uint64_t zgtaphys_raycast_groups(ZGTAPhysicsWorld*,const float *origin,const float *direction,float max_distance,uint32_t query_groups,uint64_t exclude_body,const uint64_t *excluded_colliders,uint32_t excluded_count,float *geometry,int32_t *info,uint64_t *hit_body);
uint32_t zgtaphys_body_next_kinematic(ZGTAPhysicsWorld*,uint64_t body,const float *transform);
uint64_t zgtaphys_collider_capsule(ZGTAPhysicsWorld*,uint64_t body,float half_height,float radius,const float *transform,float friction,float restitution);
/* parameters[12]: offset,upXYZ,maxSlope,minSlope,snap(-1off),stepHeight(-1off),stepWidth,nudge,mass,dt.
 * options:1slide,2stepDynamic,4applyImpulses,8relativeSnap. movement[5]:translationXYZ,grounded,sliding.
 * collisions[capacity*10]:TOI,normalXYZ,witnessXYZ,appliedTranslationXYZ. */
uint32_t zgtaphys_character_move(ZGTAPhysicsWorld*,uint64_t collider,const float *desired,const float *parameters,uint32_t options,uint32_t query_groups,uint32_t query_flags,float *movement,uint64_t *colliderIDs,float *collisions,uint32_t capacity,uint32_t *collision_count);
/* Archived public world factory increments prediction distance by one f32 ULP per tick. */
uint32_t zgtaphys_archived_stepping(ZGTAPhysicsWorld*,uint32_t enabled);
uint32_t zgtaphys_collider_translation(ZGTAPhysicsWorld*,uint64_t collider,const float *position);
/* LOCAL parent offset; standalone collider is an accepted no-op, as in Rapier. */
uint32_t zgtaphys_collider_translation_wrt_parent(ZGTAPhysicsWorld*,uint64_t collider,const float *position);
uint32_t zgtaphys_collider_info(ZGTAPhysicsWorld*,uint64_t collider,float *position,uint64_t *body,uint32_t *dynamic,int32_t *material);
/* Query options bit1: groups supplied; bit2: require a parent body. Flags are Rapier QueryFilterFlags. */
uint32_t zgtaphys_intersections_capsule(ZGTAPhysicsWorld*,const float *position,float half_height,float radius,uint32_t groups,uint32_t flags,uint32_t options,const uint64_t *excluded_colliders,uint32_t collider_count,const uint64_t *excluded_bodies,uint32_t body_count,uint64_t *colliders,uint32_t capacity);
/* Literal Ball query, otherwise identical filtering and buffer contract. */
uint32_t zgtaphys_intersections_sphere(ZGTAPhysicsWorld*,const float *position,float radius,uint32_t groups,uint32_t flags,uint32_t options,const uint64_t *excluded_colliders,uint32_t collider_count,const uint64_t *excluded_bodies,uint32_t body_count,uint64_t *colliders,uint32_t capacity);
/* contact[10]: distance,normal2XYZ,point1XYZ,point2XYZ, in world coordinates. */
uint32_t zgtaphys_contact(ZGTAPhysicsWorld*,uint64_t first,uint64_t second,float prediction,float *contact);
uint32_t zgtaphys_project_point(ZGTAPhysicsWorld*,uint64_t collider,const float *point,uint32_t solid,float *projected);
uint64_t zgtaphys_query_ray(ZGTAPhysicsWorld*,const float *origin,const float *direction,float distance,uint32_t groups,uint32_t flags,uint32_t options,const uint64_t *excluded_colliders,uint32_t collider_count,const uint64_t *excluded_bodies,uint32_t body_count,float *geometry);
uint64_t zgtaphys_cast_ball(ZGTAPhysicsWorld*,const float *origin,const float *direction,float radius,float distance,uint32_t groups,uint32_t flags,uint32_t options,const uint64_t *excluded_colliders,uint32_t collider_count,const uint64_t *excluded_bodies,uint32_t body_count,float *geometry);
/* Same movement ABI, with explicit exclusion sets and options bit16 for an optional groups filter. */
uint32_t zgtaphys_character_move_filtered(ZGTAPhysicsWorld*,uint64_t collider,const float *desired,const float *parameters,uint32_t options,uint32_t query_groups,uint32_t query_flags,const uint64_t *excluded_colliders,uint32_t collider_count,const uint64_t *excluded_bodies,uint32_t body_count,float *movement,uint64_t *colliderIDs,float *collisions,uint32_t capacity,uint32_t *collision_count);
/* Native contact events: no game damage threshold/scaling is applied. Auto-cleared each step.
 * ids[capacity*4]: collider1,collider2,body1,body2 (0 if standalone).
 * forces[capacity*8]: totalForceXYZ,totalForceMagnitude,maxForceDirectionXYZ,maxForceMagnitude. */
uint32_t zgtaphys_collider_contact_events(ZGTAPhysicsWorld*,uint64_t collider,uint32_t enabled);
uint32_t zgtaphys_contact_events_count(ZGTAPhysicsWorld*);
uint32_t zgtaphys_contact_events_drain(ZGTAPhysicsWorld*,uint64_t *ids,float *forces,uint32_t *started,uint32_t capacity);
uint32_t zgtaphys_collider_piece(ZGTAPhysicsWorld*,uint64_t collider,int32_t piece);
/* Returns shape kind:1ball,2cuboid,3capsule,4other; data[7]:world quaternionXYZW,dimensionsXYZ.
 * Dimensions:ball[radius,0,0],box[halfXYZ],capsule[halfHeight,radius,0]. piece -1 means unregistered. */
uint32_t zgtaphys_collider_shape_info(ZGTAPhysicsWorld*,uint64_t collider,float *data,int32_t *piece);
/* Collider-wide normalized query classes, separate from raw per-face metadata. */
uint32_t zgtaphys_collider_set_query_metadata(ZGTAPhysicsWorld*,uint64_t collider,int32_t surface,int32_t material);
uint32_t zgtaphys_collider_query_metadata(ZGTAPhysicsWorld*,uint64_t collider,int32_t *surface_material);
/* Explicit JS rotation setters normalize Float input, unlike raw state restore. */
uint32_t zgtaphys_body_set_browser_rotation(ZGTAPhysicsWorld*,uint64_t body,const float *xyzw,uint32_t wake_up);
uint32_t zgtaphys_body_set_browser_next_rotation(ZGTAPhysicsWorld*,uint64_t body,const float *xyzw);
#ifdef __cplusplus
}
#endif
#endif
