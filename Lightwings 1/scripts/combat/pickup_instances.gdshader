shader_type canvas_item;
render_mode unshaded;
// Batched light pickups (spec v0.3 §10). One quad per pickup, replacing two immediate
// `canvas.draw_arc` calls each (measured ~17 ms of frame time at the 400-pickup cap).
//
// A pickup must read as a HOLLOW circle with a running light, never as a solid bullet (§10's shape
// rule), so mode 1 draws a rim plus one lit segment covering 13% of the circumference (§18's
// running-light constant) and mode 0 draws the opaque black fill a void pickup needs behind its rim.
//
// INSTANCE_CUSTOM: x = mode (0 fill, 1 rim+light), y = lit-segment start as a fraction of the
// circumference, z = rim half-width in local units (the quad is scaled so the unit circle is the
// pickup's radius, so a constant screen-space width becomes a radius-dependent fraction),
// w = emission for the lit segment, which must exceed 1.0 so the bloom pass picks it up.

const float LIGHT_FRACTION = 0.13;

varying vec4 instance_color;
varying vec4 parameters;

void vertex() {
	instance_color = COLOR;
	parameters = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float aa = max(fwidth(r), 0.02);
	if (parameters.x < 0.5) {
		// Void's opaque black disc, sitting behind the rim.
		float fill = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
		COLOR = vec4(instance_color.rgb, instance_color.a * fill);
	} else {
		float half_width = max(parameters.z, aa);
		float coverage = 1.0 - smoothstep(half_width - aa, half_width + aa, abs(r - 1.0));
		// Angle around the rim as a 0..1 fraction, measured the same way draw_arc swept it.
		float around = fract(atan(q.y, q.x) / TAU + 1.0);
		float from_start = fract(around - parameters.y);
		float lit = step(from_start, LIGHT_FRACTION);
		vec3 tint = mix(instance_color.rgb, vec3(1.0) * max(parameters.w, 1.0), lit);
		COLOR = vec4(tint, instance_color.a * coverage);
	}
}
