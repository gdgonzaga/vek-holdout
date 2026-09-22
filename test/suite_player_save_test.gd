extends GdUnitTestSuite

## Player save/load: state that lives on child components must round-trip through
## serialize()/deserialize(). Content-agnostic: skill state, inventory stacks, and the
## equipped tool are all synthetic in-memory fixtures.

const PlayerScene = preload("res://subsystems/player/player.tscn")

## Synthetic main-hand-eligible item id, registered in ItemDB for this suite only so
## Equipment.deserialize() (which resolves slot contents by id through ItemDB) can restore it.
const _TOOL_ID := "test_player_save_tool"
## Synthetic plain carry stack id — never registered in ItemDB, proving inventory round trips
## raw stacks without needing a def (Inventory.serialize()/deserialize() never consult ItemDB).
const _STACK_ID := "test_player_save_stack"

var _previous_tool_def: ItemDef = null


func before_test() -> void:
	_previous_tool_def = ItemDB._defs_by_id.get(_TOOL_ID, null)


func after_test() -> void:
	# Restore whatever ItemDB held for the synthetic tool id before this test touched it.
	if _previous_tool_def != null:
		ItemDB._defs_by_id[_TOOL_ID] = _previous_tool_def
	else:
		ItemDB._defs_by_id.erase(_TOOL_ID)
	_previous_tool_def = null


func test_skill_progress_survives_save_and_load() -> void:
	# Break caught: serialize() omitted skill_set, so trained levels reset to L1 on load.
	var player := _spawn_player()
	player.skill_set.skills["test_skill"] = {"level": 3, "progress": 7}

	var saved := player.serialize()

	var restored := _spawn_player()
	restored.deserialize(saved)
	assert_int(restored.skill_set.get_level("test_skill")).is_equal(3)
	assert_int(int(restored.skill_set.skills.get("test_skill", {}).get("progress", -1))).is_equal(7)


func test_loading_a_save_clears_leftover_motion() -> void:
	# Break caught: a restored player keeping the velocity it had when the load happened, so it
	# slides off (or falls through) its restored position.
	var player := _spawn_player()
	var saved := player.serialize()
	player.velocity = Vector3(3.0, -5.0, 2.0)

	player.deserialize(saved)

	assert_vector(player.velocity).is_equal(Vector3.ZERO)


func test_full_round_trip_restores_every_serialized_field() -> void:
	# Break caught: deserialize() forgetting a component (equipment, needs, health), so a loaded
	# save quietly resets that one piece of state to its defaults instead of restoring it.
	# 1. Tool Registration: Registers a synthetic main-hand-eligible ItemDef so equip and restore
	#    can both resolve it by id.
	var tool := _register_test_tool()
	var player := _spawn_player()
	# 2. Non-Default State: Pushes every field serialize() writes away from its spawn default.
	_give_player_non_default_state(player, tool)

	var saved := player.serialize()
	var restored := _spawn_player()
	restored.deserialize(saved)

	# 3. Full Field Verification: Confirms every field the round trip touched survived intact.
	_assert_state_matches(restored, tool)


## Auxiliary: Instantiates player.tscn into the test tree.
func _spawn_player() -> Player:
	var player: Player = auto_free(PlayerScene.instantiate())
	add_child(player)
	return player


## Auxiliary: Registers a synthetic main-hand-eligible tool in ItemDB for this test only.
func _register_test_tool() -> ItemDef:
	var tool: ItemDef = auto_free(ItemDef.new())
	tool.id = _TOOL_ID
	var tags: Array[String] = ["tool"]
	tool.tags = tags
	ItemDB._defs_by_id[_TOOL_ID] = tool
	return tool


## Auxiliary: Drives every serialized field away from its spawn default: position, camera
## orientation, a carried stack, an equipped tool, a need level, and HP.
func _give_player_non_default_state(player: Player, tool: ItemDef) -> void:
	player.global_position = Vector3(12.5, 3.0, -7.25)
	player._rig.set_orientation(deg_to_rad(40.0), deg_to_rad(-15.0))
	player.inventory.items[_STACK_ID] = 5
	player.inventory.items[_TOOL_ID] = 2
	var equip_result: Equipment.EquipResult = player.equip_item(tool)
	assert_int(equip_result).is_equal(Equipment.EquipResult.OK)
	player.needs.set_need(&"hunger", 0.42)
	player.health_component.max_hp = 150
	player.health_component.current_hp = 47


## Auxiliary: Asserts every field _give_player_non_default_state set survived the round trip.
func _assert_state_matches(restored: Player, tool: ItemDef) -> void:
	assert_vector(restored.global_position).is_equal_approx(Vector3(12.5, 3.0, -7.25), Vector3.ONE * 0.01)
	assert_float(restored._rig.get_yaw()).is_equal_approx(deg_to_rad(40.0), 0.001)
	assert_float(restored._rig.get_pitch()).is_equal_approx(deg_to_rad(-15.0), 0.001)
	assert_int(restored.inventory.get_item_count(_STACK_ID)).is_equal(5)
	assert_int(restored.inventory.get_item_count(_TOOL_ID)).is_equal(1)
	assert_object(restored.equipment.get_item(Equipment.SLOT_MAIN_HAND)).is_same(tool)
	assert_float(restored.needs.get_need(&"hunger")).is_equal_approx(0.42, 0.001)
	assert_int(restored.health_component.max_hp).is_equal(150)
	assert_int(restored.health_component.current_hp).is_equal(47)
