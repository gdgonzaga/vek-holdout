extends PanelContainer
class_name SquadCard
## A single squad management card in the Squads screen of Colony Management.
## Displays squad name, member list, deployment status, dismiss buttons,
## add/remove member controls, and delete squad action.

signal squad_modified()

@onready var _squad_name_label: Label = %SquadNameLabel
@onready var _squad_status_label: Label = %SquadStatusLabel
@onready var _dismiss_squad_button: Button = %DismissSquadButton
@onready var _delete_squad_button: Button = %DeleteSquadButton
@onready var _member_list: VBoxContainer = %MemberList
@onready var _no_members_label: Label = %NoMembersLabel
@onready var _add_member_option: OptionButton = %AddMemberOption
@onready var _add_member_button: Button = %AddMemberButton

var _squad_id: String = ""


func setup(squad_id: String) -> void:
	_squad_id = squad_id
	if not is_node_ready():
		ready.connect(_initial_refresh, CONNECT_ONE_SHOT)
	else:
		_initial_refresh()


func _initial_refresh() -> void:
	if _squad_id == "":
		return

	if _dismiss_squad_button != null and not _dismiss_squad_button.pressed.is_connected(_on_dismiss_squad_pressed):
		_dismiss_squad_button.pressed.connect(_on_dismiss_squad_pressed)

	if _delete_squad_button != null and not _delete_squad_button.pressed.is_connected(_on_delete_squad_pressed):
		_delete_squad_button.pressed.connect(_on_delete_squad_pressed)

	if _add_member_button != null and not _add_member_button.pressed.is_connected(_on_add_member_pressed):
		_add_member_button.pressed.connect(_on_add_member_pressed)

	refresh()


func refresh() -> void:
	if _squad_id == "" or Colony == null:
		return

	_squad_name_label.text = "SQUAD: %s" % _squad_id.to_upper()

	var member_ids: Array[String] = Colony.get_squad_members(_squad_id)
	var active_deploy_count := 0

	for child in _member_list.get_children():
		child.queue_free()

	if member_ids.is_empty():
		_no_members_label.visible = true
	else:
		_no_members_label.visible = false
		for cid in member_ids:
			var colonist := Colony.get_colonist(cid)
			var c_name := colonist.display_name if colonist != null else cid
			var hp_text := "HP: %d/%d" % [colonist.get_hp(), colonist.get_max_hp()] if colonist != null else ""
			var is_deployed := Colony.has_active_deployment(cid)
			if is_deployed:
				active_deploy_count += 1

			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)

			var name_lbl := Label.new()
			name_lbl.text = "• %s (%s)" % [c_name, hp_text]
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_lbl)

			var status_lbl := Label.new()
			if is_deployed:
				var pos = Colony.get_active_deployment_position(cid)
				var pos_str := "(%d, %d, %d)" % [int(pos.x), int(pos.y), int(pos.z)] if pos is Vector3 else ""
				status_lbl.text = "Stationed %s" % pos_str
				status_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 1.0))
			else:
				status_lbl.text = "On Duty"
				status_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
			row.add_child(status_lbl)

			if is_deployed:
				var dismiss_btn := Button.new()
				dismiss_btn.text = "Dismiss"
				dismiss_btn.pressed.connect(_on_dismiss_colonist_pressed.bind(cid))
				row.add_child(dismiss_btn)

			var remove_btn := Button.new()
			remove_btn.text = "Remove"
			remove_btn.pressed.connect(_on_remove_member_pressed.bind(cid))
			row.add_child(remove_btn)

			_member_list.add_child(row)

	if active_deploy_count > 0:
		_squad_status_label.text = "Status: Stationed (%d/%d deployed)" % [active_deploy_count, member_ids.size()]
		_squad_status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 1.0))
		_dismiss_squad_button.visible = true
	else:
		_squad_status_label.text = "Status: Routine (%d members)" % member_ids.size()
		_squad_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1.0))
		_dismiss_squad_button.visible = false

	_populate_available_candidates()


func _populate_available_candidates() -> void:
	if _add_member_option == null or Colony == null:
		return

	_add_member_option.clear()
	var squad_members: Array[String] = Colony.get_squad_members(_squad_id)
	var candidate_count := 0

	for colonist in Colony.colonists:
		if not is_instance_valid(colonist):
			continue
		if squad_members.has(colonist.colonist_id):
			continue
		var extra := " [In: %s]" % colonist.squad_id if colonist.squad_id != "" else ""
		_add_member_option.add_item("%s%s" % [colonist.display_name, extra])
		_add_member_option.set_item_metadata(candidate_count, colonist.colonist_id)
		candidate_count += 1

	_add_member_button.disabled = (candidate_count == 0)
	_add_member_option.disabled = (candidate_count == 0)


func _on_add_member_pressed() -> void:
	var selected_idx := _add_member_option.selected
	if selected_idx < 0:
		return
	var cid: String = str(_add_member_option.get_item_metadata(selected_idx))
	if cid != "":
		Colony.assign_to_squad(cid, _squad_id)
		refresh()
		squad_modified.emit()


func _on_remove_member_pressed(colonist_id: String) -> void:
	Colony.remove_from_squad(colonist_id)
	refresh()
	squad_modified.emit()


func _on_dismiss_colonist_pressed(colonist_id: String) -> void:
	Colony.cancel_deployments([colonist_id])
	refresh()
	squad_modified.emit()


func _on_dismiss_squad_pressed() -> void:
	Colony.cancel_squad_deployment(_squad_id)
	refresh()
	squad_modified.emit()


func _on_delete_squad_pressed() -> void:
	Colony.delete_squad(_squad_id)
	squad_modified.emit()
