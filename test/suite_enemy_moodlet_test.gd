extends GdUnitTestSuite
## Test suite for EnemyBase moodlet queries, StatThresholdMoodletDef evaluation, and EnemyMoodletVisualizer 3D billboards.

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
	
	# Damage enemy (swarmer max_hp = 50, max_durability = 10)
	# 35 damage -> 10 durability absorbed, 25 HP lost -> 25 / 50 = 0.5 ratio
	enemy.take_damage(35)
	assert_float(enemy.get_stat_ratio(&"hp")).is_equal_approx(0.5, 0.001)
	assert_float(enemy.get_stat_value(&"hp")).is_equal_approx(25.0, 0.001)
	
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
	enemy.moodlet_defs = [moodlet]
	add_child(enemy)
	
	# Case 1: Full health (1.0 > 0.60) -> Inactive
	assert_int(moodlet.evaluate_icon_index(enemy)).is_equal(-1)
	assert_object(moodlet.get_active_texture(enemy)).is_null()
	assert_array(enemy.get_active_moodlets()).is_empty()
	
	# Case 2: Wounded (take 35 dmg -> 25/50 HP = 0.50 <= 0.60 and > 0.25) -> Tier 0
	enemy.take_damage(35)
	assert_int(moodlet.evaluate_icon_index(enemy)).is_equal(0)
	assert_object(moodlet.get_active_texture(enemy)).is_equal(_tex_0)
	
	var active: Array[Dictionary] = enemy.get_active_moodlets()
	assert_int(active.size()).is_equal(1)
	assert_int(active[0]["index"]).is_equal(0)
	assert_object(active[0]["texture"]).is_equal(_tex_0)
	assert_str(active[0]["name"]).is_equal("Injured")
	
	# Case 3: Critical (take 15 more dmg -> 10/50 HP = 0.20 <= 0.25) -> Tier 1
	enemy.take_damage(15)
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
	enemy.moodlet_defs = [moodlet]
	add_child(enemy)
	
	var visualizer: EnemyMoodletVisualizer = enemy.get_node_or_null("EnemyMoodletVisualizer") as EnemyMoodletVisualizer
	assert_object(visualizer).is_not_null()
	
	# Full HP -> billboard inactive / sprite not visible
	visualizer._update_moodlet_display()
	assert_bool(visualizer._sprites[0].visible).is_false()
	
	# Damage enemy below 50%
	enemy.take_damage(40) # 10 dur + 30 hp -> 20/50 = 0.40 <= 0.50
	visualizer._update_moodlet_display()
	assert_bool(visualizer._sprites[0].visible).is_true()
	assert_object(visualizer._sprites[0].texture).is_equal(_tex_0)
	
	# Heal back up -> billboard sprite hides
	enemy.health_component.heal(20) # 40/50 = 0.80 > 0.50
	visualizer._update_moodlet_display()
	assert_bool(visualizer._sprites[0].visible).is_false()
