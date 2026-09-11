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
		
	var req_tags: Array[StringName] = []
	if default_tool_tag != &"":
		req_tags.append(default_tool_tag)
	var req_id: String = default_tool_id
	
	if blackboard:
		if blackboard.has_var(&"required_equipped") and str(blackboard.get_var(&"required_equipped")) != "":
			req_id = str(blackboard.get_var(&"required_equipped"))
		elif blackboard.has_var(tool_id_var):
			var var_id: Variant = blackboard.get_var(tool_id_var)
			if var_id != null and str(var_id) != "":
				req_id = str(var_id)

		if blackboard.has_var(&"required_equipped_tags"):
			var raw_tags: Variant = blackboard.get_var(&"required_equipped_tags")
			if raw_tags is Array:
				for t: Variant in raw_tags:
					req_tags.append(StringName(str(t)))
		if blackboard.has_var(tool_tag_var):
			var var_tag: Variant = blackboard.get_var(tool_tag_var)
			if var_tag != null and str(var_tag) != "":
				var s_tag := StringName(str(var_tag))
				if not req_tags.has(s_tag):
					req_tags.append(s_tag)
			
		if req_tags.is_empty() and req_id == "":
			# Fallback to active_job inspection
			var job: Variant = null
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

	# If no requirement exists, condition passes vacuously
	if req_tags.is_empty() and req_id == "":
		return SUCCESS

	# Check equipment slots first — an already-equipped item satisfies the condition
	# without needing to fetch from the carry inventory.
	var eq: Equipment = agent.get_node_or_null("Equipment") as Equipment
	if eq != null and eq.has_required_equipment(req_id, req_tags):
		return SUCCESS
		
	var inv: Inventory = null
	if "inventory" in agent and agent.inventory != null:
		inv = agent.inventory as Inventory
		
	if inv == null:
		return FAILURE
		
	# Check specific ID match in inventory
	if req_id != "":
		if inv.has_method("has_item") and inv.has_item(req_id, 1):
			return SUCCESS
		if inv.has_method("get_item_count") and inv.get_item_count(req_id) > 0:
			return SUCCESS
			
	# Check tag match in inventory
	if not req_tags.is_empty():
		for tag in req_tags:
			if inv.has_item_tag(String(tag)):
				return SUCCESS
					
	return FAILURE


func _item_has_tag(item_id: String, tag: String) -> bool:
	var def = ItemDB.get_def(item_id)
	if def != null and "tags" in def and def.tags is Array:
		return def.tags.has(tag)
	return false
