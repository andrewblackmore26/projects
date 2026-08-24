shader_type canvas_item;
render_mode blend_add, unshaded;

// A wire is a thin ribbon mesh: UV.x is the wire parameter t (0 at node A,
// 1 at node B), UV.y is the across-coordinate in [-1, 1]. Everything that
// moves -- beams, the contest front -- is a UNIFORM, never a moved sprite
// (spec section 8.4), so the whole board is a handful of draw calls and the
// motion is exact at any framerate.
//
// The colours written here have components ABOVE 1.0 on purpose: the crisp
// core is what the glow pass blooms (spec section 8.1). Never widen the core
// to fake a glow.

// None of these carry a source_color hint: that hint makes Godot convert the
// value from sRGB on the way in, which silently rewrites both the palette and
// the emission headroom the bloom threshold is calibrated against. Values are
// written raw and land on screen unchanged, so they can be measured.
uniform vec4 owner_color_a = vec4(0.35, 0.38, 0.44, 1.0);
uniform vec4 owner_color_b = vec4(0.35, 0.38, 0.44, 1.0);

// Where the A/B colour split sits: the contest contact point when one is
// active, otherwise the midpoint.
uniform float boundary_t = 0.5;

// Master dimmer, used by tap-to-inspect (spec section 7.1).
uniform float base_intensity = 1.0;

// Half-width of the crisp core as a fraction of the ribbon half-width, so the
// core stays 1-2 px however wide the ribbon is drawn.
uniform float core_uv = 0.35;

uniform float contest_active = 0.0;
uniform vec4 contest_color = vec4(6.0, 6.0, 6.0, 1.0);
// Grows with min(powerPlayer, powerAi): a heavy grind burns brighter.
uniform float contest_heat = 1.0;

const int MAX_PULSES = 8;
uniform int pulse_count = 0;
uniform float pulse_pos[MAX_PULSES];
uniform float pulse_size[MAX_PULSES];
uniform vec4 pulse_color[MAX_PULSES];

void fragment() {
    float t = UV.x;
    float across = abs(UV.y);

    // Crisp core plus a soft body. The body is what reads as a wire at rest;
    // the core is what the bloom threshold catches.
    float core = 1.0 - smoothstep(0.0, core_uv, across);
    float body = (1.0 - smoothstep(core_uv, 1.0, across)) * 0.22;

    vec3 base = mix(owner_color_a.rgb, owner_color_b.rgb, step(boundary_t, t));
    vec3 rgb = base * (core + body);

    // Travelling charge: a bright bead on the wire, brightest at its centre.
    for (int i = 0; i < MAX_PULSES; i++) {
        if (i < pulse_count) {
            float d = abs(t - pulse_pos[i]);
            float falloff = exp(-(d * d) / max(pulse_size[i] * pulse_size[i], 1e-6));
            rgb += pulse_color[i].rgb * falloff * (core + body * 2.0);
        }
    }

    // The contest contact point: the brightest thing on the board, with sparks
    // added by ContestView on top (spec section 8.5).
    float dc = abs(t - boundary_t);
    float hot = exp(-(dc * dc) / max(0.0006 * contest_heat, 1e-6));
    rgb += contest_color.rgb * hot * contest_active * (core + body * 3.0);

    rgb *= base_intensity;

    // Godot's shading language forbids `return` inside fragment(): branch to a
    // single write at the end instead (a compile error otherwise renders the
    // mesh black, which looks exactly like "the change had no effect").
    COLOR = vec4(rgb, 1.0);
}
