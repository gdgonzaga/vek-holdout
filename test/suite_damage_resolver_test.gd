extends GdUnitTestSuite

## Unit tests for DamageResolver (GDD §6.11 Durability-before-HP arithmetic).

const DamageResolverScript = preload("res://subsystems/combat/damage_resolver.gd")


func test_resolve_durability_partial_absorb() -> void:
	assert_int(DamageResolverScript.resolve_durability(30, 50)).is_equal(20)


func test_resolve_durability_exact_absorb() -> void:
	assert_int(DamageResolverScript.resolve_durability(50, 50)).is_equal(0)


func test_resolve_durability_overflow_clamps_to_zero() -> void:
	assert_int(DamageResolverScript.resolve_durability(80, 50)).is_equal(0)


func test_resolve_durability_no_durability_returns_unchanged() -> void:
	assert_int(DamageResolverScript.resolve_durability(30, 0)).is_equal(0)


func test_resolve_overflow_partial_absorb_has_no_overflow() -> void:
	assert_int(DamageResolverScript.resolve_overflow(30, 50)).is_equal(0)


func test_resolve_overflow_exceeds_durability() -> void:
	assert_int(DamageResolverScript.resolve_overflow(80, 50)).is_equal(30)


func test_resolve_overflow_no_durability_passes_full_amount() -> void:
	assert_int(DamageResolverScript.resolve_overflow(30, 0)).is_equal(30)
