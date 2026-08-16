class_name FarmPlotParams
extends Resource
## Capability parameter for farm plot furniture (GDD §7.2 / Farming).
## Declares that the parent furniture is a farm plot supporting crop growth.

## Allowed CropDef ids for this plot. Empty means any crop is supported.
@export var allowed_crops: Array[String] = []
