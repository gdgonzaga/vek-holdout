extends PanelContainer
class_name CraftingStationRow
## A single workstation card in the Crafting Stations screen of Colony Management.
## Displays station info, active order status, queue controls, assigned crafting colonists,
## and a paused/active toggle.

signal order_changed()

@onready var _station_name_label: Label = %StationNameLabel
@onready var _pause_button: Button = %PauseButton

@onready var _active_order_container: VBoxContainer = %ActiveOrderContainer
@onready var _order_title_label: Label = %OrderTitleLabel
@onready var _order_details_label: Label = %OrderDetailsLabel
@onready var _maintain_status_label: Label = %MaintainStatusLabel
@onready var _worker_claim_label: Label = %WorkerClaimLabel
@onready var _cancel_order_button: Button = %CancelOrderButton

@onready var _idle_order_container: HBoxContainer = %IdleOrderContainer
@onready var _recipe_option_button: OptionButton = %RecipeOptionButton
@onready var _stock_spin_box: SpinBox = %StockSpinBox
@onready var _queue_button: Button = %QueueButton

@onready var _colonists_list_label: Label = %ColonistsListLabel

var _station: CraftingStation = null
var _poll_timer: Timer = null


func setup(station: CraftingStation) -> void:
	_station = station
	if not is_node_ready():
		ready.connect(_initial_refresh, CONNECT_ONE_SHOT)
	else:
		_initial_refresh()


func _initial_refresh() -> void:
	if _station == null or not is_instance_valid(_station):
		return

	_update_header()
	_populate_recipes()

	_pause_button.toggled.connect(_on_pause_toggled)
	_cancel_order_button.pressed.connect(_on_cancel_pressed)
	_queue_button.pressed.connect(_on_queue_pressed)

	_poll_timer = Timer.new()
	_poll_timer.wait_time = 0.5
	_poll_timer.timeout.connect(_refresh_live_status)
	add_child(_poll_timer)
	_poll_timer.start()

	_refresh_live_status()


func _update_header() -> void:
	var furniture := _station.get_parent() as Furniture
	var label_text := furniture.label if (furniture != null and furniture.label != "") else "Crafting Station"
	var pos := _station.anchor_cell()
	_station_name_label.text = "%s  @ (%d, %d, %d)" % [label_text, pos.x, pos.y, pos.z]

	var paused := _station.is_paused()
	_pause_button.button_pressed = paused
	_update_pause_button_text(paused)


func _update_pause_button_text(paused: bool) -> void:
	if paused:
		_pause_button.text = "Paused"
		_pause_button.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4, 1))
	else:
		_pause_button.text = "Active"
		_pause_button.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 1))


func _on_pause_toggled(button_pressed: bool) -> void:
	if _station != null and is_instance_valid(_station):
		_station.set_paused(button_pressed)
		_update_pause_button_text(button_pressed)


func _populate_recipes() -> void:
	_recipe_option_button.clear()
	if _station == null:
		return
	for i in range(_station.recipes.size()):
		var recipe := _station.recipes[i]
		_recipe_option_button.add_item(recipe.label(), i)


func _refresh_live_status() -> void:
	if _station == null or not is_instance_valid(_station):
		return

	_refresh_order_section()
	_refresh_assigned_colonists()


func _refresh_order_section() -> void:
	var recipe := _station.active_recipe()
	if recipe == null:
		_active_order_container.visible = false
		_idle_order_container.visible = true
		return

	_active_order_container.visible = true
	_idle_order_container.visible = false

	var worker_tag := "For Colony" if _station.worker() == CraftingStation.WORKER_COLONY else "For Player"
	_order_title_label.text = "Active Bill: %s (%s)" % [recipe.label(), worker_tag]

	var parts := PackedStringArray()
	for entry in recipe.inputs:
		var item_id := entry.item_def.id
		parts.append("%s %d/%d" % [_item_name(item_id), _station.given_count(item_id), entry.count])
	_order_details_label.text = "Deposited Materials: %s" % ", ".join(parts)

	var maintain := _station.maintain_goal()
	if not maintain.is_empty():
		var item_id: String = maintain.get("item_id", "")
		var target: int = int(maintain.get("count", 0))
		var furniture := _station.get_parent() as Node3D if _station != null else null
		var pos: Variant = furniture.global_position if furniture != null and furniture.is_inside_tree() else null
		var current_stock: int = Colony.storage_registry.colony_stock(item_id, pos)
		_maintain_status_label.visible = true
		_maintain_status_label.text = "Maintain Target: %d %s (Stock: %d / %d)" % [
			target, _item_name(item_id), current_stock, target
		]
	else:
		_maintain_status_label.visible = false

	var status_str := "Idle / Waiting for materials"
	if _station.is_paused():
		status_str = "Paused by Overseer"
	elif _station.is_claimed():
		var owner_id := _station.claim_owner()
		if owner_id == CraftingStation.PLAYER_CLAIM:
			status_str = "Crafting by Player"
		else:
			var colonist := _find_colonist(owner_id)
			var cname := colonist.display_name if colonist != null else owner_id
			status_str = "Crafting by %s" % cname
	elif _station.is_ready():
		status_str = "Materials ready — waiting for crafter"
	_worker_claim_label.text = "Status: %s" % status_str


func _refresh_assigned_colonists() -> void:
	var crafting_colonists: Array[String] = []
	for c in Colony.colonists:
		if not is_instance_valid(c):
			continue
		var prio: int = int(c.labor_priorities.get("crafting", 0))
		if prio > 0:
			var level: int = c.skill_set.get_level("crafting") if c.skill_set != null else 1
			var mult: float = c.skill_set.get_multiplier("crafting") if c.skill_set != null else 1.0
			crafting_colonists.append("%s (Prio %d, Lvl %d, %.1fx speed)" % [c.display_name, prio, level, mult])

	if crafting_colonists.is_empty():
		_colonists_list_label.text = "None (no colonist has Crafting labor enabled)"
		_colonists_list_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	else:
		_colonists_list_label.text = "; ".join(crafting_colonists)
		_colonists_list_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))


func _on_queue_pressed() -> void:
	if _station == null or not is_instance_valid(_station):
		return
	var idx := _recipe_option_button.selected
	if idx < 0 or idx >= _station.recipes.size():
		return
	var recipe := _station.recipes[idx]
	var target := int(_stock_spin_box.value)
	var maintain := {}
	if target > 0 and not recipe.outputs.is_empty():
		maintain = {
			"item_id": recipe.outputs[0].item_def.id,
			"count": target,
		}
	if _station.queue_recipe(recipe.id, CraftingStation.WORKER_COLONY, maintain):
		_refresh_live_status()
		order_changed.emit()


func _on_cancel_pressed() -> void:
	if _station != null and is_instance_valid(_station):
		_station.cancel_order()
		_refresh_live_status()
		order_changed.emit()


func _find_colonist(colonist_id: String) -> Colonist:
	for c in Colony.colonists:
		if is_instance_valid(c) and c.colonist_id == colonist_id:
			return c
	return null


func _item_name(item_id: String) -> String:
	var def := ItemDB.get_def(item_id)
	if def != null and def.resource_name != "":
		return def.resource_name
	return item_id
