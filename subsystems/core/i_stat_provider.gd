class_name IStatProvider
extends RefCounted
## Duck-typed contract for entities that expose queryable stats and an
## activity/interaction-state identifier to the moodlet system
## (StatThresholdMoodletDef, ActivityMoodletDef) via has_method() checks —
## do NOT extend this script.
##
## Partial implementation is expected, not an error: EnemyBase implements only
## the stat methods (enemies have no activity moodlets), and Harvestable
## implements only get_stat_ratio/get_stat_value (its is_marked_for_harvest
## state is surfaced through WildFlora's get_current_activity instead, not
## duplicated here).
##
## Implementations: Colonist (full), EnemyBase (stat methods only), WildFlora
## (full — get_current_activity repurposed to report interaction state:
## choppable/marked_for_harvest/forageable/depleted), Harvestable (stat
## methods only, composed into WildFlora rather than queried directly by the
## moodlet pipeline).


## Normalized 0.0-1.0 ratio for a named stat, or -1.0 if unknown/uninitialized.
func get_stat_ratio(_stat_name: StringName) -> float:
	return -1.0


## Raw scalar value for a named stat, or -1.0 if unknown/uninitialized.
func get_stat_value(_stat_name: StringName) -> float:
	return -1.0


## Current activity OR interaction-state identifier (e.g. &"idle", &"mining"
## for colonists; &"choppable", &"forageable" for wild flora), or &"" if
## unresolvable / not applicable to this entity type.
func get_current_activity() -> StringName:
	return &""
