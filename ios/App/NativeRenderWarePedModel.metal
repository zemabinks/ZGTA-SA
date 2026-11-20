// SPDX-License-Identifier: AGPL-3.0-only
#include <metal_stdlib>
using namespace metal;

// Field order/layout matches NativeRenderWareModel's vertex/fragment contract.
struct NativeRWPedVertex { float3 position; float3 normal; float2 uv; float4 color; };
struct NativeRWPedUniforms {
    float4x4 viewProjection; float4x4 model; float4x4 normalMatrix;
    float4 color; float4 lightDirectionAmbient; float4 settings;
};
struct NativeRWPedSkin { float4 point; uint4 bones; float4 weights; };
struct NativeRWPedOut { float4 position [[position]]; float2 uv; float4 color; float3 normal; };

static float4 nativeRWPedPosition(const device NativeRWPedSkin &skin, constant float4x4 *palette) {
    float4 point(0);
    for (uint slot = 0; slot < 4; ++slot)
        if (skin.weights[slot] > 0) point += (palette[skin.bones[slot]] * skin.point) * skin.weights[slot];
    return float4(point.xyz, 1);
}
static float3 nativeRWPedNormal(float3 normal, const device NativeRWPedSkin &skin, constant float4x4 *palette) {
    float3 result(0);
    for (uint slot = 0; slot < 4; ++slot)
        if (skin.weights[slot] > 0) result += (palette[skin.bones[slot]] * float4(normal, 0)).xyz * skin.weights[slot];
    return result;
}
vertex NativeRWPedOut native_rw_ped_vertex(uint id [[vertex_id]],
    const device NativeRWPedVertex *vertices [[buffer(0)]], constant NativeRWPedUniforms &u [[buffer(1)]],
    const device NativeRWPedSkin *skin [[buffer(2)]], constant float4x4 *palette [[buffer(3)]]) {
    NativeRWPedVertex source = vertices[id]; NativeRWPedOut out;
    out.position = u.viewProjection * u.model * nativeRWPedPosition(skin[id], palette);
    out.normal = (u.normalMatrix * float4(nativeRWPedNormal(source.normal, skin[id], palette), 0)).xyz;
    out.uv = source.uv;
    out.color = (u.settings.z > 0.5f ? float4(1) : source.color) * u.color;
    return out;
}
// Uses the exact vertex-stage skinning helpers, for numerical Metal regressions.
kernel void native_rw_ped_probe(uint id [[thread_position_in_grid]],
    const device NativeRWPedVertex *vertices [[buffer(0)]], const device NativeRWPedSkin *skin [[buffer(1)]],
    constant float4x4 *palette [[buffer(2)]], constant NativeRWPedUniforms &u [[buffer(3)]],
    device float4 *positions [[buffer(4)]], device float4 *normals [[buffer(5)]], constant uint &count [[buffer(6)]]) {
    if (id >= count) return;
    positions[id] = u.model * nativeRWPedPosition(skin[id], palette);
    normals[id] = float4((u.normalMatrix * float4(nativeRWPedNormal(vertices[id].normal, skin[id], palette), 0)).xyz, 0);
}
