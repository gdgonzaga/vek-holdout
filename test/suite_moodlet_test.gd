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
	var def: MoodletDef = auto_free(MoodletDef.new()) as MoodletDef
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist) as Colonist
	
	assert_int(def.evaluate_icon_index(colonist)).is_equal(-1)
	assert_object(def.get_active_texture(colonist)).is_null()


func test_moodlet_def_out_of_bounds_clamping() -> void:
	# Create a mock MoodletDef that returns an out-of-bounds index
	var def: MoodletDef = auto_free(MoodletDef.new()) as MoodletDef
	def.icons.append(_tex_0)
	
	# When evaluate_icon_index returns a valid index 0
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist) as Colonist
	
	# Base returns -1 -> get_active_texture is null
	assert_object(def.get_active_texture(colonist)).is_null()


func test_stat_threshold_depletion_below_threshold() -> void:
	var moodlet: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
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
	var moodlet: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	moodlet.id = &"test_stress"
	moodlet.stat_id = &"hunger" # test accumulation logic using hunger values
	moodlet.trigger_mode = StatThresholdMoodletDef.TriggerMode.ABOVE_THRESHOLD
	moodlet.thresholds = [0.50, 0.85]
	moodlet.icons = [_tex_0, _tex_1]
	
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist) as Colonist
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
	var m_hp: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	m_hp.id = &"hp_moodlet"
	m_hp.stat_id = &"hp"
	m_hp.trigger_mode = StatThresholdMoodletDef.TriggerMode.BELOW_THRESHOLD
	m_hp.thresholds = [0.50]
	m_hp.icons = [_tex_0]
	
	var m_hunger: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	m_hunger.id = &"hunger_moodlet"
	m_hunger.stat_id = &"hunger"
	m_hunger.trigger_mode = StatThresholdMoodletDef.TriggerMode.BELOW_THRESHOLD
	m_hunger.thresholds = [0.40]
	m_hunger.icons = [_tex_1]
	
	var col_def: ColonistDef = auto_free(ColonistDef.new()) as ColonistDef
	col_def.max_hp = 100
	col_def.moodlet_defs = [m_hp, m_hunger]
	
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist) as Colonist
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
	var m_hp: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	m_hp.id = &"hp_moodlet"
	m_hp.stat_id = &"hp"
	m_hp.thresholds = [0.50]
	m_hp.icons = [_tex_0]
	
	var col_def: ColonistDef = auto_free(ColonistDef.new()) as ColonistDef
	col_def.moodlet_defs = [m_hp]
	
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist) as Colonist
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
	var moodlet: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	moodlet.stat_id = &"hunger"
	
	# Null colonist
	assert_int(moodlet.evaluate_icon_index(null)).is_equal(-1)
	assert_object(moodlet.get_active_texture(null)).is_null()
	
	# Colonist with null needs
	var colonist: Colonist = auto_free(Colonist.new()) as Colonist
	assert_int(moodlet.evaluate_icon_index(colonist)).is_equal(-1)
	assert_float(colonist.get_stat_ratio(&"hunger")).is_equal_approx(-1.0, 0.001)


func test_colonist_get_current_activity_and_job_resolution() -> void:
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist) as Colonist
	add_child(colonist)
	
	# Default activity should be idle
	assert_str(String(colonist.get_current_activity())).is_equal("idle")
	
	# Blackboard goal takes precedence (e.g. need goals)
	if colonist.bt_player and colonist.bt_player.blackboard:
		colonist.bt_player.blackboard.set_var(&"current_goal", &"eat")
		assert_str(String(colonist.get_current_activity())).is_equal("eat")
		
		colonist.bt_player.blackboard.set_var(&"current_goal", &"rest")
		assert_str(String(colonist.get_current_activity())).is_equal("rest")
		
		# When goal is work, resolve labor_id from current_job
		colonist.bt_player.blackboard.set_var(&"current_goal", &"work")
		var mock_job: Job = auto_free(Job.new()) as Job
		mock_job.labor_id = "mining"
		colonist.current_job = mock_job
		assert_str(String(colonist.get_current_activity())).is_equal("mining")
		
		# When goal is work but no job is assigned, should resolve to idle
		colonist.current_job = null
		assert_str(String(colonist.get_current_activity())).is_equal("idle")


func test_activity_moodlet_def_evaluation() -> void:
	var moodlet: ActivityMoodletDef = auto_free(ActivityMoodletDef.new()) as ActivityMoodletDef
	moodlet.id = &"activity"
	moodlet.activity_icon_map = {
		&"idle": 0,
		&"mining": 1,
	}
	moodlet.icons = [_tex_0, _tex_1]
	
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist) as Colonist
	add_child(colonist)
	
	# Default activity (idle -> icon 0)
	assert_int(moodlet.evaluate_icon_index(colonist)).is_equal(0)
	assert_object(moodlet.get_active_texture(colonist)).is_equal(_tex_0)
	
	# Mining activity (mining -> icon 1)
	var mock_job: Job = auto_free(Job.new()) as Job
	mock_job.labor_id = "mining"
	colonist.current_job = mock_job
	assert_int(moodlet.evaluate_icon_index(colonist)).is_equal(1)
	assert_object(moodlet.get_active_texture(colonist)).is_equal(_tex_1)
	
	# Unmapped activity -> -1 / null
	mock_job.labor_id = "unmapped_labor"
	assert_int(moodlet.evaluate_icon_index(colonist)).is_equal(-1)
	assert_object(moodlet.get_active_texture(colonist)).is_null()
	
	# Null colonist -> -1 / null
	assert_int(moodlet.evaluate_icon_index(null)).is_equal(-1)
	assert_object(moodlet.get_active_texture(null)).is_null()


func test_colonist_moodlet_visualizer_multi_moodlet_row() -> void:
	var m_hp: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	m_hp.id = &"hp_moodlet"
	m_hp.stat_id = &"hp"
	m_hp.thresholds = [0.50]
	m_hp.icons = [_tex_0]
	
	var m_act: ActivityMoodletDef = auto_free(ActivityMoodletDef.new()) as ActivityMoodletDef
	m_act.id = &"act_moodlet"
	m_act.activity_icon_map = { &"mining": 0 }
	m_act.icons = [_tex_1]
	
	var col_def: ColonistDef = auto_free(ColonistDef.new()) as ColonistDef
	col_def.moodlet_defs = [m_hp, m_act]
	
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist) as Colonist
	colonist.colonist_def = col_def
	add_child(colonist)
	
	var visualizer: ColonistMoodletVisualizer = colonist.get_node_or_null("ColonistMoodletVisualizer") as ColonistMoodletVisualizer
	assert_object(visualizer).is_not_null()
	
	# Set colonist to mining and injure them -> both moodlets active
	var mock_job: Job = auto_free(Job.new()) as Job
	mock_job.labor_id = "mining"
	colonist.current_job = mock_job
	colonist.take_damage(60, null)
	
	visualizer._update_moodlet_display()
	
	var sprites: Array[Sprite3D] = []
	for child in visualizer.get_children():
		if child is Sprite3D and (child as Sprite3D).visible:
			sprites.append(child as Sprite3D)
	
	assert_int(sprites.size()).is_equal(2)
	assert_object(sprites[0].texture).is_equal(_tex_0)
	assert_object(sprites[1].texture).is_equal(_tex_1)


func test_moodlet_def_icon_hframes_resolution() -> void:
	var m_def: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	m_def.stat_id = &"hunger"
	m_def.thresholds = [0.75, 0.25]
	m_def.icons = [_tex_0, _tex_1]
	m_def.icon_hframes = [1, 4]
	
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist) as Colonist
	add_child(colonist)
	
	# Tier 0 (hunger = 0.50 <= 0.75) -> hframes = 1
	colonist.needs.set_need(&"hunger", 0.50)
	assert_int(m_def.get_hframes(colonist)).is_equal(1)
	
	# Tier 1 (hunger = 0.10 <= 0.25) -> hframes = 4
	colonist.needs.set_need(&"hunger", 0.10)
	assert_int(m_def.get_hframes(colonist)).is_equal(4)
	
	# FPS resolution: default 6.0, tier override
	assert_float(m_def.get_fps(colonist)).is_equal_approx(6.0, 0.001)
	m_def.icon_fps = [4.0, 12.0]
	assert_float(m_def.get_fps(colonist)).is_equal_approx(12.0, 0.001)
	
	# Unconfigured tier -> defaults to 1
	m_def.icon_hframes = []
	assert_int(m_def.get_hframes(colonist)).is_equal(1)


func test_colonist_moodlet_visualizer_multi_line_layout_and_skip() -> void:
	var def_line0: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	def_line0.stat_id = &"hp"
	def_line0.thresholds = [0.50]
	def_line0.icons = [_tex_0]
	def_line0.line_number = 0
	
	var def_line1: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	def_line1.stat_id = &"hunger"
	def_line1.thresholds = [0.50]
	def_line1.icons = [_tex_0]
	def_line1.line_number = 1
	
	var def_line2: ActivityMoodletDef = auto_free(ActivityMoodletDef.new()) as ActivityMoodletDef
	def_line2.activity_icon_map = { "mining": 0 }
	def_line2.icons = [_tex_1]
	def_line2.line_number = 2
	
	var colonist_def: ColonistDef = auto_free(ColonistDef.new()) as ColonistDef
	colonist_def.moodlet_defs = [def_line0, def_line1, def_line2]
	
	var colonist_scene: PackedScene = load("res://subsystems/colonists/colonist.tscn")
	var colonist: Colonist = auto_free(colonist_scene.instantiate() as Colonist) as Colonist
	colonist.colonist_def = colonist_def
	add_child(colonist)
	
	var visualizer: ColonistMoodletVisualizer = colonist.get_node_or_null("ColonistMoodletVisualizer") as ColonistMoodletVisualizer
	assert_object(visualizer).is_not_null()
	
	# Case 1: Line 0 (HP <= 0.5) and Line 2 (mining) active, Line 1 (hunger = 1.0 > 0.5) inactive -> Line 1 skipped
	colonist.take_damage(60, null)
	colonist.needs.set_need(&"hunger", 1.0) # Line 1 inactive
	var mock_job: Job = auto_free(Job.new()) as Job
	mock_job.labor_id = "mining"
	colonist.current_job = mock_job # Line 2 active
	
	visualizer._update_moodlet_display()
	
	assert_bool(visualizer._sprites[0].visible).is_true()
	assert_bool(visualizer._sprites[1].visible).is_true()
	assert_float(visualizer._sprites[0].position.y).is_equal_approx(visualizer.height_offset, 0.001)
	# Line 2 should be compacted to row index 1 (height_offset + 1 * line_spacing)
	assert_float(visualizer._sprites[1].position.y).is_equal_approx(visualizer.height_offset + visualizer.line_spacing, 0.001)
	
	# Case 2: Line 1 becomes active (hunger = 0.20 <= 0.5) -> All 3 lines active
	colonist.needs.set_need(&"hunger", 0.20)
	visualizer._update_moodlet_display()
	
	assert_bool(visualizer._sprites[0].visible).is_true()
	assert_bool(visualizer._sprites[1].visible).is_true()
	assert_bool(visualizer._sprites[2].visible).is_true()
	assert_float(visualizer._sprites[0].position.y).is_equal_approx(visualizer.height_offset, 0.001)
	assert_float(visualizer._sprites[1].position.y).is_equal_approx(visualizer.height_offset + visualizer.line_spacing, 0.001)
	assert_float(visualizer._sprites[2].position.y).is_equal_approx(visualizer.height_offset + 2.0 * visualizer.line_spacing, 0.001)




