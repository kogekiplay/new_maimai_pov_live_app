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
    float originX;
    float originY;
};

kernel void marqueeBlend(
    texture2d<float, access::read_write> outputTexture [[texture(0)]],
    texture2d<float, access::sample> textTexture [[texture(1)]],
    constant MarqueeUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float2 pixelPos = float2(gid.x + u.originX, gid.y + u.originY);

    if (pixelPos.x >= u.outWidth || pixelPos.y >= u.outHeight) return;

    float textLeft = u.scrollX;
    float textRight = u.scrollX + u.textWidth;
    float textTop = u.textY;
    float textBottom = u.textY + u.textHeight;

    if (pixelPos.x < textLeft || pixelPos.x >= textRight ||
        pixelPos.y < textTop || pixelPos.y >= textBottom) return;

    float relX = (pixelPos.x - textLeft) / u.textWidth;
    float relY = (pixelPos.y - textTop) / u.textHeight;

    if (relX < 0.0 || relX > 1.0 || relY < 0.0 || relY > 1.0) return;

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 textPixel = textTexture.sample(s, float2(relX, relY));

    float alpha = textPixel.a * u.opacity;
    if (alpha < 0.001) return;

    uint2 writePos = uint2(pixelPos.x, pixelPos.y);
    float4 background = outputTexture.read(writePos);
    float4 result = float4(
        textPixel.rgb * alpha + background.rgb * (1.0 - alpha),
        1.0
    );
    outputTexture.write(result, writePos);
}
