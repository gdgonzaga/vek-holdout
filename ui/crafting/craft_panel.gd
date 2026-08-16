extends Control
## Crafting panel for one station — the dual-mode surface. Per recipe:
## [ Queue ] (colony order; the adjacent "until stock" SpinBox ≥ 1 turns it
## into a maintain order that self-requeues until storage holds that many of
## the recipe's first output) and [ Craft ] (queue it reserved for you; the
## player's carried inputs are deposited immediately, any shortfall is hauled
## — the order then waits ready for Craft now). The order section shows
## deposit progress + worker tag, and offers Craft now (any ready order,
## colonist-queued ones included — the ledger is communal) and Cancel.
##
## Recipe conditions gate only the player's Craft button (they're colonist
## claim gates for Queue — JobBoard enforces those — and the player's SkillSet
## now evaluates them for personal crafting).
##
## Rows are rebuilt only on queue/craft/cancel actions; the 0.5s timer
## refreshes just the order section (rebuilding rows would reset the SpinBoxes
## mid-typing). Lifecycle mirrors ui/storage/storage_panel.

signal closed()

const ORDER_POLL_INTERVAL := 0.5

@onready var _title_label: Label = $Panel/VBox/Header/TitleLabel
@onready var _close_button: Button = $Panel/VBox/Header/CloseButton
@onready var _order_label: Label = $Panel/VBox/OrderLabel
@onready var _order_buttons: HBoxContainer = $Panel/VBox/OrderButtons
@onready var _recipe_list: VBoxContainer = $Panel/VBox/Scroll/RecipeList

var _station: CraftingStation = null
var _player: Player = null

var _craft_now_button: Button
var _cancel_button: Button

var _craft_action := CraftAction.new()


func setup(station: CraftingStation, player: Player) -> void:
	_station = station
	_player = player
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
	_craft_now_button = Button.new()
	_craft_now_button.text = "Craft now"
	_craft_now_button.pressed.connect(_craft_now)
	_order_buttons.add_child(_craft_now_button)
	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.pressed.connect(_cancel)
	_order_buttons.add_child(_cancel_button)
	var poll := Timer.new()
	poll.wait_time = ORDER_POLL_INTERVAL
	poll.timeout.connect(func() -> void:
		if _station != null and is_instance_valid(_station):
			_refresh_order_section())
	add_child(poll)
	poll.start()
	_refresh()


func _refresh() -> void:
	_refresh_order_section()
	for child in _recipe_list.get_children():
		child.queue_free()
	var order_active := _station.has_active_order()
	for recipe in _station.recipes:
		_recipe_row(recipe, order_active)


## Order status line + the Craft now / Cancel buttons. Polled live so hauler
## deposits and maintain progress tick up while the panel is open.
func _refresh_order_section() -> void:
	var recipe := _station.active_recipe()
	if recipe == null:
		_order_label.text = "No active order"
		_craft_now_button.visible = false
		_cancel_button.visible = false
		return
	var parts := PackedStringArray()
	for entry in recipe.inputs:
		var id := entry.item_def.id
		parts.append("%s %d/%d" % [
			_item_name(id), _station.given_count(id), entry.count,
		])
	var tag := "for you" if _station.worker() == CraftingStation.WORKER_PLAYER \
			else "for the colony"
	var maintain := _station.maintain_goal()
	if not maintain.is_empty():
		var item_id: String = maintain.get("item_id", "")
		tag += " · stock %d/%d" % [
			Colony.storage_registry.colony_stock(item_id),
			int(maintain.get("count", 0)),
		]
	if _station.is_claimed():
		tag += " · being crafted"
	_order_label.text = "%s — %s · %s" % [recipe.label(), "  ".join(parts), tag]
	_craft_now_button.visible = _station.is_ready()
	_craft_now_button.disabled = not _station.can_player_work()
	_cancel_button.visible = true


func _recipe_row(recipe: RecipeDef, order_active: bool) -> void:
	var row := HBoxContainer.new()
	_recipe_list.add_child(row)

	var text := Label.new()
	text.text = _describe(recipe)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(text)

	var until := Label.new()
	until.text = "until:"
	row.add_child(until)
	var stock := SpinBox.new()
	stock.min_value = 0
	stock.max_value = 999
	stock.step = 1
	stock.value = 0
	stock.custom_minimum_size = Vector2(64, 0)
	stock.tooltip_text = "Requeue until colony storage holds this many (0 = one-shot)"
	row.add_child(stock)

	var queue := Button.new()
	queue.text = "Queue"
	queue.disabled = order_active
	queue.tooltip_text = "Queue as a colony job (a colonist crafts it)"
	# Bind by value — `recipe`/`stock` change per iteration, and the SpinBox
	# must be read at click time, not capture time.
	queue.pressed.connect(func() -> void:
		var target := int(stock.value)
		var maintain := {}
		if target > 0 and not recipe.outputs.is_empty():
			maintain = {
				"item_id": recipe.outputs[0].item_def.id,
				"count": target,
			}
		if _station.queue_recipe(recipe.id, CraftingStation.WORKER_COLONY, maintain):
			_refresh())
	row.add_child(queue)

	var craft := Button.new()
	craft.text = "Craft"
	var ineligible := _player != null and not _player_meets(recipe)
	craft.disabled = order_active or ineligible
	if ineligible:
		craft.tooltip_text = "You don't meet this recipe's conditions"
	else:
		craft.tooltip_text = "Queue for yourself and craft it at the bench"
	craft.pressed.connect(func() -> void:
		_craft_yourself(recipe))
	row.add_child(craft)


## Queue reserved for the player, then deposit whatever they're carrying
## toward it right away (the same ledger haulers write; shortfalls get hauled).
func _craft_yourself(recipe: RecipeDef) -> void:
	if _station.queue_recipe(recipe.id, CraftingStation.WORKER_PLAYER):
		if _player != null:
			_station.deposit_from(_player)
		_refresh()


## Hand the order to CraftAction (gauge + produce). The panel closes first —
## the gauge owns the screen and Esc while it runs means "cancel craft", not
## "close panel".
func _craft_now() -> void:
	if not _station.can_player_work() or _player == null:
		return
	var station := _station
	close()
	_craft_action.execute(_player, station)


func _cancel() -> void:
	_station.cancel_order()
	_refresh()


func _player_meets(recipe: RecipeDef) -> bool:
	if _player == null or _player.skill_set == null:
		return false
	for condition in recipe.conditions:
		if not condition.is_met(_player, _station):
			return false
	return true


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
