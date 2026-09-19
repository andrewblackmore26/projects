shader_type canvas_item;
render_mode unshaded;

uniform float visual_time = 0.0;
uniform float body_scale = 1.0;
uniform float canvas_scale = 1.0;
uniform vec4 light_parameters[128]; // period, phase, perimeter, style
uniform vec2 part_centers[128];
uniform vec4 part_geometry[128];
uniform int motion_signature = 0;
uniform vec4 part_offsets[128]; // translation xy, visibility z
uniform vec4 core_color : source_color = vec4(1.0);
uniform float core_radius = 3.0;
uniform bool show_core = true;
uniform bool evolution_ready = false;

varying vec4 base_color;
varying vec3 running_color;
varying float primitive_kind;
varying float part_visible;
varying vec4 light_data;
varying float perimeter_pixels;
varying float path_pixels;

float inward(int part) {
	return motion_signature == 3 ? 1.0 - 0.06 * fract(visual_time / 2.0) : 1.0;
}
float rim(int part, vec2 direction) {
	vec4 geometry = part_geometry[part];
	float c = cos(-geometry.z);
	float s = sin(-geometry.z);
	vec2 local = mat2(vec2(c,s),vec2(-s,c)) * direction;
	return 1.0 / max(length(local / max(geometry.xy, vec2(0.001))), 0.001);
}
void vertex() {
	vec2 original_vertex = VERTEX;
	int part = int(CUSTOM0.z + 0.5);
	primitive_kind = CUSTOM0.w;
	base_color = COLOR;
	running_color = CUSTOM1.rgb;
	part_visible = part_offsets[part].z;
	light_data = light_parameters[part];
	float perimeter = light_data.z;
	vec2 position = VERTEX + part_offsets[part].xy + part_centers[part] * (inward(part) - 1.0);
	vec2 normal = CUSTOM0.xy;
	float path = UV.x;
	if (primitive_kind > 0.5) {
		int packed = int(CUSTOM1.w + 0.5);
		int from_part = packed % 128;
		int to_part = packed / 128;
		vec2 from_position = part_centers[from_part] * inward(from_part) + part_offsets[from_part].xy;
		vec2 to_position = part_centers[to_part] * inward(to_part) + part_offsets[to_part].xy;
		float amount = UV.x / max(perimeter, 0.0001);
		vec2 direction = to_position - from_position;
				float center_distance = length(direction);
		vec2 unit_direction = direction / max(center_distance, 0.001);
		float from_radius = rim(from_part, unit_direction);
		float to_radius = rim(to_part, -unit_direction);
		from_position += unit_direction * from_radius;
		to_position -= unit_direction * to_radius;
		if (center_distance <= from_radius + to_radius) part_visible = 0.0;
		direction = to_position - from_position;
		perimeter = length(direction);
		position = mix(from_position, to_position, amount);
		normal = vec2(-direction.y, direction.x) / max(perimeter, 0.0001) * UV.y;
		path = amount * perimeter;
		part_visible *= part_offsets[from_part].z * part_offsets[to_part].z;
	}
	perimeter_pixels = perimeter * body_scale * canvas_scale;
	path_pixels = path * body_scale * canvas_scale;
	VERTEX = position * body_scale + normal * 1.8 / canvas_scale;
	if (primitive_kind < -1.5) {
		VERTEX = original_vertex / canvas_scale;
		part_visible = show_core ? 1.0 : 0.0;
	}
}

void fragment() {
	if (primitive_kind < -1.5) {
		float radius = length(UV) * (core_radius + 0.75);
		float alpha = 1.0 - smoothstep(core_radius - 0.5, core_radius + 0.5, radius);
		float ready_pulse = evolution_ready ? 1.0 + 0.10 * (0.5 - 0.5 * cos(visual_time * 3.141592)) : 1.0;
		COLOR = vec4(core_color.rgb * 1.8 * ready_pulse, alpha * part_visible);
	} else if (primitive_kind < -0.5) {
		COLOR = vec4(base_color.rgb, base_color.a * part_visible);
	} else {
		float across = abs(UV.y) * 1.8;
		float half_width = (light_data.w > 1.5 && light_data.w < 2.5) ? 1.0 : 0.75;
		float opacity = 1.0;
		if (light_data.w > 0.5 && light_data.w < 1.5) {
			half_width = 0.5;
			opacity = (mod(path_pixels, 6.0) < 2.0 ? 0.5 : 0.0);
		}
		float outline_alpha = (1.0 - smoothstep(half_width - 0.45, half_width + 0.45, across)) * opacity;
		float perimeter = max(perimeter_pixels, 0.001);
				float cycles = (visual_time + light_data.y) / light_data.x;
		if (motion_signature == 1) cycles += 0.025 * sin(cycles * 6.283185 * 5.0);
		if (motion_signature == 2) cycles = floor(cycles * 12.0) / 12.0;
		if (motion_signature == 5 && light_data.w > 2.5 && mod(abs(light_data.y * 10.0), 2.0) > 0.5) cycles *= -1.0;
		float phase = fract(cycles) * perimeter;
		float half_segment = perimeter * 0.065;
		float centered = mod(path_pixels - phase - half_segment + perimeter * 0.5, perimeter) - perimeter * 0.5;
		float outside_segment = max(abs(centered) - half_segment, 0.0);
		float capsule_distance = length(vec2(outside_segment, across));
		float light_alpha = 1.0 - smoothstep(0.85, 1.75, capsule_distance);
		float alpha = max(outline_alpha, light_alpha);
		vec3 rgb = mix(base_color.rgb * 0.96, running_color, light_alpha);
		COLOR = vec4(rgb, alpha * part_visible);
	}
}



