class_name DigAction
extends GameAction
## The mining dig (docs/TODO.md Phase 5): a timed action that carves a sphere
## out of the natural (smooth) terrain on completion, then grants the material's
## yields to the digger — the harvesting pattern (HarvestAction) applied to
## terrain instead of a furniture node.
##
## Trigger-agnostic on purpose: the entry point is begin(actor, grid, center,
## tool), NOT GameAction.execute's (actor, target) node shape, because a dig
## target is a world position + terrain, not a scene node. The build-menu Dig
## tool calls this today; an equipped-tool LMB and colonist mining jobs later
## call the identical method (owner direction: mining converges on the harvest
## interaction model).
##
## No partial progress: smooth terrain has no HP model and no node to bank work
## on, so a cancelled dig simply aborts — the carve happens only on completion
## (the documented v1 semantics, D1 asymmetry note).

const _progress_scene: PackedScene = preload("res://ui/action_progress/action_progress.tscn")


## Start a dig by `actor` (the Player today) at world-space `center` (the
## already-nudged sphere center the ghost showed) on `grid`, using `tool`'s
## work time / carve radius. Material stats come from the grid's default
## material — F8: there is no per-position material channel, so every dig
## reads the map's one material identity.
func begin(actor: Node, grid: SmoothGrid, center: Vector3, tool: DigToolParams) -> void:
	if actor == null or grid == null or tool == null:
		return
	var material := grid.default_material
	var duration: float = tool.work_time * (float(material.hardness) if material != null else 1.0)
	var player := actor as Player
	if player != null and player.skill_set != null:
		duration = duration / player.skill_set.get_multiplier("mining")
	if duration <= 0.0:
		_apply(actor, grid, center, tool)
		return
	actor.set_busy(true)
	var ui: Control = _progress_scene.instantiate()
	var label_text := "Digging"
	if material != null and material.display_name != "":
		label_text = "Digging %s" % material.display_name
	ui.completed.connect(func() -> void:
		actor.set_busy(false)
		_apply(actor, grid, center, tool))
	# Cancelled digs bank nothing: no Harvestable-style node holds the elapsed
	# work, and smooth terrain has no partial-HP state to resume from.
	ui.cancelled.connect(func(_elapsed: float) -> void:
		actor.set_busy(false))
	_mount(ui, actor)
	ui.setup(label_text, duration)


## The completion path, kept separate so tests can run it without the gauge
## (the HarvestAction._apply testing seam).
func _apply(actor: Node, grid: SmoothGrid, center: Vector3, tool: DigToolParams) -> void:
	grid.carve(center, tool.carve_radius)
	var material := grid.default_material
	if material != null:
		var pocket := _pocket_of(actor)
		if pocket != null:
			for entry: ItemAmount in material.yields:
				pocket.add(entry.item_def.id, entry.count)
	var skill_set := _skills_of(actor)
	if skill_set != null:
		skill_set.record_use_for_labor("mining")


func _pocket_of(actor: Node) -> Inventory:
	var colonist := actor as Colonist
	if colonist != null and colonist.inventory != null:
		return colonist.inventory
	var player := actor as Player
	if player != null and player.inventory != null:
		return player.inventory
	return null


func _skills_of(actor: Node) -> SkillSet:
	var colonist := actor as Colonist
	if colonist != null:
		return colonist.skill_set
	var player := actor as Player
	if player != null:
		return player.skill_set
	return null


func _mount(ui: Control, actor: Node) -> void:
	var tree := actor.get_tree()
	var layer := tree.get_first_node_in_group("hud_layer") as CanvasLayer
	if layer == null:
		layer = tree.get_first_node_in_group("ui_layer") as CanvasLayer
	if layer == null:
		push_warning("DigAction: no CanvasLayer found, mounting on actor")
		actor.add_child(ui)
	else:
		layer.add_child(ui)
