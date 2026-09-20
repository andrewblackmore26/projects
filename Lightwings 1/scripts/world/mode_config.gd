## Answers mode-dependent questions (demo vs campaign) that were previously
## scattered through main.gd as ad-hoc `campaign.demo` checks and literals.
class_name ModeConfig
extends RefCounted

var id: String = "campaign"

static func from_demo(is_demo: bool) -> ModeConfig:
	var result := ModeConfig.new()
	result.id = "demo" if is_demo else "campaign"
	return result

func save_slot() -> String:
	return id

func max_tier() -> int:
	return 3 if id == "demo" else GameTuning.MAX_TIER

func achievements_enabled() -> bool:
	return id != "demo"

func cloud_enabled() -> bool:
	return id != "demo"
