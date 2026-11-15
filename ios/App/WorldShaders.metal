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

struct SkyRaster { float4 position [[position]]; float elevation; };
vertex SkyRaster nativeSkyVertex(uint id [[vertex_id]]) {
    const float2 points[] = {float2(-1,-1),float2(3,-1),float2(-1,3)};
    SkyRaster out; out.position = float4(points[id],0.9999,1);
    out.elevation = (points[id].y+1)*0.5; return out;
}
fragment half4 nativeSkyFragment(SkyRaster in [[stage_in]], constant Uniforms &uniforms [[buffer(1)]]) {
    return half4(half3(mix(uniforms.fogColor.rgb, uniforms.tintColor.rgb, clamp(in.elevation,0.0,1.0))),half(1));
}

vertex Raster worldVertex(uint id [[vertex_id]],
                          const device NativeVertex *vertices [[buffer(0)]],
                          constant Uniforms &uniforms [[buffer(1)]]) {
    NativeVertex source = vertices[id];
    Raster out;
    out.position = uniforms.viewProjection * source.position;
    out.depth = out.position.w;
    out.uv = source.uvLayer.xy;
    out.layer = source.uvLayer.z;
    out.tint = source.tint;
    out.dusk = source.dusk;
    return out;
}

vertex Raster animatedActorVertex(uint id [[vertex_id]],
                                  const device NativeVertex *vertices [[buffer(0)]],
                                  constant Uniforms &uniforms [[buffer(1)]],
                                  const device packed_float3 *positions [[buffer(2)]],
                                  const device packed_float3 *nextPositions [[buffer(3)]],
                                  constant float &frameMix [[buffer(4)]]) {
    NativeVertex source = vertices[id];
    Raster out;
    out.position = uniforms.viewProjection *
        float4(mix(float3(positions[id]), float3(nextPositions[id]), frameMix), 1.0);
    out.depth = out.position.w;
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
    if (textureColor.a * in.tint.a < 0.1) discard_fragment();
    half3 tint = half3(mix(in.tint.rgb, in.dusk.rgb, uniforms.settings.z));
    half3 color = min(half3(1.0), textureColor.rgb * max(tint * 1.8h, half3(0.20)));
    color *= half3(uniforms.tintColor.rgb);
    float fog = uniforms.fogSettings.z * clamp((in.depth - uniforms.fogSettings.x) /
        max(1.0, uniforms.fogSettings.y - uniforms.fogSettings.x), 0.0, 1.0);
    color = mix(color, half3(uniforms.fogColor.rgb), half(fog));
    return half4(color, textureColor.a * half(in.tint.a * uniforms.tintColor.a));
}
