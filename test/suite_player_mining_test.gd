extends GdUnitTestSuite

## Player LMB mining against a small real Map holding both grids (MiningRig).
## The Map owns BOTH grids, which is what makes ancestry-only lookups claim every hit, so each
## test places its "terrain" wall under the node that should own the struck collider.

const MiningRig = preload("res://test/helpers/mining_rig.gd")


func test_lmb_on_a_placed_block_damages_the_blocky_grid_only() -> void:
	# Break caught: the Map ancestor (or the current map) hands back the smooth grid for every
	# hit, so mining a placed block carves terrain at its cell and the block never takes damage.
	var rig := MiningRig.new(self)
	rig.add_wall(rig.blocky.get_terrain())
	var player := await rig.spawn_aimed_player()

	player.get_node("InputComponent").primary_action_pressed.emit()

	assert_int(rig.blocky.damage_calls).is_equal(1)
	assert_int(rig.smooth.damage_calls).is_equal(0)


func test_lmb_on_terrain_damages_the_smooth_grid_only() -> void:
	# Break caught: the mirror case — terrain hits must reach the smooth grid and never the blocky one.
	var rig := MiningRig.new(self)
	rig.add_wall(rig.smooth.get_terrain())
	var player := await rig.spawn_aimed_player()

	player.get_node("InputComponent").primary_action_pressed.emit()

	assert_int(rig.smooth.damage_calls).is_equal(1)
	assert_int(rig.blocky.damage_calls).is_equal(0)


func test_lmb_on_something_no_grid_owns_damages_nothing() -> void:
	# Break caught: furniture, colonists and other bodies under the Map get "mined" as terrain at
	# their own position because the Map ancestor resolves to its smooth grid.
	var rig := MiningRig.new(self)
	rig.add_wall(rig.furniture_container)
	var player := await rig.spawn_aimed_player()

	player.get_node("InputComponent").primary_action_pressed.emit()

	assert_int(rig.smooth.damage_calls).is_equal(0)
	assert_int(rig.blocky.damage_calls).is_equal(0)


func test_smooth_terrain_swing_damage_comes_from_the_mining_tool() -> void:
	# Break caught: swing damage hardcoded in the interactor, so retuning mining (or handing the
	# player a better tool) needs a script edit instead of a data edit.
	var rig := MiningRig.new(self)
	rig.add_wall(rig.smooth.get_terrain())
	var player := await rig.spawn_aimed_player()
	player.interactor.mining_tool = _tool_dealing(7)

	player.get_node("InputComponent").primary_action_pressed.emit()

	assert_array(rig.smooth.damage_amounts).is_equal([7])


func test_block_swing_damage_comes_from_the_mining_tool() -> void:
	# Break caught: the blocky path keeping its own literal after the smooth path was fixed.
	var rig := MiningRig.new(self)
	rig.add_wall(rig.blocky.get_terrain())
	var player := await rig.spawn_aimed_player()
	player.interactor.mining_tool = _tool_dealing(9)

	player.get_node("InputComponent").primary_action_pressed.emit()

	assert_array(rig.blocky.damage_amounts).is_equal([9])


## Auxiliary: A DigToolParams whose swing does `damage` HP.
func _tool_dealing(damage: int) -> DigToolParams:
	var mining_tool := DigToolParams.new()
	mining_tool.swing_damage = damage
	return mining_tool
