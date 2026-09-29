extends SceneTree
## M11: device-aware input prompts (scripts/ui/input_prompts.gd) and the ability glyph table
## (scripts/ui/ability_glyphs.gd). Headless: the prompts are resolved, not drawn; the pixels are
## a GPU capture of the HUD dock, recorded in the phase report.
##   - every one of InputBindings' 17 actions resolves a glyph file for keyboard/mouse and for each
##     pad family, from the action's CURRENT InputMap binding;
##   - a faked joypad event switches every prompt to the pad set, a faked key switches it back,
##     and drift / jitter below the thresholds switches nothing;
##   - an action with no binding for the device is REPORTED (missing, "?"), never blank;
##   - rebinding changes the glyph.
## The InputMap is edited directly, never through InputBindings.rebind, which would write the
## player's user://controls.cfg.
## Restated in the M19 UX review: the dialogue skip joined InputBindings (shown and rebindable in
## Controls), so every "16 actions" count is ACTIONS (17); SPACE wears the labelled keyboard_space
## glyph (cropped to its keycap) instead of keyboard_space_icon.
const Harness = preload("res://tests/support/harness.gd")
const ACTIONS: int = 17

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var h := Harness.new("INPUT PROMPTS")
	InputBindings.setup()
	var prompts := InputPrompts.new()
	var switches: Array = []
	prompts.device_changed.connect(func(device: String, family: String) -> void: switches.append([device, family]))
	var kbm: String = InputPrompts.KEYBOARD_MOUSE
	var pad: String = InputPrompts.PAD
	h.check(InputBindings.ACTIONS.size() == ACTIONS, "InputBindings declares the %d actions (found %d)" % [ACTIONS, InputBindings.ACTIONS.size()])

	# --- Every action resolves a real glyph file, per device and per pad family -----------------
	for family: String in ["", "xbox", "playstation", "steamdeck"]:
		var device: String = kbm if family.is_empty() else pad
		var resolved: int = _resolved(prompts, device, family)
		h.check(resolved == ACTIONS, "%s: all %d actions resolve a glyph texture (found %d; unresolved: %s)" % [device + ("/" + family if not family.is_empty() else ""), ACTIONS, resolved, _unresolved(prompts, device, family)])
		h.check(prompts.unbound_actions(device, family if not family.is_empty() else "xbox").is_empty(), "%s %s: no action is unbound" % [device, family])
	h.check(bool(prompts.prompt_for("aim_up", kbm).implicit), "Keyboard/mouse aim is the pointer rule, flagged implicit")
	h.check(str(prompts.prompt_for("ability_primary", pad, "playstation").path).ends_with("/playstation/playstation_trigger_l1.png"), "PlayStation: ability_primary (LB) wears L1")
	h.check(str(prompts.prompt_for("fire", pad, "steamdeck").path).ends_with("/steamdeck/steamdeck_button_r2.png"), "Steam Deck: fire (right trigger) wears R2")
	h.check(str(prompts.prompt_for("move_up", pad, "generic").path).ends_with("/xbox/xbox_stick_l_up.png"), "A generic pad wears the Xbox set")
	h.check(prompts.text_for("ability_primary") == "SPACE", "Build readout text for slot 1 on keyboard is SPACE (got %s)" % prompts.text_for("ability_primary"))
	# Control for the resolve instrument: a binding with no glyph on disk must drop out of the count
	# (and draw as a text chip), so "all resolved" is not true of any binding whatsoever.
	_rebind(kbm, "ability_tertiary", _key(KEY_F))
	var chip: Dictionary = prompts.prompt_for("ability_tertiary", kbm)
	h.control("ability_tertiary rebound to F, which has no glyph file", _resolved(prompts, kbm, "") == ACTIONS - 1 and chip.texture == null and str(chip.text) == "F" and not bool(chip.missing))
	_rebind(kbm, "ability_tertiary", _key(KEY_Q))

	# --- Family from the pad's reported name -----------------------------------------------------
	for case: Array in [["Xbox Series X Controller", "xbox"], ["PS5 Controller", "playstation"], ["DualSense Wireless Controller", "playstation"], ["Steam Deck", "steamdeck"], ["USB Gamepad", "generic"]]:
		h.check(InputPrompts.family_for_name(str(case[0])) == str(case[1]), "Pad '%s' reads as %s (got %s)" % [case[0], case[1], InputPrompts.family_for_name(str(case[0]))])

	# --- Live device switching -------------------------------------------------------------------
	h.check(prompts.device == kbm, "Starts on keyboard/mouse")
	h.check(_on_folder(prompts, "keyboard_mouse") == ACTIONS, "Before any pad input every prompt is a keyboard/mouse glyph")
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.1
	h.check(not prompts.observe(drift) and prompts.device == kbm, "Stick drift (0.1) does not switch the device")
	var jitter := InputEventMouseMotion.new()
	jitter.relative = Vector2(1, 0)
	h.check(not prompts.observe(jitter), "Mouse jitter (1 px) does not switch anything")
	# Control for the switch instrument: an event that is not a device (a synthesized action, which
	# is how Steam Input forwards menu actions) must leave every prompt where it was.
	var synthetic := InputEventAction.new()
	synthetic.action = "evolve"
	synthetic.pressed = true
	prompts.observe(synthetic)
	h.control("a non-device InputEventAction offered as the switch", _on_folder(prompts, "xbox") != ACTIONS)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	h.check(prompts.observe(button), "A pad button press switches the device")
	h.check(prompts.device == pad and switches.size() == 1 and str(switches[0][0]) == pad, "device_changed fired once, with 'pad' (%s)" % [switches])
	h.check(_on_folder(prompts, InputPrompts.folder_for(prompts.family)) == ACTIONS, "After the pad press every one of the %d prompts is a pad glyph (%d)" % [ACTIONS, _on_folder(prompts, InputPrompts.folder_for(prompts.family))])
	h.check(prompts.text_for("ability_primary") == ("L1" if prompts.family in ["playstation", "steamdeck"] else "LB"), "Build readout text for slot 1 on a pad is the shoulder (got %s)" % prompts.text_for("ability_primary"))
	h.check(not prompts.observe(button), "A second press on the same pad is not a switch")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	h.check(prompts.observe(key) and prompts.device == kbm and switches.size() == 2, "A key press switches back to keyboard/mouse")
	h.check(_on_folder(prompts, "keyboard_mouse") == ACTIONS, "After the key press every prompt is a keyboard/mouse glyph again")
	var stick := InputEventJoypadMotion.new()
	stick.axis = JOY_AXIS_RIGHT_Y
	stick.axis_value = -0.9
	h.check(prompts.observe(stick) and prompts.device == pad, "A full stick push switches to the pad")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	h.check(prompts.observe(click) and prompts.device == kbm, "A mouse click switches back")

	# --- Unbound is reported, not blank ----------------------------------------------------------
	var saved: Array[InputEvent] = InputMap.action_get_events("evolve")
	for event: InputEvent in saved:
		if event is InputEventJoypadButton or event is InputEventJoypadMotion: InputMap.action_erase_event("evolve", event)
	var unbound: Dictionary = prompts.prompt_for("evolve", pad, "xbox")
	h.control("evolve's pad binding erased", prompts.unbound_actions(pad, "xbox").size() == 1 and prompts.unbound_actions(pad, "xbox")[0] == "evolve" and bool(unbound.missing) and str(unbound.text) == "?" and unbound.texture == null)
	h.check(prompts.unbound_actions(kbm).is_empty(), "Erasing the pad binding leaves keyboard/mouse bound")
	InputMap.action_erase_events("evolve")
	for event: InputEvent in saved: InputMap.action_add_event("evolve", event)
	h.check(prompts.unbound_actions(pad, "xbox").is_empty(), "Restored: nothing unbound")

	# --- Rebinding changes the glyph -------------------------------------------------------------
	var before_key: String = str(prompts.prompt_for("ability_tertiary", kbm).path)
	_rebind(kbm, "ability_tertiary", _key(KEY_E))
	var after_key: Dictionary = prompts.prompt_for("ability_tertiary", kbm)
	h.check(before_key.ends_with("keyboard_q.png") and str(after_key.path).ends_with("keyboard_e.png") and after_key.texture != null, "Rebinding ability_tertiary Q -> E changes its glyph (%s -> %s)" % [before_key.get_file(), str(after_key.path).get_file()])
	var before_pad: String = str(prompts.prompt_for("ability_primary", pad, "xbox").path)
	var shoulder := InputEventJoypadButton.new()
	shoulder.button_index = JOY_BUTTON_RIGHT_SHOULDER
	_rebind(pad, "ability_primary", shoulder)
	var after_pad: String = str(prompts.prompt_for("ability_primary", pad, "xbox").path)
	h.check(before_pad.ends_with("xbox_lb.png") and after_pad.ends_with("xbox_rb.png"), "Rebinding ability_primary LB -> RB changes its pad glyph (%s -> %s)" % [before_pad.get_file(), after_pad.get_file()])
	h.check(str(prompts.prompt_for("ability_primary", kbm).path).ends_with("keyboard_space.png"), "A pad rebind leaves the keyboard glyph alone")
	InputBindings.setup()

	_steam_input(h)

	# --- Ability glyphs: one shape per ability, set pieces drawn as themselves -------------------
	var from_pieces: int = 0
	for id: String in AbilityCatalog.DEFINITIONS:
		var shape: Dictionary = AbilityGlyphs.shape_for(id)
		h.check(not (shape.get("circles", []) as Array).is_empty(), "%s has a glyph with at least one circle" % id)
		if str(shape.source).begins_with("set_piece:"): from_pieces += 1
		if AbilityCatalog.DEFINITIONS[id][0] in ["primary", "secondary", "passive"]:
			h.check(str(shape.source) != "generic", "Player ability %s has its own glyph, not the generic one" % id)
	h.check(from_pieces == SetPieceCatalog.PIECES.size(), "Every set piece's ability is drawn as its set piece (%d of %d)" % [from_pieces, SetPieceCatalog.PIECES.size()])
	h.control("an id with no piece and no table entry", str(AbilityGlyphs.shape_for("turret_ring").source) == "generic")
	h.check(not (AbilityGlyphs.shape_for("dash").circles as Array).is_empty(), "The dash has a glyph")
	h.finish(self)

## A GodotSteam stand-in with one connected controller: `pressed` digital actions are down, `sticks`
## maps an analog action to its value. `input_type` < 0 leaves getInputTypeForHandle undefined (an
## older GodotSteam).
class FakeSteam extends RefCounted:
	var pressed: Dictionary = {}
	var sticks: Dictionary = {}
	func inputInit(_explicit: bool) -> bool: return true
	func runFrame() -> void: pass
	func getConnectedControllers() -> Array: return [7]
	func activateActionSet(_controller: int, _handle: int) -> void: pass
	func getActionSetHandle(name: String) -> int: return 1 if name == "Gameplay" else 2
	func getAnalogActionHandle(name: String) -> int: return 100 + ["Move", "Aim", "MenuNavigate"].find(name)
	func getDigitalActionHandle(name: String) -> int: return 1 + SteamInputService.DIGITAL_ACTIONS.find(name)
	func getAnalogActionData(_controller: int, handle: int) -> Dictionary:
		var value: Vector2 = sticks.get(["Move", "Aim", "MenuNavigate"][handle - 100], Vector2.ZERO)
		return {"active": true, "x": value.x, "y": -value.y}
	func getDigitalActionData(_controller: int, handle: int) -> Dictionary:
		return {"active": true, "state": bool(pressed.get(SteamInputService.DIGITAL_ACTIONS[handle - 1], false))}

class TypedSteam extends FakeSteam:
	var input_type: int = 13
	func getInputTypeForHandle(_controller: int) -> int: return input_type

## M19: Steam Input forwards InputEventActions, which `observe` cannot attribute to a device (the
## control above), so SteamInputService.poll selects the pad itself when the player touches the
## controller - and only then: a connected, idle controller must not pull a keyboard player's
## prompts over. The family is Steam's controller type when GodotSteam reports it, else the Deck.
func _steam_input(h: RefCounted) -> void:
	var prompts := InputPrompts.new()
	var fake := FakeSteam.new()
	var service := SteamInputService.new()
	service.prompts = prompts
	h.check(service.initialize(fake), "the Steam Input service initializes on the stand-in")
	service.set_context(false)
	service.poll(1.0 / 60.0)
	fake.sticks["Move"] = Vector2(0.2, 0.0)
	service.poll(1.0 / 60.0)
	h.check(prompts.device == InputPrompts.KEYBOARD_MOUSE, "a connected Steam controller at rest (stick 0.2) leaves the prompts on keyboard/mouse")
	fake.sticks["Move"] = Vector2.ZERO
	fake.pressed["Fire"] = true
	service.poll(1.0 / 60.0)
	h.check(prompts.device == InputPrompts.PAD and prompts.family == "steamdeck", "pressing Fire on it switches the prompts to the pad, Steam Deck set, with no controller type available (%s/%s)" % [prompts.device, prompts.family])
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	h.check(prompts.observe(key) and prompts.device == InputPrompts.KEYBOARD_MOUSE, "a key press takes the prompts back to keyboard/mouse")
	service.poll(1.0 / 60.0)
	h.check(prompts.device == InputPrompts.KEYBOARD_MOUSE, "Fire merely HELD on the Steam controller does not pull them back (only a new press does)")
	fake.pressed.clear()
	fake.sticks["Move"] = Vector2(0.0, -0.9)
	service.poll(1.0 / 60.0)
	h.check(prompts.device == InputPrompts.PAD, "a full stick push on the Steam controller switches to the pad")
	var typed_prompts := InputPrompts.new()
	var typed := TypedSteam.new()
	var typed_service := SteamInputService.new()
	typed_service.prompts = typed_prompts
	typed_service.initialize(typed)
	typed_service.set_context(false)
	typed.pressed["Dash"] = true
	typed_service.poll(1.0 / 60.0)
	h.check(typed_prompts.device == InputPrompts.PAD and typed_prompts.family == "playstation", "a PS5 controller under Steam Input (type 13) wears the PlayStation set (%s)" % typed_prompts.family)
	# Control: the pre-M19 service, which only forwarded actions. Its Fire press reaches the prompts
	# as nothing at all, and a forwarded menu action as a non-device InputEventAction.
	var old_prompts := InputPrompts.new()
	var forwarded := InputEventAction.new()
	forwarded.action = "ui_accept"
	forwarded.pressed = true
	old_prompts.observe(forwarded)
	h.control("the Steam path as forwarded actions only (device stays %s)" % old_prompts.device, old_prompts.device != InputPrompts.PAD)
	typed.input_type = 99
	typed_prompts.select(InputPrompts.KEYBOARD_MOUSE)
	typed.pressed.clear()
	typed_service.poll(1.0 / 60.0)
	typed.pressed["Dash"] = true
	typed_service.poll(1.0 / 60.0)
	h.control("a controller type the table does not know reads as generic, not as the Deck (%s)" % typed_prompts.family, typed_prompts.family == "generic")
	service.shutdown()
	typed_service.shutdown()

func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event

## InputBindings.rebind's rule (replace this device's bindings, keep the other's), minus the save.
func _rebind(device: String, action: String, event: InputEvent) -> void:
	for old: InputEvent in InputMap.action_get_events(action):
		var was_pad: bool = old is InputEventJoypadButton or old is InputEventJoypadMotion
		if was_pad == (device == InputPrompts.PAD): InputMap.action_erase_event(action, old)
	InputMap.action_add_event(action, event)

func _resolved(prompts: InputPrompts, device: String, family: String) -> int:
	var count: int = 0
	for action: String in InputBindings.ACTIONS:
		if prompts.prompt_for(action, device, family).texture != null: count += 1
	return count

func _unresolved(prompts: InputPrompts, device: String, family: String) -> Array:
	var result: Array = []
	for action: String in InputBindings.ACTIONS:
		var prompt: Dictionary = prompts.prompt_for(action, device, family)
		if prompt.texture == null: result.append("%s(%s)" % [action, prompt.path])
	return result

## How many of the actions' ACTIVE-device prompts are glyphs from `folder`.
func _on_folder(prompts: InputPrompts, folder: String) -> int:
	var count: int = 0
	for action: String in InputBindings.ACTIONS:
		var prompt: Dictionary = prompts.prompt_for(action)
		if prompt.texture != null and str(prompt.path).contains("/%s/" % folder): count += 1
	return count
