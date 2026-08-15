extends GdUnitTestSuite

## Unit tests for the Condition system (Condition, AllOf, AnyOf, NotCondition).

var _always_false: NotCondition

func before_test() -> void:
	# Not wrapping a bare Condition (which defaults to true) gives us reusable false.
	_always_false = auto_free(NotCondition.new()) as NotCondition
	_always_false.condition = Condition.new()

func test_base_condition_returns_true_with_null_args() -> void:
	var c: Condition = auto_free(Condition.new()) as Condition
	assert_bool(c.is_met(null, null)).is_true()

func test_base_condition_returns_true_with_nodes() -> void:
	var c: Condition = auto_free(Condition.new()) as Condition
	var actor: Node = auto_free(Node.new()) as Node
	var target: Node = auto_free(Node.new()) as Node
	assert_bool(c.is_met(actor, target)).is_true()

# ── AllOf ────────────────────────────────────────────────────────────────────

func test_all_of_all_children_true() -> void:
	var composite: AllOf = auto_free(AllOf.new()) as AllOf
	composite.conditions = [Condition.new(), Condition.new(), Condition.new()]
	assert_bool(composite.is_met(null, null)).is_true()

func test_all_of_one_child_false() -> void:
	var composite: AllOf = auto_free(AllOf.new()) as AllOf
	composite.conditions = [Condition.new(), _always_false, Condition.new()]
	assert_bool(composite.is_met(null, null)).is_false()

func test_all_of_empty_children() -> void:
	var composite: AllOf = auto_free(AllOf.new()) as AllOf
	assert_bool(composite.is_met(null, null)).is_true()

func test_all_of_short_circuits_on_first_false() -> void:
	var composite: AllOf = auto_free(AllOf.new()) as AllOf
	composite.conditions = [_always_false, Condition.new()]
	assert_bool(composite.is_met(null, null)).is_false()

# ── AnyOf ────────────────────────────────────────────────────────────────────

func test_any_of_one_child_true() -> void:
	var composite: AnyOf = auto_free(AnyOf.new()) as AnyOf
	composite.conditions = [_always_false, Condition.new(), _always_false]
	assert_bool(composite.is_met(null, null)).is_true()

func test_any_of_all_children_false() -> void:
	var composite: AnyOf = auto_free(AnyOf.new()) as AnyOf
	composite.conditions = [_always_false, _always_false]
	assert_bool(composite.is_met(null, null)).is_false()

func test_any_of_empty_children() -> void:
	var composite: AnyOf = auto_free(AnyOf.new()) as AnyOf
	assert_bool(composite.is_met(null, null)).is_false()

func test_any_of_short_circuits_on_first_true() -> void:
	var composite: AnyOf = auto_free(AnyOf.new()) as AnyOf
	composite.conditions = [Condition.new(), _always_false]
	assert_bool(composite.is_met(null, null)).is_true()

# ── NotCondition ────────────────────────────────────────────────────────────

func test_not_condition_inverts_true() -> void:
	var not_true: NotCondition = auto_free(NotCondition.new()) as NotCondition
	not_true.condition = Condition.new()
	assert_bool(not_true.is_met(null, null)).is_false()

func test_not_condition_inverts_false() -> void:
	var not_false: NotCondition = auto_free(NotCondition.new()) as NotCondition
	not_false.condition = _always_false
	assert_bool(not_false.is_met(null, null)).is_true()

# ── Nesting ───────────────────────────────────────────────────────────────────

func test_not_any_of_all_false() -> void:
	var inner: AnyOf = auto_free(AnyOf.new()) as AnyOf
	inner.conditions = [_always_false, _always_false]
	var not_any: NotCondition = auto_free(NotCondition.new()) as NotCondition
	not_any.condition = inner
	assert_bool(not_any.is_met(null, null)).is_true()

func test_all_of_with_any_and_not() -> void:
	var any_tf: AnyOf = auto_free(AnyOf.new()) as AnyOf
	any_tf.conditions = [Condition.new(), _always_false]
	var not_f: NotCondition = auto_free(NotCondition.new()) as NotCondition
	not_f.condition = _always_false
	var composite: AllOf = auto_free(AllOf.new()) as AllOf
	composite.conditions = [any_tf, not_f]
	assert_bool(composite.is_met(null, null)).is_true()

func test_any_of_with_nested_all_of() -> void:
	var all_ff: AllOf = auto_free(AllOf.new()) as AllOf
	all_ff.conditions = [_always_false, _always_false]
	var all_tt: AllOf = auto_free(AllOf.new()) as AllOf
	all_tt.conditions = [Condition.new(), Condition.new()]
	var deep: AnyOf = auto_free(AnyOf.new()) as AnyOf
	deep.conditions = [all_ff, all_tt]
	assert_bool(deep.is_met(null, null)).is_true()

func test_not_all_of_mixed() -> void:
	var failed_and: AllOf = auto_free(AllOf.new()) as AllOf
	failed_and.conditions = [Condition.new(), _always_false]
	var not_and: NotCondition = auto_free(NotCondition.new()) as NotCondition
	not_and.condition = failed_and
	assert_bool(not_and.is_met(null, null)).is_true()

# ── MinSkillCondition ─────────────────────────────────────────────────────────

func _make_actor_with_skills(starting: Dictionary) -> SkilledActor:
	var actor := SkilledActor.new()
	auto_free(actor)
	actor.skill_set = SkillSet.new()
	auto_free(actor.skill_set)
	actor.skill_set.seed(starting)
	return actor

func _min_skill(skill_id: String, min_level: int) -> MinSkillCondition:
	var c: MinSkillCondition = auto_free(MinSkillCondition.new()) as MinSkillCondition
	c.skill_id = skill_id
	c.min_level = min_level
	return c

func test_min_skill_passes_at_level() -> void:
	var actor := _make_actor_with_skills({"construction": {"xp": 0, "level": 2}})
	assert_bool(_min_skill("construction", 1).is_met(actor, null)).is_true()
	assert_bool(_min_skill("construction", 2).is_met(actor, null)).is_true()

func test_min_skill_fails_below_level() -> void:
	var actor := _make_actor_with_skills({"construction": {"xp": 0, "level": 2}})
	assert_bool(_min_skill("construction", 3).is_met(actor, null)).is_false()

func test_min_skill_untrained_skill_reads_as_l1() -> void:
	var actor := _make_actor_with_skills({})
	assert_bool(_min_skill("construction", 1).is_met(actor, null)).is_true()
	assert_bool(_min_skill("construction", 2).is_met(actor, null)).is_false()

func test_min_skill_fails_without_skill_set() -> void:
	var actor: Node = auto_free(Node.new()) as Node
	assert_bool(_min_skill("construction", 1).is_met(actor, null)).is_false()

func test_min_skill_fails_with_empty_skill_id() -> void:
	var actor := _make_actor_with_skills({})
	assert_bool(_min_skill("", 1).is_met(actor, null)).is_false()

# ── HasItemCondition ──────────────────────────────────────────────────────────

func _make_actor_with_inventory(defs: Dictionary, stacks: Dictionary) -> CarryingActor:
	var actor := CarryingActor.new()
	auto_free(actor)
	var inv := MockInventory.new()
	auto_free(inv)
	inv.capacity = 100.0
	inv._defs = defs
	actor.inventory = inv
	for item_id in stacks:
		inv.add(item_id, stacks[item_id])
	return actor

func _tagged_def(tags: Array) -> ItemDef:
	var def: ItemDef = auto_free(ItemDef.new()) as ItemDef
	def.weight = 1.0
	def.tags.clear()
	for tag in tags:
		def.tags.append(tag)
	return def

func _has_item(item_id: String, item_tag: String, count: int) -> HasItemCondition:
	var c: HasItemCondition = auto_free(HasItemCondition.new()) as HasItemCondition
	c.item_id = item_id
	c.item_tag = item_tag
	c.count = count
	return c

func test_has_item_by_id() -> void:
	var actor := _make_actor_with_inventory({"plank": _tagged_def([])}, {"plank": 2})
	assert_bool(_has_item("plank", "", 1).is_met(actor, null)).is_true()
	assert_bool(_has_item("plank", "", 2).is_met(actor, null)).is_true()
	assert_bool(_has_item("plank", "", 3).is_met(actor, null)).is_false()
	assert_bool(_has_item("stone", "", 1).is_met(actor, null)).is_false()

func test_has_item_by_tag_across_stacks() -> void:
	var actor := _make_actor_with_inventory(
		{"axe": _tagged_def(["tool", "axe"]), "saw": _tagged_def(["tool"])},
		{"axe": 1, "saw": 2})
	assert_bool(_has_item("", "tool", 3).is_met(actor, null)).is_true()
	assert_bool(_has_item("", "tool", 4).is_met(actor, null)).is_false()
	assert_bool(_has_item("", "axe", 1).is_met(actor, null)).is_true()

func test_has_item_tag_ignores_untagged_and_unknown_items() -> void:
	var actor := _make_actor_with_inventory({"plank": _tagged_def([])}, {"plank": 5})
	# A stack with no resolvable def (orphaned id) must not satisfy a tag query.
	actor.inventory.items["mystery"] = 5
	assert_bool(_has_item("", "tool", 1).is_met(actor, null)).is_false()

func test_has_item_fails_when_neither_id_nor_tag_set() -> void:
	var actor := _make_actor_with_inventory({"plank": _tagged_def([])}, {"plank": 1})
	assert_bool(_has_item("", "", 1).is_met(actor, null)).is_false()

func test_has_item_fails_without_inventory() -> void:
	var actor: Node = auto_free(Node.new()) as Node
	assert_bool(_has_item("plank", "", 1).is_met(actor, null)).is_false()

# ── Test doubles ───────────────────────────────────────────────────────────────

## Actor with a SkillSet-shaped property, as MinSkillCondition resolves it.
class SkilledActor extends Node:
	var skill_set: SkillSet

## Actor with an Inventory-shaped property, as HasItemCondition resolves it.
class CarryingActor extends Node:
	var inventory: Inventory

## Inventory with mockable item definitions (same pattern as suite_inventory_test).
class MockInventory extends Inventory:
	var _defs: Dictionary = {}

	func _get_def(item_id: String) -> ItemDef:
		return _defs.get(item_id)
