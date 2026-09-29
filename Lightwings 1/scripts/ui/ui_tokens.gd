class_name UiTokens
extends RefCounted
## The design tokens of the interface (modernization M4, art direction "Luminous Instrument"): one
## place for spacing, radii, the type scale, the font families, colour ROLES and the motion
## timings. The theme (UiKit.build_theme -> theme/lightship_theme.tres), UiMotion and the screens
## read these; nothing in the UI writes an inline hex value of its own. The colours are derived
## from VisualStyle's palette, so the ships, the arena and the menus stay one palette.

## Spacing scale, px.
const SPACE_1: int = 4
const SPACE_2: int = 8
const SPACE_3: int = 12
const SPACE_4: int = 16
const SPACE_5: int = 24
const SPACE_6: int = 32
const SPACE_7: int = 48
const SPACE_8: int = 64

## Corner radii, px. Buttons are capsules: their radius is half their height, which StyleBoxFlat
## clamps to, so CAPSULE only has to be larger than any button is tall.
const RADIUS_SMALL: int = 6
const RADIUS_PANEL: int = 12
const CAPSULE: int = 64

## Type scale, px.
const TEXT_XS: int = 12
const TEXT_S: int = 14
const TEXT_M: int = 16
const TEXT_L: int = 20
const TEXT_XL: int = 28
const TEXT_2XL: int = 40
const TEXT_3XL: int = 64
const TYPE_SCALE: Array[int] = [TEXT_XS, TEXT_S, TEXT_M, TEXT_L, TEXT_XL, TEXT_2XL, TEXT_3XL]
## A label this size or larger is display type (Exo 2); smaller is body (Inter).
const DISPLAY_MIN: int = 24

## Font families. Exo 2 for display and numbers, Inter (tabular figures) for body text,
## JetBrains Mono for bindings and the console. All SIL OFL 1.1 (THIRD_PARTY_NOTICES.md).
const FONT_DISPLAY: String = "res://assets/fonts/exo2/Exo2-Variable.ttf"
const FONT_BODY: String = "res://assets/fonts/inter/Inter-Variable.ttf"
const FONT_MONO: String = "res://assets/fonts/jetbrainsmono/JetBrainsMono-Variable.ttf"
const WEIGHT_BODY: int = 450
const WEIGHT_BODY_STRONG: int = 600
const WEIGHT_DISPLAY: int = 700
const WEIGHT_BUTTON: int = 600
const WEIGHT_MONO: int = 500

## Theme type variations the screens opt into (Control.theme_type_variation).
const DISPLAY_LABEL: StringName = &"DisplayLabel"
const KICKER_LABEL: StringName = &"KickerLabel"
const MONO_LABEL: StringName = &"MonoLabel"
const PRIMARY_BUTTON: StringName = &"PrimaryButton"
const TILE_BUTTON: StringName = &"TileButton"
const GLASS_PANEL: StringName = &"GlassPanel"

## Colour roles.
## - blue: the player's light;  gold: focus and action;  coral: loss and danger;
## - element colours (ElementStyle.color in the UI) carry element information only.
## - M19 review: gold is ONLY focus and the call to action. Plain data (kickers, stats, slider and
##   toggle fills) is neutral ink or the player's blue, so gold on screen always means "this one".
const INK: Color = VisualStyle.TEXT
const INK_MUTED: Color = VisualStyle.MUTED
## A kicker (the small letter-spaced caption over a heading) and a filled value (slider, switch).
const KICKER: Color = VisualStyle.MUTED
const VALUE: Color = VisualStyle.BLUE
const INK_DISABLED: Color = Color(VisualStyle.MUTED, 0.45)
const PLAYER: Color = VisualStyle.BLUE
const FOCUS: Color = VisualStyle.ACCENT
const DANGER: Color = VisualStyle.CORAL
const CANVAS: Color = VisualStyle.BG
## Smoked glass: #0b0d14 at 82 %, a 1 px #2a3040 stroke and a 1 px highlight along the top edge.
const GLASS: Color = Color(0.043, 0.051, 0.078, 0.82)
const GLASS_RAISED: Color = Color(0.075, 0.086, 0.122, 0.9)
const GLASS_PRESSED: Color = Color(0.13, 0.115, 0.05, 0.92)
const STROKE: Color = Color(0.165, 0.188, 0.251)
const HIGHLIGHT: Color = Color(1.0, 1.0, 1.0, 0.07)
const TRACK: Color = Color(0.165, 0.188, 0.251, 0.9)
## The gold focus glow: a 2 px border plus a 12 px shadow of this colour.
const FOCUS_GLOW: Color = Color(VisualStyle.ACCENT, 0.35)
const FOCUS_GLOW_SIZE: int = 12
const FOCUS_BORDER: int = 2
## The backdrop behind modal screens over the live game.
const SCRIM: Color = Color(0.02, 0.024, 0.04)
## Mixed in linear light (HDR 2D), where 0.55 and 0.7 still let the title's wordmark compete with
## the Options heading on the captures; 0.8 in linear is about a 55 % perceptual dim of mid-grey.
const SCRIM_DIM: float = 0.8
const SCRIM_BLUR_LOD: float = 3.2

## Motion, seconds. Every UI tween reads these through UiMotion.duration().
const MICRO: float = 0.08
const FAST: float = 0.14
const BASE: float = 0.22
const SLOW: float = 0.36
const CINE: float = 0.60
const STAGGER: float = 0.035
## A stagger never delays its last item by more than this, however many items it has.
const STAGGER_MAX: float = 0.28
## Easings: out-quint in, in-cubic out, out-back 1.4 pop, a spring of omega 18 for bars.
const EASE_IN_TRANS: Tween.TransitionType = Tween.TRANS_QUINT
const EASE_IN_EASE: Tween.EaseType = Tween.EASE_OUT
const EASE_OUT_TRANS: Tween.TransitionType = Tween.TRANS_CUBIC
const EASE_OUT_EASE: Tween.EaseType = Tween.EASE_IN
const POP_OVERSHOOT: float = 1.4
const SPRING_OMEGA: float = 18.0
## Reduced motion: moves take no time and fades are capped at this.
const REDUCED_FADE_CAP: float = 0.12
## Distances, px: how far an entering element travels, and a hover's lift.
const ENTER_RISE: float = 14.0
const HOVER_SCALE: float = 1.025
const PRESS_SCALE: float = 0.96
