shader_type canvas_item;
render_mode blend_add, unshaded;

// The bloom the spec describes (section 15): threshold 1.0, small radius, high
// intensity. Godot's built-in glow works on a coarse mip chain and, measured on
// this machine, adds nothing at all for emitters under about 12 px, which is
// every running light, core and bullet in the game. This pass reads the HDR
// back buffer directly, keeps only what is above the threshold, and blurs it
// with a 9x9 gaussian tap grid spanning +-radius_px. It is drawn additively on
// a layer above the arena and below the HUD.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float threshold = 1.0;
uniform float intensity = 1.0;
uniform float radius_px = 8.0;   // half-extent of the tap grid, in screen px
uniform float sigma_px = 3.2;    // gaussian width, in screen px

void fragment() {
    vec2 px = SCREEN_PIXEL_SIZE;
    float step_px = radius_px / 4.0;
    float inv2s2 = 1.0 / (2.0 * sigma_px * sigma_px);
    vec3 sum = vec3(0.0);
    float wsum = 0.0;
    for (int i = -4; i <= 4; i++) {
        for (int j = -4; j <= 4; j++) {
            vec2 d = vec2(float(i), float(j)) * step_px;
            float w = exp(-dot(d, d) * inv2s2);
            vec3 c = texture(screen_tex, SCREEN_UV + d * px).rgb;
            sum += max(c - vec3(threshold), vec3(0.0)) * w;
            wsum += w;
        }
    }
    COLOR = vec4(sum / wsum * intensity, 1.0);
}
