shader_type canvas_item;
render_mode unshaded;
// Batched CombatFX rings/discs (spec v0.3 §19, P9 perf pass). One quad per
// live effect instance, shaped by `INSTANCE_CUSTOM.x` (0=ring, 1=filled
// disc/fragment) - the same SDF-in-a-MultiMesh pattern `projectile_instances.gdshader`
// uses for bullets, so a 500-effect storm costs one draw call instead of 500
// `canvas.draw_arc` calls. `INSTANCE_CUSTOM.y` is the ring's half-width in
// LOCAL units (the quad is scaled so its unit circle == the effect's current
// world radius, so a constant `RING_WIDTH_PX` in `fx_canvas.gd` becomes a
// radius-dependent local fraction - matching how `canvas.draw_arc`'s constant
// world-space stroke width behaves).

varying vec4 instance_color;
varying vec4 parameters;

void vertex() {
	instance_color = COLOR;
	parameters = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float mode = parameters.x;
	float aa = max(fwidth(r), 0.02);
	float coverage;
	if (mode < 0.5) {
		float half_width = max(parameters.y, aa);
		float dist = abs(r - 1.0);
		coverage = 1.0 - smoothstep(half_width - aa, half_width + aa, dist);
	} else {
		coverage = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
	}
	COLOR = vec4(instance_color.rgb, instance_color.a * coverage);
}
