class_name PackageValidation
extends RefCounted
## Explicit --verify-package mode exercises the shipped runtime and embedded PCK.

var failures: int = 0
var checks: int = 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run(app: Node) -> void:
	var tree: SceneTree = app.get_tree()
	check(not OS.has_feature("editor"), "Uses an exported engine and embedded PCK")
	var expected_demo: bool = "--expected-demo" in OS.get_cmdline_user_args()
	check(OS.has_feature("demo") == expected_demo, "Correct package feature flags")
	var player_count: int = 0
	for ship: ShipDefinition in ShipCatalog.all_forms():
		check(ShipCatalog.validate(ship).is_empty(),"Packaged ship: "+ship.id)
		if ship.is_player: player_count += 1
	check(player_count == 101,"Complete 101-player-hull roster packaged")
	for id: String in AbilityCatalog.DEFINITIONS:
		check(AbilityCatalog.get_definition(id).id == id, "Packaged ability: "+id)
	check(Engine.has_singleton("Steam"), "Packaged GodotSteam extension loads")
	check(FileAccess.file_exists("res://content/platform/steam_input_manifest.vdf"), "Input manifest is packaged")
	check(FileAccess.file_exists("res://addons/godotsteam/license.md"), "Extension license is packaged")
	## Every export preset excludes scripts/editor/*; dev_console.gd and
	## mode_config.gd live outside that folder specifically so Dev mode can
	## start in a shipped build. A silent failure here (the PCK not carrying
	## the script) would otherwise only surface as an unclickable menu
	## button, which is exactly the kind of thing this build-time check
	## exists to catch instead.
	var console_script: GDScript = load("res://scripts/ui/dev_console.gd")
	check(console_script != null and console_script.get_global_name() == "DevConsole", "dev_console.gd is packaged and loads from the PCK")
	check(DevConsole.parse("tier 3 fire").ok, "Packaged DevConsole parser runs")
	var mode_config_script: GDScript = load("res://scripts/world/mode_config.gd")
	check(mode_config_script != null and mode_config_script.get_global_name() == "ModeConfig", "mode_config.gd is packaged and loads from the PCK")
	check(("dev" in ModeConfig.available_modes(expected_demo)) == (not expected_demo), "Dev mode is reachable only in the full (non-demo) package")
	SaveService.storage_root = "user://package-validation-"+str(Time.get_ticks_usec())
	app.testing = true
	await tree.process_frame
	check(app.mode=="menu", "Packaged main menu launches")
	app._new_game(false)
	check(app.campaign.demo == expected_demo, "Demo boundary is enforced by package")
	for tick: int in range(8): await tree.physics_frame
	check(app.combat.elapsed > 0.0, "Packaged combat simulation advances")
	app.combat.light_total = 100.0
	app.combat.absorption = {"fire":20.0,"corruption":20.0,"plasma":20.0}
	app._show_evolution()
	check(tree.paused and app.overlay_kind=="evolution", "Evolution overlay opens from packaged resources")
	check(app.pending_offers.size() == 3,"Three packaged preset cards")
	app._choose_evolution(app.pending_offers[0])
	check(not tree.paused and app.combat.player_tier==2, "Evolution works in export")
	# Let the queued evolution sound enter playback before testing restore/quit.
	await tree.process_frame
	var snapshot: Dictionary = app.combat.snapshot()
	check(SaveService.save_snapshot(app.campaign.to_dict(),{"combat":snapshot},"package") == OK, "Platform save writes")
	var restored: Dictionary = SaveService.load_snapshot("package")
	check(not restored.get("run",{}).is_empty(), "Platform save reloads")
	app.combat.restore(restored.run.combat)
	check(app.combat.player_tier==2 and app.combat.light_total==100.0, "Run values survive platform serialization")
	await app._stop_audio()
	check(app.sound.audio_retired(), "Stopped packaged audio releases its native playback references")
	print("PACKAGE ",OS.get_name()," ","DEMO" if expected_demo else "CAMPAIGN",": ",checks," checks, ",failures," failures")
	tree.quit(1 if failures else 0)
