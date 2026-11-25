//
//  Shaders.metal
//  YeHangChuan
//
//  滚动折射扰动：内容穿过玻璃表面上下边缘时产生横向位移，
//  模拟厚玻璃在移动世界前的折射畸变。
//

#include <metal_stdlib>
using namespace metal;

/// - Parameters:
///   - position: 目标像素坐标（内容层坐标系）
///   - offset: 内容层相对视口顶部的滚动位移
///   - viewportHeight: 可视区高度
///   - strength: 位移强度（pt），由滚动速度驱动
[[ stitchable ]] float2 glassRefraction(float2 position,
                                        float offset,
                                        float viewportHeight,
                                        float strength) {
    float screenY = position.y - offset;

    // 只靠近顶部/底部玻璃条的区域发生折射，中间正文保持原样
    float topBand = 1.0 - smoothstep(0.0, 110.0, screenY);
    float bottomBand = smoothstep(max(viewportHeight - 132.0, 1.0), viewportHeight, screenY);
    float band = max(topBand, bottomBand);

    if (band <= 0.001 || strength <= 0.001) {
        return position;
    }

    // 两层不同频率的正弦叠加：低频给出整体弯曲，高频给出一层层的水波
    float wave = sin(screenY * 0.09) * 0.55 + sin(screenY * 0.031 + 1.2) * 0.45;
    float dx = wave * band * strength;
    float dy = band * strength * 0.06 * (screenY < viewportHeight * 0.5 ? -1.0 : 1.0);

    return float2(position.x + dx, position.y + dy);
}
