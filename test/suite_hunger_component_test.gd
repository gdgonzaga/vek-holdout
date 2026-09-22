extends GdUnitTestSuite

## Unit tests for hunger decay, starvation transitions, damage ticks, and restoration on consolidated ColonistNeeds.
##
## Content-agnostic per AGENTS.md: the decay/starvation tests inject a synthetic
## hunger NeedDef instead of reading data/needs/need_hunger.tres, so its balance
## values are free to move without breaking these tests.

const ColonistNeedsScript = preload("res://subsystems/ai/colonist_needs.gd")
const NeedDefScript = preload("res://data/schemas/need_def.gd")

var _original_loop_length: float


func before_test() -> void:
	# One real second per game hour makes decay_per_game_hour numerically equal
	# to the per-second decay rate, so expected values are exact by hand.
	_original_loop_length = TimeSystem._loop_length_seconds
	TimeSystem._loop_length_seconds = TimeSystem.HOURS_PER_DAY
	ColonistNeeds._defs_loaded = false
	ColonistNeeds._cached_need_defs.clear()


func after_test() -> void:
	TimeSystem._loop_length_seconds = _original_loop_length
	ColonistNeeds._defs_loaded = false
	ColonistNeeds._cached_need_defs.clear()


func _make_hunger_def(decay_per_game_hour: float, speed_mult: float, stamina_mult: float, damage_interval: float, damage: int) -> NeedDef:
	## Auxiliary: Builds a synthetic hunger NeedDef so decay/starvation math
	## never depends on the shipped need_hunger.tres balance values.
	var def: NeedDef = auto_free(NeedDefScript.new()) as NeedDef
	def.id = &"hunger"
	def.decay_per_game_hour = decay_per_game_hour
	def.depletion_speed_mult = speed_mult
	def.depletion_stamina_mult = stamina_mult
	def.depletion_damage_interval = damage_interval
	def.depletion_damage = damage
	return def


# =================
# Primary Tests
# =================

func test_hunger_defaults_and_ratios() -> void:
	var needs: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	needs._ready()

	assert_float(needs.get_need(&"hunger")).is_equal_approx(1.0, 0.001)
	assert_bool(needs.is_depleted(&"hunger")).is_false()
	assert_float(needs.get_speed_multiplier()).is_equal_approx(1.0, 0.001)
	assert_float(needs.get_stamina_recovery_multiplier()).is_equal_approx(1.0, 0.001)


func test_hunger_decay_and_starvation_transition() -> void:
	ColonistNeeds._cached_need_defs.clear()
	ColonistNeeds._defs_loaded = true
	# 1. Synthetic Def Injection: 0.5/game-hour decay and distinct threshold
	# multipliers so this test cannot silently pass off shipped balance numbers.
	ColonistNeeds._cached_need_defs[&"hunger"] = _make_hunger_def(0.5, 0.6, 0.4, 0.0, 0)

	var needs: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	needs._ready()
	needs.set_need(&"hunger", 0.001)

	var depleted_fired: Array[StringName] = []
	needs.need_depleted.connect(func(need_id: StringName) -> void: depleted_fired.append(need_id))

	# Decay at 0.5/sec (1 real second == 1 game hour, see before_test) drains
	# 0.001 to 0.0 well within 2.0 s.
	needs._process(2.0)

	assert_float(needs.get_need(&"hunger")).is_equal_approx(0.0, 0.001)
	assert_bool(needs.is_depleted(&"hunger")).is_true()
	assert_bool(depleted_fired.has(&"hunger")).is_true()
	assert_float(needs.get_speed_multiplier()).is_equal_approx(0.6, 0.001)
	assert_float(needs.get_stamina_recovery_multiplier()).is_equal_approx(0.4, 0.001)


func test_starvation_damage_ticks() -> void:
	ColonistNeeds._cached_need_defs.clear()
	ColonistNeeds._defs_loaded = true
	# 1. Synthetic Def Injection: a 2 HP tick every 5.0 s of starvation, so the
	# damage total below is a literal this test derives by hand, not the code's own formula.
	ColonistNeeds._cached_need_defs[&"hunger"] = _make_hunger_def(0.5, 1.0, 1.0, 5.0, 2)

	var root: Node = auto_free(Node.new()) as Node
	var needs: ColonistNeeds = ColonistNeedsScript.new()
	root.add_child(needs)
	needs._ready()
	needs.set_need(&"hunger", 0.0)

	var tick_damage_received: Array[int] = []
	needs.depletion_tick_damage.connect(func(need_id: StringName, amount: int) -> void:
		if need_id == &"hunger":
			tick_damage_received.append(amount)
	)

	# Advance less than interval (interval is 5.0s) -> no damage
	needs._process(3.0)
	assert_int(tick_damage_received.size()).is_equal(0)

	# Advance past interval (3.0s + 2.5s = 5.5s >= 5.0s) -> 1 damage tick of 2 HP
	needs._process(2.5)
	assert_int(tick_damage_received.size()).is_equal(1)
	assert_int(tick_damage_received[0]).is_equal(2)

	# Advance to 10.0 s of total starvation -> a second tick fires; 2 ticks of
	# 2 HP each means exactly 4 HP of accumulated damage.
	needs._process(4.5)
	assert_int(tick_damage_received.size()).is_equal(2)
	var total_damage := 0
	for amount: int in tick_damage_received:
		total_damage += amount
	assert_int(total_damage).is_equal(4)


func test_hunger_restoration_ends_starvation() -> void:
	var needs: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	needs._ready()
	needs.set_need(&"hunger", 0.0)
	needs._process(0.1)
	assert_bool(needs.is_depleted(&"hunger")).is_true()

	var replenished_fired: Array[StringName] = []
	needs.need_replenished.connect(func(need_id: StringName) -> void: replenished_fired.append(need_id))

	# Restoring hunger ends starvation
	needs.restore_need(&"hunger", 0.4)

	assert_bool(needs.is_depleted(&"hunger")).is_false()
	assert_bool(replenished_fired.has(&"hunger")).is_true()
	assert_float(needs.get_speed_multiplier()).is_equal_approx(1.0, 0.001)
	assert_float(needs.get_need(&"hunger")).is_equal_approx(0.4, 0.001)


func test_colonist_needs_serialization() -> void:
	var needs: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	needs._ready()
	needs.set_need(&"hunger", 0.25)
	needs.set_need(&"rest", 0.6)
	needs._depletion_timers[&"hunger"] = 1.7

	var data: Dictionary = needs.serialize()
	var restored: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	restored._ready()
	restored.deserialize(data)

	assert_float(restored.get_need(&"hunger")).is_equal_approx(0.25, 0.001)
	assert_float(restored.get_need(&"rest")).is_equal_approx(0.6, 0.001)
	assert_float(float(restored._depletion_timers.get(&"hunger", 0.0))).is_equal_approx(1.7, 0.001)
