class_name BuildMenu
extends Control
## Build-mode selection menu (ARCH "Build" subsystem).
## Lists every unlocked buildable as an entry row (build_menu_entry.tscn) — icon
## + display name. Clicking one broadcasts EventBus.buildable_selected(id) so
## BuildController sets its selected_id and Player enters Blueprint mode. Only
## the no-selection dismissal (closed) stays as a local signal — the opener
## wires it.
##
## Includes a fuzzy search filter (%SearchEdit) to filter buildables by display
## name or ID.

signal closed()

const _EntryScene := preload("res://ui/build_menu/build_menu_entry.tscn")
const DECONSTRUCT_ICON = preload("res://assets/item_icons/__deconstruct__.png")

@onready var _list: VBoxContainer = %List
@onready var _close_button: Button = %CloseButton
@onready var _search_edit: LineEdit = %SearchEdit


func _ready() -> void:
	UiGate.open_modal(self)
	_close_button.pressed.connect(close)
	_search_edit.text_changed.connect(_on_search_text_changed)
	_search_edit.text_submitted.connect(_on_search_text_submitted)
	_search_edit.grab_focus()


func _exit_tree() -> void:
	UiGate.close_modal(self)


func _unhandled_input(event: InputEvent) -> void:
	# Esc and B both dismiss the menu without a selection. The menu is a
	# registered modal, so InputComponent is gated and the Player's B router
	# never sees these presses; mark them handled so nothing else reacts.
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("build_toggle"):
		get_viewport().set_input_as_handled()
		close()


## Read BuildLibrary and fill the list with default entries.
func populate() -> void:
	_populate_default_list()
	if _search_edit != null and not _search_edit.text.is_empty():
		filter_entries(_search_edit.text)


## Internal helper to clear and instance default entries in default order.
func _populate_default_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	# Tool entries (not buildables): Deconstruct routes LMB to removal.
	# Mining is performed via direct LMB in Normal mode.
	var deconstruct: BuildMenuEntry = _EntryScene.instantiate()
	_list.add_child(deconstruct)
	deconstruct.setup_tool(BuildLibrary.DECONSTRUCT_ID, "Deconstruct", DECONSTRUCT_ICON)
	deconstruct.pressed_id.connect(_on_entry_pressed)

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


## Filters visible menu entries based on fuzzy match score with query.
func filter_entries(query: String) -> void:
	var q := query.strip_edges()
	if q.is_empty():
		_populate_default_list()
		return

	var scored_entries: Array[Dictionary] = []
	for child in _list.get_children():
		if child is BuildMenuEntry:
			var entry: BuildMenuEntry = child
			var score_name: int = fuzzy_match_score(q, entry.display_name)
			var score_id: int = fuzzy_match_score(q, entry.entry_id)
			var max_score: int = maxi(score_name, score_id)
			scored_entries.append({
				"entry": entry,
				"score": max_score
			})

	# Sort descending by match score so top matches appear at top of list
	scored_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var score_a: int = a["score"]
		var score_b: int = b["score"]
		return score_a > score_b
	)

	for item in scored_entries:
		var entry: BuildMenuEntry = item["entry"]
		var score: int = item["score"]
		if score > 0:
			entry.visible = true
			_list.move_child(entry, -1)
		else:
			entry.visible = false


func _on_search_text_changed(new_text: String) -> void:
	filter_entries(new_text)


func _on_search_text_submitted(_text: String) -> void:
	# Select the first visible matching entry if available
	for child in _list.get_children():
		if child is BuildMenuEntry and child.visible:
			_on_entry_pressed(child.entry_id)
			return


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


## Calculates a fuzzy match score for `query` against candidate `text`.
## Returns a score > 0 if matched, or 0 if no match. Higher score = better match.
static func fuzzy_match_score(query: String, text: String) -> int:
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		return 1

	var t := text.to_lower()

	# 1. Exact match
	if t == q:
		return 1000

	# 2. Prefix match
	if t.begins_with(q):
		return 800 + (100 - mini(t.length(), 90))

	# 3. Contiguous substring match
	var sub_idx := t.find(q)
	if sub_idx != -1:
		return 600 - sub_idx

	# 4. Fuzzy subsequence match
	var q_len := q.length()
	var t_len := t.length()
	var q_idx := 0
	var t_idx := 0
	var score := 100
	var last_match_idx := -10

	while q_idx < q_len and t_idx < t_len:
		if q[q_idx] == t[t_idx]:
			# Consecutive match bonus
			if t_idx == last_match_idx + 1:
				score += 20
			# Word boundary bonus (start of string or after space, underscore, dash)
			if t_idx == 0 or t[t_idx - 1] in [" ", "_", "-"]:
				score += 30
			last_match_idx = t_idx
			q_idx += 1
		t_idx += 1

	if q_idx == q_len:
		return maxi(score, 1)

	return 0
