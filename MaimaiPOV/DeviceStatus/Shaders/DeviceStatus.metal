#include <metal_stdlib>
using namespace metal;

struct DeviceStatusUniforms {
    float posX;
    float posY;
    float texWidth;
    float texHeight;
    float opacity;
    float outWidth;
    float outHeight;
    float originX;
    float originY;
};

kernel void deviceStatusBlend(
    texture2d<float, access::read_write> outputTexture [[texture(0)]],
    texture2d<float, access::sample> statusTexture [[texture(1)]],
    constant DeviceStatusUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    float2 pixelPos = float2(gid.x + u.originX, gid.y + u.originY);

    if (pixelPos.x >= u.outWidth || pixelPos.y >= u.outHeight) return;

    if (pixelPos.x < u.posX || pixelPos.x >= u.posX + u.texWidth ||
        pixelPos.y < u.posY || pixelPos.y >= u.posY + u.texHeight) return;

    float relX = (pixelPos.x - u.posX) / u.texWidth;
    float relY = (pixelPos.y - u.posY) / u.texHeight;

    if (relX < 0.0 || relX > 1.0 || relY < 0.0 || relY > 1.0) return;

    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 statusPixel = statusTexture.sample(s, float2(relX, relY));

    float alpha = statusPixel.a * u.opacity;
    if (alpha < 0.001) return;

    uint2 writePos = uint2(pixelPos.x, pixelPos.y);
    float4 background = outputTexture.read(writePos);
    float4 result = float4(
        statusPixel.rgb * alpha + background.rgb * (1.0 - alpha),
        1.0
    );
    outputTexture.write(result, writePos);
}
