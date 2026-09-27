extends SceneTree
const Harness = preload("res://tests/support/harness.gd")
const World = preload("res://scripts/combat/combat_world.gd")

func _initialize() -> void: _run.call_deferred()

func _hp(ship: ShipDefinition, tier: int) -> float:
	var total: float = 0.0
	for part: PartDefinition in ship.parts:
		if part.shape == "circle" and part.id != "core": total += ShipCompiler.part_max_hp(part, tier)
	return total

func _weapons(ship: ShipDefinition) -> Dictionary:
	var result: Dictionary = {}
	for part: PartDefinition in ship.parts:
		if part.shape == "circle" and part.ability_id != "": result[part.id] = [part.mount_id, part.ability_id]
	return result

func _part(ship: ShipDefinition, id: String) -> PartDefinition:
	for part: PartDefinition in ship.parts:
		if part.id == id: return part
	return null

func _run() -> void:
	var h := Harness.new("SHIP GEOMETRY REVISION")
	var before_count: int = 0
	var after_count: int = 0
	for entry: Dictionary in RailRoster.manifest():
		var old: ShipDefinition = RailRoster.baseline_ship(str(entry.id))
		var ship: ShipDefinition = RailRoster.build(entry)
		ShipCompiler.compile(old)
		ShipCompiler.compile(ship)
		h.check(ShipGrammar.validate(old).is_empty(), "%s legacy/custom geometry retains a valid connected drawing" % old.id)
		before_count += int(RailRoster.baseline_entries()[entry.id].counts.circles)
		after_count += int(ShipCompiler.budget(ship).circles)
		h.check(ShipGrammar.validate(ship).is_empty(), "%s validates and every component is connected" % ship.id)
		h.check(_weapons(old) == _weapons(ship), "%s retains each exact weapon/host/mount" % ship.id)
		for key: String in ["id", "tier", "role", "family", "element", "speed", "turn_rate", "accel", "drag", "hp_buffer", "damage_multiplier", "magnet_radius", "primary", "secondaries", "passives"]:
			h.check(old.get(key) == ship.get(key), "%s retains %s" % [ship.id, key])
		for tier: int in range(1, 7):
			h.check(is_equal_approx(_hp(old, tier), _hp(ship, tier)), "%s preserves limb HP at actual spawn tier %d" % [ship.id, tier])
		for part: PartDefinition in ship.parts:
			if part.style == 5: h.check(not part.solid, "%s guide has no collider" % ship.id)
		var decoded: Dictionary = ShipAuthoring.from_json(ShipAuthoring.to_json(ship))
		h.check(decoded.errors.is_empty() and ShipCompiler.grammar_signature(decoded.ship) == ShipCompiler.grammar_signature(ship), "%s geometry metadata survives JSON" % ship.id)
	print("Geometry census: %d -> %d circles across 146 hulls" % [before_count, after_count])
	h.check(after_count > 0, "The complete fleet census is nonempty; per-hull budgets, weapons and HP are checked above")
	var subject: ShipDefinition = RailRoster.build(RailRoster.manifest()[-1])
	ShipCompiler.compile(subject)
	var broken: ShipDefinition = subject.duplicate(true)
	broken.parts.erase(_part(broken, "r3s0_spoke"))
	h.control("valid ancestry but deleted outer spoke", not ShipGrammar.validate_compiled(broken).is_empty())
	broken = subject.duplicate(true)
	_part(broken, "r3s0_spoke").from_id = "r2"
	h.control("a structural line ending on an orbit guide", not ShipGrammar.validate_compiled(broken).is_empty())
	broken = subject.duplicate(true)
	_part(broken, "r3s0").integrated_host = "core"
	h.control("an external solid circle pretending to be an integrated marking", not ShipGrammar.validate_compiled(broken).is_empty())
	broken = subject.duplicate(true)
	var glyph: String = "r3s0w0"
	for i: int in range(broken.parts.size() - 1, -1, -1):
		if broken.parts[i].shape == "line" and (broken.parts[i].from_id == glyph or broken.parts[i].to_id == glyph): broken.parts.remove_at(i)
	h.control("an unconnected non-solid weapon glyph", not ShipGrammar.validate_compiled(broken).is_empty())
	_test_migration(h)
	_test_identity_rng(h)
	for id: String in SetPieceCatalog.ids():
		h.check(SetPieceCatalog.get_piece(id, false).circles == SetPieceCatalog.PIECES[id].circles, "%s custom geometry keeps every authored bead" % id)
		h.check(SetPieceCatalog.get_piece(id).muzzle == SetPieceCatalog.PIECES[id].muzzle and SetPieceCatalog.get_piece(id).ability == SetPieceCatalog.PIECES[id].ability, "%s compact glyph preserves muzzle and weapon" % id)
	_test_cached_encounter(h)
	_test_fresh_rewards(h)
	h.finish(self)

func _test_identity_rng(h: RefCounted) -> void:
	var old: ShipDefinition = RailRoster.baseline_ship("player_lightning_t6_heavy")
	var revised: ShipDefinition = old.duplicate(true)
	ShipRecipe.clean_geometry(revised)
	ShipCompiler.compile(old)
	ShipCompiler.compile(revised)
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w._rng.seed = 74017
	var initial: int = w._rng.state
	var before: Dictionary = w._make_actor(91, "lightning", 4, Vector2(900, 500), 1, false)
	w._configure_actor(before, old, true)
	var old_state: int = w._rng.state
	w._rng.state = initial
	var after: Dictionary = w._make_actor(91, "lightning", 4, Vector2(900, 500), 1, false)
	w._configure_actor(after, revised, true)
	h.check(w._rng.state == old_state, "Removed pods and cosmetic beads never perturb encounter RNG")
	for i: int in before.gun_indices:
		var index: int = after.rig.index_of(before.rig.ids[i])
		h.check(is_equal_approx(before.part_cd[i], after.part_cd[index]) and is_equal_approx(before.part_aim_error[i], after.part_aim_error[index]), "A retained gun keeps its initial cadence and aim noise by identity")
	var old_cd: PackedFloat32Array = after.part_cd.duplicate()
	var old_aim: PackedFloat32Array = after.part_aim_error.duplicate()
	w._configure_actor(after, revised, false)
	h.check(after.part_cd == old_cd and after.part_aim_error == old_aim, "Reconfiguration preserves cooldown and deterministic aim noise")
	w.free()

func _totals(actor: Dictionary) -> Vector3:
	var result: Vector3 = Vector3.ZERO
	for i: int in range(1, actor.rig.ids.size()):
		result.y += float(actor.part_max_hp[i])
		if bool(actor.part_attached[i]):
			result.x += float(actor.part_hp[i])
			result.z += float(actor.part_reward_share[i])
	return result

func _test_migration(h: RefCounted) -> void:
	var old: ShipDefinition = RailRoster.baseline_ship("player_lightning_t6_heavy")
	var revised: ShipDefinition = old.duplicate(true)
	ShipRecipe.clean_geometry(revised)
	ShipCompiler.compile(old)
	ShipCompiler.compile(revised)
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 40, [], Vector2(500, 500))
	for dead_hub: bool in [false, true]:
		var actor: Dictionary = w._make_actor(91, "lightning", 4, Vector2(900, 500), 1, false)
		w._configure_actor(actor, old, true)
		var rig: ShipMotion.ShipRig = actor.rig
		actor.part_hp[rig.index_of("r2s0p2")] *= 0.4
		w._damage_part(actor, rig.index_of("r2s0p3"), 100000, w.player)
		if dead_hub: w._damage_part(actor, rig.index_of("r2s0"), 100000, w.player)
		var totals: Vector3 = _totals(actor)
		var unpaid: float = actor.reward_unpaid_limb
		var encoded: Dictionary = CombatPersistence.encode_parts(actor)
		encoded.erase("geometry_revision") # literal pre-redesign snapshot format
		if dead_hub:
			# Simulate decorations introduced since the save: missing values start attached
			# during configure, and must inherit the saved detached host after apply_parts.
			for i: int in range(rig.index_of("r2s0") + 1, rig.index_of("r2s0") + rig.subtree_size[rig.index_of("r2s0")]):
				if rig.solid[i] != 0: continue
				for field: String in ["hp","max_hp","cd","egg_cd","aim","attached","reward_share"]:
					(encoded[field] as Dictionary).erase(rig.ids[i])
		var migrated: Dictionary = CombatPersistence.migrate_parts(encoded, revised)
		h.check(CombatPersistence.migrate_parts(migrated, revised) == migrated, "Migration is idempotent, dead hub=%s" % dead_hub)
		w._configure_actor(actor, revised, false)
		CombatPersistence.apply_parts(w, actor, encoded)
		h.check(_totals(actor).is_equal_approx(totals), "Migration preserves saved remaining/max HP and only unpaid limb shares, dead hub=%s" % dead_hub)
		h.check(is_equal_approx(actor.reward_unpaid_limb, unpaid), "Migration leaves actor reward pools alone")
		var hub: int = actor.rig.index_of("r2s0")
		h.check(bool(actor.part_attached[hub]) != dead_hub, "Migration never resurrects a detached hub")
		if dead_hub: _assert_detached_glyphs(h, actor, "r2s0", "Missing saved glyph state")
		var saved: Dictionary = CombatPersistence.encode_parts(actor)
		CombatPersistence.apply_parts(w, actor, saved)
		h.check(_totals(actor).is_equal_approx(totals), "New snapshots reload without healing or duplicating rewards")
		w._clear_encounter()
	w.free()

func _assert_detached_glyphs(h: RefCounted, actor: Dictionary, hub_id: String, context: String) -> void:
	var rig: ShipMotion.ShipRig = actor.rig
	var hub: int = rig.index_of(hub_id)
	var glyphs: int = 0
	for i: int in range(hub + 1, hub + rig.subtree_size[hub]):
		if rig.solid[i] != 0: continue
		glyphs += 1
		h.check(not bool(actor.part_attached[i]) and float(actor.part_hp[i]) == 0.0, "%s: %s stays detached with its host" % [context, rig.ids[i]])
	h.check(glyphs > 0, context + " exercises actual non-solid glyph descendants")

func _test_cached_encounter(h: RefCounted) -> void:
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	w.setup_player("neutral", 1, 40, [], Vector2(500, 500))
	var old: ShipDefinition = RailRoster.baseline_ship("boss_lightning")
	ShipCompiler.compile(old)
	var actor: Dictionary = w._make_actor(91, "lightning", 4, Vector2(900, 500), 1, true)
	actor.hull_id = old.id
	w._configure_actor(actor, old, true)
	w.enemies.append(actor)
	w.actors_by_id[int(actor.id)] = actor
	actor.part_hp[actor.rig.index_of("r2s1")] *= 0.45
	w._damage_part(actor, actor.rig.index_of("r3s0p0"), 100000, w.player)
	w._damage_part(actor, actor.rig.index_of("r4s0"), 100000, w.player)
	w._flush_debris()
	var totals: Vector3 = _totals(actor)
	var remaining: float = float(actor.reward_remaining)
	var unpaid: float = float(actor.reward_unpaid_limb)
	var legacy: Dictionary = CombatPersistence.encounter_snapshot(w)
	(legacy.enemies[0].parts as Dictionary).erase("geometry_revision")
	var key: String = "geometry-revision-cold-cache"
	CombatPersistence.cache_encounter(w, key, legacy)
	h.check(w.encounter_records.has(key), "Legacy encounter is stored in the compressed cache")
	w.sector_cache.clear()
	h.check(not w.sector_cache.has(key), "Cold restore cannot use the decoded cache")
	var decoded: Dictionary = CombatPersistence.read_cached_encounter(w, key)
	h.check(decoded == legacy, "Compressed cache decodes the original revision-1 encounter without changing it")
	CombatPersistence.restore_encounter(w, decoded)
	h.check(w.enemies.size() == 1, "Cold encounter restores the original enemy count")
	var restored: Dictionary = w.enemies[0]
	h.check(restored.definition.geometry_revision == 1 and restored.hull_id == "boss_lightning", "Cold restore retains the saved revision-1 anatomy")
	h.check(_totals(restored).is_equal_approx(totals), "Cold restore preserves remaining HP, maximum HP and unpaid limb shares")
	h.check(is_equal_approx(float(restored.reward_remaining), remaining) and is_equal_approx(float(restored.reward_unpaid_limb), unpaid), "Cold restore preserves both actor reward pools")
	h.check(CombatPersistence.json_value(w.pickups) == legacy.pickups, "Cold restore preserves already-paid detached-limb pickups exactly")
	_assert_detached_glyphs(h, restored, "r4s0", "Cold encounter restore")
	h.check(not (decoded.enemies[0].parts as Dictionary).has("geometry_revision"), "Restoring does not mutate the cached legacy payload")
	var updated: Dictionary = CombatPersistence.encounter_snapshot(w)
	h.check(int(updated.enemies[0].parts.geometry_revision) == 1, "Resaving preserves the actor's original geometry revision")
	CombatPersistence.cache_encounter(w, key, updated)
	w.sector_cache.clear()
	CombatPersistence.restore_encounter(w, CombatPersistence.read_cached_encounter(w, key))
	h.check(_totals(w.enemies[0]).is_equal_approx(totals), "Repeated compressed cache restores without healing or duplicating shares")
	h.check(CombatPersistence.encounter_snapshot(w) == updated, "Repeated compressed restore is idempotent for all serialized encounter state")
	w.free()

func _test_fresh_rewards(h: RefCounted) -> void:
	var w: CombatWorld = World.new()
	w.visuals_enabled = false
	root.add_child(w)
	w.set_physics_process(false)
	for id: String in ["boss_lightning", "enemy_chain_lightning_t2"]:
		var old: ShipDefinition = RailRoster.baseline_ship(id)
		ShipCompiler.compile(old)
		for tier: int in [1, 4, 6]:
			var rival: bool = id.begins_with("boss_")
			var previous: Dictionary = w._make_actor(90, "lightning", tier, Vector2(900, 500), 1, rival)
			w._configure_actor(previous, old, true)
			var current: Dictionary = w._spawn_named_enemy(id, "lightning", tier, Vector2(900, 500), rival, false)
			h.check(not current.is_empty() and current.definition.geometry_revision == 3, "%s T%d spawns revised geometry" % [id, tier])
			h.check(_totals(previous).is_equal_approx(_totals(current)), "%s T%d preserves freshly allocated limb HP and reward shares" % [id, tier])
			h.check(is_equal_approx(float(previous.hp), float(current.hp)) and is_equal_approx(float(previous.reward_remaining), float(current.reward_remaining)) and is_equal_approx(float(previous.reward_unpaid_limb), float(current.reward_unpaid_limb)), "%s T%d preserves core health and both fresh reward pools" % [id, tier])
			var budget: float = float((80 + 30 * tier) if rival else (24 + 10 * tier))
			h.check(is_equal_approx(_totals(current).z, float(current.reward_unpaid_limb)) and is_equal_approx(float(current.reward_remaining) + float(current.reward_unpaid_limb), budget), "%s T%d allocates every reward exactly once" % [id, tier])
			w._clear_encounter()
	w.free()
