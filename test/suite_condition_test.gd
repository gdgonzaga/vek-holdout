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
