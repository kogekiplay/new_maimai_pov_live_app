#include <metal_stdlib>
using namespace metal;

struct MarqueeUniforms {
    float scrollX;
    float textY;
    float textWidth;
    float textHeight;
    float opacity;
    float outWidth;
    float outHeight;
};

kernel void marqueeBlend(
    texture2d<float, access::read_write> outputTexture [[texture(0)]],
    texture2d<float, access::sample> textTexture [[texture(1)]],
    constant MarqueeUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= uint(u.outWidth) || gid.y >= uint(u.outHeight)) return;

    float textLeft = u.scrollX;
    float textRight = u.scrollX + u.textWidth;
    float textTop = u.textY;
    float textBottom = u.textY + u.textHeight;

    if (float(gid.x) < textLeft || float(gid.x) >= textRight ||
        float(gid.y) < textTop || float(gid.y) >= textBottom) return;

    float relX = (float(gid.x) - textLeft) / u.textWidth;
    float relY = (float(gid.y) - textTop) / u.textHeight;

    if (relX < 0.0 || relX > 1.0 || relY < 0.0 || relY > 1.0) return;

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 textPixel = textTexture.sample(s, float2(relX, relY));

    float alpha = textPixel.a * u.opacity;
    if (alpha < 0.001) return;

    float4 background = outputTexture.read(gid);
    float4 result = float4(
        textPixel.rgb * alpha + background.rgb * (1.0 - alpha),
        1.0
    );
    outputTexture.write(result, gid);
}
