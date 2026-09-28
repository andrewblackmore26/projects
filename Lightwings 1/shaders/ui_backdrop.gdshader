shader_type canvas_item;
// The backdrop behind a modal screen over the live game (modernization M5, ScreenRouter backdrop
// "dim_blur"): the screen behind it, blurred through the back buffer's mipmaps (Godot blurs each
// mip level as it builds them), then dimmed toward the scrim colour. The node's modulate alpha
// (COLOR.a here) is the transition: 0 shows the game untouched, 1 is the full backdrop.
// blur_lod 0 is dim only, the fallback if a renderer cannot supply the mipmaps.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 scrim : source_color = vec4(0.02, 0.024, 0.04, 1.0);
uniform float dim : hint_range(0.0, 1.0) = 0.55;
uniform float blur_lod : hint_range(0.0, 6.0) = 3.2;

void fragment() {
	float fade = COLOR.a;
	float lod = blur_lod * fade;
	// Five taps one mip texel apart smooth the blocky upsampling of a single coarse mip.
	vec2 tap = SCREEN_PIXEL_SIZE * exp2(lod) * 0.75;
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, lod).rgb * 0.36;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(tap.x, tap.y), lod).rgb * 0.16;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(-tap.x, tap.y), lod).rgb * 0.16;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(tap.x, -tap.y), lod).rgb * 0.16;
	blurred += textureLod(screen_texture, SCREEN_UV + vec2(-tap.x, -tap.y), lod).rgb * 0.16;
	COLOR = vec4(mix(blurred, scrim.rgb, dim * fade), 1.0);
}
