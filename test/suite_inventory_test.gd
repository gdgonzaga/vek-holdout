extends GdUnitTestSuite

## Unit tests for the Inventory system (Inventory, add, remove, transfer_to).

const Doubles = preload("res://test/helpers/doubles.gd")

# ── Test doubles ────────────────────────────────────────────────────────────────

## Mock ItemDefs with known weights.
var _wood: ItemDef
var _stone: ItemDef


func before_test() -> void:
	_wood = ItemDef.new()
	_wood.weight = 2.0
	auto_free(_wood)

	_stone = ItemDef.new()
	_stone.weight = 5.0
	auto_free(_stone)


## Helper: creates a MockInventory with the given capacity and mock defs wired up.
func _make_inventory(capacity: float, defs: Dictionary) -> Inventory:
	var inv := Doubles.MockInventory.new()
	inv.capacity = capacity
	inv._defs = defs
	auto_free(inv)
	return inv


# ── add() — core logic ────────────────────────────────────────────────────────

func test_add_single_item() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	var overflow := inv.add("wood", 1)
	assert_int(overflow).is_equal(0)
	assert_int(inv.get_item_count("wood")).is_equal(1)
	assert_float(inv.current_weight()).is_equal(2.0)

func test_add_multiple_items() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	inv.add("wood", 5)
	assert_int(inv.get_item_count("wood")).is_equal(5)
	assert_float(inv.current_weight()).is_equal(10.0)

func test_add_unknown_item_returns_all_as_overflow() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	var overflow := inv.add("unknown", 10)
	assert_int(overflow).is_equal(10)
	assert_int(inv.items.size()).is_equal(0)

func test_add_negative_count_is_noop() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	var overflow := inv.add("wood", -5)
	assert_int(overflow).is_equal(0)
	assert_int(inv.get_item_count("wood")).is_equal(0)

func test_add_zero_count_is_noop() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	var overflow := inv.add("wood", 0)
	assert_int(overflow).is_equal(0)
	assert_int(inv.get_item_count("wood")).is_equal(0)


# ── add() — capacity enforcement ────────────────────────────────────────────────

func test_add_fills_to_capacity() -> void:
	var inv := _make_inventory(10.0, {"wood": _wood})  # capacity 10, wood = 2 kg
	var overflow := inv.add("wood", 10)
	assert_int(inv.get_item_count("wood")).is_equal(5)  # 5 × 2 = 10
	assert_int(overflow).is_equal(5)

func test_add_partial_fit() -> void:
	var inv := _make_inventory(7.0, {"wood": _wood})  # capacity 7, wood = 2 kg
	var overflow := inv.add("wood", 5)
	assert_int(inv.get_item_count("wood")).is_equal(3)  # 3 × 2 = 6 ≤ 7
	assert_int(overflow).is_equal(2)

func test_add_overfull_returns_all() -> void:
	var inv := _make_inventory(1.0, {"stone": _stone})  # capacity 1, stone = 5 kg
	var overflow := inv.add("stone", 1)
	assert_int(inv.get_item_count("stone")).is_equal(0)
	assert_int(overflow).is_equal(1)


# ── add() — accumulation ─────────────────────────────────────────────────────

func test_add_same_item_accumulates() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	inv.add("wood", 3)
	inv.add("wood", 2)
	assert_int(inv.get_item_count("wood")).is_equal(5)

func test_add_different_items_independent() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood, "stone": _stone})
	inv.add("wood", 3)
	inv.add("stone", 2)
	assert_int(inv.get_item_count("wood")).is_equal(3)
	assert_int(inv.get_item_count("stone")).is_equal(2)


# ── remove() ───────────────────────────────────────────────────────────────────

func test_remove_exact_count() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	inv.add("wood", 5)
	var unfulfilled := inv.remove("wood", 3)
	assert_int(unfulfilled).is_equal(0)
	assert_int(inv.get_item_count("wood")).is_equal(2)

func test_remove_more_than_available() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	inv.add("wood", 3)
	var unfulfilled := inv.remove("wood", 10)
	assert_int(unfulfilled).is_equal(7)
	assert_int(inv.get_item_count("wood")).is_equal(0)

func test_remove_unknown_item() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	var unfulfilled := inv.remove("unknown", 5)
	assert_int(unfulfilled).is_equal(5)

func test_remove_all_erases_entry() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	inv.add("wood", 5)
	inv.remove("wood", 5)
	assert_bool(inv.items.has("wood")).is_false()

func test_remove_zero_is_noop() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	inv.add("wood", 5)
	var unfulfilled := inv.remove("wood", 0)
	assert_int(unfulfilled).is_equal(0)
	assert_int(inv.get_item_count("wood")).is_equal(5)

func test_remove_negative_is_noop() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	inv.add("wood", 5)
	var unfulfilled := inv.remove("wood", -3)
	assert_int(unfulfilled).is_equal(0)
	assert_int(inv.get_item_count("wood")).is_equal(5)


# ── has_item() / get_item_count() ────────────────────────────────────────────

func test_has_item_sufficient() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	inv.add("wood", 5)
	assert_bool(inv.has_item("wood", 5)).is_true()

func test_has_item_insufficient() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	inv.add("wood", 5)
	assert_bool(inv.has_item("wood", 6)).is_false()

func test_has_item_absent() -> void:
	var inv := _make_inventory(50.0, {"stone": _stone})
	assert_bool(inv.has_item("stone", 1)).is_false()

func test_get_item_count() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	inv.add("wood", 5)
	assert_int(inv.get_item_count("wood")).is_equal(5)

func test_get_item_count_absent() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	assert_int(inv.get_item_count("unknown")).is_equal(0)


# ── can_add() ──────────────────────────────────────────────────────────────────

func test_can_add_true() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	assert_bool(inv.can_add("wood", 1)).is_true()

func test_can_add_false() -> void:
	var inv := _make_inventory(1.0, {"wood": _wood})
	assert_bool(inv.can_add("wood", 1)).is_false()

func test_can_add_unknown_returns_false() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood})
	assert_bool(inv.can_add("unknown", 1)).is_false()


# ── current_weight() ──────────────────────────────────────────────────────────

func test_current_weight_mixed() -> void:
	var inv := _make_inventory(50.0, {"wood": _wood, "stone": _stone})
	inv.add("wood", 3)   # 3 × 2.0 = 6.0
	inv.add("stone", 2)  # 2 × 5.0 = 10.0
	assert_float(inv.current_weight()).is_equal(16.0)

func test_current_weight_empty() -> void:
	var inv := _make_inventory(50.0, {})
	assert_float(inv.current_weight()).is_equal(0.0)


# ── transfer_to() ──────────────────────────────────────────────────────────────

func test_transfer_full() -> void:
	var defs := {"wood": _wood}
	var source := _make_inventory(50.0, defs)
	var target := _make_inventory(50.0, defs)
	source.add("wood", 5)
	var unplaced := source.transfer_to(target, "wood", 5)
	assert_int(unplaced).is_equal(0)
	assert_int(source.get_item_count("wood")).is_equal(0)
	assert_int(target.get_item_count("wood")).is_equal(5)

func test_transfer_partial() -> void:
	var defs := {"wood": _wood}
	var source := _make_inventory(50.0, defs)
	var target := _make_inventory(8.0, defs)  # fits 4 wood (4 × 2 = 8)
	source.add("wood", 10)
	var unplaced := source.transfer_to(target, "wood", 10)
	assert_int(unplaced).is_equal(6)
	assert_int(source.get_item_count("wood")).is_equal(6)   # 4 went back
	assert_int(target.get_item_count("wood")).is_equal(4)

func test_transfer_target_full() -> void:
	var defs := {"wood": _wood}
	var source := _make_inventory(50.0, defs)
	var target := _make_inventory(0.0, defs)
	source.add("wood", 5)
	var unplaced := source.transfer_to(target, "wood", 5)
	assert_int(unplaced).is_equal(5)
	assert_int(source.get_item_count("wood")).is_equal(5)   # all returned
	assert_int(target.get_item_count("wood")).is_equal(0)

func test_transfer_more_than_source_has() -> void:
	var defs := {"wood": _wood}
	var source := _make_inventory(50.0, defs)
	var target := _make_inventory(50.0, defs)
	source.add("wood", 3)
	var unplaced := source.transfer_to(target, "wood", 10)
	assert_int(unplaced).is_equal(7)  # 3 transferred, 7 never existed
	assert_int(source.get_item_count("wood")).is_equal(0)
	assert_int(target.get_item_count("wood")).is_equal(3)

func test_transfer_unknown_item() -> void:
	var source := _make_inventory(50.0, {"wood": _wood})
	var target := _make_inventory(50.0, {"wood": _wood})
	var unplaced := source.transfer_to(target, "unknown", 10)
	assert_int(unplaced).is_equal(10)
	assert_int(source.items.size()).is_equal(0)
	assert_int(target.items.size()).is_equal(0)

func test_transfer_conserves_total() -> void:
	var defs := {"wood": _wood, "stone": _stone}
	var source := _make_inventory(50.0, defs)
	var target := _make_inventory(12.0, defs)  # fits 4 wood + 0 stone
	source.add("wood", 10)
	var total_before := source.get_item_count("wood")
	source.transfer_to(target, "wood", 10)
	var total_after := source.get_item_count("wood") + target.get_item_count("wood")
	assert_int(total_after).is_equal(total_before)


# ── StorageInventory: capacity loading + player<->crate transfer ───────────────

## StorageInventory copies def.storage_params.capacity into its base capacity.
## We call _apply_storage_params() directly (the method _ready delegates to)
## because _ready only fires once a node enters the scene tree, which the unit
## harness can't provide.
func test_storage_inventory_loads_capacity_from_def() -> void:
	var params := StorageParams.new()
	params.capacity = 42.0
	auto_free(params)
	var def := FurnitureDef.new()
	def.storage_params = params
	auto_free(def)
	var furniture := Furniture.new()
	auto_free(furniture)
	furniture.def = def
	var storage := Doubles.MockStorageInventory.new()
	storage._defs = {"wood": _wood}
	furniture.add_child(storage)
	auto_free(storage)
	storage._apply_storage_params()
	assert_float(storage.capacity).is_equal(42.0)

## Without storage_params, capacity stays at the Inventory default (0.0).
func test_storage_inventory_no_params_leaves_capacity_default() -> void:
	var furniture := Furniture.new()
	auto_free(furniture)
	furniture.def = FurnitureDef.new()      # storage_params == null
	auto_free(furniture.def)
	var storage := Doubles.MockStorageInventory.new()
	storage._defs = {"wood": _wood}
	furniture.add_child(storage)
	auto_free(storage)
	storage._apply_storage_params()
	assert_float(storage.capacity).is_equal(0.0)

## No parent Furniture (orphan) — capacity stays at the default.
func test_storage_inventory_no_parent_leaves_capacity_default() -> void:
	var storage := Doubles.MockStorageInventory.new()
	storage._defs = {"wood": _wood}
	auto_free(storage)
	storage._apply_storage_params()
	assert_float(storage.capacity).is_equal(0.0)

## Player (CharacterInventory-style) and crate (StorageInventory) interoperate
## via transfer_to — the storage path the UI actually uses.
func test_transfer_between_inventory_and_storage() -> void:
	var defs := {"wood": _wood}
	var player := _make_inventory(50.0, defs)
	var crate := Doubles.MockStorageInventory.new()
	crate._defs = defs
	crate.capacity = 8.0   # bypass _ready; set capacity directly
	auto_free(crate)
	player.add("wood", 10)
	# Player -> crate: crate fits 4 wood (4 × 2 = 8).
	var unplaced := player.transfer_to(crate, "wood", 10)
	assert_int(unplaced).is_equal(6)
	assert_int(player.get_item_count("wood")).is_equal(6)
	assert_int(crate.get_item_count("wood")).is_equal(4)
	# Crate -> player: move it all back.
	var unplaced2 := crate.transfer_to(player, "wood", 4)
	assert_int(unplaced2).is_equal(0)
	assert_int(player.get_item_count("wood")).is_equal(10)
	assert_int(crate.get_item_count("wood")).is_equal(0)


# ── Storage filtering (StorageParams hard gate) ──────────────────────────────

func test_storage_inventory_allowed_item_ids_restriction() -> void:
	var ammo_def := ItemDef.new()
	ammo_def.weight = 0.5
	auto_free(ammo_def)

	var defs := {"wood": _wood, "ammo": ammo_def}
	var params := StorageParams.new()
	params.capacity = 50.0
	params.allowed_item_ids = ["ammo"]
	auto_free(params)

	var fdef := FurnitureDef.new()
	fdef.storage_params = params
	auto_free(fdef)

	var furniture := Furniture.new()
	furniture.def = fdef
	auto_free(furniture)

	var storage := Doubles.MockStorageInventory.new()
	storage._defs = defs
	furniture.add_child(storage)
	auto_free(storage)
	storage._apply_storage_params()

	# Ammo is allowed
	assert_bool(storage.can_add("ammo", 1)).is_true()
	var overflow_ammo := storage.add("ammo", 4)
	assert_int(overflow_ammo).is_equal(0)
	assert_int(storage.get_item_count("ammo")).is_equal(4)

	# Wood is disallowed by the hard gate
	assert_bool(storage.can_add("wood", 1)).is_false()
	var overflow_wood := storage.add("wood", 2)
	assert_int(overflow_wood).is_equal(2)
	assert_int(storage.get_item_count("wood")).is_equal(0)


func test_storage_inventory_allowed_tags_restriction() -> void:
	var ammo_def := ItemDef.new()
	ammo_def.weight = 0.5
	ammo_def.tags = ["ammo", "consumable"]
	auto_free(ammo_def)

	var wood_def := ItemDef.new()
	wood_def.weight = 2.0
	wood_def.tags = ["resource"]
	auto_free(wood_def)

	var defs := {"ammo": ammo_def, "wood": wood_def}
	var params := StorageParams.new()
	params.capacity = 50.0
	params.allowed_tags = ["ammo"]
	auto_free(params)

	var fdef := FurnitureDef.new()
	fdef.storage_params = params
	auto_free(fdef)

	var furniture := Furniture.new()
	furniture.def = fdef
	auto_free(furniture)

	var storage := Doubles.MockStorageInventory.new()
	storage._defs = defs
	furniture.add_child(storage)
	auto_free(storage)
	storage._apply_storage_params()

	# Item with matching tag is allowed
	assert_bool(storage.can_add("ammo", 1)).is_true()
	# Item without matching tag is disallowed
	assert_bool(storage.can_add("wood", 1)).is_false()


func test_storage_inventory_empty_filters_allows_all() -> void:
	var ammo_def := ItemDef.new()
	ammo_def.weight = 0.5
	auto_free(ammo_def)

	var defs := {"wood": _wood, "ammo": ammo_def}
	var params := StorageParams.new()
	params.capacity = 50.0
	# Both allowed_item_ids and allowed_tags are empty by default
	auto_free(params)

	var fdef := FurnitureDef.new()
	fdef.storage_params = params
	auto_free(fdef)

	var furniture := Furniture.new()
	furniture.def = fdef
	auto_free(furniture)

	var storage := Doubles.MockStorageInventory.new()
	storage._defs = defs
	furniture.add_child(storage)
	auto_free(storage)
	storage._apply_storage_params()

	assert_bool(storage.can_add("wood", 1)).is_true()
	assert_bool(storage.can_add("ammo", 1)).is_true()


func test_transfer_to_restricted_storage_rejects_unallowed() -> void:
	var ammo_def := ItemDef.new()
	ammo_def.weight = 0.5
	auto_free(ammo_def)

	var defs := {"wood": _wood, "ammo": ammo_def}
	var player := _make_inventory(50.0, defs)
	player.add("wood", 5)
	player.add("ammo", 10)

	var params := StorageParams.new()
	params.capacity = 50.0
	params.allowed_item_ids = ["ammo"]
	auto_free(params)

	var fdef := FurnitureDef.new()
	fdef.storage_params = params
	auto_free(fdef)

	var furniture := Furniture.new()
	furniture.def = fdef
	auto_free(furniture)

	var crate := Doubles.MockStorageInventory.new()
	crate._defs = defs
	furniture.add_child(crate)
	auto_free(crate)
	crate._apply_storage_params()

	# Transfer wood to ammo-only crate fails and keeps wood in player inventory
	var unplaced_wood := player.transfer_to(crate, "wood", 5)
	assert_int(unplaced_wood).is_equal(5)
	assert_int(player.get_item_count("wood")).is_equal(5)
	assert_int(crate.get_item_count("wood")).is_equal(0)

	# Transfer ammo succeeds
	var unplaced_ammo := player.transfer_to(crate, "ammo", 10)
	assert_int(unplaced_ammo).is_equal(0)
	assert_int(player.get_item_count("ammo")).is_equal(0)
	assert_int(crate.get_item_count("ammo")).is_equal(10)
