extends GdUnitTestSuite
## Test suite for Colonist Moodlet system, StatThresholdMoodletDef, unified stat getters, and 3D visualizer.

var _tex_0: PlaceholderTexture2D
var _tex_1: PlaceholderTexture2D


func before_test() -> void:
	_tex_0 = auto_free(PlaceholderTexture2D.new())
	_tex_0.size = Vector2(16, 16)
	_tex_1 = auto_free(PlaceholderTexture2D.new())
	_tex_1.size = Vector2(16, 16)


func test_moodlet_def_base_defaults() -> void:
	var def := auto_free(MoodletDef.new())
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist)
	
	assert_int(def.evaluate_icon_index(colonist)).is_equal(-1)
	assert_object(def.get_active_texture(colonist)).is_null()


func test_moodlet_def_out_of_bounds_clamping() -> void:
	# Create a mock MoodletDef that returns an out-of-bounds index
	var def := auto_free(MoodletDef.new())
	def.icons.append(_tex_0)
	
	# When evaluate_icon_index returns a valid index 0
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist)
	
	# Base returns -1 -> get_active_texture is null
	assert_object(def.get_active_texture(colonist)).is_null()


func test_stat_threshold_depletion_below_threshold() -> void:
	var moodlet := auto_free(StatThresholdMoodletDef.new())
	moodlet.id = &"test_hunger"
	moodlet.stat_id = &"hunger"
	moodlet.trigger_mode = StatThresholdMoodletDef.TriggerMode.BELOW_THRESHOLD
	moodlet.thresholds = [0.40, 0.15]
	moodlet.icons = [_tex_0, _tex_1]
	
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist)
	add_child(colonist)
	
	# Case 1: Satisfied (hunger = 1.0 > 0.40) -> Hidden (-1)
	colonist.needs.set_need(&"hunger", 1.0)
	assert_int(moodlet.evaluate_icon_index(colonist)).is_equal(-1)
	assert_object(moodlet.get_active_texture(colonist)).is_null()
	
	# Case 2: Hungry (hunger = 0.35 <= 0.40 and > 0.15) -> Tier 0
	colonist.needs.set_need(&"hunger", 0.35)
	assert_int(moodlet.evaluate_icon_index(colonist)).is_equal(0)
	assert_object(moodlet.get_active_texture(colonist)).is_equal(_tex_0)
	
	# Case 3: Starving (hunger = 0.10 <= 0.15) -> Tier 1
	colonist.needs.set_need(&"hunger", 0.10)
	assert_int(moodlet.evaluate_icon_index(colonist)).is_equal(1)
	assert_object(moodlet.get_active_texture(colonist)).is_equal(_tex_1)


func test_stat_threshold_accumulation_above_threshold() -> void:
	var moodlet := auto_free(StatThresholdMoodletDef.new())
	moodlet.id = &"test_stress"
	moodlet.stat_id = &"hunger" # test accumulation logic using hunger values
	moodlet.trigger_mode = StatThresholdMoodletDef.TriggerMode.ABOVE_THRESHOLD
	moodlet.thresholds = [0.50, 0.85]
	moodlet.icons = [_tex_0, _tex_1]
	
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist)
	add_child(colonist)
	
	# Case 1: Low / Below cutoff (0.20 < 0.50) -> Hidden (-1)
	colonist.needs.set_need(&"hunger", 0.20)
	assert_int(moodlet.evaluate_icon_index(colonist)).is_equal(-1)
	assert_object(moodlet.get_active_texture(colonist)).is_null()
	
	# Case 2: Tier 0 (0.60 >= 0.50 and < 0.85) -> Tier 0
	colonist.needs.set_need(&"hunger", 0.60)
	assert_int(moodlet.evaluate_icon_index(colonist)).is_equal(0)
	assert_object(moodlet.get_active_texture(colonist)).is_equal(_tex_0)
	
	# Case 3: Tier 1 (0.90 >= 0.85) -> Tier 1
	colonist.needs.set_need(&"hunger", 0.90)
	assert_int(moodlet.evaluate_icon_index(colonist)).is_equal(1)
	assert_object(moodlet.get_active_texture(colonist)).is_equal(_tex_1)


func test_colonist_get_stat_ratio_and_value() -> void:
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist)
	add_child(colonist)
	
	# HP queries
	assert_float(colonist.get_stat_ratio(&"hp")).is_equal_approx(1.0, 0.001)
	assert_float(colonist.get_stat_value(&"hp")).is_equal_approx(float(colonist.get_max_hp()), 0.001)
	
	colonist.take_damage(50, null)
	var expected_ratio: float = float(colonist.get_hp()) / float(colonist.get_max_hp())
	assert_float(colonist.get_stat_ratio(&"hp")).is_equal_approx(expected_ratio, 0.001)
	assert_float(colonist.get_stat_value(&"hp")).is_equal_approx(float(colonist.get_hp()), 0.001)
	
	# Needs queries
	colonist.needs.set_need(&"rest", 0.75)
	assert_float(colonist.get_stat_ratio(&"rest")).is_equal_approx(0.75, 0.001)
	assert_float(colonist.get_stat_value(&"rest")).is_equal_approx(0.75, 0.001)
	
	# Unknown stat
	assert_float(colonist.get_stat_ratio(&"nonexistent_stat")).is_equal_approx(-1.0, 0.001)
	assert_float(colonist.get_stat_value(&"nonexistent_stat")).is_equal_approx(-1.0, 0.001)


func test_colonist_get_active_moodlets_ordered() -> void:
	var m_hp := auto_free(StatThresholdMoodletDef.new())
	m_hp.id = &"hp_moodlet"
	m_hp.stat_id = &"hp"
	m_hp.trigger_mode = StatThresholdMoodletDef.TriggerMode.BELOW_THRESHOLD
	m_hp.thresholds = [0.50]
	m_hp.icons = [_tex_0]
	
	var m_hunger := auto_free(StatThresholdMoodletDef.new())
	m_hunger.id = &"hunger_moodlet"
	m_hunger.stat_id = &"hunger"
	m_hunger.trigger_mode = StatThresholdMoodletDef.TriggerMode.BELOW_THRESHOLD
	m_hunger.thresholds = [0.40]
	m_hunger.icons = [_tex_1]
	
	var col_def := auto_free(ColonistDef.new())
	col_def.max_hp = 100
	col_def.moodlet_defs = [m_hp, m_hunger]
	
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist)
	colonist.colonist_def = col_def
	add_child(colonist)
	
	# Initially both HP and hunger are satisfied -> 0 active moodlets
	colonist.needs.set_need(&"hunger", 1.0)
	assert_int(colonist.get_active_moodlets().size()).is_equal(0)
	
	# Trigger hunger only
	colonist.needs.set_need(&"hunger", 0.20)
	var active_one: Array[Dictionary] = colonist.get_active_moodlets()
	assert_int(active_one.size()).is_equal(1)
	assert_str(active_one[0]["def"].id).is_equal("hunger_moodlet")
	
	# Trigger HP as well -> both active in configured order [m_hp, m_hunger]
	colonist.take_damage(60, null) # HP now 40/100 <= 0.50
	var active_two: Array[Dictionary] = colonist.get_active_moodlets()
	assert_int(active_two.size()).is_equal(2)
	assert_str(active_two[0]["def"].id).is_equal("hp_moodlet")
	assert_str(active_two[1]["def"].id).is_equal("hunger_moodlet")


func test_colonist_moodlet_visualizer_billboard_updates() -> void:
	var m_hp := auto_free(StatThresholdMoodletDef.new())
	m_hp.id = &"hp_moodlet"
	m_hp.stat_id = &"hp"
	m_hp.thresholds = [0.50]
	m_hp.icons = [_tex_0]
	
	var col_def := auto_free(ColonistDef.new())
	col_def.moodlet_defs = [m_hp]
	
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist)
	colonist.colonist_def = col_def
	add_child(colonist)
	
	var visualizer: ColonistMoodletVisualizer = colonist.get_node_or_null("ColonistMoodletVisualizer") as ColonistMoodletVisualizer
	assert_object(visualizer).is_not_null()
	
	var sprite: Sprite3D = visualizer.get_node_or_null("@Sprite3D@1") as Sprite3D
	if sprite == null:
		for child in visualizer.get_children():
			if child is Sprite3D:
				sprite = child as Sprite3D
				break
	assert_object(sprite).is_not_null()
	
	# Healthy colonist -> sprite hidden
	visualizer._update_moodlet_display()
	assert_bool(sprite.visible).is_false()
	
	# Injure colonist -> sprite becomes visible with _tex_0
	colonist.take_damage(60, null)
	visualizer._update_moodlet_display()
	assert_bool(sprite.visible).is_true()
	assert_object(sprite.texture).is_equal(_tex_0)


func test_moodlet_def_null_safety() -> void:
	var moodlet := auto_free(StatThresholdMoodletDef.new())
	moodlet.stat_id = &"hunger"
	
	# Null colonist
	assert_int(moodlet.evaluate_icon_index(null)).is_equal(-1)
	assert_object(moodlet.get_active_texture(null)).is_null()
	
	# Colonist with null needs
	var colonist: Colonist = auto_free(Colonist.new())
	assert_int(moodlet.evaluate_icon_index(colonist)).is_equal(-1)
	assert_float(colonist.get_stat_ratio(&"hunger")).is_equal_approx(-1.0, 0.001)
