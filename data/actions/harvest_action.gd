class_name HarvestAction
extends GameAction
## The player directly harvests a furniture node (e.g. chopping a tree) with LMB.
## Runs the ActionProgress HUD gauge, then completes the Harvestable.

const _progress_scene: PackedScene = preload("res://ui/action_progress/action_progress.tscn")


func execute(actor: Node, target: Node) -> void:
	var harvestable := _harvestable_of(target)
	if harvestable == null:
		return
	var params := harvestable.params()
	if params == null:
		return
	var player := actor as Player
	var duration: float = params.work_time
	if player != null and player.skill_set != null:
		duration = params.work_time / player.skill_set.get_multiplier("harvesting")
	var remaining: float = maxf(0.0, duration - harvestable.work_done())
	if remaining <= 0.0:
		_apply(actor, harvestable)
		return
	_start_timed_harvest(actor, harvestable, duration, remaining)


func _start_timed_harvest(actor: Node, harvestable: Harvestable, total_duration: float, _remaining: float) -> void:
	actor.set_busy(true)
	var ui: Control = _progress_scene.instantiate()
	var furniture := harvestable.get_parent() as Furniture
	var label_text: String = "Harvesting %s" % (furniture.label if furniture != null else "Resource")
	ui.completed.connect(func() -> void:
		actor.set_busy(false)
		if not is_instance_valid(harvestable):
			return
		_apply(actor, harvestable))
	ui.cancelled.connect(func(elapsed: float) -> void:
		actor.set_busy(false)
		if is_instance_valid(harvestable):
			harvestable.set_work_done(elapsed))
	_mount(ui, harvestable)
	ui.setup(label_text, total_duration, harvestable.work_done())


func _apply(actor: Node, harvestable: Harvestable) -> void:
	var completed := harvestable.complete(actor)
	if completed:
		var player := actor as Player
		if player != null and player.skill_set != null:
			player.skill_set.record_use_for_labor("harvesting")


func _harvestable_of(target: Node) -> Harvestable:
	if target == null or not is_instance_valid(target):
		return null
	var harvestable := target as Harvestable
	if harvestable != null:
		return harvestable
	return target.get_node_or_null("Harvestable") as Harvestable


func _mount(ui: Control, harvestable: Harvestable) -> void:
	var tree := harvestable.get_tree()
	var layer := tree.get_first_node_in_group("hud_layer") as CanvasLayer
	if layer == null:
		layer = tree.get_first_node_in_group("ui_layer") as CanvasLayer
	if layer == null:
		push_warning("HarvestAction: no CanvasLayer found, mounting on harvestable")
		harvestable.add_child(ui)
	else:
		layer.add_child(ui)
