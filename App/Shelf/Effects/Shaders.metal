#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// Value noise + fBm, cheap enough for a full-window background at 30 fps.
static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

static float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int i = 0; i < 4; i++) {
        value += amplitude * valueNoise(p);
        p *= 2.03;
        amplitude *= 0.5;
    }
    return value;
}

/// Topographic contour lines drifting slowly, tinted across the width. Onboarding backdrop.
[[ stitchable ]] half4 topographicFlow(float2 position, half4 color, float2 size, float time,
                                       half4 tintA, half4 tintB, float density) {
    float2 uv = position / max(size.y, 1.0);
    float n = fbm(uv * 2.2 + float2(time * 0.030, -time * 0.020))
            + 0.35 * fbm(uv * 4.0 - float2(time * 0.015, time * 0.010));
    float bands = n * density;
    float f = fract(bands);
    float edge = min(f, 1.0 - f);
    float lineWidth = density * 0.0035;
    float line = 1.0 - smoothstep(0.0, lineWidth, edge);
    float glow = 1.0 - smoothstep(0.0, lineWidth * 7.0, edge);
    float across = clamp(position.x / max(size.x, 1.0), 0.0, 1.0);
    half4 tint = mix(tintA, tintB, half(smoothstep(0.1, 0.9, across)));
    float alpha = line * 0.55 + glow * 0.08;
    return half4(tint.rgb * half(alpha), half(alpha));
}

/// Vinyl record: fine grooves, the dead wax and run-out, and two anisotropic sheen wedges.
/// The light is fixed, so only the label needs to rotate for the record to look like it spins.
[[ stitchable ]] half4 vinylRecord(float2 position, half4 color, float2 size, half4 tint) {
    float2 c = size * 0.5;
    float2 d = position - c;
    float radius = min(size.x, size.y) * 0.5;
    float r = length(d) / radius;
    if (r > 1.0) return half4(0);
    float angle = atan2(d.y, d.x);

    float grooves = 0.5 + 0.5 * sin(r * radius * 2.6);
    float tracks = smoothstep(0.004, 0.0, abs(fract(r * 7.0) - 0.5) - 0.49);
    float3 base = float3(0.035, 0.035, 0.04) + float3(tint.rgb) * 0.05;
    base += grooves * 0.018;
    base -= tracks * 0.02;

    float sheen = pow(abs(cos(angle - 0.9)), 18.0) + 0.6 * pow(abs(cos(angle + 0.5)), 30.0);
    sheen *= smoothstep(0.36, 0.5, r) * smoothstep(1.0, 0.92, r);
    base += sheen * float3(0.33, 0.32, 0.36);

    float rim = smoothstep(0.985, 1.0, r);
    base = mix(base, float3(0.0), rim);
    float edgeAlpha = 1.0 - smoothstep(0.995, 1.0, r);
    return half4(half3(base) * half(edgeAlpha), half(edgeAlpha));
}

/// Lava lamp: metaballs rising and falling through a warm gradient.
[[ stitchable ]] half4 lavaLamp(float2 position, half4 color, float2 size, float time, half4 colorA, half4 colorB) {
    float2 uv = position / size;
    float field = 0.0;
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float speed = 0.05 + 0.025 * fract(fi * 0.37);
        float y = fract(fi * 0.21 + time * speed);
        y = 0.5 + 0.48 * sin(y * 6.2831 + fi);
        float x = 0.5 + 0.3 * sin(time * 0.17 + fi * 1.7);
        float2 p = float2(x, 1.0 - y);
        float2 delta = (uv - p) * float2(size.x / size.y, 1.0);
        float rr = 0.012 + 0.008 * fract(fi * 0.53);
        field += rr / max(dot(delta, delta), 0.0001);
    }
    float blob = smoothstep(0.9, 1.15, field);
    half3 liquid = mix(colorB.rgb * 0.25h, colorB.rgb * 0.55h, half(uv.y));
    half3 wax = mix(colorA.rgb, colorA.rgb * 1.25h + 0.12h, half(smoothstep(1.2, 3.5, field)));
    half3 rgb = mix(liquid, wax, half(blob));
    return half4(rgb, 1.0h);
}

/// Weather sky. condition: 0 clear, 1 partly cloudy, 2 cloudy, 3 fog, 4 drizzle, 5 rain, 6 snow, 7 storm.
[[ stitchable ]] half4 weatherSky(float2 position, half4 color, float2 size, float time, float condition, float isDay) {
    float2 uv = position / size;
    float3 dayTop = float3(0.29, 0.56, 0.86), dayBottom = float3(0.62, 0.79, 0.93);
    float3 nightTop = float3(0.03, 0.05, 0.12), nightBottom = float3(0.10, 0.13, 0.25);
    float overcast = condition >= 2.0 ? 0.7 : (condition >= 1.0 ? 0.25 : 0.0);
    float3 top = mix(nightTop, dayTop, isDay);
    float3 bottom = mix(nightBottom, dayBottom, isDay);
    float3 grey = mix(float3(0.16, 0.17, 0.2), float3(0.55, 0.58, 0.63), isDay);
    float3 sky = mix(mix(top, bottom, uv.y), grey * (0.8 + 0.3 * uv.y), overcast);

    if (condition >= 1.0) {
        float clouds = fbm(float2(uv.x * 3.0 + time * 0.02, uv.y * 4.0));
        float cover = condition >= 2.0 ? 0.35 : 0.55;
        float c = smoothstep(cover, cover + 0.3, clouds) * (1.0 - uv.y * 0.6);
        sky = mix(sky, mix(float3(0.85), float3(0.3, 0.32, 0.38), 1.0 - isDay), c * 0.6);
    }
    if (condition < 1.0 && isDay < 0.5) {
        float star = step(0.995, hash21(floor(position * 0.5))) * (0.6 + 0.4 * sin(time * 2.0 + hash21(floor(position)) * 6.0));
        sky += star * (1.0 - uv.y);
    }
    if (condition >= 4.0 && condition < 6.0 || condition >= 7.0) {
        float density = condition >= 5.0 ? 1.0 : 0.45;
        float2 p = float2(position.x + position.y * 0.18, position.y);
        float column = floor(p.x / 6.0);
        float speed = 420.0 + 180.0 * hash21(float2(column, 1.0));
        float drop = fract((p.y + time * speed) / 70.0 + hash21(float2(column, 3.0)));
        float streak = smoothstep(0.0, 0.12, drop) * smoothstep(0.24, 0.12, drop);
        streak *= step(1.0 - density * 0.55, hash21(float2(column, 7.0)));
        streak *= 1.0 - smoothstep(0.6, 3.0, abs(fract(p.x / 6.0) * 6.0 - 3.0));
        sky += streak * 0.22;
    }
    if (condition >= 6.0 && condition < 7.0) {
        for (int layer = 0; layer < 3; layer++) {
            float scale = 18.0 + float(layer) * 10.0;
            float2 p = position / scale + float2(sin(time * 0.6 + float(layer)) * 0.3, -time * (0.6 + float(layer) * 0.25));
            float2 cell = floor(p);
            float2 f = fract(p) - 0.5 - (float2(hash21(cell), hash21(cell + 9.1)) - 0.5) * 0.6;
            float flake = smoothstep(0.09, 0.0, length(f)) * step(0.55, hash21(cell + 3.3));
            sky += flake * 0.8;
        }
    }
    if (condition >= 7.0) {
        float flash = step(0.985, fract(sin(floor(time * 3.0) * 12.9898) * 43758.5453));
        sky += flash * 0.25;
    }
    if (condition >= 3.0 && condition < 4.0) {
        float fog = fbm(float2(uv.x * 2.0 + time * 0.03, uv.y * 3.0));
        sky = mix(sky, float3(0.75, 0.77, 0.8) * mix(0.35, 1.0, isDay), smoothstep(0.3, 0.8, fog) * 0.6);
    }
    return half4(half3(sky), 1.0h);
}

/// LCD: a faint pixel grid and a soft vignette, as a color effect over the screen contents.
[[ stitchable ]] half4 lcdPixels(float2 position, half4 color, float2 size, float pitch) {
    float2 cell = fract(position / pitch);
    float grid = smoothstep(0.0, 0.18, cell.x) * smoothstep(0.0, 0.18, cell.y);
    float2 uv = position / size - 0.5;
    float vignette = 1.0 - dot(uv, uv) * 0.55;
    half shade = half(mix(0.95, 1.0, grid) * vignette);
    return half4(color.rgb * shade, color.a);
}
