shader_type canvas_item;
render_mode unshaded;

// This viewport already contains bloom. Keep it below the foreground extraction
// threshold, otherwise the second glow pass would leak through black Void masks.
void fragment() {
	vec4 background = texture(TEXTURE, UV);
	COLOR = vec4(clamp(background.rgb, vec3(0.0), vec3(0.99)), 1.0);
}
