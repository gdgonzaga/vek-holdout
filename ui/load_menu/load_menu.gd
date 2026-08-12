extends PanelContainer
## Load Game screen — lists every save slot from SaveSystem.list_saves(). Click
## a row to load it (await SaveSystem.load_game then close_screen); click the X
## on a row to delete it (no confirmation in v1 — destructive ops warrant a
## confirmation dialog later). Back returns to the main menu.
##
## Opened via SceneManager.open_screen("load_menu"). Each row is built in code
## from the save meta dicts — no per-row scene file, since the layout is two
## buttons in an HBox.

@onready var _saves_list: VBoxContainer = %SavesList
@onready var _empty_label: Label = %EmptyLabel
@onready var _back_btn: Button = %Back


func _ready() -> void:
	_back_btn.pressed.connect(_on_back_pressed)
	_populate()


## Rebuild the list from SaveSystem.list_saves() (newest first). Safe to call
## after a delete to refresh without re-instantiating the screen.
func _populate() -> void:
	for child in _saves_list.get_children():
		child.queue_free()
	var saves: Array[Dictionary] = SaveSystem.list_saves()
	_empty_label.visible = saves.is_empty()
	for save in saves:
		_saves_list.add_child(_build_row(save))


## One row = HBoxContainer with a load Button (stretches) + a small delete Button.
## `bind(slot_id)` curry-passes the slot id into each handler so we don't need a
## closure-per-row mapping.
func _build_row(save: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.set("theme_override_constants/separation", 8)

	var load_btn := Button.new()
	# "display_name (Day N)" — saved_at is unix seconds; a date stamp can land
	# here later. String-cast slot_id defensively since list_saves types it but
	# JSON round-trips can soften that.
	load_btn.text = "%s  —  Day %d" % [String(save.get("display_name", "?")), int(save.get("current_day", 0))]
	load_btn.custom_minimum_size = Vector2(360, 0)
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.pressed.connect(_on_load_pressed.bind(String(save.get("slot_id", ""))))

	var delete_btn := Button.new()
	delete_btn.text = "X"
	delete_btn.custom_minimum_size = Vector2(40, 0)
	delete_btn.pressed.connect(_on_delete_pressed.bind(String(save.get("slot_id", ""))))

	row.add_child(load_btn)
	row.add_child(delete_btn)
	return row


## Load the chosen slot, then close this screen — close_screen frees us, the
## freshly-loaded map becomes the live view. Await load_game because it awaits
## swap_map internally (player must be in the tree before state restore). On
## failure (missing/corrupt slot, version mismatch) stay on this screen so the
## user can pick a different save rather than landing in an empty world.
func _on_load_pressed(slot_id: String) -> void:
	if slot_id == "":
		return
	var ok: bool = await SaveSystem.load_game(slot_id)
	if ok:
		SceneManager.close_screen()
	else:
		_populate()  # the slot may have been the problem; refresh in case


## Delete the slot and refresh the list. The list rebuild keeps the screen
## interactive (no full re-instantiate).
func _on_delete_pressed(slot_id: String) -> void:
	if slot_id == "":
		return
	SaveSystem.delete_save(slot_id)
	_populate()


## Back to main menu. open_screen closes this first, then mounts main_menu.
func _on_back_pressed() -> void:
	SceneManager.open_screen("main_menu")
