#include <metal_stdlib>
using namespace metal;
struct VertexOut { float4 position [[position]]; float2 uv; };
struct Params { float progress; float perspective; float blur; float shadow; float aspect; float style; float protectedTop; float pad2; };
vertex VertexOut bendVertex(uint id [[vertex_id]]) {
    float2 p[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    VertexOut out; out.position=float4(p[id],0,1); out.uv=float2((p[id].x+1)*0.5,(1-p[id].y)*0.5); return out;
}
fragment float4 bendFragment(VertexOut in [[stage_in]], texture2d<float> desktop [[texture(0)]], texture2d<float> fine [[texture(1)]], texture2d<float> soft [[texture(2)]], texture2d<float> medium [[texture(3)]], texture2d<float> strong [[texture(4)]], constant Params &p [[buffer(0)]]) {
    constexpr sampler s(coord::normalized,address::clamp_to_edge,filter::linear);
    float fold=clamp(p.progress,0.0,1.0);
    if (fold < 0.00001 || in.uv.y < p.protectedTop) return desktop.sample(s,in.uv);
    float height=1.0-in.uv.y;
    // Rectified reference frames show content lifting toward the top, not
    // receding into a shorter plane. Both vertical endpoints stay anchored.
    float lift=1.15*fold*p.perspective;
    float projectedY=in.uv.y*(1.0+lift)/(1.0+lift*in.uv.y);
    float sourceY=mix(projectedY,in.uv.y,smoothstep(0.8,1.0,in.uv.y));
    float inset=0.13*fold*p.perspective*height;
    float2 uv=float2((in.uv.x-0.5)/(1.0-2.0*inset)+0.5,sourceY);
    // Select adjacent Gaussian levels instead of layering a sharp ghost over
    // every blurred image. The blur grows continuously toward the top.
    float radius=64.0*fold*pow(height,2.2)*(p.style>1.5 ? 1.25 : 1.0);
    float3 color;
    if (p.blur<0.001) color=desktop.sample(s,uv).rgb;
    else if(radius<4.0) color=mix(desktop.sample(s,uv).rgb,fine.sample(s,uv).rgb,smoothstep(0.0,4.0,radius));
    else if(radius<10.0) color=mix(fine.sample(s,uv).rgb,soft.sample(s,uv).rgb,smoothstep(4.0,10.0,radius));
    else if(radius<28.0) color=mix(soft.sample(s,uv).rgb,medium.sample(s,uv).rgb,smoothstep(10.0,28.0,radius));
    else color=mix(medium.sample(s,uv).rgb,strong.sample(s,uv).rgb,smoothstep(28.0,64.0,radius));
    // Feather the sides, not a horizontal black strip across the top.
    float feather=max(fwidth(in.uv.x),0.040*fold*(0.25+0.75*p.blur)*height);
    float edge=min(in.uv.x-inset,1.0-inset-in.uv.x);
    float coverage=smoothstep(-feather,feather,edge);
    float sideShade=exp(-max(edge,0.0)/0.035)*fold*p.shadow*0.32*height;
    if(p.style>0.5 && p.style<1.5) sideShade*=1.6;
    color*=1.0-sideShade;
    if(p.style>1.5) color=mix(color,float3(0.86,0.9,0.94),fold*pow(height,2.3)*0.08);
    return float4(color*coverage,1);
}
