#include <metal_stdlib>
using namespace metal;

struct OverlayUniforms {
    float posX;
    float posY;
    float scale;
    float opacity;
    float rotation;
    float overlayWidth;
    float overlayHeight;
    float outWidth;
    float outHeight;
    float originX;
    float originY;
};

kernel void overlayBlend(
    texture2d<float, access::read_write> outputTexture [[texture(0)]],
    texture2d<float, access::sample> overlayTexture [[texture(1)]],
    constant OverlayUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float2 pixelPos = float2(gid.x + u.originX, gid.y + u.originY);

    if (pixelPos.x >= u.outWidth || pixelPos.y >= u.outHeight) return;

    float overlayPixelW = u.outWidth * u.scale;
    float overlayPixelH = overlayPixelW * (u.overlayHeight / u.overlayWidth);
    float centerX = u.posX * u.outWidth;
    float centerY = u.posY * u.outHeight;

    float dx = pixelPos.x - centerX;
    float dy = pixelPos.y - centerY;

    float cosR = cos(u.rotation);
    float sinR = sin(u.rotation);

    float rotDx = dx * cosR + dy * sinR;
    float rotDy = -dx * sinR + dy * cosR;

    float relX = (rotDx + overlayPixelW / 2.0) / overlayPixelW;
    float relY = (rotDy + overlayPixelH / 2.0) / overlayPixelH;

    if (relX < 0.0 || relX > 1.0 || relY < 0.0 || relY > 1.0) return;

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 overlay = overlayTexture.sample(s, float2(relX, relY));

    float alpha = overlay.a * u.opacity;
    if (alpha < 0.001) return;

    uint2 writePos = uint2(pixelPos.x, pixelPos.y);
    float4 background = outputTexture.read(writePos);
    float4 result = float4(
        overlay.rgb * alpha + background.rgb * (1.0 - alpha),
        1.0
    );
    outputTexture.write(result, writePos);
}
