## Answers EVERY mode-dependent question (spec §4: campaign / dev / demo),
## replacing the scattered `campaign.demo` checks, `OS.has_feature("demo")`
## checks and v0.2-era literals that used to live in main.gd and
## campaign_state.gd. One row per mode; nothing outside this table decides
## what a mode means.
class_name ModeConfig
extends RefCounted

var id: String = "campaign"

## save_slot: SaveService slot name.
## cloud_enabled: may this mode's profile ever be pushed to Steam Cloud
##   (spec §4 "Dev is never cloud-synced").
## achievements_enabled: spec §4 "Dev mode earns no achievements".
## max_tier: evolution ceiling. Demo is redefined by the approved preamble
##   to have NO tier cap (dropped-scope table: "no tier cap").
## level_cap: highest level number this mode's world model ever reveals
##   (element reveal / archetype tables key off this, not off levels_completed).
## selectable_levels(profile): which level numbers level-select offers.
## enemy_elements: elements the node pool may roll enemies from.
## initial_unlocked: elements the profile starts with unlocked.
## offer_policy: "standard" (three ranked offers) or "all_hulls" (dev: every
##   next-tier hull of every element, grouped for the UI).
## console_enabled: spec §4 "a tier-set console command... stays in the
##   shipped build" for dev only.
const ROWS: Dictionary = {
	"campaign": {
		"save_slot": "campaign", "cloud_enabled": true, "achievements_enabled": true,
		"max_tier": GameTuning.MAX_TIER, "level_cap": 5,
		"enemy_elements": GameTuning.ELEMENTS, "initial_unlocked": ["lightning"],
		"offer_policy": "standard", "console_enabled": false, "menu_label": "CAMPAIGN",
	},
	"dev": {
		"save_slot": "dev", "cloud_enabled": false, "achievements_enabled": false,
		"max_tier": GameTuning.MAX_TIER, "level_cap": 5,
		"enemy_elements": GameTuning.ELEMENTS, "initial_unlocked": GameTuning.ELEMENTS,
		"offer_policy": "all_hulls", "console_enabled": true, "menu_label": "DEV MODE",
	},
	"demo": {
		"save_slot": "demo", "cloud_enabled": false, "achievements_enabled": false,
		"max_tier": GameTuning.MAX_TIER, "level_cap": 2,
		"enemy_elements": ["lightning", "fire"], "initial_unlocked": ["lightning"],
		"offer_policy": "standard", "console_enabled": false, "menu_label": "DEMO",
	},
}

static func from_id(mode_id: String) -> ModeConfig:
	var result := ModeConfig.new()
	result.id = mode_id if ROWS.has(mode_id) else "campaign"
	return result

## Kept for the many existing call sites that only ever asked the old
## binary question (menu-time `--demo` build detection, save fixtures).
static func from_demo(is_demo: bool) -> ModeConfig:
	return from_id("demo" if is_demo else "campaign")

func _row() -> Dictionary:
	return ROWS.get(id, ROWS["campaign"])

func save_slot() -> String:
	return str(_row().save_slot)

func max_tier() -> int:
	return int(_row().max_tier)

func achievements_enabled() -> bool:
	return bool(_row().achievements_enabled)

func cloud_enabled() -> bool:
	return bool(_row().cloud_enabled)

func level_cap() -> int:
	return int(_row().level_cap)

func enemy_elements() -> Array:
	return Array(_row().enemy_elements)

func initial_unlocked() -> Array:
	return Array(_row().initial_unlocked)

func offer_policy() -> String:
	return str(_row().offer_policy)

func console_enabled() -> bool:
	return bool(_row().console_enabled)

func menu_label() -> String:
	return str(_row().menu_label)

## Campaign offers levels 1..completed+1; dev offers every level (spec §4
## "Level select"); demo is capped to its own level_cap regardless of
## levels_completed (a demo build never reveals levels 3-5).
func selectable_levels(levels_completed: Array) -> Array[int]:
	var highest: int = 1
	for entry: Variant in levels_completed:
		highest = maxi(highest, int(entry) + 1)
	var result: Array[int] = []
	var ceiling: int = level_cap() if id == "dev" else mini(level_cap(), highest)
	for level: int in range(1, ceiling + 1):
		result.append(level)
	return result

## Available modes for the CURRENT build flavour (spec §4: "a demo build
## offers demo only" -- Dev must not be reachable in a demo build, or it
## would hand over the whole game). `is_demo_build` is the build's own
## `OS.has_feature("demo")` question, asked exactly once, here.
static func available_modes(is_demo_build: bool) -> Array[String]:
	var result: Array[String] = []
	if is_demo_build:
		result.append("demo")
	else:
		result.append("campaign")
		result.append("dev")
	return result
