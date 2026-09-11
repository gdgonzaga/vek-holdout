extends GdUnitTestSuite

## Unit tests for HungerComponent starvation, decay, signals, and ColonistNeeds synchronization.

const HungerComponentScript = preload("res://subsystems/colonists/hunger_component.gd")
const ColonistNeedsScript = preload("res://subsystems/ai/colonist_needs.gd")


# =================
# Primary Tests
# =================

func test_hunger_defaults_and_ratios() -> void:
	var comp: HungerComponent = auto_free(HungerComponentScript.new()) as HungerComponent
	comp.max_hunger = 1.0
	comp.current_hunger = 1.0
	
	assert_float(comp.get_hunger_ratio()).is_equal_approx(1.0, 0.001)
	assert_bool(comp.is_starving()).is_false()
	assert_float(comp.get_speed_multiplier()).is_equal_approx(1.0, 0.001)
	assert_float(comp.get_stamina_recovery_multiplier()).is_equal_approx(1.0, 0.001)


func test_hunger_decay_and_starvation_transition() -> void:
	var comp: HungerComponent = auto_free(HungerComponentScript.new()) as HungerComponent
	comp.max_hunger = 1.0
	comp.current_hunger = 0.1
	comp.decay_rate = 0.05
	comp.starvation_damage_interval = 2.0
	comp.starvation_damage = 3

	var started_fired: Array[bool] = []
	comp.starvation_started.connect(func() -> void: started_fired.append(true))

	# Advance decay past zero
	comp._process(2.5)

	assert_float(comp.current_hunger).is_equal_approx(0.0, 0.001)
	assert_bool(comp.is_starving()).is_true()
	assert_bool(started_fired.is_empty()).is_false()
	assert_float(comp.get_speed_multiplier()).is_equal_approx(0.8, 0.001)
	assert_float(comp.get_stamina_recovery_multiplier()).is_equal_approx(0.5, 0.001)


func test_starvation_damage_ticks() -> void:
	var comp: HungerComponent = auto_free(HungerComponentScript.new()) as HungerComponent
	comp.current_hunger = 0.0
	comp.starvation_damage_interval = 2.0
	comp.starvation_damage = 5

	var tick_damage_received: Array[int] = []
	comp.starvation_tick_damage.connect(func(amount: int) -> void: tick_damage_received.append(amount))

	# Advance less than interval -> no damage
	comp._process(1.5)
	assert_int(tick_damage_received.size()).is_equal(0)

	# Advance past interval -> 1 damage tick
	comp._process(1.0)
	assert_int(tick_damage_received.size()).is_equal(1)
	assert_int(tick_damage_received[0]).is_equal(5)


func test_hunger_restoration_ends_starvation() -> void:
	var comp: HungerComponent = auto_free(HungerComponentScript.new()) as HungerComponent
	comp.current_hunger = 0.0
	comp._process(0.1)
	assert_bool(comp.is_starving()).is_true()

	var ended_fired: Array[bool] = []
	comp.starvation_ended.connect(func() -> void: ended_fired.append(true))

	# Restoring hunger ends starvation
	comp.restore_hunger(0.4)
	comp._process(0.01)

	assert_bool(comp.is_starving()).is_false()
	assert_bool(ended_fired.is_empty()).is_false()
	assert_float(comp.get_speed_multiplier()).is_equal_approx(1.0, 0.001)
	assert_float(comp.get_hunger_ratio()).is_equal_approx(0.4, 0.01)


func test_hunger_component_serialization() -> void:
	var comp: HungerComponent = auto_free(HungerComponentScript.new()) as HungerComponent
	comp.current_hunger = 0.25
	comp.max_hunger = 1.0
	comp._starvation_timer = 1.7
	comp.decay_rate = 0.03

	var data: Dictionary = comp.serialize()
	assert_float(float(data["current_hunger"])).is_equal_approx(0.25, 0.001)
	assert_float(float(data["starvation_timer"])).is_equal_approx(1.7, 0.001)

	var restored: HungerComponent = auto_free(HungerComponentScript.new()) as HungerComponent
	restored.deserialize(data)
	assert_float(restored.current_hunger).is_equal_approx(0.25, 0.001)
	assert_float(restored._starvation_timer).is_equal_approx(1.7, 0.001)
	assert_float(restored.decay_rate).is_equal_approx(0.03, 0.001)


func test_colonist_needs_synchronizes_with_hunger_component() -> void:
	var root: Node = auto_free(Node.new()) as Node
	var hunger_comp: HungerComponent = HungerComponentScript.new()
	hunger_comp.name = "HungerComponent"
	hunger_comp.current_hunger = 0.7
	root.add_child(hunger_comp)

	var needs: ColonistNeeds = ColonistNeedsScript.new()
	needs.name = "ColonistNeeds"
	root.add_child(needs)

	# ColonistNeeds reads hunger directly from HungerComponent
	assert_float(needs.get_need(&"hunger")).is_equal_approx(0.7, 0.001)
	assert_float(needs.get_deficit(&"hunger")).is_equal_approx(0.3, 0.001)

	# Setting need through ColonistNeeds updates HungerComponent
	needs.set_need(&"hunger", 0.95)
	assert_float(hunger_comp.current_hunger).is_equal_approx(0.95, 0.001)
	assert_float(needs.get_need(&"hunger")).is_equal_approx(0.95, 0.001)
