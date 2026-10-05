// The CRT layer (plan, section 7): a C64 screen as it looks on the glass of a
// cathode-ray tube. It is presentation only: it draws the picture the monitor's
// display model made, which is what the converter optimised for, and never
// changes the C64 picture or its files.
//
// - Scanlines. A C64 sends a progressive picture, so the beam draws the same
//   lines every frame and the gaps between them stay dark. Each line is a beam
//   whose height grows with its brightness: dark lines are thin, with black
//   gaps between them, and bright ones nearly fill the gaps. A beam spreads its
//   light without adding any, so the picture keeps its brightness.
// - Glow: the glass scatters some of the light, so bright areas spill into
//   their surroundings and into the gaps.
// - Curvature: the glass bulges, so the picture shrinks towards its corners,
//   which are rounded, and darkens towards its edges.
//
// Light adds up in linear light, so the shader decodes the screen's sRGB, and
// encodes the result again for SwiftUI, which draws in extended sRGB.
//
// `CRT.swift` passes the arguments: the screen as RGBA bytes, its glow as
// linear RGBA floats at a quarter of its size each way, and the settings, in
// the order of `CRTSettings` below.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

/// The settings, as `CRT.shaderSettings` lays them out.
struct CRTSettings {
    /// The screen's size in pixels: 384 × 272 for a C64's.
    float2 screen;
    /// The display window, where the picture fills in cell by cell.
    float2 windowOrigin;
    float2 windowSize;
    /// The glow's size in its own pixels.
    float2 glowSize;
    /// Device pixels per point.
    float scale;
    /// How far a black and a white line's beam spreads, as the standard
    /// deviation of a Gaussian, in lines.
    float beamMin;
    float beamMax;
    /// How wide the step between neighbouring pixels on a line is, in pixels:
    /// 0 is a hard edge, 1 a smooth slope.
    float edge;
    /// How much of the light the glass scatters into the glow.
    float glow;
    /// How far the glass bulges: how much the picture's corners move in.
    float curvature;
    /// How much darker the corners are than the centre.
    float vignette;
    /// The radius of the tube's corners, as a fraction of its height.
    float corner;
    float brightness;
    /// How many of the display window's 1,000 cells show, while the picture
    /// fills in.
    float revealed;
};

constant int crtSettingCount = 18;

static CRTSettings crtSettings(device const float *values) {
    CRTSettings s;
    s.screen = float2(values[0], values[1]);
    s.windowOrigin = float2(values[2], values[3]);
    s.windowSize = float2(values[4], values[5]);
    s.glowSize = float2(values[6], values[7]);
    s.scale = values[8];
    s.beamMin = values[9];
    s.beamMax = values[10];
    s.edge = values[11];
    s.glow = values[12];
    s.curvature = values[13];
    s.vignette = values[14];
    s.corner = values[15];
    s.brightness = values[16];
    s.revealed = values[17];
    return s;
}

static float crtLinear(float c) {
    return c <= 0.04045f ? c / 12.92f : pow((c + 0.055f) / 1.055f, 2.4f);
}

static float3 crtLinear(float3 c) {
    return float3(crtLinear(c.x), crtLinear(c.y), crtLinear(c.z));
}

static float crtEncoded(float c) {
    return c <= 0.0031308f ? c * 12.92f : 1.055f * pow(c, 1.0f / 2.4f) - 0.055f;
}

static float3 crtEncoded(float3 c) {
    return float3(crtEncoded(c.x), crtEncoded(c.y), crtEncoded(c.z));
}

static float3 crtBlend(float3 a, float3 b, float t) {
    return a + (b - a) * t;
}

/// Whether a pixel shows yet: the border always does, and the display window
/// fills in cell by cell, 40 to a row.
static bool crtRevealed(CRTSettings s, int x, int y) {
    int column = x - int(s.windowOrigin.x);
    int row = y - int(s.windowOrigin.y);
    if (column < 0 || row < 0 || column >= int(s.windowSize.x) || row >= int(s.windowSize.y)) {
        return true;
    }
    int cell = (row / 8) * (int(s.windowSize.x) / 8) + column / 8;
    return float(cell) < s.revealed;
}

/// A pixel's light: black beyond the screen's edges, and where the picture
/// has not filled in yet.
static float3 crtPixel(device const uchar *pixels, CRTSettings s, int x, int y) {
    if (x < 0 || y < 0 || x >= int(s.screen.x) || y >= int(s.screen.y) || !crtRevealed(s, x, y)) {
        return float3(0.0f);
    }
    int index = (y * int(s.screen.x) + x) * 4;
    float3 pixel = float3(float(pixels[index]), float(pixels[index + 1]), float(pixels[index + 2]));
    return crtLinear(pixel / 255.0f);
}

/// A line's light at a point across it, in pixels: each pixel holds its
/// colour, with a step to the next one as wide as `edge`.
static float3 crtLine(device const uchar *pixels, CRTSettings s, int line, float x) {
    float position = x - 0.5f;
    float left = floor(position);
    float t = position - left;
    float halfEdge = max(s.edge, 0.001f) * 0.5f;
    float blend = smoothstep(0.5f - halfEdge, 0.5f + halfEdge, t);
    float3 a = crtPixel(pixels, s, int(left), line);
    float3 b = crtPixel(pixels, s, int(left) + 1, line);
    return crtBlend(a, b, blend);
}

/// The light at a point of the screen, in pixels, from the beams of the four
/// nearest lines. Each beam spreads its line's light over a Gaussian whose
/// width grows with the light, and whose area is always 1. `footprint` is a
/// device pixel's height in lines: a beam is blurred by it, so that the
/// thinnest beams still fall on whole pixels.
static float3 crtBeams(device const uchar *pixels, CRTSettings s, float2 spot, float footprint) {
    float y = spot.y - 0.5f;
    float above = floor(y);
    float3 light = float3(0.0f);
    for (int k = -1; k <= 2; k++) {
        float centre = above + float(k);
        float apart = y - centre;
        float3 colour = crtLine(pixels, s, int(centre), spot.x);
        float3 width = s.beamMin + (s.beamMax - s.beamMin) * colour;
        width = sqrt(width * width + footprint * footprint / 12.0f);
        light += colour * exp(-(apart * apart) / (2.0f * width * width)) / (width * 2.5066283f);
    }
    return light;
}

/// One of the glow's pixels.
static float3 crtGlowPixel(device const float *glow, int width, int x, int y) {
    int index = (y * width + x) * 4;
    return float3(glow[index], glow[index + 1], glow[index + 2]);
}

/// The glow at a point of the screen, from 0 to 1 across and down: the glow's
/// pixels, blended.
static float3 crtGlow(device const float *glow, CRTSettings s, float2 spot) {
    float2 position = spot * s.glowSize - 0.5f;
    float2 base = floor(position);
    float2 t = position - base;
    int width = int(s.glowSize.x);
    int height = int(s.glowSize.y);
    int x0 = clamp(int(base.x), 0, width - 1);
    int x1 = clamp(int(base.x) + 1, 0, width - 1);
    int y0 = clamp(int(base.y), 0, height - 1);
    int y1 = clamp(int(base.y) + 1, 0, height - 1);
    float3 top = crtBlend(crtGlowPixel(glow, width, x0, y0), crtGlowPixel(glow, width, x1, y0), t.x);
    float3 bottom = crtBlend(crtGlowPixel(glow, width, x0, y1), crtGlowPixel(glow, width, x1, y1), t.x);
    return crtBlend(top, bottom, t.y);
}

/// How much of a device pixel lies on the tube, whose corners are rounded:
/// 1 inside, 0 outside, and in between along its edge. The point goes from 0
/// to 1 across and down the screen, which is `size` points.
static float crtCoverage(CRTSettings s, float2 spot, float2 size) {
    float radius = s.corner * size.y;
    float2 fromCentre = fabs(spot - 0.5f) * size;
    float2 beyond = max(fromCentre - (size * 0.5f - radius), float2(0.0f));
    float outside = length(beyond) - radius;
    return clamp(0.5f - outside * s.scale, 0.0f, 1.0f);
}

/// The light of the glass at a point, from 0 to 1 across and down the TV,
/// which is `size` points.
static float3 crtLight(
    device const uchar *pixels, device const float *glow, CRTSettings s, float2 glass, float2 size
) {
    // The glass bulges: towards the corners, a point of the glass shows a
    // point of the screen further out, so the picture's edges curve.
    float2 c = glass * 2.0f - 1.0f;
    float aspect = size.x / size.y;
    float2 bulge = float2(1.0f + s.curvature * c.y * c.y, 1.0f + s.curvature * aspect * c.x * c.x);
    float2 spot = (c * bulge) * 0.5f + 0.5f;
    float coverage = crtCoverage(s, spot, size);
    if (coverage <= 0.0f) {
        return float3(0.0f);
    }
    float2 pixel = spot * s.screen;
    float footprint = s.screen.y / (size.y * s.scale);
    float3 light = crtBeams(pixels, s, pixel, footprint);
    // The glow shows only where the picture has filled in.
    float shown = crtRevealed(s, int(floor(pixel.x)), int(floor(pixel.y))) ? 1.0f : 0.0f;
    light = crtBlend(light, crtGlow(glow, s, spot) * shown, s.glow);
    float vignette = 1.0f - s.vignette * dot(c, c) * 0.5f;
    return max(light * (s.brightness * vignette * coverage), float3(0.0f));
}

/// The CRT layer, as a SwiftUI fill: each pixel's colour, opaque, in sRGB.
[[ stitchable ]] half4 crtScreen(
    float2 position, float4 bounds, device const void *screen, int screenBytes, device const void *glow,
    int glowBytes, device const float *values, int valueCount
) {
    float4 black = float4(0.0f, 0.0f, 0.0f, 1.0f);
    if (valueCount < crtSettingCount || bounds.z <= 0.0f || bounds.w <= 0.0f) {
        return half4(black);
    }
    CRTSettings s = crtSettings(values);
    // Never read beyond the data, if it does not match the settings.
    int screenSize = int(s.screen.x) * int(s.screen.y) * 4;
    int glowSize = int(s.glowSize.x) * int(s.glowSize.y) * 16;
    if (screenBytes < screenSize || glowBytes < glowSize) {
        return half4(black);
    }
    float2 size = float2(bounds.z, bounds.w);
    float2 glass = (position - float2(bounds.x, bounds.y)) / size;
    float3 light = crtLight((device const uchar *)screen, (device const float *)glow, s, glass, size);
    return half4(float4(crtEncoded(clamp(light, float3(0.0f), float3(1.0f))), 1.0f));
}
