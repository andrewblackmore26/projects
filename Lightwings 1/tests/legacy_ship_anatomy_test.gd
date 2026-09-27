extends SceneTree
const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")

func _initialize() -> void: _run.call_deferred()

func _damage(actor: Dictionary) -> void:
	var rig: ShipMotion.ShipRig = actor.rig
	for i: int in range(1, rig.ids.size()):
		actor.part_cd[i] = 0.37 + float(i) * 0.01
		actor.part_egg_cd[i] = 1.7
		actor.part_aim[i] = Vector2(0.6, 0.8)
		if float(actor.part_max_hp[i]) > 0.0: actor.part_hp[i] *= 0.43
	# A final leaf is absent, including a spent share. Loading must not recreate it.
	var leaf: int = rig.ids.size() - 1
	actor.part_attached[leaf] = 0
	actor.part_hp[leaf] = 0.0

func _run() -> void:
	var h := Harness.new("LEGACY SHIP ANATOMY")
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	for revision: int in [1, 2]:
		for entry: Dictionary in RailRoster.manifest():
			var old: ShipDefinition = ShipCatalog.get_ship_revision(str(entry.id), revision)
			h.check(old != null and old.geometry_revision == revision, "%s legacy%d definition resolves" % [entry.id, revision])
			if old == null: continue
			var actor: Dictionary = w._make_actor(21, old.element, 4, Vector2(500, 400), 1, old.faction == "boss")
			actor.hull_id = old.id
			w._configure_actor(actor, old, true)
			_damage(actor)
			var before: Dictionary = CombatPersistence.encode_parts(actor)
			var saved: Dictionary = CombatPersistence.actor_snapshot(w, actor)
			# Exercise real pre-change saves, which had no embedded grammar or revision1 tag.
			saved.erase("hull_definition")
			if revision == 1: saved.parts.erase("geometry_revision")
			var encounter: Dictionary = {"enemies": [saved], "pickups": [{"id": 17, "amount": 2.5}], "resource_paid": 3, "resource_remaining": 7}
			CombatPersistence.cache_encounter(w, "legacy", encounter)
			w.sector_cache.clear()
			CombatPersistence.restore_encounter(w, CombatPersistence.read_cached_encounter(w, "legacy"))
			h.check(w.enemies.size() == 1, "%s legacy%d cold cache retains actor" % [entry.id, revision])
			if w.enemies.is_empty(): continue
			var restored: Dictionary = w.enemies[0]
			h.check(restored.definition.geometry_revision == revision and restored.rig.ids == actor.rig.ids, "%s legacy%d exact anatomy and circle IDs retained" % [entry.id, revision])
			h.check(CombatPersistence.encode_parts(restored) == before, "%s legacy%d HP, cooldowns, aim, attachment and reward shares retained" % [entry.id, revision])
			h.check(restored.reward_remaining == actor.reward_remaining and restored.reward_unpaid_limb == actor.reward_unpaid_limb, "%s legacy%d actor reward pools retained" % [entry.id, revision])
			var again: Dictionary = CombatPersistence.encounter_snapshot(w)
			CombatPersistence.restore_encounter(w, again)
			h.check(CombatPersistence.encounter_snapshot(w) == again, "%s legacy%d resave is idempotent" % [entry.id, revision])
		for id: String in ["player_seed", "player_lightning_t6_heavy"]:
			w.setup_player("neutral", 1, 80.0, [], Vector2(500, 400))
			w.set_player_hull(id)
			var definition: ShipDefinition = ShipCatalog.get_ship_revision(id, revision)
			w._configure_actor(w.player, definition, true)
			_damage(w.player)
			var before: Dictionary = CombatPersistence.encode_parts(w.player)
			var saved: Dictionary = CombatPersistence.snapshot(w)
			saved.player.erase("hull_definition")
			if revision == 1: saved.player.parts.erase("geometry_revision")
			CombatPersistence.restore(w, saved)
			h.check(w.player.definition.geometry_revision == revision and CombatPersistence.encode_parts(w.player) == before, "%s legacy%d whole save retains player anatomy/state" % [id, revision])
			var again: Dictionary = CombatPersistence.snapshot(w)
			CombatPersistence.restore(w, again)
			h.check(CombatPersistence.snapshot(w) == again, "%s legacy%d repeated whole save is idempotent" % [id, revision])
	var current: ShipDefinition = ShipCatalog.get_ship("player_lightning_t6_heavy")
	h.check(current.geometry_revision == 3, "New spawns and evolution still select revision3")
	var custom: ShipDefinition = ShipCatalog.get_ship_revision("player_lightning_t6_heavy", 1)
	custom.id = "custom_preserved_anatomy"
	custom.rails[0].slots[0].hp = 137.0
	var decoded: ShipDefinition = ShipCatalog.get_ship_revision(custom.id, 1, ShipCatalog.encode_definition(custom))
	h.check(decoded != null and ShipAuthoring.to_json(decoded) == ShipAuthoring.to_json(custom), "Embedded custom geometry survives without a roster file")
	h.control("invalid embedded ID cannot replace another hull", ShipCatalog.get_ship_revision("missing_id", 1, ShipCatalog.encode_definition(custom)) == null)
	var native: ShipDefinition = ShipDefinition.new()
	native.id = "custom_native_anatomy"
	native.faction = "enemy"
	native.element = "corruption"
	ShipCatalog.add_part(native, "core", "circle", Vector2.ZERO, 14.0, "chassis", "speed")
	ShipCatalog.mount_component(native, "pulse_cannon", "primary", Vector2(0, -27), 6.0)
	ShipCatalog.recalculate(native)
	var native_saved: Dictionary = ShipCatalog.encode_definition(native)
	var native_json: Dictionary = CombatPersistence.decode_value(JSON.parse_string(JSON.stringify(CombatPersistence.json_value(native_saved))))
	var native_restored: ShipDefinition = ShipCatalog.get_ship_revision(native.id, 1, native_json)
	h.check(native_restored != null and ShipCatalog.encode_definition(native_restored) == native_saved, "Native schema3 authored circles/lines/stats survive JSON without a roster file")
	w.free()
	h.finish(self)
