class_name DeployColonistAction
extends GameAction
## Enters tactical deployment placement mode for a single colonist.

func execute(_actor: Node, target: Node) -> void:
	if target == null:
		return
	var cid: String = str(target.get("colonist_id"))
	if cid == "":
		return
	EventBus.command_mode_requested.emit([cid])
