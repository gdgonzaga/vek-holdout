class_name DismissSquadAction
extends GameAction
## Dismisses a deployed squad, releasing all squad members back to normal routines.

func execute(_actor: Node, target: Node) -> void:
	if target == null or Colony == null:
		return
	var squad_id: String = str(target.get("squad_id"))
	if squad_id != "":
		Colony.cancel_squad_deployment(squad_id)
