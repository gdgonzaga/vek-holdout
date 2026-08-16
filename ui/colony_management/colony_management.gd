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

@onready var _close_button: Button = %CloseButton
@onready var _tab_container: TabContainer = %TabContainer

@onready var _colonist_list: VBoxContainer = %ColonistList
@onready var _no_selection_label: Label = %NoSelectionLabel
@onready var _details_content: VBoxContainer = %DetailsContent
@onready var _detail_name_label: Label = %DetailNameLabel
@onready var _detail_id_label: Label = %DetailIdLabel
@onready var _detail_hp_label: Label = %DetailHpLabel
@onready var _detail_stamina_label: Label = %DetailStaminaLabel
@onready var _detail_mood_label: Label = %DetailMoodLabel
@onready var _detail_activity_label: Label = %DetailActivityLabel
@onready var _detail_raid_stance_label: Label = %DetailRaidStanceLabel
@onready var _skills_grid: VBoxContainer = %SkillsGrid
@onready var _detail_inventory_weight_label: Label = %DetailInventoryWeightLabel
@onready var _detail_item_list: VBoxContainer = %DetailItemList

@onready var _labors_grid: GridContainer = %LaborsGrid
@onready var _no_colonists_label: Label = %NoColonistsLabel

@onready var _crafting_station_list: VBoxContainer = %CraftingStationList
@onready var _no_stations_label: Label = %NoStationsLabel

@onready var _storage_list: VBoxContainer = %StorageList
@onready var _no_storage_label: Label = %NoStorageLabel
@onready var _storage_subtitle_label: Label = %StorageSubtitleLabel

var _selected_colonist: Colonist = null


func _ready() -> void:
	if _close_button != null:
		_close_button.pressed.connect(_on_close_pressed)
	if _tab_container != null:
		_tab_container.tab_changed.connect(_on_tab_changed)
	_refresh_colonist_roster()
	_refresh_labors_matrix()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("colony_management"):
		SceneManager.close_screen()
		get_viewport().set_input_as_handled()


func _on_close_pressed() -> void:
	SceneManager.close_screen()


func _on_tab_changed(_tab_index: int) -> void:
	if _tab_index == 1:
		_refresh_colonist_roster()
	elif _tab_index == 2:
		_refresh_labors_matrix()
	elif _tab_index == 3:
		_refresh_crafting_stations()
	elif _tab_index == 4:
		_refresh_storage()


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

	var act: String = "Idle"
	if _selected_colonist.current_job != null and is_instance_valid(_selected_colonist.current_job):
		var t: String = _selected_colonist.current_job.title
		act = t if t != "" else _selected_colonist.current_job.labor_id.capitalize()
	_detail_activity_label.text = "Current Activity: %s" % act
	_detail_raid_stance_label.text = "Raid Stance: Default (%d)" % _selected_colonist.raid_stance

	_populate_skills()
	_populate_carried_items()


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


func _populate_carried_items() -> void:
	if _detail_item_list == null or _detail_inventory_weight_label == null:
		return
	for child in _detail_item_list.get_children():
		child.queue_free()

	var inv: CharacterInventory = _selected_colonist.inventory
	if inv == null:
		_detail_inventory_weight_label.text = "Carry Capacity: 0.0 / 50.0 kg"
		var empty_lbl := Label.new()
		empty_lbl.text = "No carried items"
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		empty_lbl.add_theme_font_size_override("font_size", 13)
		_detail_item_list.add_child(empty_lbl)
		return

	_detail_inventory_weight_label.text = "Carry Weight: %.1f / %.1f kg" % [inv.current_weight(), inv.capacity]

	if inv.items.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No carried items"
		empty_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		empty_lbl.add_theme_font_size_override("font_size", 13)
		_detail_item_list.add_child(empty_lbl)
		return

	for item_id in inv.items:
		var count: int = inv.items[item_id]
		var def: ItemDef = ItemDB.get_def(item_id)
		var iname: String = def.resource_name if (def != null and def.resource_name != "") else item_id
		var weight: float = (def.weight * count) if def != null else 0.0
		var lbl := Label.new()
		lbl.text = "• %s  x%d  (%.1f kg)" % [iname, count, weight]
		lbl.add_theme_font_size_override("font_size", 13)
		_detail_item_list.add_child(lbl)


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
	var container: Node3D = Colony.storage_registry.get("_container") as Node3D
	if container == null or not is_instance_valid(container):
		return stations

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
