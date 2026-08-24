shader_type canvas_item;
render_mode unshaded;

// The board's ground. It goes through a raw shader on purpose: Godot converts a
// clear colour (and a ColorRect's colour) from sRGB on the way in, so #05070D
// specified that way lands near zero on screen and the neon has nothing to sit
// against. Written here, the value reaches the framebuffer untouched and can be
// eyedropped against the spec.
//
// Not pure black, deliberately: glow needs something to sit against.

// No source_color hint on purpose: that hint makes Godot convert the value from
// sRGB on the way in, which is the very transfer that sinks #05070D to black.
uniform vec4 ground = vec4(0.0196, 0.0275, 0.051, 1.0);

void fragment() {
    COLOR = vec4(ground.rgb, 1.0);
}
