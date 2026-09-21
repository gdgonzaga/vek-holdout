extends GdUnitTestSuite

## Player equip/unequip: a held item MOVES out of the carry inventory (the colonist
## contract), so it is not listed, weighed, dropped or deposited as cargo while held.
## Content-agnostic: in-memory ItemDefs registered in ItemDB for the test only.

const PlayerScene = preload("res://subsystems/player/player.tscn")

var _previous_defs: Dictionary = {}


func after_test() -> void:
	for item_id: String in _previous_defs:
		if _previous_defs[item_id] != null:
			ItemDB._defs_by_id[item_id] = _previous_defs[item_id]
		else:
			ItemDB._defs_by_id.erase(item_id)
	_previous_defs.clear()


func _register_item(item_id: String, tags: Array[String], weight: float = 1.0) -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new())
	def.id = item_id
	def.tags = tags
	def.weight = weight
	if not _previous_defs.has(item_id):
		_previous_defs[item_id] = ItemDB._defs_by_id.get(item_id, null)
	ItemDB._defs_by_id[item_id] = def
	return def


func _spawn_player() -> Player:
	var player: Player = PlayerScene.instantiate()
	auto_free(player)
	add_child(player)
	return player


func test_equip_item_moves_the_item_out_of_the_inventory() -> void:
	# Break caught: leaving the item in the inventory lets the player hold it AND deposit/drop it.
	var player := _spawn_player()
	var axe := _register_item("test_equip_axe", ["tool"])
	player.inventory.add("test_equip_axe", 2)

	var result: Equipment.EquipResult = player.equip_item(axe)

	assert_int(result).is_equal(Equipment.EquipResult.OK)
	assert_str(player.get_equipped_item().id).is_equal("test_equip_axe")
	assert_int(player.inventory.get_item_count("test_equip_axe")).is_equal(1)


func test_equip_item_swaps_the_held_item_back_into_the_inventory() -> void:
	var player := _spawn_player()
	var sword := _register_item("test_equip_sword", ["weapon"])
	var pistol := _register_item("test_equip_pistol", ["weapon"])
	var pick := _register_item("test_equip_pick", ["tool"])
	player.inventory.add("test_equip_sword", 1)
	player.inventory.add("test_equip_pistol", 1)
	player.inventory.add("test_equip_pick", 1)
	player.equip_item(sword)    # main hand
	player.equip_item(pistol)   # the sword moves to the free holster
	player.equip_item(pick)     # holster taken, so the pistol from the hand returns to the inventory

	assert_str(player.get_equipped_item().id).is_equal("test_equip_pick")
	assert_str(player.equipment.get_item(Equipment.SLOT_HOLSTER).id).is_equal("test_equip_sword")
	assert_int(player.inventory.get_item_count("test_equip_pistol")).is_equal(1)
	assert_int(player.inventory.get_item_count("test_equip_pick")).is_equal(0)


func test_equip_item_reports_when_the_item_is_not_carried() -> void:
	var player := _spawn_player()
	var axe := _register_item("test_equip_axe", ["tool"])

	assert_int(player.equip_item(axe)).is_equal(Equipment.EquipResult.NOT_CARRIED)
	assert_object(player.get_equipped_item()).is_null()


func test_unequip_slot_returns_the_item_to_the_inventory() -> void:
	var player := _spawn_player()
	var axe := _register_item("test_equip_axe", ["tool"])
	player.inventory.add("test_equip_axe", 1)
	player.equip_item(axe)

	var ok: bool = player.unequip_slot(Equipment.SLOT_MAIN_HAND)

	assert_bool(ok).is_true()
	assert_object(player.get_equipped_item()).is_null()
	assert_int(player.inventory.get_item_count("test_equip_axe")).is_equal(1)


func test_unequip_slot_is_refused_when_the_inventory_is_full() -> void:
	var player := _spawn_player()
	var axe := _register_item("test_equip_axe", ["tool"], 5.0)
	player.inventory.add("test_equip_axe", 1)
	player.equip_item(axe)
	# Fill the pack so the axe has no room to come back.
	var filler := _register_item("test_equip_filler", ["material"], 1.0)
	player.inventory.add("test_equip_filler", int(player.inventory.capacity))

	var ok: bool = player.unequip_slot(Equipment.SLOT_MAIN_HAND)

	assert_bool(ok).is_false()
	assert_str(player.get_equipped_item().id).is_equal("test_equip_axe")
	assert_int(player.inventory.get_item_count("test_equip_axe")).is_equal(0)
	assert_object(filler).is_not_null()


func test_dropped_item_lands_where_the_player_is_looking() -> void:
	# Break caught: drop direction read from the body basis, which never rotates (only the
	# camera rig and the visuals turn), so every drop flew toward world -Z.
	var player := _spawn_player()
	_register_item("test_drop_crate", ["tool"])
	player.inventory.add("test_drop_crate", 1)
	# A +90 degree rig yaw turns -Z forward into -X (hand-derived: rotating (0,0,-1) about Y by +90 gives (-1,0,0)).
	player._rig.set_orientation(deg_to_rad(90.0), 0.0)

	var dropped: WorldItem = player.drop_item("test_drop_crate", 1)
	auto_free(dropped)

	var offset := dropped.global_position - player.global_position
	assert_float(offset.x).is_less(-0.5)
	assert_float(offset.z).is_equal_approx(0.0, 0.1)


func test_a_held_item_cannot_be_dropped_as_cargo() -> void:
	# Break caught: drop_item used to unequip the last copy; a held item is now simply not carried.
	var player := _spawn_player()
	var axe := _register_item("test_equip_axe", ["tool"])
	player.inventory.add("test_equip_axe", 1)
	player.equip_item(axe)

	var dropped: WorldItem = player.drop_item("test_equip_axe", 1)

	assert_object(dropped).is_null()
	assert_str(player.get_equipped_item().id).is_equal("test_equip_axe")
