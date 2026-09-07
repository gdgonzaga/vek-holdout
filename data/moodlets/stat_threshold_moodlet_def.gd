## Data Schema: StatThresholdMoodletDef
## Generic threshold-driven moodlet evaluator for colonist stats (ARCH §6).
## Compares normalized stat ratios against defined threshold cutoffs.
extends MoodletDef
class_name StatThresholdMoodletDef

enum TriggerMode {
	BELOW_THRESHOLD, ## Triggers when stat <= threshold (depletion: HP, hunger, rest)
	ABOVE_THRESHOLD, ## Triggers when stat >= threshold (accumulation: stress, toxicity)
}

@export var stat_id: StringName = &"hunger"
@export var trigger_mode: TriggerMode = TriggerMode.BELOW_THRESHOLD
## Ordered thresholds from least severe (index 0) to most severe (last index).
@export var thresholds: Array[float] = [0.40, 0.15]


# =================
# Primary Functions
# =================

func evaluate_icon_index(entity: Node) -> int:
	if entity == null:
		return -1
	
	# 1. Stat Query: Retrieve the normalized 0.0 to 1.0 ratio for the configured stat.
	var stat_ratio: float = _query_entity_stat_ratio(entity)
	if stat_ratio < 0.0:
		return -1
	
	# 2. Threshold Matching: Scan thresholds backward from most critical to least critical.
	return _match_threshold_index(stat_ratio)


# ===================
# Auxiliary Functions
# ===================

func _query_entity_stat_ratio(entity: Node) -> float:
	## Auxiliary: Safely calls get_stat_ratio on entity.
	if entity.has_method("get_stat_ratio"):
		return float(entity.get_stat_ratio(stat_id))
	return -1.0


func _match_threshold_index(stat_ratio: float) -> int:
	## Auxiliary: Compares stat ratio against thresholds array in reverse order to resolve the most severe active tier.
	for i in range(thresholds.size() - 1, -1, -1):
		var cutoff: float = thresholds[i]
		if trigger_mode == TriggerMode.BELOW_THRESHOLD and stat_ratio <= cutoff:
			return i
		elif trigger_mode == TriggerMode.ABOVE_THRESHOLD and stat_ratio >= cutoff:
			return i
	return -1
