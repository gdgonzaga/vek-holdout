class_name BuildMenu
extends Control
## Build-mode selection menu (ARCH "Build" subsystem).
## Lists every unlocked buildable as an entry row (build_menu_entry.tscn) — icon
## + display name. Clicking one broadcasts EventBus.buildable_selected(id) so
## BuildController sets its selected_id and Player enters Blueprint mode. Only
## the no-selection dismissal (closed) stays as a local signal — the opener
## wires it.
##
## The container skeleton is authored in build_menu.tscn (ARCH line 135: UI is
## .tscn, not built dynamically); the per-buildable entries are instanced in
## populate(). Each entry is itself a scene so its layout (icon size, label
## font, spacing, future cost/category fields) is editor-tunable.

signal closed()

const _EntryScene := preload("res://ui/build_menu/build_menu_entry.tscn")

@onready var _list: VBoxContainer = $Panel/VBox/ScrollContainer/List
@onready var _close_button: Button = $Panel/VBox/Header/CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)


## Read BuildLibrary and fill the list with one entry per unlocked buildable.
func populate() -> void:
	for child in _list.get_children():
		child.queue_free()
	for def in BuildLibrary.get_unlocked():
		var entry: BuildMenuEntry = _EntryScene.instantiate()
		_list.add_child(entry)
		entry.setup(def)
		entry.pressed_id.connect(_on_entry_pressed)
	# Tool entries (not buildables): Deconstruct routes LMB to removal instead of
	# placement. Not unlock-gated — it's always available.
	var deconstruct: BuildMenuEntry = _EntryScene.instantiate()
	_list.add_child(deconstruct)
	deconstruct.setup_tool(BuildLibrary.DECONSTRUCT_ID, "Deconstruct")
	deconstruct.pressed_id.connect(_on_entry_pressed)


func _on_entry_pressed(id: String) -> void:
	# Broadcast the selection globally. BuildController listens and sets its
	# selected_id; Player listens and enters Blueprint mode. This menu stays
	# otherwise EventBus-agnostic — closed() (no-selection dismissal) stays local.
	EventBus.buildable_selected.emit(id)
	queue_free()


## Called by the opener when the menu should close without a selection (B-toggle
## from the menu state). Esc no longer closes it — it's reserved for the Pause
## Menu (GDD §4 controls table, line 214), and B is owned by the Player.
func close() -> void:
	closed.emit()
	queue_free()
