class_name FoodParams
extends Resource
## Capability parameter for edible food items (ARCH colonists.md, GDD §7).
## Attached to ItemDef via the nullable `food` export, establishing modular
## nutrition, consumption duration, animation, and health restoration values.

## Hunger restoration fraction on a 0.0 to 1.0 scale (1.0 = 100% hunger restored).
@export_range(0.0, 1.0) var nutrition_value: float = 0.4

## Immediate HP restored upon finishing consumption.
@export var health_restore: int = 0

## Duration in seconds required for an entity to consume this food item.
@export var eat_duration: float = 2.0

## Animation played by ColonistAnimationController or Player during eating.
@export var eating_animation: StringName = &"eat"

## Optional moodlet or status effect ID applied upon consumption (e.g. fine meal buff).
@export var mood_modifier: StringName = &""

## Spoilage timeframe in game hours. 0.0 designates a non-perishable ration.
@export var spoilage_hours: float = 0.0


# =================
# Primary Functions
# =================

## Returns the effective nutrition restored given a current deficit.
func calculate_effective_nutrition(current_deficit: float) -> float:
	# 1. Nutrition Clamping: Bounds the restoration against the current need deficit.
	return _clamp_nutrition_to_deficit(current_deficit, nutrition_value)


# ===================
# Auxiliary Functions
# ===================

func _clamp_nutrition_to_deficit(deficit: float, max_nutrition: float) -> float:
	## Auxiliary: Ensures restored value is non-negative and capped at the requested nutrition.
	if deficit <= 0.0:
		return 0.0
	return minf(deficit, max_nutrition)
