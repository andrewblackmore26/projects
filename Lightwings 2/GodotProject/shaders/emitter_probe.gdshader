shader_type canvas_item;
render_mode unshaded;

// Diagnostic: a flat emitter well above the glow threshold. If a 200x100 block
// of this does not bloom, the glow pass is not running at all.
uniform float level = 1.8;

void fragment() {
    COLOR = vec4(vec3(level), 1.0);
}
