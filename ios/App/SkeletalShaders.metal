#include <metal_stdlib>
using namespace metal;

struct SkeletalNativeVertex {
    float4 position;
    float4 uvLayer;
    float4 tint;
    float4 dusk;
};
struct SkeletalUniforms {
    float4x4 viewProjection;
    float4 settings;
    float4 fogColor;
    float4 fogSettings;
    float4 tintColor;
};
struct SkeletalVertex {
    float4 point;
    uint4 bones;
    float4 weights;
};
struct SkeletalRaster {
    float4 position [[position]];
    float2 uv;
    float layer;
    float4 tint;
    float4 dusk;
    float depth;
};

static float4 skinPosition(const device SkeletalVertex &influence,
                           constant float4x4 *palette) {
    float4 point(0.0);
    for (uint slot = 0; slot < 4; ++slot) {
        point += (palette[influence.bones[slot]] * influence.point) * influence.weights[slot];
    }
    return float4(point.xyz, 1.0);
}

vertex SkeletalRaster skeletalActorVertex(uint id [[vertex_id]],
    const device SkeletalNativeVertex *vertices [[buffer(0)]],
    constant SkeletalUniforms &uniforms [[buffer(1)]],
    const device SkeletalVertex *skin [[buffer(2)]],
    constant float4x4 *palette [[buffer(3)]]) {
    SkeletalNativeVertex source = vertices[id];
    SkeletalRaster out;
    out.position = uniforms.viewProjection * skinPosition(skin[id], palette);
    out.depth = out.position.w;
    out.uv = source.uvLayer.xy;
    out.layer = source.uvLayer.z;
    out.tint = source.tint;
    out.dusk = source.dusk;
    return out;
}

// The probe uses the same function as the vertex stage. It supports a direct
// numeric comparison against the locally baked ANP3 reference without a UI.
kernel void skeletalPositionProbe(uint id [[thread_position_in_grid]],
    const device SkeletalVertex *skin [[buffer(0)]],
    constant float4x4 *palette [[buffer(1)]],
    device float4 *positions [[buffer(2)]],
    constant uint &count [[buffer(3)]]) {
    if (id < count) positions[id] = skinPosition(skin[id], palette);
}
