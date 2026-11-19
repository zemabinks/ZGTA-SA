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

static half4 ordinaryActorShade(Raster in,half4 textureColor,constant Uniforms &uniforms) {
    if (textureColor.a * in.tint.a < 0.1) discard_fragment();
    half3 tint = half3(mix(in.tint.rgb, in.dusk.rgb, uniforms.settings.z));
    half3 color = min(half3(1.0), textureColor.rgb * max(tint * 1.8h, half3(0.20)));
    color *= half3(uniforms.tintColor.rgb);
    float fog = uniforms.fogSettings.z * clamp((in.depth - uniforms.fogSettings.x) /
        max(1.0, uniforms.fogSettings.y - uniforms.fogSettings.x), 0.0, 1.0);
    color = mix(color, half3(uniforms.fogColor.rgb), half(fog));
    return half4(color, textureColor.a * half(in.tint.a * uniforms.tintColor.a));
}

static half4 nativeAtlasColor(Raster in, texture2d<half> atlas, constant Uniforms &uniforms) {
    constexpr sampler sampleAtlas(coord::normalized, address::clamp_to_edge,
                                  filter::linear, mip_filter::none);
    float layer = max(0.0, round(in.layer));
    float cellSize = uniforms.settings.w > 0.0 ? uniforms.settings.w : 64.0;
    float columns = floor(uniforms.settings.x / cellSize);
    float2 cell = float2(fmod(layer, columns), floor(layer / columns));
    float2 tiledUV = fract(in.uv);
    float2 atlasUV = (cell * cellSize + 0.5 + tiledUV * (cellSize - 1.0)) / uniforms.settings.xy;
    return atlas.sample(sampleAtlas, atlasUV);
}

fragment half4 ordinaryModelFragment(Raster in [[stage_in]],
                                     texture2d<half> atlas [[texture(0)]],
                                     constant Uniforms &uniforms [[buffer(1)]]) {
    return ordinaryActorShade(in,nativeAtlasColor(in,atlas,uniforms),uniforms);
}

fragment half4 worldFragment(Raster in [[stage_in]],
                             texture2d<half> atlas [[texture(0)]],
                             constant Uniforms &uniforms [[buffer(1)]]) {
    half4 textureColor = nativeAtlasColor(in,atlas,uniforms);
    if (textureColor.a * in.tint.a < 0.1) discard_fragment();
    // Exterior prelighting is an illumination term, separate from model tint.
    half3 day = min(half3(in.tint.rgb) + half3(0.30h), half3(1.0h));
    half3 night = min(half3(in.dusk.rgb) + half3(0.10h,0.10h,0.15h), half3(1.0h));
    half3 light = mix(day,night,half(clamp(uniforms.settings.z,0.0,1.0)));
    half3 color = textureColor.rgb * light * half3(uniforms.tintColor.rgb);
    float fog = uniforms.fogSettings.z * clamp((in.depth - uniforms.fogSettings.x) /
        max(1.0, uniforms.fogSettings.y - uniforms.fogSettings.x), 0.0, 1.0);
    color = mix(color,half3(uniforms.fogColor.rgb),half(fog));
    return half4(color,textureColor.a * half(in.tint.a * uniforms.tintColor.a));
}

// The per-model rectangle layout belongs to the fragment stage only.
// V2 repeats each integer tap within its own original content rectangle.
// Reduce finite UVs to [0,1) before multiplication/conversion: even extreme
// finite interpolants cannot overflow the bounded native texel index.
inline uint2 pedRepeatTexel(int2 position,uint2 size) {
    int2 extent=int2(size);
    return uint2((position%extent+extent)%extent);
}
inline half4 pedNativeBase(texture2d<half> atlas,float2 uv,float4 rect,float filter) {
    float2 phase=fract(uv);
    uint2 size=uint2(rect.zw),origin=uint2(rect.xy);
    if (filter==1.0) {
        int2 pixel=int2(floor(phase*rect.zw));
        return atlas.read(origin+pedRepeatTexel(pixel,size));
    }
    float2 p=phase*rect.zw-0.5;
    int2 base=int2(floor(p));float2 weight=p-float2(base);
    float4 a=float4(atlas.read(origin+pedRepeatTexel(base,size)));
    float4 b=float4(atlas.read(origin+pedRepeatTexel(base+int2(1,0),size)));
    float4 c=float4(atlas.read(origin+pedRepeatTexel(base+int2(0,1),size)));
    float4 d=float4(atlas.read(origin+pedRepeatTexel(base+int2(1,1),size)));
    return half4(mix(mix(a,b,weight.x),mix(c,d,weight.x),weight.y));
}
fragment half4 ordinaryPedAtlasFragment(Raster in [[stage_in]],
    texture2d<half> atlas [[texture(0)]],
    constant Uniforms &uniforms [[buffer(1)]],
    constant float4 *layout [[buffer(2)]]) {
    constexpr sampler sampleAtlas(coord::normalized, address::clamp_to_edge,
                                  filter::linear, mip_filter::none);
    float slot=round(in.layer);
    if (!isfinite(slot) || slot<0.0 || slot>=layout[0].z || (layout[0].w!=1.0 && layout[0].w!=2.0)) {
        discard_fragment();return half4(0.0);
    }
    if (layout[0].w==2.0) {
        float4 rect=layout[uint(slot)*2+1],sampling=layout[uint(slot)*2+2];
        if (!all(isfinite(in.uv)) || (sampling.x!=1.0 && sampling.x!=2.0 && sampling.x!=6.0) || sampling.y!=1.0 || sampling.z!=1.0 || sampling.w!=0.0) {
            discard_fragment();return half4(0.0);
        }
        return ordinaryActorShade(in,pedNativeBase(atlas,in.uv,rect,sampling.x),uniforms);
    }
    float4 rect=layout[uint(slot)+1];
    float2 atlasUV=(rect.xy+0.5+fract(in.uv)*(rect.zw-1.0))/layout[0].xy;
    half4 textureColor=atlas.sample(sampleAtlas,atlasUV);
    return ordinaryActorShade(in,textureColor,uniforms);
}

// Native-sized array slices let Metal apply the original repeat sampler at
// the image's own dimensions, including the device's sampling precision.
fragment half4 ordinaryPedNativeFragment(Raster in [[stage_in]],
    texture2d_array<half> images [[texture(0)]],
    constant Uniforms &uniforms [[buffer(1)]],
    constant float4 *layout [[buffer(2)]],
    constant uint2 *entries [[buffer(3)]],
    constant uint &group [[buffer(4)]]) {
    float slot=round(in.layer);
    if (!isfinite(slot) || !isfinite(layout[0].z) || layout[0].z<1.0 || layout[0].z>4096.0 ||
        slot<0.0 || slot>=layout[0].z || layout[0].w!=2.0 || !all(isfinite(in.uv))) {
        discard_fragment();return half4(0.0);
    }
    float4 rect=layout[uint(slot)*2+1],sampling=layout[uint(slot)*2+2];
    uint2 entry=entries[uint(slot)];
    if (!all(isfinite(rect)) || any(rect.zw<1.0) || any(rect.zw>4096.0) ||
        entry.x!=group || entry.y>=images.get_array_size() ||
        any(uint2(rect.zw)!=uint2(images.get_width(),images.get_height())) ||
        (sampling.x!=1.0 && sampling.x!=2.0 && sampling.x!=6.0) ||
        sampling.y!=1.0 || sampling.z!=1.0 || sampling.w!=0.0) {
        discard_fragment();return half4(0.0);
    }
    // Float32 values at this magnitude have no fractional component. Reduce
    // exact large integers to zero before hardware address conversion.
    float2 uv=select(in.uv,float2(0.0),abs(in.uv)>=float2(8388608.0));
    constexpr sampler point(coord::normalized,address::repeat,filter::nearest,mip_filter::none);
    constexpr sampler linear(coord::normalized,address::repeat,filter::linear,mip_filter::none);
    half4 color=sampling.x==1.0 ? images.sample(point,uv,entry.y):images.sample(linear,uv,entry.y);
    return ordinaryActorShade(in,color,uniforms);
}


// Optional detailed-cell sharp map uses the original plus-one WRL2 lookup.
fragment half4 worldSharpFragment(Raster in [[stage_in]],
    texture2d<half> atlas [[texture(0)]],texture2d_array<half> sharpImages [[texture(1)]],
    sampler originalSampler [[sampler(0)]],constant Uniforms &uniforms [[buffer(1)]],
    constant uint *sharpMap [[buffer(2)]]) {
    half4 textureColor=nativeAtlasColor(in,atlas,uniforms);
    float layer=round(in.layer);
    if(isfinite(layer) && layer>=0.0 && layer<float(sharpMap[0])) {
        uint selected=sharpMap[4+uint(layer)];
        if(selected>0 && selected<=sharpMap[1] && selected<=sharpImages.get_array_size())
            textureColor=sharpImages.sample(originalSampler,in.uv,selected-1);
    }
    if (textureColor.a * in.tint.a < 0.1) discard_fragment();
    // Exterior prelighting is an illumination term, separate from model tint.
    half3 day = min(half3(in.tint.rgb) + half3(0.30h), half3(1.0h));
    half3 night = min(half3(in.dusk.rgb) + half3(0.10h,0.10h,0.15h), half3(1.0h));
    half3 light = mix(day,night,half(clamp(uniforms.settings.z,0.0,1.0)));
    half3 color = textureColor.rgb * light * half3(uniforms.tintColor.rgb);
    float fog = uniforms.fogSettings.z * clamp((in.depth - uniforms.fogSettings.x) /
        max(1.0, uniforms.fogSettings.y - uniforms.fogSettings.x), 0.0, 1.0);
    color = mix(color,half3(uniforms.fogColor.rgb),half(fog));
    return half4(color,textureColor.a * half(in.tint.a * uniforms.tintColor.a));
}


// The indexed solid prefix is cut out but opaque. The clear suffix retains
// source alpha and belongs to the later, non-depth-writing surface phase.
static half4 worldSurfaceShade(Raster in,half4 texel,constant Uniforms &uniforms,uint clear) {
    half opacity=texel.a*half(in.tint.a);
    if (clear!=0 ? opacity<0.03h : opacity<0.1h) discard_fragment();
    half3 day=min(half3(in.tint.rgb)+half3(0.30h),half3(1.0h));
    half3 night=min(half3(in.dusk.rgb)+half3(0.10h,0.10h,0.15h),half3(1.0h));
    half3 light=mix(day,night,half(clamp(uniforms.settings.z,0.0,1.0)));
    half3 color=texel.rgb*light*half3(uniforms.tintColor.rgb);
    float fog=uniforms.fogSettings.z*clamp((in.depth-uniforms.fogSettings.x)/
        max(1.0,uniforms.fogSettings.y-uniforms.fogSettings.x),0.0,1.0);
    color=mix(color,half3(uniforms.fogColor.rgb),half(fog));
    return half4(color,(clear!=0 ? opacity:1.0h)*half(uniforms.tintColor.a));
}
fragment half4 worldSurfaceFragment(Raster in [[stage_in]],texture2d<half> atlas [[texture(0)]],
    constant Uniforms &uniforms [[buffer(1)]],constant uint &clear [[buffer(3)]]) {
    return worldSurfaceShade(in,nativeAtlasColor(in,atlas,uniforms),uniforms,clear);
}
fragment half4 worldSharpSurfaceFragment(Raster in [[stage_in]],
    texture2d<half> atlas [[texture(0)]],texture2d_array<half> images [[texture(1)]],
    sampler originalSampler [[sampler(0)]],constant Uniforms &uniforms [[buffer(1)]],
    constant uint *map [[buffer(2)]],constant uint &clear [[buffer(3)]]) {
    float layer=round(in.layer);uint selected=0;
    if(isfinite(layer) && layer>=0.0 && layer<float(map[0])) selected=map[4+uint(layer)];
    half4 texel;
    if(selected>0 && selected<=map[1] && selected<=images.get_array_size())
        texel=images.sample(originalSampler,in.uv,selected-1);
    else texel=nativeAtlasColor(in,atlas,uniforms);
    return worldSurfaceShade(in,texel,uniforms,clear);
}
