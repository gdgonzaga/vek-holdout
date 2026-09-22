extends GdUnitTestSuite
## Test suite for EnemyBase moodlet queries, StatThresholdMoodletDef evaluation, and EnemyMoodletVisualizer 3D billboards.
## Content-agnostic: damage amounts are derived from the loaded archetype's own
## HealthComponent stats at runtime (R9), never hardcoded against a shipped
## enemy's HP/durability numbers.

var _tex_0: PlaceholderTexture2D
var _tex_1: PlaceholderTexture2D


func before_test() -> void:
	_tex_0 = auto_free(PlaceholderTexture2D.new())
	_tex_0.size = Vector2(16, 16)
	_tex_1 = auto_free(PlaceholderTexture2D.new())
	_tex_1.size = Vector2(16, 16)


func test_enemy_stat_ratio_and_value() -> void:
	var enemy_scene: PackedScene = load("res://subsystems/combat/enemies/enemy_swarmer/enemy_swarmer.tscn")
	var enemy: EnemyBase = auto_free(enemy_scene.instantiate() as EnemyBase)
	add_child(enemy)

	# Initial full health
	assert_float(enemy.get_stat_ratio(&"hp")).is_equal_approx(1.0, 0.001)
	assert_float(enemy.get_stat_ratio(&"health")).is_equal_approx(1.0, 0.001)
	assert_float(enemy.get_stat_value(&"hp")).is_equal_approx(float(enemy.health_component.max_hp), 0.001)
	assert_float(enemy.get_stat_value(&"max_hp")).is_equal_approx(float(enemy.health_component.max_hp), 0.001)

	var max_hp := enemy.health_component.max_hp
	# Drain durability, then remove half of max_hp -- the ratio must land at 0.5 regardless of archetype.
	var hp_loss := int(max_hp / 2.0)
	enemy.take_damage(_damage_past_durability(enemy, hp_loss))
	var expected_ratio := float(max_hp - hp_loss) / float(max_hp)
	assert_float(enemy.get_stat_ratio(&"hp")).is_equal_approx(expected_ratio, 0.001)
	assert_float(enemy.get_stat_value(&"hp")).is_equal_approx(float(max_hp - hp_loss), 0.001)

	# Unknown stat returns -1.0
	assert_float(enemy.get_stat_ratio(&"nonexistent_stat")).is_equal_approx(-1.0, 0.001)
	assert_float(enemy.get_stat_value(&"nonexistent_stat")).is_equal_approx(-1.0, 0.001)


func test_enemy_moodlet_threshold_evaluation() -> void:
	var moodlet: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	moodlet.id = &"enemy_health"
	moodlet.display_name = "Injured"
	moodlet.stat_id = &"hp"
	moodlet.trigger_mode = StatThresholdMoodletDef.TriggerMode.BELOW_THRESHOLD
	moodlet.thresholds = [0.60, 0.25]
	moodlet.icons = [_tex_0, _tex_1]

	var enemy_scene: PackedScene = load("res://subsystems/combat/enemies/enemy_swarmer/enemy_swarmer.tscn")
	var enemy: EnemyBase = auto_free(enemy_scene.instantiate() as EnemyBase)
	enemy.enemy_def = enemy.enemy_def.duplicate()
	enemy.enemy_def.moodlet_defs = [moodlet]
	add_child(enemy)

	# Case 1: Full health (1.0 > 0.60) -> Inactive
	assert_int(moodlet.evaluate_icon_index(enemy)).is_equal(-1)
	assert_object(moodlet.get_active_texture(enemy)).is_null()
	assert_array(enemy.get_active_moodlets()).is_empty()

	# Case 2: Wounded to 55% of max_hp -- inside (0.25, 0.60] -> Tier 0.
	var max_hp := enemy.health_component.max_hp
	var loss_to_55 := int(round(float(max_hp) * 0.45))
	enemy.take_damage(_damage_past_durability(enemy, loss_to_55))
	assert_int(moodlet.evaluate_icon_index(enemy)).is_equal(0)
	assert_object(moodlet.get_active_texture(enemy)).is_equal(_tex_0)

	var active: Array[Dictionary] = enemy.get_active_moodlets()
	assert_int(active.size()).is_equal(1)
	assert_int(active[0]["index"]).is_equal(0)
	assert_object(active[0]["texture"]).is_equal(_tex_0)
	assert_str(active[0]["name"]).is_equal("Injured")

	# Case 3: Wounded further to 15% of max_hp -- at or below 0.25 -> Tier 1.
	var loss_to_15 := int(round(float(max_hp) * 0.85))
	enemy.take_damage(loss_to_15 - loss_to_55)
	assert_int(moodlet.evaluate_icon_index(enemy)).is_equal(1)
	assert_object(moodlet.get_active_texture(enemy)).is_equal(_tex_1)

	active = enemy.get_active_moodlets()
	assert_int(active.size()).is_equal(1)
	assert_int(active[0]["index"]).is_equal(1)
	assert_object(active[0]["texture"]).is_equal(_tex_1)


func test_enemy_moodlet_visualizer_billboard_updates() -> void:
	var moodlet: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	moodlet.id = &"enemy_hp_status"
	moodlet.display_name = "Damaged"
	moodlet.stat_id = &"hp"
	moodlet.trigger_mode = StatThresholdMoodletDef.TriggerMode.BELOW_THRESHOLD
	moodlet.thresholds = [0.50]
	moodlet.icons = [_tex_0]

	var enemy_scene: PackedScene = load("res://subsystems/combat/enemies/enemy_swarmer/enemy_swarmer.tscn")
	var enemy: EnemyBase = auto_free(enemy_scene.instantiate() as EnemyBase)
	enemy.enemy_def = enemy.enemy_def.duplicate()
	enemy.enemy_def.moodlet_defs = [moodlet]
	add_child(enemy)

	var visualizer: EnemyMoodletVisualizer = enemy.get_node_or_null("EnemyMoodletVisualizer") as EnemyMoodletVisualizer
	assert_object(visualizer).is_not_null()

	# Full HP -> billboard inactive / sprite not visible
	visualizer._update_moodlet_display()
	assert_bool(visualizer._sprites[0].visible).is_false()

	# Damage to 40% of max_hp -- below the 50% threshold.
	var max_hp := enemy.health_component.max_hp
	var loss_to_40 := int(round(float(max_hp) * 0.60))
	enemy.take_damage(_damage_past_durability(enemy, loss_to_40))
	visualizer._update_moodlet_display()
	assert_bool(visualizer._sprites[0].visible).is_true()
	assert_object(visualizer._sprites[0].texture).is_equal(_tex_0)

	# Heal back up by the same fraction of max_hp -> comfortably above the threshold again.
	enemy.health_component.heal(loss_to_40)
	visualizer._update_moodlet_display()
	assert_bool(visualizer._sprites[0].visible).is_false()


func test_enemy_moodlet_visualizer_multi_line_layout_and_skip() -> void:
	var def_line0: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	def_line0.stat_id = &"hp"
	def_line0.thresholds = [0.80]
	def_line0.icons = [_tex_0]
	def_line0.line_number = 0

	var def_line1: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	def_line1.stat_id = &"hp"
	def_line1.thresholds = [0.20] # only triggers under 20%
	def_line1.icons = [_tex_0]
	def_line1.line_number = 1

	var def_line2: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	def_line2.stat_id = &"hp"
	def_line2.thresholds = [0.60]
	def_line2.icons = [_tex_1]
	def_line2.line_number = 2

	var enemy_scene: PackedScene = load("res://subsystems/combat/enemies/enemy_swarmer/enemy_swarmer.tscn")
	var enemy: EnemyBase = auto_free(enemy_scene.instantiate() as EnemyBase)
	enemy.enemy_def = enemy.enemy_def.duplicate()
	enemy.enemy_def.moodlet_defs = [def_line0, def_line1, def_line2]
	add_child(enemy)

	var visualizer: EnemyMoodletVisualizer = enemy.get_node_or_null("EnemyMoodletVisualizer") as EnemyMoodletVisualizer
	assert_object(visualizer).is_not_null()

	# Damage to roughly half HP:
	# Line 0 (threshold 0.80) is active
	# Line 1 (threshold 0.20) is inactive -> skipped!
	# Line 2 (threshold 0.60) is active
	var max_hp := enemy.health_component.max_hp
	var loss_to_50 := int(round(float(max_hp) * 0.50))
	enemy.take_damage(_damage_past_durability(enemy, loss_to_50))
	visualizer._update_moodlet_display()

	assert_bool(visualizer._sprites[0].visible).is_true()
	assert_bool(visualizer._sprites[1].visible).is_true()
	assert_float(visualizer._sprites[0].position.y).is_equal_approx(visualizer.height_offset, 0.001)
	# Line 2 should be compacted to row index 1 (height_offset + 1 * line_spacing)
	assert_float(visualizer._sprites[1].position.y).is_equal_approx(visualizer.height_offset + visualizer.line_spacing, 0.001)


# ===================
# Auxiliary Functions
# ===================

func _damage_past_durability(enemy: EnemyBase, hp_loss: int) -> int:
	## Auxiliary: total damage (from full health) needed to drain this enemy's current
	## durability and then remove exactly hp_loss from its HP, so callers can target a
	## specific HP ratio without hardcoding the archetype's shipped HP/durability numbers.
	return enemy.health_component.current_durability + hp_loss
