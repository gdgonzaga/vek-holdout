class_name AreaCard
extends PanelContainer
## A single area management card in the Areas tab of Colony Management (ARCH "UI").
## Displays area name (editable), bounds, Y-layer height, colonist member roster,
## add/remove member controls, and delete area action.

signal area_modified()

@onready var _area_name_edit: LineEdit = %AreaNameEdit
@onready var _area_bounds_label: Label = %AreaBoundsLabel
@onready var _delete_area_button: Button = %DeleteAreaButton
@onready var _member_list: VBoxContainer = %MemberList
@onready var _no_members_label: Label = %NoMembersLabel
@onready var _add_member_option: OptionButton = %AddMemberOption
@onready var _add_member_button: Button = %AddMemberButton

var _area_id: String = ""


# =================
# Primary Functions
# =================

func setup(area_id: String) -> void:
	_area_id = area_id
	if not is_node_ready():
		ready.connect(_initial_refresh, CONNECT_ONE_SHOT)
	else:
		# 1. UI Setup: Connects signals and loads initial area values.
		_initial_refresh()


func refresh() -> void:
	if _area_id == "" or Colony == null or Colony.area_manager == null:
		return
	var area: Area = Colony.area_manager.get_area(_area_id)
	if area == null:
		return

	# 1. Header Population: Syncs name edit text and bounds info label.
	_refresh_header(area)
	# 2. Member Roster Display: Rebuilds colonist member rows with removal actions.
	_refresh_member_roster(area)
	# 3. Candidate Selector: Fills candidate dropdown with unassigned colonists.
	_populate_available_candidates(area)


# ===================
# Auxiliary Functions
# ===================

func _initial_refresh() -> void:
	## Auxiliary: Connects widget button signals and populates card contents.
	if _area_name_edit != null and not _area_name_edit.text_submitted.is_connected(_on_name_submitted):
		_area_name_edit.text_submitted.connect(_on_name_submitted)
		_area_name_edit.focus_exited.connect(_on_name_focus_exited)

	if _delete_area_button != null and not _delete_area_button.pressed.is_connected(_on_delete_area_pressed):
		_delete_area_button.pressed.connect(_on_delete_area_pressed)

	if _add_member_button != null and not _add_member_button.pressed.is_connected(_on_add_member_pressed):
		_add_member_button.pressed.connect(_on_add_member_pressed)

	refresh()


func _refresh_header(area: Area) -> void:
	## Auxiliary: Sets name field text and formats bounds coordinates text.
	if _area_name_edit != null and not _area_name_edit.has_focus():
		_area_name_edit.text = area.display_name

	if _area_bounds_label != null:
		var bounds: Dictionary = area.get_outer_bounds()
		var b_min: Vector3i = bounds.get("min", Vector3i.ZERO)
		var b_max: Vector3i = bounds.get("max", Vector3i.ZERO)
		var count: int = area.boxes.size()
		_area_bounds_label.text = "%d Box%s | Bounds: (%d, %d, %d)..(%d, %d, %d)" % [
			count, "es" if count != 1 else "",
			b_min.x, b_min.y, b_min.z,
			b_max.x, b_max.y, b_max.z
		]


func _refresh_member_roster(area: Area) -> void:
	## Auxiliary: Clears and repopulates colonist member rows.
	if _member_list == null:
		return

	for child in _member_list.get_children():
		child.queue_free()

	if area.member_colonist_ids.is_empty():
		if _no_members_label != null:
			_no_members_label.visible = true
	else:
		if _no_members_label != null:
			_no_members_label.visible = false

		for cid in area.member_colonist_ids:
			var row := _build_member_row(cid)
			_member_list.add_child(row)


func _build_member_row(cid: String) -> HBoxContainer:
	## Auxiliary: Creates a single colonist member row containing name, HP, and remove button.
	var colonist := Colony.get_colonist(cid)
	var c_name := colonist.display_name if colonist != null else cid
	var hp_text := "HP: %d/%d" % [colonist.get_hp(), colonist.get_max_hp()] if colonist != null else ""

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var name_lbl := Label.new()
	name_lbl.text = "• %s (%s)" % [c_name, hp_text]
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(_on_remove_member_pressed.bind(cid))
	row.add_child(remove_btn)

	return row


func _populate_available_candidates(area: Area) -> void:
	## Auxiliary: Populates option button with colonists not yet assigned to this area.
	if _add_member_option == null or Colony == null:
		return

	_add_member_option.clear()
	var candidate_count := 0

	for colonist in Colony.colonists:
		if not is_instance_valid(colonist):
			continue
		if area.member_colonist_ids.has(colonist.colonist_id):
			continue
		_add_member_option.add_item(colonist.display_name)
		_add_member_option.set_item_metadata(candidate_count, colonist.colonist_id)
		candidate_count += 1

	if _add_member_button != null:
		_add_member_button.disabled = (candidate_count == 0)
	_add_member_option.disabled = (candidate_count == 0)


func _on_name_submitted(new_text: String) -> void:
	## Auxiliary: Applies name edit when user presses Enter in line edit.
	_commit_rename(new_text)


func _on_name_focus_exited() -> void:
	## Auxiliary: Applies name edit when user clicks outside the line edit.
	if _area_name_edit != null:
		_commit_rename(_area_name_edit.text)


func _commit_rename(new_text: String) -> void:
	## Auxiliary: Persists area rename to AreaManager and signals modification.
	var trimmed := new_text.strip_edges()
	if trimmed.is_empty() or Colony == null or Colony.area_manager == null:
		return
	var area: Area = Colony.area_manager.get_area(_area_id)
	if area != null and area.display_name != trimmed:
		Colony.area_manager.rename_area(_area_id, trimmed)
		area_modified.emit()


func _on_delete_area_pressed() -> void:
	## Auxiliary: Removes this area from AreaManager and signals modification.
	if Colony != null and Colony.area_manager != null:
		Colony.area_manager.delete_area(_area_id)
		area_modified.emit()


func _on_add_member_pressed() -> void:
	## Auxiliary: Adds selected colonist to area and updates UI.
	if _add_member_option == null or Colony == null or Colony.area_manager == null:
		return
	var selected_idx := _add_member_option.selected
	if selected_idx < 0:
		return
	var cid: String = str(_add_member_option.get_item_metadata(selected_idx))
	if cid != "":
		Colony.area_manager.add_member(_area_id, cid)
		refresh()
		area_modified.emit()


func _on_remove_member_pressed(colonist_id: String) -> void:
	## Auxiliary: Removes specified colonist from area and updates UI.
	if Colony != null and Colony.area_manager != null:
		Colony.area_manager.remove_member(_area_id, colonist_id)
		refresh()
		area_modified.emit()
