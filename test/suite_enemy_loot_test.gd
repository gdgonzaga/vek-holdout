extends GdUnitTestSuite
## Test suite for EnemyBase drop-on-death: a defeated enemy rolls its
## EnemyDef.loot_table and scatters the result as WorldItems where it fell.
## Content-agnostic: the swarmer scene is only a shell that supplies the
## HealthComponent and AI plumbing; the def, items and table are in-memory.
## Item ids are unique per test because WorldItems live in an autoload-shared group.

const ENEMY_SCENE_PATH := "res://subsystems/combat/enemies/enemy_swarmer/enemy_swarmer.tscn"
const _ITEM_PREFIX := "test_loot_"
const _LETHAL_DAMAGE: int = 1000000
const _DEATH_POS := Vector3(40.0, 5.0, 40.0)
const ItemsLayerFixture = preload("res://test/helpers/items_layer_fixture.gd")


func before_test() -> void:
	# Drops are parented under the map's ItemsLayer (a stand-in here), not the enemy, so they outlive it.
	ItemsLayerFixture.add_to(self)


func after_test() -> void:
	# Sweep leftovers explicitly: drops made before a failed assert must not leak into later suites.
	for node in get_tree().get_nodes_in_group("world_items"):
		var item := node as WorldItem
		if item != null and item.item_id.begins_with(_ITEM_PREFIX):
			item.queue_free()


func _make_item(item_id: String) -> ItemDef:
	var item := ItemDef.new()
	item.id = item_id
	return item


func _make_amount(item: ItemDef, count: int) -> ItemAmount:
	var amount := ItemAmount.new()
	amount.item_def = item
	amount.count = count
	return amount


func _make_entry(item: ItemDef, chance: float, min_count: int, max_count: int) -> LootEntry:
	var entry := LootEntry.new()
	entry.item_def = item
	entry.chance = chance
	entry.min_count = min_count
	entry.max_count = max_count
	return entry


## Builds an enemy from the swarmer shell with HP pinned in memory so "lethal"
## and "non-lethal" damage never depend on authored content.
func _make_enemy(table: LootTable) -> EnemyBase:
	var enemy: EnemyBase = auto_free((load(ENEMY_SCENE_PATH) as PackedScene).instantiate() as EnemyBase)
	var def: EnemyDef = enemy.enemy_def.duplicate() as EnemyDef
	def.max_hp = 100
	def.max_durability = 0
	def.loot_table = table
	enemy.enemy_def = def
	add_child(enemy)
	enemy.global_position = _DEATH_POS
	return enemy


func _world_items_with_id(item_id: String) -> Array[WorldItem]:
	var found: Array[WorldItem] = []
	for node in get_tree().get_nodes_in_group("world_items"):
		var item := node as WorldItem
		if item != null and item.item_id == item_id and not item.is_queued_for_deletion():
			found.append(item)
	return found


func _stack_counts(item_id: String) -> Array[int]:
	var counts: Array[int] = []
	for item in _world_items_with_id(item_id):
		counts.append(item.count)
	return counts


func _world_item_total() -> int:
	return get_tree().get_nodes_in_group("world_items").size()


# Break caught: EnemyBase never rolling its table, skipping entries, or losing counts.
func test_death_spawns_one_world_item_per_rolled_stack_with_its_count() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.guaranteed = [_make_amount(_make_item("test_loot_stack_guar"), 3)]
	table.entries = [_make_entry(_make_item("test_loot_stack_entry"), 1.0, 2, 2)]
	var enemy := _make_enemy(table)

	enemy.take_damage(_LETHAL_DAMAGE)

	assert_array(_stack_counts("test_loot_stack_guar")).contains_exactly([3])
	assert_array(_stack_counts("test_loot_stack_entry")).contains_exactly([2])


# Break caught: dropping on damage (wrong signal) instead of on death.
func test_non_lethal_damage_spawns_nothing() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.guaranteed = [_make_amount(_make_item("test_loot_nonlethal"), 1)]
	var enemy := _make_enemy(table)

	enemy.take_damage(1)

	assert_bool(enemy.is_dead).is_false()
	assert_array(_stack_counts("test_loot_nonlethal")).is_empty()


# Break caught: a second hit on an already-dead enemy re-running the death drop.
func test_damage_after_death_does_not_drop_a_second_time() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.guaranteed = [_make_amount(_make_item("test_loot_once"), 2)]
	var enemy := _make_enemy(table)

	enemy.take_damage(_LETHAL_DAMAGE)
	enemy.take_damage(_LETHAL_DAMAGE)

	assert_array(_stack_counts("test_loot_once")).contains_exactly([2])


# Break caught: spawning at the world origin (or the wrong node) instead of where the enemy fell.
func test_drops_spawn_near_where_the_enemy_died() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.guaranteed = [_make_amount(_make_item("test_loot_near"), 1)]
	var enemy := _make_enemy(table)

	enemy.take_damage(_LETHAL_DAMAGE)

	var items := _world_items_with_id("test_loot_near")
	assert_array(items).has_size(1)
	for item in items:
		assert_float(item.global_position.distance_to(_DEATH_POS)).is_less(2.0)


# Break caught: every stack using the same angle, so all drops overlap on one
# point and the physics bodies shove each other away.
func test_multiple_stacks_scatter_to_distinct_positions() -> void:
	var table: LootTable = auto_free(LootTable.new()) as LootTable
	table.guaranteed = [
		_make_amount(_make_item("test_loot_scatter_a"), 1),
		_make_amount(_make_item("test_loot_scatter_b"), 1),
		_make_amount(_make_item("test_loot_scatter_c"), 1),
	]
	var enemy := _make_enemy(table)

	enemy.take_damage(_LETHAL_DAMAGE)

	var positions: Array[Vector3] = []
	for item_id in ["test_loot_scatter_a", "test_loot_scatter_b", "test_loot_scatter_c"]:
		for item in _world_items_with_id(item_id):
			positions.append(item.global_position)
	assert_array(positions).has_size(3)
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			assert_float(positions[i].distance_to(positions[j])).is_greater(0.5)


# Break caught: a null table spawning something or crashing the death path.
func test_enemy_without_loot_table_drops_nothing() -> void:
	var enemy := _make_enemy(null)
	var before: int = _world_item_total()

	enemy.take_damage(_LETHAL_DAMAGE)

	assert_bool(enemy.is_dead).is_true()
	assert_int(_world_item_total()).is_equal(before)


# Break caught: dereferencing enemy_def.loot_table when there is no def (bare
# EnemyBase is a supported configuration, see EnemyBase.enemy_def doc).
func test_enemy_without_def_dies_without_dropping() -> void:
	var enemy: EnemyBase = auto_free((load(ENEMY_SCENE_PATH) as PackedScene).instantiate() as EnemyBase)
	enemy.enemy_def = null
	add_child(enemy)
	var before: int = _world_item_total()

	enemy.take_damage(_LETHAL_DAMAGE)

	assert_bool(enemy.is_dead).is_true()
	assert_int(_world_item_total()).is_equal(before)
