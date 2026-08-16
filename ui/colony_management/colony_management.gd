extends Control
## Colony Management window with tabbed sections for colony overview, colonist roster,
## labor assignments, crafting stations, and storage management.
##
## Opened via Tab hotkey (or UI button). Closed via Tab/Esc hotkey or close button.

const COLONIST_ENTRY_SCENE := preload("res://ui/colony_management/colonist_entry.tscn")
const ColonistEntryScript := preload("res://ui/colony_management/colonist_entry.gd")

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

var _selected_colonist: Colonist = null


func _ready() -> void:
	if _close_button != null:
		_close_button.pressed.connect(_on_close_pressed)
	if _tab_container != null:
		_tab_container.tab_changed.connect(_on_tab_changed)
	_refresh_colonist_roster()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("colony_management"):
		SceneManager.close_screen()
		get_viewport().set_input_as_handled()


func _on_close_pressed() -> void:
	SceneManager.close_screen()


func _on_tab_changed(_tab_index: int) -> void:
	if _tab_index == 1:
		_refresh_colonist_roster()


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
