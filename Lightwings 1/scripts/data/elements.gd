class_name Elements
extends RefCounted
## Element identities, stable wire order and high-contrast projectile/feedback colours.
## The restrained ship/UI palette lives in VisualStyle with the same colour keys.
##
## INDEX_ORDER is a wire format: a bullet's element is an int into it, an actor's faction is that
## int + 1, and saves store both. Never reorder it. The campaign's reveal order is a different list
## with a different job and stays in GameTuning.ELEMENTS.

const INDEX_ORDER: Array[String] = ["fire", "lightning", "void", "corruption", "plasma"]

const PLAYER_COLOR_KEY: String = "blue"
const COLOR_KEYS: Array[String] = ["blue", "red", "yellow", "green", "violet", "silver"]
const COLOR_KEY: Dictionary = {"fire": "red", "lightning": "yellow", "corruption": "green", "plasma": "violet", "void": "silver"}
const ELEMENT_OF_COLOR: Dictionary = {"red": "fire", "yellow": "lightning", "green": "corruption", "violet": "plasma", "silver": "void"}

## Bright projectile and ability feedback colours, by colour key.
const RIM: Dictionary = {"blue": Color("6fd3ff"), "red": Color("ff5436"), "yellow": Color("ffd23f"), "green": Color("45e06a"), "violet": Color("a97dff"), "silver": Color("9aa3b3")}
const FILL: Dictionary = {"blue": Color("08233a"), "red": Color("2a0b08"), "yellow": Color("2a2206"), "green": Color("062a12"), "violet": Color("1d1233"), "silver": Color("000000")}
const LIGHT: Dictionary = {"blue": Color("dcf5ff"), "red": Color("ffc6b5"), "yellow": Color("fff3bd"), "green": Color("caffd5"), "violet": Color("e4d6ff"), "silver": Color("ffffff")}

const PLAYER_RIM: Color = Color("6fd3ff")

## Rim colours in INDEX_ORDER, for the canvases that index by a bullet's element int.
const RIM_BY_INDEX: Array[Color] = [Color("ff5436"), Color("ffd23f"), Color("9aa3b3"), Color("45e06a"), Color("a97dff")]

static func index_of(element: String) -> int:
	return INDEX_ORDER.find(element)

static func color_key(element: String) -> String:
	return str(COLOR_KEY.get(element, ""))
