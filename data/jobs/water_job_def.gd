extends FarmingJobDef
class_name WaterJobDef
## Watering labor (GDD §6 / Farming, ARCH "Farming"): colonist waters a thirsty crop.

func _needs(growable: Growable) -> bool:
	return growable.needs_water()


func _apply(growable: Growable, actor: Node) -> void:
	growable.water(actor)
