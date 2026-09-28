shader_type canvas_item;
render_mode unshaded;
// Modernization M16: the ONE full-screen post pass (scripts/fx/post_fx.gd, CanvasLayer 5: above the
// world and its glow, below the UI on layer 10). Every uniform is driven by PostFx; nothing here
// keeps time of its own. Colours are the 2D buffer's own values (linear with hdr_2d on).

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
// Corner darkening at the far corner, 0..1. Subtle by default.
uniform float vignette_strength = 0.16;
uniform float vignette_start = 0.45;
uniform float vignette_end = 1.1;
// Radial chromatic aberration, in screen pixels (<= 3 by contract, PostFx clamps it).
uniform float aberration_px = 0.0;
uniform float hurt = 0.0;
uniform vec4 hurt_color : source_color = vec4(1.0, 0.42, 0.36, 1.0);
// Additive white; PostFx.request_flash is the only writer and caps it at 0.25 x the flash setting.
uniform float flash = 0.0;
uniform float desaturation = 0.0;
// Low-light coral edge, 0..1 (PostFx pulses it on the heartbeat unless motion is reduced).
uniform float low_light_edge = 0.0;
uniform vec4 low_light_color : source_color = vec4(1.0, 0.42, 0.36, 1.0);
uniform float scanlines = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 centred = uv - 0.5;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	// 0 at the centre, 1 at a corner, independent of the aspect ratio.
	float dist = length(centred * vec2(aspect, 1.0)) / length(vec2(aspect * 0.5, 0.5));
	vec3 colour;
	if (aberration_px > 0.001) {
		vec2 direction = length(centred) > 0.00001 ? normalize(centred * vec2(aspect, 1.0)) : vec2(0.0);
		// Full strength beyond a quarter of the way out, zero at the centre so the ship never splits.
		vec2 offset = direction * aberration_px * smoothstep(0.0, 0.25, dist) * SCREEN_PIXEL_SIZE;
		colour.r = texture(screen_texture, uv - offset).r;
		colour.g = texture(screen_texture, uv).g;
		colour.b = texture(screen_texture, uv + offset).b;
	} else {
		colour = texture(screen_texture, uv).rgb;
	}
	float edge = smoothstep(vignette_start, vignette_end, dist);
	colour *= 1.0 - vignette_strength * edge;
	float luma = dot(colour, vec3(0.2126, 0.7152, 0.0722));
	colour = mix(colour, vec3(luma), clamp(desaturation, 0.0, 1.0));
	float rim = smoothstep(0.3, 1.0, dist);
	colour = mix(colour, low_light_color.rgb * max(luma, 0.15), clamp(low_light_edge * rim, 0.0, 1.0));
	// A faint additive coral too, so the pulse still reads over the near-black void.
	colour += low_light_color.rgb * low_light_edge * rim * rim * 0.06;
	colour = mix(colour, hurt_color.rgb * max(luma, 0.2) + colour * 0.5, clamp(hurt * (0.15 + 0.45 * rim), 0.0, 1.0));
	if (scanlines > 0.001) {
		colour *= 1.0 - scanlines * 0.18 * step(mod(FRAGCOORD.y, 3.0), 1.0);
	}
	colour += vec3(flash);
	COLOR = vec4(colour, 1.0);
}
