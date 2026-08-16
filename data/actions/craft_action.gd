class_name CraftAction
extends GameAction
## The player personally works a station's ready order (GDD §7.9 dual-mode
## crafting — the player-side twin of CraftingJobDef, the way BuildAction is
## the twin of ConstructionJobDef). Invoked from the craft panel's Craft now /
## Craft yourself buttons; no ActionOption wiring (the panel is the surface).
##
## Same shape as BuildAction: claim the station under "player" (arbitrates the
## colonist race in both directions), lock the player, run the ActionProgress
## gauge, produce on completion. Duration = recipe.base_time ÷ the player's
## crafting multiplier (SkillSet wired on the Player); Esc-cancel persists
## work_done on the order so a restart resumes. Recipe conditions are checked
## by the panel before offering the button — execute() itself only guards
## workability (ready + unclaimed), keeping the action usable from any
## future surface (an E-tap option, keybinds).

const CRAFTING_DEF: CraftingJobDef = preload("res://data/jobs/crafting.tres")
const _progress_scene: PackedScene = preload("res://ui/action_progress/action_progress.tscn")


func execute(actor: Node, target: Node) -> void:
	var station := _station_of(target)
	if station == null or not station.can_player_work():
		return
	var recipe := station.active_recipe()
	if recipe == null:
		return
	var player := actor as Player
	var duration := recipe.base_time
	if player != null and player.skill_set != null:
		duration = recipe.base_time / player.skill_set.get_multiplier(CRAFTING_DEF.labor_id)
	if duration <= 0.0:
		_apply(actor, station, recipe)  # instant path
		return
	_start_timed_craft(actor, station, recipe, duration)


## Claim the station, lock the player, run the gauge. Completion re-guards
## with can_player_work — the player's own claim doesn't block it (that's the
## state the gauge itself created), so this rejects only when the order was
## resolved or freed externally mid-gauge. Cancel releases the claim and
## persists the elapsed work for resume.
func _start_timed_craft(actor: Node, station: CraftingStation, recipe: RecipeDef, duration: float) -> void:
	if not station.claim(CraftingStation.PLAYER_CLAIM):
		return
	actor.set_busy(true)
	var ui: Control = _progress_scene.instantiate()
	ui.completed.connect(func() -> void:
		actor.set_busy(false)
		if not is_instance_valid(station):
			return
		if station.can_player_work():
			_apply(actor, station, recipe)
		else:
			GameLog.craft("%s was resolved elsewhere" % recipe.label()))
	ui.cancelled.connect(func(elapsed: float) -> void:
		actor.set_busy(false)
		if is_instance_valid(station):
			station.release_claim(CraftingStation.PLAYER_CLAIM)
			station.set_work_done(elapsed))
	_mount(ui, station)
	ui.setup("Crafting %s" % recipe.label(), duration, station.work_done())


## Produce (pocket-first — the player crafting personally is how the player
## gets the item), resolve the order (complete_order requeues a colony maintain
## order still short of target), and grant the player crafting XP.
func _apply(actor: Node, station: CraftingStation, recipe: RecipeDef) -> void:
	var produced: bool = CRAFTING_DEF.produce(actor, station, recipe, true)
	station.complete_order()
	if produced:
		GameLog.craft("Crafted %s" % recipe.label())
		var player := actor as Player
		if player != null and player.skill_set != null:
			player.skill_set.record_use_for_labor(CRAFTING_DEF.labor_id)


## Accept the station node directly or the furniture (the panel passes the
## station; an E-tap surface would pass the furniture).
func _station_of(target: Node) -> CraftingStation:
	var station := target as CraftingStation
	if station != null and is_instance_valid(station):
		return station
	var furniture := target as Furniture
	if furniture != null:
		return furniture.get_node_or_null("CraftingStation") as CraftingStation
	return null


## Add the gauge to a UI CanvasLayer (prefer the HUD overlay), the BuildAction
## mounting pattern.
func _mount(ui: Control, station: CraftingStation) -> void:
	var tree := station.get_tree()
	var layer := tree.get_first_node_in_group("hud_layer") as CanvasLayer
	if layer == null:
		layer = tree.get_first_node_in_group("ui_layer") as CanvasLayer
	if layer == null:
		push_warning("CraftAction: no CanvasLayer found, mounting on station")
		station.add_child(ui)
	else:
		layer.add_child(ui)
