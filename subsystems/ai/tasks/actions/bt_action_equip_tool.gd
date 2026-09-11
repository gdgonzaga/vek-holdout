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

	# 1. Requirements Resolution: Read required equipment ID and tags from blackboard or active job.
	var reqs: Dictionary = _resolve_equipment_requirements()
	var req_id: String = str(reqs.get("item_id", ""))
	var req_tags: Array[StringName] = reqs.get("tags", [] as Array[StringName])
	if req_id == "" and req_tags.is_empty():
		# No tool requirement — nothing to equip, action is vacuously successful.
		return SUCCESS

	# 2. Equipment Lookup: Attempt a swap between main_hand and holster first
	#    (zero inventory churn — the tool is already equipped somewhere).
	var eq: Equipment = _get_equipment()
	if eq != null and eq.swap_hand_for_requirements(req_id, req_tags):
		return SUCCESS

	# 3. Inventory Lookup: Find the first matching item in the carry inventory
	#    and move it into main_hand.
	if _equip_from_inventory(eq, req_id, req_tags):
		return SUCCESS

	return FAILURE

## ====================
## Auxiliary Functions
## ====================

func _resolve_equipment_requirements() -> Dictionary:
	## Auxiliary: Resolves required equipment ID and tags from blackboard or active job def.
	var req_id: String = ""
	var req_tags: Array[StringName] = []
	if blackboard:
		if blackboard.has_var(&"required_equipped"):
			req_id = str(blackboard.get_var(&"required_equipped"))
		if blackboard.has_var(&"required_equipped_tags"):
			var raw: Variant = blackboard.get_var(&"required_equipped_tags")
			if raw is Array:
				for t: Variant in raw:
					req_tags.append(StringName(str(t)))
		elif blackboard.has_var(&"required_tool_tag"):
			var raw_tag: Variant = blackboard.get_var(&"required_tool_tag")
			if raw_tag != null and str(raw_tag) != "":
				req_tags.append(StringName(str(raw_tag)))

	# Fallback: inspect the active job/claim for its def fields.
	if req_id == "" and req_tags.is_empty():
		var job: Variant = null
		if blackboard != null:
			if blackboard.has_var(&"active_job"):
				job = blackboard.get_var(&"active_job")
			elif blackboard.has_var(&"active_claim"):
				job = blackboard.get_var(&"active_claim")
		if job != null and is_instance_valid(job):
			var def_obj: Resource = job.def if "def" in job and job.def != null else (job.job_def if "job_def" in job else null)
			if def_obj != null:
				if "required_equipped" in def_obj and str(def_obj.required_equipped) != "":
					req_id = str(def_obj.required_equipped)
				if def_obj.has_method("get_effective_required_tags"):
					req_tags = def_obj.get_effective_required_tags()
				elif "required_equipped_tags" in def_obj and def_obj.required_equipped_tags is Array:
					for t: Variant in def_obj.required_equipped_tags:
						req_tags.append(StringName(str(t)))
				elif "required_tool_tag" in def_obj and str(def_obj.required_tool_tag) != "":
					req_tags.append(StringName(str(def_obj.required_tool_tag)))

	return {"item_id": req_id, "tags": req_tags}


func _get_equipment() -> Equipment:
	## Auxiliary: Returns the Equipment sibling node on the agent, or null if absent.
	if not is_instance_valid(agent):
		return null
	return agent.get_node_or_null("Equipment") as Equipment


func _equip_from_inventory(eq: Equipment, req_id: String, req_tags: Array[StringName]) -> bool:
	## Auxiliary: Searches the agent's carry inventory for a matching item,
	##            removes one from inventory, and equips it to main_hand.
	if eq == null or not is_instance_valid(agent):
		return false
	var inv: Inventory = _get_inventory()
	if inv == null:
		return false

	var matching_id: String = ""
	if req_id != "" and inv.has_item(req_id, 1):
		matching_id = req_id
	else:
		matching_id = _find_inventory_item_with_tags(inv, req_tags)

	if matching_id.is_empty():
		return false

	var item_def: ItemDef = ItemDB.get_def(matching_id)
	if item_def == null:
		return false

	inv.remove(matching_id, 1)
	return eq.equip(Equipment.SLOT_MAIN_HAND, item_def)


func _get_inventory() -> Inventory:
	## Auxiliary: Returns the Inventory node on the agent using duck-typed access.
	if "inventory" in agent and agent.inventory != null:
		return agent.inventory as Inventory
	return null


func _find_inventory_item_with_tags(inv: Inventory, tags: Array[StringName]) -> String:
	## Auxiliary: Iterates inventory items and returns the first item_id whose ItemDef carries any matching tag.
	if not ("items" in inv) or not (inv.items is Dictionary):
		return ""
	for item_id: String in inv.items.keys():
		if inv.items[item_id] > 0:
			var def: ItemDef = ItemDB.get_def(item_id)
			if def != null:
				for tag: StringName in tags:
					if tag != &"" and def.has_tag(String(tag)):
						return item_id
	return ""
