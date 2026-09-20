class_name ColonistDetailsPanel
extends VBoxContainer
## Details pane of the Colonists tab for the selected colonist, split into sub-tabs so the Gear
## editor is no longer buried at the bottom of one long scroll: Overview (vitals, needs,
## moodlets, activity), Gear (equipment slots + picker), Skills & Carry, and Debug (AI and
## navigation telemetry, hidden outside debug builds). Owned by colony_management, which calls
## set_colonist() on selection and refresh_live() on its live-refresh tick.
##
## The activity / navigation / skills / carried-items helpers under "Auxiliary Functions" were
## relocated from colony_management.gd; only the selected-colonist field name changed.

const OVERVIEW_TAB: int = 0
const GEAR_TAB: int = 1
const SKILLS_TAB: int = 2
const DEBUG_TAB: int = 3

## Storage and pocket changes have no signal, so the Gear tab re-evaluates its status text on this tick.
const GEAR_REFRESH_INTERVAL: float = 1.0

var _colonist: Colonist = null
var _gear_refresh_timer: float = 0.0
var _last_inventory_snapshot: Dictionary = {}

@onready var _sub_tabs: TabContainer = %DetailSubTabs
@onready var _detail_name_label: Label = %DetailNameLabel
@onready var _detail_id_label: Label = %DetailIdLabel
@onready var _detail_hp_label: Label = %DetailHpLabel
@onready var _detail_needs_label: Label = %DetailNeedsLabel
@onready var _detail_mood_label: Label = %DetailMoodLabel
@onready var _detail_activity_label: Label = %DetailActivityLabel
@onready var _detail_goal_label: Label = %DetailGoalLabel
@onready var _detail_job_target_label: Label = %DetailJobTargetLabel
@onready var _detail_navigation_label: Label = %DetailNavigationLabel
@onready var _detail_blacklist_label: Label = %DetailBlacklistLabel
@onready var _skills_grid: VBoxContainer = %SkillsGrid
@onready var _detail_inventory_weight_label: Label = %DetailInventoryWeightLabel
@onready var _detail_item_list: VBoxContainer = %DetailItemList
@onready var _equipment_panel: ColonistEquipmentPanel = %ColonistEquipmentPanel

# =================
# Primary Functions
# =================

func _ready() -> void:
	# 1. Sub-tab Events: refresh a sub-tab's content the moment the player switches to it.
	_sub_tabs.tab_changed.connect(_on_sub_tab_changed)

	# 2. Debug Tab: developer telemetry stays in the scene (unique-name lookups keep working) but is hidden in release builds.
	_sub_tabs.set_tab_hidden(DEBUG_TAB, not OS.is_debug_build())


func _process(delta: float) -> void:
	if _colonist == null or not is_visible_in_tree() or _sub_tabs.current_tab != GEAR_TAB:
		return
	_gear_refresh_timer += delta
	if _gear_refresh_timer >= GEAR_REFRESH_INTERVAL:
		_gear_refresh_timer = 0.0

		# 1. Gear Tick: re-evaluate status reasons and stock, which have no change signals.
		_equipment_panel.refresh_display()


## Shows `colonist` (or nothing for null) and fills every sub-tab once, so a tab switch or a
## test never sees stale data from the previous selection.
func set_colonist(colonist: Colonist) -> void:
	_gear_refresh_timer = 0.0
	_last_inventory_snapshot.clear()
	if colonist == null or not is_instance_valid(colonist):
		_colonist = null
		_equipment_panel.set_colonist(null)
		return
	_colonist = colonist

	# 1. Header: name and id are shown above every sub-tab.
	_refresh_header()

	# 2. Sub-tab Content: fill all four sub-tabs, not just the visible one.
	_refresh_overview()
	_refresh_debug()
	_populate_skills()
	_populate_carried_items(true)

	# 3. Gear: bind the equipment panel, which then follows the colonist's Equipment signals.
	_equipment_panel.set_colonist(colonist)


## Live-refresh tick from colony_management: updates only the sub-tab the player is looking at.
func refresh_live() -> void:
	if _colonist == null or not is_instance_valid(_colonist):
		return

	# 1. Visible Sub-tab: skip the other three, which the player cannot see and which refresh on switch.
	_refresh_sub_tab(_sub_tabs.current_tab)

# ===================
# Auxiliary Functions
# ===================

func _on_sub_tab_changed(tab_index: int) -> void:
	if _colonist != null and is_instance_valid(_colonist):
		_refresh_sub_tab(tab_index)


func _refresh_sub_tab(tab_index: int) -> void:
	## Auxiliary: Refreshes the content of one sub-tab.
	match tab_index:
		OVERVIEW_TAB:
			_refresh_overview()
		GEAR_TAB:
			_equipment_panel.refresh_display()
		SKILLS_TAB:
			_populate_carried_items()
		DEBUG_TAB:
			_refresh_debug()


func _refresh_header() -> void:
	## Auxiliary: Name and (muted) id above the sub-tabs.
	_detail_name_label.text = _colonist.display_name
	_detail_id_label.text = "ID: %s" % _colonist.colonist_id


func _refresh_overview() -> void:
	## Auxiliary: Player-facing vitals: health, needs, moodlets and what the colonist is doing.
	_detail_hp_label.text = "Health: %d / %d" % [_colonist.get_hp(), _colonist.get_max_hp()]
	_detail_needs_label.text = _needs_text(_colonist)
	_detail_mood_label.text = _mood_text(_colonist)
	_detail_activity_label.text = "Current Activity: %s" % _resolve_colonist_activity(_colonist)


func _refresh_debug() -> void:
	## Auxiliary: Developer telemetry: brain goal, job target, navigation and job cooldowns.
	var goal: StringName = _get_colonist_goal(_colonist)
	var goal_text: String = "None" if goal == &"none" else String(goal).capitalize()
	_detail_goal_label.text = "Brain Goal: %s" % goal_text
	_detail_job_target_label.text = _resolve_job_target_info(_colonist)
	_detail_navigation_label.text = _resolve_navigation_info(_colonist)
	_detail_blacklist_label.text = _resolve_blacklist_info(_colonist)


func _needs_text(colonist: Colonist) -> String:
	## Auxiliary: "Needs: Hunger a% | Rest b% | Recreation c%", or "n/a" when the colonist has no needs component.
	var needs_comp: ColonistNeeds = colonist.get_node_or_null("ColonistNeeds") as ColonistNeeds
	if needs_comp == null:
		return "Needs: n/a"
	var hunger_pct: int = int(round(needs_comp.get_need(&"hunger") * 100.0))
	var rest_pct: int = int(round(needs_comp.get_need(&"rest") * 100.0))
	var rec_pct: int = int(round(needs_comp.get_need(&"recreation") * 100.0))
	return "Needs: Hunger %d%% | Rest %d%% | Recreation %d%%" % [hunger_pct, rest_pct, rec_pct]


func _mood_text(colonist: Colonist) -> String:
	## Auxiliary: "Mood: " plus the names of active moodlets, or a plain none-message.
	var names: Array[String] = []
	for moodlet: Dictionary in colonist.get_active_moodlets():
		var moodlet_name: String = str(moodlet.get("name", ""))
		if not moodlet_name.is_empty():
			names.append(moodlet_name)
	return "Mood: %s" % (", ".join(names) if not names.is_empty() else "no active moodlets")


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
			if is_instance_valid(obj) and obj is Node3D:
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

	if _colonist.skill_set == null or _colonist.skill_set.skill_defs == null:
		return

	for def in _colonist.skill_set.skill_defs.skills:
		if def == null:
			continue
		var level: int = _colonist.skill_set.get_level(def.skill_id)
		var mult: float = _colonist.skill_set.get_multiplier(def.labor if def.labor != "" else def.skill_id)
		var label := Label.new()
		var sname: String = def.display_name if def.display_name != "" else def.skill_id.capitalize()
		label.text = "• %s: Level %d (Speed: %.1fx)" % [sname, level, mult]
		label.add_theme_font_size_override("font_size", 13)
		_skills_grid.add_child(label)


func _populate_carried_items(force: bool = false) -> void:
	if _detail_item_list == null or _detail_inventory_weight_label == null:
		return

	var inv: CharacterInventory = _colonist.inventory if _colonist != null else null
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
	for item_id in ItemStackOrder.sorted_item_ids(inv.items):
		var count: int = int(inv.items[item_id])
		if count <= 0:
			continue
		has_items = true
		var def: ItemDef = ItemDB.get_def(item_id)
		var iname: String = ItemDB.get_display_name(str(item_id))
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
