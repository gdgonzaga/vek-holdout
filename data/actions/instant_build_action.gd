class_name InstantBuildAction
extends GameAction
## Materializes the targeted blueprint into the world (GDD §7.4). Bound to a
## Blueprint node via its "Build" ActionOption. Forwards to Blueprint.complete —
## the shared completion entry point that a future colonist work-tick / JobBoard
## drives the same way.

func execute(actor: Node, target: Node) -> void:
	var bp := target as Blueprint
	if bp == null:
		return
	bp.complete(actor)
