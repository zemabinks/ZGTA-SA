#include <metal_stdlib>
using namespace metal;

struct AtmosphereVertex { float4 position, uvLayer, tint, dusk; };
struct AtmosphereUniforms {
    float4x4 matrix;
    float4 atlas; // width, height, cell size, unused
};
struct AtmosphereRaster {
    float4 position [[position]];
    float2 uv;
    float layer;
    float4 tint;
};
vertex AtmosphereRaster nativeAtmosphereVertex(uint id [[vertex_id]],
        const device AtmosphereVertex *vertices [[buffer(0)]],
        constant AtmosphereUniforms &u [[buffer(1)]]) {
    AtmosphereVertex v = vertices[id]; AtmosphereRaster o;
    o.position = u.matrix * v.position;
    if (v.uvLayer.w > 0.5) o.position.z = o.position.w * 0.9999;
    o.uv = v.uvLayer.xy; o.layer = v.uvLayer.z; o.tint = v.tint; return o;
}
static float4 atmosphereTex(AtmosphereRaster in, texture2d<half> atlas, constant AtmosphereUniforms &u) {
    constexpr sampler sample(coord::normalized, address::clamp_to_edge, filter::linear);
    float columns = floor(u.atlas.x / u.atlas.z);
    float2 tile = float2(fmod(round(in.layer),columns),floor(round(in.layer)/columns));
    float2 uv = (tile*u.atlas.z+0.5+clamp(in.uv,0.0,1.0)*(u.atlas.z-1.0))/u.atlas.xy;
    return float4(atlas.sample(sample,uv));
}
static float3 outputSRGB(float3 c) {
    return select(1.055*pow(max(c,0.0),float3(1.0/2.4))-0.055,c*12.92,c<=0.0031308);
}
fragment half4 nativeSkySpriteFragment(AtmosphereRaster in [[stage_in]],texture2d<half> atlas [[texture(0)]],constant AtmosphereUniforms &u [[buffer(1)]]) {
    return half4(half3(atmosphereTex(in,atlas,u).rgb*in.tint.rgb),1.0h);
}
fragment half4 nativeCloudSpriteFragment(AtmosphereRaster in [[stage_in]],texture2d<half> atlas [[texture(0)]],constant AtmosphereUniforms &u [[buffer(1)]]) {
    float4 tex = atmosphereTex(in,atlas,u); float alpha = tex.a*in.tint.a;
    if (alpha < 0.004) discard_fragment(); return half4(half3(tex.rgb*in.tint.rgb),half(alpha));
}
fragment half4 nativeWeatherSpriteFragment(AtmosphereRaster in [[stage_in]],texture2d<half> atlas [[texture(0)]],constant AtmosphereUniforms &u [[buffer(1)]]) {
    float4 tex = atmosphereTex(in,atlas,u); float alpha = tex.a*in.tint.a;
    if (alpha < 0.003) discard_fragment(); return half4(half3(outputSRGB(tex.rgb*in.tint.rgb)),half(alpha));
}
fragment half4 nativeAtmosphereColorFragment(AtmosphereRaster in [[stage_in]]) { return half4(in.tint); }
fragment half4 nativeRainbowFragment(AtmosphereRaster in [[stage_in]]) {
    const float3 colors[] = {float3(30,0,0),float3(30,15,0),float3(30,30,0),float3(10,30,10),float3(0,0,30),float3(15,0,30)};
    float at=clamp(1.0-in.uv.y,0.0,1.0)*5.0; uint first=uint(min(floor(at),4.0));
    float3 color=mix(colors[first],colors[first+1],at-float(first))/255.0;
    float soft=sin(in.uv.y*3.14159);
    return half4(half3(color*(in.tint.x*soft*soft*smoothstep(0.0,0.08,in.layer))),1.0h);
}

struct DomeUniforms { float4x4 inverseMatrix; float4 eye, forward, high, low, below, settings; };
struct DomeRaster { float4 position [[position]]; float2 ndc; };
vertex DomeRaster nativeDomeVertex(uint id [[vertex_id]]) {
    const float2 p[]={float2(-1,-1),float2(3,-1),float2(-1,3)};
    DomeRaster o;o.position=float4(p[id],0.9999,1);o.ndc=p[id];return o;
}
fragment half4 nativeDomeFragment(DomeRaster in [[stage_in]],constant DomeUniforms &u [[buffer(1)]]) {
    float4 projected=u.inverseMatrix*float4(in.ndc,1,1);
    float3 way=normalize(projected.xyz/projected.w-u.eye.xyz);
    float3 own=mix(u.low.rgb,u.high.rgb,pow(clamp(way.z,0.0,1.0),0.55));
    float game=max(u.settings.x,u.settings.y);
    float across=length(u.forward.xy);float2 ahead=across>0.0001?u.forward.xy/across:float2(0);
    float along=dot(way.xy,ahead),rise=along>0.0001?way.z/along:(way.z>=0.0?1000.0:-1000.0);
    float3 games=rise>=0.0?mix(u.low.rgb,u.high.rgb,min(rise*2.0,1.0)):mix(u.low.rgb,u.below.rgb,clamp((-rise-0.1)*5.0,0.0,1.0));
    return half4(half3(mix(own,games,game)),1.0h);
}

struct WaterUniforms {
    float4x4 matrix;
    float4 eye;
    float4 tint;
    float4 alphas;
    float4 shifts;
    float4 waves; // phases, roughness (without 0.67)
    float4 fogColor;
    float4 fog; // fogStart, farClip, gameFog, haze
    float4 net; // origin x/y, replacement half width, unused
    float4 alongX[2];
    float4 alongY[2];
};
struct WaterRaster {
    float4 position [[position]];
    float2 game;
    float3 place;
    float depth;
    float2 shade;
    float wavy;
};
static WaterRaster waterVertex(AtmosphereVertex v,constant WaterUniforms &u) {
    WaterRaster o;float2 game=v.position.xy;float3 place=v.position.xyz;
    o.game=game;o.wavy=v.uvLayer.w>0.5?-1.0:v.uvLayer.z;o.shade=float2(0.577,1);
    if (v.uvLayer.w > 0.5) {
        float2 at=abs(game),netted=at*0.5,corner=floor(netted),share=fract(netted);
        uint x=uint(fmod(corner.x,8.0)),y=uint(fmod(corner.y,8.0)),nx=(x+1)%8,ny=(y+1)%8;
        float scale=mix(u.alongX[x/4][x%4],u.alongX[nx/4][nx%4],share.x)*mix(u.alongY[y/4][y%4],u.alongY[ny/4][ny%4],share.y);
        scale*=u.waves.w*clamp((1.0-distance(game,u.eye.xy)/48.0)/0.25,0.0,1.0);
        float3 tall=float3(2.0*v.uvLayer.x,v.uvLayer.y,0.5*v.uvLayer.y)*scale;
        float3 crests=float3(at.x/64.0+at.y/64.0,at.x/26.0+at.y/52.0,at.y*0.05);
        float3 phase=u.waves.xyz+fract(crests)*6.28318531;
        place.z+=dot(sin(phase),tall);
        float3 leans=cos(phase)*tall*float3(-0.09817477,0.24166097,0.31415927);
        float3 lean=normalize(float3(leans.x+leans.y+leans.z,leans.x+leans.y,1));
        o.shade=float2(max((lean.x+lean.y+lean.z)*0.577,0.0)*0.65+0.27,v.uvLayer.z);
    }
    o.place=place;o.position=u.matrix*float4(place,1);o.depth=o.position.w;return o;
}
vertex WaterRaster nativeWaterVertex(uint id [[vertex_id]],const device AtmosphereVertex *vertices [[buffer(0)]],constant WaterUniforms &u [[buffer(1)]]) {
    return waterVertex(vertices[id],u);
}
fragment half4 nativeWaterFragment(WaterRaster in [[stage_in]],texture2d<half> map [[texture(0)]],constant WaterUniforms &u [[buffer(1)]]) {
    if (in.shade.y < 0.0001) discard_fragment();
    // A negative wavy value marks the near net; flat wavy polygons yield to it.
    if (in.wavy>0.5 && abs(in.game.x-u.net.x)<u.net.z && abs(in.game.y-u.net.y)<u.net.z) discard_fragment();
    constexpr sampler sample(coord::normalized,address::repeat,filter::linear,mip_filter::linear);
    float3 first=float3(map.sample(sample,in.game/25.0+u.shifts.xy).rgb);
    float3 second=float3(map.sample(sample,in.game/12.5+u.shifts.zw).rgb);
    float caught=in.shade.x;
    if (in.wavy>=0.0) {
        float2 at=abs(in.game);
        float big=-cos(u.waves.x+(at.x*0.015625+at.y*0.015625)*6.283185)*0.398*0.098175;
        float small=cos(u.waves.y+(at.x*0.038462+at.y*0.019231)*6.283185)*0.241*0.241661;
        float cross=cos(u.waves.z+at.y*0.05*6.283185)*0.1205*0.314159;
        float3 lean=normalize(float3((big+small+cross)*u.waves.w*0.67,(big+small)*u.waves.w*0.67,1));
        caught=max((lean.x+lean.y+lean.z)*0.577,0.0)*0.65+0.27;
    }
    float near=1.0-smoothstep(24.0,48.0,distance(u.eye.xyz,in.place));
    float3 lit=u.tint.rgb*mix(0.577,caught,near);
    float solid=1.0-(1.0-u.alphas.x)*(1.0-u.alphas.y);
    float3 color=lit*(second*u.alphas.y+first*u.alphas.x*(1.0-u.alphas.y))/max(solid,0.001);
    float along=1.0-clamp(normalize(u.eye.xyz-in.place).z,0.0,1.0);
    float linearFog=clamp((in.depth-u.fog.x)/max(u.fog.y-u.fog.x,1.0),0.0,1.0);
    float hazed=1.0-exp(-in.depth*u.fog.w);
    float air=max(mix(hazed,linearFog,u.fog.z),linearFog*along*along*along);
    return half4(half3(mix(color,u.fogColor.rgb,air)),half(solid));
}
