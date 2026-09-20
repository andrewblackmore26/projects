shader_type canvas_item;
render_mode unshaded;

varying vec4 instance_color;
varying vec4 parameters;

void vertex() {
	instance_color = COLOR;
	parameters = INSTANCE_CUSTOM;
}

// Capsule coverage shared by the plain projectile (kind 0) and the two
// "interior" kinds (2, 3): a solid capsule; zero straight-section length
// produces a circular mine.
float capsule_coverage(vec2 q, float straight) {
	vec2 cap = vec2(max(abs(q.x) * (1.0 + straight) - straight, 0.0), q.y);
	float distance_to_edge = length(cap) - 1.0;
	float aa = max(fwidth(distance_to_edge), 0.025);
	return 1.0 - smoothstep(-aa, aa, distance_to_edge);
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float kind = parameters.y;
	if (kind < 0.5) {
		// Plain projectile: pulse/ricochet/mine, small and unremarkable (spec
		// §19 "small projectiles stay plain").
		float coverage = capsule_coverage(q, parameters.x);
		COLOR = vec4(instance_color.rgb, min(instance_color.a, 1.0) * coverage);
	} else if (kind < 1.5) {
		// Black-hole body, bright rim and dashed reach ring share one instance.
		float radius = length(q) * parameters.w;
		float aa = max(fwidth(radius), 0.6);
		float body = 1.0 - smoothstep(parameters.z - aa, parameters.z + aa, radius);
		float rim = 1.0 - smoothstep(1.1, 1.1 + aa, abs(radius - parameters.z));
		float reach = 1.0 - smoothstep(0.5, 0.5 + aa, abs(radius - (parameters.w - 1.0)));
		float arc_length = (atan(q.y, q.x) + PI) * (parameters.w - 1.0);
		float dash = 1.0 - step(2.0, mod(arc_length, 6.0));
		float reach_alpha = reach * dash * 0.22;
		vec3 rgb = mix(vec3(0.60, 0.65, 0.70), vec3(0.0), body);
		rgb = mix(rgb, instance_color.rgb, rim);
		COLOR = vec4(rgb, max(max(body, rim), reach_alpha));
	} else {
		// Interiors (spec §19: "anything above ~7 px radius gets internal
		// structure... rotation tells the player it's live before it does
		// anything"). Driven by the bullet's own AGE (parameters.w), never a
		// wall clock, so it freezes exactly when the sim pauses and matches
		// exactly what the sim itself advanced. `straight` still shapes the
		// outer capsule; the interior lives in the roughly-circular "head".
		float straight = parameters.x;
		float coverage = capsule_coverage(q, straight);
		vec2 c = vec2(q.x / max(1.0 + straight, 0.001), q.y);
		float r = length(c);
		float age = parameters.w;
		float interior = 0.0;
		vec3 tint = instance_color.rgb;
		if (kind < 2.5) {
			// Rocket: "rotating inner ring and spoke".
			float spin = age * 2.6;
			vec2 spoke_dir = vec2(cos(spin), sin(spin));
			float ring = 1.0 - smoothstep(0.10, 0.20, abs(r - 0.55));
			float along = dot(c, spoke_dir);
			float perp = abs(c.x * spoke_dir.y - c.y * spoke_dir.x);
			float spoke = step(perp, 0.07) * step(0.0, along) * step(along, 0.62);
			float centre = 1.0 - smoothstep(0.14, 0.22, r);
			interior = max(max(ring, spoke), centre * 0.7);
		} else {
			// Seeker: "pulsing halo ring".
			float pulse = 0.5 + 0.5 * sin(age * 6.0);
			float halo_r = 0.45 + 0.18 * pulse;
			interior = 1.0 - smoothstep(0.08, 0.18, abs(r - halo_r));
		}
		interior *= coverage;
		vec3 rgb = mix(tint, vec3(1.6, 1.6, 1.6), interior * 0.75);
		COLOR = vec4(rgb, min(instance_color.a, 1.0) * coverage);
	}
}
