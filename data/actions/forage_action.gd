class_name ForageAction
extends GameAction
## Player manual action to forage mature fruit/produce from WildFlora.
## Runs a short ActionProgress HUD gauge, then triggers wild_flora.forage(player).

const _progress_scene: PackedScene = preload("res://ui/action_progress/action_progress.tscn")


func execute(actor: Node, target: Node) -> void:
	var flora := _resolve_flora(target)
	if flora == null or not flora.can_forage():
		return
	
	var player := actor as Player
	var harvesting_mult: float = 1.0
	if player != null and player.skill_set != null:
		harvesting_mult = player.skill_set.get_multiplier("harvesting")
	
	var duration: float = maxf(0.5, 1.2 / maxf(0.1, harvesting_mult))
	_start_forage_progress(actor, flora, duration)


# =============================================================================
# Auxiliary Functions (Step-down narrative order)
# =============================================================================

func _start_forage_progress(actor: Node, flora: WildFlora, duration: float) -> void:
	## Auxiliary: Mounts ActionProgress radial gauge and connects completion callbacks.
	var player := actor as Player
	if player != null:
		player.set_busy(true)
	
	var ui: Control = _progress_scene.instantiate()
	var label_text: String = "Foraging %s" % flora.label
	
	ui.completed.connect(func() -> void:
		if player != null:
			player.set_busy(false)
		if is_instance_valid(flora):
			var harvested := flora.forage(actor)
			if harvested and player != null and player.skill_set != null:
				player.skill_set.record_use_for_labor("harvesting")
	)
	
	ui.cancelled.connect(func(_elapsed: float) -> void:
		if player != null:
			player.set_busy(false)
	)
	
	_mount_ui(ui, flora)
	ui.setup(label_text, duration, 0.0)


func _resolve_flora(target: Node) -> WildFlora:
	## Auxiliary: Resolves target or target parent to WildFlora instance.
	if target == null or not is_instance_valid(target):
		return null
	if target is WildFlora:
		return target as WildFlora
	return target.get_parent() as WildFlora


func _mount_ui(ui: Control, flora: WildFlora) -> void:
	## Auxiliary: Mounts UI gauge onto active hud_layer.
	var tree := flora.get_tree()
	if tree == null:
		return
	var layer := tree.get_first_node_in_group("hud_layer") as CanvasLayer
	if layer == null:
		layer = tree.get_first_node_in_group("ui_layer") as CanvasLayer
	if layer != null:
		layer.add_child(ui)
	else:
		flora.add_child(ui)
