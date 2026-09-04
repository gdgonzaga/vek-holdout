class_name DebugItemSpawn
extends Control
## Debug screen to inspect and spawn any item registered in ItemDB.
## Opened via the debug_item_spawn input hotkey (F8) or SceneManager.
##
## Spawns items as WorldItem nodes in the 3D world in front of the active player.

const ROW_SCENE := preload("res://ui/debug_item_spawn/debug_item_row.tscn")
const RowScript := preload("res://ui/debug_item_spawn/debug_item_row.gd")

@onready var _close_button: Button = %CloseButton
@onready var _search_edit: LineEdit = %SearchEdit
@onready var _count_label: Label = %CountLabel
@onready var _item_list: VBoxContainer = %ItemList
@onready var _status_label: Label = %StatusLabel

var _total_count: int = 0


func _ready() -> void:
	_close_button.pressed.connect(_on_close_pressed)
	_search_edit.text_changed.connect(_on_search_text_changed)
	_search_edit.text_submitted.connect(_on_search_text_submitted)
	populate()
	_search_edit.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("debug_item_spawn"):
		get_viewport().set_input_as_handled()
		_on_close_pressed()


func populate() -> void:
	for child in _item_list.get_children():
		_item_list.remove_child(child)
		child.queue_free()

	var defs: Array[ItemDef] = ItemDB.get_all_defs() if ItemDB != null else []
	# Sort alphabetically by id
	defs.sort_custom(func(a: ItemDef, b: ItemDef) -> bool:
		return a.id.to_lower() < b.id.to_lower()
	)

	_total_count = defs.size()

	for def in defs:
		var row: DebugItemRow = ROW_SCENE.instantiate() as DebugItemRow
		_item_list.add_child(row)
		row.setup(def)
		row.spawn_requested.connect(_on_spawn_requested)

	_update_count_label(_total_count)

	if _search_edit != null and not _search_edit.text.is_empty():
		filter_entries(_search_edit.text)


func filter_entries(query: String) -> void:
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		for child in _item_list.get_children():
			if child is Control:
				child.visible = true
		_update_count_label(_total_count)
		return

	var visible_count := 0
	for child in _item_list.get_children():
		var row := child as DebugItemRow
		if row == null:
			continue
		var score := _match_score(q, row)
		if score > 0:
			row.visible = true
			visible_count += 1
		else:
			row.visible = false

	_update_count_label(visible_count)


func _match_score(q: String, row: DebugItemRow) -> int:
	# Check ID
	var id_match: String = row.item_id.to_lower()
	if id_match == q:
		return 1000
	if id_match.begins_with(q):
		return 800
	if id_match.find(q) != -1:
		return 500

	# Check Display Name
	var name_match: String = row.display_name.to_lower()
	if name_match.find(q) != -1:
		return 400

	# Check Tags
	for tag in row.tags:
		if tag.to_lower().find(q) != -1:
			return 300

	return 0


func _update_count_label(visible_count: int) -> void:
	if _count_label != null:
		_count_label.text = "Showing %d of %d items" % [visible_count, _total_count]


func _on_search_text_changed(new_text: String) -> void:
	filter_entries(new_text)


func _on_search_text_submitted(_text: String) -> void:
	# Spawn 1 of the first matching visible item on Enter
	for child in _item_list.get_children():
		var row := child as DebugItemRow
		if row != null and row.visible:
			_on_spawn_requested(row.item_id, 1)
			return


func _on_spawn_requested(item_id: String, count: int) -> void:
	var player: Player = SceneManager.get_player() if SceneManager != null else null
	var spawn_pos := Vector3.ZERO
	var parent_node: Node = null

	if player != null and is_instance_valid(player) and player.is_inside_tree():
		spawn_pos = player.global_position
		var forward := -player.global_transform.basis.z.normalized()
		if not forward.is_zero_approx():
			spawn_pos += forward * 1.0 + Vector3(0.0, 0.5, 0.0)
		parent_node = player.get_parent()
	elif GameState != null and GameState.map_root != null:
		parent_node = GameState.map_root
	elif get_tree() != null and get_tree().current_scene != null:
		parent_node = get_tree().current_scene
	elif get_tree() != null and get_tree().root != null:
		parent_node = get_tree().root
	else:
		parent_node = self

	var spawned: WorldItem = WorldItem.spawn_at(parent_node, item_id, count, spawn_pos)
	if spawned != null:
		var msg := "Spawned %d x %s at player location" % [count, item_id]
		if _status_label != null:
			_status_label.text = msg
		if GameLog != null:
			GameLog.info("Debug: %s" % msg)
	else:
		if _status_label != null:
			_status_label.text = "Failed to spawn %s" % item_id


func _on_close_pressed() -> void:
	if SceneManager != null and SceneManager.is_screen_open():
		SceneManager.close_screen()
	else:
		queue_free()
