shader_type canvas_item;
render_mode unshaded;

uniform float visual_time = 0.0;
uniform float body_scale = 1.0;
uniform float canvas_scale = 1.0;
uniform vec4 light_parameters[128]; // period, phase, perimeter, style (circles only)
uniform vec2 part_centers[128];     // rest position (circles only)
uniform vec4 part_geometry[128];    // radius, radius, 0, 0 (circles only)
uniform int motion_signature = 0;
uniform vec4 part_offsets[128]; // xy translation, z radius scale (0 = hidden), w rim flare (reserved, P8)
uniform vec4 core_color : source_color = vec4(1.0);
uniform float core_radius = 3.0;
// Ship design spec 9.5: radius = 5 * (1 + sin(t * 4.0) * 0.22), the fleet's one steady heartbeat.
// core_quad is the baked quad's half-extent; 0 means the v0.3 value, core_radius + 0.75.
uniform float core_pulse = 0.0;
uniform float core_pulse_freq = 4.0;
uniform float core_quad = 0.0;
uniform bool show_core = true;
uniform bool evolution_ready = false;
uniform float stroke_width = 1.5;
uniform float connector_width = 2.0;
uniform float connector_opacity = 0.85;
uniform float light_width = 2.6;
uniform float light_fraction = 0.13;
uniform float guide_width = 1.0;
uniform float guide_opacity = 0.28;
uniform float guide_dash = 2.0;
uniform float guide_period = 7.0;
// M12, render only: the evolved hull assembles core-out. At assembly_t 1 (the default) every
// circle is at full size, so nothing else changes; below 1 a circle's radius and its distance from
// the core scale by smoothstep of how far the wavefront (assembly_t, widened by assembly_band) has
// passed its own reach d / assembly_extent (reach = rest distance + radius; the extent is the
// hull's largest reach). Lines follow their end circles.
uniform float assembly_t = 1.0;
uniform float assembly_extent = 1.0;
uniform float assembly_band = 0.35;

varying vec4 base_color;
varying vec3 running_color;
varying float primitive_kind;
varying float part_visible;
varying vec4 light_data;
varying float perimeter_pixels;
varying float path_pixels;
varying float flare_amount; // P8 target feedback: part_offsets[part].w on a circle rim, 0 on lines/core

float assembly(int part) {
	if (assembly_t >= 1.0) return 1.0;
	// A circle's reach (centre distance plus radius), so a wide ring round the core comes late.
	float d = clamp((length(part_centers[part]) + part_geometry[part].x) / max(assembly_extent, 0.001), 0.0, 1.0);
	return smoothstep(0.0, 1.0, clamp((assembly_t * (1.0 + assembly_band) - d) / assembly_band, 0.0, 1.0));
}

// A circle's rest centre, drawn in toward the core while it assembles.
vec2 assembled_center(int part) {
	return part_centers[part] * mix(0.55, 1.0, assembly(part));
}

float rim(int part, vec2 direction) {
	vec4 geometry = part_geometry[part];
	float scale = max(part_offsets[part].z * assembly(part), 0.0);
	return 1.0 / max(length(direction / max(geometry.xy * scale, vec2(0.001))), 0.001);
}

void vertex() {
	vec2 original_vertex = VERTEX;
	primitive_kind = CUSTOM0.w;
	base_color = COLOR;
	running_color = CUSTOM1.rgb;
	vec2 position;
	vec2 normal;
	flare_amount = 0.0;
	if (primitive_kind > 0.5) {
		// Line: period/phase/authored-perimeter travel with the vertex; final
		// position comes entirely from the two endpoint circles below.
		light_data = vec4(CUSTOM0.x, CUSTOM0.y, CUSTOM0.z, 2.0);
		part_visible = 1.0;
		position = VERTEX;
		normal = vec2(0.0);
	} else {
		int part = int(CUSTOM0.z + 0.5);
		light_data = light_parameters[part];
		float scale = part_offsets[part].z * assembly(part);
		vec2 local = VERTEX - part_centers[part];
		position = assembled_center(part) + local * max(scale, 0.0) + part_offsets[part].xy;
		part_visible = scale > 0.0001 ? 1.0 : 0.0;
		normal = CUSTOM0.xy;
		flare_amount = clamp(part_offsets[part].w, 0.0, 1.0);
	}
	float path = UV.x;
	float perimeter = light_data.z;
	if (primitive_kind > 0.5) {
		int packed = int(CUSTOM1.w + 0.5);
		int from_part = packed % 128;
		int to_part = packed / 128;
		vec2 from_position = assembled_center(from_part) + part_offsets[from_part].xy;
		vec2 to_position = assembled_center(to_part) + part_offsets[to_part].xy;
		float amount = UV.x / max(perimeter, 0.0001);
		vec2 direction = to_position - from_position;
		float center_distance = length(direction);
		vec2 unit_direction = direction / max(center_distance, 0.001);
		// Kind 2 (ship design spec): a set-piece line starts at its hub's CENTRE, not its rim.
		float from_radius = primitive_kind > 1.5 ? 0.0 : rim(from_part, unit_direction);
		float to_radius = rim(to_part, -unit_direction);
		from_position += unit_direction * from_radius;
		to_position -= unit_direction * to_radius;
		if (center_distance <= from_radius + to_radius) part_visible = 0.0;
		direction = to_position - from_position;
		perimeter = length(direction);
		position = mix(from_position, to_position, amount);
		normal = vec2(-direction.y, direction.x) / max(perimeter, 0.0001) * UV.y;
		path = amount * perimeter;
		float from_visible = part_offsets[from_part].z * assembly(from_part) > 0.0001 ? 1.0 : 0.0;
		float to_visible = part_offsets[to_part].z * assembly(to_part) > 0.0001 ? 1.0 : 0.0;
		part_visible *= from_visible * to_visible;
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
		// P8 target feedback: the player's ONLY hitbox is the core (spec §16),
		// so a player hit (and an enemy core hit) must flare THIS branch, not
		// just the rim-quad branch below - `flare_amount` was already computed
		// in vertex() from the same `part_offsets[part].w` (the core's own
		// mesh entry is `part` 0, same as every other circle).
		float extent = core_quad > 0.0 ? core_quad : core_radius + 0.75;
		float pulsed = core_radius * (1.0 + core_pulse * sin(visual_time * core_pulse_freq));
		float radius = length(UV) * (extent + flare_amount * 1.5);
		float alpha = 1.0 - smoothstep(pulsed - 0.5, pulsed + 0.5 + flare_amount * 1.5, radius);
		float ready_pulse = evolution_ready ? 1.0 + 0.10 * (0.5 - 0.5 * cos(visual_time * 3.141592)) : 1.0;
		vec3 core_rgb = core_color.rgb * 1.15 * ready_pulse + flare_amount * vec3(1.6, 1.55, 1.5);
		// M12 assembly: the core ignites first and burns hot while the hull builds around it.
		core_rgb += (1.0 - clamp(assembly_t, 0.0, 1.0)) * vec3(1.4, 1.45, 1.6);
		alpha *= smoothstep(0.0, 0.08, assembly_t);
		COLOR = vec4(core_rgb, alpha * part_visible);
	} else if (primitive_kind < -0.5) {
		COLOR = vec4(base_color.rgb, base_color.a * part_visible);
	} else {
		float across = abs(UV.y) * 1.8;
		float half_width = (primitive_kind > 0.5 ? connector_width : stroke_width) * 0.5;
		float opacity = primitive_kind > 0.5 ? connector_opacity : 1.0;
		bool guide = (light_data.w > 0.5 && light_data.w < 1.5) || light_data.w > 4.5;
		if (light_data.w > 0.5 && light_data.w < 1.5) {
			half_width = guide_width * 0.5;
			opacity = (mod(path_pixels, guide_period) < guide_dash ? guide_opacity : 0.0);
		}
		// Passive markings share the body stroke. Style 5 is a subordinate orbit guide.
		if (light_data.w > 4.5) {
			half_width = guide_width * 0.5;
			opacity = (mod(path_pixels, guide_period) < guide_dash ? guide_opacity : 0.0);
		}
		float outline_alpha = (1.0 - smoothstep(half_width - 0.45, half_width + 0.45, across)) * opacity;
		float alpha = outline_alpha;
		vec3 rgb = base_color.rgb;
		// A rounded arc runs around each physical or integrated circular rim. The
		// arc is measured along the circumference, independently of orbital motion.
		if (primitive_kind < 0.5 && !guide && light_fraction > 0.0) {
			float phase = fract((visual_time + light_data.y) / max(light_data.x, 0.05));
			float progress = path_pixels / max(perimeter_pixels, 0.001);
			float relative = fract(progress - phase - light_fraction * 0.5 + 0.5) - 0.5;
			float along = max(0.0, (abs(relative) - light_fraction * 0.5) * perimeter_pixels);
			float arc = 1.0 - smoothstep(light_width * 0.5 - 0.45, light_width * 0.5 + 0.45, length(vec2(along, across)));
			rgb = mix(rgb, running_color, arc);
			alpha = max(alpha, arc);
		}
		// P8 target feedback (spec §19): "flare the target circle's own rim" -
		// a hit brightens and widens the rim itself rather than a separate ring
		// drawn in front of it. `flare_amount` decays to 0 over 0.25s (combat_world.gd).
		rgb += flare_amount * vec3(1.6, 1.55, 1.5);
		float flare_alpha = max(outline_alpha, 1.0 - smoothstep(half_width + 0.6, half_width + 2.2, across)) * flare_amount;
		alpha = max(alpha, flare_alpha);
		COLOR = vec4(rgb, alpha * part_visible);
	}
}
