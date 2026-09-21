extends GdUnitTestSuite

## LMB dispatch while the player holds an item in main hand. An item with a primary action
## owns LMB (the action fires, or the press is swallowed while the action is in its lockout),
## and an item with none leaves LMB to interaction and mining. Aimed at a terrain wall so a
## press that wrongly falls through shows up as smooth-grid damage.
## Content-agnostic: the item and its action are in-memory doubles registered in ItemDB for
## the test only.

const MiningRig = preload("res://test/helpers/mining_rig.gd")

const TOOL_ID := "test_primary_action_tool"

var _previous_def: ItemDef = null


## EquipActionParams double: counts executions instead of doing anything.
class RecordingEquipAction extends EquipActionParams:
	var fired: int = 0

	func execute(_actor: Node) -> void:
		fired += 1


func before_test() -> void:
	_previous_def = ItemDB._defs_by_id.get(TOOL_ID, null)


func after_test() -> void:
	if _previous_def != null:
		ItemDB._defs_by_id[TOOL_ID] = _previous_def
	else:
		ItemDB._defs_by_id.erase(TOOL_ID)


func test_lmb_fires_the_equipped_items_primary_action() -> void:
	# Break caught: the equipped item's action not running, or running AND letting the same press
	# fall through to mining the wall.
	var rig := MiningRig.new(self)
	rig.add_wall(rig.smooth.get_terrain())
	var action: RecordingEquipAction = RecordingEquipAction.new()
	var player := await rig.spawn_aimed_player()
	_equip_tool_with(player, action)

	player.get_node("InputComponent").primary_action_pressed.emit()

	assert_int(action.fired).is_equal(1)
	assert_int(rig.smooth.damage_calls).is_equal(0)


func test_lmb_inside_the_lockout_is_swallowed_not_passed_on() -> void:
	# Break caught: clicking faster than the action's lockout either re-firing it or, worse, falling
	# through to mining whatever is under the crosshair while the weapon is still recovering.
	var rig := MiningRig.new(self)
	rig.add_wall(rig.smooth.get_terrain())
	var action: RecordingEquipAction = RecordingEquipAction.new()
	action.cooldown_seconds = 5.0
	var player := await rig.spawn_aimed_player()
	_equip_tool_with(player, action)
	var lmb: Signal = player.get_node("InputComponent").primary_action_pressed

	lmb.emit()
	lmb.emit()

	assert_int(action.fired).is_equal(1)
	assert_int(rig.smooth.damage_calls).is_equal(0)


func test_an_item_with_no_primary_action_leaves_lmb_to_mining() -> void:
	# Break caught: any equippable item in main hand swallowing LMB even though it has nothing to
	# run, so the player can no longer mine or interact while holding it.
	var rig := MiningRig.new(self)
	rig.add_wall(rig.smooth.get_terrain())
	var player := await rig.spawn_aimed_player()
	_equip_tool_with(player, null)

	player.get_node("InputComponent").primary_action_pressed.emit()

	assert_int(rig.smooth.damage_calls).is_equal(1)


func test_a_dead_player_cannot_mine() -> void:
	# Break caught: the LMB handler only checking mode and UI gates, so a corpse keeps mining.
	var rig := MiningRig.new(self)
	rig.add_wall(rig.smooth.get_terrain())
	var player := await rig.spawn_aimed_player()
	player.take_damage(1000)

	player.get_node("InputComponent").primary_action_pressed.emit()

	assert_int(rig.smooth.damage_calls).is_equal(0)


func test_lmb_is_ignored_while_a_tool_mode_owns_the_cursor() -> void:
	# Break caught: mining under the crosshair while placing a blueprint or drawing a designation box.
	var rig := MiningRig.new(self)
	rig.add_wall(rig.smooth.get_terrain())
	var player := await rig.spawn_aimed_player()
	player.mode = Player.Mode.BUILD_PLACEMENT

	player.get_node("InputComponent").primary_action_pressed.emit()

	assert_int(rig.smooth.damage_calls).is_equal(0)


# --- Fixtures ----------------------------------------------------------------

## Auxiliary: Registers an in-memory tool whose EquippableParams carries `primary_action` (or
## none), carries one, and equips it into main hand. Asserts the equip so a setup failure can't
## make the tests above pass or fail for the wrong reason.
func _equip_tool_with(player: Player, primary_action: EquipActionParams) -> void:
	var tags: Array[String] = ["tool"]
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = TOOL_ID
	def.tags = tags
	def.weight = 1.0
	var params := EquippableParams.new()
	params.primary_action = primary_action
	def.equippable = params
	ItemDB._defs_by_id[TOOL_ID] = def
	player.inventory.add(TOOL_ID, 1)

	var result: Equipment.EquipResult = player.equip_item(def)

	assert_int(result).is_equal(Equipment.EquipResult.OK)
