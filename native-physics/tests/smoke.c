#include "ZGTARapier.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static int near(float a,float b,float epsilon){return fabsf(a-b)<=epsilon;}
int main(void){
    assert(zgtaphys_bridge_version()==1);
    ZGTAPhysicsWorld *world=zgtaphys_world_new(0,-9.81f,0);assert(world);
    float identity[7]={0,0,0,0,0,0,1};
    float ground_half[3]={20,.1f,20};
    uint64_t ground=zgtaphys_collider_box(world,0,ground_half,identity,.5f,0);assert(ground);
    float pose[7]={0,5,0,0,0,0,1},mass[7]={10,0,0,0,2,2,2};
    uint64_t body=zgtaphys_body_new(world,1,pose,mass,1);assert(body);
    float half[3]={.5f,.5f,.5f};
    uint64_t shape=zgtaphys_collider_box(world,body,half,identity,.5f,0);assert(shape);
    for(int i=0;i<240;i++) assert(zgtaphys_world_step(world));
    float state[13];assert(zgtaphys_body_state(world,body,state));
    assert(near(state[1],.6f,.05f));
    assert(fabsf(state[8])<.1f);
    // A real Rapier collision must stop a high-speed body above a thin wall.
    state[1]=10;state[8]=-200;assert(zgtaphys_body_set_state(world,body,state));
    for(int i=0;i<10;i++)assert(zgtaphys_world_step(world));
    assert(zgtaphys_body_state(world,body,state));assert(state[1]>.45f);
    assert(zgtaphys_body_remove(world,body));
    // JS creation/setter mass is deferred. Explicit recompute is a separate API.
    body=zgtaphys_body_new(world,1,pose,mass,0);assert(body);
    float impulse[3]={10,0,0},torque[3]={0,4,0};
    assert(zgtaphys_body_impulse(world,body,impulse,0));
    assert(zgtaphys_body_impulse(world,body,torque,1));
    assert(zgtaphys_body_state(world,body,state));
    assert(state[7]==0 && state[11]==0);
    float effective_mass=-1;assert(zgtaphys_body_mass(world,body,&effective_mass));assert(effective_mass==0);
    assert(zgtaphys_world_step(world));
    assert(zgtaphys_body_impulse(world,body,impulse,0));
    assert(zgtaphys_body_impulse(world,body,torque,1));
    assert(zgtaphys_body_state(world,body,state));
    assert(near(state[7],1,.0001f));assert(near(state[11],2,.0001f));
    mass[0]=20;assert(zgtaphys_body_set_mass(world,body,mass));
    assert(zgtaphys_body_impulse(world,body,impulse,0));
    assert(zgtaphys_body_state(world,body,state));assert(near(state[7],2,.0001f));
    assert(zgtaphys_body_mass(world,body,&effective_mass));assert(effective_mass==10);
    assert(zgtaphys_body_recompute_mass(world,body));
    assert(zgtaphys_body_mass(world,body,&effective_mass));assert(effective_mass==20);
    assert(zgtaphys_body_impulse(world,body,impulse,0));
    assert(zgtaphys_body_state(world,body,state));assert(near(state[7],2.5f,.0001f));
    assert(zgtaphys_body_remove(world,body));assert(!zgtaphys_body_state(world,body,state));
    assert(zgtaphys_collider_remove(world,ground));
    // Face ordering and SCL2 surface/material annotations survive both sides.
    float vertices[12]={-10,0,-10,10,0,-10,10,0,10,-10,0,10};
    uint32_t indices[6]={0,2,1,0,3,2};int32_t surfaces[2]={7,9},materials[2]={55,66};
    uint64_t mesh=zgtaphys_collider_trimesh(world,vertices,4,indices,2,surfaces,materials);assert(mesh);
    float origin[3]={5,3,0},direction[3]={0,-1,0},hit[7];int32_t info[3];uint64_t hit_body=0;
    assert(zgtaphys_raycast(world,origin,direction,10,0,0,0,hit,info,&hit_body)==mesh);
    assert(near(hit[0],3,.0001f));assert(hit[2]>.99f);assert(info[0]==0);assert(info[1]==7);assert(info[2]==55);
    assert(!hit_body);
    uint64_t excluded[1]={mesh};
    assert(!zgtaphys_raycast(world,origin,direction,10,0,excluded,1,hit,info,&hit_body));
    assert(zgtaphys_collider_enabled(world,mesh,0));
    assert(!zgtaphys_raycast(world,origin,direction,10,0,0,0,hit,info,&hit_body));
    assert(zgtaphys_collider_enabled(world,mesh,1));
    // Box/sphere/convex-hull contacts and own-body ray exclusions.
    body=zgtaphys_body_new(world,1,pose,mass,0);assert(body);
    uint64_t ball=zgtaphys_collider_ball(world,body,1,identity,.5f,0);assert(ball);
    float ray_origin[3]={0,8,0};
    assert(zgtaphys_raycast(world,ray_origin,direction,20,0,0,0,hit,info,&hit_body)==ball);assert(hit_body==body);
    assert(zgtaphys_raycast(world,ray_origin,direction,20,body,0,0,hit,info,&hit_body)==mesh);
    assert(zgtaphys_collider_groups(world,ball,0x00010001,0xffffffff));
    assert(zgtaphys_raycast_groups(world,ray_origin,direction,20,0x00020002,0,0,0,hit,info,&hit_body)==mesh);
    assert(zgtaphys_collider_surface(world,ball,12,34));
    assert(zgtaphys_raycast_groups(world,ray_origin,direction,20,0x00010001,0,0,0,hit,info,&hit_body)==ball);
    assert(info[1]==12 && info[2]==34);
    float hull[12]={0,0,0,1,0,0,0,1,0,0,0,1};float hull_pose[7]={3,2,0,0,0,0,1};
    assert(zgtaphys_collider_convex(world,0,hull,4,hull_pose,.5f,0));
    uint32_t bad[3]={0,1,99};assert(!zgtaphys_collider_trimesh(world,vertices,4,bad,1,0,0));
    assert(!zgtaphys_body_new(world,99,pose,mass,0));
    zgtaphys_world_free(world);
    world=zgtaphys_world_new(0,0,0);assert(world);
    assert(zgtaphys_collider_box(world,0,ground_half,identity,.5f,0));
    float wall_half[3]={.1f,3,3},wall_pose[7]={1.5f,2,0,0,0,0,1};
    assert(zgtaphys_collider_box(world,0,wall_half,wall_pose,.5f,0));
    float actor_pose[7]={0,.97f,0,0,0,0,1};
    body=zgtaphys_body_new(world,2,actor_pose,mass,0);assert(body);
    uint64_t capsule=zgtaphys_collider_capsule(world,body,.5f,.35f,identity,.5f,0);assert(capsule);
    float desired[3]={2,-.3f,0},parameters[12]={.02f,0,1,0,.785398f,.785398f,.2f,-1,.5f,.0001f,0,1.0f/60};
    float movement[5],collisions[160];uint64_t collider_ids[16];uint32_t count=0;
    assert(zgtaphys_character_move(world,capsule,desired,parameters,9,0xffffffff,0,movement,collider_ids,collisions,16,&count));
    assert(movement[0]>.8f && movement[0]<1.2f);assert(movement[3]>0);assert(count>0);
    actor_pose[0]+=movement[0];actor_pose[1]+=movement[1];actor_pose[2]+=movement[2];
    assert(zgtaphys_body_next_kinematic(world,body,actor_pose));assert(zgtaphys_world_step(world));
    assert(zgtaphys_body_state(world,body,state));assert(near(state[0],actor_pose[0],.0001f));
    zgtaphys_world_free(world);
    puts("PASS: native Rapier C ABI, fixed-step dynamics, CCD collision, mass/inertia impulses, ray exclusions and triangle annotations");
    return 0;
}
