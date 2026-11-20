// SPDX-License-Identifier: AGPL-3.0-only
#include <metal_stdlib>
using namespace metal;

struct NativeRWVertex {
    float3 position;
    float3 normal;
    float2 uv;
    float4 color;
};
struct NativeRWUniforms {
    float4x4 viewProjection;
    float4x4 model;
    float4x4 normalMatrix;
    float4 color;
    float4 lightDirectionAmbient;
    float4 settings;
};
struct NativeRWOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float3 normal;
};
vertex NativeRWOut native_rw_model_vertex(uint index [[vertex_id]],
                                        const device NativeRWVertex *vertices [[buffer(0)]],
                                        constant NativeRWUniforms &u [[buffer(1)]]) {
    NativeRWVertex v = vertices[index];
    NativeRWOut out;
    out.position = u.viewProjection * u.model * float4(v.position, 1);
    out.normal = (u.normalMatrix * float4(v.normal, 0)).xyz;
    out.uv = v.uv;
    out.color = (u.settings.z > 0.5f ? float4(1) : v.color) * u.color;
    return out;
}
static float4 nativeRWMaterial(float2 uv, float4 vertexColor, float3 normal,
                              texture2d<float> image, sampler imageSampler,
                              constant NativeRWUniforms &u) {
    // No-map materials have no texture operation. A bound identity texture
    // alone is insufficient: a border sampler can turn it into zero outside
    // the image. The fallback binding still satisfies Metal's resource ABI.
    float4 texel = u.settings.w > 0.5f ? image.sample(imageSampler, uv) : float4(1);
    float4 color = texel * vertexColor;
    if (color.a < u.settings.y) discard_fragment();
    float n2 = dot(normal, normal);
    float l2 = dot(u.lightDirectionAmbient.xyz, u.lightDirectionAmbient.xyz);
    float diffuse = n2 > 1e-12 && l2 > 1e-12
        ? max(0.0f, dot(normal * rsqrt(n2), u.lightDirectionAmbient.xyz * rsqrt(l2))) : 0.0f;
    color.rgb *= max(0.0f, u.lightDirectionAmbient.w + u.settings.x * diffuse);
    return color;
}
fragment float4 native_rw_model_fragment(NativeRWOut in [[stage_in]],
                                        texture2d<float> image [[texture(0)]],
                                        sampler imageSampler [[sampler(0)]],
                                        constant NativeRWUniforms &u [[buffer(1)]]) {
    return nativeRWMaterial(in.uv, in.color, in.normal, image, imageSampler, u);
}

// The skinned stage adds clip-W depth. The existing static-object interface and
// uniforms stay unchanged; both fragments share the exact material operation.
struct NativeRWPedSceneOut {
    float4 position [[position]]; float2 uv; float4 color; float3 normal; float depth;
};
struct NativeRWPedEnvironment { float4 fogColor; float4 fogSettings; };
fragment float4 native_rw_ped_fragment(NativeRWPedSceneOut in [[stage_in]],
    texture2d<float> image [[texture(0)]], sampler imageSampler [[sampler(0)]],
    constant NativeRWUniforms &u [[buffer(1)]],
    constant NativeRWPedEnvironment &scene [[buffer(4)]]) {
    float4 color = nativeRWMaterial(in.uv, in.color, in.normal, image, imageSampler, u);
    float fog = scene.fogSettings.z * clamp((in.depth - scene.fogSettings.x) /
        max(1.0f, scene.fogSettings.y - scene.fogSettings.x), 0.0f, 1.0f);
    color.rgb = mix(color.rgb, scene.fogColor.rgb, fog);
    return color;
}
