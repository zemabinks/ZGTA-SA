#include "ZGTARapier.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static int checks=0;
#define CHECK(x) do {++checks;if(!(x)){fprintf(stderr,"FAIL line%d: %s\n",__LINE__,#x);abort();}} while(0)
static int order(const void*a,const void*b){const uint64_t x=*(const uint64_t*)a,y=*(const uint64_t*)b;return (x>y)-(x<y);}
static unsigned query(ZGTAPhysicsWorld*w,int ball,uint32_t groups,uint32_t flags,uint32_t opts,const uint64_t*ec,uint32_t nc,const uint64_t*eb,uint32_t nb,uint64_t*out,uint32_t cap){
 const float p[3]={0,0,0};return ball?zgtaphys_intersections_sphere(w,p,.3f,groups,flags,opts,ec,nc,eb,nb,out,cap):zgtaphys_intersections_capsule(w,p,0,.3f,groups,flags,opts,ec,nc,eb,nb,out,cap);
}
int main(void){
 ZGTAPhysicsWorld*w=zgtaphys_world_new(0,0,0);CHECK(w);const float pose[7]={0,0,0,0,0,0,1},half[3]={.25f,.25f,.25f},mass[7]={10,0,0,0,2,2,2};
 const uint64_t standalone=zgtaphys_collider_box(w,0,half,pose,.5f,0),fixed=zgtaphys_body_new(w,0,pose,0,0),dynamic=zgtaphys_body_new(w,1,pose,mass,0),kinematic=zgtaphys_body_new(w,2,pose,0,0);
 const uint64_t fixedShape=zgtaphys_collider_ball(w,fixed,.25f,pose,.5f,0),dynamicOne=zgtaphys_collider_box(w,dynamic,half,pose,.5f,0),dynamicTwo=zgtaphys_collider_ball(w,dynamic,.25f,pose,.5f,0),kinematicShape=zgtaphys_collider_box(w,kinematic,half,pose,.5f,0),ped=zgtaphys_collider_ball(w,0,.25f,pose,.5f,0);
 CHECK(standalone&&fixed&&dynamic&&kinematic&&fixedShape&&dynamicOne&&dynamicTwo&&kinematicShape&&ped);
 const uint64_t g1[]={standalone,fixedShape,kinematicShape,ped},g2[]={dynamicOne,dynamicTwo};
 for(unsigned i=0;i<4;i++)CHECK(zgtaphys_collider_groups(w,g1[i],0x00010001,0xffffffff));
 for(unsigned i=0;i<2;i++)CHECK(zgtaphys_collider_groups(w,g2[i],0x00020002,0xffffffff));
 CHECK(zgtaphys_collider_set_query_metadata(w,ped,2,62));
 uint64_t out[16];CHECK(query(w,1,0,0,0,0,0,0,0,out,16)==6);
 CHECK(query(w,1,0,0,1,0,0,0,0,out,16)==0);
 CHECK(query(w,1,0x00010001,0,1,0,0,0,0,out,16)==4);
 CHECK(query(w,1,0x00020002,0,1,0,0,0,0,out,16)==2);
 CHECK(query(w,1,0,0,2,0,0,0,0,out,16)==4);
 CHECK(query(w,1,0x00010001,0,3,0,0,0,0,out,16)==2);
 CHECK(query(w,1,0,1,0,0,0,0,0,out,16)==3);
 CHECK(query(w,1,0,2,0,0,0,0,0,out,16)==5);
 CHECK(query(w,1,0,4,0,0,0,0,0,out,16)==4);
 CHECK(query(w,1,0,3,0,0,0,0,0,out,16)==2);
 CHECK(query(w,1,0,6,0,0,0,0,0,out,16)==3);
 CHECK(query(w,1,0,0,0,&dynamicOne,1,0,0,out,16)==5);
 CHECK(query(w,1,0,0,0,0,0,&dynamic,1,out,16)==4);
 CHECK(query(w,1,0,0,0,&fixedShape,1,&dynamic,1,out,16)==3);
 // Deep-overlap corpus isolates filtering from the deliberate grazing-shape
 // distinction. Every existing mask/flag/exclusion combination must agree.
 const uint32_t groups[]={0,0x00010001,0x00020002,0xffffffff};
 for(uint32_t flags=0;flags<32;flags++)for(unsigned g=0;g<4;g++)for(unsigned opts=0;opts<4;opts++)for(unsigned nc=0;nc<2;nc++)for(unsigned nb=0;nb<2;nb++){
  uint64_t a[16],b[16];const unsigned na=query(w,0,groups[g],flags,opts,&fixedShape,nc,&dynamic,nb,a,16),n=query(w,1,groups[g],flags,opts,&fixedShape,nc,&dynamic,nb,b,16);
  CHECK(na==n);qsort(a,na,sizeof(*a),order);qsort(b,n,sizeof(*b),order);for(unsigned i=0;i<n;i++)CHECK(a[i]==b[i]);
 }
 uint64_t bounded[2]={0,0x12345678};CHECK(query(w,1,0,0,0,0,0,0,0,bounded,1)==1);CHECK(bounded[1]==0x12345678);
 CHECK(query(w,1,0,0,0,0,0,0,0,0,0)==0);CHECK(query(w,1,0,0,0,0,0,0,0,bounded,100001)==0);
 CHECK(query(w,1,0,0,0,0,1,0,0,out,16)==0);CHECK(query(w,1,0,0,0,0,0,0,1,out,16)==0);
 float bad[3]={NAN,0,0},p[3]={0,0,0};
 CHECK(!zgtaphys_intersections_sphere(w,bad,.3f,0,0,0,0,0,0,0,out,16));
 CHECK(!zgtaphys_intersections_sphere(w,p,NAN,0,0,0,0,0,0,0,out,16));
 CHECK(!zgtaphys_intersections_sphere(w,p,0,0,0,0,0,0,0,0,out,16));
 CHECK(!zgtaphys_intersections_sphere(w,p,-1,0,0,0,0,0,0,0,out,16));
 CHECK(!zgtaphys_intersections_sphere(0,p,.3f,0,0,0,0,0,0,0,out,16));
 CHECK(zgtaphys_collider_enabled(w,ped,0));CHECK(query(w,1,0,0,0,0,0,0,0,out,16)==5);
 zgtaphys_world_free(w);
 // Independent, analytically separated triangle planes reproduce the actual
 // shape-type bug without publishing any game geometry. Rounded f32 centers
 // are slightly farther than radius from these planes: a Ball must not overlap.
 const float planes[]={128,1024,1500,2048};
 for(unsigned i=0;i<sizeof(planes)/sizeof(*planes);i++){
  w=zgtaphys_world_new(0,0,0);CHECK(w);
  float z=planes[i],vertices[9]={-2,0,z,2,0,z,0,4,z};uint32_t triangles[3]={0,1,2};int32_t surface=2,material=0;
  CHECK(zgtaphys_collider_trimesh(w,vertices,3,triangles,1,&surface,&material));
  float point[3]={0,2,z+.3f};CHECK((double)point[2]-(double)z>(double).3f);
  CHECK(zgtaphys_intersections_sphere(w,point,.3f,0,0,0,0,0,0,0,out,16)==0);
  CHECK(zgtaphys_intersections_capsule(w,point,0,.3f,0,0,0,0,0,0,0,out,16)==1);
  point[2]=nextafterf(z+.3f,-INFINITY);
  CHECK(zgtaphys_intersections_sphere(w,point,.3f,0,0,0,0,0,0,0,out,16)==1);
  point[2]=nextafterf(z+.3f,INFINITY);
  CHECK(zgtaphys_intersections_sphere(w,point,.3f,0,0,0,0,0,0,0,out,16)==0);
  zgtaphys_world_free(w);
 }
 printf("PASS literal sphere C ABI: %d mask/flag/parent/body/collider exclusions, bounds/invalid arguments, PED metadata, existing capsule compatibility and independent grazing-regression checks\n",checks);
}
