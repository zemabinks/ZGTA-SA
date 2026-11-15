#include <metal_stdlib>
using namespace metal;

// Native translation of the public generic FX instanced shader. Sprite
// dimensions/layers are preserved in up to eight original texture arrays.
struct NativeFXInstance {float4 place,size,color,way,kind;};
struct NativeFXUniforms {float4x4 projection,viewRotation;float4 fogColor,fog;};
struct NativeFXRaster {float4 position [[position]];float2 uv;float4 color;float3 pick;float depth;};
NativeFXRaster nativeFXPlace(uint id,NativeFXInstance p,constant NativeFXUniforms& u) {
    constexpr uint indices[6]={0,1,2,0,2,3};
    constexpr float2 corners[4]={float2(-0.5,-0.5),float2(0.5,-0.5),float2(0.5,0.5),float2(-0.5,0.5)};
    constexpr float2 uvs[4]={float2(0,0),float2(1,0),float2(1,1),float2(0,1)};
    uint corner=indices[id];float2 base=corners[corner];
    float3 view;
    if(p.kind.z>0.5) {
        float c=cos(p.place.w),s=sin(p.place.w);
        float2 level=float2(base.x*p.size.x+p.size.z,p.size.w-base.y*p.size.y);
        // Public shader Y-up (x,0,z) level plane converted once to GTA Z-up.
        float3 offset=float3(level.x*c+level.y*s,level.x*s-level.y*c,0);
        view=(u.viewRotation*float4(p.place.xyz+offset,0)).xyz;
    } else {
        float2 scale=p.size.xy;float rotation=p.place.w;
        if(p.way.w!=0) {
            float3 going=(u.viewRotation*float4(p.way.xyz,0)).xyz;
            rotation=abs(going.x)+abs(going.y)>0 ? atan2(going.y,going.x):0;
            if(p.way.w>0)scale.x=max(scale.x,length(going.xy)*p.way.w);
        }
        float2 aligned=(base-(p.size.zw-float2(0.5)))*scale;
        view=(u.viewRotation*float4(p.place.xyz,0)).xyz;
        view.xy+=float2(cos(rotation)*aligned.x-sin(rotation)*aligned.y,sin(rotation)*aligned.x+cos(rotation)*aligned.y);
    }
    return {u.projection*float4(view,1),uvs[corner],p.color,p.kind.xyw,-view.z};
}
vertex NativeFXRaster nativeFXVertex(uint id [[vertex_id]],uint instance [[instance_id]],
                                    device const NativeFXInstance* particles [[buffer(0)]],constant NativeFXUniforms& u [[buffer(1)]]) {
    return nativeFXPlace(id,particles[instance],u);
}
float3 nativeFXOutput(float3 value) {
    return select(1.055*pow(max(value,float3(0)),float3(0.4166666667))-0.055,value*12.92,value<=0.0031308);
}
fragment half4 nativeFXFragment(NativeFXRaster in [[stage_in]],constant NativeFXUniforms& u [[buffer(1)]],
 texture2d_array<float> t0 [[texture(0)]],texture2d_array<float> t1 [[texture(1)]],texture2d_array<float> t2 [[texture(2)]],texture2d_array<float> t3 [[texture(3)]],
 texture2d_array<float> t4 [[texture(4)]],texture2d_array<float> t5 [[texture(5)]],texture2d_array<float> t6 [[texture(6)]],texture2d_array<float> t7 [[texture(7)]],
 sampler s0 [[sampler(0)]],sampler s1 [[sampler(1)]],sampler s2 [[sampler(2)]],sampler s3 [[sampler(3)]],sampler s4 [[sampler(4)]],sampler s5 [[sampler(5)]],sampler s6 [[sampler(6)]],sampler s7 [[sampler(7)]]) {
    float2 dx=dfdx(in.uv),dy=dfdy(in.uv);uint layer=uint(in.pick.x);int sheet=int(in.pick.y+0.5);float4 texel;
    switch(sheet) {
        case 0:texel=t0.sample(s0,in.uv,layer,gradient2d(dx,dy));break;
        case 1:texel=t1.sample(s1,in.uv,layer,gradient2d(dx,dy));break;
        case 2:texel=t2.sample(s2,in.uv,layer,gradient2d(dx,dy));break;
        case 3:texel=t3.sample(s3,in.uv,layer,gradient2d(dx,dy));break;
        case 4:texel=t4.sample(s4,in.uv,layer,gradient2d(dx,dy));break;
        case 5:texel=t5.sample(s5,in.uv,layer,gradient2d(dx,dy));break;
        case 6:texel=t6.sample(s6,in.uv,layer,gradient2d(dx,dy));break;
        default:texel=t7.sample(s7,in.uv,layer,gradient2d(dx,dy));break;
    }
    float4 color=in.color*texel;
    color.rgb=nativeFXOutput(color.rgb);
    float3 clear=color.rgb;
    color.rgb=mix(color.rgb,u.fogColor.rgb,smoothstep(u.fog.x,u.fog.y,in.depth)*u.fog.z);
    color.rgb=mix(color.rgb,clear,in.pick.z);
    float strength=clamp(color.a,0.0,1.0);
    return half4(half3(clamp(color.rgb,0.0,1.0)*strength),half(strength*(1-in.pick.z)));
}
