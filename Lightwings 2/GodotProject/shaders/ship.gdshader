shader_type canvas_item;
render_mode blend_mix, unshaded;

// One shader for every lightship (spec 11). Per-vertex data arrives in the
// CUSTOM0 float attribute and UV, packed by Core's ShipMeshBuilder:
//   CUSTOM0.x  palette role index
//   CUSTOM0.y  flags: kind (3 bits) | period index << 3 | phase index << 4
//   CUSTOM0.z  perimeter of the part in screen px
//   UV.x       perimeter fraction along the stroke (screen px for dashed rings), 0 for fills
//   UV.y       across the ribbon, -1..1
// kind: 0 fill, 1 stroke with running light, 2 dashed reference ring, 3 tether
// with running light, 4 core, 5 stroke without light (inner ring loops).
//
// None of the colour uniforms carry a source_color hint: that hint converts the
// value from sRGB on the way in, which is the very transfer the hdr_2d pipeline
// already applies, and the palette would no longer measure as written.

uniform vec4 stroke_colors[8];
uniform vec4 fill_colors[8];
uniform vec4 light_colors[8];

uniform float sim_time = 0.0;        // simulation seconds, never TIME: captures must be reproducible
uniform float light_fraction = 0.13; // spec 11.5: 13 % of the perimeter is lit
uniform float light_emission = 1.8;  // pale tint x 1.8 sits above the glow threshold of 1.0
uniform float stroke_level = 0.92;   // base strokes sit just under the threshold
uniform float stroke_core = 0.577;   // 1.5 px of the 2.6 px ribbon is the base stroke
uniform float tether_core = 0.77;    // 2.0 px of the 2.6 px ribbon for tethers
uniform float cap_px = 1.3;          // ribbon half-width in px; also the round-cap radius of the lit segment
uniform float edge_aa = 0.45;        // px of anti-aliasing on the stroke edges
uniform float dash_on = 2.0;         // reference rings: 2 px on, 4 px off
uniform float dash_period = 6.0;
uniform float ring_alpha = 0.5;
uniform float dim = 1.0;
uniform float debug_flat = 0.0;      // diagnostic: > 0 replaces the output with a flat value

varying vec4 v_pack;
varying vec2 v_uv;

void vertex() {
    v_pack = CUSTOM0;
    v_uv = UV;
}

void fragment() {
    int role = int(round(v_pack.x));
    int flags = int(round(v_pack.y));
    int kind = flags & 7;
    float period = ((flags >> 3) & 1) == 1 ? 1.6 : 2.0;
    int ph = (flags >> 4) & 3;
    float phase = ph == 1 ? -0.7 : (ph == 2 ? -1.3 : 0.0);
    float perim_px = v_pack.z;

    vec3 stroke = stroke_colors[role].rgb;
    vec3 fill = fill_colors[role].rgb;
    vec3 light = light_colors[role].rgb;
    float across = abs(v_uv.y);
    float aa = edge_aa / cap_px;

    vec4 outc = vec4(fill, 1.0);   // kind 0: the dark fill

    if (kind == 4) {
        // The core: a solid disc above the threshold so it glows.
        outc = vec4(stroke * light_emission, 1.0);
    } else if (kind == 2) {
        // Dashed reference ring, 1 px, UV.x is already in screen px.
        float on = 1.0 - step(dash_on, mod(v_uv.x, dash_period));
        outc = vec4(stroke * stroke_level, ring_alpha * on);
    } else if (kind == 1 || kind == 3 || kind == 5) {
        float core_w = (kind == 3) ? tether_core : stroke_core;
        float base = 1.0 - smoothstep(core_w - aa, core_w + aa, across);
        float lit = 0.0;
        if (kind != 5) {
            // The running light: a segment of light_fraction of the perimeter,
            // starting at offset and travelling one lap per period, with round
            // caps of radius cap_px at both ends (perimeter known in px).
            float offset = fract((sim_time + phase) / period);
            float d = fract(v_uv.x - offset);              // 0 at the head of the segment
            float half_len = light_fraction * 0.5;
            float cd = abs(d - half_len);
            cd = min(cd, 1.0 - cd);                        // wrap around the loop
            float end_px = max(cd - half_len, 0.0) * perim_px;
            float cross_px = across * cap_px;
            float dist = sqrt(end_px * end_px + cross_px * cross_px);
            lit = 1.0 - smoothstep(cap_px - edge_aa, cap_px + edge_aa, dist);
        }
        vec3 rgb = mix(stroke * stroke_level, light * light_emission, lit);
        outc = vec4(rgb, max(base, lit));
    }

    // No `return` inside fragment(): a compile error renders the mesh black,
    // which looks exactly like "the change had no effect".
    if (debug_flat > 0.0) {
        outc = vec4(vec3(debug_flat), 1.0);
    }
    COLOR = vec4(outc.rgb * dim, outc.a);
}
