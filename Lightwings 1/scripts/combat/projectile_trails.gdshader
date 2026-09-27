shader_type canvas_item;
render_mode unshaded;
uniform sampler2D history_texture : filter_nearest, repeat_disable;
varying vec4 ribbon_color;
varying float edge;
varying float fade;

vec2 sample_point(int index, int head, int back) {
	return texelFetch(history_texture, ivec2((head - back + 21) % 21, index), 0).rg;
}

void vertex() {
	int index = int(INSTANCE_CUSTOM.x + 0.5);
	vec2 metadata = texelFetch(history_texture, ivec2(21, index), 0).rg;
	vec2 appearance = texelFetch(history_texture, ivec2(22, index), 0).rg;
	int head = int(metadata.x + 0.5);
	int count = max(int(metadata.y + 0.5), 1);
	int back = min(int(UV.x + 0.5), count - 1);
	vec2 point = sample_point(index, head, back);
	vec2 before = sample_point(index, head, max(back - 1, 0));
	vec2 after = sample_point(index, head, min(back + 1, count - 1));
	vec2 direction = before - after;
	vec2 normal = vec2(-direction.y, direction.x) / max(length(direction), 0.001);
	float amount = 1.0 - float(back) / max(float(count - 1), 1.0);
	float width = max(0.7, appearance.x * 1.5 * amount);
	VERTEX = point + normal * UV.y * width * 0.5;
	edge = UV.y;
	fade = metadata.y < 2.0 || UV.x >= float(count) ? 0.0 : 0.75 * amount;
	int flags = int(appearance.y + 0.5);
	vec3 light = vec3(0.71569, 0.91310, 1.0);
	if ((flags & 256) != 0) light = vec3(1.0, 0.56471, 0.46208);
	else if ((flags & 32) != 0) light = vec3(0.77582, 0.67244, 1.0);
	else if ((flags & 16) != 0) light = vec3(1.0, 0.89627, 0.50888);
	ribbon_color = vec4(light, 1.0);
}

void fragment() {
	float aa = max(fwidth(edge), 0.04);
	float alpha = 1.0 - smoothstep(1.0 - aa, 1.0, abs(edge));
	COLOR = vec4(ribbon_color.rgb, ribbon_color.a * fade * alpha);
}
