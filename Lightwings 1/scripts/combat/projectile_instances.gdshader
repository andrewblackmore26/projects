shader_type canvas_item;
render_mode unshaded;
varying vec4 instance_color;
varying vec4 parameters; // body radius, kind + friendly bit, quad extent, simulation age

void vertex() {
	instance_color = COLOR;
	parameters = INSTANCE_CUSTOM;
}

float ring(float distance, float radius, float width, float aa) {
	return 1.0 - smoothstep(width * 0.5 - aa, width * 0.5 + aa, abs(distance - radius));
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * parameters.z;
	float radius = length(p);
	float aa = max(fwidth(radius) * 0.5, 0.35);
	float kind = mod(parameters.y, 8.0);
	bool friendly = parameters.y > 7.5;
	float body_r = parameters.x;
	float body = 1.0 - smoothstep(body_r - aa, body_r + aa, radius);
	float outline = ring(radius, body_r, 1.7, aa);
	vec3 dark_fill = vec3(0.003347, 0.005605, 0.009721); // sRGB #0b1119
	vec3 light = vec3(0.71569, 0.91310, 1.0);
	if (kind > 1.5 && kind < 2.5) light = vec3(1.0, 0.56471, 0.46208);
	if (kind > 2.5 && kind < 3.5) light = vec3(0.77582, 0.67244, 1.0);
	if (kind > 3.5) light = vec3(1.0, 0.89627, 0.50888);
	vec3 rgb = mix(dark_fill, instance_color.rgb, outline);
	float alpha = max(body, outline);
	if (kind > 0.5 && kind < 1.5) {
		float guide = ring(radius, parameters.z - 1.0, 1.0, aa);
		float arc = (atan(p.y, p.x) + PI) * (parameters.z - 1.0);
		guide *= (1.0 - step(2.0, mod(arc, 6.0))) * 0.22;
		rgb = mix(instance_color.rgb, rgb, max(body, outline));
		alpha = max(alpha, guide);
	} else if (kind > 1.5 && kind < 2.5) {
		float spin = parameters.w * 7.8;
		vec2 direction = vec2(cos(spin), sin(spin));
		float along = dot(p, direction);
		float across = abs(p.x * direction.y - p.y * direction.x);
		float diameter = (1.0 - smoothstep(0.65 - aa, 0.65 + aa, across)) * (1.0 - smoothstep(body_r * 0.5 - aa, body_r * 0.5 + aa, abs(along)));
		float inner = max(ring(radius, body_r * 0.5, 1.5, aa), diameter) * 0.95;
		rgb = mix(rgb, light, inner);
	} else if (kind > 2.5 && kind < 3.5) {
		float halo_r = body_r + 2.5 + sin(parameters.w * 13.0) * 1.2;
		float halo = ring(radius, halo_r, 1.5, aa) * 0.5;
		rgb = mix(rgb, light, halo / max(max(alpha, halo), 0.001));
		alpha = max(alpha, halo);
	}
	if (friendly) {
		float pip = 1.0 - smoothstep(1.05 - aa, 1.05 + aa, radius);
		rgb = mix(rgb, vec3(0.15896, 0.65141, 1.0), pip);
		alpha = max(alpha, pip);
	}
	COLOR = vec4(rgb, alpha * instance_color.a);
}
