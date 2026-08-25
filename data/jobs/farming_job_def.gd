extends JobDef
class_name FarmingJobDef
## Shared skeleton for farm-plot labors (Sow, Water, Tend) executed by LimboAI behavior trees.

## Seconds of WORK before the skill multiplier (authored per .tres — rule 1).
@export var work_time := 2.0


## Resolve a job target to its Growable — the node itself or its "Growable"
## child (farm-plot furniture carries the component).
static func growable_from(node: Variant) -> Growable:
	if not is_instance_valid(node):
		return null
	var n := node as Node
	if n == null:
		return null
	var g := n as Growable
	if g != null:
		return g
	return n.get_node_or_null("Growable") as Growable
