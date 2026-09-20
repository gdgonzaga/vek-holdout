extends GdUnitTestSuite
## Test suite for LootRoller: independent per-entry chance, uniform inclusive
## count range, guaranteed amounts, and one merged stack per item id.
## Content-agnostic: every ItemDef/LootTable is built in memory.

const _SEED: int = 12345


func _make_item(item_id: String) -> ItemDef:
	var item := ItemDef.new()
	item.id = item_id
	return item


func _make_entry(item: ItemDef, chance: float, min_count: int, max_count: int) -> LootEntry:
	var entry := LootEntry.new()
	entry.item_def = item
	entry.chance = chance
	entry.min_count = min_count
	entry.max_count = max_count
	return entry


func _make_amount(item: ItemDef, count: int) -> ItemAmount:
	var amount := ItemAmount.new()
	amount.item_def = item
	amount.count = count
	return amount


func _make_rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = _SEED
	return rng


# Break caught: a missing null guard crashes every enemy that has no table.
func test_null_table_returns_empty() -> void:
	var result: Dictionary[String, int] = LootRoller.roll(null, _make_rng())
	assert_int(result.size()).is_equal(0)


# Break caught: an empty table inventing a drop.
func test_empty_table_returns_empty() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	var result: Dictionary[String, int] = LootRoller.roll(table, _make_rng())
	assert_int(result.size()).is_equal(0)


# Break caught: guaranteed list ignored or counts altered.
func test_guaranteed_amounts_are_returned_with_exact_counts() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.guaranteed = [_make_amount(_make_item("test_a"), 3), _make_amount(_make_item("test_b"), 1)]
	var result: Dictionary[String, int] = LootRoller.roll(table, _make_rng())
	assert_int(result.size()).is_equal(2)
	assert_int(result.get("test_a", 0)).is_equal(3)
	assert_int(result.get("test_b", 0)).is_equal(1)


# Break caught: a half-authored ItemAmount (no item, or zero count) spawning junk
# or crashing on null item_def.
func test_guaranteed_skips_null_item_and_non_positive_count() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.guaranteed = [
		_make_amount(null, 5),
		_make_amount(_make_item("test_zero"), 0),
		_make_amount(_make_item("test_neg"), -2),
		_make_amount(_make_item("test_ok"), 2),
	]
	var result: Dictionary[String, int] = LootRoller.roll(table, _make_rng())
	assert_int(result.size()).is_equal(1)
	assert_int(result.get("test_ok", 0)).is_equal(2)


# Break caught: chance=1.0 failing on the rare randf()==1.0 edge (strict < with no guard).
func test_chance_one_always_drops_the_exact_count() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.entries = [_make_entry(_make_item("test_a"), 1.0, 4, 4)]
	var rng := _make_rng()
	for i in 200:
		var result: Dictionary[String, int] = LootRoller.roll(table, rng)
		assert_int(result.get("test_a", 0)).is_equal(4)


# Break caught: chance=0.0 leaking a drop on the rare randf()==0.0 edge.
func test_chance_zero_never_drops() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.entries = [_make_entry(_make_item("test_a"), 0.0, 1, 1)]
	var rng := _make_rng()
	for i in 200:
		var result: Dictionary[String, int] = LootRoller.roll(table, rng)
		assert_int(result.size()).is_equal(0)


# Break caught: chance compared the wrong way round. At 0.25 an inverted test
# lands near 1500 of 2000, far outside the band (fixed seed keeps this stable).
func test_chance_quarter_drops_about_a_quarter_of_the_time() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.entries = [_make_entry(_make_item("test_a"), 0.25, 1, 1)]
	var rng := _make_rng()
	var hits: int = 0
	for i in 2000:
		var result: Dictionary[String, int] = LootRoller.roll(table, rng)
		hits += 1 if result.has("test_a") else 0
	assert_int(hits).is_between(400, 600)


# Break caught: off-by-one in the count range (exclusive max, or min never reached).
func test_count_covers_both_inclusive_bounds_and_nothing_outside() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.entries = [_make_entry(_make_item("test_a"), 1.0, 2, 4)]
	var rng := _make_rng()
	var seen: Dictionary = {}
	for i in 300:
		var result: Dictionary[String, int] = LootRoller.roll(table, rng)
		seen[result.get("test_a", 0)] = true
	assert_array(seen.keys()).contains_exactly_in_any_order([2, 3, 4])


# Break caught: min_count <= 0 producing a zero/negative stack from a passing roll.
func test_count_below_one_is_clamped_up_to_one() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.entries = [_make_entry(_make_item("test_a"), 1.0, 0, 2)]
	var rng := _make_rng()
	var seen: Dictionary = {}
	for i in 300:
		var result: Dictionary[String, int] = LootRoller.roll(table, rng)
		seen[result.get("test_a", 0)] = true
	assert_array(seen.keys()).contains_exactly_in_any_order([1, 2])


# Break caught: an inverted range (max < min) crashing or returning a count below min.
func test_max_below_min_is_raised_to_min() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.entries = [_make_entry(_make_item("test_a"), 1.0, 5, 2)]
	var rng := _make_rng()
	for i in 50:
		var result: Dictionary[String, int] = LootRoller.roll(table, rng)
		assert_int(result.get("test_a", 0)).is_equal(5)


# Break caught: an entry with no item crashing on null item_def.
func test_entry_with_null_item_is_skipped() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.entries = [_make_entry(null, 1.0, 1, 1), _make_entry(_make_item("test_a"), 1.0, 1, 1)]
	var result: Dictionary[String, int] = LootRoller.roll(table, _make_rng())
	assert_int(result.size()).is_equal(1)
	assert_int(result.get("test_a", 0)).is_equal(1)


# Break caught: same item under several sources spawning separate stacks (extra
# physics bodies) or one source overwriting another instead of summing.
func test_same_item_from_guaranteed_and_entries_merges_into_one_summed_stack() -> void:
	var item := _make_item("test_a")
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.guaranteed = [_make_amount(item, 2)]
	table.entries = [_make_entry(item, 1.0, 3, 3), _make_entry(item, 1.0, 1, 1)]
	var result: Dictionary[String, int] = LootRoller.roll(table, _make_rng())
	assert_int(result.size()).is_equal(1)
	assert_int(result.get("test_a", 0)).is_equal(6)


# Break caught: a failed/passed roll on one entry short-circuiting the others
# (entries must be independent, no pick-one behavior, no global cap).
func test_entries_roll_independently_and_all_passing_entries_drop() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.entries = [
		_make_entry(_make_item("test_a"), 1.0, 1, 1),
		_make_entry(_make_item("test_b"), 0.0, 1, 1),
		_make_entry(_make_item("test_c"), 1.0, 2, 2),
	]
	var result: Dictionary[String, int] = LootRoller.roll(table, _make_rng())
	assert_int(result.size()).is_equal(2)
	assert_int(result.get("test_a", 0)).is_equal(1)
	assert_int(result.get("test_c", 0)).is_equal(2)
