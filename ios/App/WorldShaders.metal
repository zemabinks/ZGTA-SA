#include <metal_stdlib>
using namespace metal;

struct NativeVertex {
    float4 position;
    float4 uvLayer;
    float4 tint;
    float4 dusk;
};

struct Uniforms {
    float4x4 viewProjection;
    float4 settings; // atlas width, atlas height, night blend, reserved
};

struct Raster {
    float4 position [[position]];
    float2 uv;
    float layer;
    float4 tint;
    float4 dusk;
};

vertex Raster worldVertex(uint id [[vertex_id]],
                          const device NativeVertex *vertices [[buffer(0)]],
                          constant Uniforms &uniforms [[buffer(1)]]) {
    NativeVertex source = vertices[id];
    Raster out;
    out.position = uniforms.viewProjection * source.position;
    out.uv = source.uvLayer.xy;
    out.layer = source.uvLayer.z;
    out.tint = source.tint;
    out.dusk = source.dusk;
    return out;
}

fragment half4 worldFragment(Raster in [[stage_in]],
                             texture2d<half> atlas [[texture(0)]],
                             constant Uniforms &uniforms [[buffer(1)]]) {
    constexpr sampler sampleAtlas(coord::normalized, address::clamp_to_edge,
                                  filter::linear, mip_filter::none);
    float layer = max(0.0, round(in.layer));
    float cellSize = uniforms.settings.w > 0.0 ? uniforms.settings.w : 64.0;
    float columns = floor(uniforms.settings.x / cellSize);
    float2 cell = float2(fmod(layer, columns), floor(layer / columns));
    float2 tiledUV = fract(in.uv);
    float2 atlasUV = (cell * cellSize + 0.5 + tiledUV * (cellSize - 1.0)) / uniforms.settings.xy;
    half4 textureColor = atlas.sample(sampleAtlas, atlasUV);
    half3 tint = half3(mix(in.tint.rgb, in.dusk.rgb, uniforms.settings.z));
    half3 color = min(half3(1.0), textureColor.rgb * max(tint * 1.8h, half3(0.20)));
    return half4(color, textureColor.a * half(in.tint.a));
}
