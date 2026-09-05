extends PanelContainer
class_name JobRow
## A single job card in the Jobs screen of Colony Management.
## Displays job title, labor category, progress, assignees, and specialized
## details for hauling and construction tasks.

@onready var _title_label: Label = %TitleLabel
@onready var _labor_badge: Label = %LaborBadge
@onready var _status_badge: Label = %StatusBadge
@onready var _progress_bar: ProgressBar = %ProgressBar
@onready var _progress_label: Label = %ProgressLabel
@onready var _location_label: Label = %LocationLabel
@onready var _workers_label: Label = %WorkersLabel

@onready var _hauling_section: VBoxContainer = %HaulingSection
@onready var _hauling_item_label: Label = %HaulingItemLabel
@onready var _hauling_route_label: Label = %HaulingRouteLabel

@onready var _construction_section: VBoxContainer = %ConstructionSection
@onready var _construction_buildable_label: Label = %ConstructionBuildableLabel
@onready var _construction_materials_label: Label = %ConstructionMaterialsLabel

var _job: Variant = null


func setup(job: Variant) -> void:
	_job = job
	if not is_node_ready():
		ready.connect(_update_display, CONNECT_ONE_SHOT)
	else:
		_update_display()


func _update_display() -> void:
	if _job == null:
		return

	# 1. Title & Labor
	var title_str: String = "Job"
	if "title" in _job and not str(_job.title).is_empty():
		title_str = str(_job.title)
	elif "labor_id" in _job and not str(_job.labor_id).is_empty():
		title_str = str(_job.labor_id).capitalize() + " Job"
	_title_label.text = title_str

	var labor_str: String = str(_job.labor_id).to_lower() if "labor_id" in _job else ""
	_labor_badge.text = "[%s]" % (labor_str.capitalize() if not labor_str.is_empty() else "General")
	if labor_str == "construction":
		_labor_badge.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3, 1.0))
	elif labor_str == "hauling":
		_labor_badge.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0, 1.0))
	elif labor_str == "mining":
		_labor_badge.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5, 1.0))
	else:
		_labor_badge.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1.0))

	# 2. Status & Workers
	var is_sleeping: bool = ("sleep_until_msec" in _job) and (Time.get_ticks_msec() < int(_job.sleep_until_msec))
	var assignees: Array[String] = []
	if _job is Job:
		assignees.assign((_job as Job)._assigned_colonists)
	elif "active_claims" in _job and _job.active_claims is Dictionary:
		for cid in _job.active_claims:
			assignees.append(str(cid))

	if is_sleeping:
		var secs_left := int(ceil(float(_job.sleep_until_msec - Time.get_ticks_msec()) / 1000.0))
		_status_badge.text = "Cooldown (%ds)" % secs_left
		_status_badge.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
	elif not assignees.is_empty():
		_status_badge.text = "Active (%d worker%s)" % [assignees.size(), "" if assignees.size() == 1 else "s"]
		_status_badge.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5, 1.0))
	elif ("is_completed" in _job) and _job.is_completed:
		_status_badge.text = "Completed"
		_status_badge.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	else:
		_status_badge.text = "Available"
		_status_badge.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 1.0))

	if assignees.is_empty():
		_workers_label.text = "Workers: None"
	else:
		var names: Array[String] = []
		for cid in assignees:
			var c: Colonist = Colony.get_colonist(cid) if Colony != null and Colony.has_method("get_colonist") else null
			if c != null and not c.display_name.is_empty():
				names.append(c.display_name)
			else:
				names.append(cid.left(8))
		_workers_label.text = "Workers: %s" % ", ".join(names)

	# 3. Progress & Work Units
	var completed: int = int(_job.completed_units) if "completed_units" in _job else 0
	var total: int = int(_job.total_units) if "total_units" in _job else 1
	var unclaimed: int = int(_job.unclaimed_units) if "unclaimed_units" in _job else (total - completed)
	if total <= 0:
		total = 1
	var pct := clampf(float(completed) / float(total), 0.0, 1.0)
	_progress_bar.value = pct * 100.0
	_progress_label.text = "Progress: %d / %d units (%d%%) • Unclaimed: %d" % [
		completed, total, int(pct * 100.0), maxi(0, unclaimed)
	]

	# 4. Location & Anchor
	var anchor: Vector3i = _job.anchor_cell if "anchor_cell" in _job else Vector3i.ZERO
	var world_pos: Vector3 = Vector3.ZERO
	if "world_position" in _job and _job.world_position != Vector3.ZERO:
		world_pos = _job.world_position
	elif "location" in _job and _job.location != Vector3.ZERO:
		world_pos = _job.location
	elif anchor != Vector3i.ZERO:
		world_pos = Vector3(anchor) + Vector3(0.5, 0.0, 0.5)

	var loc_parts: Array[String] = []
	if anchor != Vector3i.ZERO:
		loc_parts.append("Anchor: %s" % str(anchor))
	elif world_pos != Vector3.ZERO:
		loc_parts.append("Pos: (%.1f, %.1f, %.1f)" % [world_pos.x, world_pos.y, world_pos.z])

	if "target_node" in _job and _job.target_node != null and is_instance_valid(_job.target_node):
		loc_parts.append("Target: %s" % _job.target_node.name)

	_location_label.text = " • ".join(loc_parts) if not loc_parts.is_empty() else "Location: General"

	# 5. Specialized: Hauling Section
	if labor_str == "hauling":
		_hauling_section.visible = true
		var item_str := ""
		if "item_id" in _job and not str(_job.item_id).is_empty():
			var idef = ItemDB.get_def(str(_job.item_id)) if ItemDB != null else null
			var iname: String = idef.resource_name if (idef != null and idef.resource_name != "") else str(_job.item_id)
			item_str = "Item: %s" % iname
			if "total_units" in _job and int(_job.total_units) > 0:
				item_str += " x%d" % int(_job.total_units)
		else:
			item_str = "Item: Stored / Carried Items"
		_hauling_item_label.text = item_str

		var src_str := "Ground / Storage"
		if "source_position" in _job and _job.source_position != Vector3.ZERO:
			src_str = "(%.1f, %.1f, %.1f)" % [_job.source_position.x, _job.source_position.y, _job.source_position.z]
		var dst_str := "Destination"
		if "target_position" in _job and _job.target_position != Vector3.ZERO:
			dst_str = "(%.1f, %.1f, %.1f)" % [_job.target_position.x, _job.target_position.y, _job.target_position.z]
		elif "target_node" in _job and _job.target_node != null and is_instance_valid(_job.target_node):
			dst_str = _job.target_node.name
		_hauling_route_label.text = "Route: %s -> %s" % [src_str, dst_str]
	else:
		_hauling_section.visible = false

	# 6. Specialized: Construction Section
	if labor_str == "construction":
		_construction_section.visible = true
		var target_node = _job.target_node if "target_node" in _job else null
		var buildable_name := "Buildable: Structure"
		var mat_str := "Materials: Complete / Free build"
		if target_node != null and is_instance_valid(target_node):
			if target_node is Blueprint:
				var bp := target_node as Blueprint
				var bdef_str: String = bp.target_def_id if bp.target_def_id != "" else "Blueprint"
				buildable_name = "Buildable: %s" % bdef_str.capitalize()
				if bp.has_complete_materials():
					mat_str = "Materials: Ready for Construction"
				else:
					var missing: Array[String] = []
					var target_def = bp._target_def() if bp.has_method("_target_def") else null
					if target_def != null and "material_cost" in target_def:
						for entry in target_def.material_cost:
							var rem: int = bp.remaining_need(entry.item_def.id)
							if rem > 0:
								var iname: String = entry.item_def.resource_name if (entry.item_def != null and entry.item_def.resource_name != "") else entry.item_def.id
								missing.append("%dx %s" % [rem, iname])
					if not missing.is_empty():
						mat_str = "Awaiting Materials: Needs %s" % ", ".join(missing)
					else:
						mat_str = "Awaiting Materials"
			else:
				buildable_name = "Object: %s" % target_node.name
		_construction_buildable_label.text = buildable_name
		_construction_materials_label.text = mat_str
	else:
		_construction_section.visible = false
