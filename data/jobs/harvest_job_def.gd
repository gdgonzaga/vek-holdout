extends JobDef
class_name HarvestJobDef
## Harvesting labor (GDD §6.10, ARCH "Harvesting", ARCH "Farming"): declarative job
## template for harvesting resources executed by LimboAI behavior trees.

static func harvestable_from(node: Variant) -> Harvestable:
	if not is_instance_valid(node):
		return null
	var n := node as Node
	if n == null:
		return null
	var h := n as Harvestable
	if h != null:
		return h
	return n.get_node_or_null("Harvestable") as Harvestable
