## Subsystem: AI Tasks
## Checks if the agent possesses a required tool by tag or specific item ID in its carry inventory.
@tool
class_name BTConditionHasTool
extends BTCondition

## Blackboard variable storing the required tool tag
@export var tool_tag_var: StringName = &"required_tool_tag"

## Static fallback tool tag
@export var default_tool_tag: StringName = &""

## Blackboard variable storing a specific required tool item ID
@export var tool_id_var: StringName = &"required_tool_id"

## Static fallback tool item ID
@export var default_tool_id: String = ""


func _generate_name() -> String:
	return "Has Tool  tag: %s | id: %s" % [
		LimboUtility.decorate_var(tool_tag_var),
		LimboUtility.decorate_var(tool_id_var)
	]


func _tick(_delta: float) -> Status:
	if not agent:
		return FAILURE
		
	var req_tag: String = String(default_tool_tag)
	var req_id: String = default_tool_id
	
	if blackboard:
		if blackboard.has_var(tool_tag_var):
			var var_tag: Variant = blackboard.get_var(tool_tag_var)
			if var_tag != null and str(var_tag) != "":
				req_tag = str(var_tag)
			
		if blackboard.has_var(tool_id_var):
			var var_id: Variant = blackboard.get_var(tool_id_var)
			if var_id != null and str(var_id) != "":
				req_id = str(var_id)
			
		if req_tag == "" and req_id == "":
			# Fallback to active_job inspection
			var job: Variant = null
			if blackboard.has_var(&"active_job"):
				job = blackboard.get_var(&"active_job")
			if job != null and is_instance_valid(job):
				if "required_tool_tag" in job and str(job.required_tool_tag) != "":
					req_tag = str(job.required_tool_tag)
				elif "def" in job and job.def != null and "required_tool_tag" in job.def:
					req_tag = str(job.def.required_tool_tag)

	# If no requirement exists, condition passes vacuously
	if req_tag == "" and req_id == "":
		return SUCCESS
		
	var inv = null
	if "inventory" in agent and agent.inventory != null:
		inv = agent.inventory
		
	if inv == null:
		return FAILURE
		
	# Check specific ID match
	if req_id != "":
		if inv.has_method("has_item") and inv.has_item(req_id, 1):
			return SUCCESS
		if inv.has_method("get_item_count") and inv.get_item_count(req_id) > 0:
			return SUCCESS
			
	# Check tag match
	if req_tag != "":
		if "items" in inv and inv.items is Dictionary:
			for item_id in inv.items.keys():
				if inv.items[item_id] > 0 and _item_has_tag(str(item_id), req_tag):
					return SUCCESS
					
	return FAILURE


func _item_has_tag(item_id: String, tag: String) -> bool:
	var def = ItemDB.get_def(item_id)
	if def != null and "tags" in def and def.tags is Array:
		return def.tags.has(tag)
	return false
