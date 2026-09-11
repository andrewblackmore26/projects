shader_type canvas_item;
render_mode unshaded;

// The playfield. It goes through a raw shader on purpose: Godot converts a
// clear colour (and a ColorRect's colour) from sRGB on the way in, so #050507
// specified that way lands near zero on screen and the glow has nothing to sit
// against. Written here, the value reaches the framebuffer untouched and can be
// measured against the spec (Appendix A: playfield #050507).
//
// No source_color hint on purpose: that hint makes Godot convert the value from
// sRGB on the way in, which is the very transfer that sinks #050507 to black.
uniform vec4 ground = vec4(0.0196, 0.0196, 0.0275, 1.0);

void fragment() {
    COLOR = vec4(ground.rgb, 1.0);
}
