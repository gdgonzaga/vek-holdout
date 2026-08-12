class_name BuildAction
extends GameAction
## Materializes the targeted blueprint into the world (GDD §7.4), after a
## build-time delay driven by the target BuildableDef.build_time. Bound to a
## Blueprint node via its "Build" ActionOption.
##
## BuildAction is a Resource — no _ready/_process — so the per-frame progress
## tick lives on the ActionProgress UI node it spawns. The gauge itself is
## generic (label + duration + signals); this action wires the Blueprint/Player
## specifics (busy lock, completion, and persisting interrupted work) onto those
## signals. For a build_time <= 0 (or an unknown def) it falls back to instant
## completion via Blueprint.complete — the same path a future colonist work-tick
## / JobBoard will drive.

const _progress_scene: PackedScene = preload("res://ui/action_progress/action_progress.tscn")


func execute(actor: Node, target: Node) -> void:
	var bp := target as Blueprint
	if bp == null:
		return
	var def := BuildLibrary.get_def(bp.target_def_id)
	var duration: float = def.build_time if def != null else 0.0
	if duration <= 0.0:
		bp.complete(actor) # instant path
		return
	_start_timed_build(actor, bp, duration)


## Lock the player, show the gauge, and react to its signals: complete forwards
## to Blueprint.complete; cancel persists the elapsed work so a retry resumes.
func _start_timed_build(actor: Node, bp: Blueprint, duration: float) -> void:
	actor.set_busy(true)
	var ui: Control = _progress_scene.instantiate()
	ui.completed.connect(func() -> void:
		actor.set_busy(false)
		bp.work_done = 0.0
		bp.complete(actor))
	ui.cancelled.connect(func(elapsed: float) -> void:
		actor.set_busy(false)
		bp.work_done = elapsed)
	_mount(ui, bp)
	ui.setup(label if label != "" else "Build", duration, bp.work_done)


## Add the gauge to a UI CanvasLayer (prefer the HUD overlay the rest of the
## game mounts transient panels on), mirroring InteractionComponent's lookup.
func _mount(ui: Control, bp: Blueprint) -> void:
	var tree := bp.get_tree()
	var layer := tree.get_first_node_in_group("hud_layer") as CanvasLayer
	if layer == null:
		layer = tree.get_first_node_in_group("ui_layer") as CanvasLayer
	if layer == null:
		push_warning("BuildAction: no CanvasLayer found, mounting on blueprint")
		bp.add_child(ui)
	else:
		layer.add_child(ui)
