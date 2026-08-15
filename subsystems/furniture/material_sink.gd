class_name MaterialSink
extends RefCounted
## Duck-typed contract for furniture that receives hauled materials (GDScript
## has no interfaces; Blueprint — a Furniture — is the first implementer,
## crafting stations next). A node is a material sink when it answers:
##
##   needed_item_ids() -> Array[String]   item_ids still owed
##   remaining_need(item_id) -> int       units of one item still owed
##   deposit_from(actor) -> int           take what the actor carries (partial
##                                        ok); emits when satisfied
##   has_complete_materials() -> bool     nothing further is owed
##
## HaulingJobDef talks to job.target_node through exactly these four — never a
## Blueprint cast — so any furniture implementing them is haulable to. Checked
## via has_method (is_material_sink), not a class test.
##
## Static-only helper; never instantiated.

const REQUIRED_METHODS := [
	"needed_item_ids", "remaining_need", "deposit_from", "has_complete_materials",
]


## True if `node` is alive and answers the full MaterialSink surface.
static func is_material_sink(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	for method in REQUIRED_METHODS:
		if not node.has_method(method):
			return false
	return true
