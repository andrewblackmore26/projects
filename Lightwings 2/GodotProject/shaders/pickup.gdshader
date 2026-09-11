shader_type canvas_item;
render_mode blend_mix, unshaded;

// Light pickups (spec 6): HOLLOW, slow, a small version of the element's base
// shape with a running light travelling around its outline. The rule that
// separates them from bullets at a glance: bullets are solid and fast,
// pickups are hollow and slow.
//   INSTANCE_CUSTOM.x = shape (0 circle/blob, 1 triangle, 2 diamond, 3 crescent)
//   INSTANCE_CUSTOM.y = palette role index
//   INSTANCE_CUSTOM.z = light period index (0 = 2.0 s, 1 = 1.6 s)
//   INSTANCE_CUSTOM.w = light phase index (0, 1, 2 = 0, -0.7, -1.3 s)

uniform vec4 stroke_colors[8];
uniform vec4 light_colors[8];
uniform float sim_time = 0.0;
uniform float stroke_level = 0.92;
uniform float light_emission = 1.8;
uniform float light_fraction = 0.13;
uniform float stroke_half_px = 0.75;   // 1.5 px base stroke
uniform float light_half_px = 1.3;     // 2.6 px running light

varying vec4 v_custom;

void vertex() {
    v_custom = INSTANCE_CUSTOM;
}

float sd_triangle(vec2 p) {
    vec2 a = vec2(0.0, -0.85), b = vec2(0.75, 0.65), c = vec2(-0.75, 0.65);
    vec2 e0 = b - a, e1 = c - b, e2 = a - c;
    vec2 v0 = p - a, v1 = p - b, v2 = p - c;
    vec2 pq0 = v0 - e0 * clamp(dot(v0, e0) / dot(e0, e0), 0.0, 1.0);
    vec2 pq1 = v1 - e1 * clamp(dot(v1, e1) / dot(e1, e1), 0.0, 1.0);
    vec2 pq2 = v2 - e2 * clamp(dot(v2, e2) / dot(e2, e2), 0.0, 1.0);
    float s = sign(e0.x * e2.y - e0.y * e2.x);
    vec2 d = min(min(vec2(dot(pq0, pq0), s * (v0.x * e0.y - v0.y * e0.x)),
                     vec2(dot(pq1, pq1), s * (v1.x * e1.y - v1.y * e1.x))),
                     vec2(dot(pq2, pq2), s * (v2.x * e2.y - v2.y * e2.x)));
    return -sqrt(d.x) * sign(d.y);
}

float sd_shape(int shape, vec2 p) {
    float d = length(p) - 0.75;
    if (shape == 1) {
        d = sd_triangle(p);
    } else if (shape == 2) {
        vec2 q = abs(p);
        d = (q.x * 0.9 + q.y * 0.55 - 0.55 * 0.9) / length(vec2(0.9, 0.55));
    } else if (shape == 3) {
        d = max(length(p) - 0.8, -(length(p - vec2(0.0, -0.45)) - 0.6));
    }
    return d;
}

void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    int shape = int(round(v_custom.x));
    int role = int(round(v_custom.y));
    float period = int(round(v_custom.z)) == 1 ? 1.6 : 2.0;
    int ph = int(round(v_custom.w));
    float phase = ph == 1 ? -0.7 : (ph == 2 ? -1.3 : 0.0);

    float d = sd_shape(shape, p);
    // Quad units per screen pixel, so the stroke is constant in screen space.
    float upx = max(length(vec2(dFdx(p.x), dFdy(p.x))), 1e-4);
    float dist_px = abs(d) / upx;
    float base = 1.0 - smoothstep(stroke_half_px - 0.4, stroke_half_px + 0.4, dist_px);

    // Running light by angle, clockwise from forward.
    float ang = fract(atan(p.x, -p.y) / 6.2831853);
    float offset = fract((sim_time + phase) / period);
    float in_seg = step(fract(ang - offset), light_fraction);
    float lit = in_seg * (1.0 - smoothstep(light_half_px - 0.4, light_half_px + 0.4, dist_px));

    vec3 rgb = mix(stroke_colors[role].rgb * stroke_level, light_colors[role].rgb * light_emission, lit);
    COLOR = vec4(rgb, max(base, lit));
}
