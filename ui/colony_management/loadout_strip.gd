class_name LoadoutStrip
extends VBoxContainer
## Header of the Gear sub-tab: pick a saved loadout and Apply it to the shown colonist, or save
## the colonist's current targets as a loadout. A loadout is stamped, not linked (ARCH
## equipment.md), so the only lasting effect of Apply is the colonist's own targets. The strip
## also names the saved loadouts those targets currently match. It listens to the colonist's
## target changes and to the loadout book, so it never polls. Call set_colonist() after add_child.

const RESULT_NEEDS_NAME: String = "Enter a name for the loadout"
const CONFIRM_SAVE_TEXT: String = "Save"
const CONFIRM_OVERWRITE_TEXT: String = "Overwrite"

var _colonist: Colonist = null
var _book: LoadoutBook = null

@onready var _option: OptionButton = %LoadoutOption
@onready var _apply_button: Button = %ApplyButton
@onready var _save_as_button: Button = %SaveAsButton
@onready var _save_row: HBoxContainer = %SaveRow
@onready var _save_name_input: LineEdit = %SaveNameInput
@onready var _confirm_save_button: Button = %ConfirmSaveButton
@onready var _cancel_save_button: Button = %CancelSaveButton
@onready var _match_label: Label = %MatchLabel
@onready var _result_label: Label = %ResultLabel

# =================
# Primary Functions
# =================

func _ready() -> void:
	# 1. Events: wire the buttons and the name field once; sources are bound per colonist.
	_connect_events()

	# 2. Initial View: fill the dropdown and labels for whatever colonist was set before ready.
	_show_current_state()


func _exit_tree() -> void:
	# 1. Source Release: the loadout book outlives this strip, so drop our listener explicitly.
	_disconnect_sources()


## Points the strip at a colonist (or null), closes any half-finished save and clears the last result.
func set_colonist(colonist: Colonist) -> void:
	# 1. Source Handover: stop listening to the previous colonist before binding the new one.
	_disconnect_sources()
	_colonist = colonist
	_book = Colony.loadouts
	_connect_sources()

	# 2. View Reset: a result sentence or open name row belongs to the colonist it was made for.
	if is_node_ready():
		_set_result("")
		_close_save_row()
		_show_current_state()


## Re-derives the match label and which buttons are usable from the colonist's current targets.
func refresh() -> void:
	if not is_node_ready():
		return

	# 1. Match Label: which saved loadouts the colonist's targets equal right now.
	_match_label.text = _match_text()

	# 2. Button State: Apply needs a colonist and a loadout; Save needs at least one target to keep.
	_apply_button.disabled = not _has_colonist() or LoadoutUi.selected_id(_option).is_empty()
	_save_as_button.disabled = not _has_colonist() or not LoadoutUi.has_targets(_colonist.equipment)

	# 3. Confirm Label: "Overwrite" warns that the typed name already belongs to a saved loadout.
	_confirm_save_button.text = _confirm_text()

# ===================
# Auxiliary Functions
# ===================

func _connect_events() -> void:
	## Auxiliary: Connects every control the strip owns.
	_apply_button.pressed.connect(_on_apply_pressed)
	_save_as_button.pressed.connect(_on_save_as_pressed)
	_confirm_save_button.pressed.connect(_on_confirm_save_pressed)
	_cancel_save_button.pressed.connect(_close_save_row)
	_option.item_selected.connect(_on_option_selected)
	_save_name_input.text_changed.connect(_on_name_changed)
	_save_name_input.text_submitted.connect(_on_name_submitted)
	_save_name_input.gui_input.connect(_on_name_gui_input)


func _connect_sources() -> void:
	## Auxiliary: Listens to the colonist's target changes and to the book's contents.
	if _has_colonist():
		_colonist.equipment.desired_slot_changed.connect(_on_target_changed)
	if _book != null:
		_book.changed.connect(_on_book_changed)


func _disconnect_sources() -> void:
	## Auxiliary: Undoes _connect_sources for whatever colonist and book were bound.
	if _has_colonist() and _colonist.equipment.desired_slot_changed.is_connected(_on_target_changed):
		_colonist.equipment.desired_slot_changed.disconnect(_on_target_changed)
	if _book != null and _book.changed.is_connected(_on_book_changed):
		_book.changed.disconnect(_on_book_changed)


func _has_colonist() -> bool:
	## Auxiliary: True when there is a live colonist with an Equipment component to read and write.
	return _colonist != null and is_instance_valid(_colonist) and _colonist.equipment != null


func _show_current_state() -> void:
	## Auxiliary: Rebuilds the dropdown (keeping the selection) and re-derives labels and buttons.
	if _book != null:
		LoadoutUi.fill_options(_option, _book, LoadoutUi.selected_id(_option))
	refresh()


func _match_text() -> String:
	## Auxiliary: "Matches: Miner", "Custom targets" or "No targets set" for the bound colonist.
	if not _has_colonist() or _book == null:
		return LoadoutUi.NO_TARGETS_TEXT
	var names: Array[String] = []
	for id: String in _book.find_matching_ids(_colonist.equipment):
		names.append(_book.get_name(id))
	return LoadoutUi.match_text(names, LoadoutUi.has_targets(_colonist.equipment))


func _confirm_text() -> String:
	## Auxiliary: "Overwrite" when the typed name is already a saved loadout, otherwise "Save".
	if _book != null and not _book.find_id_by_name(_save_name_input.text).is_empty():
		return CONFIRM_OVERWRITE_TEXT
	return CONFIRM_SAVE_TEXT


func _set_result(text: String) -> void:
	## Auxiliary: Shows the last action's sentence; the label takes no space while empty.
	_result_label.text = text
	_result_label.visible = not text.is_empty()


func _open_save_row() -> void:
	## Auxiliary: Reveals the name row, prefilled with the selected loadout's name so updating it is one click.
	_save_row.visible = true
	_save_name_input.text = _book.get_name(LoadoutUi.selected_id(_option)) if _book != null else ""
	_confirm_save_button.text = _confirm_text()
	_save_name_input.grab_focus()
	_save_name_input.select_all()


func _close_save_row() -> void:
	## Auxiliary: Hides the name row and drops focus so typing does not leak into the field.
	_save_row.visible = false
	_save_name_input.release_focus()


func _save_targets_as(typed_name: String) -> void:
	## Auxiliary: Captures the colonist's targets under `typed_name`, overwriting a loadout of that name.
	var clean_name: String = typed_name.strip_edges()
	if clean_name.is_empty():
		_set_result(RESULT_NEEDS_NAME)
		return

	# 1. Target Loadout: reuse an existing loadout of that name, otherwise create one.
	var existing_id: String = _book.find_id_by_name(clean_name)
	var id: String = existing_id if not existing_id.is_empty() else _book.create(clean_name)
	_book.capture_from(id, _colonist.equipment)

	# 2. View Update: select what was just saved, report it and put the name row away.
	LoadoutUi.fill_options(_option, _book, id)
	_set_result(LoadoutUi.save_summary(_book.get_name(id), _book.get_slots(id).size(), not existing_id.is_empty()))
	_close_save_row()
	refresh()


func _on_apply_pressed() -> void:
	var id: String = LoadoutUi.selected_id(_option)
	if id.is_empty() or not _has_colonist():
		return

	# 1. Stamp: write the loadout's slots into the colonist's targets (the audit does the fetching).
	var counts: Dictionary = _book.apply_to(id, _colonist.equipment, LoadoutUi.item_resolver())

	# 2. Feedback: say what changed and what could not be applied.
	_set_result(LoadoutUi.apply_summary(_book.get_name(id), counts))


func _on_save_as_pressed() -> void:
	if _has_colonist() and _book != null:
		_open_save_row()


func _on_confirm_save_pressed() -> void:
	if _has_colonist() and _book != null:
		_save_targets_as(_save_name_input.text)


func _on_name_submitted(typed_name: String) -> void:
	if _has_colonist() and _book != null:
		_save_targets_as(typed_name)


func _on_name_changed(_typed_name: String) -> void:
	_confirm_save_button.text = _confirm_text()


func _on_name_gui_input(event: InputEvent) -> void:
	## Auxiliary: Esc in the name field backs out of the save and is consumed, so it never closes the screen.
	if event.is_action_pressed("ui_cancel"):
		_close_save_row()
		get_viewport().set_input_as_handled()


func _on_option_selected(_index: int) -> void:
	refresh()


func _on_target_changed(_slot_id: String, _item_id: String) -> void:
	refresh()


func _on_book_changed() -> void:
	_show_current_state()
