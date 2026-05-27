#include <metal_stdlib>
using namespace metal;

struct SongCardUniforms {
    float posX;
    float posY;
    float scale;
    float opacity;
    float cardWidth;
    float cardHeight;
    float outWidth;
    float outHeight;
    float originX;
    float originY;
};

kernel void songCardBlend(
    texture2d<float, access::read_write> outputTexture [[texture(0)]],
    texture2d<float, access::sample> cardTexture [[texture(1)]],
    constant SongCardUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float2 pixelPos = float2(gid.x + u.originX, gid.y + u.originY);

    if (pixelPos.x >= u.outWidth || pixelPos.y >= u.outHeight) return;

    float cardPixelW = u.outWidth * u.scale;
    float cardPixelH = cardPixelW * (u.cardHeight / u.cardWidth);
    float centerX = u.posX * u.outWidth;
    float centerY = u.posY * u.outHeight;
    float left = centerX - cardPixelW / 2.0;
    float top = centerY - cardPixelH / 2.0;

    float relX = (pixelPos.x - left) / cardPixelW;
    float relY = (pixelPos.y - top) / cardPixelH;

    if (relX < 0.0 || relX > 1.0 || relY < 0.0 || relY > 1.0) return;

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 card = cardTexture.sample(s, float2(relX, relY));

    float alpha = card.a * u.opacity;
    if (alpha < 0.001) return;

    uint2 writePos = uint2(pixelPos.x, pixelPos.y);
    float4 background = outputTexture.read(writePos);
    float4 result = float4(
        card.rgb * alpha + background.rgb * (1.0 - alpha),
        1.0
    );
    outputTexture.write(result, writePos);
}
