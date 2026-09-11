#include <metal_stdlib>
using namespace metal;
struct VertexOut { float4 position [[position]]; float2 uv; };
struct Params { float progress; float perspective; float blur; float shadow; float style; };
vertex VertexOut bendVertex(uint id [[vertex_id]]) {
    float2 p[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    VertexOut out; out.position=float4(p[id],0,1); out.uv=float2((p[id].x+1)*0.5,(1-p[id].y)*0.5); return out;
}
fragment float4 bendFragment(VertexOut in [[stage_in]], texture2d<float> desktop [[texture(0)]], texture2d<float> fine [[texture(1)]], texture2d<float> soft [[texture(2)]], texture2d<float> medium [[texture(3)]], texture2d<float> strong [[texture(4)]], constant Params &p [[buffer(0)]]) {
    constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::linear);
    float fold=clamp(p.progress,0.0,1.0);
    if (fold < 0.00001) return desktop.sample(s,in.uv);
    float height=1.0-in.uv.y;
    // Inverse projective mapping. The lower edge stays anchored at the hinge,
    // while the upper corners draw inward like the reference's folding sheet.
    // A single homography keeps straight desktop lines straight throughout.
    float taper=0.24*fold*p.perspective;
    float depth=(2.0*taper)/max(0.1,1.0-2.0*taper);
    float sourceHeight=height/(1.0+depth*(1.0-height));
    float width=1.0/(1.0+depth*sourceHeight);
    float inset=(1.0-width)*0.5;
    float2 uv=float2((in.uv.x-0.5)/width+0.5,1.0-sourceHeight);
    float hingeWeight=smoothstep(0.0,0.22,height);
    // Concentrate defocus at the upper edge, including the menu bar. Keeping
    // the centre readable avoids making the whole desktop look out of focus.
    float radius=48.0*fold*pow(height,3.5)*(p.style>1.5 ? 1.25 : 1.0);
    float3 color;
    if (p.blur<0.001) color=desktop.sample(s,uv).rgb;
    else if(radius<4.0) color=mix(desktop.sample(s,uv).rgb,fine.sample(s,uv).rgb,smoothstep(0.0,4.0,radius));
    else if(radius<10.0) color=mix(fine.sample(s,uv).rgb,soft.sample(s,uv).rgb,smoothstep(4.0,10.0,radius));
    else if(radius<28.0) color=mix(soft.sample(s,uv).rgb,medium.sample(s,uv).rgb,smoothstep(10.0,28.0,radius));
    else color=mix(medium.sample(s,uv).rgb,strong.sample(s,uv).rgb,smoothstep(28.0,64.0,radius));
    // Feather the sides, not a horizontal black strip across the top.
    float feather=max(fwidth(in.uv.x),0.0025*fold*height);
    float edge=min(in.uv.x-inset,1.0-inset-in.uv.x);
    float coverage=smoothstep(-feather,feather,edge);
    float sideShade=exp(-max(edge,0.0)/0.035)*fold*p.shadow*0.22*height*hingeWeight;
    if(p.style>0.5 && p.style<1.5) sideShade*=1.6;
    color*=1.0-sideShade;
    if(p.style>1.5) color=mix(color,float3(0.86,0.9,0.94),fold*pow(height,2.3)*0.08);
    return float4(color*coverage,1);
}
