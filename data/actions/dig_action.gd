class_name DigAction
extends GameAction
## The mining dig (docs/TODO.md Phase 5): a timed action that carves a box or
## sphere out of the natural (smooth) terrain on completion, then grants the material's
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
## Material stats are per-position (terrain_mining/plan.md): the def resolves
## through the grid's sidecar/strata chain — dig a hilltop, get dirt; dig at
## depth 30, get rock or ore. hp scales the duration (work_time * hp / 100;
## the future tool-damage model consumes the same pool per swing).
##
## No partial progress: smooth terrain has no node to bank work on, so a
## cancelled dig simply aborts — the carve happens only on completion
## (the documented v1 semantics, D1 asymmetry note).

const _progress_scene: PackedScene = preload("res://ui/action_progress/action_progress.tscn")

## hp that keeps today's baseline dig duration (work_time * 1.0) — the def's
## hp is expressed against this scale (old hardness 3 == hp 300).
const HP_SCALE := 100.0


## Start a dig by `actor` (the Player today) at world-space `center` (the
## already-resolved dig center the ghost showed) on `grid`, using `tool`'s
## work time / shape. Material stats come from the grid AT THE DIG POSITION
## — F12 sidecar for authored ground, strata depth rules for natural
## ground, default_material when neither answers.
func begin(actor: Node, grid: SmoothGrid, center: Vector3, tool: DigToolParams) -> void:
	if actor == null or grid == null or tool == null:
		return
	var material := _resolve_material(grid, center, tool)
	var duration: float = tool.work_time * (float(material.hp) / HP_SCALE if material != null else 1.0)
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
	# Resolve the def BEFORE carving — after the removal the center is
	# air and the sidecar answer would be "".
	var material := _resolve_material(grid, center, tool)
	if tool.shape == DigToolParams.Shape.BOX:
		var half_box := tool.box_size * 0.5
		grid.carve_box(center - half_box, center + half_box)
	else:
		grid.carve(center, tool.carve_radius)
	if material != null:
		var tree := actor.get_tree() if actor != null else null
		var parent: Variant = tree if tree != null else actor
		for entry: ItemAmount in material.yields:
			if entry != null and entry.item_def != null and entry.count > 0:
				WorldItem.spawn_at(parent, entry.item_def.id, entry.count, center)
	var tree := actor.get_tree() if actor != null else null
	if tree != null:
		WorldItem.wake_items_near(tree, center, 3.0)
	var skill_set := _skills_of(actor)
	if skill_set != null:
		skill_set.record_use_for_labor("mining")


## The def the dig answers for, per shape: a BOX scans the samples its carve
## clears (the struck cell's min sample can be air on incline edges — and
## round(4.5)=5 would even sample the wrong position entirely), a SPHERE
## samples its center as before.
func _resolve_material(grid: SmoothGrid, center: Vector3, tool: DigToolParams) -> TerrainMaterialDef:
	if tool.shape == DigToolParams.Shape.BOX:
		var half_box := tool.box_size * 0.5
		return grid.get_first_material_def_in_box(center - half_box, center + half_box)
	return grid.get_material_def_at(Vector3i(center.round()))


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
