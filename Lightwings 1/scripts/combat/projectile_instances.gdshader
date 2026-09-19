shader_type canvas_item;
render_mode unshaded;

varying vec4 instance_color;
varying vec4 parameters;

void vertex() {
	instance_color = COLOR;
	parameters = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	if (parameters.y < 0.5) {
		// A solid capsule; zero straight-section length produces a circular mine.
		float straight = parameters.x;
		vec2 cap = vec2(max(abs(q.x) * (1.0 + straight) - straight, 0.0), q.y);
		float distance_to_edge = length(cap) - 1.0;
		float aa = max(fwidth(distance_to_edge), 0.025);
		float coverage = 1.0 - smoothstep(-aa, aa, distance_to_edge);
		COLOR = vec4(instance_color.rgb, min(instance_color.a, 1.0) * coverage);
	} else {
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
	}
}
