#include <metal_stdlib>
using namespace metal;

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

vertex VSOut vs_main(uint vid [[vertex_id]]) {
    // Fullscreen triangle.
    float2 pos;
    float2 uv;
    if (vid == 0) { pos = float2(-1.0, -1.0); uv = float2(0.0, 1.0); }
    else if (vid == 1) { pos = float2( 3.0, -1.0); uv = float2(2.0, 1.0); }
    else { pos = float2(-1.0,  3.0); uv = float2(0.0, -1.0); }

    VSOut o;
    o.position = float4(pos, 0.0, 1.0);
    o.uv = uv;
    return o;
}

fragment float4 fs_main(VSOut in [[stage_in]],
                        texture2d<float> tex [[texture(0)]],
                        sampler samp [[sampler(0)]]) {
    // Clamp UV to texture space for safety.
    float2 uv = clamp(in.uv, float2(0.0), float2(1.0));
    return tex.sample(samp, uv);
}
