class_name ColonistNamer
extends RefCounted
## Pure random-name rolling for generic colonists (ARCH colonists.md). Holds no state and
## touches no autoloads: the caller supplies the pool, the RNG and the names already in use,
## so Colony owns the roster/RNG while the rolling logic tests with in-memory pools.

## Random re-rolls tried before falling back to a numbered suffix. Generous for a roster
## capped at a handful of colonists; a nearly exhausted pool just gets a suffix.
const MAX_ROLL_ATTEMPTS: int = 20

# =================
# Primary Functions
# =================

## Rolls a name from `pool` that is not in `taken`. The first name comes from the male or female
## list with equal probability (whatever their sizes), so the roster's mix does not depend on
## list length. Returns "" when the pool is null or has no usable names, so callers can fall
## back to the def's authored display_name. If every roll collides, returns the last roll with
## the smallest free number appended ("Ann Day 2").
static func pick(pool: NamePool, rng: RandomNumberGenerator, taken: Array[String]) -> String:
	if pool == null:
		return ""

	# 1. Usable Names: drop blank entries so an authoring slip never yields an empty part.
	var first_lists: Array[Array] = _usable_first_lists(pool)
	var lasts: Array[String] = _usable_names(pool.last_names)
	if first_lists.is_empty() and lasts.is_empty():
		return ""

	# 2. Roll And Retry: draw until a full name is free, so names stay unique across the roster.
	var candidate: String = ""
	for attempt: int in MAX_ROLL_ATTEMPTS:
		candidate = _roll_name(first_lists, lasts, rng)
		if not taken.has(candidate):
			return candidate

	# 3. Uniqueness Fallback: the pool is (nearly) exhausted, so disambiguate with a number.
	return _make_unique(candidate, taken)

# ===================
# Auxiliary Functions
# ===================

static func _usable_names(names: PackedStringArray) -> Array[String]:
	## Auxiliary: The non-blank, whitespace-trimmed entries of a name list.
	var usable: Array[String] = []
	for entry: String in names:
		var trimmed: String = entry.strip_edges()
		if not trimmed.is_empty():
			usable.append(trimmed)
	return usable


static func _usable_first_lists(pool: NamePool) -> Array[Array]:
	## Auxiliary: The male and female first-name lists that still have a usable entry after
	## trimming, so a blank or empty list never takes part in the coin flip.
	var lists: Array[Array] = []
	for names: PackedStringArray in [pool.male_first_names, pool.female_first_names]:
		var usable: Array[String] = _usable_names(names)
		if not usable.is_empty():
			lists.append(usable)
	return lists


static func _roll_name(first_lists: Array[Array], lasts: Array[String], rng: RandomNumberGenerator) -> String:
	## Auxiliary: A first name (fair coin between the lists, then uniform within one) and/or a last name.
	var parts: Array[String] = []
	if not first_lists.is_empty():
		var chosen: Array = first_lists[rng.randi_range(0, first_lists.size() - 1)]
		parts.append(chosen[rng.randi_range(0, chosen.size() - 1)])
	if not lasts.is_empty():
		parts.append(lasts[rng.randi_range(0, lasts.size() - 1)])
	return " ".join(parts)


static func _make_unique(base_name: String, taken: Array[String]) -> String:
	## Auxiliary: `base_name` with the smallest number (from 2) that is not already taken.
	var suffix: int = 2
	while taken.has("%s %d" % [base_name, suffix]):
		suffix += 1
	return "%s %d" % [base_name, suffix]
