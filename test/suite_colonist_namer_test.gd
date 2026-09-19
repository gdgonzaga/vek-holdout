extends GdUnitTestSuite
## Tests for ColonistNamer (random colonist names from a NamePool) and for how
## Colony.spawn_colonist applies it. Content-agnostic: pools are built in memory with
## synthetic names, and the RNG is seeded so every roll is reproducible.

# Swap-and-restore (AGENTS.md): the real registry must never be wired to test
# fixtures, and Colony's container must survive the spawn tests' on_map_wired.
var _real_registry: StorageRegistry
var _real_container: Node3D
var _test_registry: StorageRegistry


func before_test() -> void:
	_real_registry = Colony.storage_registry
	_real_container = Colony._container
	_test_registry = auto_free(StorageRegistry.new())
	Colony.storage_registry = _test_registry
	Colony.colonists.clear()


func after_test() -> void:
	Colony.storage_registry = _real_registry
	Colony._container = _real_container
	Colony.colonists.clear()


func _make_pool(males: Array[String], females: Array[String], lasts: Array[String]) -> NamePool:
	var pool: NamePool = auto_free(NamePool.new())
	pool.male_first_names = PackedStringArray(males)
	pool.female_first_names = PackedStringArray(females)
	pool.last_names = PackedStringArray(lasts)
	return pool


func _make_rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _no_names() -> Array[String]:
	var none: Array[String] = []
	return none


func _numbered(prefix: String, count: int) -> Array[String]:
	var out: Array[String] = []
	for i in count:
		out.append("%s%d" % [prefix, i])
	return out


# ==============================
# ColonistNamer.pick
# ==============================

func test_pick_joins_a_first_and_last_name() -> void:
	var pool: NamePool = _make_pool(["Ann"], [], ["Bay"])

	assert_str(ColonistNamer.pick(pool, _make_rng(1), _no_names())).is_equal("Ann Bay")


func test_pick_only_uses_names_from_the_pool() -> void:
	var pool: NamePool = _make_pool(["Ann", "Bo", "Cy"], ["Di", "Ed"], ["Day", "Eli", "Fay"])
	var rng: RandomNumberGenerator = _make_rng(7)

	for i in 50:
		var parts: PackedStringArray = ColonistNamer.pick(pool, rng, _no_names()).split(" ")
		assert_int(parts.size()).is_equal(2)
		assert_bool(pool.male_first_names.has(parts[0]) or pool.female_first_names.has(parts[0])).is_true()
		assert_bool(pool.last_names.has(parts[1])).is_true()


func test_pick_is_reproducible_for_the_same_seed() -> void:
	var pool: NamePool = _make_pool(["Ann", "Bo"], ["Cy", "Di"], ["Day", "Eli", "Fay", "Gus"])

	var first: String = ColonistNamer.pick(pool, _make_rng(42), _no_names())
	var second: String = ColonistNamer.pick(pool, _make_rng(42), _no_names())

	assert_str(first).is_equal(second)


func test_pick_draws_from_both_first_name_lists() -> void:
	var pool: NamePool = _make_pool(["Mo"], ["Fi"], ["Day"])
	var rng: RandomNumberGenerator = _make_rng(5)

	var seen: Dictionary = {}
	for i in 100:
		seen[ColonistNamer.pick(pool, rng, _no_names())] = true

	assert_bool(seen.has("Mo Day")).is_true()
	assert_bool(seen.has("Fi Day")).is_true()


func test_pick_chooses_between_the_lists_evenly_whatever_their_sizes() -> void:
	var pool: NamePool = _make_pool(["Mo"], _numbered("F", 50), ["Day"])
	var rng: RandomNumberGenerator = _make_rng(11)

	var male_rolls: int = 0
	for i in 400:
		if ColonistNamer.pick(pool, rng, _no_names()) == "Mo Day":
			male_rolls += 1

	assert_int(male_rolls).is_between(160, 240)


func test_pick_with_only_a_female_list_never_uses_male_names() -> void:
	var pool: NamePool = _make_pool([], ["Fi"], ["Day"])
	var rng: RandomNumberGenerator = _make_rng(2)

	for i in 30:
		assert_str(ColonistNamer.pick(pool, rng, _no_names())).is_equal("Fi Day")


func test_pick_with_only_a_male_list_never_uses_female_names() -> void:
	var pool: NamePool = _make_pool(["Mo"], [], ["Day"])
	var rng: RandomNumberGenerator = _make_rng(2)

	for i in 30:
		assert_str(ColonistNamer.pick(pool, rng, _no_names())).is_equal("Mo Day")


func test_pick_ignores_a_first_name_list_that_is_all_blank() -> void:
	var pool: NamePool = _make_pool(["  ", ""], ["Fi"], ["Day"])
	var rng: RandomNumberGenerator = _make_rng(3)

	for i in 30:
		assert_str(ColonistNamer.pick(pool, rng, _no_names())).is_equal("Fi Day")


func test_pick_avoids_a_taken_name_when_a_free_one_exists() -> void:
	var pool: NamePool = _make_pool(["Ann", "Bo"], [], ["Day"])
	var taken: Array[String] = ["Ann Day"]

	for seed_value in 30:
		assert_str(ColonistNamer.pick(pool, _make_rng(seed_value), taken)).is_equal("Bo Day")


func test_pick_appends_a_number_when_every_combination_is_taken() -> void:
	var pool: NamePool = _make_pool(["Ann"], [], ["Day"])
	var taken: Array[String] = ["Ann Day"]

	assert_str(ColonistNamer.pick(pool, _make_rng(1), taken)).is_equal("Ann Day 2")


func test_pick_skips_numbers_that_are_also_taken() -> void:
	var pool: NamePool = _make_pool(["Ann"], [], ["Day"])
	var taken: Array[String] = ["Ann Day", "Ann Day 2"]

	assert_str(ColonistNamer.pick(pool, _make_rng(1), taken)).is_equal("Ann Day 3")


func test_pick_with_only_last_names_returns_a_single_name() -> void:
	var pool: NamePool = _make_pool([], [], ["Day"])

	assert_str(ColonistNamer.pick(pool, _make_rng(1), _no_names())).is_equal("Day")


func test_pick_with_only_first_names_returns_a_single_name() -> void:
	var pool: NamePool = _make_pool(["Ann"], [], [])

	assert_str(ColonistNamer.pick(pool, _make_rng(1), _no_names())).is_equal("Ann")


func test_pick_returns_empty_for_a_null_or_empty_pool() -> void:
	assert_str(ColonistNamer.pick(null, _make_rng(1), _no_names())).is_equal("")
	assert_str(ColonistNamer.pick(_make_pool([], [], []), _make_rng(1), _no_names())).is_equal("")


func test_pick_ignores_blank_entries_in_a_list() -> void:
	var pool: NamePool = _make_pool(["", "Ann", "  "], [], ["Day"])
	var rng: RandomNumberGenerator = _make_rng(3)

	for i in 30:
		assert_str(ColonistNamer.pick(pool, rng, _no_names())).is_equal("Ann Day")


# ==============================
# Colony.spawn_colonist
# ==============================

func _wire_map() -> void:
	var container: Node3D = auto_free(Node3D.new())
	add_child(container)
	Colony.on_map_wired(container, [])


func _def_with_pool(pool: NamePool) -> ColonistDef:
	var def: ColonistDef = auto_free(ColonistDef.new())
	def.name_pool = pool
	return def


func test_spawn_names_a_colonist_from_the_defs_pool() -> void:
	_wire_map()
	var def: ColonistDef = _def_with_pool(_make_pool(["Ann"], [], ["Day"]))

	var spawned: Colonist = Colony.spawn_colonist(def, Vector3.ZERO)

	assert_str(spawned.display_name).is_equal("Ann Day")


func test_spawn_gives_each_colonist_a_distinct_name_when_the_pool_allows() -> void:
	_wire_map()
	var def: ColonistDef = _def_with_pool(_make_pool(["Ann", "Bo"], ["Cy"], ["Day", "Eli"]))

	var names: Array[String] = []
	for i in 5:
		names.append(Colony.spawn_colonist(def, Vector3.ZERO).display_name)

	var unique: Dictionary = {}
	for n: String in names:
		unique[n] = true
	assert_int(unique.size()).is_equal(5)


func test_spawn_without_a_pool_keeps_the_defs_authored_name() -> void:
	_wire_map()
	var def: ColonistDef = auto_free(ColonistDef.new())
	def.display_name = "Authored Name"

	var spawned: Colonist = Colony.spawn_colonist(def, Vector3.ZERO)

	assert_str(spawned.display_name).is_equal("Authored Name")


func test_spawn_treats_a_pool_with_no_usable_names_as_no_pool() -> void:
	_wire_map()
	var def: ColonistDef = _def_with_pool(_make_pool([], [], []))
	def.display_name = "Fallback Name"

	var spawned: Colonist = Colony.spawn_colonist(def, Vector3.ZERO)

	assert_str(spawned.display_name).is_equal("Fallback Name")


func test_spawn_after_loading_avoids_names_already_in_the_restored_roster() -> void:
	_wire_map()
	var def: ColonistDef = _def_with_pool(_make_pool(["Ann", "Bo"], [], ["Day"]))
	var first_name: String = Colony.spawn_colonist(def, Vector3.ZERO).display_name
	var saved: Dictionary = Colony.serialize()
	Colony.reset_for_new_game()
	Colony.deserialize(saved)
	_wire_map()
	assert_int(Colony.colonists.size()).is_equal(1)

	var second: Colonist = Colony.spawn_colonist(def, Vector3.ZERO)

	assert_str(second.display_name).is_not_equal(first_name)
	assert_bool(second.display_name in ["Ann Day", "Bo Day"]).is_true()
