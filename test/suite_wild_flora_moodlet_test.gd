extends GdUnitTestSuite
## Unit tests for the formalized IStatProvider contract (subsystems/core/
## i_stat_provider.gd), the shared MoodletLayoutResolver (subsystems/core/
## moodlet_layout_resolver.gd), and WildFlora's moodlet integration (ARCH
## wild-flora.md "Moodlet System"). Content-agnostic: uses FakeStatProvider
## and synthetic MoodletDefs instead of asserting on real .tres content IDs.

const Doubles = preload("res://test/helpers/doubles.gd")
const ColonySandbox = preload("res://test/helpers/colony_sandbox.gd")

var _sandbox: ColonySandbox
var _furniture_layer: FurnitureLayer
var _tex_0: PlaceholderTexture2D
var _tex_1: PlaceholderTexture2D


func before_test() -> void:
	GameLog.clear()
	_sandbox = ColonySandbox.new(self)
	_furniture_layer = FurnitureLayer.new()
	_furniture_layer.set_container(_sandbox.container)
	_tex_0 = auto_free(PlaceholderTexture2D.new())
	_tex_0.size = Vector2(16, 16)
	_tex_1 = auto_free(PlaceholderTexture2D.new())
	_tex_1.size = Vector2(16, 16)


func after_test() -> void:
	_sandbox.restore()


func _create_test_flora_def(p_id: String) -> WildFloraDef:
	var def := WildFloraDef.new()
	def.id = p_id
	def.display_name = "Test Flora"
	def.hp = 100
	def.tags = ["tree"]
	def.growth_time_hours = 10.0
	def.destroy_on_fruit_harvest = false
	def.regrowth_stage_index = 1

	var stage0 := WildFloraStage.new()
	stage0.min_progress = 0.0
	stage0.max_hp = 30
	stage0.can_harvest_fruit = false

	var stage1 := WildFloraStage.new()
	stage1.min_progress = 0.5
	stage1.max_hp = 60
	stage1.can_harvest_fruit = false

	var stage2 := WildFloraStage.new()
	stage2.min_progress = 1.0
	stage2.max_hp = 100
	stage2.can_harvest_fruit = true
	var item_amount := ItemAmount.new()
	var dummy_item := ItemDef.new()
	dummy_item.id = "test_flora_fruit"
	item_amount.item_def = dummy_item
	item_amount.count = 2
	stage2.harvest_yields = [item_amount]

	def.stages = [stage0, stage1, stage2]
	return def


# =========================================================================
# IStatProvider contract via FakeStatProvider
# =========================================================================

func test_stat_threshold_moodlet_evaluates_fake_stat_provider() -> void:
	var provider: Doubles.FakeStatProvider = auto_free(Doubles.FakeStatProvider.new())
	add_child(provider)

	var moodlet: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	moodlet.stat_id = &"morale"
	moodlet.trigger_mode = StatThresholdMoodletDef.TriggerMode.BELOW_THRESHOLD
	moodlet.thresholds = [0.5]
	moodlet.icons = [_tex_0]

	provider.stat_ratios[&"morale"] = 0.9
	assert_int(moodlet.evaluate_icon_index(provider)).is_equal(-1)

	provider.stat_ratios[&"morale"] = 0.2
	assert_int(moodlet.evaluate_icon_index(provider)).is_equal(0)


func test_activity_moodlet_evaluates_fake_stat_provider() -> void:
	var provider: Doubles.FakeStatProvider = auto_free(Doubles.FakeStatProvider.new())
	add_child(provider)

	var moodlet: ActivityMoodletDef = auto_free(ActivityMoodletDef.new()) as ActivityMoodletDef
	moodlet.activity_icon_map = {&"choppable": 0}
	moodlet.icons = [_tex_0]

	provider.current_activity = &"choppable"
	assert_int(moodlet.evaluate_icon_index(provider)).is_equal(0)

	provider.current_activity = &"unmapped_state"
	assert_int(moodlet.evaluate_icon_index(provider)).is_equal(-1)


# =========================================================================
# MoodletLayoutResolver — the exact 8d42ae5 starvation regression, generic
# =========================================================================

func test_group_moodlets_by_line_caps_rows_independently() -> void:
	var status_def: MoodletDef = auto_free(MoodletDef.new()) as MoodletDef
	status_def.line_number = 4
	var activity_def: MoodletDef = auto_free(MoodletDef.new()) as MoodletDef
	activity_def.line_number = 2

	# 4 status-row entries (would fill a flat cap of 4 on their own) + 1
	# activity-row entry — matches the "colonist has every status moodlet
	# active" scenario 8d42ae5 fixed.
	var valid_moodlets: Array[Dictionary] = []
	for i in range(4):
		valid_moodlets.append({"def": status_def, "index": 0, "texture": _tex_0, "name": ""})
	valid_moodlets.append({"def": activity_def, "index": 0, "texture": _tex_1, "name": ""})

	var grouped: Dictionary = MoodletLayoutResolver.group_moodlets_by_line(valid_moodlets, 4)

	assert_bool(grouped.has(4)).is_true()
	assert_bool(grouped.has(2)).is_true()
	assert_int((grouped[4] as Array).size()).is_equal(4)
	# The activity row must survive uncapped by the status row's volume.
	assert_int((grouped[2] as Array).size()).is_equal(1)

	var active_lines: Array[int] = MoodletLayoutResolver.get_sorted_active_lines(grouped)
	assert_array(active_lines).is_equal([2, 4])
	assert_int(MoodletLayoutResolver.count_grouped_sprites(grouped, active_lines)).is_equal(5)


func test_evaluate_active_moodlets_filters_hidden_and_null_texture() -> void:
	var provider: Doubles.FakeStatProvider = auto_free(Doubles.FakeStatProvider.new())
	add_child(provider)
	provider.stat_ratios[&"hp"] = 1.0

	var hidden_def: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	hidden_def.stat_id = &"hp"
	hidden_def.thresholds = [0.5]
	hidden_def.icons = [_tex_0]

	# Below threshold, but icons empty -> get_active_texture is null -> filtered.
	var no_icon_def: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	no_icon_def.stat_id = &"hp"
	no_icon_def.thresholds = [2.0]

	var defs: Array[MoodletDef] = [hidden_def, no_icon_def]
	var active := MoodletLayoutResolver.evaluate_active_moodlets(provider, defs)
	assert_int(active.size()).is_equal(0)


# =========================================================================
# WildFlora IStatProvider implementation
# =========================================================================

func test_wild_flora_get_stat_ratio_tracks_hp_damage() -> void:
	var def := _create_test_flora_def("test_stat_flora")
	var anchor := Vector3i(2, 0, 2)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var flora := node as WildFlora
	flora.set_growth_progress(1.0)

	assert_float(flora.get_stat_ratio(&"hp")).is_equal_approx(1.0, 0.001)
	flora.take_damage(40)
	assert_float(flora.get_stat_ratio(&"hp")).is_equal_approx(0.6, 0.001)
	assert_float(flora.get_stat_value(&"hp")).is_equal_approx(60.0, 0.001)

	assert_float(flora.get_stat_ratio(&"nonexistent_stat")).is_equal_approx(-1.0, 0.001)


func test_wild_flora_get_current_activity_priority_chain() -> void:
	var def := _create_test_flora_def("test_activity_flora")
	var anchor := Vector3i(4, 0, 4)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var flora := node as WildFlora

	# Unripe, tagged "tree" -> choppable.
	flora.set_growth_progress(0.2)
	assert_str(String(flora.get_current_activity())).is_equal("choppable")

	# Mature with ripe fruit -> forageable takes priority over choppable.
	flora.set_growth_progress(1.0)
	assert_str(String(flora.get_current_activity())).is_equal("forageable")

	# After foraging, regrown to a non-fruiting stage that still bears fruit
	# at another stage -> depleted (not choppable, not forageable).
	flora.forage(null)
	assert_str(String(flora.get_current_activity())).is_equal("depleted")


func test_wild_flora_moodlet_visualizer_billboard_updates() -> void:
	var def := _create_test_flora_def("test_visualizer_flora")
	var hp_moodlet: StatThresholdMoodletDef = auto_free(StatThresholdMoodletDef.new()) as StatThresholdMoodletDef
	hp_moodlet.stat_id = &"hp"
	hp_moodlet.thresholds = [0.5]
	hp_moodlet.icons = [_tex_0]
	def.moodlet_defs = [hp_moodlet]

	var anchor := Vector3i(6, 0, 6)
	var node: Furniture = _furniture_layer.spawn(def, anchor, 0)
	var flora := node as WildFlora
	flora.set_growth_progress(1.0)

	var visualizer: WildFloraMoodletVisualizer = flora.get_node_or_null("WildFloraMoodletVisualizer") as WildFloraMoodletVisualizer
	assert_object(visualizer).is_not_null()

	visualizer._update_moodlet_display()
	assert_bool(visualizer._sprites[0].visible).is_false()

	flora.take_damage(60)
	visualizer._update_moodlet_display()
	assert_bool(visualizer._sprites[0].visible).is_true()
	assert_object(visualizer._sprites[0].texture).is_equal(_tex_0)
