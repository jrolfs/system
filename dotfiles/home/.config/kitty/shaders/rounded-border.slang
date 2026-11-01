// Rounds the corners of a kitty panel and draws a border down its left edge.
//
// A panel is a borderless window, so macOS neither rounds it nor outlines it,
// and kitty has no option for either: window_border_radius draws kitty's own
// split borders inside the window, and does nothing alongside the
// draw_minimal_borders that kitty.conf sets.
//
// The corner is a circle because that is what was measured. A window capture of
// the main kitty with its alpha channel kept fits a circular arc of 32 device
// pixels to within a pixel, against four to six for any superellipse, so this is
// an exact rounded-rectangle distance field rather than the squircle an earlier
// panel used.
//
// The border is the left edge only, as wide as the split line between two
// kitty windows, so the panel reads as one more split of the window beside
// it. Measured, not taken from window_border_width: with draw_minimal_borders
// the line between two windows is both of their borders side by side, 16
// device pixels where the setting says 4pt. The corner clip still applies to
// it, though with only the right-hand corners rounded there is nothing on the
// left to cut it, and it runs straight from top to bottom like a split line.
//
// Only the right-hand corners are rounded because only they are corners of
// anything. The panel's right edge lines up with the main kitty window's, so
// those two corners are its corners; the left edge sits over the middle of
// that window, where a rounded corner would be a notch rather than an edge.
//
// Sizes are in device pixels, the only size a shader is handed. They are set
// in switch-panel.pipeline.

import kitty_custom_shader_types;

static const float RADIUS_PX = 32.0;
static const float BORDER_PX = 16.0;

// Linear RGB, which is what kitty hands a shader. #282828, the split lines'
// active_border_color in gruvbox-material dark soft.
static const float3 BORDER_COLOR = float3(0.0212);
static const float BORDER_ALPHA = 1.0;

// Signed distance from the edge of a rectangle with rounded corners: negative
// inside, positive outside, in the same units as its arguments. The radius
// applies to the right-hand corners only; the left ones are square.
float rounded_rectangle(float2 pixel, float2 size, float radius) {
    radius = pixel.x > size.x * 0.5 ? radius : 0.0;
    float2 q = abs(pixel - size * 0.5) - (size * 0.5 - radius);
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    float2 size = float2(d.viewport_size_pixels);
    float distance = rounded_rectangle(t.pos * size, size, RADIUS_PX);

    // A half-pixel band either side of each edge is what antialiases it rather
    // than cutting it.
    float inside = clamp(0.5 - distance, 0.0, 1.0);
    float border = clamp(BORDER_PX + 0.5 - t.pos.x * size.x, 0.0, 1.0);

    // Premultiplied, like everything at this stage, so the border's colour is
    // scaled by its own alpha before it is laid over the terminal.
    float4 ring = float4(BORDER_COLOR * BORDER_ALPHA, BORDER_ALPHA);
    return lerp(color, ring, border) * inside;
}
