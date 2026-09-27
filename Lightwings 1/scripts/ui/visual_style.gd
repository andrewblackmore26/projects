class_name VisualStyle
extends RefCounted
## One presentation palette for ships, menus and the arena. Gameplay never reads these values.
const BG: Color = Color("050507")
const PANEL: Color = Color("1b1b20")
const TEXT: Color = Color("e5e3da")
const MUTED: Color = Color("9c9ca7")
const ACCENT: Color = Color("ffd23f")
const BLUE: Color = Color("6fd3ff")
const CORAL: Color = Color("ff5436")
const GREEN: Color = Color("45e06a")
const VIOLET: Color = Color("a97dff")
const SILVER: Color = Color("9aa3b3")
const STROKE_WIDTH: float = 1.5
const CONNECTOR_WIDTH: float = 2.0
const CONNECTOR_OPACITY: float = 0.85
const LIGHT_WIDTH: float = 2.6
const LIGHT_FRACTION: float = 0.13
const GUIDE_WIDTH: float = 1.0
const GUIDE_OPACITY: float = 0.28
const GUIDE_DASH: float = 2.0
const GUIDE_PERIOD: float = 7.0
const CORE_PULSE: float = 0.25
const CORE_FREQUENCY: float = 4.0
const GLOW_INTENSITY: float = 0.65
const GLOW_STRENGTH: float = 0.22
const PALETTE: Dictionary = {
	"blue": BLUE, "player": BLUE, "player_blue": BLUE,
	"fire": CORAL, "red": CORAL, "lightning": ACCENT, "gold": ACCENT, "yellow": ACCENT,
	"corruption": GREEN, "green": GREEN, "plasma": VIOLET, "violet": VIOLET,
	"void": SILVER, "silver": SILVER, "neutral": SILVER, "white": Color.WHITE, "black": Color.BLACK,
}
const FILLS: Dictionary = {
	"blue": Color("08233a"), "player": Color("08233a"), "player_blue": Color("08233a"),
	"fire": Color("2a0b08"), "red": Color("2a0b08"),
	"lightning": Color("2a2206"), "yellow": Color("2a2206"), "gold": Color("2a2206"),
	"corruption": Color("062a12"), "green": Color("062a12"),
	"plasma": Color("1d1233"), "violet": Color("1d1233"),
	"void": Color("090a10"), "silver": Color("090a10"), "neutral": Color("090a10"),
	"white": Color("272729"), "black": Color.BLACK,
}

static func configure_ship_material(material: ShaderMaterial) -> void:
	material.set_shader_parameter("stroke_width", STROKE_WIDTH)
	material.set_shader_parameter("connector_width", CONNECTOR_WIDTH)
	material.set_shader_parameter("connector_opacity", CONNECTOR_OPACITY)
	material.set_shader_parameter("light_width", LIGHT_WIDTH)
	material.set_shader_parameter("light_fraction", LIGHT_FRACTION)
	material.set_shader_parameter("guide_width", GUIDE_WIDTH)
	material.set_shader_parameter("guide_opacity", GUIDE_OPACITY)
	material.set_shader_parameter("guide_dash", GUIDE_DASH)
	material.set_shader_parameter("guide_period", GUIDE_PERIOD)
	material.set_shader_parameter("core_pulse", CORE_PULSE)
	material.set_shader_parameter("core_pulse_freq", CORE_FREQUENCY)

static func configure_glow(environment: Environment) -> void:
	environment.glow_hdr_threshold = 1.0
	environment.glow_intensity = GLOW_INTENSITY
	environment.glow_strength = GLOW_STRENGTH
	environment.glow_bloom = 0.0
