#include <metal_stdlib>
using namespace metal;
struct Vertex { float3 position; float4 color; float2 uv; };
struct Uniforms { float4x4 viewProjection; float4x4 modelToBoard; float4x4 boardToWorld; float4 tint; float4 edges[8]; uint edgeCount; uint textured; uint clipped; uint padding; };
struct Out { float4 position [[position]]; float4 color; float2 uv; float3 board; };
vertex Out sc_vertex(uint id [[vertex_id]], device const Vertex *vertices [[buffer(0)]], constant Uniforms &u [[buffer(1)]]) {
    Vertex v=vertices[id]; float4 board=u.modelToBoard*float4(v.position,1); Out o;
    o.position=u.viewProjection*u.boardToWorld*board; o.color=v.color*u.tint; o.uv=v.uv; o.board=board.xyz; return o;
}
fragment float4 sc_fragment(Out in [[stage_in]], constant Uniforms &u [[buffer(1)]], texture2d<float> texture [[texture(0)]]) {
    if(u.clipped) { bool positive=false,negative=false;
        for(uint i=0;i<u.edgeCount;i++) { float4 e=u.edges[i]; float2 d=e.zw-e.xy,p=in.board.xz-e.xy; float v=d.x*p.y-d.y*p.x; positive|=v>0.00002; negative|=v < -0.00002; }
        // The table bounds an X/Z footprint, not an elevation slice. Rivers and
        // lower floors remain visible when the player-centered origin rises.
        if(positive&&negative) discard_fragment();
    }
    constexpr sampler s(address::repeat,filter::linear,mip_filter::linear);
    float4 c=in.color;
    if(u.textured) { float4 t=texture.sample(s,in.uv); if(t.a<0.03) discard_fragment(); c*=t; }
    if(c.a<(u.clipped ? 0.2 : 0.005)) discard_fragment();
    return float4(c.rgb*c.a,c.a);
}
