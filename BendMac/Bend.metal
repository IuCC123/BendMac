#include <metal_stdlib>
using namespace metal;
struct VertexOut { float4 position [[position]]; float2 uv; };
struct Params { float progress; float perspective; float blur; float shadow; float aspect; float style; float pad1; float pad2; };
vertex VertexOut bendVertex(uint id [[vertex_id]]) {
    float2 p[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    VertexOut out; out.position = float4(p[id],0,1); out.uv = float2((p[id].x+1)*0.5, (1-p[id].y)*0.5); return out;
}
fragment float4 bendFragment(VertexOut in [[stage_in]], texture2d<float> desktop [[texture(0)]], texture2d<float> soft [[texture(1)]], texture2d<float> medium [[texture(2)]], texture2d<float> strong [[texture(3)]], constant Params &p [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float fold = p.progress;
    float theta = fold * p.perspective * 0.20943951;
    float c = cos(theta), k = sin(theta) / 10.0;
    float projectedY = 1 - in.uv.y;
    // Invert bottom-anchored 3-D projective transform for perspective-correct sampling.
    float denom = c - projectedY * k;
    if (denom <= 0.001) return float4(0,0,0,1);
    float y = projectedY / denom;
    float scale = 1 + y*k;
    float2 uv = float2((in.uv.x-0.5)*scale+0.5, 1-y);
    if (any(uv < 0) || any(uv > 1)) return float4(0,0,0,1);
    float top = pow(y, 2.3);
    float3 color = desktop.sample(s, uv).rgb;
    // Keep the physical screen plane. The lid already supplies the rotation.
    // Blur reaches the upper content early, with a sharp band at the hinge.
    float amount = (1.0-exp(-fold*6.0)) * (p.style > 1.5 ? 1.25 : 1.0);
    color = mix(color,soft.sample(s,uv).rgb,clamp(amount*(1-smoothstep(0.42,0.94,uv.y)),0.0,1.0));
    color = mix(color,medium.sample(s,uv).rgb,clamp(amount*(1-smoothstep(0.22,0.75,uv.y)),0.0,1.0));
    color = mix(color,strong.sample(s,uv).rgb,clamp(amount*(1-smoothstep(0.08,0.48,uv.y)),0.0,1.0));
    float corners = exp(-uv.x*uv.x*15.0) + exp(-(1-uv.x)*(1-uv.x)*15.0);
    float shade = fold*p.shadow*(0.08*pow(y,3.0) + 0.25*corners*pow(y,4.0));
    if (p.style > 0.5 && p.style < 1.5) shade *= 1.6;
    color *= 1-clamp(shade,0.0,0.9);
    if (p.style > 1.5) color = mix(color, float3(0.86,0.9,0.94), fold*top*0.15);
    float feather = max(0.0001, fold*0.025*p.blur);
    color *= smoothstep(0.0,feather,uv.y);
    // A fine anti-aliased edge keeps the sidewalls stable while the lid moves.
    float edge = min(uv.x,1-uv.x) / max(fwidth(uv.x),0.0001);
    return float4(color * clamp(edge,0.0,1.0),1);
}
