#include <metal_stdlib>
using namespace metal;

static float liquidBlob(float2 uv, float2 center, float2 scale) {
    float2 d = (uv - center) / scale;
    return exp(-dot(d, d));
}

[[ stitchable ]] half4 flameGlass(float2 position, half4 color, float2 size, float time, float2 tilt) {
    float2 uv = position / max(size, float2(1.0));
    float aspect = size.x / max(size.y, 1.0);
    float2 centered = float2((uv.x - 0.5) * aspect, uv.y - 0.5);

    float radius = aspect * 0.5;
    float segment = 0.5 - radius;
    float capsuleDistance = length(float2(centered.x, max(abs(centered.y) - segment, 0.0))) - radius;
    float edge = smoothstep(0.038, 0.0, abs(capsuleDistance));
    float inner = smoothstep(0.0, -0.11, capsuleDistance);

    float liquidWindow = smoothstep(0.08, 0.20, uv.y) * (1.0 - smoothstep(0.97, 1.0, uv.y));
    float slow = time * 0.72;
    float2 flow = clamp(tilt, float2(-1.0), float2(1.0));
    float surfaceLevel = 0.84 - flow.y * 0.08;
    float surfaceTilt = flow.x * (uv.x - 0.5) * 0.18;
    float fillMask = smoothstep(surfaceLevel + surfaceTilt, surfaceLevel + surfaceTilt + 0.13, uv.y);

    float2 poolUv = uv;
    poolUv.x += sin(slow + uv.y * 4.0) * 0.030 - flow.x * 0.11;
    poolUv.y += sin(slow * 0.8 + uv.x * 5.0) * 0.018 + flow.y * 0.05;

    float bottomPool = liquidBlob(poolUv, float2(0.50, 0.91), float2(0.52, 0.17));
    bottomPool += liquidBlob(poolUv, float2(0.29, 0.84), float2(0.31, 0.13)) * 0.48;
    bottomPool += liquidBlob(poolUv, float2(0.72, 0.85), float2(0.33, 0.13)) * 0.46;

    float2 slosh = float2(flow.x * 0.18, flow.y * -0.10);
    float2 dropA = float2(0.30 + sin(slow * 0.9) * 0.06, 0.68 + sin(slow * 1.1) * 0.07) + slosh * 0.80;
    float2 dropB = float2(0.52 + sin(slow * 0.7 + 1.4) * 0.05, 0.58 + sin(slow * 0.95 + 0.8) * 0.08) + slosh;
    float2 dropC = float2(0.73 + sin(slow * 0.8 + 2.2) * 0.06, 0.70 + sin(slow * 1.0 + 2.6) * 0.07) + slosh * 0.75;
    float risingDrops = liquidBlob(uv, dropA, float2(0.18, 0.13)) * 0.56;
    risingDrops += liquidBlob(uv, dropB, float2(0.20, 0.15)) * 0.64;
    risingDrops += liquidBlob(uv, dropC, float2(0.18, 0.13)) * 0.54;

    float bridge = smoothstep(0.48, 0.06, abs(uv.x - 0.50)) * smoothstep(0.92, 0.42, uv.y) * 0.24;
    float field = (bottomPool * 1.05 + risingDrops * 1.14 + bridge * 0.70) * liquidWindow * fillMask;
    float liquid = smoothstep(0.34, 0.58, field);
    liquid = pow(liquid, 0.72);

    float purpleMix = smoothstep(0.50, 0.23, uv.y) * liquid;
    purpleMix = clamp(purpleMix, 0.0, 1.0);

    float3 base = float3(0.010, 0.010, 0.013);
    float3 honey = float3(0.72, 0.33, 0.040);
    float3 amber = float3(0.34, 0.11, 0.020);
    float3 purple = float3(0.66, 0.18, 1.0);
    float3 liquidColor = mix(honey, amber, smoothstep(0.98, 0.48, uv.y));
    liquidColor = mix(liquidColor, purple, purpleMix * 0.86);

    float surface = smoothstep(0.48, 0.62, field) - smoothstep(0.70, 0.86, field);
    float3 glassEdge = float3(0.25, 0.23, 0.25) * edge * 0.58;
    float3 meniscus = float3(0.86, 0.46, 0.10) * edge * smoothstep(0.44, 0.95, uv.y) * 0.18;
    float3 rgb = base + liquidColor * liquid * 1.38 + liquidColor * surface * 0.20 + glassEdge + meniscus;
    rgb *= 0.68 + inner * 0.50;

    return half4(half3(rgb), half(1.0));
}
