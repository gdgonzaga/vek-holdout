class_name DismissColonistAction
extends GameAction
## Dismisses a deployed colonist, releasing them back to normal colony routines.

func execute(_actor: Node, target: Node) -> void:
	if target == null or Colony == null:
		return
	var cid: String = str(target.get("colonist_id"))
	if cid != "":
		Colony.cancel_deployments([cid])
