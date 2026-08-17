extends GdUnitTestSuite

## Unit tests for SkillSet (ARCH "Subsystem: Skills"): use-based leveling, the
## labor→skill multiplier mapping, ColonistDef.starting_skills seeding, and the
## save round-trip. Curves are overridden with small values where threshold math
## matters; the shipped skills.tres defaults drive the labor-map tests.

var _skill_set: SkillSet
var _progress_events: Array = []
var _level_events: Array = []


func before_test() -> void:
	_skill_set = SkillSet.new()
	auto_free(_skill_set)
	# In the tree so _ready builds the labor map from the shipped skills.tres —
	# the labor-mapping tests below exercise the real catalog.
	add_child(_skill_set)
	_progress_events = []
	_level_events = []
	_skill_set.skill_progressed.connect(
		func(skill_id: String, progress: int): _progress_events.append([skill_id, progress]))
	_skill_set.skill_leveled_up.connect(
		func(skill_id: String, level: int): _level_events.append([skill_id, level]))


## A SkillSet with a tiny use_curve [2, 4] (L2 at 2 uses, L3 at 4) for the given
## labor, in the tree so _ready builds the labor map from it.
func _make_set_with_curve(labor: String, use_curve: Array[int]) -> SkillSet:
	var def := SkillDef.new()
	auto_free(def)
	def.skill_id = labor
	def.display_name = labor
	def.labor = labor
	def.use_curve = use_curve
	var list := SkillDefList.new()
	auto_free(list)
	list.skills = [def]
	var ss := SkillSet.new()
	auto_free(ss)
	ss.skill_defs = list
	add_child(ss)
	return ss


# ── Seeding ───────────────────────────────────────────────────────────────────

func test_seed_sets_level_and_progress() -> void:
	_skill_set.seed({"construction": {"xp": 5, "level": 2}})
	assert_int(_skill_set.get_level("construction")).is_equal(2)
	assert_int(_skill_set.skills["construction"]["progress"]).is_equal(5)


func test_seed_clamps_out_of_range_levels() -> void:
	_skill_set.seed({"construction": {"xp": 0, "level": 9}})
	assert_int(_skill_set.get_level("construction")).is_equal(5)


func test_seed_ignores_skills_not_in_the_catalog() -> void:
	# "tree_chopping" IS in the catalog (a leftover entry without a labor) —
	# this must be an id nothing declares.
	_skill_set.seed({"unknown_skill": {"xp": 99, "level": 4}})
	assert_bool(_skill_set.skills.has("unknown_skill")).is_false()


func test_unseeded_skill_reads_as_level_one() -> void:
	assert_int(_skill_set.get_level("construction")).is_equal(1)


# ── record_use + leveling ─────────────────────────────────────────────────────

func test_record_use_increments_progress_and_emits() -> void:
	_skill_set.record_use("construction")
	_skill_set.record_use("construction")
	assert_int(_skill_set.skills["construction"]["progress"]).is_equal(2)
	assert_int(_progress_events.size()).is_equal(2)


func test_record_use_ignores_unknown_skill() -> void:
	_skill_set.record_use("unknown_skill")
	assert_bool(_skill_set.skills.has("unknown_skill")).is_false()
	assert_int(_progress_events.size()).is_equal(0)


func test_level_up_at_curve_threshold() -> void:
	var ss := _make_set_with_curve("construction", [2, 4])
	ss.record_use("construction")
	assert_int(ss.get_level("construction")).is_equal(1)
	ss.record_use("construction")
	assert_int(ss.get_level("construction")).is_equal(2)
	ss.record_use("construction")
	ss.record_use("construction")
	assert_int(ss.get_level("construction")).is_equal(3)


func test_level_caps_at_five() -> void:
	var ss := _make_set_with_curve("construction", [1, 1, 1, 1])
	for i in range(10):
		ss.record_use("construction")
	assert_int(ss.get_level("construction")).is_equal(5)


func test_leveled_up_signal_emits_on_crossing() -> void:
	var ss := _make_set_with_curve("construction", [2])
	var events: Array = []
	ss.skill_leveled_up.connect(
		func(skill_id: String, level: int): events.append([skill_id, level]))
	ss.record_use("construction")
	ss.record_use("construction")
	assert_int(events.size()).is_equal(1)
	assert_str(events[0][0]).is_equal("construction")
	assert_int(events[0][1]).is_equal(2)


# ── Labor mapping + multiplier ────────────────────────────────────────────────

func test_multiplier_follows_labor_skill_level() -> void:
	# skills.tres defaults: multipliers [1.0, 1.2, 1.4, 1.7, 2.0].
	_skill_set.seed({"construction": {"xp": 0, "level": 2}})
	assert_float(_skill_set.get_multiplier("construction")).is_equal(1.2)


func test_unskilled_labor_multiplier_is_one() -> void:
	# hauling maps to no skill in the shipped catalog.
	assert_float(_skill_set.get_multiplier("hauling")).is_equal(1.0)


func test_l1_multiplier_is_one() -> void:
	assert_float(_skill_set.get_multiplier("construction")).is_equal(1.0)


func test_meets_requirement_at_and_below_level() -> void:
	_skill_set.seed({"construction": {"xp": 0, "level": 2}})
	assert_bool(_skill_set.meets_requirement("construction", 1)).is_true()
	assert_bool(_skill_set.meets_requirement("construction", 2)).is_true()
	assert_bool(_skill_set.meets_requirement("construction", 3)).is_false()


func test_record_use_for_labor_grants_xp_for_skilled_labor() -> void:
	assert_bool(_skill_set.record_use_for_labor("construction")).is_true()
	assert_int(_skill_set.skills["construction"]["progress"]).is_equal(1)


func test_record_use_for_labor_noop_for_unskilled_labor() -> void:
	assert_bool(_skill_set.record_use_for_labor("hauling")).is_false()
	assert_bool(_skill_set.skills.has("hauling")).is_false()


# ── Save round-trip ───────────────────────────────────────────────────────────

func test_serialize_round_trip_preserves_state() -> void:
	# "unknown_skill" is not in the catalog, so seeding drops it — state only
	# round-trips what the catalog declares.
	_skill_set.seed({"construction": {"xp": 0, "level": 2}, "unknown_skill": {"xp": 1, "level": 1}})
	_skill_set.record_use("construction")
	var restored := SkillSet.new()
	auto_free(restored)
	add_child(restored) # in-tree so _ready builds the labor map
	restored.deserialize(_skill_set.serialize())
	assert_int(restored.get_level("construction")).is_equal(2)
	assert_int(restored.skills["construction"]["progress"]).is_equal(1)
	assert_bool(restored.skills.has("unknown_skill")).is_false()
	assert_float(restored.get_multiplier("construction")).is_equal(1.2)
