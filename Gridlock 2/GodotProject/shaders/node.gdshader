shader_type canvas_item;
render_mode blend_add, unshaded;

// A node outline is a closed ribbon around the hex: UV.x runs 0..1 around the
// ring, UV.y is across in [-1, 1]. Same HDR rule as the wire shader -- a thin
// crisp core in colours above 1.0, and bloom supplies the thickness.

// No source_color hint (see wire.gdshader): values are written raw so the
// palette and the emission headroom survive to the framebuffer intact.
uniform vec4 ring_color = vec4(0.35, 0.38, 0.44, 1.0);
uniform float intensity = 1.0;
uniform float base_intensity = 1.0;
uniform float core_uv = 0.4;

// Overcharge: brightness ramps with hold progress and a pulse quickens with it
// (spec section 8.6). The opponent is meant to see this coming.
uniform float pulse_phase = 0.0;
uniform float pulse_amount = 0.0;

// Burst armed: the outline flares and fractures.
uniform float armed = 0.0;

// Disabled: a slow dim sweep travels around the ring so it reads as "off"
// rather than merely dark.
uniform float sweep = -1.0;

// Capture: a brief flash in the capturing colour.
uniform float flash = 0.0;

void fragment() {
    float around = UV.x;
    float across = abs(UV.y);

    float core = 1.0 - smoothstep(0.0, core_uv, across);
    float body = (1.0 - smoothstep(core_uv, 1.0, across)) * 0.25;
    float shape = core + body;

    float level = intensity;
    level *= 1.0 + pulse_amount * 0.55 * sin(pulse_phase);

    // Fracture the ring into arc segments once a burst is armed.
    float fracture = 1.0 - armed * 0.75 * step(0.5, fract(around * 9.0));
    level *= fracture;

    if (sweep >= 0.0) {
        float d = abs(fract(around - sweep + 0.5) - 0.5);
        level *= 0.35 + 0.65 * smoothstep(0.0, 0.22, d);
    }

    vec3 rgb = ring_color.rgb * shape * level;
    rgb += ring_color.rgb * shape * flash * 4.0;
    rgb *= base_intensity;

    COLOR = vec4(rgb, 1.0);
}
