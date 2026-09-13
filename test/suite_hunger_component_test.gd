extends GdUnitTestSuite

## Unit tests for hunger decay, starvation transitions, damage ticks, and restoration on consolidated ColonistNeeds.

const ColonistNeedsScript = preload("res://subsystems/ai/colonist_needs.gd")


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
	var needs: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	needs._ready()
	needs.set_need(&"hunger", 0.001)

	var depleted_fired: Array[StringName] = []
	needs.need_depleted.connect(func(need_id: StringName) -> void: depleted_fired.append(need_id))

	# Advance decay past zero (decay is 3.75/hr = ~0.00104/sec; 2.0s is plenty)
	needs._process(2.0)

	assert_float(needs.get_need(&"hunger")).is_equal_approx(0.0, 0.001)
	assert_bool(needs.is_depleted(&"hunger")).is_true()
	assert_bool(depleted_fired.has(&"hunger")).is_true()
	assert_float(needs.get_speed_multiplier()).is_equal_approx(0.8, 0.001)
	assert_float(needs.get_stamina_recovery_multiplier()).is_equal_approx(0.5, 0.001)


func test_starvation_damage_ticks() -> void:
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


func test_legacy_save_deserialization_fallback() -> void:
	var needs: ColonistNeeds = auto_free(ColonistNeedsScript.new()) as ColonistNeeds
	needs._ready()
	var legacy_data: Dictionary = {
		"current_hunger": 0.42,
		"is_starving": false
	}
	needs.deserialize(legacy_data)
	assert_float(needs.get_need(&"hunger")).is_equal_approx(0.42, 0.001)
