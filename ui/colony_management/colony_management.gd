extends Control
## Colony Management window with tabbed sections for colony overview, colonist roster,
## labor assignments, crafting stations, and storage management.
##
## Opened via Tab hotkey (or UI button). Closed via Tab/Esc hotkey or close button.

const COLONIST_ENTRY_SCENE := preload("res://ui/colony_management/colonist_entry.tscn")
const ColonistEntryScript := preload("res://ui/colony_management/colonist_entry.gd")
const LABOR_CELL_SCENE := preload("res://ui/colony_management/labor_cell.tscn")
const CRAFTING_STATION_ROW_SCENE := preload("res://ui/colony_management/crafting_station_row.tscn")
const STORAGE_CONTAINER_ROW_SCENE := preload("res://ui/colony_management/storage_container_row.tscn")
const LaborCellScript := preload("res://ui/colony_management/labor_cell.gd")
const StorageContainerRowScript := preload("res://ui/colony_management/storage_container_row.gd")
const SQUAD_CARD_SCENE := preload("res://ui/colony_management/squad_card.tscn")
const SquadCardScript := preload("res://ui/colony_management/squad_card.gd")
const JOB_ROW_SCENE := preload("res://ui/colony_management/job_row.tscn")
const JobRowScript := preload("res://ui/colony_management/job_row.gd")

@onready var _close_button: Button = %CloseButton
@onready var _tab_container: TabContainer = %TabContainer

@onready var _info_current_day_label: Label = %InfoCurrentDayLabel
@onready var _info_elapsed_days_label: Label = %InfoElapsedDaysLabel
@onready var _info_play_time_label: Label = %InfoPlayTimeLabel
@onready var _info_colonist_count_label: Label = %InfoColonistCountLabel
@onready var _info_colonist_status_label: Label = %InfoColonistStatusLabel
@onready var _info_activity_summary_label: Label = %InfoActivitySummaryLabel
@onready var _info_active_jobs_label: Label = %InfoActiveJobsLabel
@onready var _info_storage_summary_label: Label = %InfoStorageSummaryLabel
@onready var _info_stations_count_label: Label = %InfoStationsCountLabel

@onready var _colonist_list: VBoxContainer = %ColonistList
@onready var _no_selection_label: Label = %NoSelectionLabel
@onready var _details_content: VBoxContainer = %DetailsContent
@onready var _detail_name_label: Label = %DetailNameLabel
@onready var _detail_id_label: Label = %DetailIdLabel
@onready var _detail_hp_label: Label = %DetailHpLabel
@onready var _detail_stamina_label: Label = %DetailStaminaLabel
@onready var _detail_mood_label: Label = %DetailMoodLabel
@onready var _detail_activity_label: Label = %DetailActivityLabel
@onready var _detail_needs_label: Label = %DetailNeedsLabel
@onready var _detail_goal_label: Label = %DetailGoalLabel
@onready var _detail_job_target_label: Label = %DetailJobTargetLabel
@onready var _detail_navigation_label: Label = %DetailNavigationLabel
@onready var _detail_blacklist_label: Label = %DetailBlacklistLabel
@onready var _detail_raid_stance_label: Label = %DetailRaidStanceLabel
@onready var _skills_grid: VBoxContainer = %SkillsGrid
@onready var _detail_inventory_weight_label: Label = %DetailInventoryWeightLabel
@onready var _detail_item_list: VBoxContainer = %DetailItemList

var _colonist_refresh_timer: float = 0.0
const COLONIST_REFRESH_INTERVAL: float = 0.25

@onready var _jobs_summary_label: Label = %JobsSummaryLabel
@onready var _job_category_filter: OptionButton = %JobCategoryFilter
@onready var _no_jobs_label: Label = %NoJobsLabel
@onready var _job_list: VBoxContainer = %JobList

var _jobs_refresh_timer: float = 0.0
const JOBS_REFRESH_INTERVAL: float = 0.5

@onready var _labors_grid: GridContainer = %LaborsGrid
@onready var _no_colonists_label: Label = %NoColonistsLabel

@onready var _crafting_station_list: VBoxContainer = %CraftingStationList
@onready var _no_stations_label: Label = %NoStationsLabel

@onready var _storage_list: VBoxContainer = %StorageList
@onready var _no_storage_label: Label = %NoStorageLabel
@onready var _storage_subtitle_label: Label = %StorageSubtitleLabel

@onready var _squad_list: VBoxContainer = %SquadList
@onready var _no_squads_label: Label = %NoSquadsLabel
@onready var _new_squad_line_edit: LineEdit = %NewSquadLineEdit
@onready var _create_squad_button: Button = %CreateSquadButton

var _selected_colonist: Colonist = null


func _ready() -> void:
	if _close_button != null:
		_close_button.pressed.connect(_on_close_pressed)
	if _tab_container != null:
		_tab_container.tab_changed.connect(_on_tab_changed)
	_refresh_colony_info()
	_refresh_colonist_roster()
	_refresh_labors_matrix()
	if _job_category_filter != null:
		_job_category_filter.clear()
		_job_category_filter.add_item("All Jobs")
		_job_category_filter.add_item("Hauling")
		_job_category_filter.add_item("Construction")
		_job_category_filter.add_item("Other")
		_job_category_filter.item_selected.connect(func(_idx: int) -> void: _refresh_jobs())
	if _create_squad_button != null:
		_create_squad_button.pressed.connect(_on_create_squad_pressed)
	if _new_squad_line_edit != null:
		_new_squad_line_edit.text_submitted.connect(func(_t: String) -> void: _on_create_squad_pressed())


func _process(delta: float) -> void:
	if not visible or _tab_container == null:
		return
	if _tab_container.current_tab == 0:
		_update_time_labels()
	elif _tab_container.current_tab == 1:
		_colonist_refresh_timer += delta
		if _colonist_refresh_timer >= COLONIST_REFRESH_INTERVAL:
			_colonist_refresh_timer = 0.0
			_refresh_live_colonist_details()
	elif _tab_container.current_tab == 3:
		_jobs_refresh_timer += delta
		if _jobs_refresh_timer >= JOBS_REFRESH_INTERVAL:
			_jobs_refresh_timer = 0.0
			_refresh_jobs(true)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("colony_management"):
		SceneManager.close_screen()
		get_viewport().set_input_as_handled()


func _on_close_pressed() -> void:
	SceneManager.close_screen()


func _on_tab_changed(_tab_index: int) -> void:
	if _tab_index == 0:
		_refresh_colony_info()
	elif _tab_index == 1:
		_refresh_colonist_roster()
	elif _tab_index == 2:
		_refresh_labors_matrix()
	elif _tab_index == 3:
		_refresh_jobs()
	elif _tab_index == 4:
		_refresh_crafting_stations()
	elif _tab_index == 5:
		_refresh_storage()
	elif _tab_index == 6:
		_refresh_squads()


func _refresh_colonist_roster() -> void:
	if _colonist_list == null:
		return

	for child in _colonist_list.get_children():
		child.queue_free()

	var roster: Array[Colonist] = Colony.colonists
	var selected_found := false

	for colonist in roster:
		if not is_instance_valid(colonist):
			continue
		var entry: Button = COLONIST_ENTRY_SCENE.instantiate() as Button
		_colonist_list.add_child(entry)
		entry.call("setup", colonist)
		if entry.has_signal("selected"):
			entry.connect("selected", _on_colonist_selected)
		if _selected_colonist == colonist:
			selected_found = true

	if not selected_found:
		if not roster.is_empty() and is_instance_valid(roster[0]):
			_selected_colonist = roster[0]
		else:
			_selected_colonist = null

	_update_details_view()


func _on_colonist_selected(colonist: Colonist) -> void:
	_selected_colonist = colonist
	_update_details_view()


func _update_details_view() -> void:
	if _no_selection_label == null or _details_content == null:
		return

	if _selected_colonist == null or not is_instance_valid(_selected_colonist):
		_no_selection_label.visible = true
		_details_content.visible = false
		return

	_no_selection_label.visible = false
	_details_content.visible = true

	_detail_name_label.text = _selected_colonist.display_name
	_detail_id_label.text = "ID: %s" % _selected_colonist.colonist_id
	_detail_hp_label.text = "Health: %d / %d" % [_selected_colonist.get_hp(), _selected_colonist.get_max_hp()]
	_detail_stamina_label.text = "Stamina: 100 / 100 (Stub)"
	_detail_mood_label.text = "Mood: Neutral / 100% (Stub)"

	_refresh_live_colonist_details()

	_detail_raid_stance_label.text = "Raid Stance: Default (%d)" % _selected_colonist.raid_stance

	_populate_skills()
	_populate_carried_items()


func _refresh_live_colonist_details() -> void:
	if _selected_colonist == null or not is_instance_valid(_selected_colonist):
		return
	if _details_content == null or not _details_content.visible:
		return

	if _detail_hp_label != null:
		_detail_hp_label.text = "Health: %d / %d" % [_selected_colonist.get_hp(), _selected_colonist.get_max_hp()]

	if _detail_needs_label != null:
		var needs_comp: ColonistNeeds = _selected_colonist.get_node_or_null("ColonistNeeds") as ColonistNeeds
		if needs_comp != null:
			var hunger_pct := int(round(needs_comp.get_need(&"hunger") * 100.0))
			var rest_pct := int(round(needs_comp.get_need(&"rest") * 100.0))
			var rec_pct := int(round(needs_comp.get_need(&"recreation") * 100.0))
			_detail_needs_label.text = "Needs: Hunger %d%% | Rest %d%% | Recreation %d%%" % [hunger_pct, rest_pct, rec_pct]
		else:
			_detail_needs_label.text = "Needs: Hunger 100% | Rest 100% | Recreation 100%"

	var goal: StringName = _get_colonist_goal(_selected_colonist)
	if _detail_goal_label != null:
		var goal_text := "None"
		if goal != &"none":
			goal_text = String(goal).capitalize()
		_detail_goal_label.text = "Brain Goal: %s" % goal_text

	if _detail_activity_label != null:
		_detail_activity_label.text = "Current Activity: %s" % _resolve_colonist_activity(_selected_colonist)

	if _detail_job_target_label != null:
		_detail_job_target_label.text = _resolve_job_target_info(_selected_colonist)

	if _detail_navigation_label != null:
		_detail_navigation_label.text = _resolve_navigation_info(_selected_colonist)

	if _detail_blacklist_label != null:
		_detail_blacklist_label.text = _resolve_blacklist_info(_selected_colonist)

	_populate_carried_items()

	if _colonist_list != null:
		for child in _colonist_list.get_children():
			if child.has_method("_update_display"):
				child.call("_update_display")


func _resolve_colonist_activity(colonist: Colonist) -> String:
	if colonist == null or not is_instance_valid(colonist):
		return "Idle"

	var path: Array = colonist.get("_path") if "_path" in colonist else []
	var path_idx: int = int(colonist.get("_path_index")) if "_path_index" in colonist else 0
	var is_moving: bool = not path.is_empty() and path_idx < path.size()

	var job_obj = _get_colonist_job_obj(colonist)
	var goal: StringName = _get_colonist_goal(colonist)

	if is_moving:
		if job_obj != null:
			return "Moving to %s" % _get_job_title(job_obj)
		elif goal == &"rest":
			return "Moving to Rest Area"
		elif goal == &"hunger":
			return "Moving to Food"
		elif goal == &"recreation":
			return "Moving to Recreation"
		return "Moving (Waypoint %d/%d)" % [path_idx + 1, path.size()]

	if job_obj != null:
		var title: String = _get_job_title(job_obj)
		if "completed_units" in job_obj and "total_units" in job_obj and int(job_obj.total_units) > 0:
			return "Working: %s (%d/%d units)" % [title, int(job_obj.completed_units), int(job_obj.total_units)]
		return "Working: %s" % title

	if goal != &"none" and goal != &"work":
		return "Satisfying %s" % String(goal).capitalize()

	return "Idle"


func _get_colonist_job_obj(colonist: Colonist) -> Variant:
	if colonist == null or not is_instance_valid(colonist):
		return null
	var bt: BTPlayer = colonist.get_node_or_null("BTPlayer") as BTPlayer
	if bt != null and bt.blackboard != null and bt.blackboard.has_var(&"active_job"):
		var j = bt.blackboard.get_var(&"active_job")
		if j != null:
			return j
	if colonist.current_job != null and is_instance_valid(colonist.current_job):
		return colonist.current_job
	return null


func _get_job_title(job_obj: Variant) -> String:
	if job_obj == null:
		return "Job"
	if "title" in job_obj and not str(job_obj.title).is_empty():
		return str(job_obj.title)
	elif "labor_id" in job_obj and not str(job_obj.labor_id).is_empty():
		return str(job_obj.labor_id).capitalize()
	elif "def" in job_obj and job_obj.def != null and "display_name" in job_obj.def:
		return str(job_obj.def.display_name)
	return "Job"


func _get_colonist_goal(colonist: Colonist) -> StringName:
	if colonist == null or not is_instance_valid(colonist):
		return &"none"
	var bt: BTPlayer = colonist.get_node_or_null("BTPlayer") as BTPlayer
	if bt != null and bt.blackboard != null and bt.blackboard.has_var(&"current_goal"):
		return bt.blackboard.get_var(&"current_goal")
	return &"none"


func _resolve_job_target_info(colonist: Colonist) -> String:
	if colonist == null or not is_instance_valid(colonist):
		return "Job Target: None"
	var job_obj = _get_colonist_job_obj(colonist)
	var target_str: String = ""
	var pos_str: String = ""
	var target_pos: Vector3 = Vector3.ZERO
	var has_target_pos := false

	if job_obj != null:
		var title := _get_job_title(job_obj)
		if "anchor_cell" in job_obj and job_obj.anchor_cell != Vector3i.ZERO:
			pos_str = "@ %s" % str(job_obj.anchor_cell)
			target_pos = Vector3(job_obj.anchor_cell) + Vector3(0.5, 0.0, 0.5)
			has_target_pos = true
		elif "target_node" in job_obj and job_obj.target_node != null and is_instance_valid(job_obj.target_node):
			pos_str = "-> %s" % job_obj.target_node.name
			target_pos = job_obj.target_node.global_position
			has_target_pos = true
		elif "world_position" in job_obj and job_obj.world_position != Vector3.ZERO:
			pos_str = "@ (%.1f, %.1f, %.1f)" % [job_obj.world_position.x, job_obj.world_position.y, job_obj.world_position.z]
			target_pos = job_obj.world_position
			has_target_pos = true
		elif "location" in job_obj and job_obj.location != Vector3.ZERO:
			pos_str = "@ (%.1f, %.1f, %.1f)" % [job_obj.location.x, job_obj.location.y, job_obj.location.z]
			target_pos = job_obj.location
			has_target_pos = true

		target_str = "%s %s" % [title, pos_str]
	else:
		var bt: BTPlayer = colonist.get_node_or_null("BTPlayer") as BTPlayer
		if bt != null and bt.blackboard != null and bt.blackboard.has_var(&"target_smart_object"):
			var obj = bt.blackboard.get_var(&"target_smart_object")
			if obj is Node3D and is_instance_valid(obj):
				target_str = "Smart Object -> %s" % obj.name
				target_pos = obj.global_position
				has_target_pos = true

	if target_str.is_empty():
		return "Job Target: None"

	if has_target_pos:
		var dist: float = colonist.global_position.distance_to(target_pos)
		return "Job Target: %s (Dist: %.1fm)" % [target_str.strip_edges(), dist]
	return "Job Target: %s" % target_str.strip_edges()


func _resolve_navigation_info(colonist: Colonist) -> String:
	if colonist == null or not is_instance_valid(colonist):
		return "Navigation: None"

	var pathfinder: VoxelPathfinder = colonist.get_node_or_null("VoxelPathfinder") as VoxelPathfinder
	var pf_status: String = pathfinder.last_status if pathfinder != null and not pathfinder.last_status.is_empty() else "OK"

	var path: Array = colonist.get("_path") if "_path" in colonist else []
	var path_idx: int = int(colonist.get("_path_index")) if "_path_index" in colonist else 0

	if not path.is_empty() and path_idx < path.size():
		var curr_wp: Vector3 = path[path_idx]
		var final_wp: Vector3 = path[-1]
		var dist_wp: float = colonist.global_position.distance_to(curr_wp)
		var dist_final: float = colonist.global_position.distance_to(final_wp)
		return "Navigation: Moving (Wp %d/%d, %.1fm | Dest: %.1fm) [A*: %s]" % [path_idx + 1, path.size(), dist_wp, dist_final, pf_status]
	elif not path.is_empty() and path_idx >= path.size():
		return "Navigation: Arrived [A*: %s]" % pf_status

	return "Navigation: Stationary [A*: %s]" % pf_status


func _resolve_blacklist_info(colonist: Colonist) -> String:
	if colonist == null or not is_instance_valid(colonist):
		return "Job Cooldowns: None"
	if Colony == null or Colony.job_board == null:
		return "Job Cooldowns: None"

	var bl_count := 0
	if "_colonist_blacklists" in Colony.job_board:
		var bl_dict: Dictionary = Colony.job_board._colonist_blacklists
		var now: int = Time.get_ticks_msec()
		for jid in bl_dict:
			var per_col: Dictionary = bl_dict[jid]
			if per_col.has(colonist.colonist_id) and int(per_col[colonist.colonist_id]) > now:
				bl_count += 1

	if bl_count > 0:
		return "Job Cooldowns: %d unreachable job(s) temporarily blacklisted" % bl_count
	return "Job Cooldowns: None"


func _populate_skills() -> void:
	if _skills_grid == null:
		return
	for child in _skills_grid.get_children():
		child.queue_free()

	if _selected_colonist.skill_set == null or _selected_colonist.skill_set.skill_defs == null:
		return

	for def in _selected_colonist.skill_set.skill_defs.skills:
		if def == null:
			continue
		var level: int = _selected_colonist.skill_set.get_level(def.skill_id)
		var mult: float = _selected_colonist.skill_set.get_multiplier(def.labor if def.labor != "" else def.skill_id)
		var label := Label.new()
		var sname: String = def.display_name if def.display_name != "" else def.skill_id.capitalize()
		label.text = "• %s: Level %d (Speed: %.1fx)" % [sname, level, mult]
		label.add_theme_font_size_override("font_size", 13)
		_skills_grid.add_child(label)


var _last_inventory_snapshot: Dictionary = {}


func _populate_carried_items(force: bool = false) -> void:
	if _detail_item_list == null or _detail_inventory_weight_label == null:
		return

	var inv: CharacterInventory = _selected_colonist.inventory if _selected_colonist != null else null
	if inv == null:
		_detail_inventory_weight_label.text = "Carry Capacity: 0.0 / 50.0 kg"
		if not force and _last_inventory_snapshot.is_empty() and _detail_item_list.get_child_count() > 0:
			return
		_last_inventory_snapshot.clear()
		for child in _detail_item_list.get_children():
			child.queue_free()
		var empty_lbl := Label.new()
		empty_lbl.text = "No carried items"
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		empty_lbl.add_theme_font_size_override("font_size", 13)
		_detail_item_list.add_child(empty_lbl)
		return

	_detail_inventory_weight_label.text = "Carry Weight: %.1f / %.1f kg" % [inv.current_weight(), inv.capacity]

	if not force and inv.items.hash() == _last_inventory_snapshot.hash():
		return

	_last_inventory_snapshot = inv.items.duplicate()
	for child in _detail_item_list.get_children():
		child.queue_free()

	var has_items := false
	for item_id in inv.items:
		var count: int = int(inv.items[item_id])
		if count <= 0:
			continue
		has_items = true
		var def: ItemDef = ItemDB.get_def(item_id)
		var iname: String = def.resource_name if (def != null and def.resource_name != "") else str(item_id)
		var weight: float = (def.weight * count) if def != null else 0.0
		var lbl := Label.new()
		lbl.text = "• %s  x%d  (%.1f kg)" % [iname, count, weight]
		lbl.add_theme_font_size_override("font_size", 13)
		_detail_item_list.add_child(lbl)

	if not has_items:
		var empty_lbl := Label.new()
		empty_lbl.text = "No carried items"
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		empty_lbl.add_theme_font_size_override("font_size", 13)
		_detail_item_list.add_child(empty_lbl)


func _get_available_labors() -> Array[LaborDef]:
	var labors: Array[LaborDef] = []
	var loaded_ids: Dictionary = {}

	var dir := DirAccess.open("res://data/labors/")
	if dir != null:
		dir.list_dir_begin()
		var fname := dir.get_next()
		while fname != "":
			if not dir.current_is_dir() and fname.ends_with(".tres"):
				var res = load("res://data/labors/" + fname)
				if res is LaborDef and res.id != "" and not loaded_ids.has(res.id):
					labors.append(res)
					loaded_ids[res.id] = true
			fname = dir.get_next()

	var fallback_paths := [
		"res://data/labors/construction.tres",
		"res://data/labors/crafting.tres",
		"res://data/labors/harvesting.tres",
		"res://data/labors/hauling.tres",
		"res://data/labors/mechanics.tres",
		"res://data/labors/smelting.tres",
	]
	for path in fallback_paths:
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is LaborDef and res.id != "" and not loaded_ids.has(res.id):
				labors.append(res)
				loaded_ids[res.id] = true

	labors.sort_custom(func(a: LaborDef, b: LaborDef) -> bool:
		return a.display_name.naturalcasecmp_to(b.display_name) < 0
	)
	return labors


func _refresh_labors_matrix() -> void:
	if _labors_grid == null:
		return

	for child in _labors_grid.get_children():
		child.queue_free()

	var roster: Array[Colonist] = Colony.colonists
	var valid_roster: Array[Colonist] = []
	for c in roster:
		if is_instance_valid(c):
			valid_roster.append(c)

	if valid_roster.is_empty():
		if _no_colonists_label != null:
			_no_colonists_label.visible = true
		_labors_grid.visible = false
		return

	if _no_colonists_label != null:
		_no_colonists_label.visible = false
	_labors_grid.visible = true

	var labors := _get_available_labors()
	_labors_grid.columns = 1 + labors.size()

	# Row 0: Header Row
	var name_hdr := PanelContainer.new()
	var name_hdr_lbl := Label.new()
	name_hdr_lbl.text = " Colonist "
	name_hdr_lbl.add_theme_font_size_override("font_size", 14)
	name_hdr_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8, 1))
	name_hdr.add_child(name_hdr_lbl)
	name_hdr.custom_minimum_size = Vector2(140, 36)
	_labors_grid.add_child(name_hdr)

	for labor in labors:
		var labor_hdr := PanelContainer.new()
		var labor_hdr_lbl := Label.new()
		labor_hdr_lbl.text = " %s " % labor.display_name
		labor_hdr_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		labor_hdr_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		labor_hdr_lbl.add_theme_font_size_override("font_size", 14)
		labor_hdr_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1))
		labor_hdr.add_child(labor_hdr_lbl)
		labor_hdr.custom_minimum_size = Vector2(80, 36)
		if labor.description != "":
			labor_hdr.tooltip_text = "%s\n%s" % [labor.display_name, labor.description]
		_labors_grid.add_child(labor_hdr)

	# Rows 1..M: Colonists
	for colonist in valid_roster:
		var name_panel := PanelContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = " %s " % colonist.display_name
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_panel.add_child(name_lbl)
		name_panel.custom_minimum_size = Vector2(140, 36)
		_labors_grid.add_child(name_panel)

		for labor in labors:
			var cell: Button = LABOR_CELL_SCENE.instantiate() as Button
			_labors_grid.add_child(cell)
			cell.call("setup", colonist, labor.id, labor.display_name)


func _refresh_jobs(live_tick: bool = false) -> void:
	if _job_list == null or _no_jobs_label == null:
		return

	var all_jobs: Array = []
	if Colony != null and Colony.job_board != null:
		all_jobs = Colony.job_board.get_all_jobs()

	# Summary counts
	var total_count: int = all_jobs.size()
	var active_count: int = 0
	var available_count: int = 0
	var cooldown_count: int = 0
	var now: int = Time.get_ticks_msec()

	for job in all_jobs:
		var is_sleeping: bool = ("sleep_until_msec" in job) and (now < int(job.sleep_until_msec))
		var has_workers: bool = false
		if job is Job:
			has_workers = not (job as Job)._assigned_colonists.is_empty()
		elif "active_claims" in job and job.active_claims is Dictionary:
			has_workers = not job.active_claims.is_empty()

		if is_sleeping:
			cooldown_count += 1
		elif has_workers:
			active_count += 1
		else:
			available_count += 1

	if _jobs_summary_label != null:
		_jobs_summary_label.text = "Total Jobs: %d | Active: %d | Available: %d | Cooldown: %d" % [
			total_count, active_count, available_count, cooldown_count
		]

	# Filtering
	var filter_idx: int = _job_category_filter.selected if _job_category_filter != null else 0
	var filtered_jobs: Array = []
	for job in all_jobs:
		var labor_str: String = str(job.labor_id).to_lower() if "labor_id" in job else ""
		if filter_idx == 1 and labor_str != "hauling":
			continue
		elif filter_idx == 2 and labor_str != "construction":
			continue
		elif filter_idx == 3 and (labor_str == "hauling" or labor_str == "construction"):
			continue
		filtered_jobs.append(job)

	if filtered_jobs.is_empty():
		_no_jobs_label.visible = true
		_job_list.visible = false
		for child in _job_list.get_children():
			child.queue_free()
		return

	_no_jobs_label.visible = false
	_job_list.visible = true

	# Live tick update optimization
	var can_reuse := false
	if live_tick and _job_list.get_child_count() == filtered_jobs.size():
		can_reuse = true
		for i in range(filtered_jobs.size()):
			var row = _job_list.get_child(i)
			if not (row is JobRowScript) or row.get("_job") != filtered_jobs[i]:
				can_reuse = false
				break

	if can_reuse:
		for i in range(filtered_jobs.size()):
			var row = _job_list.get_child(i)
			if row.has_method("_update_display"):
				row.call("_update_display")
		return

	for child in _job_list.get_children():
		child.queue_free()

	for job in filtered_jobs:
		var row: PanelContainer = JOB_ROW_SCENE.instantiate() as PanelContainer
		_job_list.add_child(row)
		row.call("setup", job)


func _refresh_crafting_stations() -> void:
	if _crafting_station_list == null:
		return

	for child in _crafting_station_list.get_children():
		child.queue_free()

	var stations := _get_all_crafting_stations()
	if stations.is_empty():
		if _no_stations_label != null:
			_no_stations_label.visible = true
		_crafting_station_list.visible = false
		return

	if _no_stations_label != null:
		_no_stations_label.visible = false
	_crafting_station_list.visible = true

	for station in stations:
		var row: CraftingStationRow = CRAFTING_STATION_ROW_SCENE.instantiate() as CraftingStationRow
		_crafting_station_list.add_child(row)
		row.setup(station)


func _get_all_crafting_stations() -> Array[CraftingStation]:
	var stations: Array[CraftingStation] = []
	if Colony == null or Colony.storage_registry == null:
		return stations
	var raw_container = Colony.storage_registry.get("_container")
	if raw_container == null or not is_instance_valid(raw_container):
		return stations
	var container: Node3D = raw_container as Node3D

	for child in container.get_children():
		if is_instance_valid(child) and child is Furniture:
			var station := child.get_node_or_null("CraftingStation") as CraftingStation
			if station != null:
				stations.append(station)
	return stations


func _refresh_storage() -> void:
	if _storage_list == null:
		return

	for child in _storage_list.get_children():
		child.queue_free()

	var containers := _get_all_storage_containers()
	if containers.is_empty():
		if _no_storage_label != null:
			_no_storage_label.visible = true
		_storage_list.visible = false
		if _storage_subtitle_label != null:
			_storage_subtitle_label.text = "No storage containers built in colony."
		return

	if _no_storage_label != null:
		_no_storage_label.visible = false
	_storage_list.visible = true

	var total_weight: float = 0.0
	var total_capacity: float = 0.0
	var unique_item_types: Dictionary = {}

	for container in containers:
		var inv: StorageInventory = Colony.storage_registry.inventory_of(container) if (Colony != null and Colony.storage_registry != null) else (container.get_node_or_null("StorageInventory") as StorageInventory)
		if inv != null:
			total_weight += inv.current_weight()
			total_capacity += inv.capacity
			for item_id in inv.items:
				unique_item_types[item_id] = unique_item_types.get(item_id, 0) + inv.items[item_id]

		var row := STORAGE_CONTAINER_ROW_SCENE.instantiate() as PanelContainer
		_storage_list.add_child(row)
		row.setup(container)

	if _storage_subtitle_label != null:
		_storage_subtitle_label.text = "Containers: %d  |  Total Stock: %.1f / %.1f kg  |  Unique Item Types: %d" % [
			containers.size(), total_weight, total_capacity, unique_item_types.size()
		]


func _get_all_storage_containers() -> Array[Furniture]:
	if Colony != null and Colony.storage_registry != null:
		return Colony.storage_registry.get_all_crates()
	return []



func _refresh_colony_info() -> void:
	_update_time_labels()
	_update_population_summary()
	_update_operations_summary()


func _update_time_labels() -> void:
	if _info_current_day_label != null:
		var tod_pct := int(TimeSystem.get_time_of_day_fraction() * 100.0)
		_info_current_day_label.text = "Current Day: Day %d (%d%%)" % [GameState.current_day, tod_pct]
	if _info_elapsed_days_label != null:
		_info_elapsed_days_label.text = "Elapsed In-Game Days: %.2f days" % TimeSystem.get_elapsed_days()
	if _info_play_time_label != null:
		_info_play_time_label.text = "Realtime Play Time: %s" % TimeSystem.get_realtime_play_time_formatted()


func _update_population_summary() -> void:
	var roster: Array[Colonist] = Colony.colonists
	var valid_roster: Array[Colonist] = []
	for c in roster:
		if is_instance_valid(c):
			valid_roster.append(c)

	var count := valid_roster.size()
	var cap: int = Colony.MVP_CAP

	if _info_colonist_count_label != null:
		_info_colonist_count_label.text = "Colonists: %d / %d" % [count, cap]

	var healthy := 0
	var injured := 0
	var working := 0
	var idle := 0

	for c in valid_roster:
		if c.get_hp() >= c.get_max_hp():
			healthy += 1
		else:
			injured += 1

		if c.current_job != null:
			working += 1
		else:
			idle += 1

	if _info_colonist_status_label != null:
		_info_colonist_status_label.text = "Status: Healthy (%d) | Injured (%d)" % [healthy, injured]

	if _info_activity_summary_label != null:
		_info_activity_summary_label.text = "Activity: Working (%d) | Idle (%d)" % [working, idle]


func _update_operations_summary() -> void:
	if _info_active_jobs_label != null:
		var job_count := Colony.job_board.get_jobs().size() if (Colony != null and Colony.job_board != null) else 0
		_info_active_jobs_label.text = "Jobs on Board: %d" % job_count

	if _info_storage_summary_label != null:
		var containers := _get_all_storage_containers()
		var total_weight: float = 0.0
		var total_cap: float = 0.0
		for container in containers:
			var inv: StorageInventory = Colony.storage_registry.inventory_of(container) if (Colony != null and Colony.storage_registry != null) else (container.get_node_or_null("StorageInventory") as StorageInventory)
			if inv != null:
				total_weight += inv.current_weight()
				total_cap += inv.capacity
		_info_storage_summary_label.text = "Storage: %d crates (%.1f / %.1f kg)" % [containers.size(), total_weight, total_cap]

	if _info_stations_count_label != null:
		var stations := _get_all_crafting_stations()
		_info_stations_count_label.text = "Crafting Workstations: %d" % stations.size()


func _refresh_squads() -> void:
	if _squad_list == null:
		return

	for child in _squad_list.get_children():
		child.queue_free()

	if Colony == null or Colony.squads.is_empty():
		if _no_squads_label != null:
			_no_squads_label.visible = true
		_squad_list.visible = false
		return

	if _no_squads_label != null:
		_no_squads_label.visible = false
	_squad_list.visible = true

	for squad_id in Colony.squads.keys():
		var card: SquadCard = SQUAD_CARD_SCENE.instantiate() as SquadCard
		_squad_list.add_child(card)
		card.setup(str(squad_id))
		card.squad_modified.connect(_refresh_squads)


func _on_create_squad_pressed() -> void:
	if _new_squad_line_edit == null or Colony == null:
		return
	var squad_name := _new_squad_line_edit.text.strip_edges()
	if squad_name == "":
		return
	Colony.create_squad(squad_name)
	_new_squad_line_edit.text = ""
	_refresh_squads()
