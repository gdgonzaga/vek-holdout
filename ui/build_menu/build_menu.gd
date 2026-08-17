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
const DECONSTRUCT_ICON = preload("res://assets/item_icons/__deconstruct__.png")
# Prototype icon for the Dig tool (a dirt block) until the art pass.
const DIG_ICON = preload("res://assets/item_icons/dirt_block.png")

@onready var _list: VBoxContainer = $Panel/VBox/ScrollContainer/List
@onready var _close_button: Button = $Panel/VBox/Header/CloseButton


func _ready() -> void:
	UiGate.open_modal(self)
	_close_button.pressed.connect(close)


func _exit_tree() -> void:
	UiGate.close_modal(self)


func _unhandled_input(event: InputEvent) -> void:
	# Esc and B both dismiss the menu without a selection. The menu is a
	# registered modal, so InputComponent is gated and the Player's B router
	# never sees these presses; mark them handled so nothing else reacts.
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("build_toggle"):
		get_viewport().set_input_as_handled()
		close()


## Read BuildLibrary and fill the list with one entry per unlocked buildable.
func populate() -> void:
	for child in _list.get_children():
		child.queue_free()

	# Tool entries (not buildables): Deconstruct routes LMB to removal, Dig
	# routes it to a timed smooth-terrain carve (mining, Phase 5). Neither is
	# unlock-gated — always available.
	var deconstruct: BuildMenuEntry = _EntryScene.instantiate()
	_list.add_child(deconstruct)
	deconstruct.setup_tool(BuildLibrary.DECONSTRUCT_ID, "Deconstruct", DECONSTRUCT_ICON)
	deconstruct.pressed_id.connect(_on_entry_pressed)

	var dig: BuildMenuEntry = _EntryScene.instantiate()
	_list.add_child(dig)
	dig.setup_tool(BuildLibrary.DIG_ID, "Dig", DIG_ICON)
	dig.pressed_id.connect(_on_entry_pressed)

	for def in BuildLibrary.get_unlocked():
		var entry: BuildMenuEntry = _EntryScene.instantiate()
		_list.add_child(entry)
		entry.setup(def)
		entry.pressed_id.connect(_on_entry_pressed)

	# Natural terrain materials (smooth placement, Phase 5): add-sphere blobs
	# of ground material. Ambient content like the tools — not unlock-gated.
	for mat in BuildLibrary.get_terrain_materials():
		var mat_entry: BuildMenuEntry = _EntryScene.instantiate()
		_list.add_child(mat_entry)
		mat_entry.setup_tool(mat.id, mat.display_name, mat.icon)
		mat_entry.pressed_id.connect(_on_entry_pressed)


func _on_entry_pressed(id: String) -> void:
	# Broadcast the selection globally. BuildController listens and sets its
	# selected_id; Player listens and enters Blueprint mode. This menu stays
	# otherwise EventBus-agnostic — closed() (no-selection dismissal) stays local.
	EventBus.buildable_selected.emit(id)
	queue_free()


## Close without a selection (Esc, B, or the header Close button — all routed
## through _unhandled_input / the button). The opener reacts via `closed`.
func close() -> void:
	closed.emit()
	queue_free()
