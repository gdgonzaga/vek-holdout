@tool
class_name BTActionEatFood
extends BTAction
## AI Task: Consumes 1 food item from colonist carry inventory, plays the eating animation,
## replenishes hunger on HungerComponent/ColonistNeeds, and heals HP if specified by FoodParams.
## Resilient against interruptions (preserves unconsumed food if aborted early).

@export var food_item_var: StringName = &"food_item_id"
@export var goal_var: StringName = &"current_goal"
@export var default_eat_duration: float = 2.0
@export var default_animation: StringName = &"eat"
@export var default_nutrition: float = 0.4

var _elapsed: float = 0.0
var _active_duration: float = 2.0
var _active_item_id: String = ""
var _food_params: FoodParams = null
var _anim_controller: Node = null


# =================
# Primary Functions
# =================

func _generate_name() -> String:
	return "Eat Food  item: %s, goal: %s" % [
		LimboUtility.decorate_var(food_item_var),
		LimboUtility.decorate_var(goal_var)
	]


func _enter() -> void:
	_elapsed = 0.0
	_active_duration = default_eat_duration
	_food_params = null
	_active_item_id = ""

	# 1. Food Parameter Resolution: Inspect carried inventory to bind active food item and duration.
	_resolve_active_food_item()

	# 2. Animation Binding: Start eating animation override.
	_resolve_anim_controller()
	var anim_name := default_animation
	if _food_params != null and _food_params.eating_animation != &"":
		anim_name = _food_params.eating_animation
	if _anim_controller != null and _anim_controller.has_method("play_animation_override"):
		_anim_controller.play_animation_override(anim_name)


func _tick(delta: float) -> Status:
	if _active_item_id == "":
		return FAILURE

	_elapsed += delta
	if _elapsed < _active_duration:
		return RUNNING

	# 1. Food Consumption: Deduct 1 unit from inventory and apply physiological restoration.
	var consumed: bool = _consume_food_and_replenish()
	if not consumed:
		return FAILURE

	# 2. Goal Clearance: Clear eating goal so ColonistBrain re-evaluates next desires.
	_clear_blackboard_goal()

	return SUCCESS


func _exit() -> void:
	# 1. Clean Animation Exit: Clear any active animation override on task exit or abort.
	if _anim_controller != null and _anim_controller.has_method("clear_override"):
		_anim_controller.clear_override()


# ===================
# Auxiliary Functions
# ===================

func _resolve_active_food_item() -> void:
	## Auxiliary: Resolves item ID and FoodParams from blackboard or carried inventory.
	var item_id := ""
	if blackboard != null and blackboard.has_var(food_item_var):
		item_id = str(blackboard.get_var(food_item_var))

	var inv := _get_agent_inventory()
	if inv != null and inv.items is Dictionary:
		if item_id == "" or inv.get_item_count(item_id) <= 0:
			for key in inv.items.keys():
				var cid := str(key)
				if inv.get_item_count(cid) > 0 and _is_edible(cid):
					item_id = cid
					break

	if item_id != "":
		_active_item_id = item_id
		if ItemDB != null:
			var def: ItemDef = ItemDB.get_def(item_id)
			if def != null and def.food != null:
				_food_params = def.food
				_active_duration = def.food.eat_duration


func _consume_food_and_replenish() -> bool:
	## Auxiliary: Removes 1 item from inventory and updates hunger and HP.
	var inv := _get_agent_inventory()
	if inv == null or inv.get_item_count(_active_item_id) <= 0:
		return false

	inv.remove(_active_item_id, 1)

	var nutrition: float = default_nutrition
	var health_heal: int = 0
	if _food_params != null:
		nutrition = _food_params.nutrition_value
		health_heal = _food_params.health_restore

	# 1. Hunger Restoration: Restore satiety on HungerComponent or ColonistNeeds.
	_apply_hunger_restoration(nutrition)

	# 2. HP Healing: Heal entity if food provides health restoration.
	if health_heal > 0 and agent.has_method("heal"):
		agent.heal(health_heal)

	return true


func _apply_hunger_restoration(amount: float) -> void:
	## Auxiliary: Updates hunger on HungerComponent and ColonistNeeds.
	var hunger_comp: HungerComponent = null
	if agent != null:
		hunger_comp = agent.get_node_or_null("HungerComponent") as HungerComponent
		if hunger_comp == null and "hunger_component" in agent:
			hunger_comp = agent.hunger_component

	if hunger_comp != null:
		hunger_comp.restore_hunger(amount)
		return

	var needs: ColonistNeeds = null
	if agent != null:
		needs = agent.get_node_or_null("ColonistNeeds") as ColonistNeeds
		if needs == null and "needs" in agent:
			needs = agent.needs

	if needs != null:
		var current_val := needs.get_need(&"hunger")
		needs.set_need(&"hunger", clampf(current_val + amount, 0.0, 1.0))


func _clear_blackboard_goal() -> void:
	## Auxiliary: Clears active goal and food targets from blackboard.
	if blackboard != null:
		if blackboard.has_var(goal_var):
			blackboard.set_var(goal_var, &"none")
		if blackboard.has_var(food_item_var):
			blackboard.erase_var(food_item_var)
		if blackboard.has_var(&"food_source_node"):
			blackboard.erase_var(&"food_source_node")
		if blackboard.has_var(&"food_source_type"):
			blackboard.erase_var(&"food_source_type")


func _get_agent_inventory() -> CharacterInventory:
	## Auxiliary: Extracts CharacterInventory from agent.
	return AIUtils.resolve_character_inventory(agent)


func _resolve_anim_controller() -> void:
	## Auxiliary: Locates ColonistAnimationController on agent.
	_anim_controller = AIUtils.resolve_anim_controller(_anim_controller, agent)


func _is_edible(item_id: String) -> bool:
	## Auxiliary: Returns true if item has FoodParams or food tag.
	return AIUtils.is_edible_item(item_id)
