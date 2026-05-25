#include <metal_stdlib>
using namespace metal;

struct CanvasUniforms {
    float cropX1;
    float cropY1;
    float cropW;
    float cropH;
    float stabWidth;
    float stabHeight;
    float canvasWidth;
    float canvasHeight;
    float gameX;
    float gameY;
    float gameW;
    float gameH;
    float bgColorR;
    float bgColorG;
    float bgColorB;
};

kernel void cropAndCompose(
    texture2d<float, access::sample> stabOutput [[texture(0)]],
    texture2d<float, access::write>  canvasOutput [[texture(1)]],
    constant CanvasUniforms& u [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= uint(u.canvasWidth) || gid.y >= uint(u.canvasHeight)) return;

    if (gid.x >= uint(u.gameX) && gid.x < uint(u.gameX + u.gameW) &&
        gid.y >= uint(u.gameY) && gid.y < uint(u.gameY + u.gameH))
    {
        float relX = float(gid.x - uint(u.gameX)) / u.gameW;
        float relY = float(gid.y - uint(u.gameY)) / u.gameH;

        float srcX = u.cropX1 + relX * u.cropW;
        float srcY = u.cropY1 + relY * u.cropH;

        if (srcX < 0.0 || srcX >= u.stabWidth || srcY < 0.0 || srcY >= u.stabHeight) {
            canvasOutput.write(float4(u.bgColorR, u.bgColorG, u.bgColorB, 1.0), gid);
            return;
        }

        float2 uv = float2(srcX / u.stabWidth, srcY / u.stabHeight);
        constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
        float4 rgba = stabOutput.sample(s, uv);
        canvasOutput.write(rgba, gid);
    }
    else
    {
        canvasOutput.write(float4(u.bgColorR, u.bgColorG, u.bgColorB, 1.0), gid);
    }
}
