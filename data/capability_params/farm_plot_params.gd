class_name FarmPlotParams
extends FurnitureCapability
## Capability parameter for farm plot furniture (GDD §7.2 / Farming).
## Declares that the parent furniture is a farm plot supporting crop growth.

## Allowed CropDef ids for this plot. Empty means any crop is supported.
@export var allowed_crops: Array[String] = []

## Number of independent crop slots on this plot (reserved for future multi-crop plots).
## Currently only slot 0 is used; Growable reads this for capacity display.
@export var crop_slots: int = 1

## Growth rate multiplier applied on top of CropDef.growth_time_hours.
## Use to model enriched soil, heated glass, or penalty plots (e.g. 0.8 = 20% slower).
## 1.0 = no modification (default).
@export_range(0.1, 5.0) var growth_rate_multiplier: float = 1.0

## Hydration source hint for the future irrigation tier (ARCH farming.md §Tier 2).
## "manual" = colonists fetch water; "irrigated" = connected to fluid network (planned).
@export_enum("manual", "irrigated") var hydration_mode: String = "manual"


## Returns the farming ActionOptions needed on the plot's InteractionComponent.
func collect_action_options() -> Array[ActionOption]:
	return [
		preload("res://data/action_options/inspect_crop_action_option.tres"),
		preload("res://data/action_options/select_crop_action_option.tres"),
		preload("res://data/action_options/toggle_harvest_action_option.tres"),
	]

