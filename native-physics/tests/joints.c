#include "ZGTARapier.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static uint64_t body(ZGTAPhysicsWorld *w,float x,float mass) {
    float pose[7]={x,0,0,0,0,0,1},props[7]={mass,0,0,0,mass,mass,mass};
    return zgtaphys_body_new(w,1,pose,props,0);
}
int main(void) {
    ZGTAPhysicsWorld *w=zgtaphys_world_new(0,0,0);assert(w);
    uint64_t a=body(w,0,10),b=body(w,2,20),c=body(w,4,30);assert(a&&b&&c);
    float anchors[6]={1,0,0,-1,0,0},out[6];uint64_t ids[2];uint32_t contacts;
    uint64_t ab=zgtaphys_joint_spherical(w,a,b,anchors,0,1);
    uint64_t bc=zgtaphys_joint_spherical(w,b,c,anchors,0,1);assert(ab&&bc&&ab!=bc);
    assert(zgtaphys_joint_info(w,ab,ids,out,&contacts));
    assert(ids[0]==a&&ids[1]==b&&!contacts);
    for(int i=0;i<6;i++)assert(out[i]==anchors[i]);
    assert(!zgtaphys_joint_spherical(NULL,a,b,anchors,0,1));
    assert(!zgtaphys_joint_spherical(w,a,a,anchors,0,1));
    assert(!zgtaphys_joint_spherical(w,a,999999,anchors,0,1));
    assert(!zgtaphys_joint_spherical(w,ab,b,anchors,0,1));
    assert(!zgtaphys_joint_spherical(w,a,b,NULL,0,1));
    anchors[2]=NAN;assert(!zgtaphys_joint_spherical(w,a,b,anchors,0,1));anchors[2]=0;
    assert(!zgtaphys_joint_info(w,ab,NULL,out,&contacts));
    assert(!zgtaphys_joint_info(w,ab,ids,NULL,&contacts));
    assert(!zgtaphys_joint_info(w,ab,ids,out,NULL));
    float moved[3]={1,.2f,0};assert(zgtaphys_joint_anchor1(w,ab,moved,1));
    moved[0]=INFINITY;assert(!zgtaphys_joint_anchor1(w,ab,moved,1));
    assert(!zgtaphys_joint_anchor1(w,ab,NULL,1));
    assert(zgtaphys_joint_info(w,ab,ids,out,&contacts));assert(out[0]==1&&out[1]==.2f);
    assert(zgtaphys_world_step(w));
    float impulse[3]={30,0,0};assert(zgtaphys_body_impulse(w,a,impulse,0));
    for(int i=0;i<120;i++)assert(zgtaphys_world_step(w));
    float before[13],after[13];assert(zgtaphys_body_state(w,b,before));
    assert(zgtaphys_joint_remove(w,bc,1));assert(!zgtaphys_joint_remove(w,bc,1));
    assert(zgtaphys_body_state(w,b,after));
    for(int i=0;i<13;i++)assert(before[i]==after[i]); /* Release preserves momentum. */
    assert(!zgtaphys_joint_info(w,bc,ids,out,&contacts));
    bc=zgtaphys_joint_spherical(w,b,c,anchors,0,1);assert(bc);
    assert(zgtaphys_body_remove(w,b));
    assert(!zgtaphys_joint_info(w,ab,ids,out,&contacts));
    assert(!zgtaphys_joint_info(w,bc,ids,out,&contacts));
    assert(!zgtaphys_joint_anchor1(w,ab,anchors,1));
    uint64_t replacement=body(w,2,20);assert(replacement!=b);
    uint64_t fresh=zgtaphys_joint_spherical(w,a,replacement,anchors,1,0);assert(fresh!=ab&&fresh!=bc);
    assert(zgtaphys_joint_info(w,fresh,ids,out,&contacts));assert(contacts==1);
    assert(!zgtaphys_joint_info(w,ab,ids,out,&contacts));
    zgtaphys_world_free(w);

    for(int enabled=0;enabled<2;enabled++) {
        w=zgtaphys_world_new(0,0,0);a=body(w,0,1);b=body(w,0,1);
        float half[3]={.5f,.5f,.5f},identity[7]={0,0,0,0,0,0,1},zero[6]={0};
        assert(zgtaphys_collider_box(w,a,half,identity,0,0));
        assert(zgtaphys_collider_box(w,b,half,identity,0,0));
        /* Offset anchors permit separation when connected-body contacts are
           enabled, and both bodies retain free relative angular motion. */
        zero[0]=-.5f;zero[3]=.5f;
        fresh=zgtaphys_joint_spherical(w,a,b,zero,enabled,1);assert(fresh);
        assert(zgtaphys_joint_info(w,fresh,ids,out,&contacts));assert(contacts==(uint32_t)enabled);
        assert(zgtaphys_world_step(w));
        float torque[3]={0,10,0};assert(zgtaphys_body_impulse(w,a,torque,1));
        for(int i=0;i<60;i++)assert(zgtaphys_world_step(w));
        assert(zgtaphys_body_state(w,a,before));assert(zgtaphys_body_state(w,b,after));
        for(int i=0;i<13;i++)assert(isfinite(before[i])&&isfinite(after[i]));
        assert(fabsf(before[4]-after[4])>.01f); /* No angular lock or motor. */
        zgtaphys_world_free(w);
    }
    /* A joint at rest with overlapping shapes: unlike disjoint trajectory
       cases, this must distinguish suppression from enabled contact solving. */
    for(int enabled=0;enabled<2;enabled++) {
        w=zgtaphys_world_new(0,0,0);a=body(w,0,1);b=body(w,.5f,1);
        float half[3]={.5f,.5f,.5f},identity[7]={0,0,0,0,0,0,1};
        uint64_t ca=zgtaphys_collider_box(w,a,half,identity,0,0),cb=zgtaphys_collider_box(w,b,half,identity,0,0);
        assert(ca&&cb);assert(zgtaphys_collider_contact_events(w,ca,1));assert(zgtaphys_collider_contact_events(w,cb,1));
        float rest[6]={.25f,0,0,-.25f,0,0};assert(zgtaphys_joint_spherical(w,a,b,rest,enabled,1));
        uint32_t event_count=0;float response=0;
        for(int frame=0;frame<12;frame++) {
            assert(zgtaphys_world_step(w));assert(zgtaphys_body_state(w,a,before));assert(zgtaphys_body_state(w,b,after));
            uint64_t event_ids[16];float forces[32];uint32_t started[4];
            uint32_t count=zgtaphys_contact_events_drain(w,event_ids,forces,started,4);event_count+=count;
            assert(!zgtaphys_contact_events_count(w));
            for(uint32_t i=0;i<count;i++) {
                assert((event_ids[i*4]==ca&&event_ids[i*4+1]==cb)||(event_ids[i*4]==cb&&event_ids[i*4+1]==ca));
                assert(event_ids[i*4+2]==(event_ids[i*4]==ca?a:b));assert(event_ids[i*4+3]==(event_ids[i*4+1]==ca?a:b));
                for(int j=0;j<8;j++)assert(isfinite(forces[i*8+j]));
                assert(forces[i*8+3]>0&&forces[i*8+7]>0);
            }
            response=fmaxf(response,fabsf(before[0]));
            if(!enabled) {
                assert(!count&&before[0]==0&&after[0]==.5f);
                for(int j=1;j<13;j++)assert(before[j]==(j==6?1:0)&&after[j]==(j==6?1:0));
            }
        }
        assert(enabled?(event_count>0&&response>.01f):(!event_count&&response==0));zgtaphys_world_free(w);
    }

    /* The v2 parent-local setter changes neither the body nor its momentum.
       A stationary body's collider world pose remains old until step. */
    w=zgtaphys_world_new(0,0,0);a=body(w,0,1);
    float half[3]={.2f,.2f,.2f},identity[7]={0,0,0,0,0,0,1},alone_pose[7]={-10,0,0,0,0,0,1},local[3]={1,0,0};
    uint64_t attached=zgtaphys_collider_box(w,a,half,identity,0,0),standalone=zgtaphys_collider_box(w,0,half,alone_pose,0,0);assert(attached&&standalone);
    assert(zgtaphys_world_step(w));assert(zgtaphys_body_state(w,a,before));
    assert(!zgtaphys_collider_translation_wrt_parent(NULL,attached,local));
    assert(!zgtaphys_collider_translation_wrt_parent(w,999999,local));
    assert(!zgtaphys_collider_translation_wrt_parent(w,a,local));
    assert(!zgtaphys_collider_translation_wrt_parent(w,attached,NULL));
    for(int i=0;i<3;i++) {
        float bad[3]={0,0,0};bad[i]=NAN;assert(!zgtaphys_collider_translation_wrt_parent(w,attached,bad));
        bad[i]=INFINITY;assert(!zgtaphys_collider_translation_wrt_parent(w,attached,bad));
    }
    assert(zgtaphys_collider_translation_wrt_parent(w,attached,local));
    assert(zgtaphys_body_state(w,a,after));for(int i=0;i<13;i++)assert(before[i]==after[i]);
    float co_position[3];uint64_t co_body;uint32_t dynamic;int32_t material;
    assert(zgtaphys_collider_info(w,attached,co_position,&co_body,&dynamic,&material));
    assert(co_body==a&&dynamic&&co_position[0]==0&&co_position[1]==0&&co_position[2]==0);
    assert(zgtaphys_world_step(w));assert(zgtaphys_collider_info(w,attached,co_position,NULL,NULL,NULL));assert(co_position[0]==1);
    assert(zgtaphys_collider_translation_wrt_parent(w,standalone,local));
    assert(zgtaphys_collider_info(w,standalone,co_position,NULL,NULL,NULL));assert(co_position[0]==-10);
    assert(zgtaphys_world_step(w));assert(zgtaphys_collider_info(w,standalone,co_position,NULL,NULL,NULL));assert(co_position[0]==-10);
    assert(zgtaphys_body_state(w,a,before));before[0]=2;before[4]=sqrtf(.5f);before[6]=sqrtf(.5f);
    before[7]=.7f;before[8]=-.2f;before[9]=.1f;before[10]=.1f;before[11]=.2f;before[12]=-.1f;
    assert(zgtaphys_body_set_state(w,a,before));assert(zgtaphys_body_state(w,a,before));
    assert(zgtaphys_collider_info(w,attached,co_position,NULL,NULL,NULL));
    assert(fabsf(co_position[0]-2)<.00001f&&fabsf(co_position[1])<.00001f&&fabsf(co_position[2]+1)<.00001f);
    local[0]=.25f;local[1]=.5f;local[2]=-.75f;assert(zgtaphys_collider_translation_wrt_parent(w,attached,local));
    assert(zgtaphys_body_state(w,a,after));for(int i=0;i<13;i++)assert(before[i]==after[i]);
    assert(zgtaphys_collider_remove(w,attached));assert(!zgtaphys_collider_translation_wrt_parent(w,attached,local));
    assert(zgtaphys_body_remove(w,a));assert(zgtaphys_collider_translation_wrt_parent(w,standalone,local));zgtaphys_world_free(w);
    puts("PASS spherical joint C ABI: invalid/opaque IDs, moving anchors, momentum release, overlap contact events/suppression, free rotation and endpoint cleanup; parent-local v2 guards, stationary timing, rotation, momentum and standalone no-op");
    return 0;
}
