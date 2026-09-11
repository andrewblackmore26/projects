shader_type canvas_item;
render_mode blend_mix, unshaded;

// Bullets (spec 6, 15): SOLID, fast, a small version of the element's base
// shape, drawn in batches through a MultiMesh. Everything per instance rides in
// INSTANCE_CUSTOM as plain floats (never the instance colour, which is treated
// as a colour and converted):
//   x = shape (0 circle, 1 triangle, 2 diamond, 3 crescent)
//   y = palette role index
// The quad spans -1..1 in UV space scaled by the instance transform; forward is
// -Y, rotated onto the bullet's velocity by the transform.

uniform vec4 stroke_colors[8];
uniform vec4 light_colors[8];
uniform float emission = 1.8;   // bullets sit above the bloom threshold

varying vec4 v_custom;

void vertex() {
    v_custom = INSTANCE_CUSTOM;
}

float sd_triangle(vec2 p) {
    // Isosceles, apex forward (-Y), base at +0.7.
    vec2 a = vec2(0.0, -0.9), b = vec2(0.72, 0.7), c = vec2(-0.72, 0.7);
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
    float d = length(p) - 0.8;
    if (shape == 1) {
        d = sd_triangle(p);
    } else if (shape == 2) {
        vec2 q = abs(p);
        d = (q.x * 0.95 + q.y * 0.5 - 0.5 * 0.95) / length(vec2(0.95, 0.5));
    } else if (shape == 3) {
        d = max(length(p) - 0.85, -(length(p - vec2(0.0, -0.5)) - 0.62));
    }
    return d;
}

void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    int shape = int(round(v_custom.x));
    int role = int(round(v_custom.y));
    float d = sd_shape(shape, p);
    float aa = max(fwidth(d), 1e-4);
    float alpha = 1.0 - smoothstep(-aa, aa, d);
    // A solid body in the stroke colour with a paler centre, all above the threshold.
    float centre = 1.0 - smoothstep(-0.55, -0.2, d);
    vec3 col = mix(stroke_colors[role].rgb, light_colors[role].rgb, centre) * emission;
    COLOR = vec4(col, alpha);
}
