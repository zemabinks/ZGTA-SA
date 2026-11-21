// SPDX-License-Identifier: AGPL-3.0-only
#include <metal_stdlib>
using namespace metal;

struct NativeShotVertex {float4 position,color;};
struct NativeShotRaster {float4 position [[position]];float4 color;};
vertex NativeShotRaster nativeShotTracerVertex(uint index [[vertex_id]],
    device const NativeShotVertex* vertices [[buffer(0)]],constant float4x4& matrix [[buffer(1)]]) {
    NativeShotVertex item=vertices[index];
    return {matrix*item.position,item.color};
}
fragment float4 nativeShotTracerFragment(NativeShotRaster in [[stage_in]]) {
    float3 value=in.color.rgb;
    float3 encoded=select(1.055*pow(max(value,float3(0)),float3(1.0/2.4))-0.055,12.92*value,value<=0.0031308);
    return float4(encoded,in.color.a);
}
