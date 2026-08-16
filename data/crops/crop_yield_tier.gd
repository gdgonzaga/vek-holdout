class_name CropYieldTier
extends Resource
## Defines yields granted when harvesting a crop at or above a minimum growth progress (GDD §6 / Farming).

@export var min_growth_progress: float = 1.0
@export var yields: Array[ItemAmount] = []
