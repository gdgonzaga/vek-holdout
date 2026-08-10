extends GdUnitTestSuite

## Unit tests for the Inventory system (Inventory, add, remove, transfer_to).

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


## Helper: creates a TestInventory with the given capacity and mock defs wired up.
func _make_inventory(capacity: float, defs: Dictionary) -> Inventory:
	var inv := TestInventory.new()
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


# ── TestInventory subclass ─────────────────────────────────────────────────────

## Inventory with mockable item definitions for testing.
class TestInventory extends Inventory:
	var _defs: Dictionary = {}

	func _get_def(item_id: String) -> ItemDef:
		return _defs.get(item_id)
