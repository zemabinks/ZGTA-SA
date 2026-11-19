#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4x4 viewProjection;
    float4 settings;
    float4 fogColor;
    float4 fogSettings;
    float4 tintColor;
};
struct Raster {
    float4 position [[position]];
    float2 uv;
    float layer;
    float4 tint;
    float4 dusk;
    float depth;
};

// Per-material states mirror original lens texture/emission, alpha testing
// and .14 scorched material color. General lighting currently shares the
// existing native world path; the exported normals enable its separate port.
fragment half4 vehicleFragment(Raster in [[stage_in]],
                               texture2d<half> atlas [[texture(0)]],
                               constant Uniforms &uniforms [[buffer(1)]],
                               constant float4 &material [[buffer(2)]]) {
    constexpr sampler sampleAtlas(coord::normalized,address::clamp_to_edge,filter::linear,mip_filter::none);
    float layer=material.x>=0 ? material.x:max(0.0,round(in.layer));
    float cellSize=uniforms.settings.w>0 ? uniforms.settings.w:128.0;
    float columns=floor(uniforms.settings.x/cellSize);
    float2 cell=float2(fmod(layer,columns),floor(layer/columns));
    float2 uv=(cell*cellSize+0.5+fract(in.uv)*(cellSize-1.0))/uniforms.settings.xy;
    half4 texel=atlas.sample(sampleAtlas,uv);
    half alpha=texel.a*half(in.tint.a);
    if(alpha<half(material.w))discard_fragment();
    half3 tint=half3(mix(in.tint.rgb,in.dusk.rgb,uniforms.settings.z));
    half3 color=material.y>0 ? texel.rgb:min(half3(1.0),texel.rgb*max(tint*half(1.8*material.z),half3(0.20*material.z)));
    color*=half3(uniforms.tintColor.rgb);
    float fog=uniforms.fogSettings.z*clamp((in.depth-uniforms.fogSettings.x)/max(1.0,uniforms.fogSettings.y-uniforms.fogSettings.x),0.0,1.0);
    color=mix(color,half3(uniforms.fogColor.rgb),half(fog));
    return half4(color,alpha*half(uniforms.tintColor.a));
}

static float3 vehicleSRGBToLinear(float3 value) {
    return select(pow((value+0.055)/1.055,float3(2.4)),value/12.92,value<=0.04045);
}
static float3 vehicleLinearToSRGB(float3 value) {
    value=clamp(value,0.0,1.0);
    return select(1.055*pow(value,float3(1.0/2.4))-0.055,value*12.92,value<=0.0031308);
}

// Version2 has neutral intrinsic/prelit RGB only on authored paint slots.
// Other parts retain the legacy path exactly, including lamps and alpha.
// Paint is a linear material colour from the original browser catalogue;
// texture transfer and display encoding are explicit rather than baked grey.
fragment half4 vehiclePaintFragment(Raster in [[stage_in]],
                                    texture2d<half> atlas [[texture(0)]],
                                    constant Uniforms &uniforms [[buffer(1)]],
                                    constant float4 &material [[buffer(2)]],
                                    constant float4 &paint [[buffer(3)]]) {
    constexpr sampler sampleAtlas(coord::normalized,address::clamp_to_edge,filter::linear,mip_filter::none);
    float layer=material.x>=0 ? material.x:max(0.0,round(in.layer));
    float cellSize=uniforms.settings.w>0 ? uniforms.settings.w:128.0;
    float columns=floor(uniforms.settings.x/cellSize);
    float2 cell=float2(fmod(layer,columns),floor(layer/columns));
    float2 uv=(cell*cellSize+0.5+fract(in.uv)*(cellSize-1.0))/uniforms.settings.xy;
    half4 texel=atlas.sample(sampleAtlas,uv);
    half alpha=texel.a*half(in.tint.a);
    if(alpha<half(material.w))discard_fragment();
    half3 color;
    if(paint.w>0.5 && material.y<=0) {
        float3 intrinsic=mix(in.tint.rgb,in.dusk.rgb,uniforms.settings.z);
        float3 illumination=max(intrinsic*1.8,float3(0.20))*material.z;
        float3 surface=vehicleSRGBToLinear(float3(texel.rgb))*paint.rgb*illumination;
        color=half3(vehicleLinearToSRGB(surface));
    }else{
        half3 tint=half3(mix(in.tint.rgb,in.dusk.rgb,uniforms.settings.z));
        color=material.y>0 ? texel.rgb:min(half3(1.0),texel.rgb*max(tint*half(1.8*material.z),half3(0.20*material.z)));
    }
    color*=half3(uniforms.tintColor.rgb);
    float fog=uniforms.fogSettings.z*clamp((in.depth-uniforms.fogSettings.x)/max(1.0,uniforms.fogSettings.y-uniforms.fogSettings.x),0.0,1.0);
    color=mix(color,half3(uniforms.fogColor.rgb),half(fog));
    return half4(color,alpha*half(uniforms.tintColor.a));
}

// VPC3 uses the complete original base image and its hardware sampler.
fragment half4 vehicleNativeFragment(Raster in [[stage_in]],
                                    texture2d<half> image [[texture(0)]],
                                    sampler sourceSampler [[sampler(0)]],
                                    constant Uniforms &uniforms [[buffer(1)]],
                                    constant float4 &material [[buffer(2)]],
                                    constant float4 &paint [[buffer(3)]]) {
    half4 texel=image.sample(sourceSampler,in.uv);
    half alpha=texel.a*half(in.tint.a);
    if(alpha<half(material.w))discard_fragment();
    half3 color;
    if(paint.w>0.5 && material.y<=0) {
        float3 intrinsic=mix(in.tint.rgb,in.dusk.rgb,uniforms.settings.z);
        float3 illumination=max(intrinsic*1.8,float3(0.20))*material.z;
        float3 surface=vehicleSRGBToLinear(float3(texel.rgb))*paint.rgb*illumination;
        color=half3(vehicleLinearToSRGB(surface));
    }else{
        half3 tint=half3(mix(in.tint.rgb,in.dusk.rgb,uniforms.settings.z));
        color=material.y>0 ? texel.rgb:min(half3(1.0),texel.rgb*max(tint*half(1.8*material.z),half3(0.20*material.z)));
    }
    color*=half3(uniforms.tintColor.rgb);
    float fog=uniforms.fogSettings.z*clamp((in.depth-uniforms.fogSettings.x)/max(1.0,uniforms.fogSettings.y-uniforms.fogSettings.x),0.0,1.0);
    color=mix(color,half3(uniforms.fogColor.rgb),half(fog));
    return half4(color,alpha*half(uniforms.tintColor.a));
}
