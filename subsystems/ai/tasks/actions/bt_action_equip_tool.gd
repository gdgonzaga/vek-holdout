## Subsystem: AI Tasks
## Resolves a required tool from equipment slots or carry inventory into main_hand.
## Runs immediately before work execution in the colonist behavior tree so the
## right tool is always in the active hand before a job tick fires.
##
## Resolution order:
##   1. main_hand already has the tag          -> SUCCESS (no-op)
##   2. holster has the tag                    -> swap main_hand <-> holster, SUCCESS
##   3. carry inventory has an item with tag   -> equip into main_hand, SUCCESS
##   4. none of the above                      -> FAILURE (upstream BT must fetch the tool)
@tool
class_name BTActionEquipTool
extends BTAction

## ================
## Primary Functions
## ================

func _generate_name() -> String:
	return "Equip Tool for required_tool_tag"


func _tick(_delta: float) -> Status:
	if not agent:
		return FAILURE

	# 1. Tag Resolution: Read the required tag from blackboard or fall back to active job.
	var req_tag: StringName = _resolve_required_tag()
	if req_tag == &"":
		# No tool requirement — nothing to equip, action is vacuously successful.
		return SUCCESS

	# 2. Equipment Lookup: Attempt a swap between main_hand and holster first
	#    (zero inventory churn — the tool is already equipped somewhere).
	var eq: Equipment = _get_equipment()
	if eq != null and eq.swap_hand_for_tag(req_tag):
		return SUCCESS

	# 3. Inventory Lookup: Find the first matching item in the carry inventory
	#    and move it into main_hand.
	if _equip_from_inventory(eq, req_tag):
		return SUCCESS

	return FAILURE

## ====================
## Auxiliary Functions
## ====================

func _resolve_required_tag() -> StringName:
	## Auxiliary: Reads required_tool_tag from the blackboard, with fallback to the active job def.
	if blackboard == null:
		return &""
	if blackboard.has_var(&"required_tool_tag"):
		var raw: Variant = blackboard.get_var(&"required_tool_tag")
		var tag: StringName = StringName(str(raw)) if raw != null else &""
		if tag != &"":
			return tag
	# Fallback: inspect the active job/claim for its required_tool_tag field.
	var job: Variant = null
	if blackboard.has_var(&"active_job"):
		job = blackboard.get_var(&"active_job")
	if blackboard.has_var(&"active_claim") and job == null:
		job = blackboard.get_var(&"active_claim")
	if job != null and is_instance_valid(job):
		if "required_tool_tag" in job and str(job.required_tool_tag) != "":
			return StringName(str(job.required_tool_tag))
		if "job_def" in job and job.job_def != null and "required_tool_tag" in job.job_def:
			return StringName(str(job.job_def.required_tool_tag))
		if "def" in job and job.def != null and "required_tool_tag" in job.def:
			return StringName(str(job.def.required_tool_tag))
	return &""


func _get_equipment() -> Equipment:
	## Auxiliary: Returns the Equipment sibling node on the agent, or null if absent.
	if not is_instance_valid(agent):
		return null
	return agent.get_node_or_null("Equipment") as Equipment


func _equip_from_inventory(eq: Equipment, tag: StringName) -> bool:
	## Auxiliary: Searches the agent's carry inventory for an item matching tag,
	##            removes one from inventory, and equips it to main_hand.
	##            Returns true if the equip succeeded.
	if eq == null or not is_instance_valid(agent):
		return false
	var inv: Inventory = _get_inventory()
	if inv == null:
		return false

	# Find an item ID in the inventory that carries the needed tag.
	var matching_id: String = _find_inventory_item_with_tag(inv, String(tag))
	if matching_id.is_empty():
		return false

	var item_def: ItemDef = ItemDB.get_def(matching_id)
	if item_def == null:
		return false

	# Move item from carry bag to equipment slot.
	inv.remove(matching_id, 1)
	return eq.equip(Equipment.SLOT_MAIN_HAND, item_def)


func _get_inventory() -> Inventory:
	## Auxiliary: Returns the Inventory node on the agent using duck-typed access.
	if "inventory" in agent and agent.inventory != null:
		return agent.inventory as Inventory
	return null


func _find_inventory_item_with_tag(inv: Inventory, tag: String) -> String:
	## Auxiliary: Iterates inventory items and returns the first item_id whose ItemDef carries tag.
	if not ("items" in inv) or not (inv.items is Dictionary):
		return ""
	for item_id: String in inv.items.keys():
		if inv.items[item_id] > 0:
			var def: ItemDef = ItemDB.get_def(item_id)
			if def != null and def.has_tag(tag):
				return item_id
	return ""
