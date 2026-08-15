extends Control
## Crafting panel for one station: lists its recipes (def.crafting_params),
## queues on click, and shows the active order's deposit progress. Minimal v1 —
## one active order per station (queue_recipe no-ops while one runs, so rows
## disable), no cancel/re-queue.
##
## Recipe conditions (colonist skill gates) are NOT evaluated here — they gate
## the craft job's claim (CraftingJobDef.meets_requirements), not the queue,
## and the player has no SkillSet to evaluate them against anyway.
##
## Lifecycle: instantiated by OpenCraftingAction, mounted on a CanvasLayer,
## destroyed on close. Structure mirrors ui/storage/storage_panel.

signal closed()

@onready var _title_label: Label = $Panel/VBox/Header/TitleLabel
@onready var _close_button: Button = $Panel/VBox/Header/CloseButton
@onready var _order_label: Label = $Panel/VBox/OrderLabel
@onready var _recipe_list: VBoxContainer = $Panel/VBox/Scroll/RecipeList

var _station: CraftingStation = null


func setup(station: CraftingStation) -> void:
	_station = station
	# Defer until the node is in the tree so @onready has resolved.
	if not is_node_ready():
		ready.connect(_initial_refresh, CONNECT_ONE_SHOT)
	else:
		_initial_refresh()


func _initial_refresh() -> void:
	var furniture := _station.get_parent() as Furniture
	if furniture != null and furniture.label != "":
		_title_label.text = furniture.label
	_close_button.pressed.connect(close)
	_refresh()


func _refresh() -> void:
	_refresh_order_label()
	for child in _recipe_list.get_children():
		child.queue_free()
	var order_active := _station.has_active_order()
	for recipe in _station.recipes:
		var row := Button.new()
		row.text = _describe(recipe)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.flat = true
		row.disabled = order_active
		# Bind by value — `recipe` changes per iteration.
		row.pressed.connect(func() -> void:
			_queue(recipe)
		)
		_recipe_list.add_child(row)


func _refresh_order_label() -> void:
	var recipe := _station.active_recipe()
	if recipe == null:
		_order_label.text = "No active order"
		return
	var parts := PackedStringArray()
	for entry in recipe.inputs:
		var id := entry.item_def.id
		parts.append("%s %d/%d" % [
			_item_name(id), _station.given_count(id), entry.count,
		])
	_order_label.text = "%s — %s" % [recipe.label(), "  ".join(parts)]


func _queue(recipe: RecipeDef) -> void:
	if _station.queue_recipe(recipe.id):
		_refresh()


## "Plank x4 — 1 Wood block (4s)": outputs, then inputs, then base time.
func _describe(recipe: RecipeDef) -> String:
	var outs := PackedStringArray()
	for entry in recipe.outputs:
		outs.append("%s x%d" % [_item_name(entry.item_def.id), entry.count])
	var ins := PackedStringArray()
	for entry in recipe.inputs:
		ins.append("%d %s" % [entry.count, _item_name(entry.item_def.id)])
	var text := "%s — %s" % [" + ".join(outs), " + ".join(ins)]
	if recipe.base_time > 0.0:
		text += " (%.0fs)" % recipe.base_time
	return text


func _item_name(item_id: String) -> String:
	var def := ItemDB.get_def(item_id)
	if def != null and def.resource_name != "":
		return def.resource_name
	return item_id


func close() -> void:
	closed.emit()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
